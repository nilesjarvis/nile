import Foundation

extension SessionTalkRuntime {
    func handleMessageStart(liveSessionID: String) {
        guard let turn = currentTurn(for: liveSessionID) else {
            return
        }
        if [.preparingSpeech, .speaking].contains(coordinator.state.phase) {
            pauseTurn(
                turn,
                message:
                    "Talk paused because another turn started while Hermes's reply was playing.",
                stopSpeech: false
            )
        } else if coordinator.markWorking(turn) {
            publishState()
        }
    }

    @discardableResult
    func handleAssistantCompleted(
        liveSessionID: String,
        rawText: String,
        completionWasStopping: Bool,
        environmentProvider: @escaping EnvironmentProvider,
        onError: @escaping ErrorHandler
    ) -> Bool {
        guard let turn = currentTurn(for: liveSessionID) else {
            return false
        }
        let submitWasAcknowledged = submission.takeAcknowledgement(for: turn)
        if completionWasStopping {
            let resumeMode = resumeAfterStop
            resumeAfterStop = nil
            pauseTurn(
                turn,
                message:
                    "Hermes's turn ended while Stop was in progress. Tap Resume to keep talking."
            )
            if let resumeMode, coordinator.isCurrent(resumeMode) {
                pauseAndScheduleResume(
                    resumeMode,
                    message: "Hermes's response was interrupted.",
                    environmentProvider: environmentProvider,
                    onError: onError
                )
            }
        } else if !submitWasAcknowledged {
            if coordinator.markWorking(turn) {
                publishState()
            }
        } else {
            speakReply(
                turn,
                rawText: rawText,
                environmentProvider: environmentProvider,
                onError: onError
            )
        }
        return true
    }

    @discardableResult
    func handleError(
        liveSessionID: String,
        message: String,
        wasStopping: Bool,
        environmentProvider: @escaping EnvironmentProvider
    ) -> Bool {
        guard let turn = currentTurn(for: liveSessionID) else {
            return false
        }
        let resumeMode = wasStopping ? resumeAfterStop : nil
        if resumeMode != nil {
            resumeAfterStop = nil
        }
        if submission.hasUncorrelatedTerminal(for: turn) {
            if coordinator.markWorking(turn) {
                publishState()
            }
        } else {
            pauseTurn(
                turn,
                message: "Hermes could not finish that turn: \(message)"
            )
            if let resumeMode, coordinator.isCurrent(resumeMode) {
                pauseAndScheduleResume(
                    resumeMode,
                    message: "Hermes's response was interrupted.",
                    environmentProvider: environmentProvider,
                    onError: { _ in }
                )
            }
        }
        return true
    }

    func handleStopSucceeded(
        environmentProvider: @escaping EnvironmentProvider
    ) {
        guard let resumeMode = resumeAfterStop else {
            return
        }
        resumeAfterStop = nil
        pauseAndScheduleResume(
            resumeMode,
            message: "Hermes's response was interrupted.",
            environmentProvider: environmentProvider,
            onError: { _ in }
        )
    }

    func handleStopFailed(message: String) {
        guard let resumeMode = resumeAfterStop else {
            return
        }
        resumeAfterStop = nil
        _ = coordinator.pause(
            resumeMode,
            message: "Could not interrupt Hermes's response: \(message)"
        )
        publishState()
    }

    func pauseTurn(
        _ turn: TalkTurnToken,
        message: String,
        stopSpeech: Bool = true
    ) {
        if stopSpeech {
            speech.stop()
        }
        submission.clearAcknowledgement(for: turn)
        if coordinator.pauseTurn(turn, message: message) {
            publishState()
            resetInputPresentation()
        }
    }

    private func speakReply(
        _ turn: TalkTurnToken,
        rawText: String,
        environmentProvider: @escaping EnvironmentProvider,
        onError: @escaping ErrorHandler
    ) {
        guard coordinator.isCurrent(turn) else {
            return
        }
        let talkOwner = turn.mode.owner
        let speechOwner = SessionSpeechRuntime.Owner(
            gatewayGeneration: Int(talkOwner.connectionGeneration),
            gatewayID: talkOwner.gatewayID,
            storedSessionID: talkOwner.selectedSessionID,
            liveSessionID: talkOwner.liveSessionID
        )
        speech.playTalkReply(
            rawText,
            owner: speechOwner,
            isCurrentOwner: { [weak self] owner in
                guard let self else {
                    return false
                }
                let environment = environmentProvider()
                return owner == speechOwner
                    && coordinator.isCurrent(turn)
                    && environment.owner == talkOwner
                    && environment.isForeground
            },
            onPreparing: { [weak self] in
                guard let self, coordinator.markPreparingSpeech(turn) else {
                    return false
                }
                publishState()
                return true
            },
            onPlaybackReady: { [weak self] in
                guard let self, coordinator.markSpeaking(turn) else {
                    return false
                }
                publishState()
                return true
            },
            onCompleted: { [weak self] in
                guard let self,
                      let request = coordinator.requestRelistenAfterTurn(turn)
                else {
                    return
                }
                publishState()
                scheduleRelisten(
                    request,
                    environmentProvider: environmentProvider,
                    onError: onError
                )
            },
            onStopped: { [weak self] in
                guard let self else {
                    return
                }
                let message =
                    "Hermes's reply was interrupted. Tap Resume when you're ready."
                onError(message)
                pauseTurn(turn, message: message, stopSpeech: false)
            },
            onFailure: { [weak self] failure in
                guard let self else {
                    return
                }
                let message = failure.synthesisUnavailable
                    ? "Hermes voice is unavailable: \(failure.description)"
                    : "Could not play Hermes's reply: \(failure.description)"
                onError(message)
                pauseTurn(turn, message: message, stopSpeech: false)
            }
        )
    }

    private func currentTurn(for liveSessionID: String) -> TalkTurnToken? {
        coordinator.currentTurn().flatMap {
            $0.mode.owner.liveSessionID == liveSessionID ? $0 : nil
        }
    }
}
