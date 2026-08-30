import XCTest
@testable import Nile

@MainActor
final class SessionTimelineRuntimeTests: XCTestCase {
    func testOffscreenEventsPreserveTranscriptToolsTodosAndStatus() {
        let runtime = SessionTimelineRuntime()
        runtime.capture(snapshot(storedID: "one"))

        var projection = runtime.consume(
            .messageStart(sessionID: "live-one"),
            gatewayID: "gateway"
        )
        XCTAssertEqual(projection?.activeStatusMutation, .set("working"))

        projection = runtime.consume(
            .assistantDelta(
                sessionID: "live-one",
                text: "Before tool"
            ),
            gatewayID: "gateway"
        )
        _ = runtime.consume(
            .toolStart(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                detail: "swift test",
                context: "Running tests",
                generating: false
            ),
            gatewayID: "gateway"
        )
        projection = runtime.consume(
            .toolComplete(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                result: "passed",
                outcome: .succeeded,
                summary: "Tests passed",
                durationSeconds: 2,
                todos: [
                    TodoItem(content: "Ship", status: "in_progress"),
                ],
                inlineDiff: nil
            ),
            gatewayID: "gateway"
        )

        XCTAssertEqual(projection?.activeStatusMutation, .unchanged)
        XCTAssertEqual(
            projection?.switchPresentation?.scrollOwner,
            TranscriptScrollOwner(
                gatewayID: "gateway",
                sessionID: "one"
            )
        )
        XCTAssertEqual(
            projection?.switchPresentation?.activeTodos?.map(\.content),
            ["Ship"]
        )
        XCTAssertEqual(
            projection?.switchPresentation?.entries.compactMap {
                guard case let .message(message) = $0 else {
                    return nil
                }
                return message.content
            },
            ["Prompt one", "Before tool"]
        )
        XCTAssertEqual(
            projection?.switchPresentation?.entries.compactMap {
                guard case let .tool(tool) = $0 else {
                    return nil
                }
                return tool.content
            },
            ["passed"]
        )
    }

    func testRestoreRequiresObservedEventAndExactLiveRuntime() {
        let runtime = SessionTimelineRuntime()
        runtime.capture(snapshot(storedID: "one"))
        let resumed = liveSession(
            storedID: "one",
            running: true,
            inflight: InflightTurn(user: "Question", assistant: "Answer")
        )

        XCTAssertNil(
            runtime.restore(storedSessionID: "one", resumed: resumed)
        )
        _ = runtime.consume(
            .statusUpdate(sessionID: "live-one", text: "Working"),
            gatewayID: nil
        )
        let restored = runtime.restore(
            storedSessionID: "one",
            resumed: resumed
        )
        XCTAssertEqual(restored?.liveSession, resumed)
        XCTAssertTrue(restored?.isSending == true)
        XCTAssertTrue(restored?.attachedToExistingTurn == true)

        let differentRuntime = LiveSession(
            liveID: "replacement-live",
            storedID: "one",
            info: resumed.info,
            messages: [],
            running: true,
            status: "working",
            inflight: resumed.inflight
        )
        XCTAssertNil(
            runtime.restore(
                storedSessionID: "one",
                resumed: differentRuntime
            )
        )
    }

    func testCompletionRemovesPendingRowsAndClearsBusyStatus() {
        let runtime = SessionTimelineRuntime()
        runtime.capture(
            snapshot(
                storedID: "one",
                entries: [
                    .message(
                        TranscriptMessage(
                            id: "pending-user",
                            role: .user,
                            content: "Question",
                            pending: true
                        )
                    ),
                ],
                observedLiveEvent: true
            ),
            observedLiveEvent: true
        )
        _ = runtime.consume(
            .messageStart(sessionID: "live-one"),
            gatewayID: nil
        )
        let projection = runtime.consume(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Complete",
                usage: nil
            ),
            gatewayID: nil
        )

        XCTAssertEqual(projection?.activeStatusMutation, .remove)
        XCTAssertFalse(projection?.switchPresentation?.isSending ?? true)
        XCTAssertFalse(
            projection?.switchPresentation?.entries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.pending
            } ?? true
        )
        XCTAssertEqual(
            projection?.switchPresentation?.entries.compactMap {
                guard case let .message(message) = $0,
                      message.role == .assistant else {
                    return nil
                }
                return message.content
            },
            ["Complete"]
        )
    }

    func testReplacementAndLRUEvictionKeepIndexesConsistent() {
        let runtime = SessionTimelineRuntime(maximumTimelineCount: 2)
        runtime.capture(snapshot(storedID: "one"))
        runtime.capture(snapshot(storedID: "two"))
        _ = runtime.consume(
            .statusUpdate(sessionID: "live-one", text: "Still active"),
            gatewayID: nil
        )
        runtime.capture(snapshot(storedID: "three"))

        XCTAssertEqual(runtime.cachedTimelineCount, 2)
        XCTAssertNotNil(
            runtime.switchPresentation(
                storedSessionID: "one",
                gatewayID: nil
            )
        )
        XCTAssertNil(
            runtime.switchPresentation(
                storedSessionID: "two",
                gatewayID: nil
            )
        )
        XCTAssertNotNil(
            runtime.switchPresentation(
                storedSessionID: "three",
                gatewayID: nil
            )
        )

        runtime.capture(
            snapshot(
                storedID: "one",
                liveID: "replacement-one"
            )
        )
        XCTAssertNil(
            runtime.consume(
                .statusUpdate(sessionID: "live-one", text: "stale"),
                gatewayID: nil
            )
        )
        runtime.reset()
        XCTAssertEqual(runtime.cachedTimelineCount, 0)

        runtime.capture(snapshot(storedID: "old", liveID: "shared-live"))
        runtime.capture(snapshot(storedID: "new", liveID: "shared-live"))
        XCTAssertNil(
            runtime.switchPresentation(
                storedSessionID: "old",
                gatewayID: nil
            )
        )
        XCTAssertNotNil(
            runtime.switchPresentation(
                storedSessionID: "new",
                gatewayID: nil
            )
        )
        XCTAssertEqual(runtime.cachedTimelineCount, 1)
    }

    private func snapshot(
        storedID: String,
        liveID: String? = nil,
        entries: [TranscriptEntry]? = nil,
        observedLiveEvent: Bool = false
    ) -> SessionTimelineRuntime.Snapshot {
        let identifier = liveID ?? "live-\(storedID)"
        let initialEntries = entries ?? [
            .message(
                TranscriptMessage(
                    id: "user-\(storedID)",
                    role: .user,
                    content: "Prompt \(storedID)"
                )
            ),
        ]
        return SessionTimelineRuntime.Snapshot(
            liveSession: liveSession(
                storedID: storedID,
                liveID: identifier
            ),
            storedSessionID: storedID,
            entries: initialEntries,
            activeTodos: nil,
            delegationTurns: [],
            pinnedDelegationTurnID: nil,
            isSending: observedLiveEvent,
            turnStartedAt: nil,
            attachedToExistingTurn: false,
            coordinator: LiveTranscriptCoordinator(
                idFactory: { "\($0)-\(storedID)" },
                clockMilliseconds: { 1_000 }
            )
        )
    }

    private func liveSession(
        storedID: String,
        liveID: String? = nil,
        running: Bool = false,
        inflight: InflightTurn? = nil
    ) -> LiveSession {
        LiveSession(
            liveID: liveID ?? "live-\(storedID)",
            storedID: storedID,
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: running,
            status: running ? "working" : "idle",
            inflight: inflight
        )
    }
}
