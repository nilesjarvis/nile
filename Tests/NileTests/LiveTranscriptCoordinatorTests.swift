import XCTest
@testable import Nile

final class LiveTranscriptCoordinatorTests: XCTestCase {
    func testDeltaCoalescerCapsBurstPublicationsAtCadence() {
        var coalescer = AssistantDeltaEventCoalescer()
        var publications: [HermesStreamEvent] = []

        for tick in 0..<4 {
            for fragment in 0..<30 {
                let emitted = coalescer.receive(
                    .assistantDelta(
                        sessionID: "live-one",
                        text: "\(tick)-\(fragment);"
                    )
                )
                XCTAssertTrue(emitted.isEmpty)
            }
            if let publication = coalescer.flush() {
                publications.append(publication)
            }
        }

        XCTAssertEqual(
            AssistantDeltaEventCoalescer.maximumPublicationsPerSecond,
            30
        )
        XCTAssertEqual(publications.count, 4)
        let publishedText = publications.compactMap { event -> String? in
            guard case let .assistantDelta(sessionID, text) = event else {
                return nil
            }
            XCTAssertEqual(sessionID, "live-one")
            return text
        }.joined()
        let expectedText = (0..<4).flatMap { tick in
            (0..<30).map { fragment in "\(tick)-\(fragment);" }
        }.joined()
        XCTAssertEqual(publishedText, expectedText)
    }

    func testDeltaCoalescerFlushesBeforeOrderedStructuralEvents() {
        var coalescer = AssistantDeltaEventCoalescer()

        _ = coalescer.receive(
            .assistantDelta(sessionID: "live-one", text: "hello ")
        )
        _ = coalescer.receive(
            .assistantDelta(sessionID: "live-one", text: "there")
        )
        let completion = HermesStreamEvent.assistantCompleted(
            sessionID: "live-one",
            text: "hello there!",
            usage: nil
        )

        let emitted = coalescer.receive(completion)

        XCTAssertEqual(emitted, [
            .assistantDelta(sessionID: "live-one", text: "hello there"),
            completion,
        ])
        let pending = coalescer.flush()
        XCTAssertNil(pending)
    }

    func testDeltaCoalescerDoesNotMergeAcrossSessions() {
        var coalescer = AssistantDeltaEventCoalescer()

        _ = coalescer.receive(
            .assistantDelta(sessionID: "live-one", text: "one")
        )
        let emitted = coalescer.receive(
            .assistantDelta(sessionID: "live-two", text: "two")
        )

        XCTAssertEqual(emitted, [
            .assistantDelta(sessionID: "live-one", text: "one"),
        ])
        let pending = coalescer.flush()
        XCTAssertEqual(
            pending,
            .assistantDelta(sessionID: "live-two", text: "two")
        )
    }

    func testDeltasShareOneBubbleAndAuthoritativeCompletionWins() {
        let fixture = Fixture()

        fixture.coordinator.beginTurn()
        fixture.append("hi ")
        fixture.append("there")
        fixture.complete("hi there!")

        XCTAssertEqual(fixture.messages, [
            TranscriptMessage(
                id: "assistant-1",
                role: .assistant,
                content: "hi there!"
            ),
        ])
    }

    func testInterimSealsAssistantSegmentWithoutCompletingTurn() {
        let fixture = Fixture()

        fixture.coordinator.beginTurn()
        fixture.append("draft commentary")
        fixture.interim("authoritative commentary")
        fixture.append("final ")
        fixture.complete("final answer")

        XCTAssertEqual(
            fixture.messages.map(\.content),
            ["authoritative commentary", "final answer"]
        )
    }

    func testNewToolSplitsLaterAssistantTextChronologically() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("before tool")
        fixture.tool(
            LiveToolEvent(
                toolID: "terminal-1",
                name: "terminal",
                status: "running",
                content: "",
                label: "Running `swift test`"
            )
        )
        fixture.append("after tool")
        fixture.complete("final after tool")

        XCTAssertEqual(fixture.transcript.map(\.id), [
            "assistant-1",
            "tool-terminal-1",
            "assistant-2",
        ])
        XCTAssertEqual(
            fixture.messages.map(\.content),
            ["before tool", "final after tool"]
        )
        XCTAssertEqual(fixture.tools.single?.startedAtMilliseconds, 1_234)
    }

    func testToolFinalizesMediaInAssistantSegmentItCloses() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("Before tool MEDIA:/tmp/result.png")
        fixture.tool(
            LiveToolEvent(
                toolID: "one",
                name: "terminal",
                status: "done",
                content: "ok"
            )
        )
        fixture.append("after tool")
        fixture.complete("final after tool")

        XCTAssertEqual(fixture.messages[0].content, "Before tool")
        XCTAssertEqual(
            fixture.messages[0].attachments.map(\.path),
            ["/tmp/result.png"]
        )
        XCTAssertEqual(fixture.messages[1].content, "final after tool")
    }

    func testCompletionAfterTurnEndsOnToolDoesNotDuplicateEarlierText() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("already shown")
        fixture.tool(
            LiveToolEvent(
                toolID: "one",
                name: "memory",
                status: "done",
                content: "saved"
            )
        )
        fixture.complete("already shown")

        XCTAssertEqual(fixture.messages.map(\.content), ["already shown"])
    }

    func testCompletionWithoutDeltaCreatesExactlyOneBubble() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.complete("complete response")
        fixture.complete("")

        XCTAssertEqual(fixture.messages, [
            TranscriptMessage(
                id: "assistant-1",
                role: .assistant,
                content: "complete response"
            ),
        ])
    }

    func testRestoredTurnContinuesSeededBubbleAndPreventsDuplicate() {
        let fixture = Fixture(
            initialTranscript: [
                .message(
                    TranscriptMessage(
                        id: "inflight-assistant-live",
                        role: .assistant,
                        content: "seeded "
                    )
                ),
            ]
        )
        fixture.coordinator.restoreTurn(
            activeAssistantID: "inflight-assistant-live",
            turnProducedText: true
        )
        fixture.append("continued")
        fixture.complete("seeded continued!")

        XCTAssertEqual(fixture.messages.map(\.content), ["seeded continued!"])
        fixture.coordinator.restoreTurn(
            activeAssistantID: nil,
            turnProducedText: true
        )
        fixture.complete("must not duplicate")
        XCTAssertEqual(fixture.messages.map(\.content), ["seeded continued!"])
    }

    func testSystemRowClosesAssistantSegmentAndRetainsErrorState() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("first")
        fixture.system("gateway warning", isError: true)
        fixture.append("second")

        XCTAssertEqual(fixture.transcript.map(\.id), [
            "assistant-1", "system-2", "assistant-3",
        ])
        guard case let .message(system) = fixture.transcript[1] else {
            return XCTFail("Expected system message")
        }
        XCTAssertEqual(system.role, .system)
        XCTAssertTrue(system.isError)
    }

    func testToolUpdateDoesNotSplitActiveAssistantSegment() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("before ")
        fixture.tool(
            LiveToolEvent(
                toolID: "one",
                name: "terminal",
                status: "running",
                content: ""
            )
        )
        fixture.append("after ")
        fixture.tool(
            LiveToolEvent(
                toolID: "one",
                name: "terminal",
                status: "done",
                content: "ok",
                outcome: .succeeded,
                durationSeconds: 2.1
            )
        )
        fixture.append("continued")

        XCTAssertEqual(
            fixture.messages.map(\.content),
            ["before ", "after continued"]
        )
        XCTAssertEqual(fixture.tools.single?.content, "ok")
        XCTAssertEqual(fixture.tools.single?.durationSeconds, 2.1)
    }

    func testToolTodoUpdatesOwnActivePlanLifecycle() {
        let fixture = Fixture(
            activeTodos: [TodoItem(content: "old", status: "pending")]
        )
        fixture.tool(
            LiveToolEvent(
                toolID: "todo",
                name: "todo",
                status: "running",
                content: "",
                todos: [
                    TodoItem(content: "Build", status: "in_progress"),
                ]
            )
        )
        XCTAssertEqual(fixture.activeTodos?.map(\.content), ["Build"])

        fixture.tool(
            LiveToolEvent(
                toolID: "todo",
                name: "todo",
                status: "done",
                content: "",
                todos: []
            )
        )
        XCTAssertNil(fixture.activeTodos)
    }

    func testImageCacheAPIDelegatesToBoundedPayloadStore() {
        let coordinator = LiveTranscriptCoordinator(
            maxCachedImages: 2,
            maxCachedImageBase64Characters: 5
        )
        coordinator.rememberImage(path: "a", base64: "aa")
        coordinator.rememberImage(path: "b", base64: "bb")
        coordinator.rememberImage(path: "c", base64: "cc")
        XCTAssertEqual(coordinator.cachedImages(), ["b": "bb", "c": "cc"])

        coordinator.clearCachedImages()
        XCTAssertTrue(coordinator.cachedImages().isEmpty)
    }

    func testEmptyDeltaEstablishesTurnBubbleAndTextProof() {
        let fixture = Fixture()
        fixture.coordinator.beginTurn()
        fixture.append("")
        fixture.coordinator.closeAssistantBubble()
        fixture.complete("completion echo")

        XCTAssertEqual(fixture.messages, [
            TranscriptMessage(
                id: "assistant-1",
                role: .assistant,
                content: ""
            ),
        ])
    }
}

private final class Fixture {
    let coordinator: LiveTranscriptCoordinator
    var transcript: [TranscriptEntry]
    var activeTodos: [TodoItem]?

    init(
        initialTranscript: [TranscriptEntry] = [],
        activeTodos: [TodoItem]? = nil
    ) {
        var nextID = 0
        transcript = initialTranscript
        self.activeTodos = activeTodos
        coordinator = LiveTranscriptCoordinator(
            idFactory: { prefix in
                nextID += 1
                return "\(prefix)-\(nextID)"
            },
            clockMilliseconds: { 1_234 }
        )
    }

    var messages: [TranscriptMessage] {
        transcript.compactMap {
            guard case let .message(message) = $0 else {
                return nil
            }
            return message
        }
    }

    var tools: [TranscriptTool] {
        transcript.compactMap {
            guard case let .tool(tool) = $0 else {
                return nil
            }
            return tool
        }
    }

    func append(_ delta: String) {
        transcript = coordinator.appendAssistant(delta, to: transcript)
    }

    func complete(_ content: String) {
        transcript = coordinator.completeAssistant(content, in: transcript)
    }

    func interim(_ content: String) {
        transcript = coordinator.finalizeInterimAssistant(
            content,
            in: transcript
        )
    }

    func system(_ content: String, isError: Bool = false) {
        transcript = coordinator.appendSystem(
            content,
            isError: isError,
            to: transcript
        )
    }

    func tool(_ event: LiveToolEvent) {
        let projection = coordinator.upsertTool(
            in: transcript,
            activeTodos: activeTodos,
            event: event
        )
        transcript = projection.transcript
        activeTodos = projection.activeTodos
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
