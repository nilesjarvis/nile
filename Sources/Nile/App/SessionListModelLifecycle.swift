import Foundation

/// Model-facing lifecycle callbacks and gateway recovery phase projection.
@MainActor
extension SessionListModel {
    func installConnectionLossHandler(
        _ handler: @escaping @MainActor @Sendable
            (GatewayConnectionLossNotice) -> Void
    ) {
        runtimes.lifecycleRuntime.installConnectionLossHandler(handler)
    }

    func installBackgroundTurnStartedHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        runtimes.lifecycleRuntime.installBackgroundTurnStartedHandler(handler)
    }

    func stopBackgroundTurnsOutsideGateway(_ gatewayID: String?) {
        runtimes.lifecycleRuntime.stopTurnsOutsideGateway(gatewayID)
    }

    func hasBackgroundTurnsOutsideGateway(_ gatewayID: String?) -> Bool {
        runtimes.lifecycleRuntime.hasTurnsOutsideGateway(gatewayID)
    }

    func setConnectionRecoveryPhase(_ phase: SessionConnectionPhase) {
        if phase != .online {
            runtimes.renameRuntime.reset()
        }
        connectionPhase = phase
    }
}
