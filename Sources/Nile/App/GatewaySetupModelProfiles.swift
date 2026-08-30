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
        resetHermesVoice()
        gatewayWillConnectHandler?(active.id)
        state = .checking
        do {
            try await connectionClient.connect(
                active.connection,
                timeoutMilliseconds: 15_000
            )
            connectedProfile = active
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            await connectionClient.close()
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
        reconnectCoordinator.cancel()
        operationError = nil
        resetHermesVoice()
        gatewayWillConnectHandler?(profile.id)
        state = .checking
        do {
            try await connectionClient.connect(
                profile.connection,
                timeoutMilliseconds: 15_000
            )
            try await profileStore.selectGateway(id: id)
            connectedProfile = profile
            activeGatewayID = id
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            await connectionClient.close()
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
            try await profileStore.removeGateway(id: id)
            let snapshot = try await profileStore.load()
            let draftCleanupError: String?
            do {
                try await composerDraftStore?.removeGateway(id: id)
                try await attachmentDraftStore?.removeGateway(id: id)
                try await sessionPinStore?.removeGateway(id: id)
                try await modelPinStore?.removeGateway(id: id)
                draftCleanupError = nil
            } catch {
                draftCleanupError =
                    "The gateway was removed, but Nile could not erase all of its protected local data: \(error.localizedDescription)"
            }
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
            if let draftCleanupError {
                if case .failed = state {
                    // Preserve the more actionable connection failure.
                } else {
                    operationError = draftCleanupError
                }
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
        reconnectCoordinator.cancel()
        resetHermesVoice()
        operationError = nil
        isSettingsVisible = true
    }

    func dismissSettings() {
        guard isConnected, !isUpdatingHermesVoice else {
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
