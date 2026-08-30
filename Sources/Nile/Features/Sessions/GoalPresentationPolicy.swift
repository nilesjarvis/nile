import SwiftUI

/// Shared, stateless standing-goal status presentation.
enum GoalPresentationPolicy {
    static func statusSummary(
        for goal: HermesGoal,
        isFinalizing: Bool
    ) -> String {
        if isFinalizing {
            return "Finalizing result…"
        }
        let label = switch goal.phase {
        case .active: "Active"
        case .checking: "Checking result"
        case .waiting: "Waiting"
        case .paused: "Paused"
        case .finished: "Finished"
        }
        return "\(label)  ·  \(goal.turnsUsed)/\(goal.maxTurns) turns"
    }

    static func statusColor(
        for goal: HermesGoal,
        isFinalizing: Bool
    ) -> Color {
        if isFinalizing {
            return NileColors.accent
        }
        return switch goal.phase {
        case .active, .checking: NileColors.accent
        case .waiting: NileColors.warning
        case .paused: NileColors.stopped
        case .finished: NileColors.muted
        }
    }
}
