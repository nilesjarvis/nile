import XCTest
@testable import Nile

final class DelegationCoordinatorTests: XCTestCase {
    func testSparseLifecycleMergesIntoPinnedTurnThenSettlesAndSnapshots() {
        var now = 100.0
        var turn = 0
        let coordinator = DelegationCoordinator(
            nowEpochSeconds: { now },
            newTurnID: {
                turn += 1
                return "turn-\(turn)"
            }
        )
        let owner = DelegationOwner(
            gatewayID: "gateway",
            storedSessionID: "stored"
        )

        XCTAssertNil(
            coordinator.applyEvent(
                owner: owner,
                data: event(
                    id: "agent-1",
                    goal: "Inspect consistency",
                    toolCount: 1,
                    text: "Starting"
                ),
                kind: .started
            )
        )
        XCTAssertNil(
            coordinator.applyEvent(
                owner: owner,
                data: event(
                    id: "agent-1",
                    goal: "Inspect consistency",
                    toolCount: 3,
                    text: nil,
                    toolPreview: "Running tests"
                ),
                kind: .progress
            )
        )
        var projection = coordinator.projection(
            gatewayID: "gateway",
            storedSessionID: "stored",
            transcript: []
        )
        XCTAssertEqual(projection.pinnedTurnID, "turn-1")
        XCTAssertEqual(projection.turns.first?.agents.first?.toolCount, 3)
        XCTAssertEqual(
            projection.turns.first?.agents.first?.latestActivity,
            "Running tests"
        )
        XCTAssertEqual(projection.transcript.count, 1)

        now = 110
        XCTAssertNil(
            coordinator.applyEvent(
                owner: owner,
                data: event(
                    id: "agent-1",
                    goal: "Inspect consistency",
                    toolCount: 2,
                    terminal: .completed,
                    summary: "Matched"
                ),
                kind: .completed
            )
        )
        let snapshot = coordinator.markParentCompleted(owner: owner)
        XCTAssertEqual(snapshot?.finishedAtEpochSeconds, 110)
        XCTAssertEqual(snapshot?.agents.first?.toolCount, 3)
        XCTAssertEqual(snapshot?.agents.first?.summary, "Matched")

        projection = coordinator.projection(
            gatewayID: "gateway",
            storedSessionID: "stored",
            transcript: projection.transcript
        )
        XCTAssertNil(projection.pinnedTurnID)
        XCTAssertEqual(
            projection.turns.first?.agents.first?.status,
            .finished(.completed)
        )
    }

    func testMultipleAgentsGroupAndTerminalStateCannotBeWeakened() {
        let coordinator = DelegationCoordinator(
            nowEpochSeconds: { 1 },
            newTurnID: { "turn" }
        )
        let owner = DelegationOwner(
            gatewayID: "gateway",
            storedSessionID: "stored"
        )
        _ = coordinator.applyEvent(
            owner: owner,
            data: event(id: "a", goal: "One", taskIndex: 0),
            kind: .spawnRequested
        )
        _ = coordinator.applyEvent(
            owner: owner,
            data: event(id: "b", goal: "Two", taskIndex: 1),
            kind: .started
        )
        _ = coordinator.applyEvent(
            owner: owner,
            data: event(
                id: "a",
                goal: "One",
                taskIndex: 0,
                terminal: .failed
            ),
            kind: .completed
        )
        _ = coordinator.applyEvent(
            owner: owner,
            data: event(id: "a", goal: "One", taskIndex: 0),
            kind: .progress
        )

        let agents = coordinator.projection(
            gatewayID: "gateway",
            storedSessionID: "stored",
            transcript: []
        ).turns[0].agents
        XCTAssertEqual(agents.count, 2)
        XCTAssertEqual(agents[0].status, .finished(.failed))
        XCTAssertEqual(agents[1].status, .running)
    }

    func testInterruptTransitionsReflectDefiniteAndUncertainOutcomes() {
        let coordinator = DelegationCoordinator(
            nowEpochSeconds: { 1 },
            newTurnID: { "turn" }
        )
        let owner = DelegationOwner(
            gatewayID: "gateway",
            storedSessionID: "stored"
        )
        _ = coordinator.applyEvent(
            owner: owner,
            data: event(id: "agent", goal: "Work"),
            kind: .started
        )
        let request = try! XCTUnwrap(
            coordinator.beginInterrupt(subagentID: "agent")
        )
        XCTAssertNil(coordinator.beginInterrupt(subagentID: "agent"))
        XCTAssertTrue(
            coordinator.applyInterruptFailure(request, uncertain: true)
        )
        coordinator.completeInterrupt(request)
        XCTAssertFalse(coordinator.applyInterruptResult(request, found: true))
        XCTAssertEqual(
            coordinator.projection(
                gatewayID: "gateway",
                storedSessionID: "stored",
                transcript: []
            ).turns[0].agents[0].status,
            .interruptUnconfirmed
        )

        let retry = try! XCTUnwrap(
            coordinator.beginInterrupt(subagentID: "agent")
        )
        XCTAssertTrue(coordinator.applyInterruptResult(retry, found: false))
        coordinator.completeInterrupt(retry)
        XCTAssertEqual(
            coordinator.projection(
                gatewayID: "gateway",
                storedSessionID: "stored",
                transcript: []
            ).turns[0].agents[0].status,
            .completionUnknown
        )
    }

    func testSnapshotHistoryDeduplicatesAgentsAndRetainsNewestThree() {
        let coordinator = DelegationCoordinator()
        let owner = DelegationOwner(
            gatewayID: "gateway",
            storedSessionID: "stored"
        )
        for index in 0..<5 {
            coordinator.addSnapshot(
                owner: owner,
                path: "snapshot-\(index)",
                snapshot: snapshot(
                    id: "agent-\(index)",
                    started: Double(index),
                    finished: Double(index + 1)
                )
            )
        }
        coordinator.completeSnapshotLoad(owner: owner)
        var turns = coordinator.projection(
            gatewayID: "gateway",
            storedSessionID: "stored",
            transcript: []
        ).turns
        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(
            turns.flatMap(\.agents).compactMap(\.subagentID),
            ["agent-2", "agent-3", "agent-4"]
        )

        coordinator.addSnapshot(
            owner: owner,
            path: "duplicate",
            snapshot: snapshot(
                id: "agent-4",
                started: 9,
                finished: 10
            )
        )
        coordinator.completeSnapshotLoad(owner: owner)
        turns = coordinator.projection(
            gatewayID: "gateway",
            storedSessionID: "stored",
            transcript: []
        ).turns
        XCTAssertEqual(turns.count, 3)
    }

    private func event(
        id: String?,
        goal: String,
        taskIndex: Int = 0,
        toolCount: Int? = nil,
        text: String? = nil,
        toolPreview: String? = nil,
        terminal: SubagentTerminalStatus? = nil,
        summary: String? = nil
    ) -> SubagentEventData {
        SubagentEventData(
            goal: goal,
            taskCount: 2,
            taskIndex: taskIndex,
            subagentID: id,
            parentID: "parent",
            childSessionID: id.map { "child-\($0)" },
            depth: 1,
            model: "model",
            toolCount: toolCount,
            toolsets: ["terminal"],
            text: text,
            toolName: nil,
            toolPreview: toolPreview,
            terminalStatus: terminal,
            rawTerminalStatus: terminal?.rawValue,
            summary: summary,
            durationSeconds: terminal == nil ? nil : 10,
            inputTokens: 100,
            outputTokens: 20,
            reasoningTokens: nil,
            apiCalls: 2,
            filesRead: [],
            filesWritten: [],
            outputTail: []
        )
    }

    private func snapshot(
        id: String,
        started: Double,
        finished: Double
    ) -> DelegationSnapshot {
        DelegationSnapshot(
            storedSessionID: "stored",
            startedAtEpochSeconds: started,
            finishedAtEpochSeconds: finished,
            label: id,
            agents: [
                DelegationSnapshotAgent(
                    goal: id,
                    taskCount: 1,
                    taskIndex: 0,
                    subagentID: id,
                    parentID: nil,
                    childSessionID: nil,
                    depth: nil,
                    model: nil,
                    toolCount: 0,
                    toolsets: [],
                    text: nil,
                    toolName: nil,
                    toolPreview: nil,
                    terminalStatus: .completed,
                    rawTerminalStatus: "completed",
                    summary: "done",
                    durationSeconds: 1,
                    inputTokens: nil,
                    outputTokens: nil,
                    reasoningTokens: nil,
                    apiCalls: nil,
                    filesRead: [],
                    filesWritten: [],
                    outputTail: []
                ),
            ]
        )
    }
}
