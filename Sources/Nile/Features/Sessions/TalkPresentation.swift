import Foundation

struct TalkPresentation: Equatable, Sendable {
    enum PrimaryAction: Equatable, Sendable {
        case pause
        case resume
        case interruptSpeech
        case stopRun
    }

    let status: String
    let detail: String
    let primaryAction: PrimaryAction?

    init(
        phase: TalkPhase,
        workingLabel: String?,
        hasBlockingPrompt: Bool,
        runActive: Bool
    ) {
        if hasBlockingPrompt {
            status = "Hermes needs your input"
            detail = "Listening is paused until the request is resolved."
            primaryAction = runActive ? .stopRun : nil
            return
        }
        switch phase {
        case .off:
            status = "Getting ready…"
            detail = "Starting the conversation on this device."
            primaryAction = nil
        case .preparingInput:
            status = "Preparing microphone…"
            detail =
                "Nile records the utterance; Hermes handles transcription."
            primaryAction = .pause
        case .listening:
            status = "Listening…"
            detail =
                "Speak naturally. Hermes will respond when you pause."
            primaryAction = .pause
        case .transcribing:
            status = "Hermes is transcribing…"
            detail =
                "The microphone is closed while Hermes processes your recording."
            primaryAction = .pause
        case .submitting:
            status = "Sending…"
            detail = "Your utterance is being sent to Hermes."
            primaryAction = runActive ? .stopRun : nil
        case .working:
            status = workingLabel?.isBlank == false
                ? workingLabel!
                : "Working…"
            detail = "Hermes is preparing a response."
            primaryAction = runActive ? .stopRun : nil
        case .preparingSpeech:
            status = "Preparing voice…"
            detail =
                "The first part of Hermes's response will begin shortly."
            primaryAction = .interruptSpeech
        case .speaking:
            status = "Speaking…"
            detail = runActive
                ? "Hermes is still responding. Tap Listen to interrupt and start a new turn."
                : "Tap Listen to skip the rest of the reply."
            primaryAction = .interruptSpeech
        case .paused:
            status = "Microphone paused"
            detail = "Resume when you are ready to continue."
            primaryAction = .resume
        }
    }
}
