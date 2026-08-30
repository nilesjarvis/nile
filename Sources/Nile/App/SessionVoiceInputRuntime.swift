import Foundation
import Observation

/// Owns the shared microphone adapter, ordinary-draft projection, and the
/// single voice-event task used by both ordinary dictation and Talk mode.
/// Hermes stream events remain routed exclusively by `SessionListModel`.
@MainActor
@Observable
final class SessionVoiceInputRuntime {
    typealias TalkEventHandler =
        @MainActor @Sendable (VoiceInputEvent) -> Bool
    typealias ComposerHandler = @MainActor @Sendable (String) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private(set) var isDraftListening = false
    private(set) var isDraftTranscribing = false

    var isAvailable: Bool { coordinator.isAvailable }
    var eventsAreEnabled: Bool { coordinator.eventsAreEnabled }

    @ObservationIgnored
    private let coordinator: VoiceInputCoordinator
    @ObservationIgnored
    private var eventTask: Task<Void, Never>?

    init(
        repository: (any HermesTranscriptionServing)?,
        input: (any VoiceInput)? = nil,
        audioSourceFactory: @escaping PcmAudioSourceFactory =
            AVAudioEnginePcmSource.create
    ) {
        let resolvedInput: any VoiceInput
        if let input {
            resolvedInput = input
        } else if let repository {
            resolvedInput = HermesVoiceInput(
                transcribe: { audio in
                    try await repository.transcribeSpeech(audio: audio)
                },
                audioSourceFactory: audioSourceFactory
            )
        } else {
            resolvedInput = UnavailableVoiceInput()
        }
        coordinator = VoiceInputCoordinator(input: resolvedInput)
    }

    isolated deinit {
        eventTask?.cancel()
    }

    func beginRouting(
        consumeTalkEvent: @escaping TalkEventHandler,
        onComposerChanged: @escaping ComposerHandler,
        onError: @escaping ErrorHandler
    ) {
        eventTask?.cancel()
        let events = coordinator.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else {
                    return
                }
                if consumeTalkEvent(event) {
                    continue
                }
                consumeDraftEvent(
                    event,
                    onComposerChanged: onComposerChanged,
                    onError: onError
                )
            }
        }
    }

    func startDraft(composer: String) {
        resetDraftPresentation()
        coordinator.start(composer: composer)
    }

    func stopCapture() {
        coordinator.stop()
    }

    func startCapture(composer: String) {
        resetDraftPresentation()
        coordinator.start(composer: composer)
    }

    func cancelCapture() {
        coordinator.cancel()
        resetDraftPresentation()
    }

    func transition(event: VoiceInputEvent) -> VoiceDraftTransition? {
        coordinator.transition(event: event)
    }

    func finishEvents() {
        coordinator.finishEvents()
    }

    private func consumeDraftEvent(
        _ event: VoiceInputEvent,
        onComposerChanged: ComposerHandler,
        onError: ErrorHandler
    ) {
        guard let transition = coordinator.transition(event: event) else {
            return
        }
        switch transition {
        case .preparing:
            resetDraftPresentation()
        case let .listening(updatedComposer):
            isDraftListening = true
            isDraftTranscribing = false
            onComposerChanged(updatedComposer)
        case .transcribing:
            isDraftListening = false
            isDraftTranscribing = true
        case let .finished(updatedComposer):
            resetDraftPresentation()
            coordinator.finishEvents()
            onComposerChanged(updatedComposer)
        case let .error(restoredComposer, message):
            resetDraftPresentation()
            coordinator.finishEvents()
            onComposerChanged(restoredComposer)
            onError(message)
        }
    }

    private func resetDraftPresentation() {
        isDraftListening = false
        isDraftTranscribing = false
    }
}
