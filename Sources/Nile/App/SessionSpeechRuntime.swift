import Foundation
import Observation

@MainActor
@Observable
final class SessionSpeechRuntime {
    struct Owner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String?
        let storedSessionID: String?
        let liveSessionID: String?
    }

    struct Failure: Equatable, Sendable {
        let description: String
        let synthesisUnavailable: Bool
    }

    typealias OwnerCheck = @MainActor (Owner) -> Bool
    typealias FailureHandler = @MainActor (Failure) -> Void
    typealias PlaybackReadyHandler = @MainActor () -> Bool
    typealias PlaybackHandler = @MainActor () -> Void

    private(set) var standardRepliesEnabled = false

    @ObservationIgnored
    private let repository: (any HermesSpeechSynthesisServing)?
    @ObservationIgnored
    private let output: any SpeechOutput
    @ObservationIgnored
    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration: Int64 = 0
    private var standardFailureReported = false

    init(
        repository: (any HermesSpeechSynthesisServing)?,
        output: any SpeechOutput
    ) {
        self.repository = repository
        self.output = output
    }

    isolated deinit {
        playbackTask?.cancel()
        output.stop()
    }

    func setStandardRepliesEnabled(_ enabled: Bool) {
        standardRepliesEnabled = enabled
        standardFailureReported = false
        if !enabled {
            stop()
        }
    }

    func stop() {
        playbackGeneration &+= 1
        playbackTask?.cancel()
        playbackTask = nil
        output.stop()
    }

    func playStandardReply(
        _ rawText: String,
        owner: Owner,
        isCurrentOwner: @escaping OwnerCheck,
        onFailure: @escaping FailureHandler
    ) {
        guard standardRepliesEnabled,
              let repository else {
            return
        }
        let chunks = speechChunks(rawText)
        guard !chunks.isEmpty else {
            return
        }

        let request = begin(owner: owner)
        playbackTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                for chunk in chunks {
                    guard self.isCurrent(
                        request,
                        isCurrentOwner: isCurrentOwner
                    ) else {
                        return
                    }
                    let speech = try await repository.synthesizeSpeech(
                        text: chunk
                    )
                    guard self.isCurrent(
                        request,
                        isCurrentOwner: isCurrentOwner
                    ) else {
                        return
                    }
                    let result = try await self.output.play(
                        audioBytes: speech.bytes,
                        mimeType: speech.mimeType
                    )
                    guard result == .completed,
                          self.isCurrent(
                            request,
                            isCurrentOwner: isCurrentOwner
                          ) else {
                        return
                    }
                }
                guard self.isCurrent(
                    request,
                    isCurrentOwner: isCurrentOwner
                ) else {
                    return
                }
                self.standardFailureReported = false
                self.finish(request)
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    request,
                    isCurrentOwner: isCurrentOwner
                ) else {
                    return
                }
                let failure = Self.failure(for: error)
                if failure.synthesisUnavailable {
                    self.standardRepliesEnabled = false
                } else if self.standardFailureReported {
                    self.finish(request)
                    return
                }
                self.standardFailureReported = true
                onFailure(failure)
                self.finish(request)
            }
        }
    }

    func playTalkReply(
        _ rawText: String,
        owner: Owner,
        isCurrentOwner: @escaping OwnerCheck,
        onPreparing: @escaping PlaybackReadyHandler,
        onPlaybackReady: @escaping PlaybackReadyHandler,
        onCompleted: @escaping PlaybackHandler,
        onStopped: @escaping PlaybackHandler,
        onFailure: @escaping FailureHandler
    ) {
        guard let repository else {
            return
        }
        let chunks = speechChunks(rawText)
        let request = begin(owner: owner)
        guard isCurrent(
            request,
            isCurrentOwner: isCurrentOwner
        ), onPreparing() else {
            finish(request)
            return
        }
        playbackTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                var beganPlayback = false
                for chunk in chunks {
                    guard self.isCurrent(
                        request,
                        isCurrentOwner: isCurrentOwner
                    ) else {
                        return
                    }
                    let speech = try await repository.synthesizeSpeech(
                        text: chunk
                    )
                    guard self.isCurrent(
                        request,
                        isCurrentOwner: isCurrentOwner
                    ) else {
                        return
                    }
                    if !beganPlayback {
                        guard onPlaybackReady() else {
                            self.finish(request)
                            return
                        }
                        beganPlayback = true
                    }
                    let result = try await self.output.play(
                        audioBytes: speech.bytes,
                        mimeType: speech.mimeType
                    )
                    guard self.isCurrent(
                        request,
                        isCurrentOwner: isCurrentOwner
                    ) else {
                        return
                    }
                    if result == .stopped {
                        onStopped()
                        self.finish(request)
                        return
                    }
                }
                guard self.isCurrent(
                    request,
                    isCurrentOwner: isCurrentOwner
                ) else {
                    return
                }
                onCompleted()
                self.finish(request)
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    request,
                    isCurrentOwner: isCurrentOwner
                ) else {
                    return
                }
                onFailure(Self.failure(for: error))
                self.finish(request)
            }
        }
    }

    private func begin(owner: Owner) -> PlaybackRequest {
        stop()
        let request = PlaybackRequest(
            generation: playbackGeneration,
            owner: owner
        )
        return request
    }

    private func isCurrent(
        _ request: PlaybackRequest,
        isCurrentOwner: OwnerCheck
    ) -> Bool {
        request.generation == playbackGeneration
            && isCurrentOwner(request.owner)
    }

    private func finish(_ request: PlaybackRequest) {
        guard request.generation == playbackGeneration else {
            return
        }
        playbackTask = nil
    }

    private func speechChunks(_ rawText: String) -> [String] {
        let parsedText = parseMessageContent(rawText).text
        return chunkTextForSpeech(sanitizeTextForSpeech(parsedText))
    }

    private static func failure(for error: any Error) -> Failure {
        Failure(
            description: error.localizedDescription,
            synthesisUnavailable: error is SpeechSynthesisUnavailableError
        )
    }
}

private struct PlaybackRequest: Equatable, Sendable {
    let generation: Int64
    let owner: SessionSpeechRuntime.Owner
}
