import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testEventStreamPreservesSignalOrderAndProjectsTerminalFailureLast() async {
        let signals = AsyncStream<GatewaySignal> { continuation in
            continuation.yield(
                .event(
                    generation: 3,
                    frame: GatewayEventFrame(
                        type: "message.delta",
                        sessionID: "live-1",
                        payload: ["text": .string("a")]
                    )
                )
            )
            continuation.yield(
                .event(
                    generation: 3,
                    frame: GatewayEventFrame(
                        type: "message.interim",
                        sessionID: "live-1",
                        payload: ["text": .string("checking")]
                    )
                )
            )
            continuation.yield(
                .event(
                    generation: 3,
                    frame: GatewayEventFrame(
                        type: "message.complete",
                        sessionID: "live-1",
                        payload: ["text": .string("done")]
                    )
                )
            )
            continuation.yield(
                .failure(
                    generation: 3,
                    failure: GatewayFailure(
                        message: "lost",
                        authRejected: false,
                        retryable: true
                    )
                )
            )
            continuation.finish()
        }
        let repository = TuiGatewayRepository(
            rpc: RecordingRPC(responses: [:]),
            connectionClient: NoopConnectionClient(),
            signals: signals
        )

        var received: [HermesStreamEvent] = []
        for await event in repository.events {
            received.append(event)
        }
        XCTAssertEqual(
            received,
            [
                .assistantDelta(sessionID: "live-1", text: "a"),
                .assistantInterim(sessionID: "live-1", text: "checking"),
                .assistantCompleted(sessionID: "live-1", text: "done", usage: nil),
                .connectionLost(
                    message: "lost",
                    authRejected: false,
                    retryable: true
                ),
            ]
        )
    }

    func testDelegationOperationsUseExactRPCContractAndStrictSnapshots()
        async throws {
        let rpc = RecordingRPC(
            responses: [
                "delegation.status": [
                    "active": .array([
                        .object([
                            "subagent_id": .string("agent-1"),
                            "parent_id": .string("parent-1"),
                            "depth": .number(1),
                            "goal": .string("Inspect UI"),
                            "model": .string("gemini"),
                            "started_at": .number(10),
                            "tool_count": .number(2),
                            "status": .string("working"),
                        ]),
                    ]),
                    "paused": .bool(false),
                    "max_spawn_depth": .number(3),
                    "max_concurrent_children": .number(4),
                ],
                "subagent.interrupt": [
                    "found": .bool(true),
                    "subagent_id": .string("agent-1"),
                ],
                "spawn_tree.save": [
                    "session_id": .string("stored-1"),
                    "path": .string("/snapshots/one.json"),
                ],
                "spawn_tree.list": [
                    "entries": .array([
                        .object([
                            "path": .string("/snapshots/one.json"),
                            "session_id": .string("stored-1"),
                            "started_at": .number(10),
                            "finished_at": .number(20),
                            "label": .string("Inspect UI"),
                            "count": .number(1),
                        ]),
                    ]),
                ],
                "spawn_tree.load": [
                    "session_id": .string("stored-1"),
                    "started_at": .number(10),
                    "finished_at": .number(20),
                    "label": .string("Inspect UI"),
                    "subagents": .array([
                        .object([
                            "goal": .string("Inspect UI"),
                            "task_count": .number(1),
                            "task_index": .number(0),
                            "subagent_id": .string("agent-1"),
                            "status": .string("completed"),
                            "summary": .string("Matched"),
                        ]),
                    ]),
                ],
            ]
        )
        let delegation = delegationService(rpc: rpc)
        let agent = DelegationSnapshotAgent(
            goal: "Inspect UI",
            taskCount: 1,
            taskIndex: 0,
            subagentID: "agent-1",
            parentID: "parent-1",
            childSessionID: "child-1",
            depth: 1,
            model: "gemini",
            toolCount: 2,
            toolsets: ["terminal"],
            text: "Comparing",
            toolName: "terminal",
            toolPreview: "xcodebuild test",
            terminalStatus: .completed,
            rawTerminalStatus: nil,
            summary: "Matched",
            durationSeconds: 10,
            inputTokens: 100,
            outputTokens: 20,
            reasoningTokens: 5,
            apiCalls: 2,
            filesRead: ["A.swift"],
            filesWritten: ["B.swift"],
            outputTail: [
                SubagentOutput(
                    tool: "terminal",
                    preview: "passed",
                    status: "done"
                ),
            ]
        )
        let snapshot = DelegationSnapshot(
            storedSessionID: "stored-1",
            startedAtEpochSeconds: 10,
            finishedAtEpochSeconds: 20,
            label: "Inspect UI",
            agents: [agent]
        )

        let status = try await delegation.delegationStatus()
        let interrupt = try await delegation.interruptSubagent(
            subagentID: "agent-1"
        )
        let path = try await delegation.saveDelegationSnapshot(snapshot)
        let infos = try await delegation.listDelegationSnapshots(
            storedSessionID: "stored-1",
            limit: 0
        )
        let loaded = try await delegation.loadDelegationSnapshot(path: path)

        XCTAssertEqual(status.active.first?.subagentID, "agent-1")
        XCTAssertEqual(status.maxConcurrentChildren, 4)
        XCTAssertEqual(interrupt, SubagentInterruptResult(
            found: true,
            subagentID: "agent-1"
        ))
        XCTAssertEqual(path, "/snapshots/one.json")
        XCTAssertEqual(infos.first?.count, 1)
        XCTAssertEqual(loaded.agents.first?.terminalStatus, .completed)
        XCTAssertEqual(loaded.agents.first?.summary, "Matched")

        let requests = await rpc.requests
        XCTAssertEqual(
            requests.map(\.method),
            [
                "delegation.status",
                "subagent.interrupt",
                "spawn_tree.save",
                "spawn_tree.list",
                "spawn_tree.load",
            ]
        )
        XCTAssertEqual(requests[0].params, [:])
        XCTAssertEqual(
            requests[1].params,
            ["subagent_id": .string("agent-1")]
        )
        XCTAssertEqual(
            requests[3].params,
            [
                "session_id": .string("stored-1"),
                "limit": .number(1),
                "cross_session": .bool(false),
            ]
        )
        XCTAssertEqual(
            requests[4].params,
            ["path": .string("/snapshots/one.json")]
        )
        XCTAssertEqual(requests[2].params["session_id"], .string("stored-1"))
        XCTAssertEqual(requests[2].params["started_at"], .number(10))
        XCTAssertEqual(requests[2].params["finished_at"], .number(20))
        XCTAssertEqual(
            requests[2].params["subagents"]?.arrayValue?.count,
            1
        )
        XCTAssertTrue(requests.allSatisfy {
            $0.timeoutMilliseconds == 30_000 && !$0.allowNullResult
        })
    }

    func testDelegationMutationsFailClosedWithUncertainMalformedResponses()
        async {
        let wrongInterrupt = delegationService(
            rpc: RecordingRPC(
                responses: [
                    "subagent.interrupt": [
                        "found": .bool(true),
                        "subagent_id": .string("other"),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await wrongInterrupt.interruptSubagent(
                subagentID: "agent-1"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
            XCTAssertEqual(
                hermes?.message,
                "Malformed response to subagent.interrupt: subagent_id did not match the request"
            )
        }

        let wrongSave = delegationService(
            rpc: RecordingRPC(
                responses: [
                    "spawn_tree.save": [
                        "session_id": .string("other"),
                        "path": .string("/snapshot"),
                    ],
                ]
            )
        )
        let snapshot = DelegationSnapshot(
            storedSessionID: "stored-1",
            startedAtEpochSeconds: nil,
            finishedAtEpochSeconds: 1,
            label: "",
            agents: [
                DelegationSnapshotAgent(
                    goal: "Work",
                    taskCount: 1,
                    taskIndex: 0,
                    subagentID: nil,
                    parentID: nil,
                    childSessionID: nil,
                    depth: nil,
                    model: nil,
                    toolCount: nil,
                    toolsets: [],
                    text: nil,
                    toolName: nil,
                    toolPreview: nil,
                    terminalStatus: .completed,
                    rawTerminalStatus: nil,
                    summary: nil,
                    durationSeconds: nil,
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
        await XCTAssertThrowsErrorAsync(
            try await wrongSave.saveDelegationSnapshot(snapshot)
        ) { error in
            XCTAssertEqual(
                (error as? HermesError)?.requestMayHaveSucceeded,
                true
            )
        }
    }

    func testDelegationProtocolRejectsMalformedStatusAndSnapshotRows()
        async {
        let malformedStatus = delegationService(
            rpc: RecordingRPC(
                responses: [
                    "delegation.status": [
                        "active": .array([]),
                        "paused": .string("false"),
                        "max_spawn_depth": .number(1),
                        "max_concurrent_children": .number(1),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await malformedStatus.delegationStatus()
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to delegation.status: paused was missing or not true or false"
            )
        }

        let malformedSnapshot = delegationService(
            rpc: RecordingRPC(
                responses: [
                    "spawn_tree.load": [
                        "session_id": .string("stored"),
                        "finished_at": .number(-1),
                        "label": .string(""),
                        "subagents": .array([]),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await malformedSnapshot.loadDelegationSnapshot(path: "one")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to spawn_tree.load: finished_at was missing or not a finite nonnegative number"
            )
        }
    }

}
