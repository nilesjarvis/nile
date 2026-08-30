import Foundation

final class HermesVoiceInput: VoiceInput, @unchecked Sendable {
    let isAvailable: Bool
    let events: AsyncStream<VoiceInputEvent>

    private let captureOperation: SpeechCaptureOperation
    private let continuation: AsyncStream<VoiceInputEvent>.Continuation
    private let stateLock = NSLock()
    private let captureGate = SpeechCaptureGate()
    private var generation: Int64 = 0
    private var activeCapture: SpeechCapture?

    init(
        transcribe: @escaping @Sendable (
            RecordedAudio
        ) async throws -> SpeechTranscript,
        audioSourceFactory: @escaping PcmAudioSourceFactory,
        isAvailable: Bool = true,
        elapsedMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        },
        detectorFactory: @escaping @Sendable () ->
            PcmVoiceActivityDetector = {
                PcmVoiceActivityDetector()
            },
        noSpeechTimeoutMilliseconds: Int64 = 6_000,
        endpointSilenceMilliseconds: Int64 = 700,
        maximumUtteranceMilliseconds: Int64 = 30_000
    ) {
        precondition(noSpeechTimeoutMilliseconds >= 0)
        precondition(endpointSilenceMilliseconds >= 0)
        precondition(maximumUtteranceMilliseconds > 0)
        self.isAvailable = isAvailable
        captureOperation = SpeechCaptureOperation(
            transcribe: transcribe,
            audioSourceFactory: audioSourceFactory,
            elapsedMilliseconds: elapsedMilliseconds,
            detectorFactory: detectorFactory,
            noSpeechTimeoutMilliseconds: noSpeechTimeoutMilliseconds,
            endpointSilenceMilliseconds: endpointSilenceMilliseconds,
            maximumUtteranceMilliseconds: maximumUtteranceMilliseconds
        )
        let pair = AsyncStream.makeStream(
            of: VoiceInputEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        events = pair.stream
        continuation = pair.continuation
    }

    deinit {
        cancel()
        continuation.finish()
    }

    func start() {
        guard isAvailable else {
            continuation.yield(
                .error(
                    message: "Voice input is unavailable on this device"
                )
            )
            return
        }

        stateLock.lock()
        generation += 1
        let capture = SpeechCapture(generation: generation)
        let previous = activeCapture
        activeCapture = capture
        stateLock.unlock()
        previous?.cancelSynchronously()

        let task = Task.detached(priority: .userInitiated) {
            [weak self, capture] in
            guard let self else {
                return
            }
            await self.captureGate.acquire()
            defer {
                Task {
                    await self.captureGate.release()
                }
            }
            let terminal = await self.captureOperation.run(
                capture: capture,
                isCurrent: { [weak self, capture] in
                    self?.isCurrent(capture) ?? false
                },
                emit: { [continuation = self.continuation] event in
                    continuation.yield(event)
                }
            )
            if let terminal {
                self.emitTerminal(capture, terminal)
            }
            self.finishCapture(capture)
        }
        capture.setTask(task)
    }

    func stop() {
        stateLock.lock()
        let capture = activeCapture
        stateLock.unlock()
        capture?.requestFinish()
    }

    func cancel() {
        stateLock.lock()
        generation += 1
        let capture = activeCapture
        activeCapture = nil
        stateLock.unlock()
        capture?.cancelSynchronously()
    }

    private func emitTerminal(
        _ capture: SpeechCapture,
        _ event: VoiceInputEvent
    ) {
        stateLock.lock()
        let owns = activeCapture === capture
            && generation == capture.generation
            && !capture.isCancelled
        let shouldEmit = owns && capture.markTerminalIfNeeded()
        stateLock.unlock()
        if shouldEmit {
            continuation.yield(event)
        }
    }

    private func isCurrent(_ capture: SpeechCapture) -> Bool {
        stateLock.lock()
        let result = activeCapture === capture
            && generation == capture.generation
            && !capture.isCancelled
            && !capture.isTerminal
        stateLock.unlock()
        return result
    }

    private func finishCapture(_ capture: SpeechCapture) {
        stateLock.withLock {
            if activeCapture === capture {
                activeCapture = nil
            }
        }
    }
}
