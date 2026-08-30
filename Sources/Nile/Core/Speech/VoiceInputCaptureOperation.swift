import Foundation

struct SpeechCaptureOperation: Sendable {
    private let transcribe:
        @Sendable (RecordedAudio) async throws -> SpeechTranscript
    private let audioSourceFactory: PcmAudioSourceFactory
    private let elapsedMilliseconds: @Sendable () -> Int64
    private let detectorFactory:
        @Sendable () -> PcmVoiceActivityDetector
    private let noSpeechTimeoutMilliseconds: Int64
    private let endpointSilenceMilliseconds: Int64
    private let maximumUtteranceMilliseconds: Int64

    init(
        transcribe: @escaping @Sendable (
            RecordedAudio
        ) async throws -> SpeechTranscript,
        audioSourceFactory: @escaping PcmAudioSourceFactory,
        elapsedMilliseconds: @escaping @Sendable () -> Int64,
        detectorFactory: @escaping @Sendable () ->
            PcmVoiceActivityDetector,
        noSpeechTimeoutMilliseconds: Int64,
        endpointSilenceMilliseconds: Int64,
        maximumUtteranceMilliseconds: Int64
    ) {
        self.transcribe = transcribe
        self.audioSourceFactory = audioSourceFactory
        self.elapsedMilliseconds = elapsedMilliseconds
        self.detectorFactory = detectorFactory
        self.noSpeechTimeoutMilliseconds = noSpeechTimeoutMilliseconds
        self.endpointSilenceMilliseconds = endpointSilenceMilliseconds
        self.maximumUtteranceMilliseconds = maximumUtteranceMilliseconds
    }

    func run(
        capture: SpeechCapture,
        isCurrent: @escaping @Sendable () -> Bool,
        emit: @escaping @Sendable (VoiceInputEvent) -> Void
    ) async -> VoiceInputEvent? {
        var source: (any PcmAudioSource)?
        defer {
            capture.clearSource()
            source?.close()
        }
        do {
            guard isCurrent(), !Task.isCancelled else {
                return nil
            }
            emit(.preparing)
            let openedSource = try await audioSourceFactory()
            source = openedSource
            guard capture.setSource(openedSource), isCurrent(),
                  !Task.isCancelled else {
                openedSource.close()
                return nil
            }
            if capture.isFinishRequested {
                openedSource.close()
                return .finished(text: "")
            }

            try openedSource.start()
            let startedAt = elapsedMilliseconds()
            emit(.listening(partialText: ""))

            var detector = detectorFactory()
            var recording = [Int16](
                repeating: 0,
                count: maximumSamples()
            )
            var readBuffer = [Int16](
                repeating: 0,
                count: speechReadSamples
            )
            var recordedSamples = 0
            var outcome = SpeechCaptureOutcome.cancelled

            while true {
                if Task.isCancelled || !isCurrent() || capture.isCancelled {
                    break
                }
                if capture.isFinishRequested {
                    outcome = .forced
                    break
                }

                let count = openedSource.read(&readBuffer)
                if count > 0 {
                    guard count <= readBuffer.count else {
                        throw HermesError(
                            "Microphone returned an invalid sample count",
                            retryable: false
                        )
                    }
                    let writable = min(
                        count,
                        recording.count - recordedSamples
                    )
                    if writable > 0 {
                        for index in 0..<writable {
                            recording[recordedSamples + index] =
                                readBuffer[index]
                        }
                        recordedSamples += writable
                    }
                    let now = elapsedMilliseconds()
                    detector.accept(
                        samples: readBuffer,
                        count: count,
                        nowMilliseconds: now
                    )
                    if detector.heardSpeech,
                       let lastSpeech = detector.lastSpeechAtMilliseconds,
                       now - lastSpeech >= endpointSilenceMilliseconds {
                        outcome = .endpoint
                        break
                    }
                    if !detector.heardSpeech,
                       now - startedAt >= noSpeechTimeoutMilliseconds {
                        outcome = .noSpeech
                        break
                    }
                    if now - startedAt >= maximumUtteranceMilliseconds
                        || recordedSamples == recording.count {
                        outcome = .forced
                        break
                    }
                } else if !capture.isFinishRequested
                    && !capture.isCancelled {
                    throw HermesError(
                        "Microphone read failed (\(count))",
                        retryable: false
                    )
                }
            }

            openedSource.stop()
            openedSource.close()
            capture.clearSource()
            source = nil

            switch outcome {
            case .cancelled:
                return nil
            case .noSpeech:
                return .finished(text: "")
            case .endpoint, .forced:
                guard detector.heardSpeech, recordedSamples > 0 else {
                    return .finished(text: "")
                }
                try Task.checkCancellation()
                guard isCurrent() else {
                    return nil
                }
                emit(.transcribing)
                let transcript = try await transcribe(
                    RecordedAudio(
                        mimeType: "audio/wav",
                        bytes: PcmWavEncoder.encode(
                            samples: recording,
                            count: recordedSamples
                        )
                    )
                )
                try Task.checkCancellation()
                return .finished(
                    text: transcript.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                )
            }
        } catch is CancellationError {
            return nil
        } catch {
            return .error(message: voiceInputFailureMessage(error))
        }
    }

    private func maximumSamples() -> Int {
        let samples = Int64(speechSampleRateHz)
            * maximumUtteranceMilliseconds / 1_000
        return Int(max(1, min(samples, Int64(Int.max))))
    }
}

private func voiceInputFailureMessage(_ error: any Error) -> String {
    if error is MicrophonePermissionDeniedError {
        return "Microphone permission denied"
    }
    if error is SpeechTranscriptionUnavailableError {
        return "Hermes voice transcription is unavailable"
    }
    if error.localizedDescription.localizedCaseInsensitiveContains(
        "microphone"
    ) {
        return "Microphone could not be opened"
    }
    return "Hermes could not transcribe that recording"
}

private enum SpeechCaptureOutcome {
    case cancelled
    case noSpeech
    case endpoint
    case forced
}
