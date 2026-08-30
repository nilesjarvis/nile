import WebKit

struct GatewaySetupDependencies {
    let profileStore: any GatewayProfileStoring
    let composerDraftStore: (any ComposerDraftStoring)?
    let attachmentDraftStore: (any AttachmentDraftStoring)?
    let sessionPinStore: (any SessionPinStoring)?
    let modelPinStore: (any ModelPinStoring)?
    let connectionClient: any GatewayConnecting
    let sessionCleaner: (any GatewaySessionCleaning)?
    let hermesVoice: HermesVoiceCoordinator
    let reconnectCoordinator: GatewayReconnectCoordinator

    @MainActor
    static func resolve(
        profileStore: (any GatewayProfileStoring)?,
        composerDraftStore: (any ComposerDraftStoring)?,
        attachmentDraftStore: (any AttachmentDraftStoring)?,
        sessionPinStore: (any SessionPinStoring)?,
        modelPinStore: (any ModelPinStoring)?,
        connectionClient: (any GatewayConnecting)?,
        sessionCleaner: (any GatewaySessionCleaning)?,
        hermesVoiceService: (any HermesVoiceServing)?,
        statusClient: GatewayStatusClient,
        reconnectCoordinator: GatewayReconnectCoordinator?
    ) -> Self {
        let resolvedProfileStore = profileStore ?? SecureGatewayProfileStore()
        let resolvedConnectionClient: any GatewayConnecting
        let resolvedSessionCleaner: (any GatewaySessionCleaning)?
        if let connectionClient {
            resolvedConnectionClient = connectionClient
            resolvedSessionCleaner = sessionCleaner
        } else {
            let authenticator = GatewayAuthenticationService(
                statusClient: statusClient,
                cookieStore: WebKitGatewayCookieStore(),
                savedProfiles: {
                    try await resolvedProfileStore.load().profiles
                }
            )
            resolvedConnectionClient = TuiGatewayClient(
                requestFactory: GatewayAuthenticationRequestFactory(
                    authenticator: authenticator
                )
            )
            resolvedSessionCleaner = sessionCleaner ?? authenticator
        }
        let hermesVoice = HermesVoiceCoordinator(
            loadVoice: {
                guard let hermesVoiceService else {
                    throw unavailableVoiceError
                }
                return try await hermesVoiceService.getHermesVoiceConfig()
            },
            updateVoice: { expectedProvider, voice in
                guard let hermesVoiceService else {
                    throw unavailableVoiceError
                }
                return try await hermesVoiceService.setHermesVoice(
                    expectedProvider: expectedProvider,
                    voice: voice
                )
            }
        )
        return Self(
            profileStore: resolvedProfileStore,
            composerDraftStore: composerDraftStore,
            attachmentDraftStore: attachmentDraftStore,
            sessionPinStore: sessionPinStore,
            modelPinStore: modelPinStore,
            connectionClient: resolvedConnectionClient,
            sessionCleaner: resolvedSessionCleaner,
            hermesVoice: hermesVoice,
            reconnectCoordinator:
                reconnectCoordinator ?? GatewayReconnectCoordinator()
        )
    }

    private static var unavailableVoiceError: HermesError {
        HermesError(
            "Hermes voice settings are unavailable for this repository",
            retryable: false
        )
    }
}
