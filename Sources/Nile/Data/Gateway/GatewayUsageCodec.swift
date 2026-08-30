import Foundation

func decodeSessionUsage(
    _ usage: JSONValue.Object,
    breakdown: JSONValue.Object?
) -> SessionUsage {
    let contextUsed = positiveInt(breakdown?["context_used"])
        ?? positiveInt(usage["context_used"])
    let contextMax = positiveInt(breakdown?["context_max"])
        ?? positiveInt(usage["context_max"])
    let contextPercent: Int? = if let contextUsed, let contextMax {
        reportedPercent(breakdown?["context_percent"])
            ?? reportedPercent(usage["context_percent"])
            ?? boundedContextPercent(
                used: contextUsed,
                maximum: contextMax
            )
    } else {
        nil
    }
    return SessionUsage(
        inputTokens: max(0, usage.int("input")),
        outputTokens: max(0, usage.int("output")),
        totalTokens: max(0, usage.int("total")),
        apiCalls: max(0, usage.int("calls")),
        contextPercent: contextPercent,
        contextUsed: contextUsed,
        contextMax: contextMax,
        categories: decodeContextCategories(breakdown),
        compactionCount: max(0, usage.int("compressions"))
    )
}

func decodeGatewayStats(
    _ object: JSONValue.Object,
    fallbackDays: Int
) -> GatewayStats {
    let totals = object["totals"]?.objectValue ?? [:]
    let skillRows = object["skills"]?.objectValue?["top_skills"]?
        .arrayValue?.objectValues ?? []
    let periodDays = positiveInt(object["period_days"]) ?? fallbackDays
    return GatewayStats(
        periodDays: periodDays,
        totals: GatewayStatsTotals(
            inputTokens: nonNegativeInt64(totals["total_input"]),
            outputTokens: nonNegativeInt64(totals["total_output"]),
            cacheReadTokens: nonNegativeInt64(totals["total_cache_read"]),
            reasoningTokens: nonNegativeInt64(totals["total_reasoning"]),
            sessions: nonNegativeInt64(totals["total_sessions"]),
            apiCalls: nonNegativeInt64(totals["total_api_calls"]),
            estimatedCostUSD: nonNegativeDouble(
                totals["total_estimated_cost"]
            ),
            actualCostUSD: nonNegativeDouble(totals["total_actual_cost"])
        ),
        daily: (object["daily"]?.arrayValue?.objectValues ?? [])
            .compactMap { row in
                guard let day = cleanString(row["day"]) else {
                    return nil
                }
                return DailyGatewayStats(
                    day: day,
                    inputTokens: nonNegativeInt64(row["input_tokens"]),
                    outputTokens: nonNegativeInt64(row["output_tokens"]),
                    cacheReadTokens: nonNegativeInt64(
                        row["cache_read_tokens"]
                    ),
                    reasoningTokens: nonNegativeInt64(
                        row["reasoning_tokens"]
                    ),
                    sessions: nonNegativeInt64(row["sessions"]),
                    apiCalls: nonNegativeInt64(row["api_calls"])
                )
            },
        models: (object["by_model"]?.arrayValue?.objectValues ?? [])
            .compactMap { row in
                guard let model = cleanString(row["model"]) else {
                    return nil
                }
                return ModelGatewayStats(
                    model: model,
                    inputTokens: nonNegativeInt64(row["input_tokens"]),
                    outputTokens: nonNegativeInt64(row["output_tokens"]),
                    sessions: nonNegativeInt64(row["sessions"]),
                    apiCalls: nonNegativeInt64(row["api_calls"])
                )
            },
        tools: (object["tools"]?.arrayValue?.objectValues ?? [])
            .compactMap { row in
                guard let name = cleanString(row["tool"]) else {
                    return nil
                }
                return NamedUsageStat(
                    name: name,
                    count: nonNegativeInt64(row["count"])
                )
            },
        skills: skillRows.compactMap { row in
            guard let name = cleanString(row["skill"]) else {
                return nil
            }
            return NamedUsageStat(
                name: name,
                count: nonNegativeInt64(row["total_count"])
            )
        }
    )
}

private func decodeContextCategories(
    _ breakdown: JSONValue.Object?
) -> [ContextCategory] {
    (breakdown?["categories"]?.arrayValue?.objectValues ?? [])
        .compactMap { row in
            let tokens = row.int("tokens")
            let id = row.string("id")
            let label = cleanString(row["label"]) ?? id
            guard tokens > 0, !label.isBlank else {
                return nil
            }
            return ContextCategory(id: id, label: label, tokens: tokens)
        }
}

private func positiveInt(_ value: JSONValue?) -> Int? {
    value?.lenientIntValue.flatMap { $0 > 0 ? $0 : nil }
}

private func reportedPercent(_ value: JSONValue?) -> Int? {
    value?.lenientIntValue.flatMap {
        $0 >= 0 ? min(100, $0) : nil
    }
}

private func nonNegativeInt64(_ value: JSONValue?) -> Int64 {
    guard let number = value?.lenientDoubleValue,
          number >= 0 else {
        return 0
    }
    guard number < Double(Int64.max) else {
        return .max
    }
    return Int64(number)
}

private func nonNegativeDouble(_ value: JSONValue?) -> Double {
    guard let number = value?.lenientDoubleValue, number >= 0 else {
        return 0
    }
    return number
}

private func cleanString(_ value: JSONValue?) -> String? {
    guard let value, value != .null else {
        return nil
    }
    let string = value.lenientStringValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return string.isEmpty ? nil : string
}
