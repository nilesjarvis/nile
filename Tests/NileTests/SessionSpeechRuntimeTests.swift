import XCTest
@testable import Nile

@MainActor
final class SessionSpeechRuntimeTests: XCTestCase {
    func testStandardReplyOwnsSanitizationAndPlayback() async {
        let repository = SpeechRuntimeRepository(
            result: .success(
                SynthesizedSpeech(
                    mimeType: "audio/mpeg",
                    bytes: Data([1, 2, 3]),
                    provider: "edge"
                )
            )
        )
        let output = SpeechRuntimeOutput()
        let runtime = SessionSpeechRuntime(
            repository: repository,
            output: output
        )
        let owner = playbackOwner
        var failure: SessionSpeechRuntime.Failure?

        runtime.setStandardRepliesEnabled(true)
        runtime.playStandardReply(
            "**Answer** with [details](https://example.com).\n\nMEDIA:/tmp/private.png",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onFailure: { failure = $0 }
        )

        await eventually { output.played.count == 1 }
        let synthesizedTexts = await repository.synthesizedTexts
        XCTAssertEqual(
            synthesizedTexts,
            ["Answer with details."]
        )
        XCTAssertEqual(output.played.first?.mimeType, "audio/mpeg")
        XCTAssertNil(failure)
        XCTAssertTrue(runtime.standardRepliesEnabled)
    }

    func testUnavailableStandardReplyDisablesToggleAndReportsFailure() async {
        let repository = SpeechRuntimeRepository(
            result: .failure(SpeechSynthesisUnavailableError())
        )
        let runtime = SessionSpeechRuntime(
            repository: repository,
            output: SpeechRuntimeOutput()
        )
        let owner = playbackOwner
        var failure: SessionSpeechRuntime.Failure?

        runtime.setStandardRepliesEnabled(true)
        runtime.playStandardReply(
            "Reply",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onFailure: { failure = $0 }
        )

        await eventually { failure != nil }
        XCTAssertFalse(runtime.standardRepliesEnabled)
        XCTAssertEqual(
            failure,
            SessionSpeechRuntime.Failure(
                description:
                    "This Hermes server does not support spoken replies",
                synthesisUnavailable: true
            )
        )
    }

    func testTalkPlaybackPublishesReadyThenStoppedWithoutCompletion() async {
        let repository = SpeechRuntimeRepository(
            result: .success(
                SynthesizedSpeech(
                    mimeType: "audio/wav",
                    bytes: Data([7]),
                    provider: nil
                )
            )
        )
        let output = SpeechRuntimeOutput(result: .stopped)
        let runtime = SessionSpeechRuntime(
            repository: repository,
            output: output
        )
        let owner = playbackOwner
        var events: [String] = []

        runtime.playTalkReply(
            "Hermes reply",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onPreparing: {
                events.append("preparing")
                return true
            },
            onPlaybackReady: {
                events.append("ready")
                return true
            },
            onCompleted: { events.append("completed") },
            onStopped: { events.append("stopped") },
            onFailure: { _ in events.append("failed") }
        )

        await eventually { events.count == 3 }
        XCTAssertEqual(events, ["preparing", "ready", "stopped"])
        XCTAssertEqual(output.played.count, 1)
    }

    func testStopCancelsInFlightSynthesisBeforePlayback() async {
        let repository = BlockingSpeechRuntimeRepository()
        let output = SpeechRuntimeOutput()
        let runtime = SessionSpeechRuntime(
            repository: repository,
            output: output
        )
        let owner = playbackOwner
        var started = repository.synthesisStarted.makeAsyncIterator()

        runtime.setStandardRepliesEnabled(true)
        runtime.playStandardReply(
            "Reply",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onFailure: { _ in XCTFail("Cancellation is not a failure") }
        )
        _ = await started.next()

        runtime.stop()
        try? await ContinuousClock().sleep(for: .milliseconds(10))

        XCTAssertTrue(output.played.isEmpty)
        XCTAssertGreaterThanOrEqual(output.stopCount, 2)
    }

    private var playbackOwner: SessionSpeechRuntime.Owner {
        SessionSpeechRuntime.Owner(
            gatewayGeneration: 3,
            gatewayID: "gateway-1",
            storedSessionID: "stored-1",
            liveSessionID: "live-1"
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            try? await clock.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition did not become true")
    }
}

private actor SpeechRuntimeRepository: HermesSpeechSynthesisServing {
    private let result: Result<SynthesizedSpeech, any Error>
    private(set) var synthesizedTexts: [String] = []

    init(result: Result<SynthesizedSpeech, any Error>) {
        self.result = result
    }

    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech {
        synthesizedTexts.append(text)
        return try result.get()
    }
}

private actor BlockingSpeechRuntimeRepository: HermesSpeechSynthesisServing {
    nonisolated let synthesisStarted: AsyncStream<Void>
    private let synthesisStartedContinuation:
        AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream()
        synthesisStarted = pair.stream
        synthesisStartedContinuation = pair.continuation
    }

    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech {
        synthesisStartedContinuation.yield()
        try await Task.sleep(for: .seconds(60))
        return SynthesizedSpeech(
            mimeType: "audio/mpeg",
            bytes: Data([1]),
            provider: nil
        )
    }
}

@MainActor
private final class SpeechRuntimeOutput: SpeechOutput {
    struct Played: Equatable {
        let bytes: Data
        let mimeType: String
    }

    private let result: SpeechPlaybackResult
    private(set) var played: [Played] = []
    private(set) var stopCount = 0

    init(result: SpeechPlaybackResult = .completed) {
        self.result = result
    }

    func play(
        audioBytes: Data,
        mimeType: String
    ) async throws -> SpeechPlaybackResult {
        played.append(Played(bytes: audioBytes, mimeType: mimeType))
        return result
    }

    func stop() {
        stopCount += 1
    }
}
