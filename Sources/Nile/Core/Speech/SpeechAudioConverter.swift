@preconcurrency import AVFoundation
import Foundation

final class SpeechAudioConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(speechSampleRateHz),
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(
                  from: inputFormat,
                  to: targetFormat
              ) else {
            throw HermesError(
                "16 kHz microphone capture is unavailable",
                retryable: false
            )
        }
        self.converter = converter
        self.targetFormat = targetFormat
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> [Int16] {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, ceil(Double(input.frameLength) * ratio) + 32)
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw HermesError(
                "Microphone audio conversion failed",
                retryable: false
            )
        }
        let inputProvider = SpeechConverterInput(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }
        if status == .error {
            throw conversionError ?? HermesError(
                "Microphone audio conversion failed",
                retryable: false
            )
        }
        guard output.frameLength > 0,
              let channel = output.int16ChannelData?[0] else {
            return []
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(output.frameLength)
            )
        )
    }
}

private final class SpeechConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !supplied else {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}
