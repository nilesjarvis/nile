struct UsageSummary: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

struct ContextCategory: Equatable, Sendable {
    let id: String
    let label: String
    let tokens: Int
}

struct SessionUsage: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let apiCalls: Int
    let contextPercent: Int?
    let contextUsed: Int?
    let contextMax: Int?
    let categories: [ContextCategory]
    let compactionCount: Int

    init(
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        apiCalls: Int,
        contextPercent: Int?,
        contextUsed: Int?,
        contextMax: Int?,
        categories: [ContextCategory] = [],
        compactionCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.apiCalls = apiCalls
        self.contextPercent = contextPercent
        self.contextUsed = contextUsed
        self.contextMax = contextMax
        self.categories = categories
        self.compactionCount = compactionCount
    }
}

func boundedContextPercent(used: Int, maximum: Int) -> Int {
    guard used > 0, maximum > 0 else {
        return 0
    }
    guard used < maximum else {
        return 100
    }
    return min(
        99,
        max(0, Int(Double(used) / Double(maximum) * 100))
    )
}

func saturatingUsageAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let left = max(0, lhs)
    let right = max(0, rhs)
    let (sum, overflow) = left.addingReportingOverflow(right)
    return overflow ? .max : sum
}

func saturatingUsageAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let left = max(0, lhs)
    let right = max(0, rhs)
    let (sum, overflow) = left.addingReportingOverflow(right)
    return overflow ? .max : sum
}

struct GatewayStats: Equatable, Sendable {
    let periodDays: Int
    let totals: GatewayStatsTotals
    let daily: [DailyGatewayStats]
    let models: [ModelGatewayStats]
    let tools: [NamedUsageStat]
    let skills: [NamedUsageStat]

    init(
        periodDays: Int,
        totals: GatewayStatsTotals,
        daily: [DailyGatewayStats],
        models: [ModelGatewayStats],
        tools: [NamedUsageStat] = [],
        skills: [NamedUsageStat] = []
    ) {
        self.periodDays = periodDays
        self.totals = totals
        self.daily = daily
        self.models = models
        self.tools = tools
        self.skills = skills
    }
}

struct GatewayStatsTotals: Equatable, Sendable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let reasoningTokens: Int64
    let sessions: Int64
    let apiCalls: Int64
    let estimatedCostUSD: Double
    let actualCostUSD: Double

    var recordedTokens: Int64 {
        saturatingUsageAdd(inputTokens, outputTokens)
    }
}

struct DailyGatewayStats: Equatable, Sendable {
    let day: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let reasoningTokens: Int64
    let sessions: Int64
    let apiCalls: Int64

    var recordedTokens: Int64 {
        saturatingUsageAdd(inputTokens, outputTokens)
    }
}

struct ModelGatewayStats: Equatable, Sendable {
    let model: String
    let inputTokens: Int64
    let outputTokens: Int64
    let sessions: Int64
    let apiCalls: Int64

    var recordedTokens: Int64 {
        saturatingUsageAdd(inputTokens, outputTokens)
    }
}

struct NamedUsageStat: Equatable, Sendable {
    let name: String
    let count: Int64
}

protocol HermesSessionUsageServing: Sendable {
    func sessionUsage(liveSessionID: String) async throws -> SessionUsage
}

extension HermesSessionUsageServing {
    func sessionUsage(liveSessionID: String) async throws -> SessionUsage {
        throw HermesError(
            "Session usage is unavailable for this repository",
            retryable: false
        )
    }
}

protocol HermesGatewayStatsServing: Sendable {
    func gatewayStats(days: Int) async throws -> GatewayStats
}

extension HermesGatewayStatsServing {
    func gatewayStats() async throws -> GatewayStats {
        try await gatewayStats(days: 30)
    }

    func gatewayStats(days: Int) async throws -> GatewayStats {
        throw HermesError(
            "Usage statistics are unavailable for this repository",
            retryable: false
        )
    }
}

protocol HermesUsageServing:
    HermesSessionUsageServing,
    HermesGatewayStatsServing
{}
