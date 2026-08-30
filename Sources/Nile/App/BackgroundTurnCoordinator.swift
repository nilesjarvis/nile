import Foundation

struct BackgroundTurnTarget: Equatable, Hashable, Sendable {
    let gatewayID: String
    let storedSessionID: String?
    let liveSessionID: String
}

@MainActor
protocol TurnBackgroundControlling: AnyObject {
    func installExpirationHandler(
        _ handler: @escaping @MainActor @Sendable
            (BackgroundTurnTarget) -> Void
    )
    func onAppForegroundChanged(_ isForeground: Bool) throws
    func turnStarted(_ target: BackgroundTurnTarget) throws
    func turnCompleted(_ target: BackgroundTurnTarget) throws
    func turnStopped(_ target: BackgroundTurnTarget) throws
}

@MainActor
final class NoOpTurnBackgroundController: TurnBackgroundControlling {
    func installExpirationHandler(
        _ handler: @escaping @MainActor @Sendable
            (BackgroundTurnTarget) -> Void
    ) {}

    func onAppForegroundChanged(_ isForeground: Bool) {}

    func turnStarted(_ target: BackgroundTurnTarget) {}

    func turnCompleted(_ target: BackgroundTurnTarget) {}

    func turnStopped(_ target: BackgroundTurnTarget) {}
}

@MainActor
final class BackgroundTurnCoordinator {
    private let controller: any TurnBackgroundControlling
    private(set) var activeTarget: BackgroundTurnTarget?
    private(set) var pendingTargets: [BackgroundTurnTarget] = []

    init(controller: any TurnBackgroundControlling) {
        self.controller = controller
        controller.installExpirationHandler { [weak self] target in
            self?.onExecutionExpired(target)
        }
    }

    func onAppForegroundChanged(_ isForeground: Bool) {
        try? controller.onAppForegroundChanged(isForeground)
        if isForeground {
            _ = startPendingTarget()
        }
    }

    func onExecutionExpired(_ target: BackgroundTurnTarget) {
        guard activeTarget == target else {
            return
        }
        activeTarget = nil
        appendPending(target)
    }

    @discardableResult
    func start(_ target: BackgroundTurnTarget) -> Bool {
        if activeTarget == target {
            return false
        }
        if activeTarget != nil {
            appendPending(target)
            return false
        }
        appendPending(target)
        do {
            try controller.turnStarted(target)
            activeTarget = target
            removePending(target)
            return true
        } catch {
            return false
        }
    }

    func complete(gatewayID: String?, liveSessionID: String) {
        settleFirstMatching(
            where: {
                $0.gatewayID == gatewayID
                    && $0.liveSessionID == liveSessionID
            },
            notify: controller.turnCompleted
        )
    }

    func completeReconciled(
        gatewayID: String,
        storedSessionID: String?
    ) {
        settleFirstMatching(
            where: {
                $0.gatewayID == gatewayID
                    && $0.storedSessionID == storedSessionID
            },
            notify: controller.turnCompleted
        )
    }

    func reconcileStatuses(
        gatewayID: String,
        statuses: [String: String]
    ) {
        let completedStoredIDs = ([activeTarget].compactMap { $0 }
            + pendingTargets)
            .filter { $0.gatewayID == gatewayID }
            .compactMap(\.storedSessionID)
            .filter {
                guard let status = statuses[$0] else {
                    return true
                }
                return status == "idle"
            }
        for storedSessionID in completedStoredIDs {
            completeReconciled(
                gatewayID: gatewayID,
                storedSessionID: storedSessionID
            )
        }
    }

    func stop(gatewayID: String?, liveSessionID: String) {
        settleFirstMatching(
            where: {
                $0.gatewayID == gatewayID
                    && $0.liveSessionID == liveSessionID
            },
            notify: controller.turnStopped
        )
    }

    func stopAll() {
        let pending = pendingTargets
        pendingTargets.removeAll()
        for target in pending {
            try? controller.turnStopped(target)
        }
        guard let activeTarget else {
            return
        }
        self.activeTarget = nil
        try? controller.turnStopped(activeTarget)
    }

    func conflicts(with target: BackgroundTurnTarget) -> Bool {
        let owned = activeTarget ?? pendingTargets.first
        return owned != nil && owned != target
    }

    func hasTarget(outsideGateway gatewayID: String?) -> Bool {
        ([activeTarget].compactMap { $0 } + pendingTargets)
            .contains { $0.gatewayID != gatewayID }
    }

    func contains(_ target: BackgroundTurnTarget) -> Bool {
        activeTarget == target || pendingTargets.contains(target)
    }

    private func settleFirstMatching(
        where matches: (BackgroundTurnTarget) -> Bool,
        notify: (BackgroundTurnTarget) throws -> Void
    ) {
        guard let activeTarget, matches(activeTarget) else {
            guard let pending = pendingTargets.first(where: matches) else {
                return
            }
            removePending(pending)
            try? notify(pending)
            return
        }
        self.activeTarget = nil
        try? notify(activeTarget)
        _ = startPendingTarget()
    }

    @discardableResult
    private func startPendingTarget() -> Bool {
        guard activeTarget == nil, let target = pendingTargets.first else {
            return false
        }
        return start(target)
    }

    private func appendPending(_ target: BackgroundTurnTarget) {
        guard !pendingTargets.contains(target) else {
            return
        }
        pendingTargets.append(target)
    }

    private func removePending(_ target: BackgroundTurnTarget) {
        pendingTargets.removeAll { $0 == target }
    }
}
