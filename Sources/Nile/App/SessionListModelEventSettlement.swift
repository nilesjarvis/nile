import Foundation

/// Ordered cross-feature settlement stages invoked by the sole event router.
@MainActor
extension SessionListModel {
    func applyDelegationLifecycle(_ event: HermesStreamEvent) {
        switch event {
        case let .subagentUpdate(sessionID, kind, data):
            handleDelegationEvent(
                sessionID: sessionID,
                kind: kind,
                data: data
            )
        case let .assistantCompleted(sessionID, _, _):
            markDelegationParentCompleted(liveSessionID: sessionID)
        default:
            break
        }
    }

    func settleTurnLifecycle(_ event: HermesStreamEvent) {
        switch event {
        case let .assistantCompleted(sessionID, _, _):
            runtimes.lifecycleRuntime.completeTurn(
                gatewayID: currentGatewayID,
                liveSessionID: sessionID
            )
        case let .error(sessionID, _):
            stopBackgroundTurn(
                gatewayID: currentGatewayID,
                liveSessionID: sessionID
            )
        default:
            break
        }
    }

    func consumeBlockingPromptEvent(_ event: HermesStreamEvent) -> Bool {
        let fallbackStoredSessionID = event.sessionID == liveSession?.liveID
            ? selectedSessionID
            : nil
        switch runtimes.blockingPromptRuntime.handleEvent(
            event,
            gatewayID: currentGatewayID,
            fallbackStoredSessionID: fallbackStoredSessionID
        ) {
        case .notHandled:
            return false
        case .consumed:
            return true
        case .added:
            cancelVoiceForOwnershipChange()
            runtimes.talkRuntime.pauseForBlockingPrompt()
            syncBlockingPromptUI()
            return true
        }
    }

    func settleTerminalResources(_ event: HermesStreamEvent) {
        switch event {
        case let .assistantCompleted(sessionID, _, _):
            runtimes.talkRuntime.noteTerminalBeforeAdmission(
                liveSessionID: sessionID
            )
            runtimes.attachmentRuntime.onAssistantCompleted(
                liveSessionID: sessionID
            )
            if let gatewayID = currentGatewayID {
                runtimes.blockingPromptRuntime.finalizeRuntime(
                    gatewayID: gatewayID,
                    liveSessionID: sessionID,
                    message:
                        "The run finished before this request was answered."
                )
                syncBlockingPromptUI()
            }
        case let .error(sessionID, message):
            runtimes.talkRuntime.noteTerminalBeforeAdmission(
                liveSessionID: sessionID
            )
            if let owner = currentDraftOwner() {
                let rejected = runtimes.attachmentRuntime.onError(
                    owner: owner,
                    liveSessionID: sessionID,
                    message: message
                )
                settleRejectedAttachmentBatches(
                    rejected,
                    message: message
                )
            }
            if let gatewayID = currentGatewayID {
                runtimes.blockingPromptRuntime.finalizeRuntime(
                    gatewayID: gatewayID,
                    liveSessionID: sessionID,
                    message:
                        "The run ended before this request was answered."
                )
                syncBlockingPromptUI()
            }
        default:
            break
        }
    }

    private func settleRejectedAttachmentBatches(
        _ batches: [OutboundAttachmentBatch],
        message: String
    ) {
        for batch in batches {
            guard let marker = runtimes.attachmentPersistenceRuntime.marker(
                id: batch.id
            ) else {
                continue
            }
            let token = runtimes.composerRuntime.capture(batch.owner)
            Task { [weak self] in
                await self?.settleFailedAttachmentBatch(
                    batch,
                    marker: marker,
                    token: token,
                    message: message,
                    uncertain: false
                )
            }
        }
    }
}
