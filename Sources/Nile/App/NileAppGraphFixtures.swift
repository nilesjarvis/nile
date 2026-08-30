import Foundation

enum NileDebugFixturePolicy {
    static func arguments(from arguments: [String]) -> [String] {
#if DEBUG
        arguments
#elseif NILE_LOCAL_RELEASE
        arguments.filter {
            $0 == "--nile-performance-streaming-stress"
        }
#else
        []
#endif
    }
}

/// Deterministic fixture state and sample payloads used by `NileAppGraph`.
///
/// Fake capability collaborators extend this namespace from their dedicated
/// source so neither concern accumulates in production dependency wiring.
#if DEBUG || NILE_LOCAL_RELEASE
enum NileAppGraphFixtures {
    enum StreamingTranscriptFixture {
        case empty
        case partial
        case table

        var content: String {
            switch self {
            case .empty:
                ""
            case .partial:
                """
                ## Live response

                A **partial response** is arriving progressively.
                """
            case .table:
                """
                ## Release readiness

                | Area | Status | Checks |
                | :--- | :---: | ---: |
                | Gateway authentication | **Ready** | 18 |
                | Session recovery | Needs review | 12 |
                | Accessibility | Ready | 7 |
                """
            }
        }

        var images: [MessageImage] {
            switch self {
            case .empty:
                return []
            case .partial:
                return [
                    MessageImage(
                        base64:
                            "iVBORw0KGgoAAAANSUhEUgAAAGAAAAA2CAYAAAA4T5zSAAAAkUlEQVR42u3coRHAIBREQWpBpQYsKiINMUMvVEJroNLCR7DiNXDrL42+ls6VjAAAwF9+PgUEAAAAAAAAAAAAAAAAAAAAAAAAAIBxAFwO8NapgAAAAAAAAAAAAAAAAAAAAAAAAAAAMA4AAAIAQKcASpsKCAAAAAAAAAAAAAAAAAAAAAAAAAAA4wC4HEAeswAotg1lLjCxBlaKcQAAAABJRU5ErkJggg==",
                        label: "Streaming inline image"
                    ),
                ]
            case .table:
                return []
            }
        }

        var isStreaming: Bool {
            switch self {
            case .empty, .partial:
                true
            case .table:
                false
            }
        }
    }

    enum ComposerActivityFixture {
        case idle
        case working
        case stopping
        case needsInput

        init?(arguments: [String]) {
            if arguments.contains("--nile-fixture-composer-idle") {
                self = .idle
            } else if arguments.contains("--nile-fixture-composer-working") {
                self = .working
            } else if arguments.contains("--nile-fixture-composer-stopping") {
                self = .stopping
            } else if arguments.contains(
                "--nile-fixture-composer-needs-input"
            ) {
                self = .needsInput
            } else {
                return nil
            }
        }

        @MainActor
        func apply(to model: SessionListModel) {
            guard self != .idle else {
                return
            }
            model.isSending = true
            model.isStopping = self == .stopping
            model.turnStartedAt = Date().addingTimeInterval(-8)
            guard let selectedSessionID = model.selectedSessionID else {
                return
            }
            model.activeStatuses[selectedSessionID] =
                self == .needsInput ? "waiting" : "working"
        }
    }

    static func sessionUsage() -> SessionUsage {
        SessionUsage(
            inputTokens: 12_400,
            outputTokens: 3_250,
            totalTokens: 15_650,
            apiCalls: 18,
            contextPercent: 62,
            contextUsed: 124_000,
            contextMax: 200_000,
            categories: [
                ContextCategory(
                    id: "system_prompt",
                    label: "System prompt",
                    tokens: 18_000
                ),
                ContextCategory(
                    id: "tool_definitions",
                    label: "Tool definitions",
                    tokens: 27_000
                ),
                ContextCategory(id: "rules", label: "Rules", tokens: 11_000),
                ContextCategory(id: "skills", label: "Skills", tokens: 8_000),
                ContextCategory(
                    id: "conversation",
                    label: "Conversation",
                    tokens: 60_000
                ),
            ],
            compactionCount: 2
        )
    }

    static func gatewayStatsReferenceDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 24)
        )!
    }

    static func gatewayStats(
        days: Int,
        referenceDate: Date
    ) -> GatewayStats {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: referenceDate)
        let daily = (0..<days).map { offset in
            let date = calendar.date(
                byAdding: .day,
                value: offset - days + 1,
                to: today
            )!
            let components = calendar.dateComponents(
                [.year, .month, .day],
                from: date
            )
            let day = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
            let active = offset % 3 != 0
            return DailyGatewayStats(
                day: day,
                inputTokens: active ? Int64(8_000 + offset * 470) : 0,
                outputTokens: active ? Int64(2_000 + offset * 190) : 0,
                cacheReadTokens: active ? Int64(offset * 120) : 0,
                reasoningTokens: active ? Int64(offset * 75) : 0,
                sessions: active ? Int64(1 + offset % 4) : 0,
                apiCalls: active ? Int64(2 + offset % 7) : 0
            )
        }
        return GatewayStats(
            periodDays: days,
            totals: GatewayStatsTotals(
                inputTokens: 284_500,
                outputTokens: 71_800,
                cacheReadTokens: 92_400,
                reasoningTokens: 18_900,
                sessions: 42,
                apiCalls: 168,
                estimatedCostUSD: 7.42,
                actualCostUSD: 0
            ),
            daily: daily,
            models: [
                ModelGatewayStats(
                    model: "gemini-3-pro",
                    inputTokens: 198_000,
                    outputTokens: 51_000,
                    sessions: 29,
                    apiCalls: 112
                ),
                ModelGatewayStats(
                    model: "claude-sonnet-4",
                    inputTokens: 86_500,
                    outputTokens: 20_800,
                    sessions: 13,
                    apiCalls: 56
                ),
            ],
            tools: [
                NamedUsageStat(name: "terminal", count: 86),
                NamedUsageStat(name: "read_file", count: 64),
                NamedUsageStat(name: "apply_patch", count: 31),
            ],
            skills: [
                NamedUsageStat(name: "verify", count: 14),
                NamedUsageStat(name: "github", count: 8),
            ]
        )
    }
}
#endif
