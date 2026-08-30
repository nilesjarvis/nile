import Foundation

enum SessionDisplayRoute: Equatable, Sendable {
    case live
    case terminalHistory
    case needsSourceLookup
}

/// Owns repository availability, active gateway identity, and gateway-scoped
/// terminal/Claim provenance.
///
/// Terminal provenance must survive reconnects and partial `session.list`
/// pages. A successful user Claim takes precedence until the gateway changes.
@MainActor
final class SessionGatewayContextRuntime {
    let hasSessionRepository: Bool

    private var loadedGatewayID: String?
    private var terminalSessionIDs: Set<String> = []
    private var claimedSessionIDs: Set<String> = []

    init(hasSessionRepository: Bool) {
        self.hasSessionRepository = hasSessionRepository
    }

    var currentGatewayID: String? {
        loadedGatewayID ?? (!hasSessionRepository ? "fixture" : nil)
    }

    var productionGatewayID: String? {
        loadedGatewayID
    }

    func setLoadedGatewayID(_ gatewayID: String) {
        loadedGatewayID = gatewayID
    }

    func recordListedSessions(_ sessions: [HermesSession]) {
        terminalSessionIDs.formUnion(
            sessions.lazy.filter(\.isTerminalOwned).map(\.id)
        )
    }

    func displayRoute(
        storedSessionID: String,
        listedSession: HermesSession?
    ) -> SessionDisplayRoute {
        if claimedSessionIDs.contains(storedSessionID) {
            return .live
        }
        if terminalSessionIDs.contains(storedSessionID) {
            return .terminalHistory
        }
        if let listedSession,
           let source = listedSession.source,
           !source.isBlank {
            return listedSession.isTerminalOwned ? .terminalHistory : .live
        }
        return .needsSourceLookup
    }

    func isKnownTerminalSession(
        storedSessionID: String,
        listedSession: HermesSession?
    ) -> Bool {
        displayRoute(
            storedSessionID: storedSessionID,
            listedSession: listedSession
        ) == .terminalHistory
    }

    func isReadOnlySession(
        storedSessionID: String?,
        sessions: [HermesSession]
    ) -> Bool {
        guard let storedSessionID else {
            return false
        }
        return isKnownTerminalSession(
            storedSessionID: storedSessionID,
            listedSession: sessions.first { $0.id == storedSessionID }
        )
    }

    func recordTerminalSession(storedSessionID: String) {
        terminalSessionIDs.insert(storedSessionID)
    }

    func recordClaim(
        storedSessionID: String,
        resumedStoredSessionID: String?
    ) {
        claimedSessionIDs.insert(storedSessionID)
        if let resumedStoredSessionID {
            claimedSessionIDs.insert(resumedStoredSessionID)
        }
        terminalSessionIDs.remove(storedSessionID)
    }

    func clearGateway() {
        terminalSessionIDs.removeAll()
        claimedSessionIDs.removeAll()
    }
}
