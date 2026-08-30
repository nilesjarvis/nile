import AVFoundation
import Foundation

@MainActor
final class AVSpeechOutput: NSObject, SpeechOutput, AVAudioPlayerDelegate {
    private var requestGeneration: Int64 = 0
    private var activePlayback: SpeechPlayback?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func play(
        audioBytes: Data,
        mimeType: String
    ) async throws -> SpeechPlaybackResult {
        guard !audioBytes.isEmpty else {
            throw HermesError(
                "Synthesized audio is empty",
                retryable: false
            )
        }
        let normalizedMimeType = mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard normalizedMimeType.hasPrefix("audio/") else {
            throw HermesError(
                "Synthesized reply must use an audio MIME type",
                retryable: false
            )
        }

        requestGeneration += 1
        finishActive(.stopped)
        let generation = requestGeneration
        do {
            try SpeechAudioSession.activatePlayback()
            let player = try AVAudioPlayer(data: audioBytes)
            player.delegate = self
            let playback = SpeechPlayback(
                generation: generation,
                player: player
            )
            activePlayback = playback

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    playback.continuation = continuation
                    guard generation == requestGeneration,
                          !Task.isCancelled else {
                        finish(playback, .stopped)
                        return
                    }
                    guard player.prepareToPlay(), player.play() else {
                        finish(
                            playback,
                            .failed(
                                HermesError(
                                    "Could not start the spoken reply",
                                    retryable: false
                                )
                            )
                        )
                        return
                    }
                    armWatchdog(playback)
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.stop(generation: generation)
                }
            }
        } catch {
            if generation == requestGeneration {
                finishActive(.failed(error))
            }
            SpeechAudioSession.deactivate()
            throw error
        }
    }

    func stop() {
        requestGeneration += 1
        finishActive(.stopped)
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self,
                  let playback = self.activePlayback,
                  ObjectIdentifier(playback.player) == playerID else {
                return
            }
            self.finish(
                playback,
                flag
                    ? .completed
                    : .failed(
                        HermesError(
                            "Spoken-reply playback failed",
                            retryable: false
                        )
                    )
            )
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        let playerID = ObjectIdentifier(player)
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self,
                  let playback = self.activePlayback,
                  ObjectIdentifier(playback.player) == playerID else {
                return
            }
            self.finish(
                playback,
                .failed(
                    HermesError(
                        message ?? "Spoken-reply playback failed",
                        retryable: false
                    )
                )
            )
        }
    }

    @objc
    private nonisolated func handleAudioInterruption(
        _ notification: Notification
    ) {
        let typeValue = notification.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? UInt
        guard typeValue
            == AVAudioSession.InterruptionType.began.rawValue else {
            return
        }
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    private func stop(generation: Int64) {
        guard activePlayback?.generation == generation else {
            return
        }
        requestGeneration += 1
        finishActive(.stopped)
    }

    private func armWatchdog(_ playback: SpeechPlayback) {
        let durationMilliseconds: Int64
        if playback.player.duration > 0 {
            durationMilliseconds = min(
                Int64(playback.player.duration * 1_000) + 30_000,
                30 * 60 * 1_000
            )
        } else {
            durationMilliseconds = 10 * 60 * 1_000
        }
        playback.watchdog = Task { @MainActor [weak self, weak playback] in
            try? await Task.sleep(
                for: .milliseconds(durationMilliseconds)
            )
            guard !Task.isCancelled,
                  let self,
                  let playback,
                  self.activePlayback === playback else {
                return
            }
            self.finish(
                playback,
                .failed(
                    HermesError(
                        "Spoken-reply playback stalled",
                        retryable: false
                    )
                )
            )
        }
    }

    private func finishActive(_ end: SpeechPlaybackEnd) {
        if let activePlayback {
            finish(activePlayback, end)
        }
    }

    private func finish(
        _ playback: SpeechPlayback,
        _ end: SpeechPlaybackEnd
    ) {
        guard !playback.ended else {
            return
        }
        playback.ended = true
        playback.watchdog?.cancel()
        playback.watchdog = nil
        if activePlayback === playback {
            activePlayback = nil
        }
        playback.player.delegate = nil
        if playback.player.isPlaying {
            playback.player.stop()
        }
        SpeechAudioSession.deactivate()

        guard let continuation = playback.continuation else {
            return
        }
        playback.continuation = nil
        switch end {
        case .completed:
            continuation.resume(returning: .completed)
        case .stopped:
            continuation.resume(returning: .stopped)
        case let .failed(error):
            continuation.resume(throwing: error)
        }
    }
}

@MainActor
private final class SpeechPlayback {
    let generation: Int64
    let player: AVAudioPlayer
    var continuation:
        CheckedContinuation<SpeechPlaybackResult, any Error>?
    var watchdog: Task<Void, Never>?
    var ended = false

    init(generation: Int64, player: AVAudioPlayer) {
        self.generation = generation
        self.player = player
    }
}

private enum SpeechPlaybackEnd {
    case completed
    case stopped
    case failed(any Error)
}
