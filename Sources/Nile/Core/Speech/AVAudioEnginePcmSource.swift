@preconcurrency import AVFoundation
import Foundation

final class AVAudioEnginePcmSource:
    PcmAudioSource,
    @unchecked Sendable
{
    private let condition = NSCondition()
    private let engine = AVAudioEngine()
    private var samples: [Int16] = []
    private var readOffset = 0
    private var started = false
    private var stopRequested = false
    private var closed = false
    private var tapInstalled = false
    private var conversionFailed = false

    static func create() async throws -> AVAudioEnginePcmSource {
        guard await microphonePermissionGranted() else {
            throw MicrophonePermissionDeniedError()
        }
        return AVAudioEnginePcmSource()
    }

    func start() throws {
        condition.lock()
        guard !closed else {
            condition.unlock()
            throw HermesError(
                "Microphone source is already closed",
                retryable: false
            )
        }
        guard !stopRequested else {
            condition.unlock()
            throw HermesError(
                "Microphone capture was stopped",
                retryable: false
            )
        }
        condition.unlock()

        do {
            try SpeechAudioSession.activateRecording()

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  inputFormat.channelCount > 0 else {
                throw HermesError(
                    "16 kHz microphone capture is unavailable",
                    retryable: false
                )
            }
            let converterBox = try SpeechAudioConverter(
                inputFormat: inputFormat
            )

            input.installTap(
                onBus: 0,
                bufferSize: AVAudioFrameCount(speechReadSamples),
                format: inputFormat
            ) { [weak self, converterBox] buffer, _ in
                guard let self else {
                    return
                }
                do {
                    let converted = try converterBox.convert(buffer)
                    self.enqueue(converted)
                } catch {
                    self.recordConversionFailure()
                }
            }
            condition.lock()
            tapInstalled = true
            condition.unlock()
            engine.prepare()
            try engine.start()
            condition.lock()
            started = true
            condition.unlock()
        } catch {
            stopAudioEngine()
            SpeechAudioSession.deactivate()
            throw error
        }
    }

    func read(_ destination: inout [Int16]) -> Int {
        condition.lock()
        defer { condition.unlock() }
        while availableSampleCount == 0,
              !stopRequested,
              !closed,
              !conversionFailed {
            condition.wait()
        }
        guard !stopRequested, !closed, !conversionFailed else {
            return -1
        }
        let count = min(destination.count, availableSampleCount)
        guard count > 0 else {
            return -1
        }
        for index in 0..<count {
            destination[index] = samples[readOffset + index]
        }
        readOffset += count
        compactConsumedSamplesIfNeeded()
        return count
    }

    func stop() {
        condition.lock()
        guard !stopRequested, !closed else {
            condition.unlock()
            return
        }
        stopRequested = true
        condition.broadcast()
        condition.unlock()
        stopAudioEngine()
    }

    func close() {
        condition.lock()
        guard !closed else {
            condition.unlock()
            return
        }
        closed = true
        stopRequested = true
        condition.broadcast()
        condition.unlock()
        stopAudioEngine()
        SpeechAudioSession.deactivate()
    }

    private var availableSampleCount: Int {
        samples.count - readOffset
    }

    private func enqueue(_ converted: [Int16]) {
        guard !converted.isEmpty else {
            return
        }
        condition.lock()
        guard !stopRequested, !closed else {
            condition.unlock()
            return
        }
        samples.append(contentsOf: converted)
        condition.signal()
        condition.unlock()
    }

    private func recordConversionFailure() {
        condition.lock()
        conversionFailed = true
        condition.broadcast()
        condition.unlock()
    }

    private func compactConsumedSamplesIfNeeded() {
        guard readOffset > 8_192,
              readOffset * 2 >= samples.count else {
            return
        }
        samples.removeFirst(readOffset)
        readOffset = 0
    }

    private func stopAudioEngine() {
        condition.lock()
        let shouldRemoveTap = tapInstalled
        tapInstalled = false
        let wasStarted = started
        started = false
        condition.unlock()
        if wasStarted {
            engine.stop()
        }
        if shouldRemoveTap {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private static func microphonePermissionGranted() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
