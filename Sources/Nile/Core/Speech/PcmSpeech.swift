import Foundation

let speechSampleRateHz = 16_000
let speechReadSamples = 1_600

struct PcmVoiceActivityDetector: Sendable {
    private let minimumSpeechRMS: Double
    private let noiseMultiplier: Double
    private let speechStartFrames: Int
    private var noiseFloor: Double
    private var consecutiveSpeechFrames = 0

    private(set) var heardSpeech = false
    private(set) var lastSpeechAtMilliseconds: Int64?

    init(
        minimumSpeechRMS: Double = 500,
        noiseMultiplier: Double = 2.5,
        initialNoiseFloor: Double = 200,
        speechStartFrames: Int = 2
    ) {
        precondition(minimumSpeechRMS > 0)
        precondition(noiseMultiplier > 1)
        precondition(initialNoiseFloor >= 0)
        precondition(speechStartFrames > 0)
        self.minimumSpeechRMS = minimumSpeechRMS
        self.noiseMultiplier = noiseMultiplier
        self.speechStartFrames = speechStartFrames
        noiseFloor = initialNoiseFloor
    }

    @discardableResult
    mutating func accept(
        samples: [Int16],
        count: Int,
        nowMilliseconds: Int64
    ) -> Bool {
        precondition((0...samples.count).contains(count))
        guard count > 0 else {
            return false
        }
        var sumSquares = 0.0
        for index in 0..<count {
            let sample = Double(samples[index])
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Double(count))
        if !heardSpeech {
            let threshold = max(
                minimumSpeechRMS,
                noiseFloor * noiseMultiplier
            )
            if rms >= threshold {
                consecutiveSpeechFrames += 1
                if consecutiveSpeechFrames >= speechStartFrames {
                    heardSpeech = true
                    lastSpeechAtMilliseconds = nowMilliseconds
                    return true
                }
            } else {
                consecutiveSpeechFrames = 0
                noiseFloor = noiseFloor * 0.95 + rms * 0.05
            }
            return false
        }

        let continuationThreshold = max(
            minimumSpeechRMS * 0.55,
            noiseFloor * 1.5
        )
        let speech = rms >= continuationThreshold
        if speech {
            lastSpeechAtMilliseconds = nowMilliseconds
        }
        return speech
    }
}

enum PcmWavEncoder {
    static func encode(
        samples: [Int16],
        count: Int,
        sampleRateHz: Int = speechSampleRateHz
    ) -> Data {
        precondition(
            (0...samples.count).contains(count),
            "PCM sample count is out of bounds"
        )
        precondition(sampleRateHz > 0, "Sample rate must be positive")
        let dataBytes = count * MemoryLayout<Int16>.size
        var output = Data(capacity: 44 + dataBytes)
        output.appendASCII("RIFF")
        output.appendLittleEndian(UInt32(36 + dataBytes))
        output.appendASCII("WAVE")
        output.appendASCII("fmt ")
        output.appendLittleEndian(UInt32(16))
        output.appendLittleEndian(UInt16(1))
        output.appendLittleEndian(UInt16(1))
        output.appendLittleEndian(UInt32(sampleRateHz))
        output.appendLittleEndian(
            UInt32(sampleRateHz * MemoryLayout<Int16>.size)
        )
        output.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        output.appendLittleEndian(UInt16(16))
        output.appendASCII("data")
        output.appendLittleEndian(UInt32(dataBytes))
        for sample in samples.prefix(count) {
            output.appendLittleEndian(UInt16(bitPattern: sample))
        }
        return output
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
