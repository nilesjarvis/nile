import Foundation

private let goalTurnsExpression = try! NSRegularExpression(
    pattern: #"\b(\d+)/(\d+) turns\b"#
)
func parseGoalStatusOutput(_ output: String) throws -> HermesGoal? {
    let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized == "No active goal. Set one with /goal <text>." {
        return nil
    }
    let phase: GoalPhase
    switch normalized {
    case let text where text.hasPrefix("⊙ Goal ("):
        phase = .active
    case let text where text.hasPrefix("⏳ Goal ("):
        phase = .waiting
    case let text where text.hasPrefix("⏸ Goal ("):
        phase = .paused
    case let text where text.hasPrefix("✓ Goal done ("):
        phase = .finished
    default:
        throw malformedGoalResponse(
            method: "goal.status",
            mutationMayHaveSucceeded: false
        )
    }

    guard let turnsMatch = firstMatch(
        goalTurnsExpression,
        in: normalized
    ),
    let turnsUsed = intCapture(1, in: normalized, match: turnsMatch),
    let maxTurns = intCapture(2, in: normalized, match: turnsMatch) else {
        throw malformedGoalResponse(
            method: "goal.status",
            mutationMayHaveSucceeded: false
        )
    }
    let searchStart = turnsMatch.range.location + turnsMatch.range.length
    guard let separator = normalized.range(
        of: "): ",
        range: String.Index(utf16Offset: searchStart, in: normalized)
            ..< normalized.endIndex
    ) else {
        throw malformedGoalResponse(
            method: "goal.status",
            mutationMayHaveSucceeded: false
        )
    }
    let headerEnd = normalized.index(after: separator.lowerBound)
    let header = String(normalized[..<headerEnd])
    let objective = String(normalized[separator.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !objective.isEmpty,
          turnsUsed >= 0,
          maxTurns > 0,
          turnsUsed <= maxTurns else {
        throw malformedGoalResponse(
            method: "goal.status",
            mutationMayHaveSucceeded: false
        )
    }
    let pausedReason = header.range(of: " — ").map {
        String(header[$0.upperBound...])
            .trimmingCharacters(in: CharacterSet(
                charactersIn: ")"
            ).union(.whitespacesAndNewlines))
    }.flatMap { $0.isEmpty ? nil : $0 }
    return HermesGoal(
        objective: objective,
        phase: phase,
        turnsUsed: turnsUsed,
        maxTurns: maxTurns,
        pausedReason: pausedReason
    )
}

func parseGoalSetNotice(
    _ notice: String,
    expectedObjective: String
) throws -> HermesGoal {
    let firstLine = notice
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let prefix = "⊙ Goal set ("
    let suffix = "-turn budget): "
    guard firstLine.hasPrefix(prefix),
          let suffixRange = firstLine.range(
              of: suffix,
              range: firstLine.index(
                  firstLine.startIndex,
                  offsetBy: prefix.count
              )..<firstLine.endIndex
          ),
          let maxTurns = Int(
              firstLine[
                  firstLine.index(
                      firstLine.startIndex,
                      offsetBy: prefix.count
                  )..<suffixRange.lowerBound
              ]
          ) else {
        throw malformedGoalResponse(
            method: "goal.set",
            mutationMayHaveSucceeded: true
        )
    }
    let objective = String(firstLine[suffixRange.upperBound...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard maxTurns > 0, objective == expectedObjective else {
        throw malformedGoalResponse(
            method: "goal.set",
            mutationMayHaveSucceeded: true
        )
    }
    return HermesGoal(
        objective: objective,
        phase: .active,
        turnsUsed: 0,
        maxTurns: maxTurns
    )
}

func malformedGoalResponse(
    method: String,
    mutationMayHaveSucceeded: Bool
) -> HermesError {
    HermesError(
        "Hermes returned an unsupported response to \(method)",
        retryable: false,
        requestMayHaveSucceeded: mutationMayHaveSucceeded
    )
}

private func firstMatch(
    _ expression: NSRegularExpression,
    in text: String
) -> NSTextCheckingResult? {
    expression.firstMatch(
        in: text,
        range: NSRange(text.startIndex..<text.endIndex, in: text)
    )
}

private func intCapture(
    _ index: Int,
    in text: String,
    match: NSTextCheckingResult
) -> Int? {
    stringCapture(index, in: text, match: match).flatMap(Int.init)
}

private func stringCapture(
    _ index: Int,
    in text: String,
    match: NSTextCheckingResult
) -> String? {
    guard index < match.numberOfRanges,
          let range = Range(match.range(at: index), in: text) else {
        return nil
    }
    return String(text[range])
}
