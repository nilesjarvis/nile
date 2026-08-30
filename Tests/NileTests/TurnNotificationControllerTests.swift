import UIKit
import XCTest
@testable import Nile

@MainActor
final class TurnNotificationControllerTests: XCTestCase {
    func testCompletionUsesGenericCopyAndStoredRouteOnly() {
        let target = BackgroundTurnTarget(
            gatewayID: "private-gateway",
            storedSessionID: "private-stored",
            liveSessionID: "private-live"
        )
        let route = TurnNotificationRoute(
            gatewayID: target.gatewayID,
            storedSessionID: target.storedSessionID
        )

        XCTAssertEqual(SystemTurnNotificationScheduler.title, "Turn finished")
        XCTAssertEqual(
            SystemTurnNotificationScheduler.body,
            "Open Nile to view the result"
        )
        let rendered = [
            SystemTurnNotificationScheduler.title,
            SystemTurnNotificationScheduler.body,
        ].joined(separator: "\n")
        XCTAssertFalse(rendered.contains(target.gatewayID))
        XCTAssertFalse(rendered.contains(target.storedSessionID!))
        XCTAssertFalse(rendered.contains(target.liveSessionID))
        XCTAssertEqual(
            route.userInfo,
            [
                TurnNotificationRoute.gatewayIDKey: target.gatewayID,
                TurnNotificationRoute.storedSessionIDKey:
                    target.storedSessionID!,
            ]
        )
        XCTAssertFalse(route.userInfo.values.contains(target.liveSessionID))
    }

    func testRouteParserRejectsMissingGatewayAndNormalizesBlankSession() {
        XCTAssertNil(TurnNotificationRoute(userInfo: [:]))
        XCTAssertNil(
            TurnNotificationRoute(
                userInfo: [TurnNotificationRoute.gatewayIDKey: "  "]
            )
        )
        XCTAssertEqual(
            TurnNotificationRoute(
                userInfo: [
                    TurnNotificationRoute.gatewayIDKey: " gateway ",
                    TurnNotificationRoute.storedSessionIDKey: "  ",
                ]
            ),
            TurnNotificationRoute(
                gatewayID: "gateway",
                storedSessionID: nil
            )
        )
    }

    func testRoutePolicyWaitsDiscardsConnectsAndLoadsFailClosed() {
        let route = TurnNotificationRoute(
            gatewayID: "target",
            storedSessionID: "session"
        )
        let saved = Set(["target", "other"])

        XCTAssertEqual(
            TurnNotificationRoutePolicy.initialGatewayDecision(
                route: route,
                savedGatewayIDs: saved,
                state: .reconnecting,
                connectedGatewayID: nil,
                isSignInPresented: false
            ),
            .wait
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.initialGatewayDecision(
                route: route,
                savedGatewayIDs: saved,
                state: .idle,
                connectedGatewayID: nil,
                isSignInPresented: true
            ),
            .wait
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.initialGatewayDecision(
                route: route,
                savedGatewayIDs: ["other"],
                state: .idle,
                connectedGatewayID: nil,
                isSignInPresented: false
            ),
            .discard
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.initialGatewayDecision(
                route: route,
                savedGatewayIDs: saved,
                state: .connected,
                connectedGatewayID: "other",
                isSignInPresented: false
            ),
            .connect
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.initialGatewayDecision(
                route: route,
                savedGatewayIDs: saved,
                state: .connected,
                connectedGatewayID: "target",
                isSignInPresented: false
            ),
            .loadSessions
        )
    }

    func testRoutePolicyRequiresExactSuccessfulGatewayAfterConnect() {
        let route = TurnNotificationRoute(
            gatewayID: "target",
            storedSessionID: nil
        )

        XCTAssertEqual(
            TurnNotificationRoutePolicy.connectedGatewayDecision(
                route: route,
                state: .failed("no route"),
                connectedGatewayID: nil,
                isSignInPresented: false
            ),
            .discard
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.connectedGatewayDecision(
                route: route,
                state: .connected,
                connectedGatewayID: "other",
                isSignInPresented: false
            ),
            .wait
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.connectedGatewayDecision(
                route: route,
                state: .connected,
                connectedGatewayID: "target",
                isSignInPresented: true
            ),
            .wait
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.connectedGatewayDecision(
                route: route,
                state: .connected,
                connectedGatewayID: "target",
                isSignInPresented: false
            ),
            .loadSessions
        )
    }

    func testRoutePolicySelectsOnlyStoredSessionAndFinishesGatewayRoute() {
        let storedRoute = TurnNotificationRoute(
            gatewayID: "target",
            storedSessionID: "stored"
        )

        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: storedRoute,
                state: .loading,
                sessionIDs: ["stored"],
                selectedSessionID: nil
            ),
            .wait
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: storedRoute,
                state: .failed("missing"),
                sessionIDs: [],
                selectedSessionID: nil
            ),
            .discard
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: storedRoute,
                state: .loaded,
                sessionIDs: ["other"],
                selectedSessionID: "other"
            ),
            .discard
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: storedRoute,
                state: .loaded,
                sessionIDs: ["stored"],
                selectedSessionID: "other"
            ),
            .select("stored")
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: storedRoute,
                state: .loaded,
                sessionIDs: ["stored"],
                selectedSessionID: "stored"
            ),
            .finish
        )
        XCTAssertEqual(
            TurnNotificationRoutePolicy.sessionDecision(
                route: TurnNotificationRoute(
                    gatewayID: "target",
                    storedSessionID: nil
                ),
                state: .loaded,
                sessionIDs: [],
                selectedSessionID: nil
            ),
            .finish
        )
    }

    func testControllerEndsExactTaskAndNotifiesOnlyInBackground() throws {
        let execution = RecordingBackgroundExecution()
        let notifications = RecordingTurnNotifications()
        let controller = IOSTurnBackgroundController(
            execution: execution,
            notifications: notifications
        )
        let first = target("first")

        controller.onAppForegroundChanged(true)
        try controller.turnStarted(first)
        controller.turnCompleted(first)

        XCTAssertEqual(
            execution.ended,
            [UIBackgroundTaskIdentifier(rawValue: 1)]
        )
        XCTAssertTrue(notifications.targets.isEmpty)

        controller.onAppForegroundChanged(false)
        try controller.turnStarted(first)
        controller.turnCompleted(first)

        XCTAssertEqual(
            execution.ended,
            [
                UIBackgroundTaskIdentifier(rawValue: 1),
                UIBackgroundTaskIdentifier(rawValue: 2),
            ]
        )
        XCTAssertEqual(notifications.targets, [first])
    }

    func testExpirationEndsTaskAndReportsExactTargetWithoutCompletion() throws {
        let execution = RecordingBackgroundExecution()
        let notifications = RecordingTurnNotifications()
        let controller = IOSTurnBackgroundController(
            execution: execution,
            notifications: notifications
        )
        let target = target("expired")
        var expirations: [BackgroundTurnTarget] = []
        controller.installExpirationHandler {
            expirations.append($0)
        }

        try controller.turnStarted(target)
        execution.expireLast()

        XCTAssertEqual(
            execution.ended,
            [UIBackgroundTaskIdentifier(rawValue: 1)]
        )
        XCTAssertEqual(expirations, [target])
        XCTAssertTrue(notifications.targets.isEmpty)
    }

    func testEducationChoicePersistsAndRequestsOnlyAfterEnable() async {
        let store = MemoryNotificationEducationStore()
        let permissions = RecordingNotificationPermissions(
            status: .notDetermined
        )
        let model = NotificationEducationModel(
            store: store,
            permissions: permissions
        )

        model.considerPresentation()
        await eventually { model.isVisible }
        model.enableNotifications()
        await eventually { permissions.requestCount == 1 }
        model.considerPresentation()
        await Task.yield()

        XCTAssertFalse(model.isVisible)
        XCTAssertTrue(store.isDismissed())
    }

    private func target(_ suffix: String) -> BackgroundTurnTarget {
        BackgroundTurnTarget(
            gatewayID: "gateway-\(suffix)",
            storedSessionID: "stored-\(suffix)",
            liveSessionID: "live-\(suffix)"
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
final class BiometricAppLockModelTests: XCTestCase {
    func testDisabledLockStartsUncoveredWithoutAuthenticating() async {
        let store = MemoryBiometricAppLockStore(isEnabled: false)
        let authenticator = RecordingBiometricAuthenticator(
            capability: .available(.faceID),
            outcomes: []
        )
        let model = BiometricAppLockModel(
            store: store,
            authenticator: authenticator
        )

        await model.appDidBecomeActive()

        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
        XCTAssertTrue(authenticator.reasons.isEmpty)
    }

    func testEnablingPersistsOnlyAfterSuccessfulBiometricCheck() async {
        let store = MemoryBiometricAppLockStore(isEnabled: false)
        let authenticator = RecordingBiometricAuthenticator(
            capability: .available(.faceID),
            outcomes: [true]
        )
        let model = BiometricAppLockModel(
            store: store,
            authenticator: authenticator
        )

        await model.appDidBecomeActive()
        await model.setEnabled(true)

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(store.isEnabled())
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
        XCTAssertEqual(authenticator.reasons.count, 1)
        XCTAssertTrue(authenticator.reasons[0].contains("Face ID"))
    }

    func testFailedOrUnavailableBiometricsCannotEnableLock() async {
        let failureStore = MemoryBiometricAppLockStore(isEnabled: false)
        let failureAuthenticator = RecordingBiometricAuthenticator(
            capability: .available(.touchID),
            outcomes: [false]
        )
        let failureModel = BiometricAppLockModel(
            store: failureStore,
            authenticator: failureAuthenticator
        )

        await failureModel.setEnabled(true)

        XCTAssertFalse(failureModel.isEnabled)
        XCTAssertFalse(failureStore.isEnabled())
        XCTAssertEqual(
            failureModel.errorMessage,
            "Authentication was not completed. App lock remains off."
        )

        let unavailableStore = MemoryBiometricAppLockStore(isEnabled: false)
        let unavailableAuthenticator = RecordingBiometricAuthenticator(
            capability: .unavailable(
                .faceID,
                message: "Set up Face ID first."
            ),
            outcomes: []
        )
        let unavailableModel = BiometricAppLockModel(
            store: unavailableStore,
            authenticator: unavailableAuthenticator
        )

        await unavailableModel.setEnabled(true)

        XCTAssertFalse(unavailableModel.isEnabled)
        XCTAssertFalse(unavailableStore.isEnabled())
        XCTAssertEqual(
            unavailableModel.errorMessage,
            "Set up Face ID first."
        )
        XCTAssertTrue(unavailableAuthenticator.reasons.isEmpty)

        for (failure, message) in [
            (NileBiometricAuthenticationFailure.canceled,
             "Authentication was canceled. App lock remains off."),
            (.lockedOut,
             "Biometrics are locked. Unlock your iPhone with its passcode, then try again."),
            (.notEnrolled,
             "Set up Face ID or Touch ID in iOS Settings, then try again."),
            (.failed, "Authentication failed. App lock remains off."),
        ] {
            let store = MemoryBiometricAppLockStore(isEnabled: false)
            let model = BiometricAppLockModel(
                store: store,
                authenticator: FailingBiometricAuthenticator(failure: failure)
            )

            await model.setEnabled(true)

            XCTAssertFalse(model.isEnabled)
            XCTAssertFalse(store.isEnabled())
            XCTAssertEqual(model.errorMessage, message)
        }
    }

    func testLifecyclePrivacyShieldAndUnlockRemainFailClosed() async {
        let store = MemoryBiometricAppLockStore(isEnabled: true)
        let authenticator = RecordingBiometricAuthenticator(
            capability: .available(.faceID),
            outcomes: [true, false, true]
        )
        let model = BiometricAppLockModel(
            store: store,
            authenticator: authenticator
        )

        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)

        await model.appDidBecomeActive()
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)

        model.appDidBecomeInactive()
        XCTAssertFalse(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)

        await model.appDidBecomeActive()
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
        XCTAssertEqual(authenticator.reasons.count, 1)

        model.appDidEnterBackground()
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)

        await model.appDidBecomeActive()
        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)
        XCTAssertEqual(
            model.errorMessage,
            "Authentication was not completed. Nile remains locked."
        )

        await model.unlock()
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(authenticator.reasons.count, 3)
    }

    func testDisablingClearsPersistedAndVisibleLockState() async {
        let store = MemoryBiometricAppLockStore(isEnabled: true)
        let model = BiometricAppLockModel(
            store: store,
            authenticator: RecordingBiometricAuthenticator(
                capability: .available(.touchID),
                outcomes: []
            )
        )

        await model.setEnabled(false)

        XCTAssertFalse(store.isEnabled())
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
    }

    func testBackgroundDuringAuthenticationCannotUnlockApp() async {
        let authenticator = SuspendingBiometricAuthenticator()
        let model = BiometricAppLockModel(
            store: MemoryBiometricAppLockStore(isEnabled: true),
            authenticator: authenticator
        )

        let authentication = Task {
            await model.appDidBecomeActive()
        }
        while !authenticator.isWaiting {
            await Task.yield()
        }

        model.appDidEnterBackground()
        authenticator.complete(with: true)
        await authentication.value

        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)
    }

    func testTransientInactivityDuringAuthenticationDoesNotReprompt() async {
        let authenticator = SuspendingBiometricAuthenticator()
        let model = BiometricAppLockModel(
            store: MemoryBiometricAppLockStore(isEnabled: true),
            authenticator: authenticator
        )

        let authentication = Task {
            await model.appDidBecomeActive()
        }
        while !authenticator.isWaiting {
            await Task.yield()
        }

        model.appDidBecomeInactive()
        authenticator.complete(with: true)
        await authentication.value

        XCTAssertFalse(model.isLocked)
        XCTAssertTrue(model.showsPrivacyShield)

        await model.appDidBecomeActive()

        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.showsPrivacyShield)
        XCTAssertFalse(authenticator.isWaiting)
    }
}

@MainActor
private final class RecordingBackgroundExecution:
    BackgroundExecutionOperating
{
    private var nextIdentifier = 1
    private var expiration: (@MainActor @Sendable () -> Void)?
    private(set) var ended: [UIBackgroundTaskIdentifier] = []

    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        self.expiration = expiration
        defer { nextIdentifier += 1 }
        return UIBackgroundTaskIdentifier(rawValue: nextIdentifier)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        ended.append(identifier)
    }

    func expireLast() {
        expiration?()
    }
}

@MainActor
private final class RecordingTurnNotifications: TurnNotificationScheduling {
    private(set) var targets: [BackgroundTurnTarget] = []

    func scheduleCompletion(for target: BackgroundTurnTarget) {
        targets.append(target)
    }
}

private final class MemoryNotificationEducationStore:
    NotificationEducationStoring,
    @unchecked Sendable
{
    private var dismissed = false

    func isDismissed() -> Bool {
        dismissed
    }

    func dismiss() {
        dismissed = true
    }
}

@MainActor
private final class MemoryBiometricAppLockStore:
    BiometricAppLockStoring
{
    private var enabled: Bool

    init(isEnabled: Bool) {
        enabled = isEnabled
    }

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }
}

@MainActor
private final class RecordingBiometricAuthenticator:
    BiometricAuthenticating
{
    private let currentCapability: NileBiometricCapability
    private var outcomes: [Bool]
    private(set) var reasons: [String] = []

    init(
        capability: NileBiometricCapability,
        outcomes: [Bool]
    ) {
        currentCapability = capability
        self.outcomes = outcomes
    }

    func capability() -> NileBiometricCapability {
        currentCapability
    }

    func authenticate(reason: String) -> Bool {
        reasons.append(reason)
        return outcomes.isEmpty ? false : outcomes.removeFirst()
    }
}

@MainActor
private final class FailingBiometricAuthenticator:
    BiometricAuthenticating
{
    private let failure: NileBiometricAuthenticationFailure

    init(failure: NileBiometricAuthenticationFailure) {
        self.failure = failure
    }

    func capability() -> NileBiometricCapability {
        .available(.faceID)
    }

    func authenticate(reason: String) async throws -> Bool {
        throw failure
    }
}

@MainActor
private final class SuspendingBiometricAuthenticator:
    BiometricAuthenticating
{
    private var continuation: CheckedContinuation<Bool, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func capability() -> NileBiometricCapability {
        .available(.faceID)
    }

    func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Bool) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

@MainActor
private final class RecordingNotificationPermissions:
    NotificationPermissionManaging
{
    let status: NileNotificationAuthorizationStatus
    private(set) var requestCount = 0

    init(status: NileNotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> NileNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() -> Bool {
        requestCount += 1
        return true
    }
}
