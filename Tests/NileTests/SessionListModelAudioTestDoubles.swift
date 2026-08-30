import Foundation
@testable import Nile

final class SessionVoiceInputStub:
    VoiceInput,
    @unchecked Sendable
{
    let isAvailable = true
    let events: AsyncStream<VoiceInputEvent>
    private let continuation:
        AsyncStream<VoiceInputEvent>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init() {
        let pair = AsyncStream.makeStream(
            of: VoiceInputEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        events = pair.stream
        continuation = pair.continuation
    }

    func emit(_ event: VoiceInputEvent) {
        continuation.yield(event)
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
final class SessionSpeechOutputStub: SpeechOutput {
    struct Played: Equatable {
        let bytes: Data
        let mimeType: String
    }

    private(set) var played: [Played] = []
    private(set) var stopCount = 0

    func play(
        audioBytes: Data,
        mimeType: String
    ) async throws -> SpeechPlaybackResult {
        played.append(Played(bytes: audioBytes, mimeType: mimeType))
        return .completed
    }

    func stop() {
        stopCount += 1
    }
}
