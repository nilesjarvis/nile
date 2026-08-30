import Foundation

protocol GatewaySessionCleaning: Sendable {
    func clearSession(
        for connection: GatewayConnection,
        includeHostWideCookies: Bool
    ) async throws
}

struct GatewayCookieScopeConflictError: LocalizedError, Equatable, Sendable {
    let conflictingProfileName: String

    var errorDescription: String? {
        "This gated gateway's browser session overlaps \(conflictingProfileName). "
            + "Remove the overlapping profile or use a separate hostname."
    }
}

struct GatewayAuthenticationEvent: Equatable, Sendable {
    let profileID: String
    let loginURL: URL
}
