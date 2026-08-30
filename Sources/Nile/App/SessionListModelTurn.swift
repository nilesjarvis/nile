import Foundation

/// Displayed-session turn submission, steering, Stop, and settlement bridge.
///
/// SessionTurnRuntime retains transport tasks, delivery uncertainty, and Stop
/// fencing. This extension owns optimistic transcript, protected-draft
/// settlement, background-turn, Talk, and blocking-prompt presentation while
/// the core model remains the sole ordered Hermes event boundary.
@MainActor
extension SessionListModel {
    func stopActiveRun() {
        guard showsComposer,
              !isOpeningSession,
              !isStopping,
              isSending || composerIsBlocked,
              let liveSession else {
            return
        }
        isStopping = true
        operationError = nil
        let liveSessionID = liveSession.liveID
        let started = runtimes.turnRuntime.stop(
            liveSessionID: liveSessionID
        ) { [weak self] outcome in
            self?.settleStop(outcome, liveSessionID: liveSessionID)
        }
        if !started {
            isStopping = false
        }
    }

    func submitPrompt(
        _ input: String,
        liveSessionID: String,
        token: SessionComposerRuntime.RecoveryToken,
        persistenceClaim: PersistedComposerDraft?
    ) -> Bool {
        let entryID = "user-\(UUID().uuidString)"
        liveTranscript.beginTurn()
        transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: entryID,
                    role: .user,
                    content: input
                )
            )
        )
        isSending = true
        turnStartedAt = Date()
        activeTodos = nil
        if let selectedSessionID {
            activeStatuses[selectedSessionID] = "working"
        }
        beginBackgroundTurn(
            gatewayID: token.owner.gatewayID,
            storedSessionID: token.owner.storedSessionID,
            liveSessionID: liveSessionID
        )

        _ = runtimes.turnRuntime.sendPrompt(
            liveSessionID: liveSessionID,
            text: input,
            prepare: { [weak self] in
                guard let self else {
                    return false
                }
                return await self.runtimes.draftLifecycleRuntime.flushClaim(
                    owner: token.owner,
                    claim: persistenceClaim
                )
            },
            onOutcome: { [weak self] outcome in
                guard let self else {
                    return
                }
                switch outcome {
                case .accepted:
                    await self.applyDraftClaimRetirement(
                        owner: token.owner,
                        claim: persistenceClaim
                    )
                case .preparationFailed:
                    self.settlePromptFailure(
                        token: token,
                        liveSessionID: liveSessionID,
                        entryID: entryID,
                        input: input,
                        message: Self.draftFlushFailureMessage,
                        uncertain: false
                    )
                case .cancelled:
                    self.settlePromptFailure(
                        token: token,
                        liveSessionID: liveSessionID,
                        entryID: entryID,
                        input: input,
                        message: "Send was interrupted before Nile received confirmation. Check the source conversation before retrying.",
                        uncertain: true
                    )
                case let .failed(message, uncertain):
                    self.settlePromptFailure(
                        token: token,
                        liveSessionID: liveSessionID,
                        entryID: entryID,
                        input: input,
                        message: message,
                        uncertain: uncertain
                    )
                }
            }
        )
        return true
    }

    func queueSteer(
        _ input: String,
        liveSessionID: String,
        token: SessionComposerRuntime.RecoveryToken,
        persistenceClaim: PersistedComposerDraft?
    ) -> Bool {
        let entryID = "steer-\(UUID().uuidString)"
        transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: entryID,
                    role: .user,
                    content: input,
                    pending: true
                )
            )
        )

        _ = runtimes.turnRuntime.sendSteer(
            liveSessionID: liveSessionID,
            text: input,
            prepare: { [weak self] in
                guard let self else {
                    return false
                }
                return await self.runtimes.draftLifecycleRuntime.flushClaim(
                    owner: token.owner,
                    claim: persistenceClaim
                )
            },
            onOutcome: { [weak self] outcome in
                guard let self else {
                    return
                }
                switch outcome {
                case .accepted:
                    await self.applyDraftClaimRetirement(
                        owner: token.owner,
                        claim: persistenceClaim
                    )
                case .rejected:
                    self.settleSteerFailure(
                        token: token,
                        entryID: entryID,
                        input: input,
                        notice:
                            "Steering was not queued. Your message was restored.",
                        uncertain: false
                    )
                case .preparationFailed:
                    self.settleSteerFailure(
                        token: token,
                        entryID: entryID,
                        input: input,
                        notice: Self.draftFlushFailureMessage,
                        uncertain: false
                    )
                case .cancelled:
                    self.settleSteerFailure(
                        token: token,
                        entryID: entryID,
                        input: input,
                        notice: Self.uncertainSteerRecoveryMessage,
                        uncertain: true
                    )
                case let .failed(message, uncertain):
                    self.settleSteerFailure(
                        token: token,
                        entryID: entryID,
                        input: input,
                        notice: uncertain
                            ? Self.uncertainSteerRecoveryMessage
                            : "Steering failed: \(message). Your message was restored.",
                        uncertain: uncertain
                    )
                }
            }
        )
        return true
    }

    func beginBackgroundTurn(
        gatewayID: String,
        storedSessionID: String?,
        liveSessionID: String
    ) {
        runtimes.lifecycleRuntime.startTurn(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    func stopBackgroundTurn(
        gatewayID: String?,
        liveSessionID: String
    ) {
        runtimes.lifecycleRuntime.stopTurn(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID
        )
    }

    private static let uncertainSteerRecoveryMessage =
        "Nile could not confirm whether steering was queued. Your message was restored; inspect the running turn before retrying to avoid a duplicate."
}
