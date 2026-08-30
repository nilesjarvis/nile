import Foundation

struct GoalStartAdmission: Equatable, Sendable {
    let objective: String
    let maxTurns: Int?
}

enum GoalStartAdmissionDecision: Equatable, Sendable {
    case allowed(GoalStartAdmission)
    case rejected(String)
}

enum GoalContinuationDecision: Equatable, Sendable {
    case allowed
    case ignored
    case rejected(String)
}

struct GoalCompletionReduction: Equatable, Sendable {
    let goal: HermesGoal?
    let shouldRefreshStatus: Bool
}

struct GoalProgressReduction: Equatable, Sendable {
    let goal: HermesGoal
    let isFinalizing: Bool
    let shouldRefreshStatus: Bool
}

struct GoalStatusReduction: Equatable, Sendable {
    let goal: HermesGoal?
    let isFinalizing: Bool
}

enum GoalRuntimePolicy {
    static func startAdmission(
        objective: String,
        maxTurns: Int?,
        availability: GoalAvailability,
        context: GoalActionContext,
        currentGoal: HermesGoal?
    ) -> GoalStartAdmissionDecision {
        let normalized = objective
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard availability == .available else {
            return .rejected(
                "Standing goals are unavailable on this Hermes profile."
            )
        }
        guard !normalized.isEmpty else {
            return .rejected(
                "Choose a quick goal or describe what done looks like."
            )
        }
        guard normalized.count <= 2_000 else {
            return .rejected("Keep the goal under 2,000 characters.")
        }
        guard maxTurns.map({ (1...100).contains($0) }) ?? true else {
            return .rejected("Choose a turn budget between 1 and 100.")
        }
        guard !context.isUpdatingSessionControls else {
            return .rejected(
                "Wait for the session setting to finish before starting a goal."
            )
        }
        guard !context.isSending, !context.isStopping else {
            return .rejected(
                "Wait for the current turn to finish before starting a goal."
            )
        }
        guard !context.hasPendingAttachments, !context.isAttaching else {
            return .rejected(
                "Send or remove the queued photo before starting a goal."
            )
        }
        guard currentGoal == nil || currentGoal?.phase == .finished else {
            return .rejected(
                "Pause and clear the current goal before replacing it."
            )
        }
        return .allowed(
            GoalStartAdmission(
                objective: normalized,
                maxTurns: maxTurns
            )
        )
    }

    static func resumeError(
        context: GoalActionContext,
        isMutating: Bool
    ) -> String? {
        if context.isUpdatingSessionControls {
            return "Wait for the session setting to finish before resuming."
        }
        if context.isSending
            || context.hasPendingAttachments
            || isMutating {
            return "Wait for the current turn and queued photos before resuming."
        }
        return nil
    }

    static func continuationDecision(
        context: GoalActionContext,
        isMutating: Bool
    ) -> GoalContinuationDecision {
        if context.isUpdatingSessionControls {
            return .rejected(
                "Wait for the session setting to finish before continuing."
            )
        }
        if context.isSending || isMutating {
            return .ignored
        }
        if context.hasPendingAttachments {
            return .rejected(
                "Send or remove the queued photo before continuing the goal."
            )
        }
        return .allowed
    }

    static func promptFailureMessage(
        errorMessage: String?,
        uncertain: Bool
    ) -> String {
        uncertain
            ? "The goal is active, but Nile could not confirm whether its next turn started."
            : "The goal is active, but its next turn did not start: \(errorMessage ?? "send was interrupted")"
    }

    static func isUncertainMutationFailure(_ error: any Error) -> Bool {
        guard let hermes = error as? HermesError else {
            return true
        }
        return hermes.isConnectionFailure || hermes.requestMayHaveSucceeded
    }

    static func assistantCompletion(
        goal: HermesGoal?,
        isFinalizing: Bool
    ) -> GoalCompletionReduction {
        let awaitingVerdict = goal?.isLoopAlive == true || isFinalizing
        let updated: HermesGoal?
        if awaitingVerdict, let goal {
            updated = replacing(
                goal,
                phase: .checking,
                turnsUsed: min(goal.maxTurns, goal.turnsUsed + 1),
                maxTurns: nil,
                lastReason: nil,
                pausedReason: nil
            )
        } else {
            updated = goal
        }
        return GoalCompletionReduction(
            goal: updated,
            shouldRefreshStatus: isFinalizing
        )
    }

    static func progress(
        goal: HermesGoal,
        update: GoalProgressUpdate,
        isSending: Bool,
        isFinalizing: Bool
    ) -> GoalProgressReduction {
        let phase = update.phase ?? goal.phase
        if phase == .finished {
            let updated = replacing(
                goal,
                phase: isSending ? .active : .checking,
                turnsUsed: update.turnsUsed,
                maxTurns: update.maxTurns,
                lastReason: update.reason,
                pausedReason: nil
            )
            if goal.phase == .finished, !isFinalizing {
                return GoalProgressReduction(
                    goal: replacingPhase(updated, with: .finished),
                    isFinalizing: false,
                    shouldRefreshStatus: false
                )
            }
            return GoalProgressReduction(
                goal: updated,
                isFinalizing: true,
                shouldRefreshStatus: !isSending
            )
        }
        return GoalProgressReduction(
            goal: replacing(
                goal,
                phase: phase,
                turnsUsed: update.turnsUsed,
                maxTurns: update.maxTurns,
                lastReason: update.reason,
                pausedReason: phase == .paused
                    ? update.reason ?? goal.pausedReason
                    : goal.pausedReason
            ),
            isFinalizing: false,
            shouldRefreshStatus: false
        )
    }

    static func reconcileStatus(
        authoritative: HermesGoal?,
        currentGoal: HermesGoal?,
        isFinalizing: Bool,
        isSessionSending: Bool
    ) -> GoalStatusReduction {
        let terminal = authoritative == nil
            || authoritative?.phase == .waiting
            || authoritative?.phase == .paused
            || authoritative?.phase == .finished
        let resolved: HermesGoal?
        if isFinalizing, isSessionSending, terminal {
            resolved = currentGoal
        } else if isFinalizing, !terminal, let authoritative {
            resolved = replacingPhase(authoritative, with: .checking)
        } else {
            resolved = authoritative
        }
        return GoalStatusReduction(
            goal: resolved,
            isFinalizing: terminal ? false : isFinalizing
        )
    }

    static func replacingPhase(
        _ goal: HermesGoal,
        with phase: GoalPhase
    ) -> HermesGoal {
        replacing(
            goal,
            phase: phase,
            turnsUsed: nil,
            maxTurns: nil,
            lastReason: nil,
            pausedReason: nil
        )
    }

    private static func replacing(
        _ goal: HermesGoal,
        phase: GoalPhase,
        turnsUsed: Int?,
        maxTurns: Int?,
        lastReason: String?,
        pausedReason: String?
    ) -> HermesGoal {
        HermesGoal(
            objective: goal.objective,
            phase: phase,
            turnsUsed: turnsUsed ?? goal.turnsUsed,
            maxTurns: maxTurns ?? goal.maxTurns,
            lastReason: lastReason ?? goal.lastReason,
            pausedReason: pausedReason ?? goal.pausedReason
        )
    }
}
