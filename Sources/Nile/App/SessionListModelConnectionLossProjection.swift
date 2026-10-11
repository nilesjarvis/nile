import Foundation

/// Applies the gateway-wide teardown transaction for an ordered connection loss.
@MainActor
extension SessionListModel {
    func applyVisibleConnectionLoss(
        message: String,
        retryable: Bool,
        notifyGateway: Bool = true
    ) {
        cacheVisibleLiveTimeline()
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        endTalkMode()
        quarantineTrackedAttachmentBatches()
        runtimes.turnRuntime.invalidateStop()
        if retryable {
            _ = runtimes.blockingPromptRuntime.markSubmittingUncertain(
                gatewayID: currentGatewayID
            )
        } else {
            runtimes.lifecycleRuntime.stopAllTurns()
            if let gatewayID = currentGatewayID {
                runtimes.blockingPromptRuntime.finalizeGateway(
                    gatewayID: gatewayID,
                    message: "The connection ended before this request was resolved."
                )
            }
        }
        syncBlockingPromptUI()
        gatewayGeneration += 1
        displayGeneration += 1
        if let gatewayID = currentGatewayID {
            runtimes.navigationRuntime.synchronizeGateway(
                owner: SessionNavigationRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
            runtimes.modelControlRuntime.synchronizeGateway(
                owner: SessionModelControlRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
        }
        runtimes.claimRuntime.cancelStatus()
        runtimes.commandRuntime.resetCompletions()
        runtimes.modelControlRuntime.resetSessionControls()
        runtimes.goalRuntime.reset()
        resetSessionUsage()
        resetGatewayStats()
        clearDelegationState()
        liveSession = nil
        isSending = false
        isStopping = false
        runtimes.mediaRuntime.cancelOpening()
        turnStartedAt = nil
        attachedToExistingTurn = false
        activeTodos = nil
        liveTranscript.beginTurn()
        isOpeningSession = false
        runtimes.claimRuntime.reset()
        runtimes.renameRuntime.reset()
        operationError = nil
        state = .failed(message)
        connectionPhase = retryable ? .reconnecting : .failed
        if notifyGateway {
            runtimes.lifecycleRuntime.notifyConnectionLoss(
                GatewayConnectionLossNotice(
                    message: message, retryable: retryable
                )
            )
        }
    }
}
