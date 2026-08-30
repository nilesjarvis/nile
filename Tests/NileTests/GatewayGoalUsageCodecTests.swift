import XCTest
@testable import Nile

final class GatewayGoalUsageCodecTests: XCTestCase {
    func testGoalStatusCodecMatchesPinnedHermesProse() throws {
        XCTAssertNil(
            try parseGoalStatusOutput(
                "No active goal. Set one with /goal <text>."
            )
        )
        XCTAssertEqual(
            try parseGoalStatusOutput(
                "⏸ Goal (4/20 turns — user-paused): Ship and verify"
            ),
            HermesGoal(
                objective: "Ship and verify",
                phase: .paused,
                turnsUsed: 4,
                maxTurns: 20,
                pausedReason: "user-paused"
            )
        )
        XCTAssertEqual(
            try parseGoalStatusOutput(
                "⏳ Goal (2/5 turns — waiting: review): Wait safely"
            ),
            HermesGoal(
                objective: "Wait safely",
                phase: .waiting,
                turnsUsed: 2,
                maxTurns: 5,
                pausedReason: "waiting: review"
            )
        )
    }

    func testGoalStatusCodecRejectsUnsupportedOrInvalidOutput() {
        for value in [
            "Goal is active",
            "⊙ Goal (6/5 turns): invalid",
            "⊙ Goal (1/0 turns): invalid",
            "⊙ Goal (1/5 turns): ",
        ] {
            XCTAssertThrowsError(try parseGoalStatusOutput(value)) { error in
                let hermes = error as? HermesError
                XCTAssertEqual(hermes?.retryable, false)
                XCTAssertEqual(hermes?.requestMayHaveSucceeded, false)
            }
        }
    }

    func testGoalSetNoticeIsStrictAndMarksMalformedMutationUncertain()
        throws
    {
        XCTAssertEqual(
            try parseGoalSetNotice(
                "⊙ Goal set (10-turn budget): Finish safely\nextra",
                expectedObjective: "Finish safely"
            ),
            HermesGoal(
                objective: "Finish safely",
                phase: .active,
                turnsUsed: 0,
                maxTurns: 10
            )
        )
        XCTAssertThrowsError(
            try parseGoalSetNotice(
                "⊙ Goal set (10-turn budget): Other",
                expectedObjective: "Finish safely"
            )
        ) { error in
            XCTAssertEqual(
                (error as? HermesError)?.requestMayHaveSucceeded,
                true
            )
        }
    }

    func testSessionUsagePrefersBreakdownAndFiltersInvalidCategories() {
        let usage = decodeSessionUsage(
            [
                "input": .number(1_200),
                "output": .number(300),
                "total": .number(1_500),
                "calls": .number(4),
                "context_used": .number(10),
                "context_max": .number(20),
                "compressions": .number(-2),
            ],
            breakdown: [
                "context_used": .number(30),
                "context_max": .number(120),
                "categories": .array([
                    .object([
                        "id": .string("conversation"),
                        "label": .string("Conversation"),
                        "tokens": .number(20),
                    ]),
                    .object([
                        "id": .string("invalid"),
                        "label": .string(""),
                        "tokens": .number(0),
                    ]),
                ]),
            ]
        )
        XCTAssertEqual(usage.contextUsed, 30)
        XCTAssertEqual(usage.contextMax, 120)
        XCTAssertEqual(usage.contextPercent, 25)
        XCTAssertEqual(
            usage.categories,
            [ContextCategory(id: "conversation", label: "Conversation", tokens: 20)]
        )
        XCTAssertEqual(usage.compactionCount, 0)
    }

    func testGatewayStatsCodecClampsInvalidMetricsAndSkipsBlankRows() {
        let stats = decodeGatewayStats(
            [
                "period_days": .number(7),
                "totals": .object([
                    "total_input": .number(100),
                    "total_output": .number(25),
                    "total_sessions": .number(-1),
                    "total_estimated_cost": .number(0.5),
                ]),
                "daily": .array([
                    .object([
                        "day": .string("2026-07-24"),
                        "input_tokens": .number(80),
                        "output_tokens": .number(20),
                    ]),
                    .object(["day": .string(" ")]),
                ]),
                "by_model": .array([
                    .object([
                        "model": .string("model-a"),
                        "input_tokens": .number(90),
                        "output_tokens": .number(10),
                    ]),
                ]),
                "tools": .array([
                    .object([
                        "tool": .string("terminal"),
                        "count": .number(3),
                    ]),
                ]),
                "skills": .object([
                    "top_skills": .array([
                        .object([
                            "skill": .string("verify"),
                            "total_count": .number(2),
                        ]),
                    ]),
                ]),
            ],
            fallbackDays: 30
        )
        XCTAssertEqual(stats.periodDays, 7)
        XCTAssertEqual(stats.totals.recordedTokens, 125)
        XCTAssertEqual(stats.totals.sessions, 0)
        XCTAssertEqual(stats.daily.map(\.day), ["2026-07-24"])
        XCTAssertEqual(stats.models.map(\.model), ["model-a"])
        XCTAssertEqual(stats.tools, [NamedUsageStat(name: "terminal", count: 3)])
        XCTAssertEqual(stats.skills, [NamedUsageStat(name: "verify", count: 2)])
    }

    func testExtremeUsageCountersSaturateWithoutOverflow() {
        XCTAssertNil(
            JSONValue.number(Double(Int.max)).lenientIntValue
        )
        XCTAssertEqual(
            JSONValue.number(Double(Int.min)).lenientIntValue,
            .min
        )

        let usage = decodeSessionUsage(
            [
                "input": .number(-1),
                "output": .number(-2),
                "total": .number(-3),
                "calls": .number(-4),
                "context_used": .string(String(Int.max)),
                "context_max": .string(String(Int.max)),
                "context_percent": .number(9_999),
            ],
            breakdown: nil
        )
        XCTAssertEqual(usage.inputTokens, 0)
        XCTAssertEqual(usage.outputTokens, 0)
        XCTAssertEqual(usage.totalTokens, 0)
        XCTAssertEqual(usage.apiCalls, 0)
        XCTAssertEqual(usage.contextPercent, 100)
        XCTAssertEqual(
            boundedContextPercent(
                used: Int.max - 1,
                maximum: Int.max
            ),
            99
        )

        let stats = decodeGatewayStats(
            [
                "totals": .object([
                    "total_input": .number(Double(Int64.max)),
                    "total_output": .number(Double(Int64.max)),
                ]),
                "daily": .array([
                    .object([
                        "day": .string("2026-07-29"),
                        "input_tokens": .number(Double(Int64.max)),
                        "output_tokens": .number(Double(Int64.max)),
                        "sessions": .number(Double(Int64.max)),
                        "api_calls": .number(Double(Int64.max)),
                    ]),
                    .object([
                        "day": .string("2026-07-29"),
                        "sessions": .number(Double(Int64.max)),
                        "api_calls": .number(Double(Int64.max)),
                    ]),
                ]),
            ],
            fallbackDays: 30
        )
        XCTAssertEqual(stats.totals.inputTokens, .max)
        XCTAssertEqual(stats.totals.outputTokens, .max)
        XCTAssertEqual(stats.totals.recordedTokens, .max)
        XCTAssertEqual(stats.daily.first?.recordedTokens, .max)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 29)
        )!
        let momentum = stats.activityMomentum(today: today)
        XCTAssertEqual(momentum.weeklySessions, .max)
        XCTAssertEqual(momentum.weeklyCalls, .max)
        XCTAssertEqual(momentum.bestDaySessions, .max)
        XCTAssertEqual(saturatingUsageAdd(Int.max, 1), .max)
    }

    func testActivityMomentumUsesUTCStreakRules() {
        let stats = GatewayStats(
            periodDays: 30,
            totals: GatewayStatsTotals(
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                reasoningTokens: 0,
                sessions: 0,
                apiCalls: 0,
                estimatedCostUSD: 0,
                actualCostUSD: 0
            ),
            daily: [
                daily("2026-07-20", sessions: 3, calls: 4),
                daily("2026-07-21", sessions: 5, calls: 6),
                daily("2026-07-23", sessions: 2, calls: 3),
                daily("2026-07-24", sessions: 1, calls: 2),
                daily("invalid", sessions: 99, calls: 99),
            ],
            models: []
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 24)
        )!

        XCTAssertEqual(
            stats.activityMomentum(today: today),
            ActivityMomentum(
                currentStreak: 2,
                longestStreak: 2,
                activeDays: 4,
                weeklySessions: 11,
                weeklyCalls: 15,
                bestDaySessions: 5
            )
        )
    }

    func testHeatmapProjectionUsesThirteenUTCWeeksAndLogLevels() {
        let today = parseStatsDay("2026-07-24")!
        let projection = HeatmapProjection(
            daily: [
                daily("2026-04-26", sessions: 0, calls: 1),
                daily("2026-07-24", sessions: 0, calls: 100),
                daily("invalid", sessions: 9, calls: 9),
            ],
            now: today
        )

        XCTAssertEqual(projection.today, today)
        XCTAssertEqual(projection.start, parseStatsDay("2026-04-26"))
        XCTAssertEqual(projection.values.count, 91)
        XCTAssertEqual(projection.date(at: 89), today)
        XCTAssertEqual(
            projection.date(at: 90),
            parseStatsDay("2026-07-25")
        )
        XCTAssertEqual(projection.maximum, 100)
        XCTAssertEqual(projection.level(at: 0), 1)
        XCTAssertEqual(projection.level(at: 89), 4)
        XCTAssertEqual(projection.level(at: 90), 0)
        XCTAssertTrue(projection.accessibilityLabel.contains("2 active days"))
    }

    private func daily(
        _ day: String,
        sessions: Int64,
        calls: Int64
    ) -> DailyGatewayStats {
        DailyGatewayStats(
            day: day,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            reasoningTokens: 0,
            sessions: sessions,
            apiCalls: calls
        )
    }
}
