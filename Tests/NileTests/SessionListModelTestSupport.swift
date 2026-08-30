import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func session(
        id: String,
        title: String? = nil,
        source: String
    ) -> HermesSession {
        HermesSession(
            id: id,
            title: title ?? id,
            preview: nil,
            source: source,
            messageCount: 0,
            startedAt: nil,
            lastMessageAt: nil
        )
    }

    func liveSession(
        id: String,
        model: String = "claude-haiku",
        provider: String = "anthropic"
    ) -> LiveSession {
        LiveSession(
            liveID: "live-\(id)",
            storedID: id,
            info: SessionInfo(
                model: model,
                provider: provider,
                reasoningEffort: "medium",
                reasoningEffortSessionScopeSupported: true
            ),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
    }

    func delegationEvent(
        id: String,
        terminal: SubagentTerminalStatus?,
        summary: String?
    ) -> SubagentEventData {
        SubagentEventData(
            goal: "Verify delegated workflow",
            taskCount: 1,
            taskIndex: 0,
            subagentID: id,
            parentID: "parent",
            childSessionID: "child-1",
            depth: 1,
            model: "model",
            toolCount: 2,
            toolsets: ["terminal"],
            text: terminal == nil ? "Testing" : nil,
            toolName: "terminal",
            toolPreview: "xcodebuild test",
            terminalStatus: terminal,
            rawTerminalStatus: terminal?.rawValue,
            summary: summary,
            durationSeconds: terminal == nil ? nil : 5,
            inputTokens: 100,
            outputTokens: 20,
            reasoningTokens: nil,
            apiCalls: 2,
            filesRead: [],
            filesWritten: [],
            outputTail: []
        )
    }

    func modelOptionsFixture() -> ModelOptions {
        ModelOptions(
            model: "claude-haiku",
            provider: "anthropic",
            providers: [
                ModelProvider(
                    slug: "anthropic",
                    name: "Anthropic",
                    authenticated: true,
                    isCurrent: true,
                    models: ["claude-haiku", "claude-sonnet-4"],
                    capabilities: [
                        "claude-haiku": ModelCapabilities(
                            fast: true,
                            reasoning: false
                        ),
                        "claude-sonnet-4": ModelCapabilities(
                            fast: false,
                            reasoning: true
                        ),
                    ],
                    pricing: [
                        "claude-haiku": ModelPricing(
                            input: "1",
                            output: "5",
                            cache: nil,
                            free: false
                        ),
                        "claude-sonnet-4": ModelPricing(
                            input: "3",
                            output: "15",
                            cache: nil,
                            free: false
                        ),
                    ]
                ),
            ]
        )
    }

    func usageFixture(
        input: Int,
        contextPercent: Int?,
        categories: [ContextCategory] = []
    ) -> SessionUsage {
        SessionUsage(
            inputTokens: input,
            outputTokens: 100,
            totalTokens: input + 100,
            apiCalls: 3,
            contextPercent: contextPercent,
            contextUsed: contextPercent,
            contextMax: contextPercent == nil ? nil : 100,
            categories: categories
        )
    }

    func statsFixture(
        days: Int,
        sessions: Int64
    ) -> GatewayStats {
        GatewayStats(
            periodDays: days,
            totals: GatewayStatsTotals(
                inputTokens: 10,
                outputTokens: 5,
                cacheReadTokens: 2,
                reasoningTokens: 1,
                sessions: sessions,
                apiCalls: sessions,
                estimatedCostUSD: 0,
                actualCostUSD: 0
            ),
            daily: [
                DailyGatewayStats(
                    day: "2026-07-23",
                    inputTokens: 10,
                    outputTokens: 5,
                    cacheReadTokens: 2,
                    reasoningTokens: 1,
                    sessions: sessions,
                    apiCalls: sessions
                ),
            ],
            models: []
        )
    }

    func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
    }

    func eventuallyAsync(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
    }

    func imageFixtureData() -> Data {
        Data(
            base64Encoded:
                "/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjExLjEwMAD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABAEBAQAAAAAAAAAAAAAAAAAAAAYQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAAgACADASIAAhEAAxEA/9oADAMBAAIRAxEAPwCYBXo8AAAAAB//2Q=="
        ) ?? Data()
    }
}
