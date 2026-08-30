import Foundation
import Observation

@MainActor
@Observable
final class SessionRenameRuntime {
    struct Owner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String
        let storedSessionID: String
        let liveSessionID: String
    }

    typealias OwnerValidator = @MainActor @Sendable (Owner) -> Bool
    typealias RenameHandler = @MainActor @Sendable (String, Owner) -> Void

    private(set) var isDialogVisible = false
    private(set) var isRenaming = false
    private(set) var error: String?

    @ObservationIgnored
    private let repository: (any HermesSessionRenaming)?
    @ObservationIgnored
    private var task: Task<Void, Never>?
    @ObservationIgnored
    private var generation: Int64 = 0

    init(repository: (any HermesSessionRenaming)?) {
        self.repository = repository
    }

    isolated deinit {
        task?.cancel()
    }

    func setDialogVisible(_ visible: Bool, owner: Owner?) {
        guard !isRenaming else {
            return
        }
        error = nil
        guard visible, owner != nil else {
            isDialogVisible = false
            return
        }
        isDialogVisible = true
    }

    func rename(
        _ title: String,
        owner: Owner?,
        isCurrentOwner: @escaping OwnerValidator,
        onRenamed: @escaping RenameHandler
    ) {
        let normalized = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              let owner,
              isDialogVisible,
              !isRenaming else {
            return
        }
        task?.cancel()
        generation &+= 1
        let operationGeneration = generation
        isRenaming = true
        error = nil

        guard let repository else {
            finish(
                normalized,
                owner: owner,
                generation: operationGeneration,
                isCurrentOwner: isCurrentOwner,
                onRenamed: onRenamed
            )
            return
        }
        task = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await repository.renameSession(
                    liveSessionID: owner.liveSessionID,
                    title: normalized
                )
                try Task.checkCancellation()
                self.finish(
                    normalized,
                    owner: owner,
                    generation: operationGeneration,
                    isCurrentOwner: isCurrentOwner,
                    onRenamed: onRenamed
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == operationGeneration,
                      isCurrentOwner(owner) else {
                    return
                }
                self.isRenaming = false
                self.error = error.localizedDescription
                self.task = nil
            }
        }
    }

    private func finish(
        _ title: String,
        owner: Owner,
        generation operationGeneration: Int64,
        isCurrentOwner: OwnerValidator,
        onRenamed: RenameHandler
    ) {
        guard generation == operationGeneration,
              isCurrentOwner(owner) else {
            return
        }
        onRenamed(title, owner)
        isRenaming = false
        isDialogVisible = false
        error = nil
        task = nil
    }

    func reset() {
        generation &+= 1
        task?.cancel()
        task = nil
        isDialogVisible = false
        isRenaming = false
        error = nil
    }
}
