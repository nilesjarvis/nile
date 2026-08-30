import Foundation
import Observation

@MainActor
@Observable
final class GatewaySetupModel {
    enum ProbeState: Equatable {
        case loading
        case idle
        case checking
        case offline
        case reconnecting
        case restoring
        case connected
        case failed(String)
    }

    var gatewayName = ""
#if DEBUG || NILE_LOCAL_RELEASE
    var dashboardURL = "http://127.0.0.1:9119"
#else
    var dashboardURL = "https://hermes.example"
#endif
    var legacyToken = ""
    var cleartextApproved = false
    var showCleartextConfirmation = false
    var state: ProbeState = .loading
    var savedGateways: [GatewayProfile] = []
    var activeGatewayID: String?
    var connectedProfile: GatewayProfile?
    private(set) var pendingGatewaySwitch: GatewayProfile?
    var isSettingsVisible = true
    var gatewaySignInURL: URL?
    var signInFixtureHTML: String?
    var isHermesVoiceSheetVisible = false
    var hermesVoiceConfig: HermesVoiceConfig?
    var isLoadingHermesVoice = false
    var isUpdatingHermesVoice = false
    var hermesVoiceError: String?
    var usesDeterministicFixtureCopy = false
    var operationError: String?
    let profileStore: any GatewayProfileStoring
    let composerDraftStore: (any ComposerDraftStoring)?
    let attachmentDraftStore: (any AttachmentDraftStoring)?
    let sessionPinStore: (any SessionPinStoring)?
    let modelPinStore: (any ModelPinStoring)?
    let connectionClient: any GatewayConnecting
    let sessionCleaner: (any GatewaySessionCleaning)?
    let hermesVoice: HermesVoiceCoordinator
    let reconnectCoordinator: GatewayReconnectCoordinator
    var pendingSignIn: PendingSignIn?
    var reconnectRestorer: (
        @MainActor @Sendable (GatewayProfile) async -> Bool
    )?
    var reconnectPhaseHandler: (
        @MainActor @Sendable (SessionConnectionPhase) -> Void
    )?
    var gatewayWillConnectHandler: (
        @MainActor @Sendable (String?) -> Void
    )?
    var gatewaySwitchNeedsConfirmationHandler: (
        @MainActor @Sendable (String) -> Bool
    )?
    private var authenticationEventTask: Task<Void, Never>?

    struct PendingSignIn {
        let connection: GatewayConnection
        let name: String?
        let profile: GatewayProfile?
    }

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        profileStore: (any GatewayProfileStoring)? = nil,
        composerDraftStore: (any ComposerDraftStoring)? = nil,
        attachmentDraftStore: (any AttachmentDraftStoring)? = nil,
        sessionPinStore: (any SessionPinStoring)? = nil,
        modelPinStore: (any ModelPinStoring)? = nil,
        connectionClient: (any GatewayConnecting)? = nil,
        sessionCleaner: (any GatewaySessionCleaning)? = nil,
        hermesVoiceService: (any HermesVoiceServing)? = nil,
        statusClient: GatewayStatusClient = GatewayStatusClient(),
        reconnectCoordinator: GatewayReconnectCoordinator? = nil,
        automaticallyRestore: Bool = true
    ) {
        var shouldAutomaticallyRestore = automaticallyRestore
        let dependencies = GatewaySetupDependencies.resolve(
            profileStore: profileStore,
            composerDraftStore: composerDraftStore,
            attachmentDraftStore: attachmentDraftStore,
            sessionPinStore: sessionPinStore,
            modelPinStore: modelPinStore,
            connectionClient: connectionClient,
            sessionCleaner: sessionCleaner,
            hermesVoiceService: hermesVoiceService,
            statusClient: statusClient,
            reconnectCoordinator: reconnectCoordinator
        )
        self.profileStore = dependencies.profileStore
        self.composerDraftStore = dependencies.composerDraftStore
        self.attachmentDraftStore = dependencies.attachmentDraftStore
        self.sessionPinStore = dependencies.sessionPinStore
        self.modelPinStore = dependencies.modelPinStore
        self.connectionClient = dependencies.connectionClient
        self.sessionCleaner = dependencies.sessionCleaner
        self.hermesVoice = dependencies.hermesVoice
        self.reconnectCoordinator = dependencies.reconnectCoordinator
#if DEBUG
        if installDebugFixtures(arguments: arguments) {
            shouldAutomaticallyRestore = false
        }
#endif
        if shouldAutomaticallyRestore {
            Task { [weak self] in
                await self?.restoreSavedGateway()
            }
        }
    }

    func installReconnectRestorer(
        _ restorer: @escaping @MainActor @Sendable
            (GatewayProfile) async -> Bool
    ) {
        reconnectRestorer = restorer
    }

    func installReconnectPhaseHandler(
        _ handler: @escaping @MainActor @Sendable
            (SessionConnectionPhase) -> Void
    ) {
        reconnectPhaseHandler = handler
    }

    func installGatewayWillConnectHandler(
        _ handler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        gatewayWillConnectHandler = handler
    }

    func installGatewaySwitchNeedsConfirmationHandler(
        _ handler: @escaping @MainActor @Sendable (String) -> Bool
    ) {
        gatewaySwitchNeedsConfirmationHandler = handler
    }

    func setPendingGatewaySwitch(_ profile: GatewayProfile?) {
        pendingGatewaySwitch = profile
    }

    func observeAuthenticationEvents(
        _ events: AsyncStream<GatewayAuthenticationEvent>
    ) {
        authenticationEventTask?.cancel()
        authenticationEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                await self?.handleAuthenticationExpiry(event)
            }
        }
    }

    func connect() async {
        guard state != .checking, !isUpdatingHermesVoice else {
            return
        }
        reconnectCoordinator.cancel()
        operationError = nil
        let endpoint: GatewayEndpoint
        do {
            endpoint = try GatewayEndpoint.parse(dashboardURL)
        } catch {
            operationError = error.localizedDescription
            if connectedProfile == nil {
                state = .idle
            }
            return
        }

        if endpoint.isCleartext && !cleartextGatewaysSupported {
            operationError = "This build requires HTTPS. Use a secure gateway endpoint."
            if connectedProfile == nil {
                state = .idle
            }
            return
        }

        if endpoint.isCleartext && !cleartextApproved {
            showCleartextConfirmation = true
            return
        }

        resetHermesVoice()
        gatewayWillConnectHandler?(nil)
        state = .checking
        let connection = GatewayConnection(
            endpoint: endpoint,
            token: legacyToken.trimmingCharacters(in: .whitespacesAndNewlines),
            cleartextPermission: endpoint.isCleartext ? .approved : .denied
        )
        do {
            try await connectionClient.connect(
                connection,
                timeoutMilliseconds: 15_000
            )
        } catch {
            await connectionClient.close()
            if presentSignIn(
                for: error,
                pending: PendingSignIn(
                    connection: connection,
                    name: gatewayName,
                    profile: nil
                )
            ) {
                return
            }
            connectedProfile = nil
            state = .failed(Self.connectionMessage(for: error))
            return
        }

        do {
            let profile = try await profileStore.save(
                connection: connection,
                name: gatewayName
            )
            let snapshot = try await profileStore.load()
            savedGateways = snapshot.profiles
            activeGatewayID = profile.id
            connectedProfile = profile
            legacyToken = ""
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            await connectionClient.close()
            connectedProfile = nil
            state = .failed(error.localizedDescription)
        }
    }

    isolated deinit {
        authenticationEventTask?.cancel()
        reconnectCoordinator.cancel()
    }
}
