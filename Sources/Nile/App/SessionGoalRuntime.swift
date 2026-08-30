import Foundation
import Observation

@MainActor
@Observable
final class SessionGoalRuntime {
    var availability = GoalAvailability.unknown
    var goal: HermesGoal?
    var isSheetVisible = false
    var isMutating = false
    var isFinalizing = false
    var error: String?

    let repository: (any HermesGoalServing)?
    let status: GoalStatusRuntime
    let mutationLifecycle = SessionGoalMutationLifecycle()
    var lifecycleGeneration: Int64 = 0
    private var currentOwner: Owner?

    init(repository: (any HermesGoalServing)?) {
        self.repository = repository
        status = GoalStatusRuntime(repository: repository)
    }

    func installFixture(goal: HermesGoal?, showsSheet: Bool) {
        availability = .available
        self.goal = goal
        isSheetVisible = showsSheet
    }

    func reset() {
        mutationLifecycle.reset()
        status.cancel()
        lifecycleGeneration &+= 1
        currentOwner = nil
        availability = .unknown
        goal = nil
        isSheetVisible = false
        isMutating = false
        isFinalizing = false
        error = nil
    }

    func dismissSheet() {
        isSheetVisible = false
        error = nil
    }

    func presentSheet() {
        error = nil
        isSheetVisible = true
    }

    func synchronize(owner: Owner) async -> Synchronization? {
        activate(owner: owner)
        let lifecycle = lifecycleGeneration
        guard status.isBackedByRepository else {
            availability = .available
            return Synchronization(goal: goal)
        }
        guard let result = await status.synchronize(
            liveSessionID: owner.liveSessionID
        ), owner == currentOwner, lifecycle == lifecycleGeneration else {
            return nil
        }
        switch result {
        case let .available(authoritative):
            goal = authoritative
            availability = .available
            isMutating = false
            isFinalizing = false
            error = nil
            return Synchronization(goal: authoritative)
        case .unavailable:
            goal = nil
            availability = .unavailable
            isSheetVisible = false
            isMutating = false
            isFinalizing = false
            self.error = nil
            return nil
        }
    }

    func beginPrompt(owner: Owner) -> Bool {
        guard matches(owner: owner) else {
            return false
        }
        goal = goal.map {
            GoalRuntimePolicy.replacingPhase($0, with: .active)
        }
        isFinalizing = false
        error = nil
        return true
    }

    func recordPromptFailure(
        owner: Owner,
        errorMessage: String?,
        uncertain: Bool
    ) {
        guard matches(owner: owner) else {
            return
        }
        error = GoalRuntimePolicy.promptFailureMessage(
            errorMessage: errorMessage,
            uncertain: uncertain
        )
    }

    func markMessageStarted(owner: Owner?) {
        guard let owner, matches(owner: owner),
              let goal, goal.isLoopAlive else {
            return
        }
        self.goal = GoalRuntimePolicy.replacingPhase(goal, with: .active)
    }

    func handleAssistantCompleted(
        owner: Owner?,
        isSessionSending: @escaping @MainActor @Sendable () -> Bool,
        onSynchronized: @escaping SynchronizationHandler
    ) {
        guard let owner, matches(owner: owner) else {
            return
        }
        let reduction = GoalRuntimePolicy.assistantCompletion(
            goal: goal,
            isFinalizing: isFinalizing
        )
        goal = reduction.goal
        if reduction.shouldRefreshStatus {
            refreshAfterCompletion(
                owner: owner,
                settlePendingCompletion: true,
                isSessionSending: isSessionSending,
                onSynchronized: onSynchronized
            )
        }
    }

    func handleProgressUpdate(
        owner: Owner?,
        update: GoalProgressUpdate,
        isSending: Bool,
        isSessionSending: @escaping @MainActor @Sendable () -> Bool,
        onSynchronized: @escaping SynchronizationHandler
    ) {
        guard let owner, matches(owner: owner) else {
            return
        }
        guard let currentGoal = goal else {
            refreshAfterCompletion(
                owner: owner,
                settlePendingCompletion: false,
                isSessionSending: isSessionSending,
                onSynchronized: onSynchronized
            )
            return
        }
        let reduction = GoalRuntimePolicy.progress(
            goal: currentGoal,
            update: update,
            isSending: isSending,
            isFinalizing: isFinalizing
        )
        goal = reduction.goal
        isFinalizing = reduction.isFinalizing
        error = nil
        if reduction.shouldRefreshStatus {
            refreshAfterCompletion(
                owner: owner,
                settlePendingCompletion: true,
                isSessionSending: isSessionSending,
                onSynchronized: onSynchronized
            )
        }
    }

    func matches(owner: Owner) -> Bool {
        owner == currentOwner
    }

    private func activate(owner: Owner) {
        guard currentOwner != owner else {
            return
        }
        mutationLifecycle.reset()
        status.cancel()
        lifecycleGeneration &+= 1
        currentOwner = owner
        availability = .unknown
        goal = nil
        isSheetVisible = false
        isMutating = false
        isFinalizing = false
        error = nil
    }

    func prepareOwner(_ owner: Owner?) -> Owner? {
        guard let owner else {
            return nil
        }
        if currentOwner == nil {
            currentOwner = owner
        }
        return matches(owner: owner) ? owner : nil
    }

    private func refreshAfterCompletion(
        owner: Owner,
        settlePendingCompletion: Bool,
        isSessionSending: @escaping @MainActor @Sendable () -> Bool,
        onSynchronized: @escaping SynchronizationHandler
    ) {
        guard status.isBackedByRepository, matches(owner: owner) else {
            return
        }
        let lifecycle = lifecycleGeneration
        status.refresh(
            liveSessionID: owner.liveSessionID
        ) { [weak self] result in
            guard let self,
                  owner == currentOwner,
                  lifecycle == lifecycleGeneration else {
                return
            }
            switch result {
            case let .success(authoritative):
                let reduction = GoalRuntimePolicy.reconcileStatus(
                    authoritative: authoritative,
                    currentGoal: goal,
                    isFinalizing: isFinalizing,
                    isSessionSending: isSessionSending()
                )
                goal = reduction.goal
                self.availability = .available
                isMutating = false
                isFinalizing = reduction.isFinalizing
                error = nil
                onSynchronized(authoritative)
            case let .failure(message):
                if settlePendingCompletion {
                    if let goal, !isSessionSending() {
                        self.goal = GoalRuntimePolicy.replacingPhase(
                            goal,
                            with: .checking
                        )
                    }
                    isFinalizing = false
                    error = message
                }
            }
        }
    }
}
