import Foundation

/// Bridges gateway-scoped context into displayed session state without owning
/// transport, refresh, or event-routing lifecycle.
@MainActor
extension SessionListModel {
    var currentGatewayID: String? {
        runtimes.gatewayContextRuntime.currentGatewayID
    }

    var hasSessionRepository: Bool {
        runtimes.gatewayContextRuntime.hasSessionRepository
    }

    var productionGatewayID: String? {
        runtimes.gatewayContextRuntime.productionGatewayID
    }

    func setLoadedGatewayID(_ gatewayID: String) {
        runtimes.gatewayContextRuntime.setLoadedGatewayID(gatewayID)
    }

    func clearSessionOwnership() {
        runtimes.gatewayContextRuntime.clearGateway()
    }

    func recordListedSessionOwnership(_ listedSessions: [HermesSession]) {
        runtimes.gatewayContextRuntime.recordListedSessions(listedSessions)
    }

    func isKnownTerminalSession(_ session: HermesSession) -> Bool {
        runtimes.gatewayContextRuntime.isKnownTerminalSession(
            storedSessionID: session.id,
            listedSession: session
        )
    }

    func sessionDisplayRoute(for session: HermesSession) -> SessionDisplayRoute {
        runtimes.gatewayContextRuntime.displayRoute(
            storedSessionID: session.id,
            listedSession: session
        )
    }

    func recordTerminalSessionOwnership(storedSessionID: String) {
        runtimes.gatewayContextRuntime.recordTerminalSession(
            storedSessionID: storedSessionID
        )
    }

    @discardableResult
    func applyClaimedSession(
        _ resumed: LiveSession,
        owner: SessionClaimRuntime.Owner
    ) -> Bool {
        guard owner.gatewayGeneration == gatewayGeneration,
              owner.displayGeneration == displayGeneration,
              owner.gatewayID == currentGatewayID,
              owner.storedSessionID == selectedSessionID,
              isReadOnlySession else {
            return false
        }
        runtimes.gatewayContextRuntime.recordClaim(
            storedSessionID: owner.storedSessionID,
            resumedStoredSessionID: resumed.storedID
        )
        liveSession = resumed
        storedMessages = []
        applyLiveSessionTranscript(resumed)
        isReadOnlySession = false
        refreshUsage()
        isOpeningSession = false
        state = .loaded
        return true
    }
}
