import Foundation

/// Prompt, steering, and Stop outcome projection for the displayed session.
///
/// Admission and transport-task creation remain in `SessionListModelTurn` and
/// `SessionTurnRuntime`. This extension owns only protected-draft recovery and
/// visible settlement effects; authoritative events still enter through the
/// model's single ordered event application boundary.
@MainActor
extension SessionListModel {
    func settlePromptFailure(
        token: SessionComposerRuntime.RecoveryToken,
        liveSessionID: String,
        entryID: String,
        input: String,
        message: String,
        uncertain: Bool
    ) {
        if !uncertain {
            stopBackgroundTurn(
                gatewayID: token.owner.gatewayID,
                liveSessionID: liveSessionID
            )
        }
        let resolution = runtimes.draftLifecycleRuntime.recover(
            token: token,
            failedInput: input,
            notice: message,
            uncertain: uncertain,
            noticeChannel: .operation,
            isVisible: transcriptIsVisible(for: token.owner),
            onFailure: draftFailureHandler()
        )
        guard case let .visible(recovery) = resolution else {
            return
        }

        transcriptEntries.removeAll { $0.id == entryID }
        if composerIsVisible(for: recovery.owner) {
            composer = recovery.restoredText
        }
        if liveSession?.liveID == liveSessionID {
            isSending = false
            turnStartedAt = nil
            activeTodos = nil
            if let selectedSessionID {
                activeStatuses.removeValue(forKey: selectedSessionID)
            }
        }
        operationError = recovery.notice
    }

    func settleSteerFailure(
        token: SessionComposerRuntime.RecoveryToken,
        entryID: String,
        input: String,
        notice: String,
        uncertain: Bool
    ) {
        let resolution = runtimes.draftLifecycleRuntime.recover(
            token: token,
            failedInput: input,
            notice: notice,
            uncertain: uncertain,
            noticeChannel: .steer,
            isVisible: transcriptIsVisible(for: token.owner),
            onFailure: draftFailureHandler()
        )
        guard case let .visible(recovery) = resolution else {
            return
        }

        transcriptEntries.removeAll { $0.id == entryID }
        transcriptEntries = liveTranscript.appendSystem(
            recovery.notice,
            isError: true,
            to: transcriptEntries
        )
        if composerIsVisible(for: recovery.owner) {
            composer = recovery.restoredText
            operationError = recovery.notice
        }
    }

    func settleStop(
        _ outcome: SessionTurnRuntime.StopOutcome,
        liveSessionID: String
    ) {
        guard liveSession?.liveID == liveSessionID else {
            return
        }
        switch outcome {
        case .succeeded:
            settleSuccessfulStop(liveSessionID: liveSessionID)
        case let .failed(message):
            isStopping = false
            operationError = message
            runtimes.talkRuntime.handleStopFailed(message: message)
        }
    }

    func settleSuccessfulStop(liveSessionID: String) {
        stopBackgroundTurn(
            gatewayID: currentGatewayID,
            liveSessionID: liveSessionID
        )
        if let gatewayID = currentGatewayID {
            runtimes.blockingPromptRuntime.finalizeRuntime(
                gatewayID: gatewayID,
                liveSessionID: liveSessionID,
                message: "Run stopped."
            )
        }
        transcriptEntries.removeAll { entry in
            guard case let .message(message) = entry else {
                return false
            }
            return message.pending
        }
        transcriptEntries = liveTranscript.appendSystem(
            "stop requested",
            to: transcriptEntries
        )
        isSending = false
        isStopping = false
        turnStartedAt = nil
        activeTodos = nil
        if let selectedSessionID {
            activeStatuses.removeValue(forKey: selectedSessionID)
        }
        syncBlockingPromptUI()
        runtimes.talkRuntime.handleStopSucceeded(
            environmentProvider: talkEnvironmentProvider()
        )
    }
}
