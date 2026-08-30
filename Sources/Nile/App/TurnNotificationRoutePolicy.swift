enum TurnNotificationGatewayDecision: Equatable {
    case wait
    case discard
    case connect
    case loadSessions
}

enum TurnNotificationSessionDecision: Equatable {
    case wait
    case discard
    case select(String)
    case finish
}

struct TurnNotificationRoutePolicy {
    static func initialGatewayDecision(
        route: TurnNotificationRoute,
        savedGatewayIDs: Set<String>,
        state: GatewaySetupModel.ProbeState,
        connectedGatewayID: String?,
        isSignInPresented: Bool
    ) -> TurnNotificationGatewayDecision {
        switch state {
        case .loading, .checking, .offline, .reconnecting, .restoring:
            return .wait
        case .idle, .connected, .failed:
            break
        }
        guard !isSignInPresented else {
            return .wait
        }
        guard savedGatewayIDs.contains(route.gatewayID) else {
            return .discard
        }
        guard state == .connected,
              connectedGatewayID == route.gatewayID else {
            return .connect
        }
        return .loadSessions
    }

    static func connectedGatewayDecision(
        route: TurnNotificationRoute,
        state: GatewaySetupModel.ProbeState,
        connectedGatewayID: String?,
        isSignInPresented: Bool
    ) -> TurnNotificationGatewayDecision {
        if case .failed = state {
            return .discard
        }
        guard state == .connected,
              connectedGatewayID == route.gatewayID,
              !isSignInPresented else {
            return .wait
        }
        return .loadSessions
    }

    static func sessionDecision(
        route: TurnNotificationRoute,
        state: SessionListModel.LoadingState,
        sessionIDs: Set<String>,
        selectedSessionID: String?
    ) -> TurnNotificationSessionDecision {
        switch state {
        case .idle, .loading:
            return .wait
        case .failed:
            return .discard
        case .loaded:
            break
        }
        guard let storedSessionID = route.storedSessionID else {
            return .finish
        }
        guard sessionIDs.contains(storedSessionID) else {
            return .discard
        }
        guard selectedSessionID == storedSessionID else {
            return .select(storedSessionID)
        }
        return .finish
    }
}
