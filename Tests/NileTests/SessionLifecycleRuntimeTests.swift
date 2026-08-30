import XCTest
@testable import Nile

@MainActor
final class SessionLifecycleRuntimeTests: XCTestCase {
    func testForegroundReconciliationRequiresARealBackgroundTransition() {
        let controller = RecordingBackgroundController()
        let runtime = SessionLifecycleRuntime(
            backgroundController: controller
        )

        XCTAssertFalse(runtime.isForeground)
        XCTAssertFalse(runtime.setForeground(true))
        XCTAssertTrue(runtime.isForeground)
        XCTAssertFalse(runtime.setForeground(false))
        XCTAssertFalse(runtime.isForeground)
        XCTAssertTrue(runtime.setForeground(true))

        runtime.hideSurface()
        XCTAssertFalse(runtime.isForeground)
        XCTAssertTrue(runtime.setForeground(true))
        XCTAssertEqual(
            controller.events,
            [
                .foregroundChanged(true),
                .foregroundChanged(false),
                .foregroundChanged(true),
                .foregroundChanged(true),
            ]
        )
    }

    func testTurnStartCallbackIsDeduplicatedWhileCoordinatorKeepsFIFO() {
        let controller = RecordingBackgroundController()
        let runtime = SessionLifecycleRuntime(
            backgroundController: controller
        )
        let first = target("one")
        let second = target("two")
        var startedCount = 0
        runtime.installBackgroundTurnStartedHandler {
            startedCount += 1
        }

        runtime.startTurn(
            gatewayID: first.gatewayID,
            storedSessionID: first.storedSessionID,
            liveSessionID: first.liveSessionID
        )
        runtime.startTurn(
            gatewayID: first.gatewayID,
            storedSessionID: first.storedSessionID,
            liveSessionID: first.liveSessionID
        )
        runtime.startTurn(
            gatewayID: second.gatewayID,
            storedSessionID: second.storedSessionID,
            liveSessionID: second.liveSessionID
        )

        XCTAssertEqual(startedCount, 2)
        XCTAssertEqual(controller.events, [.started(first)])

        runtime.completeTurn(
            gatewayID: first.gatewayID,
            liveSessionID: first.liveSessionID
        )
        runtime.stopTurn(
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
            ]
        )
    }

    func testFailedStartNotifiesOnceAndRetriesWithoutRepublishing() {
        let controller = RecordingBackgroundController()
        controller.startError = BackgroundExecutionUnavailableError()
        let runtime = SessionLifecycleRuntime(
            backgroundController: controller
        )
        let pending = target("pending")
        var startedCount = 0
        runtime.installBackgroundTurnStartedHandler {
            startedCount += 1
        }

        runtime.startTurn(
            gatewayID: pending.gatewayID,
            storedSessionID: pending.storedSessionID,
            liveSessionID: pending.liveSessionID
        )
        controller.startError = nil
        _ = runtime.setForeground(true)

        XCTAssertEqual(startedCount, 1)
        XCTAssertEqual(
            controller.events,
            [
                .started(pending),
                .foregroundChanged(true),
                .started(pending),
            ]
        )
    }

    func testGatewayScopeStatusReconciliationAndStopAllStayExact() {
        let controller = RecordingBackgroundController()
        let runtime = SessionLifecycleRuntime(
            backgroundController: controller
        )
        let first = target("one", gatewayID: "gateway-1")
        let second = target("two", gatewayID: "gateway-2")

        runtime.startTurn(
            gatewayID: first.gatewayID,
            storedSessionID: first.storedSessionID,
            liveSessionID: first.liveSessionID
        )
        XCTAssertFalse(runtime.hasTurnsOutsideGateway("gateway-1"))
        XCTAssertTrue(runtime.hasTurnsOutsideGateway("gateway-2"))
        runtime.reconcileStatuses(
            gatewayID: first.gatewayID,
            statuses: ["stored-one": "idle"]
        )

        runtime.startTurn(
            gatewayID: second.gatewayID,
            storedSessionID: second.storedSessionID,
            liveSessionID: second.liveSessionID
        )
        runtime.stopTurnsOutsideGateway("gateway-1")
        XCTAssertEqual(
            controller.events,
            [
                .started(first),
                .completed(first),
                .started(second),
                .stopped(second),
            ]
        )
    }

    func testConnectionLossNoticeUsesInstalledLifecycleSink() {
        let runtime = SessionLifecycleRuntime(
            backgroundController: NoOpTurnBackgroundController()
        )
        var notices: [GatewayConnectionLossNotice] = []
        runtime.installConnectionLossHandler { notice in
            notices.append(notice)
        }

        let notice = GatewayConnectionLossNotice(
            message: "Gateway disconnected",
            retryable: true
        )
        runtime.notifyConnectionLoss(notice)

        XCTAssertEqual(notices, [notice])
    }

    private func target(
        _ suffix: String,
        gatewayID: String = "gateway-1"
    ) -> BackgroundTurnTarget {
        BackgroundTurnTarget(
            gatewayID: gatewayID,
            storedSessionID: "stored-\(suffix)",
            liveSessionID: "live-\(suffix)"
        )
    }
}
