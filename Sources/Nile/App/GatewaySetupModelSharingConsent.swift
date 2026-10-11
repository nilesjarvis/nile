import Foundation

struct GatewaySharingConsentRequest: Identifiable, Equatable {
    let id = UUID()
    let endpoint: GatewayEndpoint
    let gatewayName: String
    let profileID: String?
}

@MainActor
extension GatewaySetupModel {
    func installSharingConsentRevokedHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        sharingConsentRevokedHandler = handler
    }

    func requireSharingConsent(
        for endpoint: GatewayEndpoint,
        name: String,
        profileID: String? = nil
    ) -> Bool {
        guard !sharingConsentStore.isAccepted(for: endpoint) else {
            pendingSharingConsent = nil
            return false
        }
        pendingSharingConsent = GatewaySharingConsentRequest(
            endpoint: endpoint, gatewayName: name, profileID: profileID
        )
        if connectedProfile == nil { state = .idle }
        isSettingsVisible = true
        return true
    }

    func approveSharingConsent() async {
        guard let request = pendingSharingConsent else { return }
        pendingSharingConsent = nil
        if let profileID = request.profileID {
            guard let profile = savedGateways.first(where: { $0.id == profileID }),
                  profile.endpoint == request.endpoint else {
                operationError = "The gateway changed. Review sharing again before connecting."
                return
            }
            sharingConsentStore.accept(for: request.endpoint)
            await useGateway(id: profileID)
        } else {
            guard parsedFormEndpoint == request.endpoint else {
                operationError = "The gateway changed. Review sharing again before connecting."
                return
            }
            sharingConsentStore.accept(for: request.endpoint)
            await connect()
        }
    }

    func cancelSharingConsent() {
        pendingSharingConsent = nil
    }

    func revokeSharingConsent() async {
        sharingConsentGeneration &+= 1
        let generation = sharingConsentGeneration
        sharingConsentStore.revokeAll()
        reconnectCoordinator.cancel()
        pendingSharingConsent = nil
        pendingSignIn = nil
        gatewaySignInURL = nil
        signInFixtureHTML = nil
        setPendingGatewaySwitch(nil)
        showCleartextConfirmation = false
        resetHermesVoice()
        gatewayWillConnectHandler?(nil)
        sharingConsentRevokedHandler?()
        connectedProfile = nil
        legacyToken = ""
        operationError = nil
        state = .checking
        isSettingsVisible = true
        await connectionClient.close()
        if sharingConsentGeneration == generation { state = .idle }
    }

    func sharingConsentIsCurrent(
        for endpoint: GatewayEndpoint,
        generation: UInt64
    ) -> Bool {
        // Withdrawal owns closing the old connection. Stale completions must
        // return without closing a newer connection approved by the user.
        generation == sharingConsentGeneration
            && sharingConsentStore.isAccepted(for: endpoint)
    }
}
