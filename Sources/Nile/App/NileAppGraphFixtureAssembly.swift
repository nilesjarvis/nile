import Foundation

#if DEBUG || NILE_LOCAL_RELEASE
/// Constructs only the fake capabilities selected by the launch-argument plan.
/// Selection and precedence remain in `NileAppGraphFixturePlan`.
extension NileAppGraphFixturePlan {
    @MainActor
    func makeBiometricAppLockFixture() -> BiometricAppLockModel? {
#if DEBUG
        guard showsBiometricLockFailureFixture else {
            return nil
        }
        return BiometricAppLockModel(
            store: NileAppGraphFixtures.BiometricAppLockFixtureStore(),
            authenticator: NileAppGraphFixtures
                .BiometricAppLockFixtureAuthenticator()
        )
#else
        nil
#endif
    }

    func makeGatewayProfileStoreFixture()
        -> (any GatewayProfileStoring)?
    {
        let profiles = gatewayVisualFixtureProfiles
        guard !profiles.isEmpty else {
            return nil
        }
        return NileAppGraphFixtures.GatewayVisualFixtureProfileStore(
            profiles: profiles,
            activeID: "home"
        )
    }

    func makeGatewayConnectionClientFixture()
        -> (any GatewayConnecting)?
    {
        confirmsGatewaySwitchFixture
            ? NileAppGraphFixtures.GatewaySwitchFixtureConnectionClient()
            : nil
    }

    func makeGatewaySessionCleanerFixture()
        -> (any GatewaySessionCleaning)?
    {
        gatewayVisualFixture == nil
            ? nil
            : NileAppGraphFixtures.GatewayRemovalFixtureSessionCleaner()
    }

    func makeHermesVoiceServiceFixture() -> (any HermesVoiceServing)? {
        showsHermesVoiceFixture
            ? NileAppGraphFixtures.HermesVoiceFixtureService()
            : nil
    }

    @MainActor
    func configureGatewaySetupFixture(_ gatewaySetup: GatewaySetupModel) {
        let profiles = gatewayVisualFixtureProfiles
        if let activeProfile = profiles.first {
            Self.configureConnectedGateway(
                activeProfile,
                profiles: profiles,
                gatewaySetup: gatewaySetup
            )
        }
        if showsHermesVoiceFixture {
            let profile = Self.hermesVoiceProfile()
            Self.configureConnectedGateway(
                profile,
                profiles: [profile],
                gatewaySetup: gatewaySetup
            )
        }
    }

    @MainActor
    func makeSessionListFixture() -> SessionListModel? {
        guard showsSessionFixture else {
            return nil
        }
        return SessionListModel(
            fixture: sessionFixture
                ?? (showsTerminalBusyFixture ? .terminalBusy : .showcase),
            voiceInput: showsTalkFixture
                ? NileAppGraphFixtures.TalkFixtureVoiceInput()
                : UnavailableVoiceInput(),
            sessionSwitchDelay:
                showsSessionSwitchFixture || showsEmptySessionSwitchFixture
                ? .seconds(4)
                : nil,
            startsWithEmptyTranscript: showsEmptySessionSwitchFixture
        )
    }

    private var gatewayVisualFixtureProfiles: [GatewayProfile] {
        guard let gatewayVisualFixture else {
            return []
        }
        return switch gatewayVisualFixture {
        case .switchConfirmation:
            Self.gatewaySwitchProfiles()
        case .removal:
            [Self.gatewayRemovalProfile()]
        }
    }

    @MainActor
    private static func configureConnectedGateway(
        _ activeProfile: GatewayProfile,
        profiles: [GatewayProfile],
        gatewaySetup: GatewaySetupModel
    ) {
        gatewaySetup.state = .connected
        gatewaySetup.savedGateways = profiles
        gatewaySetup.activeGatewayID = activeProfile.id
        gatewaySetup.connectedProfile = activeProfile
        gatewaySetup.dashboardURL = activeProfile.normalizedBaseURL
        gatewaySetup.isSettingsVisible = true
    }

    private static func gatewaySwitchProfiles() -> [GatewayProfile] {
        [
            try! GatewayProfile(
                id: "home",
                name: "Home Hermes",
                baseURL: "https://home.example",
                token: "fixture-token"
            ),
            try! GatewayProfile(
                id: "lab",
                name: "Lab Hermes",
                baseURL: "https://lab.example",
                token: "fixture-token"
            ),
        ]
    }

    private static func gatewayRemovalProfile() -> GatewayProfile {
        try! GatewayProfile(
            id: "home",
            name: "Home Hermes",
            baseURL: "https://hermes.example",
            token: "fixture-token"
        )
    }

    private static func hermesVoiceProfile() -> GatewayProfile {
        try! GatewayProfile(
            id: "voice-fixture-gateway",
            name: "Voice fixture",
            baseURL: "https://voice-fixture.example",
            token: "fixture-token"
        )
    }
}
#else
extension NileAppGraphFixturePlan {
    @MainActor
    func makeBiometricAppLockFixture() -> BiometricAppLockModel? { nil }
    func makeGatewayProfileStoreFixture() -> (any GatewayProfileStoring)? { nil }
    func makeGatewayConnectionClientFixture() -> (any GatewayConnecting)? { nil }
    func makeGatewaySessionCleanerFixture() -> (any GatewaySessionCleaning)? { nil }
    func makeHermesVoiceServiceFixture() -> (any HermesVoiceServing)? { nil }
    @MainActor
    func configureGatewaySetupFixture(_ gatewaySetup: GatewaySetupModel) {}
    @MainActor
    func makeSessionListFixture() -> SessionListModel? { nil }
}
#endif
