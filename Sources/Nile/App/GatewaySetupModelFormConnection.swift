import Foundation

@MainActor
extension GatewaySetupModel {
    func connectApprovedForm(to endpoint: GatewayEndpoint) async {
        guard sharingConsentStore.isAccepted(for: endpoint) else { return }
        reconnectCoordinator.cancel()
        let consentGeneration = sharingConsentGeneration

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
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
        } catch {
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
            await connectionClient.close()
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
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
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
            savedGateways = snapshot.profiles
            activeGatewayID = profile.id
            connectedProfile = profile
            legacyToken = ""
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
            await connectionClient.close()
            guard sharingConsentIsCurrent(for: endpoint, generation: consentGeneration) else { return }
            connectedProfile = nil
            state = .failed(error.localizedDescription)
        }
    }

}
