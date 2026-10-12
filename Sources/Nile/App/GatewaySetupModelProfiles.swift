import Foundation

/// Saved-profile selection, removal, and settings presentation.
///
/// Connection retry and dashboard sign-in stay in the connection extension;
/// this boundary owns only the explicit profile actions initiated by settings.
@MainActor
extension GatewaySetupModel {
    func approveCleartextAndConnect() async {
        guard cleartextGatewaysSupported,
              parsedFormEndpoint?.isCleartext == true else {
            return
        }
        cleartextApproved = true
        showCleartextConfirmation = false
        await connect()
    }

    func restoreSavedGateway() async {
        guard state == .loading else {
            return
        }
        operationError = nil
        let snapshot: GatewayProfileSnapshot
        do {
            snapshot = try await profileStore.load()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        savedGateways = snapshot.profiles
        activeGatewayID = snapshot.activeProfile?.id
        guard let active = snapshot.activeProfile else {
            state = .idle
            return
        }

        dashboardURL = active.normalizedBaseURL
        guard !requireSharingConsent(
            for: active.endpoint, name: active.displayName, profileID: active.id
        ) else { return }
        let consentGeneration = sharingConsentGeneration
        resetHermesVoice()
        gatewayWillConnectHandler?(active.id)
        // Keep the launch surface visible until the first saved connection
        // settles. Settings is for setup or an actionable connection failure.
        do {
            try await connectionClient.connect(
                active.connection,
                timeoutMilliseconds: 15_000
            )
            guard sharingConsentIsCurrent(for: active.endpoint, generation: consentGeneration) else { return }
            connectedProfile = active
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            guard sharingConsentIsCurrent(for: active.endpoint, generation: consentGeneration) else { return }
            await connectionClient.close()
            guard sharingConsentIsCurrent(for: active.endpoint, generation: consentGeneration) else { return }
            if presentSignIn(
                for: error,
                pending: PendingSignIn(
                    connection: active.connection,
                    name: active.name,
                    profile: active
                )
            ) {
                return
            }
            if Self.isRetryableConnectionFailure(error) {
                connectedProfile = active
                state = .reconnecting
                isSettingsVisible = false
                scheduleReconnect(for: active)
                return
            }
            connectedProfile = nil
            state = .failed(Self.connectionMessage(for: error))
            isSettingsVisible = true
        }
    }

    func useGateway(id: String) async {
        guard state != .checking,
              !isUpdatingHermesVoice,
              let profile = savedGateways.first(where: { $0.id == id })
        else {
            return
        }
        setPendingGatewaySwitch(nil)
        operationError = nil
        guard !requireSharingConsent(
            for: profile.endpoint, name: profile.displayName, profileID: profile.id
        ) else { return }
        reconnectCoordinator.cancel()
        let consentGeneration = sharingConsentGeneration
        resetHermesVoice()
        gatewayWillConnectHandler?(profile.id)
        state = .checking
        do {
            try await connectionClient.connect(
                profile.connection,
                timeoutMilliseconds: 15_000
            )
            guard sharingConsentIsCurrent(for: profile.endpoint, generation: consentGeneration) else { return }
            try await profileStore.selectGateway(id: id)
            guard sharingConsentIsCurrent(for: profile.endpoint, generation: consentGeneration) else { return }
            connectedProfile = profile
            activeGatewayID = id
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            guard sharingConsentIsCurrent(for: profile.endpoint, generation: consentGeneration) else { return }
            await connectionClient.close()
            guard sharingConsentIsCurrent(for: profile.endpoint, generation: consentGeneration) else { return }
            if presentSignIn(
                for: error,
                pending: PendingSignIn(
                    connection: profile.connection,
                    name: profile.name,
                    profile: profile
                )
            ) {
                return
            }
            if Self.isRetryableConnectionFailure(error) {
                connectedProfile = profile
                activeGatewayID = profile.id
                state = .reconnecting
                isSettingsVisible = false
                scheduleReconnect(for: profile)
                return
            }
            connectedProfile = nil
            state = .failed(Self.connectionMessage(for: error))
        }
    }

    func requestGatewayUse(id: String) async {
        guard state != .checking,
              !isUpdatingHermesVoice,
              let profile = savedGateways.first(where: { $0.id == id })
        else {
            return
        }
        operationError = nil
        if profile.id == activeGatewayID, isConnected {
            setPendingGatewaySwitch(nil)
            dismissSettings()
            return
        }
        if gatewaySwitchNeedsConfirmationHandler?(profile.id) == true {
            setPendingGatewaySwitch(profile)
            return
        }
        await useGateway(id: profile.id)
    }

    func dismissGatewaySwitchConfirmation() {
        setPendingGatewaySwitch(nil)
    }

    func confirmGatewaySwitch() async {
        guard state != .checking,
              !isUpdatingHermesVoice,
              let pendingGatewaySwitch,
              let profile = savedGateways.first(
                  where: { $0.id == pendingGatewaySwitch.id }
              )
        else {
            return
        }
        setPendingGatewaySwitch(nil)
        await useGateway(id: profile.id)
    }

    func removeGateway(id: String) async {
        guard state != .checking, !isUpdatingHermesVoice else {
            return
        }
        operationError = nil
        guard let removingProfile = savedGateways.first(
            where: { $0.id == id }
        ) else {
            operationError = "This gateway is no longer saved."
            return
        }
        let previousState = state
        state = .checking
        defer {
            if state == .checking {
                state = previousState
            }
        }
        let removingActive = activeGatewayID == id
        if removingActive {
            reconnectCoordinator.cancel()
            resetHermesVoice()
            gatewayWillConnectHandler?(nil)
            await connectionClient.close()
            connectedProfile = nil
        }
        let remaining = savedGateways.filter { $0.id != id }
        let includeHostWideCookies =
            Self.cookiePath(for: removingProfile) == "/"
            || !remaining.contains { profile in
                Self.host(for: profile) == Self.host(for: removingProfile)
                    && Self.cookiePath(for: profile) == "/"
            }
        do {
            try await sessionCleaner?.clearSession(
                for: removingProfile.connection,
                includeHostWideCookies: includeHostWideCookies
            )
        } catch {
            let message =
                "\(removingProfile.displayName) was not removed because its "
                + "dashboard sign-in session could not be cleared. "
                + "No saved data was deleted: \(error.localizedDescription)"
            if removingActive {
                state = .failed(message)
            } else {
                operationError = message
            }
            return
        }
        do {
            try await eraseProtectedGatewayData(id: id)
            try await profileStore.removeGateway(id: id)
            let snapshot = try await profileStore.load()
            savedGateways = snapshot.profiles
            activeGatewayID = snapshot.activeProfile?.id
            if pendingGatewaySwitch?.id == id {
                setPendingGatewaySwitch(nil)
            }
            if removingActive, let next = snapshot.activeProfile {
                state = .idle
                await useGateway(id: next.id)
            } else if snapshot.profiles.isEmpty {
                state = .idle
                isSettingsVisible = true
            }
        } catch {
            if removingActive {
                await connectionClient.close()
                connectedProfile = nil
                state = .failed(error.localizedDescription)
            } else if connectedProfile != nil {
                operationError = error.localizedDescription
                state = .connected
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func showSettings() {
        guard !isUpdatingHermesVoice else {
            return
        }
        resetHermesVoice()
        operationError = nil
        isSettingsVisible = true
    }

    func dismissSettings() {
        guard connectedProfile != nil, !isChecking, !isUpdatingHermesVoice else {
            return
        }
        resetHermesVoice()
        operationError = nil
        isSettingsVisible = false
    }

    private static func host(for profile: GatewayProfile) -> String? {
        URLComponents(string: profile.normalizedBaseURL)?
            .host?.lowercased()
    }

    private static func cookiePath(for profile: GatewayProfile) -> String {
        let path = URLComponents(string: profile.normalizedBaseURL)?
            .percentEncodedPath ?? ""
        guard !path.isEmpty, path != "/" else {
            return "/"
        }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
