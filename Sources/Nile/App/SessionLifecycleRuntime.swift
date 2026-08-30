import Foundation

enum SessionConnectionPhase: Equatable, Sendable {
    case online
    case offline
    case reconnecting
    case restoring
    case failed
}

struct GatewayConnectionLossNotice: Equatable, Sendable {
    let message: String
    let retryable: Bool
}

/// Owns app/surface lifecycle state and background-turn coordination.
///
/// This runtime has no repository or event-stream capability. The session model
/// remains the sole ordered event application boundary and delegates only the
/// resulting lifecycle effects here.
@MainActor
final class SessionLifecycleRuntime {
    typealias ConnectionLossHandler = @MainActor @Sendable
        (GatewayConnectionLossNotice) -> Void
    typealias BackgroundTurnStartedHandler = @MainActor @Sendable () -> Void

    private let backgroundTurns: BackgroundTurnCoordinator
    private var hasEnteredBackground = false
    private var connectionLossHandler: ConnectionLossHandler?
    private var backgroundTurnStartedHandler: BackgroundTurnStartedHandler?

    private(set) var isForeground = false

    init(backgroundController: any TurnBackgroundControlling) {
        backgroundTurns = BackgroundTurnCoordinator(
            controller: backgroundController
        )
    }

    func installConnectionLossHandler(
        _ handler: @escaping ConnectionLossHandler
    ) {
        connectionLossHandler = handler
    }

    func installBackgroundTurnStartedHandler(
        _ handler: @escaping BackgroundTurnStartedHandler
    ) {
        backgroundTurnStartedHandler = handler
    }

    @discardableResult
    func setForeground(_ foreground: Bool) -> Bool {
        let shouldReconcile = foreground
            && !isForeground
            && hasEnteredBackground
        isForeground = foreground
        if !foreground {
            hasEnteredBackground = true
        }
        backgroundTurns.onAppForegroundChanged(foreground)
        return shouldReconcile
    }

    func hideSurface() {
        isForeground = false
        hasEnteredBackground = true
    }

    func notifyConnectionLoss(_ notice: GatewayConnectionLossNotice) {
        connectionLossHandler?(notice)
    }

    func startTurn(
        gatewayID: String,
        storedSessionID: String?,
        liveSessionID: String
    ) {
        let target = BackgroundTurnTarget(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
        let wasTracked = backgroundTurns.contains(target)
        _ = backgroundTurns.start(target)
        if !wasTracked {
            backgroundTurnStartedHandler?()
        }
    }

    func completeTurn(gatewayID: String?, liveSessionID: String) {
        backgroundTurns.complete(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID
        )
    }

    func completeReconciledTurn(
        gatewayID: String,
        storedSessionID: String?
    ) {
        backgroundTurns.completeReconciled(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }

    func stopTurn(gatewayID: String?, liveSessionID: String) {
        backgroundTurns.stop(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID
        )
    }

    func stopAllTurns() {
        backgroundTurns.stopAll()
    }

    func stopTurnsOutsideGateway(_ gatewayID: String?) {
        guard backgroundTurns.hasTarget(outsideGateway: gatewayID) else {
            return
        }
        backgroundTurns.stopAll()
    }

    func hasTurnsOutsideGateway(_ gatewayID: String?) -> Bool {
        backgroundTurns.hasTarget(outsideGateway: gatewayID)
    }

    func reconcileStatuses(
        gatewayID: String,
        statuses: [String: String]
    ) {
        backgroundTurns.reconcileStatuses(
            gatewayID: gatewayID,
            statuses: statuses
        )
    }
}
