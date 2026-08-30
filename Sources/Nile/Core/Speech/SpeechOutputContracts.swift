import Foundation

enum SpeechPlaybackResult: Equatable, Sendable {
    case completed
    case stopped
}

@MainActor
protocol SpeechOutput: AnyObject {
    func play(
        audioBytes: Data,
        mimeType: String
    ) async throws -> SpeechPlaybackResult

    func stop()
}

@MainActor
final class NoOpSpeechOutput: SpeechOutput {
    func play(
        audioBytes: Data,
        mimeType: String
    ) async throws -> SpeechPlaybackResult {
        .completed
    }

    func stop() {}
}
