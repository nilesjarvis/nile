import Foundation

/// Applies the visible/global UI projection after ordered event settlement.
@MainActor
extension SessionListModel {
    func applyVisibleEvent(_ event: HermesStreamEvent) {
        switch event {
        case let .connectionLost(message, _, retryable):
            applyVisibleConnectionLoss(message: message, retryable: retryable)
        case let .messageStart(sessionID):
            if sessionID == liveSession?.liveID, let selectedSessionID {
                runtimes.speechRuntime.stop()
                runtimes.talkRuntime.handleMessageStart(liveSessionID: sessionID)
                if let owner = currentDraftOwner() {
                    let accepted = runtimes.attachmentRuntime.onMessageStart(
                        owner: owner,
                        liveSessionID: sessionID
                    )
                    settleAcceptedAttachmentBatches(accepted)
                }
                runtimes.navigationRuntime.cancelAttachedTurnRefresh()
                activeStatuses[selectedSessionID] = "working"
                liveTranscript.beginTurn()
                isSending = true
                isStopping = false
                runtimes.goalRuntime.markMessageStarted(owner: captureGoalOwner())
                if turnStartedAt == nil {
                    turnStartedAt = Date()
                }
                syncBlockingPromptUI()
            }
        case let .assistantDelta(sessionID, text):
            assertionFailure(
                "Assistant deltas must use the cadence-limited fast path: \(sessionID), \(text.count) characters"
            )
        case let .assistantInterim(sessionID, text):
            if sessionID == liveSession?.liveID {
                transcriptEntries = liveTranscript.finalizeInterimAssistant(
                    text,
                    in: transcriptEntries
                )
                isSending = true
            }
        case let .assistantCompleted(sessionID, text, _):
            if sessionID == liveSession?.liveID, let selectedSessionID {
                applyVisibleAssistantCompletion(
                    sessionID: sessionID,
                    storedSessionID: selectedSessionID,
                    text: text
                )
            }
        case let .toolStart(
            sessionID,
            toolID,
            name,
            detail,
            context,
            _
        ):
            if sessionID == liveSession?.liveID {
                applyToolEvent(
                    LiveToolEvent(
                        toolID: toolID,
                        name: name,
                        status: "running",
                        content: detail ?? "",
                        label: context
                    )
                )
            }
        case let .toolComplete(
            sessionID,
            toolID,
            name,
            result,
            outcome,
            summary,
            durationSeconds,
            todos,
            inlineDiff
        ):
            if sessionID == liveSession?.liveID {
                let status = switch outcome {
                case .interrupted:
                    "stopped"
                case .failed:
                    "failed"
                case .succeeded, .unknown:
                    "done"
                }
                applyToolEvent(
                    LiveToolEvent(
                        toolID: toolID,
                        name: name,
                        status: status,
                        content: result ?? "",
                        outcome: outcome,
                        summary: summary,
                        durationSeconds: durationSeconds,
                        todos: todos,
                        inlineDiff: inlineDiff
                    )
                )
            }
        case let .statusUpdate(sessionID, text):
            if sessionID == liveSession?.liveID,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcriptEntries = liveTranscript.appendSystem(
                    text,
                    to: transcriptEntries
                )
            }
        case let .goalUpdate(sessionID, _, update):
            handleGoalUpdate(sessionID: sessionID, update: update)
        case let .error(sessionID, message):
            if sessionID == liveSession?.liveID, let selectedSessionID {
                applyVisibleError(
                    sessionID: sessionID,
                    storedSessionID: selectedSessionID,
                    message: message
                )
            }
        case let .sessionInfoUpdate(sessionID, info):
            if sessionID == liveSession?.liveID, let current = liveSession {
                liveSession = LiveSession(
                    liveID: current.liveID,
                    storedID: current.storedID,
                    info: info,
                    messages: current.messages,
                    running: current.running,
                    status: current.status,
                    inflight: current.inflight
                )
                refreshUsage()
            }
        default:
            break
        }
    }

    private func settleAcceptedAttachmentBatches(
        _ batches: [OutboundAttachmentBatch]
    ) {
        for batch in batches {
            guard let marker = runtimes.attachmentPersistenceRuntime.marker(
                id: batch.id
            ) else {
                continue
            }
            Task { [weak self] in
                await self?.settleAcceptedAttachmentBatch(
                    batch,
                    marker: marker
                )
            }
        }
    }

    private func applyVisibleAssistantCompletion(
        sessionID: String,
        storedSessionID: String,
        text: String
    ) {
        let completionWasStopping = isStopping
        let shouldSpeakReply = isSending
            && !isStopping
            && !runtimes.talkRuntime.isActive
        runtimes.turnRuntime.invalidateStop(liveSessionID: sessionID)
        let shouldRefreshAttachedTurn = attachedToExistingTurn
        attachedToExistingTurn = false
        transcriptEntries = liveTranscript.completeAssistant(
            text,
            in: transcriptEntries
        )
        activeStatuses.removeValue(forKey: storedSessionID)
        transcriptEntries.removeAll { entry in
            guard case let .message(message) = entry else {
                return false
            }
            return message.pending
        }
        isSending = false
        isStopping = false
        turnStartedAt = nil
        runtimes.goalRuntime.handleAssistantCompleted(
            owner: captureGoalOwner(),
            isSessionSending: { [weak self] in
                self?.isSending ?? false
            },
            onSynchronized: { [weak self] authoritative in
                self?.markStandingGoalPrompts(authoritative)
            }
        )
        if shouldRefreshAttachedTurn {
            refreshCompletedAttachedTurn(
                storedSessionID: storedSessionID,
                liveSessionID: sessionID
            )
        }
        refreshUsage()
        syncDelegationUI()
        syncBlockingPromptUI()
        hydrateVisibleMediaAttachments()
        let handledByTalk = runtimes.talkRuntime.handleAssistantCompleted(
            liveSessionID: sessionID,
            rawText: text,
            completionWasStopping: completionWasStopping,
            environmentProvider: talkEnvironmentProvider(),
            onError: talkErrorHandler()
        )
        if !handledByTalk, shouldSpeakReply {
            speakCompletedReply(text)
        }
    }

    private func applyVisibleError(
        sessionID: String,
        storedSessionID: String,
        message: String
    ) {
        let wasStopping = isStopping
        runtimes.turnRuntime.invalidateStop(liveSessionID: sessionID)
        transcriptEntries = liveTranscript.appendSystem(
            message,
            isError: true,
            to: transcriptEntries
        )
        activeStatuses.removeValue(forKey: storedSessionID)
        isSending = false
        isStopping = false
        turnStartedAt = nil
        syncBlockingPromptUI()
        runtimes.talkRuntime.handleError(
            liveSessionID: sessionID,
            message: message,
            wasStopping: wasStopping,
            environmentProvider: talkEnvironmentProvider()
        )
    }
}
