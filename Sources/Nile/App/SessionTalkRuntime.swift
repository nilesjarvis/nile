import Foundation
import Observation

@MainActor
@Observable
final class SessionTalkRuntime {
    private(set) var presentation: TalkUIState?
    private(set) var isListening = false
    private(set) var isTranscribing = false

    var isActive: Bool { coordinator.currentMode() != nil }

    @ObservationIgnored
    let voice: SessionVoiceInputRuntime
    @ObservationIgnored
    let speech: SessionSpeechRuntime
    @ObservationIgnored
    let submission: TalkSubmissionRuntime
    @ObservationIgnored
    let relisten: SessionTalkRelistenRuntime
    @ObservationIgnored
    var coordinator: TalkModeCoordinator
    @ObservationIgnored
    var resumeAfterStop: TalkModeToken?

    init(
        repository: (any HermesTalkServing)?,
        voice: SessionVoiceInputRuntime,
        speech: SessionSpeechRuntime,
        relistenDelay: Duration = .milliseconds(300),
        blankResultLimit: Int = 3
    ) {
        self.voice = voice
        self.speech = speech
        submission = TalkSubmissionRuntime(repository: repository)
        relisten = SessionTalkRelistenRuntime(delay: relistenDelay)
        coordinator = TalkModeCoordinator(blankResultLimit: blankResultLimit)
    }

    func start(
        voiceInputAvailable: Bool,
        environment: Environment,
        otherVoiceActivity: Bool,
        onError: @escaping ErrorHandler
    ) {
        guard !isActive, !otherVoiceActivity else {
            return
        }
        guard voiceInputAvailable else {
            onError("Voice input is unavailable on this device.")
            return
        }
        guard let owner = environment.owner, environment.canListen else {
            onError(
                "Talk is available when this conversation is connected and idle."
            )
            return
        }

        speech.stop()
        resetTurnState()
        _ = coordinator.begin(owner: owner)
        publishState()
        resetInputPresentation()
        onError(nil)
        voice.startCapture(composer: "")
    }

    func pause(
        message: String =
            "Microphone paused. Tap Resume when you're ready.",
        stopSpeech: Bool = true
    ) {
        guard let mode = coordinator.currentMode() else {
            return
        }
        voice.cancelCapture()
        cancelRelisten()
        if stopSpeech {
            speech.stop()
        }
        resetTurnState()
        if coordinator.pause(mode, message: message) {
            publishState()
            resetInputPresentation()
        }
    }

    func resume(
        environmentProvider: @escaping EnvironmentProvider,
        onError: @escaping ErrorHandler
    ) {
        guard let mode = coordinator.currentMode() else {
            return
        }
        let environment = environmentProvider()
        handleRelistenDecision(
            coordinator.resume(
                mode,
                currentOwner: environment.owner,
                canListen: environment.canListen
            ),
            onError: onError
        )
    }

    func interruptSpeech(
        remoteTurnActive: Bool,
        environmentProvider: @escaping EnvironmentProvider,
        onStopRequested: @escaping StopHandler
    ) {
        guard let turn = coordinator.currentTurn() else {
            return
        }
        speech.stop()
        submission.clearAcknowledgement()
        if remoteTurnActive {
            resumeAfterStop = turn.mode
            onStopRequested()
            return
        }
        guard let request = coordinator.requestRelistenAfterTurn(turn) else {
            return
        }
        publishState()
        scheduleRelisten(
            request,
            environmentProvider: environmentProvider,
            onError: { _ in }
        )
    }

    func end() {
        guard let mode = coordinator.currentMode() else {
            return
        }
        voice.cancelCapture()
        speech.stop()
        cancelRelisten()
        submission.cancel()
        resetTurnState()
        _ = coordinator.end(mode)
        presentation = nil
        resetInputPresentation()
    }

    func cancelInput() {
        voice.cancelCapture()
        resetInputPresentation()
    }

    @discardableResult
    func consumeVoiceEvent(
        _ event: VoiceInputEvent,
        environmentProvider: @escaping EnvironmentProvider,
        onSubmissionStarted: @escaping SubmissionHandler,
        onSubmissionFailed: @escaping SubmissionFailureHandler,
        onError: @escaping ErrorHandler
    ) -> Bool {
        guard let mode = coordinator.currentMode() else {
            return false
        }
        let environment = environmentProvider()
        guard environment.owner == mode.owner, environment.canListen else {
            cancelInput()
            end()
            return true
        }
        guard let transition = voice.transition(event: event) else {
            return true
        }
        switch transition {
        case .preparing:
            if coordinator.state.phase == .preparingInput {
                resetInputPresentation()
            }
        case let .listening(partial):
            guard coordinator.markListening(mode) else {
                return true
            }
            _ = coordinator.observePartial(mode, text: partial)
            publishState()
            isListening = true
            isTranscribing = false
        case .transcribing:
            guard coordinator.markTranscribing(mode) else {
                return true
            }
            publishState()
            isListening = false
            isTranscribing = true
        case let .finished(text):
            voice.finishEvents()
            resetInputPresentation()
            switch coordinator.finishRecognition(mode, text: text) {
            case let .submit(turn, finalText):
                submission.clearAcknowledgement()
                publishState()
                submission.submit(
                    turn,
                    input: finalText,
                    environmentProvider: environmentProvider,
                    onSubmissionStarted: onSubmissionStarted,
                    onSubmissionFailed: onSubmissionFailed,
                    isCurrent: { [weak self] turn in
                        self?.coordinator.isCurrent(turn) ?? false
                    },
                    onWorking: { [weak self] turn in
                        guard let self,
                              coordinator.markWorking(turn) else {
                            return
                        }
                        publishState()
                    },
                    onPause: { [weak self] turn, message in
                        self?.pauseTurn(turn, message: message)
                    }
                )
            case let .relisten(request):
                publishState()
                scheduleRelisten(
                    request,
                    environmentProvider: environmentProvider,
                    onError: onError
                )
            case .paused:
                publishState()
            case .ignored:
                break
            }
        case let .error(_, message):
            voice.finishEvents()
            _ = coordinator.pause(mode, message: message)
            publishState()
            resetInputPresentation()
        }
        return true
    }

    func pauseForBlockingPrompt() {
        pause(
            message: "Talk paused while Hermes waits for your response."
        )
    }

    func noteTerminalBeforeAdmission(liveSessionID: String) {
        submission.noteTerminalBeforeAcknowledgement(
            liveSessionID: liveSessionID
        )
    }

    func publishState() {
        let state = coordinator.state
        presentation = state.isActive ? state : nil
    }

    func resetInputPresentation() {
        isListening = false
        isTranscribing = false
    }

    func clearPresentation() {
        presentation = nil
    }

    private func resetTurnState() {
        submission.resetCorrelation()
        resumeAfterStop = nil
    }
}
