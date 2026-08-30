import Foundation

/// Writable-session Rename presentation integration.
///
/// SessionRenameRuntime retains normalization, authenticated mutation, task,
/// generation, error, and dialog lifecycle. This extension owns UI-facing
/// eligibility, immutable owner capture, and successful title projection.
@MainActor
extension SessionListModel {
    var isRenameDialogVisible: Bool {
        runtimes.renameRuntime.isDialogVisible
    }

    var isRenamingSession: Bool {
        runtimes.renameRuntime.isRenaming
    }

    var renameSessionError: String? {
        runtimes.renameRuntime.error
    }

    var canShowRenameSession: Bool {
        state == .loaded
            && connectionPhase == .online
            && selectedSessionID != nil
            && liveSession != nil
            && !isReadOnlySession
            && !isOpeningSession
    }

    func setRenameDialogVisible(_ visible: Bool) {
        runtimes.renameRuntime.setDialogVisible(
            visible,
            owner: captureRenameOwner()
        )
    }

    func renameCurrentSession(_ title: String) {
        runtimes.renameRuntime.rename(
            title,
            owner: captureRenameOwner(),
            isCurrentOwner: renameOwnerValidator(),
            onRenamed: { [weak self] title, owner in
                self?.applyRenamedSession(title, owner: owner)
            }
        )
    }

    private func applyRenamedSession(
        _ title: String,
        owner: SessionRenameRuntime.Owner
    ) {
        guard let index = sessions.firstIndex(where: {
            $0.id == owner.storedSessionID
        }) else {
            return
        }
        let session = sessions[index]
        sessions[index] = HermesSession(
            id: session.id,
            title: title,
            preview: session.preview,
            source: session.source,
            messageCount: session.messageCount,
            startedAt: session.startedAt,
            lastMessageAt: session.lastMessageAt
        )
    }

    private func captureRenameOwner() -> SessionRenameRuntime.Owner? {
        guard canShowRenameSession,
              let gatewayID = currentGatewayID,
              let storedSessionID = selectedSessionID,
              let liveSessionID = liveSession?.liveID else {
            return nil
        }
        return SessionRenameRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    private func isCurrentRenameOwner(
        _ owner: SessionRenameRuntime.Owner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.gatewayID == currentGatewayID
            && owner.storedSessionID == selectedSessionID
            && owner.liveSessionID == liveSession?.liveID
            && !isReadOnlySession
    }

    private func renameOwnerValidator()
        -> SessionRenameRuntime.OwnerValidator {
        { [weak self] owner in
            self?.isCurrentRenameOwner(owner) ?? false
        }
    }
}
