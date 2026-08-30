import Foundation

enum VoiceInputEvent: Equatable, Sendable {
    case preparing
    case listening(partialText: String)
    case transcribing
    case finished(text: String)
    case error(message: String)
}

protocol VoiceInput: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var events: AsyncStream<VoiceInputEvent> { get }

    func start()
    func stop()
    func cancel()
}

final class UnavailableVoiceInput: VoiceInput, @unchecked Sendable {
    let isAvailable = false
    let events: AsyncStream<VoiceInputEvent>

    init() {
        events = AsyncStream { _ in }
    }

    func start() {}
    func stop() {}
    func cancel() {}
}

protocol PcmAudioSource: AnyObject, Sendable {
    func start() throws
    func read(_ samples: inout [Int16]) -> Int
    func stop()
    func close()
}

typealias PcmAudioSourceFactory =
    @Sendable () async throws -> any PcmAudioSource

struct MicrophonePermissionDeniedError: Error, Sendable {}
