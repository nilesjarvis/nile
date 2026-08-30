import XCTest
@testable import Nile

@MainActor
final class BackgroundTurnCoordinatorTests: XCTestCase {
    func testExactTargetStartsAndCompletesOnlyOnce() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let target = target("one")

        coordinator.start(target)
        coordinator.start(target)
        coordinator.complete(
            gatewayID: "other-gateway",
            liveSessionID: target.liveSessionID
        )
        coordinator.complete(
            gatewayID: target.gatewayID,
            liveSessionID: "other-live"
        )
        coordinator.complete(
            gatewayID: target.gatewayID,
            liveSessionID: target.liveSessionID
        )
        coordinator.complete(
            gatewayID: target.gatewayID,
            liveSessionID: target.liveSessionID
        )

        XCTAssertEqual(
            controller.events,
            [.started(target), .completed(target)]
        )
    }

    func testQueuedTargetsAdvanceInInsertionOrder() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let first = target("first")
        let second = target("second")
        let third = target("third")

        coordinator.start(first)
        coordinator.start(second)
        coordinator.start(third)
        coordinator.complete(
            gatewayID: first.gatewayID,
            liveSessionID: first.liveSessionID
        )
        coordinator.stop(
            gatewayID: second.gatewayID,
            liveSessionID: second.liveSessionID
        )

        XCTAssertEqual(
            controller.events,
            [
                .started(first),
                .completed(first),
                .started(second),
                .stopped(second),
                .started(third),
            ]
        )
    }

    func testPendingTargetSettlesWithoutDisturbingActiveTarget() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let active = target("active")
        let pending = target("pending")

        coordinator.start(active)
        coordinator.start(pending)
        coordinator.complete(
            gatewayID: pending.gatewayID,
            liveSessionID: pending.liveSessionID
        )
        coordinator.stop(
            gatewayID: active.gatewayID,
            liveSessionID: active.liveSessionID
        )

        XCTAssertEqual(
            controller.events,
            [
                .started(active),
                .completed(pending),
                .stopped(active),
            ]
        )
    }

    func testFailedStartRemainsPendingAndRetriesOnForeground() {
        let controller = RecordingBackgroundController()
        controller.startError = BackgroundExecutionUnavailableError()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let target = target("retry")

        coordinator.start(target)
        controller.startError = nil
        coordinator.onAppForegroundChanged(true)
        coordinator.complete(
            gatewayID: target.gatewayID,
            liveSessionID: target.liveSessionID
        )

        XCTAssertEqual(
            controller.events,
            [
                .started(target),
                .foregroundChanged(true),
                .started(target),
                .completed(target),
            ]
        )
    }

    func testControllerFailuresDoNotBreakQueueOrForegroundHandling() {
        let controller = RecordingBackgroundController()
        controller.foregroundError = BackgroundExecutionUnavailableError()
        controller.completionError = BackgroundExecutionUnavailableError()
        controller.stopError = BackgroundExecutionUnavailableError()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let first = target("first")
        let second = target("second")
        let third = target("third")

        coordinator.start(first)
        coordinator.start(second)
        coordinator.start(third)
        coordinator.onAppForegroundChanged(false)
        coordinator.complete(
            gatewayID: first.gatewayID,
            liveSessionID: first.liveSessionID
        )
        coordinator.stop(
            gatewayID: second.gatewayID,
            liveSessionID: second.liveSessionID
        )

        XCTAssertEqual(
            controller.events,
            [
                .started(first),
                .foregroundChanged(false),
                .completed(first),
                .started(second),
                .stopped(second),
                .started(third),
            ]
        )
    }

    func testExecutionExpirationRequeuesOnlyExactActiveTarget() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let expiredTarget = target("expired")

        coordinator.start(expiredTarget)
        controller.expire(target("other"))
        controller.expire(expiredTarget)
        controller.expire(expiredTarget)
        coordinator.onAppForegroundChanged(false)
        coordinator.onAppForegroundChanged(true)

        XCTAssertEqual(
            controller.events,
            [
                .started(expiredTarget),
                .foregroundChanged(false),
                .foregroundChanged(true),
                .started(expiredTarget),
            ]
        )
    }

    func testReconciledStatusesSettleEveryInactiveTarget() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let first = target("first", storedSessionID: "stored-first")
        let second = target("second", storedSessionID: "stored-second")

        coordinator.start(first)
        coordinator.start(second)
        coordinator.reconcileStatuses(
            gatewayID: "gateway-1",
            statuses: [:]
        )

        XCTAssertEqual(
            controller.events,
            [
                .started(first),
                .completed(first),
                .started(second),
                .completed(second),
            ]
        )
    }

    func testReconciledCompletionUsesGatewayAndStoredSessionIdentity() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let target = target(
            "old-live",
            storedSessionID: "stored"
        )

        coordinator.start(target)
        coordinator.completeReconciled(
            gatewayID: "other-gateway",
            storedSessionID: "stored"
        )
        coordinator.completeReconciled(
            gatewayID: target.gatewayID,
            storedSessionID: "other-stored"
        )
        coordinator.completeReconciled(
            gatewayID: target.gatewayID,
            storedSessionID: "stored"
        )

        XCTAssertEqual(
            controller.events,
            [.started(target), .completed(target)]
        )
    }

    func testStopAllNotifiesPendingBeforeActiveAndClearsOwnership() {
        let controller = RecordingBackgroundController()
        let coordinator = BackgroundTurnCoordinator(controller: controller)
        let active = target("active")
        let pending = target("pending")

        coordinator.start(active)
        coordinator.start(pending)
        coordinator.stopAll()
        coordinator.stopAll()

        XCTAssertEqual(
            controller.events,
            [
                .started(active),
                .stopped(pending),
                .stopped(active),
            ]
        )
        XCTAssertFalse(coordinator.conflicts(with: target("new")))
        XCTAssertFalse(
            coordinator.hasTarget(outsideGateway: "gateway-1")
        )
    }

    func testOwnershipQueriesUseActiveThenFirstPendingPolicy() {
        let coordinator = BackgroundTurnCoordinator(
            controller: RecordingBackgroundController()
        )
        let active = target("active", gatewayID: "gateway-1")
        let pending = target("pending", gatewayID: "gateway-2")

        coordinator.start(active)
        XCTAssertFalse(coordinator.conflicts(with: active))
        XCTAssertFalse(
            coordinator.hasTarget(outsideGateway: "gateway-1")
        )
        XCTAssertTrue(
            coordinator.hasTarget(outsideGateway: "gateway-2")
        )

        coordinator.start(pending)
        XCTAssertFalse(coordinator.conflicts(with: active))
        XCTAssertTrue(coordinator.conflicts(with: pending))
        XCTAssertTrue(
            coordinator.hasTarget(outsideGateway: "gateway-1")
        )
        XCTAssertTrue(
            coordinator.hasTarget(outsideGateway: "gateway-2")
        )
        XCTAssertTrue(coordinator.hasTarget(outsideGateway: nil))
    }

    private func target(
        _ suffix: String,
        gatewayID: String = "gateway-1",
        storedSessionID: String? = nil
    ) -> BackgroundTurnTarget {
        BackgroundTurnTarget(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID ?? "stored-\(suffix)",
            liveSessionID: "live-\(suffix)"
        )
    }
}

@MainActor
final class RecordingBackgroundController: TurnBackgroundControlling {
    enum Event: Equatable {
        case foregroundChanged(Bool)
        case started(BackgroundTurnTarget)
        case completed(BackgroundTurnTarget)
        case stopped(BackgroundTurnTarget)
    }

    var events: [Event] = []
    var startError: (any Error)?
    var foregroundError: (any Error)?
    var completionError: (any Error)?
    var stopError: (any Error)?
    private var expirationHandler: (
        @MainActor @Sendable (BackgroundTurnTarget) -> Void
    )?

    func installExpirationHandler(
        _ handler: @escaping @MainActor @Sendable
            (BackgroundTurnTarget) -> Void
    ) {
        expirationHandler = handler
    }

    func onAppForegroundChanged(_ isForeground: Bool) throws {
        events.append(.foregroundChanged(isForeground))
        if let foregroundError {
            throw foregroundError
        }
    }

    func turnStarted(_ target: BackgroundTurnTarget) throws {
        events.append(.started(target))
        if let startError {
            throw startError
        }
    }

    func turnCompleted(_ target: BackgroundTurnTarget) throws {
        events.append(.completed(target))
        if let completionError {
            throw completionError
        }
    }

    func turnStopped(_ target: BackgroundTurnTarget) throws {
        events.append(.stopped(target))
        if let stopError {
            throw stopError
        }
    }

    func expire(_ target: BackgroundTurnTarget) {
        expirationHandler?(target)
    }
}
