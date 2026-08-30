import XCTest
@testable import Nile

@MainActor
final class SessionTalkRuntimeTests: XCTestCase {
    func testStartDoesNotTakeOverExistingVoiceActivity() {
        let fixture = makeRuntime(
            repository: ImmediateTalkRuntimeRepository()
        )
        var error: String?

        fixture.runtime.start(
            voiceInputAvailable: true,
            environment: activeEnvironment,
            otherVoiceActivity: true,
            onError: { error = $0 }
        )

        XCTAssertFalse(fixture.runtime.isActive)
        XCTAssertNil(fixture.runtime.presentation)
        XCTAssertEqual(fixture.voice.startCount, 0)
        XCTAssertNil(error)
    }

    func testTerminalBeforeSubmitAdmissionPausesUncorrelatedTurn() async {
        let repository = BlockingTalkRuntimeRepository()
        let fixture = makeRuntime(repository: repository)
        let environment = activeEnvironment
        var submissions: [SessionTalkRuntime.Submission] = []
        var started = repository.submitStarted.makeAsyncIterator()

        fixture.runtime.start(
            voiceInputAvailable: true,
            environment: environment,
            otherVoiceActivity: false,
            onError: { _ in }
        )
        consume(
            .listening(partialText: "private partial"),
            with: fixture.runtime,
            environment: { environment },
            onSubmissionStarted: { submissions.append($0) }
        )
        consume(
            .finished(text: "send exactly once"),
            with: fixture.runtime,
            environment: { environment },
            onSubmissionStarted: { submissions.append($0) }
        )
        _ = await started.next()

        fixture.runtime.noteTerminalBeforeAdmission(liveSessionID: "live-1")
        XCTAssertTrue(
            fixture.runtime.handleAssistantCompleted(
                liveSessionID: "live-1",
                rawText: "must not be spoken",
                completionWasStopping: false,
                environmentProvider: { environment },
                onError: { _ in }
            )
        )
        await repository.resolveSubmit(with: .streaming)

        await eventually {
            fixture.runtime.presentation?.phase == .paused
        }
        XCTAssertEqual(submissions.map(\.text), ["send exactly once"])
        XCTAssertEqual(
            fixture.runtime.presentation?.message,
            "Talk paused because a reply arrived before Nile could safely match it to your utterance. Check the transcript before continuing."
        )
    }

    func testStopSettlementResumesOnlyTheInterruptedTalkMode() async {
        let repository = ImmediateTalkRuntimeRepository()
        let fixture = makeRuntime(
            repository: repository,
            relistenDelay: .zero
        )
        let environment = activeEnvironment
        var stopRequests = 0

        fixture.runtime.start(
            voiceInputAvailable: true,
            environment: environment,
            otherVoiceActivity: false,
            onError: { _ in }
        )
        consume(
            .listening(partialText: ""),
            with: fixture.runtime,
            environment: { environment }
        )
        consume(
            .finished(text: "interrupt this"),
            with: fixture.runtime,
            environment: { environment }
        )
        await eventually {
            fixture.runtime.presentation?.phase == .working
        }

        fixture.runtime.interruptSpeech(
            remoteTurnActive: true,
            environmentProvider: { environment },
            onStopRequested: { stopRequests += 1 }
        )
        fixture.runtime.handleStopSucceeded(
            environmentProvider: { environment }
        )

        await eventually { fixture.voice.startCount == 2 }
        XCTAssertEqual(stopRequests, 1)
        XCTAssertEqual(fixture.runtime.presentation?.phase, .preparingInput)
        XCTAssertTrue(fixture.runtime.isActive)
    }

    func testRelistenInvalidatesWhenOwnerChanges() async {
        let fixture = makeRuntime(
            repository: ImmediateTalkRuntimeRepository(),
            relistenDelay: .milliseconds(1)
        )
        let environment = TalkRuntimeEnvironmentBox(activeEnvironment)

        fixture.runtime.start(
            voiceInputAvailable: true,
            environment: environment.value,
            otherVoiceActivity: false,
            onError: { _ in }
        )
        consume(
            .listening(partialText: ""),
            with: fixture.runtime,
            environment: { environment.value }
        )
        consume(
            .finished(text: ""),
            with: fixture.runtime,
            environment: { environment.value }
        )
        environment.value = SessionTalkRuntime.Environment(
            owner: nil,
            canListen: false,
            isForeground: true
        )

        await eventually { !fixture.runtime.isActive }
        XCTAssertNil(fixture.runtime.presentation)
        XCTAssertEqual(fixture.voice.startCount, 1)
    }

    func testRelistenRuntimeReplacementExecutesOnlyLatestOperation() async {
        let runtime = SessionTalkRelistenRuntime(delay: .zero)
        var executions: [String] = []

        runtime.replace { executions.append("stale") }
        runtime.replace { executions.append("latest") }

        await eventually { executions == ["latest"] }
    }

    func testRelistenRuntimeCancellationSuppressesPendingOperation() async {
        let runtime = SessionTalkRelistenRuntime(delay: .zero)
        var executed = false

        runtime.replace { executed = true }
        runtime.cancel()
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(executed)
    }

    private func makeRuntime(
        repository: any HermesTalkServing,
        relistenDelay: Duration = .milliseconds(300)
    ) -> (runtime: SessionTalkRuntime, voice: TalkRuntimeVoiceInput) {
        let voice = TalkRuntimeVoiceInput()
        let voiceRuntime = SessionVoiceInputRuntime(
            repository: nil,
            input: voice
        )
        let speech = SessionSpeechRuntime(
            repository: nil,
            output: NoOpSpeechOutput()
        )
        return (
            SessionTalkRuntime(
                repository: repository,
                voice: voiceRuntime,
                speech: speech,
                relistenDelay: relistenDelay
            ),
            voice
        )
    }

    private var activeEnvironment: SessionTalkRuntime.Environment {
        SessionTalkRuntime.Environment(
            owner: TalkOwner(
                connectionGeneration: 3,
                gatewayID: "gateway-1",
                gatewayKey: "gateway-1",
                selectedSessionID: "stored-1",
                transcriptSessionID: "stored-1",
                liveSessionID: "live-1"
            ),
            canListen: true,
            isForeground: true
        )
    }

    private func consume(
        _ event: VoiceInputEvent,
        with runtime: SessionTalkRuntime,
        environment: @escaping SessionTalkRuntime.EnvironmentProvider,
        onSubmissionStarted: @escaping SessionTalkRuntime.SubmissionHandler = {
            _ in
        }
    ) {
        XCTAssertTrue(
            runtime.consumeVoiceEvent(
                event,
                environmentProvider: environment,
                onSubmissionStarted: onSubmissionStarted,
                onSubmissionFailed: { _ in
                    XCTFail("Submission should not fail")
                },
                onError: { _ in }
            )
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

private actor ImmediateTalkRuntimeRepository: HermesTalkServing {
    func liveRuntimeStatus(liveSessionID: String) async throws -> String? {
        nil
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        .streaming
    }
}

@MainActor
private final class TalkRuntimeEnvironmentBox {
    var value: SessionTalkRuntime.Environment

    init(_ value: SessionTalkRuntime.Environment) {
        self.value = value
    }
}

private actor BlockingTalkRuntimeRepository: HermesTalkServing {
    nonisolated let submitStarted: AsyncStream<Void>
    private let submitStartedContinuation: AsyncStream<Void>.Continuation
    private var submitContinuation:
        CheckedContinuation<PromptSubmitStatus, any Error>?

    init() {
        let pair = AsyncStream<Void>.makeStream()
        submitStarted = pair.stream
        submitStartedContinuation = pair.continuation
    }

    func liveRuntimeStatus(liveSessionID: String) async throws -> String? {
        nil
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        submitStartedContinuation.yield()
        return try await withCheckedThrowingContinuation { continuation in
            submitContinuation = continuation
        }
    }

    func resolveSubmit(with status: PromptSubmitStatus) {
        submitContinuation?.resume(returning: status)
        submitContinuation = nil
    }
}

private final class TalkRuntimeVoiceInput: VoiceInput, @unchecked Sendable {
    let isAvailable = true
    let events: AsyncStream<VoiceInputEvent>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init() {
        events = AsyncStream { _ in }
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func cancel() {
        cancelCount += 1
    }
}
