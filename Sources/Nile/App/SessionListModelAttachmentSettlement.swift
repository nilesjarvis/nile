import Foundation

/// Post-admission attachment settlement and relaunch recovery projection.
///
/// Attachment runtimes remain the transport, protected-state, and recovery
/// authorities. This same-model extension applies their typed outcomes without
/// owning a repository, event stream, task registry, or mutation record store.
@MainActor
extension SessionListModel {
    func restoreAttachmentBeforeMutation(
        _ batch: OutboundAttachmentBatch,
        token: SessionComposerRuntime.RecoveryToken,
        message: String
    ) {
        runtimes.attachmentRuntime.retire(batchID: batch.id)
        let restored = runtimes.attachmentRecoveryRuntime.mergeAttachments(
            batch.attachments,
            runtimes.attachmentPersistenceRuntime.draft(for: batch.owner)
        )
        runtimes.attachmentPersistenceRuntime.replaceDraft(
            for: batch.owner,
            with: restored
        )
        if transcriptIsVisible(for: batch.owner) {
            pendingAttachments = restored
        }
        settlePromptFailure(
            token: token,
            liveSessionID: batch.liveSessionID,
            entryID: batch.userEntryID,
            input: batch.input,
            message: message,
            uncertain: false
        )
    }

    func settleAcceptedAttachmentBatch(
        _ batch: OutboundAttachmentBatch,
        marker: AttachmentMutationMarker
    ) async {
        let cleared = await runtimes.attachmentPersistenceRuntime.clearMutation(marker)
        if cleared {
            runtimes.attachmentRuntime.clearUncertainty(mutationID: marker.id)
        } else if transcriptIsVisible(for: batch.owner) {
            operationError =
                "Nile sent the photo but could not retire its recovery marker. Check the conversation before resending."
        }
        runtimes.attachmentRuntime.retire(batchID: batch.id)
    }

    func settleFailedAttachmentBatch(
        _ batch: OutboundAttachmentBatch,
        marker: AttachmentMutationMarker,
        token: SessionComposerRuntime.RecoveryToken,
        message: String,
        uncertain: Bool
    ) async {
        if uncertain {
            runtimes.attachmentRuntime.addPromptUncertainty(for: batch)
            let quarantined = marker.advancing(to: .quarantineOnly)
            _ = await runtimes.attachmentPersistenceRuntime.advanceMutation(
                from: marker,
                to: quarantined
            )
            runtimes.attachmentPersistenceRuntime.quarantine(owner: batch.owner)
            transcriptEntries.removeAll { $0.id == batch.userEntryID }
            if transcriptIsVisible(for: batch.owner) {
                liveSession = nil
                isSending = false
                turnStartedAt = nil
                operationError = Self.attachmentQuarantineMessage
            } else {
                runtimes.composerRuntime.rememberOperationNotice(
                    owner: batch.owner,
                    message: Self.attachmentQuarantineMessage,
                    uncertain: true
                )
            }
            return
        }

        let detached = await runtimes.attachmentRuntime.detachKnownLeases(for: batch)
        guard detached else {
            await settleFailedAttachmentBatch(
                batch,
                marker: marker,
                token: token,
                message: message,
                uncertain: true
            )
            return
        }
        let recoveredAttachments = runtimes.attachmentRecoveryRuntime.mergeAttachments(
            batch.attachments,
            runtimes.attachmentPersistenceRuntime.draft(for: batch.owner)
        )
        let recoveredDraft = runtimes.attachmentPersistenceRuntime.makeDraft(
            owner: batch.owner,
            attachments: recoveredAttachments
        )
        let recovered = await runtimes.attachmentPersistenceRuntime.recoverMutation(
            marker,
            as: recoveredDraft
        )
        guard recovered else {
            await settleFailedAttachmentBatch(
                batch,
                marker: marker,
                token: token,
                message: message,
                uncertain: true
            )
            return
        }
        runtimes.attachmentRuntime.retire(batchID: batch.id)
        if transcriptIsVisible(for: batch.owner) {
            pendingAttachments = recoveredAttachments
        }
        settlePromptFailure(
            token: token,
            liveSessionID: batch.liveSessionID,
            entryID: batch.userEntryID,
            input: batch.input,
            message: message,
            uncertain: false
        )
    }

    func quarantineTrackedAttachmentBatches() {
        let tracked = runtimes.attachmentRuntime.quarantineTrackedBatches()
        runtimes.attachmentPersistenceRuntime.quarantineTrackedBatches(tracked)
    }

    func restorePersistedAttachmentState(
        gatewayID: String
    ) async -> String? {
        do {
            try await runtimes.attachmentRecoveryRuntime.restore(
                gatewayID: gatewayID,
                commitGuard: { [weak self] in
                    self?.currentGatewayID == gatewayID
                }
            )
            return nil
        } catch {
            return
                "Nile could not restore protected photo drafts: \(error.localizedDescription)"
        }
    }

    func presentUnavailableRecoveredDraft(
        preferredSessionID: String?,
        gatewayID: String,
        gatewayGeneration: Int,
        navigationOwner: SessionNavigationRuntime.GatewayOwner
    ) async {
        let resolution = await runtimes.attachmentRecoveryRuntime
            .resolveUnavailableDraft(
                preferredSessionID: preferredSessionID,
                gatewayID: gatewayID,
                navigationOwner: navigationOwner,
                commitGuard: { [weak self] in
                    self?.isCurrentGateway(
                        gatewayID,
                        generation: gatewayGeneration
                    ) == true
                }
            )
        switch resolution {
        case .none, .stale:
            return
        case let .recovered(draft):
            selectedSessionID = draft.owner.storedSessionID
            liveSession = nil
            storedMessages = []
            transcriptEntries = []
            composer = draft.composer
            pendingAttachments = draft.attachments
            isReadOnlySession = false
            isOpeningSession = false
        case let .quarantined(owner, reason):
            selectedSessionID = owner.storedSessionID
            liveSession = nil
            isReadOnlySession = false
            composer = ""
            pendingAttachments = []
            operationError = reason == .unresolvedRuntime
                ? Self.attachmentQuarantineMessage
                : "Nile could not safely save the recovered photo draft."
        }
    }
}
