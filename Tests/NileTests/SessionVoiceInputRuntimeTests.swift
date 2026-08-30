import Observation
import XCTest
@testable import Nile

@MainActor
final class SessionVoiceInputRuntimeTests: XCTestCase {
    func testDraftRoutingPreservesBaseAndPublishesPhases() async {
        let input = VoiceRuntimeInput()
        let runtime = SessionVoiceInputRuntime(
            repository: nil,
            input: input
        )
        var composers: [String] = []
        var errors: [String] = []
        runtime.beginRouting(
            consumeTalkEvent: { _ in false },
            onComposerChanged: { composers.append($0) },
            onError: { errors.append($0) }
        )

        runtime.startDraft(composer: "Existing draft")
        input.emit(.preparing)
        input.emit(.listening(partialText: "spoken words"))

        await eventually {
            runtime.isDraftListening
                && composers == ["Existing draft spoken words"]
        }
        input.emit(.transcribing)
        await eventually {
            runtime.isDraftTranscribing && !runtime.isDraftListening
        }
        input.emit(.finished(text: "final words"))
        await eventually {
            !runtime.eventsAreEnabled
                && !runtime.isDraftListening
                && !runtime.isDraftTranscribing
                && composers.last == "Existing draft final words"
        }

        XCTAssertEqual(input.startCount, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testTalkHandlerPreemptsOrdinaryDraftProjection() async {
        let input = VoiceRuntimeInput()
        let runtime = SessionVoiceInputRuntime(
            repository: nil,
            input: input
        )
        var talkEvents: [VoiceInputEvent] = []
        var composers: [String] = []
        runtime.beginRouting(
            consumeTalkEvent: {
                talkEvents.append($0)
                return true
            },
            onComposerChanged: { composers.append($0) },
            onError: { _ in }
        )

        runtime.startCapture(composer: "")
        input.emit(.listening(partialText: "private partial"))

        await eventually { talkEvents.count == 1 }
        XCTAssertEqual(
            talkEvents,
            [.listening(partialText: "private partial")]
        )
        XCTAssertTrue(composers.isEmpty)
        XCTAssertFalse(runtime.isDraftListening)
        XCTAssertFalse(runtime.isDraftTranscribing)
    }

    func testCancelClearsPresentationAndRejectsLateDraftEvent() async {
        let input = VoiceRuntimeInput()
        let runtime = SessionVoiceInputRuntime(
            repository: nil,
            input: input
        )
        var composers: [String] = []
        runtime.beginRouting(
            consumeTalkEvent: { _ in false },
            onComposerChanged: { composers.append($0) },
            onError: { _ in }
        )

        runtime.startDraft(composer: "Draft")
        input.emit(.listening(partialText: "accepted"))
        await eventually { runtime.isDraftListening }

        runtime.cancelCapture()
        input.emit(.finished(text: "late"))
        try? await ContinuousClock().sleep(for: .milliseconds(10))

        XCTAssertEqual(composers, ["Draft accepted"])
        XCTAssertFalse(runtime.eventsAreEnabled)
        XCTAssertFalse(runtime.isDraftListening)
        XCTAssertFalse(runtime.isDraftTranscribing)
        XCTAssertEqual(input.cancelCount, 1)
    }

    func testRepositoryBackedDefaultAndNilRepositoryAvailability() {
        let available = SessionVoiceInputRuntime(
            repository: VoiceRuntimeRepository()
        )
        let unavailable = SessionVoiceInputRuntime(repository: nil)

        XCTAssertTrue(available.isAvailable)
        XCTAssertFalse(unavailable.isAvailable)
    }

    func testModelForwarderPublishesNestedRuntimeObservation() async {
        let input = VoiceRuntimeInput()
        let model = SessionListModel(
            fixture: .androidBrand,
            voiceInput: input
        )
        model.onAppForegroundChanged(true)
        let changed = expectation(description: "Voice observation changed")

        withObservationTracking {
            _ = model.isListening
        } onChange: {
            changed.fulfill()
        }

        model.startVoiceInput()
        input.emit(.listening(partialText: "spoken words"))

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(model.isListening)
        XCTAssertEqual(model.composer, "spoken words")
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

private actor VoiceRuntimeRepository: HermesTranscriptionServing {}

private final class VoiceRuntimeInput: VoiceInput, @unchecked Sendable {
    let isAvailable = true
    let events: AsyncStream<VoiceInputEvent>
    private let continuation: AsyncStream<VoiceInputEvent>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    init() {
        let pair = AsyncStream.makeStream(
            of: VoiceInputEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        events = pair.stream
        continuation = pair.continuation
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

    func emit(_ event: VoiceInputEvent) {
        continuation.yield(event)
    }
}
