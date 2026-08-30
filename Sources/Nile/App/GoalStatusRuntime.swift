import Foundation

enum GoalStatusLookupResult: Equatable, Sendable {
    case available(HermesGoal?)
    case unavailable
}

enum GoalStatusRefreshResult: Equatable, Sendable {
    case success(HermesGoal?)
    case failure(String)
}

typealias GoalStatusRefreshHandler = @MainActor @Sendable (
    GoalStatusRefreshResult
) -> Void

/// Owns goal-status reads, refresh replacement, and stale-result fencing.
@MainActor
final class GoalStatusRuntime {
    var isBackedByRepository: Bool { repository != nil }

    private let repository: (any HermesGoalStatusServing)?
    private var task: Task<Void, Never>?
    private var generation: Int64 = 0

    init(repository: (any HermesGoalStatusServing)?) {
        self.repository = repository
    }

    isolated deinit {
        task?.cancel()
    }

    func synchronize(
        liveSessionID: String
    ) async -> GoalStatusLookupResult? {
        cancel()
        let generation = generation
        guard let repository else {
            return .available(nil)
        }
        do {
            let goal = try await repository.goalStatus(
                liveSessionID: liveSessionID
            )
            guard generation == self.generation else {
                return nil
            }
            return .available(goal)
        } catch is CancellationError {
            return nil
        } catch {
            guard generation == self.generation else {
                return nil
            }
            return .unavailable
        }
    }

    func recover(liveSessionID: String) async -> HermesGoal? {
        guard let repository else {
            return nil
        }
        return try? await repository.goalStatus(
            liveSessionID: liveSessionID
        )
    }

    func refresh(
        liveSessionID: String,
        onResult: @escaping GoalStatusRefreshHandler
    ) {
        cancel()
        let generation = generation
        guard let repository else {
            return
        }
        task = Task { [weak self] in
            defer {
                if self?.generation == generation {
                    self?.task = nil
                }
            }
            do {
                let goal = try await repository.goalStatus(
                    liveSessionID: liveSessionID
                )
                guard let self, generation == self.generation else {
                    return
                }
                onResult(.success(goal))
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.generation else {
                    return
                }
                onResult(.failure(error.localizedDescription))
            }
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
