import Foundation

enum ModelOptionsLoadResult: Equatable, Sendable {
    case success(ModelOptions)
    case failure(String)
}

typealias ModelOptionsLoadHandler = @MainActor @Sendable (
    ModelOptionsLoadResult
) -> Void

/// Owns model-catalog reads, replacement, and stale-result fencing.
@MainActor
final class ModelOptionsRuntime {
    var isLoading: Bool { task != nil }

    private let repository: (any HermesModelOptionsServing)?
    private var task: Task<Void, Never>?
    private var generation: Int64 = 0

    init(repository: (any HermesModelOptionsServing)?) {
        self.repository = repository
    }

    isolated deinit {
        task?.cancel()
    }

    @discardableResult
    func load(
        liveSessionID: String,
        refresh: Bool,
        onResult: @escaping ModelOptionsLoadHandler
    ) -> Bool {
        cancel()
        let generation = generation
        guard let repository else {
            return false
        }
        task = Task { [weak self] in
            defer {
                if self?.generation == generation {
                    self?.task = nil
                }
            }
            do {
                let options = try await repository.modelOptions(
                    liveSessionID: liveSessionID,
                    refresh: refresh
                )
                guard let self, generation == self.generation else {
                    return
                }
                onResult(.success(options))
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.generation else {
                    return
                }
                onResult(.failure(error.localizedDescription))
            }
        }
        return true
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
