import Foundation

/// Applies command-runtime outcomes to protected drafts and transcript rows.
/// Command admission and task startup remain in `SessionListModelCommands`.
@MainActor
extension SessionListModel {
    struct SlashCommandSettlement: Sendable {
        let token: SessionComposerRuntime.RecoveryToken
        let input: String
        let owner: ComposerDraftOwner
        let liveSessionID: String
        let entryID: String
        let claim: PersistedComposerDraft?
    }

    func settleSlashCommandOutcome(
        _ outcome: SessionCommandRuntime.ExecutionOutcome,
        settlement: SlashCommandSettlement
    ) async {
        let token = settlement.token
        let input = settlement.input
        let owner = settlement.owner
        let liveSessionID = settlement.liveSessionID
        let entryID = settlement.entryID
        let claim = settlement.claim

        switch outcome {
        case .preparationFailed:
            restoreCommandDraft(
                token: token,
                input: input,
                entryID: entryID,
                notice: Self.draftFlushFailureMessage,
                uncertain: false
            )
            stopBackgroundTurn(
                gatewayID: owner.gatewayID,
                liveSessionID: liveSessionID
            )
        case let .completed(execution):
            switch execution {
            case let .output(output):
                stopBackgroundTurn(
                    gatewayID: owner.gatewayID,
                    liveSessionID: liveSessionID
                )
                await applyDraftClaimRetirement(
                    owner: owner,
                    claim: claim
                )
                deliverCommandOutput(
                    owner: owner,
                    liveSessionID: liveSessionID,
                    entryID: entryID,
                    output: output
                )
            case let .prefillComposer(message, notice):
                stopBackgroundTurn(
                    gatewayID: owner.gatewayID,
                    liveSessionID: liveSessionID
                )
                await applyDraftClaimRetirement(
                    owner: owner,
                    claim: claim
                )
                restoreCommandDraft(
                    token: token,
                    input: message,
                    entryID: entryID,
                    notice: [
                        notice,
                        "Hermes updated the conversation. The returned text is ready to edit.",
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                    uncertain: false,
                    commandStatus: .done
                )
            case .submitPrompt:
                stopBackgroundTurn(
                    gatewayID: owner.gatewayID,
                    liveSessionID: liveSessionID
                )
                restoreCommandDraft(
                    token: token,
                    input: input,
                    entryID: entryID,
                    notice:
                        "Hermes returned an agent-turn command that Nile could not start safely. The command was restored.",
                    uncertain: false
                )
            case .alias:
                restoreCommandDraft(
                    token: token,
                    input: input,
                    entryID: entryID,
                    notice:
                        "Hermes returned an unresolved command alias. The command was restored.",
                    uncertain: true
                )
            }
        case let .failed(message, uncertain):
            if !uncertain {
                stopBackgroundTurn(
                    gatewayID: owner.gatewayID,
                    liveSessionID: liveSessionID
                )
            }
            restoreCommandDraft(
                token: token,
                input: input,
                entryID: entryID,
                notice: uncertain
                    ? Self.uncertainCommandRecoveryMessage
                    : "The command wasn't completed. It was restored: \(message)",
                uncertain: uncertain
            )
        case .cancelled:
            restoreCommandDraft(
                token: token,
                input: input,
                entryID: entryID,
                notice: Self.uncertainCommandRecoveryMessage,
                uncertain: true
            )
        }
    }

    func restoreCommandDraft(
        token: SessionComposerRuntime.RecoveryToken,
        input: String,
        entryID: String?,
        notice: String,
        uncertain: Bool,
        commandStatus: TranscriptCommand.Status = .error
    ) {
        let resolution = runtimes.draftLifecycleRuntime.recover(
            token: token,
            failedInput: input,
            notice: notice,
            uncertain: uncertain,
            noticeChannel: .operation,
            isVisible: transcriptIsVisible(for: token.owner),
            onFailure: draftFailureHandler()
        )
        guard case let .visible(recovery) = resolution else {
            return
        }
        if let entryID {
            updateCommandEntry(
                id: entryID,
                output: recovery.notice,
                status: commandStatus
            )
        }
        if composerIsVisible(for: recovery.owner) {
            composer = recovery.restoredText
            operationError = recovery.notice
            refreshSlashCompletions(recovery.restoredText)
        }
    }

    func updateCommandEntry(
        id: String,
        output: String,
        status: TranscriptCommand.Status
    ) {
        transcriptEntries = transcriptEntries.map { entry in
            guard case var .command(command) = entry,
                  command.id == id else {
                return entry
            }
            command.output = output
            command.status = status
            return .command(command)
        }
    }

    private func deliverCommandOutput(
        owner: ComposerDraftOwner,
        liveSessionID: String,
        entryID: String,
        output: String
    ) {
        guard transcriptIsVisible(for: owner),
              liveSession?.liveID == liveSessionID,
              transcriptEntries.contains(where: { $0.id == entryID }) else {
            runtimes.composerRuntime.rememberOperationNotice(
                owner: owner,
                message: "Command completed:\n\(output)",
                uncertain: false,
                showBanner: false
            )
            return
        }
        updateCommandEntry(
            id: entryID,
            output: output,
            status: .done
        )
    }

    private static let uncertainCommandRecoveryMessage =
        "Nile could not confirm whether the command ran. It was restored; inspect the source conversation before retrying to avoid a duplicate."
}
