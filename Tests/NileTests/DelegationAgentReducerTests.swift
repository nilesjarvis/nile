import XCTest
@testable import Nile

final class DelegationAgentReducerTests: XCTestCase {
    func testMakeNormalizesSparseIdentityAndBoundsToolCount() {
        let data = event(
            goal: "  Inspect   consistency  ",
            subagentID: "   ",
            parentID: " parent ",
            childSessionID: " ",
            model: " model ",
            toolCount: Int.min,
            text: " ",
            toolPreview: " Running tests "
        )

        let state = DelegationAgentReducer.make(
            rowID: "row",
            order: 7,
            data: data,
            kind: .started
        )
        let ui = DelegationAgentReducer.ui(state)

        XCTAssertEqual(state.firstSeenOrder, 7)
        XCTAssertNil(ui.subagentID)
        XCTAssertEqual(ui.parentID, "parent")
        XCTAssertNil(ui.childSessionID)
        XCTAssertEqual(ui.model, "model")
        XCTAssertEqual(ui.toolCount, Int.max)
        XCTAssertEqual(ui.latestActivity, "Running tests")
        XCTAssertEqual(ui.status, .running)
        XCTAssertEqual(
            DelegationAgentReducer.fallbackKey(data),
            "fallback: parent :1:inspect consistency"
        )
    }

    func testMergePreservesTerminalAndMonotonicSparseFields() {
        let terminal = DelegationAgentReducer.make(
            rowID: "id:agent",
            order: 1,
            data: event(
                goal: "Original goal",
                subagentID: "agent",
                toolCount: -5,
                text: "Finished",
                terminalStatus: .failed
            ),
            kind: .completed
        )

        let merged = DelegationAgentReducer.merge(
            terminal,
            data: event(
                goal: " ",
                subagentID: nil,
                taskCount: 0,
                taskIndex: -1,
                toolCount: 2
            ),
            kind: .progress
        )

        XCTAssertEqual(merged.status, .finished(.failed))
        XCTAssertEqual(merged.goal, "Original goal")
        XCTAssertEqual(merged.taskCount, 2)
        XCTAssertEqual(merged.taskIndex, 1)
        XCTAssertEqual(merged.toolCount, 5)
        XCTAssertEqual(merged.latestActivity, "Finished")

        var interrupting = terminal
        interrupting.status = .interrupting
        XCTAssertEqual(
            DelegationAgentReducer.merge(
                interrupting,
                data: event(goal: "Original goal", subagentID: "agent"),
                kind: .progress
            ).status,
            .interrupting
        )
        XCTAssertEqual(
            DelegationAgentReducer.merge(
                interrupting,
                data: event(
                    goal: "Original goal",
                    subagentID: "agent",
                    terminalStatus: .completed
                ),
                kind: .completed
            ).status,
            .finished(.completed)
        )
    }

    func testSnapshotProjectionRoundTripsEventPayload() {
        let original = event(
            goal: "Ship quality",
            subagentID: "agent",
            parentID: "parent",
            childSessionID: "child",
            model: "model",
            toolCount: 8,
            text: "Done",
            toolPreview: "Applied patch",
            terminalStatus: .completed,
            summary: "Verified"
        )
        let state = DelegationAgentReducer.make(
            rowID: "id:agent",
            order: 3,
            data: original,
            kind: .completed
        )

        let snapshot = DelegationAgentReducer.snapshot(state)
        let restored = DelegationAgentReducer.eventData(snapshot)

        XCTAssertEqual(snapshot.terminalStatus, .completed)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(DelegationAgentReducer.ui(state).rowID, "id:agent")
    }

    private func event(
        goal: String,
        subagentID: String?,
        parentID: String? = "parent",
        childSessionID: String? = "child",
        model: String? = "model",
        taskCount: Int = 2,
        taskIndex: Int = 1,
        toolCount: Int? = nil,
        text: String? = nil,
        toolPreview: String? = nil,
        terminalStatus: SubagentTerminalStatus? = nil,
        summary: String? = nil
    ) -> SubagentEventData {
        SubagentEventData(
            goal: goal,
            taskCount: taskCount,
            taskIndex: taskIndex,
            subagentID: subagentID,
            parentID: parentID,
            childSessionID: childSessionID,
            depth: 2,
            model: model,
            toolCount: toolCount,
            toolsets: [],
            text: text,
            toolName: nil,
            toolPreview: toolPreview,
            terminalStatus: terminalStatus,
            rawTerminalStatus: terminalStatus?.rawValue,
            summary: summary,
            durationSeconds: 12,
            inputTokens: 100,
            outputTokens: 20,
            reasoningTokens: 5,
            apiCalls: 2,
            filesRead: [],
            filesWritten: [],
            outputTail: []
        )
    }
}
