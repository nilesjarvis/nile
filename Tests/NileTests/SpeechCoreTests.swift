@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import Nile

final class SpeechCoreTests: XCTestCase {
    func testSanitizerRemovesPresentationSyntaxAndKeepsReadableText() {
        XCTAssertEqual(
            sanitizeTextForSpeech(
                "# Result\nUse [the docs](https://docs.example) and `value` at https://example.com 😀"
            ),
            "Result Use the docs and value at link"
        )
        XCTAssertEqual(
            sanitizeTextForSpeech(
                "Thinking... Before.\n```kotlin\nsecret()\n```\nAfter."
            ),
            "Before. After."
        )
        XCTAssertEqual(
            sanitizeTextForSpeech(
                "A hyphen-\nated word.\n\nNext paragraph."
            ),
            "A hyphenated word. Next paragraph."
        )
    }

    func testSpeechChunkingUsesNaturalBoundariesAndPreservesUTF16Pairs() {
        let text =
            "First sentence is comfortably long. "
            + "Second sentence also has several words. "
            + "A final sentence closes the reply."
        let chunks = chunkTextForSpeech(text, maxCharacters: 48)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(
            chunks.allSatisfy { ($0 as NSString).length <= 48 }
        )
        XCTAssertEqual(chunks.joined(separator: " "), text)

        let paired = "abc\u{1F600}defgh"
        let pairedChunks = chunkTextForSpeech(
            paired,
            maxCharacters: 4
        )
        XCTAssertEqual(pairedChunks.joined(), paired)
        for chunk in pairedChunks {
            let utf16 = chunk as NSString
            XCTAssertFalse(isTestLowSurrogate(utf16.character(at: 0)))
            XCTAssertFalse(
                isTestHighSurrogate(
                    utf16.character(at: utf16.length - 1)
                )
            )
        }
    }

    func testVoiceActivityDetectorMatchesPinnedRMSContract() {
        var detector = PcmVoiceActivityDetector()
        let loud = [Int16](repeating: 1_500, count: speechReadSamples)
        let quiet = [Int16](repeating: 0, count: speechReadSamples)

        XCTAssertFalse(
            detector.accept(
                samples: quiet,
                count: quiet.count,
                nowMilliseconds: 100
            )
        )
        XCTAssertFalse(
            detector.accept(
                samples: loud,
                count: loud.count,
                nowMilliseconds: 200
            )
        )
        XCTAssertTrue(
            detector.accept(
                samples: loud,
                count: loud.count,
                nowMilliseconds: 300
            )
        )
        XCTAssertTrue(detector.heardSpeech)
        XCTAssertEqual(detector.lastSpeechAtMilliseconds, 300)
        XCTAssertFalse(
            detector.accept(
                samples: quiet,
                count: quiet.count,
                nowMilliseconds: 400
            )
        )
        XCTAssertEqual(detector.lastSpeechAtMilliseconds, 300)
    }

    func testWavEncoderWritesCanonicalPCMHeaderAndSamples() {
        let bytes = PcmWavEncoder.encode(
            samples: [0x0102, -2],
            count: 2
        )
        XCTAssertEqual(
            String(data: bytes.subdata(in: 0..<4), encoding: .ascii),
            "RIFF"
        )
        XCTAssertEqual(
            String(data: bytes.subdata(in: 8..<12), encoding: .ascii),
            "WAVE"
        )
        XCTAssertEqual(bytes.readLittleEndianUInt32(at: 24), 16_000)
        XCTAssertEqual(bytes.readLittleEndianUInt32(at: 40), 4)
        XCTAssertEqual(bytes.readLittleEndianInt16(at: 44), 0x0102)
        XCTAssertEqual(bytes.readLittleEndianInt16(at: 46), -2)
    }

    func testSpeechAudioConverterProduces16KHzMonoInt16Samples() throws {
        guard let inputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(speechSampleRateHz),
            channels: 1
        ),
        let input = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 128
        ),
        let channel = input.floatChannelData?[0] else {
            XCTFail("Could not allocate the speech conversion fixture")
            return
        }
        input.frameLength = 128
        for index in 0..<Int(input.frameLength) {
            channel[index] = index.isMultiple(of: 2) ? 0.25 : -0.25
        }

        let samples = try SpeechAudioConverter(
            inputFormat: inputFormat
        ).convert(input)

        XCTAssertEqual(samples.count, Int(input.frameLength))
        XCTAssertGreaterThan(Int(samples[0]), 5_000)
        XCTAssertLessThan(Int(samples[1]), -5_000)
    }

    func testPlatformSpeechSourcesSeparateSessionConversionAndContracts()
        throws
    {
        let speechDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/Nile/Core/Speech",
                isDirectory: true
            )
        let boundaries: [(
            file: String, markers: [String], limit: Int
        )] = [
            (
                "AVAudioEnginePcmSource.swift",
                [
                    "final class AVAudioEnginePcmSource:",
                    "private let engine = AVAudioEngine()",
                    "SpeechAudioSession.activateRecording()",
                    "SpeechAudioConverter(",
                ],
                220
            ),
            (
                "SpeechAudioConverter.swift",
                [
                    "final class SpeechAudioConverter:",
                    "private let converter: AVAudioConverter",
                    "private final class SpeechConverterInput:",
                    "func convert(",
                ],
                110
            ),
            (
                "SpeechAudioSession.swift",
                [
                    "enum SpeechAudioSession {",
                    "static func activateRecording()",
                    "static func activatePlayback()",
                    "static func deactivate()",
                    "mode: .measurement",
                    "options: [.allowBluetoothHFP]",
                    "setPreferredSampleRate(",
                    "setPreferredIOBufferDuration(0.1)",
                    "mode: .spokenAudio",
                    "options: [.duckOthers]",
                    "options: [.notifyOthersOnDeactivation]",
                ],
                50
            ),
            (
                "SpeechOutput.swift",
                [
                    "final class AVSpeechOutput:",
                    "private var activePlayback:",
                    "private func armWatchdog(",
                    "SpeechAudioSession.activatePlayback()",
                ],
                285
            ),
            (
                "SpeechOutputContracts.swift",
                [
                    "enum SpeechPlaybackResult:",
                    "protocol SpeechOutput:",
                    "final class NoOpSpeechOutput:",
                ],
                45
            ),
        ]
        let sources = try boundaries.map {
            try String(
                contentsOf: speechDirectory.appendingPathComponent($0.file),
                encoding: .utf8
            )
        }
        for (index, boundary) in boundaries.enumerated() {
            for marker in boundary.markers {
                XCTAssertTrue(sources[index].contains(marker))
            }
            XCTAssertLessThan(
                sources[index].components(separatedBy: .newlines).count,
                boundary.limit
            )
        }
        for declaration in [
            "final class AVAudioEnginePcmSource:",
            "final class SpeechAudioConverter:",
            "enum SpeechAudioSession {",
            "final class AVSpeechOutput:",
            "protocol SpeechOutput:",
        ] {
            XCTAssertEqual(
                sources.filter { $0.contains(declaration) }.count,
                1
            )
        }
        XCTAssertFalse(sources[0].contains("AVAudioConverter"))
        XCTAssertFalse(sources[0].contains(".setCategory("))
        XCTAssertFalse(sources[0].contains(".setActive("))
        XCTAssertFalse(sources[1].contains("AVAudioSession"))
        XCTAssertFalse(sources[2].contains("AVAudioEngine"))
        XCTAssertFalse(sources[2].contains("SpeechPlayback"))
        XCTAssertFalse(sources[3].contains(".setCategory("))
        XCTAssertFalse(sources[3].contains(".setActive("))
        XCTAssertFalse(sources[4].contains("AVAudioSession"))
        XCTAssertFalse(sources[4].contains("Task<"))
        XCTAssertLessThan(
            sources.map { $0.components(separatedBy: .newlines).count }
                .reduce(0, +),
            660
        )
    }

    func testVoiceInputSourcesSeparateRuntimeOperationAndCaptureState()
        throws
    {
        let speechDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/Nile/Core/Speech",
                isDirectory: true
            )
        let boundaries: [(file: String, markers: [String], limit: Int)] = [
            (
                "VoiceInputContracts.swift",
                [
                    "enum VoiceInputEvent:",
                    "protocol VoiceInput:",
                    "final class UnavailableVoiceInput:",
                    "protocol PcmAudioSource:",
                    "typealias PcmAudioSourceFactory",
                    "struct MicrophonePermissionDeniedError:",
                ],
                55
            ),
            (
                "VoiceInput.swift",
                [
                    "final class HermesVoiceInput:",
                    "private let captureOperation:",
                    "private let captureGate = SpeechCaptureGate()",
                    "private func emitTerminal(",
                ],
                175
            ),
            (
                "VoiceInputCaptureOperation.swift",
                [
                    "struct SpeechCaptureOperation: Sendable",
                    "func run(",
                    "PcmWavEncoder.encode(",
                    "func voiceInputFailureMessage(",
                    "enum SpeechCaptureOutcome",
                ],
                225
            ),
            (
                "VoiceInputCapture.swift",
                [
                    "actor SpeechCaptureGate",
                    "final class SpeechCapture:",
                ],
                125
            ),
        ]
        let sources = try boundaries.map {
            try String(
                contentsOf: speechDirectory.appendingPathComponent($0.file),
                encoding: .utf8
            )
        }
        for (index, boundary) in boundaries.enumerated() {
            for marker in boundary.markers {
                XCTAssertTrue(sources[index].contains(marker))
                XCTAssertEqual(sources.filter { $0.contains(marker) }.count, 1)
            }
            XCTAssertLessThan(
                sources[index].components(separatedBy: .newlines).count,
                boundary.limit
            )
        }
        XCTAssertFalse(sources[0].contains("HermesVoiceInput"))
        XCTAssertFalse(sources[0].contains("SpeechCapture"))
        XCTAssertFalse(sources[1].contains("protocol VoiceInput:"))
        XCTAssertFalse(sources[1].contains("actor SpeechCaptureGate"))
        XCTAssertFalse(sources[1].contains("PcmWavEncoder"))
        for forbidden in [
            "HermesVoiceInput", "AsyncStream", "SpeechCaptureGate",
            "stateLock", "activeCapture",
        ] {
            XCTAssertFalse(sources[2].contains(forbidden))
        }
        XCTAssertFalse(sources[3].contains("HermesVoiceInput"))
        XCTAssertFalse(sources[3].contains("PcmWavEncoder"))
        XCTAssertFalse(sources[3].contains("public "))
        XCTAssertLessThan(
            sources.map { $0.components(separatedBy: .newlines).count }
                .reduce(0, +),
            540
        )
    }

    func testNaturalPauseUploadsWavAndEmitsHermesTranscript() async throws {
        let clock = TestSpeechClock()
        let source = ScriptedSpeechAudioSource(
            clock: clock,
            amplitudes: Array(repeating: 1_500, count: 2)
                + Array(repeating: 0, count: 7)
        )
        let requests = RecordedAudioCollector()
        let input = HermesVoiceInput(
            transcribe: { audio in
                await requests.append(audio)
                return SpeechTranscript(
                    text: "Ever tried. Fail better."
                )
            },
            audioSourceFactory: { source },
            elapsedMilliseconds: { clock.now }
        )
        let events = VoiceEventCollector(input: input)

        input.start()
        try await events.waitForCount(4)

        let received = await events.values
        XCTAssertEqual(
            received,
            [
                .preparing,
                .listening(partialText: ""),
                .transcribing,
                .finished(text: "Ever tried. Fail better."),
            ]
        )
        let captured = await requests.values
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].mimeType, "audio/wav")
        XCTAssertEqual(
            captured[0].bytes.readLittleEndianUInt32(at: 24),
            16_000
        )
        XCTAssertEqual(
            captured[0].bytes.readLittleEndianUInt32(at: 40),
            UInt32(9 * speechReadSamples * 2)
        )
        XCTAssertEqual(
            captured[0].bytes.count,
            44 + 9 * speechReadSamples * 2
        )
        XCTAssertTrue(source.isClosed)
        events.cancel()
    }

    func testNoSpeechReturnsBlankWithoutCallingHermes() async throws {
        let clock = TestSpeechClock()
        let source = ScriptedSpeechAudioSource(
            clock: clock,
            amplitudes: Array(repeating: 0, count: 60)
        )
        let requests = RecordedAudioCollector()
        let input = HermesVoiceInput(
            transcribe: { audio in
                await requests.append(audio)
                return SpeechTranscript(text: "should not happen")
            },
            audioSourceFactory: { source },
            elapsedMilliseconds: { clock.now }
        )
        let events = VoiceEventCollector(input: input)

        input.start()
        try await events.waitForCount(3)

        let requestValues = await requests.values
        let received = await events.values
        XCTAssertEqual(requestValues.count, 0)
        XCTAssertEqual(
            received,
            [
                .preparing,
                .listening(partialText: ""),
                .finished(text: ""),
            ]
        )
        XCTAssertTrue(source.isClosed)
        events.cancel()
    }

    func testTranscriptionFailureOccursAfterMicrophoneCloses() async throws {
        let clock = TestSpeechClock()
        let source = ScriptedSpeechAudioSource(
            clock: clock,
            amplitudes: Array(repeating: 1_500, count: 2)
                + Array(repeating: 0, count: 7)
        )
        let microphoneState = RecordedBooleanCollector()
        let input = HermesVoiceInput(
            transcribe: { _ in
                await microphoneState.append(source.isClosed)
                throw SpeechTranscriptionUnavailableError()
            },
            audioSourceFactory: { source },
            elapsedMilliseconds: { clock.now }
        )
        let events = VoiceEventCollector(input: input)

        input.start()
        try await events.waitForCount(4)

        XCTAssertTrue(source.isClosed)
        let microphoneStates = await microphoneState.values
        XCTAssertEqual(microphoneStates, [true])
        let received = await events.values
        XCTAssertEqual(
            received,
            [
                .preparing,
                .listening(partialText: ""),
                .transcribing,
                .error(
                    message:
                        "Hermes voice transcription is unavailable"
                ),
            ]
        )
        events.cancel()
    }

    func testCancelDuringTranscriptionRejectsLatePrivateResult() async throws {
        let clock = TestSpeechClock()
        let source = ScriptedSpeechAudioSource(
            clock: clock,
            amplitudes: Array(repeating: 1_500, count: 2)
                + Array(repeating: 0, count: 7)
        )
        let gate = SpeechTestGate()
        let input = HermesVoiceInput(
            transcribe: { _ in
                await gate.wait()
                return SpeechTranscript(
                    text: "late private transcript"
                )
            },
            audioSourceFactory: { source },
            elapsedMilliseconds: { clock.now }
        )
        let events = VoiceEventCollector(input: input)

        input.start()
        try await events.waitForCount(3)
        let transcribingEvents = await events.values
        XCTAssertEqual(transcribingEvents.last, .transcribing)

        input.cancel()
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))

        let received = await events.values
        XCTAssertEqual(
            received,
            [
                .preparing,
                .listening(partialText: ""),
                .transcribing,
            ]
        )
        events.cancel()
    }

    func testCancelSynchronouslyClosesBlockingMicrophone() async throws {
        let source = BlockingSpeechAudioSource()
        let input = HermesVoiceInput(
            transcribe: { _ in SpeechTranscript(text: "unused") },
            audioSourceFactory: { source },
            elapsedMilliseconds: { 0 }
        )
        let events = VoiceEventCollector(input: input)
        input.start()
        XCTAssertTrue(source.waitUntilReadEntered(timeout: 2))

        input.cancel()
        XCTAssertTrue(source.isClosed)
        try await events.waitForCount(2)
        try await Task.sleep(for: .milliseconds(20))

        let received = await events.values
        XCTAssertEqual(
            received,
            [
                .preparing,
                .listening(partialText: ""),
            ]
        )
        events.cancel()
    }

    func testUnavailableInputEmitsActionableError() async throws {
        let input = HermesVoiceInput(
            transcribe: { _ in SpeechTranscript(text: "") },
            audioSourceFactory: {
                ScriptedSpeechAudioSource(
                    clock: TestSpeechClock(),
                    amplitudes: []
                )
            },
            isAvailable: false
        )
        let events = VoiceEventCollector(input: input)

        input.start()
        try await events.waitForCount(1)

        let received = await events.values
        XCTAssertEqual(
            received,
            [
                .error(
                    message:
                        "Voice input is unavailable on this device"
                ),
            ]
        )
        events.cancel()
    }
}

private actor RecordedAudioCollector {
    private(set) var values: [RecordedAudio] = []

    func append(_ audio: RecordedAudio) {
        values.append(audio)
    }
}

private actor RecordedBooleanCollector {
    private(set) var values: [Bool] = []

    func append(_ value: Bool) {
        values.append(value)
    }
}

private actor VoiceEventStorage {
    private(set) var values: [VoiceInputEvent] = []

    func append(_ event: VoiceInputEvent) {
        values.append(event)
    }
}

private final class VoiceEventCollector: @unchecked Sendable {
    private let storage = VoiceEventStorage()
    private var task: Task<Void, Never>?

    init(input: any VoiceInput) {
        let storage = storage
        task = Task {
            for await event in input.events {
                await storage.append(event)
            }
        }
    }

    var values: [VoiceInputEvent] {
        get async {
            await storage.values
        }
    }

    func waitForCount(_ count: Int) async throws {
        for _ in 0..<200 {
            if await storage.values.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(count) voice events")
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private final class TestSpeechClock: @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: Int64 = 0

    var now: Int64 {
        lock.withLock { milliseconds }
    }

    func advance(milliseconds: Int64) {
        lock.withLock {
            self.milliseconds += milliseconds
        }
    }
}

private final class ScriptedSpeechAudioSource:
    PcmAudioSource,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let clock: TestSpeechClock
    private let amplitudes: [Int]
    private var readIndex = 0
    private var started = false
    private var closed = false

    init(clock: TestSpeechClock, amplitudes: [Int]) {
        self.clock = clock
        self.amplitudes = amplitudes
    }

    var isClosed: Bool {
        lock.withLock { closed }
    }

    func start() throws {
        lock.withLock {
            precondition(!closed)
            started = true
        }
    }

    func read(_ samples: inout [Int16]) -> Int {
        let amplitude: Int16 = lock.withLock {
            precondition(started && !closed)
            defer { readIndex += 1 }
            return Int16(
                amplitudes.indices.contains(readIndex)
                    ? amplitudes[readIndex]
                    : 0
            )
        }
        samples = [Int16](repeating: amplitude, count: samples.count)
        clock.advance(milliseconds: 100)
        return samples.count
    }

    func stop() {
        lock.withLock {
            started = false
        }
    }

    func close() {
        lock.withLock {
            started = false
            closed = true
        }
    }
}

private final class BlockingSpeechAudioSource:
    PcmAudioSource,
    @unchecked Sendable
{
    private let condition = NSCondition()
    private var readEntered = false
    private var closed = false

    var isClosed: Bool {
        condition.withLock { closed }
    }

    func start() throws {}

    func read(_ samples: inout [Int16]) -> Int {
        condition.lock()
        readEntered = true
        condition.broadcast()
        while !closed {
            condition.wait()
        }
        condition.unlock()
        return -1
    }

    func stop() {}

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    func waitUntilReadEntered(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        while !readEntered {
            guard condition.wait(until: deadline) else {
                condition.unlock()
                return false
            }
        }
        condition.unlock()
        return true
    }
}

private actor SpeechTestGate {
    private var openState = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !openState else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        openState = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private extension Data {
    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        self.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) -> UInt32 in
            let byte0 = UInt32(
                raw.load(fromByteOffset: offset, as: UInt8.self)
            )
            let byte1 = UInt32(
                raw.load(fromByteOffset: offset + 1, as: UInt8.self)
            )
            let byte2 = UInt32(
                raw.load(fromByteOffset: offset + 2, as: UInt8.self)
            )
            let byte3 = UInt32(
                raw.load(fromByteOffset: offset + 3, as: UInt8.self)
            )
            return byte0 | byte1 << 8 | byte2 << 16 | byte3 << 24
        }
    }

    func readLittleEndianInt16(at offset: Int) -> Int16 {
        let value = self.withUnsafeBytes {
            (raw: UnsafeRawBufferPointer) -> UInt16 in
            let byte0 = UInt16(
                raw.load(fromByteOffset: offset, as: UInt8.self)
            )
            let byte1 = UInt16(
                raw.load(fromByteOffset: offset + 1, as: UInt8.self)
            )
            return byte0 | byte1 << 8
        }
        return Int16(bitPattern: value)
    }
}

private func isTestHighSurrogate(_ value: unichar) -> Bool {
    (0xD800...0xDBFF).contains(value)
}

private func isTestLowSurrogate(_ value: unichar) -> Bool {
    (0xDC00...0xDFFF).contains(value)
}
