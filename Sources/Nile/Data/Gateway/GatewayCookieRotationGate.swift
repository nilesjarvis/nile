import Foundation

/// Serializes cookie reads, responses, and persistence so a cancelled caller
/// cannot expose a partially applied dashboard-session rotation.
actor GatewayCookieRotationGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var locked = false
    private var waiters: [Waiter] = []

    /// Shields an admitted operation until its cookie effects settle, then
    /// reports caller cancellation before returning the operation's result.
    func withCancellationShield<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        let shielded = Task.detached(priority: Task.currentPriority) {
            try await operation()
        }
        let outcome = await shielded.result
        let wasCancelled = Task.isCancelled
        release()
        if wasCancelled {
            throw CancellationError()
        }
        return try outcome.get()
    }

    /// Keeps the rotation slot serialized while allowing cancellation to reach
    /// bounded downloads that do not mutate cookies after returning.
    func withInterruptibleRotation<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        defer {
            release()
        }
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !locked {
            locked = true
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(
                        Waiter(id: waiterID, continuation: continuation)
                    )
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        waiters.remove(at: index).continuation.resume(
            throwing: CancellationError()
        )
    }
}
