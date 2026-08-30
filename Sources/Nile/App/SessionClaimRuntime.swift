import Foundation
import Observation

@MainActor
@Observable
final class SessionClaimRuntime {
    struct Owner: Equatable, Sendable {
        let gatewayGeneration: Int
        let displayGeneration: Int
        let gatewayID: String
        let storedSessionID: String
    }

    enum Outcome: Sendable {
        case succeeded(LiveSession)
        case failed(String)
        case cancelled
        case stale
    }

    typealias OwnerValidator = @MainActor @Sendable (Owner) -> Bool
    typealias StatusHandler = @MainActor @Sendable (String?) -> Void

    static let busyStatuses = Set([
        "working",
        "waiting",
        "starting",
    ])

    private(set) var isDialogVisible = false
    private(set) var isClaiming = false

    @ObservationIgnored
    private let repository: (any HermesSessionClaimServing)?
    @ObservationIgnored
    private var statusTask: Task<Void, Never>?
    @ObservationIgnored
    private var statusGeneration: Int64 = 0
    @ObservationIgnored
    private var claimGeneration: Int64 = 0

    init(repository: (any HermesSessionClaimServing)?) {
        self.repository = repository
    }

    isolated deinit {
        statusTask?.cancel()
    }

    func reset() {
        claimGeneration &+= 1
        statusGeneration &+= 1
        statusTask?.cancel()
        statusTask = nil
        isDialogVisible = false
        isClaiming = false
    }

    func cancelStatus() {
        statusGeneration &+= 1
        statusTask?.cancel()
        statusTask = nil
    }

    func setDialogVisible(
        _ visible: Bool,
        owner: Owner?,
        isCurrentOwner: @escaping OwnerValidator,
        onStatus: @escaping StatusHandler
    ) {
        statusTask?.cancel()
        statusTask = nil
        statusGeneration &+= 1
        guard visible, let owner, !isClaiming else {
            isDialogVisible = false
            return
        }
        isDialogVisible = true
        guard let repository else {
            return
        }
        let generation = statusGeneration
        statusTask = Task { [weak self] in
            let status = try? await repository.liveSessionStatus(
                storedSessionID: owner.storedSessionID
            )
            guard !Task.isCancelled,
                  let self,
                  self.statusGeneration == generation,
                  self.isDialogVisible,
                  isCurrentOwner(owner) else {
                return
            }
            self.statusTask = nil
            onStatus(status)
        }
    }

    func claim(
        owner: Owner,
        isCurrentOwner: @escaping OwnerValidator,
        onStatus: @escaping StatusHandler
    ) async -> Outcome {
        statusTask?.cancel()
        statusTask = nil
        statusGeneration &+= 1
        claimGeneration &+= 1
        let generation = claimGeneration
        isDialogVisible = false
        isClaiming = true

        guard let repository else {
            isClaiming = false
            return .failed("Claim is unavailable for this session.")
        }
        do {
            let status = try await repository.liveSessionStatus(
                storedSessionID: owner.storedSessionID
            )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isCurrentClaim(
                owner,
                generation: generation,
                isCurrentOwner: isCurrentOwner
            ) else {
                return .stale
            }
            onStatus(status)
            if let status, Self.busyStatuses.contains(status) {
                throw HermesError(
                    "The terminal session is still working. Stop its current turn, then try Claim again.",
                    retryable: false
                )
            }
            let resumed = try await repository.openSession(
                storedSessionID: owner.storedSessionID
            )
            guard isCurrentClaim(
                owner,
                generation: generation,
                isCurrentOwner: isCurrentOwner
            ) else {
                return .stale
            }
            isClaiming = false
            return .succeeded(resumed)
        } catch is CancellationError {
            guard isCurrentClaim(
                owner,
                generation: generation,
                isCurrentOwner: isCurrentOwner
            ) else {
                return .stale
            }
            isClaiming = false
            return .cancelled
        } catch {
            guard isCurrentClaim(
                owner,
                generation: generation,
                isCurrentOwner: isCurrentOwner
            ) else {
                return .stale
            }
            isClaiming = false
            return .failed(error.localizedDescription)
        }
    }

    private func isCurrentClaim(
        _ owner: Owner,
        generation: Int64,
        isCurrentOwner: OwnerValidator
    ) -> Bool {
        claimGeneration == generation
            && isClaiming
            && isCurrentOwner(owner)
    }
}
