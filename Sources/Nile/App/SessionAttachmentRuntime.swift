import Foundation

/// Owns attachment transport capabilities, correlation state, lease cleanup,
/// and task lifecycles.
///
/// Protected draft and mutation-marker state lives independently in
/// `SessionAttachmentPersistenceRuntime`; `SessionEventRuntime` owns the sole
/// Hermes stream, and `SessionListModel` supplies narrow persistence and
/// presentation callbacks through its ordered application boundary. A same-
/// runtime extension executes delivery without introducing another capability,
/// coordinator, task registry, or lifecycle generation.
@MainActor
final class SessionAttachmentRuntime {
    enum PreparationOutcome: Equatable, Sendable {
        case ready
        case rejected(message: String)
    }

    enum DeliveryOutcome: Equatable, Sendable {
        case preparationFailed(message: String)
        case accepted(
            batch: OutboundAttachmentBatch,
            marker: AttachmentMutationMarker
        )
        case failed(
            batch: OutboundAttachmentBatch,
            marker: AttachmentMutationMarker,
            message: String,
            uncertain: Bool
        )
    }

    typealias Preparation = @MainActor @Sendable
        () async -> PreparationOutcome
    typealias PromptPreparation = @MainActor @Sendable
        (AttachmentMutationMarker, AttachmentMutationMarker) async -> Bool
    typealias UploadHandler = @MainActor @Sendable
        (PendingAttachment, AttachedImage) -> Void
    typealias OutcomeHandler = @MainActor @Sendable
        (DeliveryOutcome) async -> Void
    typealias StartTimeoutHandler = @MainActor @Sendable
        (OutboundAttachmentBatch, AttachmentMutationMarker) async -> Void

    let attachments: (any HermesAttachmentMutating)?
    let prompts: (any HermesPromptServing)?
    let disconnector: (any HermesDisconnectServing)?
    let startConfirmationDelay: Duration
    var coordinator = AttachmentDeliveryCoordinator()
    var deliveryTasks: [String: Task<Void, Never>] = [:]
    var startConfirmationTasks: [String: Task<Void, Never>] = [:]
    var lifecycleGeneration: Int64 = 0

    init(
        attachments: (any HermesAttachmentMutating)?,
        prompts: (any HermesPromptServing)?,
        disconnector: (any HermesDisconnectServing)?,
        startConfirmationDelay: Duration = .seconds(35)
    ) {
        self.attachments = attachments
        self.prompts = prompts
        self.disconnector = disconnector
        self.startConfirmationDelay = startConfirmationDelay
    }

    isolated deinit {
        deliveryTasks.values.forEach { $0.cancel() }
        startConfirmationTasks.values.forEach { $0.cancel() }
    }

    func onMessageStart(
        owner: ComposerDraftOwner,
        liveSessionID: String
    ) -> [OutboundAttachmentBatch] {
        coordinator.onMessageStart(
            owner: owner,
            liveSessionID: liveSessionID
        )
    }

    func onAssistantCompleted(liveSessionID: String) {
        coordinator.onAssistantCompleted(liveSessionID: liveSessionID)
    }

    func onError(
        owner: ComposerDraftOwner,
        liveSessionID: String,
        message: String
    ) -> [OutboundAttachmentBatch] {
        coordinator.onError(
            owner: owner,
            liveSessionID: liveSessionID,
            message: message
        )
    }

    func retire(batchID: String) {
        startConfirmationTasks.removeValue(forKey: batchID)?.cancel()
        coordinator.retire(batchID: batchID)
    }

    func addPromptUncertainty(for batch: OutboundAttachmentBatch) {
        coordinator.addPromptUncertainty(for: batch)
    }

    func clearUncertainty(mutationID: String) {
        coordinator.clearUncertainty(mutationID: mutationID)
    }

    func detachKnownLeases(
        for batch: OutboundAttachmentBatch
    ) async -> Bool {
        for lease in coordinator.leases(forMutationID: batch.id) {
            do {
                let detached: Bool
                if let attachments {
                    detached = try await attachments.detachImage(
                        liveSessionID: lease.liveSessionID,
                        path: lease.path
                    )
                } else {
                    detached = true
                }
                guard detached else {
                    return false
                }
                _ = coordinator.removeLease(lease)
            } catch let error as HermesError where error.code == 4001 {
                // The runtime and its in-memory image queue no longer exist.
                _ = coordinator.removeLease(lease)
            } catch {
                return false
            }
        }
        return true
    }

    /// Marks tracked work uncertain and cancels only pending confirmation
    /// timers. Protected persistence and user-facing quarantine are separate.
    func quarantineTrackedBatches() -> [OutboundAttachmentBatch] {
        let tracked = coordinator.trackedBatches()
        for batch in tracked {
            startConfirmationTasks.removeValue(forKey: batch.id)?.cancel()
            coordinator.addPromptUncertainty(for: batch)
        }
        return tracked
    }

    func reset() {
        lifecycleGeneration &+= 1
        let activeDeliveries = Array(deliveryTasks.values)
        let activeConfirmations = Array(startConfirmationTasks.values)
        deliveryTasks.removeAll()
        startConfirmationTasks.removeAll()
        coordinator = AttachmentDeliveryCoordinator()
        activeDeliveries.forEach { $0.cancel() }
        activeConfirmations.forEach { $0.cancel() }
    }
}
