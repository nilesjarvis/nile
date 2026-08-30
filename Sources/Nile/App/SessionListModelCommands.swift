import Foundation

/// Model-facing slash-command completion, execution, and recovery.
///
/// The command runtime retains repository access, debounce/execution tasks,
/// policy decisions, and cancellation. This extension integrates those
/// outcomes with the displayed composer and transcript. Authoritative Hermes
/// events still enter through the core model's single ordered boundary.
@MainActor
extension SessionListModel {
    func applySlashCompletion(_ choice: String) {
        let offset = min(max(slashReplaceFrom, 0), composer.count)
        let prefix = composer.prefix(offset)
        updateComposer(
            "/" + (String(prefix) + choice)
                .drop(while: { $0 == "/" })
        )
    }

    func pickCatalogCommand(_ command: String) {
        updateComposer("/" + command.drop(while: { $0 == "/" }))
    }

    func refreshSlashCompletions(_ value: String) {
        runtimes.commandRuntime.refreshCompletions(
            query: value,
            owner: SessionCommandRuntime.CompletionOwner(
                gatewayGeneration: gatewayGeneration,
                gatewayID: currentGatewayID
            )
        )
    }

    func runSlashCommand(
        _ input: String,
        liveSession: LiveSession,
        owner: ComposerDraftOwner
    ) -> Bool {
        let decision = runtimes.commandRuntime.decision(for: input)
        guard decision.surface != .blocked else {
            operationError = decision.message
            return false
        }
        guard !isSending else {
            operationError =
                "Wait for the current turn to finish before running a slash command. Your draft was kept."
            return false
        }

        switch decision.surface {
        case .nativeHelp:
            updateComposer("/")
            return true
        case .nativeModel:
            return performNativeSlashAction(
                input: input,
                owner: owner
            ) { model in
                model.setModelPickerVisible(true)
            }
        case .nativeGoal:
            guard goalAvailability == .available else {
                operationError =
                    "Standing goals are unavailable on this Hermes profile. Your draft was kept."
                return false
            }
            return performNativeSlashAction(
                input: input,
                owner: owner
            ) { model in
                model.setGoalSheetVisible(true)
            }
        case .nativeReasoning:
            guard let effort = decision.argument else {
                operationError = "No reasoning effort level was provided."
                return false
            }
            return performNativeSlashAction(
                input: input,
                owner: owner
            ) { model in
                model.setReasoningEffort(effort)
            }
        case .nativeNew:
            let claim = runtimes.draftLifecycleRuntime.captureClaim(
                owner: owner,
                fallbackText: input
            )
            let token = runtimes.composerRuntime.capture(owner)
            claimSlashDraft(owner: owner)
            let operationID = UUID()
            outboundTasks[operationID] = Task { [weak self] in
                guard let self else {
                    return
                }
                guard await self.runtimes.draftLifecycleRuntime.flushClaim(
                    owner: owner,
                    claim: claim
                ) else {
                    self.restoreCommandDraft(
                        token: token,
                        input: input,
                        entryID: nil,
                        notice: Self.draftFlushFailureMessage,
                        uncertain: false
                    )
                    self.outboundTasks.removeValue(forKey: operationID)
                    return
                }
                await self.applyDraftClaimRetirement(
                    owner: owner,
                    claim: claim
                )
                await self.createSession()
                self.outboundTasks.removeValue(forKey: operationID)
            }
            return true
        case .slashExec, .commandDispatch:
            break
        case .blocked:
            return false
        }

        let executionOwner = SessionCommandRuntime.ExecutionOwner(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        guard !runtimes.commandRuntime.isExecuting(owner: executionOwner) else {
            operationError =
                "Wait for the previous slash command to finish. Your draft was kept."
            return false
        }
        let claim = runtimes.draftLifecycleRuntime.captureClaim(
            owner: owner,
            fallbackText: input
        )
        let token = runtimes.composerRuntime.capture(owner)
        let entryID = "command-\(UUID().uuidString)"
        let settlement = SlashCommandSettlement(
            token: token,
            input: input,
            owner: owner,
            liveSessionID: liveSession.liveID,
            entryID: entryID,
            claim: claim
        )
        claimSlashDraft(owner: owner)
        transcriptEntries.append(
            .command(
                TranscriptCommand(
                    id: entryID,
                    command: input
                )
            )
        )
        beginBackgroundTurn(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: liveSession.liveID
        )

        guard runtimes.commandRuntime.hasRepository else {
            updateCommandEntry(
                id: entryID,
                output: "(no output)",
                status: .done
            )
            stopBackgroundTurn(
                gatewayID: owner.gatewayID,
                liveSessionID: liveSession.liveID
            )
            return true
        }
        let didStart = runtimes.commandRuntime.startExecution(
            owner: executionOwner,
            liveSessionID: liveSession.liveID,
            input: input,
            prepare: { [weak self] in
                guard let self else {
                    return false
                }
                return await self.runtimes.draftLifecycleRuntime.flushClaim(
                    owner: owner,
                    claim: claim
                )
            },
            onOutcome: { [weak self] outcome in
                guard let self else {
                    return
                }
                await self.settleSlashCommandOutcome(
                    outcome,
                    settlement: settlement
                )
            }
        )
        if !didStart {
            restoreCommandDraft(
                token: token,
                input: input,
                entryID: entryID,
                notice:
                    "Wait for the previous slash command to finish. Your draft was kept.",
                uncertain: false
            )
            stopBackgroundTurn(
                gatewayID: owner.gatewayID,
                liveSessionID: liveSession.liveID
            )
        }
        return true
    }

    private func performNativeSlashAction(
        input: String,
        owner: ComposerDraftOwner,
        action: @escaping @MainActor (SessionListModel) -> Void
    ) -> Bool {
        let claim = runtimes.draftLifecycleRuntime.captureClaim(
            owner: owner,
            fallbackText: input
        )
        let token = runtimes.composerRuntime.capture(owner)
        claimSlashDraft(owner: owner)
        action(self)
        let operationID = UUID()
        outboundTasks[operationID] = Task { [weak self] in
            guard let self else {
                return
            }
            if await self.runtimes.draftLifecycleRuntime.flushClaim(
                owner: owner,
                claim: claim
            ) {
                await self.applyDraftClaimRetirement(
                    owner: owner,
                    claim: claim
                )
            } else {
                self.restoreCommandDraft(
                    token: token,
                    input: input,
                    entryID: nil,
                    notice: Self.draftFlushFailureMessage,
                    uncertain: false
                )
            }
            self.outboundTasks.removeValue(forKey: operationID)
        }
        return true
    }

    private func claimSlashDraft(owner: ComposerDraftOwner) {
        runtimes.commandRuntime.resetCompletions()
        runtimes.modelControlRuntime.resetSessionControls()
        composer = ""
        runtimes.composerRuntime.claim(owner: owner)
        operationError = nil
    }
}
