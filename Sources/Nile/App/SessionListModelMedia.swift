import Foundation

/// Displayed-session attachment viewing and preview integration.
///
/// SessionMediaRuntime retains authenticated reads, cache preparation, bounded
/// preview tasks, and operation fencing. This extension owns only the visible
/// session projection while authoritative Hermes events remain at the core
/// model's single ordered application boundary.
@MainActor
extension SessionListModel {
    var openedAttachment: CachedAttachment? {
        runtimes.mediaRuntime.openedAttachment
    }

    var isOpeningAttachment: Bool {
        runtimes.mediaRuntime.isOpeningAttachment
    }

    func openAttachment(path: String) {
        runtimes.mediaRuntime.open(
            path: path,
            owner: captureMediaOwner(),
            isCurrentOwner: mediaOwnerValidator(),
            onError: { [weak self] message in
                self?.operationError = message
            }
        )
    }

    func dismissOpenedAttachment() {
        runtimes.mediaRuntime.dismissOpenedAttachment()
    }

    private func captureMediaOwner() -> SessionMediaRuntime.Owner? {
        guard let gatewayID = currentGatewayID,
              let storedSessionID = selectedSessionID else {
            return nil
        }
        return SessionMediaRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }

    private func isCurrentMediaOwner(
        _ owner: SessionMediaRuntime.Owner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.displayGeneration == displayGeneration
            && owner.gatewayID == currentGatewayID
            && owner.storedSessionID == selectedSessionID
    }

    private func mediaOwnerValidator()
        -> SessionMediaRuntime.OwnerValidator {
        { [weak self] owner in
            self?.isCurrentMediaOwner(owner) ?? false
        }
    }

    func hydrateVisibleMediaAttachments() {
        transcriptEntries = runtimes.mediaRuntime.reconcilePreviews(
            in: transcriptEntries,
            owner: captureMediaOwner(),
            isCurrentOwner: mediaOwnerValidator(),
            onPreview: { [weak self] update in
                self?.applyMediaPreview(update)
            },
            onNeedsReconcile: { [weak self] in
                self?.hydrateVisibleMediaAttachments()
            }
        )
    }

    private func applyMediaPreview(
        _ update: SessionMediaRuntime.PreviewUpdate
    ) {
        guard isCurrentMediaOwner(update.owner) else {
            return
        }
        transcriptEntries = transcriptEntries.map { entry in
            guard case var .message(message) = entry,
                  message.id == update.messageID,
                  message.attachments.indices.contains(
                    update.attachmentIndex
                  ),
                  message.attachments[update.attachmentIndex].path
                    == update.path else {
                return entry
            }
            message.attachments[update.attachmentIndex] = update.attachment
            return .message(message)
        }
    }
}
