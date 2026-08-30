import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class NileAppGraph {
    let gatewaySetup: GatewaySetupModel
    let sessionList: SessionListModel
    let notificationEducation: NotificationEducationModel
    let appLock: BiometricAppLockModel
    let showsSessionFixture: Bool
    let forcesReducedMotionFixture: Bool
    private(set) var pendingTurnNotificationRoute: TurnNotificationRoute?
    private var isResolvingTurnNotificationRoute = false
    @ObservationIgnored
    private var streamingStressFixtureTask: Task<Void, Never>?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let fixturePlan = NileAppGraphFixturePlan(arguments: arguments)
        forcesReducedMotionFixture =
            fixturePlan.forcesReducedMotionFixture
        appLock = fixturePlan.makeBiometricAppLockFixture()
            ?? BiometricAppLockModel()
        let profileStore: any GatewayProfileStoring =
            fixturePlan.makeGatewayProfileStoreFixture()
                ?? SecureGatewayProfileStore()
        let statusClient = GatewayStatusClient()
        let authentication = GatewayAuthenticationService(
            statusClient: statusClient,
            cookieStore: WebKitGatewayCookieStore(),
            savedProfiles: {
                try await profileStore.load().profiles
            }
        )
        let client = TuiGatewayClient(
            requestFactory: GatewayAuthenticationRequestFactory(
                authenticator: authentication
            )
        )
        let repository = TuiGatewayRepository(
            client: client,
            dashboard: GatewayDashboardClient(
                transport: authentication
            )
        )
        let gatewayConnectionClient: any GatewayConnecting =
            fixturePlan.makeGatewayConnectionClientFixture()
                ?? repository
        let draftStore = ProtectedComposerDraftStore()
        let attachmentDraftStore = ProtectedAttachmentDraftStore()
        let sessionPinStore = ProtectedSessionPinStore()
        let sessionPinWriteQueue = SessionPinWriteQueue(
            store: sessionPinStore
        )
        let modelPinStore = ProtectedModelPinStore()
        let modelPinWriteQueue = ModelPinWriteQueue(store: modelPinStore)
        let hermesVoiceService: any HermesVoiceServing =
            fixturePlan.makeHermesVoiceServiceFixture()
                ?? repository.voiceService
        let gatewaySessionCleaner: any GatewaySessionCleaning =
            fixturePlan.makeGatewaySessionCleanerFixture()
                ?? authentication
        showsSessionFixture = fixturePlan.showsSessionFixture
        notificationEducation = NotificationEducationModel(
            initiallyVisible:
                fixturePlan.showsNotificationEducationFixture
        )
        gatewaySetup = GatewaySetupModel(
            arguments: arguments,
            profileStore: profileStore,
            composerDraftStore: draftStore,
            attachmentDraftStore: attachmentDraftStore,
            sessionPinStore: sessionPinStore,
            modelPinStore: modelPinStore,
            connectionClient: gatewayConnectionClient,
            sessionCleaner: gatewaySessionCleaner,
            hermesVoiceService: hermesVoiceService,
            statusClient: statusClient,
            automaticallyRestore: fixturePlan.automaticallyRestoresGateway
        )
        fixturePlan.configureGatewaySetupFixture(gatewaySetup)
        sessionList = fixturePlan.makeSessionListFixture()
            ?? SessionListModel(
                repository: repository,
                draftStore: draftStore,
                attachmentDraftStore: attachmentDraftStore,
                sessionPinStore: sessionPinStore,
                sessionPinWriteQueue: sessionPinWriteQueue,
                modelPinStore: modelPinStore,
                modelPinWriteQueue: modelPinWriteQueue,
                backgroundController: IOSTurnBackgroundController()
            )
        streamingStressFixtureTask = NileAppGraphFixtureInstaller.install(
            fixturePlan,
            on: sessionList
        )
        sessionList.installConnectionLossHandler {
            [weak setup = gatewaySetup] notice in
            setup?.handleConnectionLoss(notice)
        }
        sessionList.installBackgroundTurnStartedHandler {
            [weak education = notificationEducation] in
            education?.considerPresentation()
        }
        gatewaySetup.installGatewayWillConnectHandler {
            [weak sessions = sessionList] gatewayID in
            sessions?.stopBackgroundTurnsOutsideGateway(gatewayID)
        }
        gatewaySetup.installGatewaySwitchNeedsConfirmationHandler {
            [weak sessions = sessionList] gatewayID in
            if fixturePlan.confirmsGatewaySwitchFixture {
                return gatewayID == "lab"
            }
            return sessions?.hasBackgroundTurnsOutsideGateway(gatewayID)
                ?? false
        }
        gatewaySetup.installReconnectPhaseHandler {
            [weak sessions = sessionList] phase in
            sessions?.setConnectionRecoveryPhase(phase)
        }
        gatewaySetup.installReconnectRestorer {
            [weak sessions = sessionList] profile in
            guard let sessions else {
                return false
            }
            return await sessions.restoreAfterReconnect(
                gatewayID: profile.id,
                preferredSessionID: profile.lastSessionID
            )
        }
        gatewaySetup.observeAuthenticationEvents(
            authentication.authenticationEvents
        )
    }

    func receiveTurnNotificationRoute(_ route: TurnNotificationRoute) {
        pendingTurnNotificationRoute = route
        Task { [weak self] in
            await self?.resolvePendingTurnNotificationRoute()
        }
    }

    func resolvePendingTurnNotificationRoute() async {
        guard !showsSessionFixture,
              !isResolvingTurnNotificationRoute,
              let route = pendingTurnNotificationRoute
        else {
            return
        }
        let initialDecision = TurnNotificationRoutePolicy
            .initialGatewayDecision(
                route: route,
                savedGatewayIDs: Set(gatewaySetup.savedGateways.map(\.id)),
                state: gatewaySetup.state,
                connectedGatewayID: gatewaySetup.connectedProfile?.id,
                isSignInPresented: gatewaySetup.gatewaySignInURL != nil
            )
        switch initialDecision {
        case .wait:
            return
        case .discard:
            pendingTurnNotificationRoute = nil
            return
        case .connect, .loadSessions:
            break
        }

        isResolvingTurnNotificationRoute = true
        defer { isResolvingTurnNotificationRoute = false }

        if initialDecision == .connect {
            await gatewaySetup.useGateway(id: route.gatewayID)
        }
        switch TurnNotificationRoutePolicy.connectedGatewayDecision(
            route: route,
            state: gatewaySetup.state,
            connectedGatewayID: gatewaySetup.connectedProfile?.id,
            isSignInPresented: gatewaySetup.gatewaySignInURL != nil
        ) {
        case .wait, .connect:
            return
        case .discard:
            pendingTurnNotificationRoute = nil
            return
        case .loadSessions:
            break
        }
        gatewaySetup.dismissSettings()
        await sessionList.load(
            gatewayID: route.gatewayID,
            preferredSessionID: route.storedSessionID
        )
        var sessionDecision = TurnNotificationRoutePolicy.sessionDecision(
            route: route,
            state: sessionList.state,
            sessionIDs: Set(sessionList.sessions.map(\.id)),
            selectedSessionID: sessionList.selectedSessionID
        )
        if case let .select(storedSessionID) = sessionDecision {
            await sessionList.selectSession(id: storedSessionID)
            sessionDecision = TurnNotificationRoutePolicy.sessionDecision(
                route: route,
                state: sessionList.state,
                sessionIDs: Set(sessionList.sessions.map(\.id)),
                selectedSessionID: sessionList.selectedSessionID
            )
        }
        switch sessionDecision {
        case .wait, .select:
            return
        case .discard:
            pendingTurnNotificationRoute = nil
        case .finish:
            pendingTurnNotificationRoute = nil
        }
    }
}
