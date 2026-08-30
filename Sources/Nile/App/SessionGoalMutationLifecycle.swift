import Foundation

/// Owns replacement, cancellation, and generation fencing for standing-goal
/// mutations without becoming a second observable goal authority.
@MainActor
final class SessionGoalMutationLifecycle {
    struct Token: Equatable, Sendable {
        let lifecycle: Int64
        let mutation: Int64
    }

    private var task: Task<Void, Never>?
    private var generation: Int64 = 0

    isolated deinit {
        task?.cancel()
    }

    @discardableResult
    func start(
        lifecycle: Int64,
        operation: @escaping @MainActor @Sendable (Token) async -> Void
    ) -> Token {
        task?.cancel()
        generation &+= 1
        let token = Token(lifecycle: lifecycle, mutation: generation)
        task = Task {
            await operation(token)
        }
        return token
    }

    func reset() {
        task?.cancel()
        task = nil
        generation &+= 1
    }

    func finish(_ token: Token, lifecycle: Int64) {
        guard isCurrent(token, lifecycle: lifecycle) else {
            return
        }
        task = nil
    }

    func isCurrent(_ token: Token, lifecycle: Int64) -> Bool {
        token.lifecycle == lifecycle && token.mutation == generation
    }
}

extension SessionGoalRuntime {
    typealias MutationToken = SessionGoalMutationLifecycle.Token

    @discardableResult
    func beginMutation(
        owner: Owner,
        operation: @escaping @MainActor @Sendable (MutationToken) async -> Void
    ) -> Bool {
        guard matches(owner: owner) else {
            return false
        }
        status.cancel()
        isMutating = true
        error = nil
        mutationLifecycle.start(
            lifecycle: lifecycleGeneration,
            operation: operation
        )
        return true
    }

    func settleMutation(
        _ updated: HermesGoal?,
        operation: String,
        owner: Owner,
        token: MutationToken
    ) {
        guard isCurrentMutation(owner: owner, token: token) else {
            return
        }
        goal = updated
        isFinalizing = false
        finishMutation(owner: owner, token: token)
        if updated == nil {
            error = "There is no goal to \(operation)."
        }
    }

    func finishMutation(
        owner: Owner,
        token: MutationToken,
        clearError: Bool = true
    ) {
        guard isCurrentMutation(owner: owner, token: token) else {
            return
        }
        mutationLifecycle.finish(token, lifecycle: lifecycleGeneration)
        isMutating = false
        isFinalizing = false
        if clearError {
            error = nil
        }
    }

    func settleMutationFailure(
        owner: Owner,
        token: MutationToken,
        error: any Error
    ) {
        guard isCurrentMutation(owner: owner, token: token) else {
            return
        }
        mutationLifecycle.finish(token, lifecycle: lifecycleGeneration)
        isMutating = false
        isFinalizing = false
        self.error = error.localizedDescription
    }

    func isCurrentMutation(
        owner: Owner,
        token: MutationToken
    ) -> Bool {
        matches(owner: owner)
            && mutationLifecycle.isCurrent(
                token,
                lifecycle: lifecycleGeneration
            )
    }
}
