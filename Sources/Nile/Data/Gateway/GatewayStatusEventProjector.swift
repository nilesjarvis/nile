import Foundation

struct GatewayStatusEventProjector: Sendable {
    func project(_ frame: GatewayEventFrame) -> HermesStreamEvent {
        let data = frame.payload ?? [:]
        let kind = data.string("kind")
        let text = data.string("text")
        if kind.caseInsensitiveCompare("goal") == .orderedSame {
            return .goalUpdate(
                sessionID: frame.sessionID,
                text: text,
                update: parseGoalProgressUpdate(text)
            )
        }
        if kind.caseInsensitiveCompare("compacting") == .orderedSame
            || text.localizedCaseInsensitiveContains("Compacting context")
            || text.localizedCaseInsensitiveContains("Pre-API compression:") {
            return .compactionStarted(
                sessionID: frame.sessionID,
                estimatedTokens: preAPICompressionTokenEstimate(text)
            )
        }
        return .statusUpdate(sessionID: frame.sessionID, text: text)
    }

    private func preAPICompressionTokenEstimate(_ text: String) -> Int64? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"Pre-API compression:\s*~([\d,]+)\s+tokens"#,
                options: [.caseInsensitive]
            ),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            ),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Int64(text[range].replacingOccurrences(of: ",", with: ""))
    }

    private func parseGoalProgressUpdate(_ text: String) -> GoalProgressUpdate {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let continuation = continuationGoalMatch(normalized) {
            return GoalProgressUpdate(
                phase: .active,
                turnsUsed: continuation.turnsUsed,
                maxTurns: continuation.maxTurns,
                reason: continuation.reason.isEmpty ? nil : continuation.reason
            )
        }
        if normalized.hasPrefix("✓ Goal achieved:") {
            let reason = String(normalized.drop { $0 != ":" }.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return GoalProgressUpdate(
                phase: .finished,
                turnsUsed: nil,
                maxTurns: nil,
                reason: reason.isEmpty ? nil : reason
            )
        }
        if normalized.hasPrefix("⏳ Goal parked") {
            let reason: String
            if let colon = normalized.firstIndex(of: ":") {
                reason = String(normalized[normalized.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                reason = normalized
            }
            return GoalProgressUpdate(
                phase: .waiting,
                turnsUsed: nil,
                maxTurns: nil,
                reason: reason.isEmpty ? nil : reason
            )
        }
        if normalized.hasPrefix("⏸ Goal paused") {
            let turns = turnsMatch(normalized)
            let reason: String
            if let separator = normalized.firstIndex(of: "—") {
                reason = String(normalized[normalized.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                reason = normalized
            }
            return GoalProgressUpdate(
                phase: .paused,
                turnsUsed: turns?.turnsUsed,
                maxTurns: turns?.maxTurns,
                reason: reason.isEmpty ? nil : reason
            )
        }
        return GoalProgressUpdate(
            phase: nil,
            turnsUsed: nil,
            maxTurns: nil,
            reason: normalized.isEmpty ? nil : normalized
        )
    }

    private func continuationGoalMatch(
        _ value: String
    ) -> (turnsUsed: Int?, maxTurns: Int?, reason: String)? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"^↻ Continuing toward goal \((\d+)/(\d+)\):\s*(.*)$"#,
                options: [.dotMatchesLineSeparators]
            ),
            let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let usedRange = Range(match.range(at: 1), in: value),
            let maxRange = Range(match.range(at: 2), in: value),
            let reasonRange = Range(match.range(at: 3), in: value)
        else {
            return nil
        }
        return (
            Int(value[usedRange]),
            Int(value[maxRange]),
            value[reasonRange].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func turnsMatch(
        _ value: String
    ) -> (turnsUsed: Int?, maxTurns: Int?)? {
        guard
            let regex = try? NSRegularExpression(pattern: #"(\d+)/(\d+) turns"#),
            let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let usedRange = Range(match.range(at: 1), in: value),
            let maxRange = Range(match.range(at: 2), in: value)
        else {
            return nil
        }
        return (Int(value[usedRange]), Int(value[maxRange]))
    }
}
