import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testGoalSetUsesCollisionFenceBudgetAndStrictDispatch() async throws {
        let objective = "Finish and verify"
        let rpc = RecordingRPC(
            responses: [
                "commands.catalog": emptyCommandCatalog(),
                "command.resolve": ["canonical": .string("goal")],
                "cli.exec": [
                    "blocked": .bool(false),
                    "code": .number(0),
                    "output": .string(""),
                ],
                "command.dispatch": [
                    "type": .string("send"),
                    "message": .string(objective),
                    "notice": .string(
                        "⊙ Goal set (10-turn budget): \(objective)"
                    ),
                    "warning": .string(""),
                ],
            ]
        )
        let goals = goalService(rpc: rpc)

        let start = try await goals.setGoal(
            liveSessionID: "live-1",
            objective: objective,
            maxTurns: 10
        )

        XCTAssertEqual(start.goal.maxTurns, 10)
        XCTAssertEqual(start.kickoffPrompt, objective)
        let requests = await rpc.requests
        XCTAssertEqual(
            requests.map(\.method),
            [
                "commands.catalog",
                "command.resolve",
                "cli.exec",
                "command.dispatch",
            ]
        )
        XCTAssertEqual(
            requests[2].params,
            [
                "argv": .array([
                    .string("config"),
                    .string("set"),
                    .string("goals.max_turns"),
                    .string("10"),
                ]),
                "timeout": .number(30),
            ]
        )
        XCTAssertEqual(
            requests[3].params,
            [
                "session_id": .string("live-1"),
                "name": .string("goal"),
                "arg": .string(objective),
            ]
        )
    }

    func testGoalCollisionFailsBeforeAnyMutation() async {
        let rpc = RecordingRPC(
            responses: [
                "commands.catalog": [
                    "warning": .string(""),
                    "categories": .array([
                        .object([
                            "name": .string("User commands"),
                            "pairs": .array([
                                .array([
                                    .string("/goal"),
                                    .string("shadow"),
                                ]),
                            ]),
                        ]),
                    ]),
                    "pairs": .array([]),
                    "skill_count": .number(0),
                ],
            ]
        )
        let goals = goalService(rpc: rpc)

        await XCTAssertThrowsErrorAsync(
            try await goals.clearGoal(liveSessionID: "live-1")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "This Hermes profile shadows /goal, so Nile cannot control it safely"
            )
        }
        let requests = await rpc.requests
        XCTAssertEqual(requests.map(\.method), ["commands.catalog"])
    }

    func testGoalStatusUsesVerifiedBuiltInAndStrictProse() async throws {
        let rpc = RecordingRPC(
            responses: [
                "commands.catalog": emptyCommandCatalog(),
                "command.resolve": ["canonical": .string("goal")],
                "command.dispatch": [
                    "type": .string("exec"),
                    "notice": .string(""),
                    "warning": .string(""),
                    "output": .string(
                        "⏸ Goal (4/20 turns — user-paused): Ship safely"
                    ),
                ],
            ]
        )
        let goals = goalService(rpc: rpc)

        let goal = try await goals.goalStatus(liveSessionID: "live-1")

        XCTAssertEqual(goal?.phase, .paused)
        XCTAssertEqual(goal?.pausedReason, "user-paused")
        let requests = await rpc.requests
        XCTAssertEqual(
            requests.last?.params,
            [
                "session_id": .string("live-1"),
                "name": .string("goal"),
                "arg": .string("status"),
            ]
        )
    }

    func testSessionUsageLoadsUsageThenBestEffortBreakdown() async throws {
        let rpc = RecordingRPC(
            responses: [
                "session.usage": [
                    "input": .number(120),
                    "output": .number(30),
                    "total": .number(150),
                    "calls": .number(2),
                ],
                "session.context_breakdown": [
                    "context_used": .number(25),
                    "context_max": .number(100),
                    "categories": .array([]),
                ],
            ]
        )
        let usageCapability = usageService(rpc: rpc)

        let usage = try await usageCapability.sessionUsage(
            liveSessionID: "live-1"
        )

        XCTAssertEqual(usage.contextPercent, 25)
        let requests = await rpc.requests
        XCTAssertEqual(
            requests.map(\.method),
            ["session.usage", "session.context_breakdown"]
        )
    }

    func testGatewayStatsUsesAuthenticatedExactDashboardQuery() async throws {
        let dashboard = QueryRecordingDashboard(
            response: [
                "period_days": .number(7),
                "totals": .object([
                    "total_input": .number(100),
                    "total_output": .number(25),
                ]),
            ]
        )
        let repository = TuiGatewayRepository(
            rpc: RecordingRPC(responses: [:]),
            connectionClient: NoopConnectionClient(),
            signals: AsyncStream { $0.finish() },
            dashboard: dashboard
        )
        try await repository.connect(connection())

        let stats = try await repository.sessionCapabilities
            .gatewayStatistics.gatewayStats(days: 7)

        XCTAssertEqual(stats.periodDays, 7)
        XCTAssertEqual(stats.totals.recordedTokens, 125)
        let requests = await dashboard.requests
        XCTAssertEqual(
            requests,
            [
                QueryDashboardRequest(
                    connection: connection(),
                    pathSegments: ["analytics", "usage"],
                    query: ["days": "7"]
                ),
            ]
        )
    }

}
