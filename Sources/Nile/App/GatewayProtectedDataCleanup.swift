import Foundation

@MainActor
extension GatewaySetupModel {
    /// Try each independent store even when one is unavailable. Keep the
    /// profile until every store succeeds so the user can retry removal.
    func eraseProtectedGatewayData(id: String) async throws {
        var failed = false
        do {
            try await composerDraftStore?.removeGateway(id: id)
        } catch {
            failed = true
        }
        do {
            try await attachmentDraftStore?.removeGateway(id: id)
        } catch {
            failed = true
        }
        do {
            try await sessionPinStore?.removeGateway(id: id)
        } catch {
            failed = true
        }
        do {
            try await modelPinStore?.removeGateway(id: id)
        } catch {
            failed = true
        }
        if failed {
            throw GatewayProtectedDataCleanupError()
        }
    }
}

private struct GatewayProtectedDataCleanupError: LocalizedError {
    var errorDescription: String? {
        "Nile could not erase all of this gateway's protected local data. "
            + "Some data may already be erased. The gateway remains saved "
            + "so you can retry Remove gateway."
    }
}
