import Foundation

/// Dashboard sign-in and reconnect state-machine integration.
///
/// `GatewayReconnectCoordinator` owns retry timing; this extension applies its
/// phases to the observable gateway state and restores the selected session.
@MainActor
extension GatewaySetupModel {
    func completeGatewaySignIn() async {
        guard state != .checking,
              let pending = pendingSignIn,
              gatewaySignInURL != nil
        else {
            return
        }
        gatewaySignInURL = nil
        operationError = nil
        if let profile = pending.profile {
            pendingSignIn = nil
            connectedProfile = profile
            activeGatewayID = profile.id
            state = .reconnecting
            isSettingsVisible = false
            scheduleReconnect(for: profile)
            return
        }
        state = .checking
        do {
            try await connectionClient.connect(
                pending.connection,
                timeoutMilliseconds: 15_000
            )
            let profile: GatewayProfile
            if let saved = pending.profile {
                try await profileStore.selectGateway(id: saved.id)
                profile = saved
            } else {
                profile = try await profileStore.save(
                    connection: pending.connection,
                    name: pending.name
                )
            }
            let snapshot = try await profileStore.load()
            savedGateways = snapshot.profiles
            activeGatewayID = profile.id
            connectedProfile = profile
            pendingSignIn = nil
            legacyToken = ""
            state = .connected
            reconnectPhaseHandler?(.online)
            isSettingsVisible = false
        } catch {
            await connectionClient.close()
            if presentSignIn(for: error, pending: pending) {
                return
            }
            pendingSignIn = nil
            connectedProfile = nil
            state = .failed(Self.connectionMessage(for: error))
            isSettingsVisible = true
        }
    }

    func cancelGatewaySignIn() async {
        reconnectCoordinator.cancel()
        await connectionClient.close()
        pendingSignIn = nil
        gatewaySignInURL = nil
        signInFixtureHTML = nil
        connectedProfile = nil
        state = savedGateways.isEmpty ? .idle : .failed(
            "Dashboard sign-in was cancelled."
        )
        isSettingsVisible = true
    }

    func handleConnectionLoss(_ notice: GatewayConnectionLossNotice) {
        guard let profile = connectedProfile else {
            state = .failed(notice.message)
            isSettingsVisible = true
            return
        }
        operationError = nil
        resetHermesVoice()
        guard notice.retryable else {
            reconnectCoordinator.cancel()
            state = .failed(notice.message)
            reconnectPhaseHandler?(.failed)
            isSettingsVisible = true
            return
        }
        state = .reconnecting
        reconnectPhaseHandler?(.reconnecting)
        isSettingsVisible = false
        scheduleReconnect(for: profile)
    }

    func onAppForeground() {
        guard let profile = connectedProfile,
              state == .offline || state == .reconnecting
        else {
            return
        }
        restartReconnect(for: profile)
    }

    func scheduleReconnect(for profile: GatewayProfile) {
        reconnectCoordinator.schedule(
            onPhase: { [weak self] phase in
                self?.applyReconnectPhase(phase, profileID: profile.id)
            },
            attempt: { [weak self] in
                guard let self else {
                    return .stop
                }
                return await self.attemptReconnect(profile)
            }
        )
    }

    private func restartReconnect(for profile: GatewayProfile) {
        reconnectCoordinator.restart(
            onPhase: { [weak self] phase in
                self?.applyReconnectPhase(phase, profileID: profile.id)
            },
            attempt: { [weak self] in
                guard let self else {
                    return .stop
                }
                return await self.attemptReconnect(profile)
            }
        )
    }

    private func applyReconnectPhase(
        _ phase: GatewayReconnectLoopPhase,
        profileID: String
    ) {
        guard connectedProfile?.id == profileID,
              gatewaySignInURL == nil,
              !isSettingsVisible
        else {
            return
        }
        switch phase {
        case .waitingForNetwork:
            state = .offline
            reconnectPhaseHandler?(.offline)
        case .attempting, .backingOff:
            state = .reconnecting
            reconnectPhaseHandler?(.reconnecting)
        }
    }

    private func attemptReconnect(
        _ profile: GatewayProfile
    ) async -> GatewayReconnectDirective {
        guard connectedProfile?.id == profile.id,
              !isSettingsVisible,
              gatewaySignInURL == nil
        else {
            return .stop
        }
        do {
            try await connectionClient.connect(
                profile.connection,
                timeoutMilliseconds: 15_000
            )
            guard connectedProfile?.id == profile.id,
                  !isSettingsVisible,
                  gatewaySignInURL == nil
            else {
                await connectionClient.close()
                return .stop
            }
            state = .restoring
            reconnectPhaseHandler?(.restoring)
            let restored = await reconnectRestorer?(profile) ?? true
            guard connectedProfile?.id == profile.id,
                  !isSettingsVisible,
                  gatewaySignInURL == nil
            else {
                await connectionClient.close()
                return .stop
            }
            guard restored else {
                await connectionClient.close()
                state = .reconnecting
                reconnectPhaseHandler?(.reconnecting)
                return .retry
            }
            try await profileStore.selectGateway(id: profile.id)
            activeGatewayID = profile.id
            state = .connected
            reconnectPhaseHandler?(.online)
            operationError = nil
            return .stop
        } catch {
            await connectionClient.close()
            let pending = PendingSignIn(
                connection: profile.connection,
                name: profile.name,
                profile: profile
            )
            if presentSignIn(for: error, pending: pending) {
                return .stop
            }
            guard connectedProfile?.id == profile.id else {
                return .stop
            }
            if Self.isRetryableConnectionFailure(error) {
                state = .reconnecting
                reconnectPhaseHandler?(.reconnecting)
                return .retry
            }
            state = .failed(Self.connectionMessage(for: error))
            reconnectPhaseHandler?(.failed)
            isSettingsVisible = true
            return .stop
        }
    }

    func handleAuthenticationExpiry(
        _ event: GatewayAuthenticationEvent
    ) async {
        guard let profile = connectedProfile,
              profile.id == event.profileID,
              gatewaySignInURL == nil
        else {
            return
        }
        reconnectCoordinator.cancel()
        resetHermesVoice()
        pendingSignIn = PendingSignIn(
            connection: profile.connection,
            name: profile.name,
            profile: profile
        )
        gatewaySignInURL = event.loginURL
        signInFixtureHTML = nil
        state = .reconnecting
        reconnectPhaseHandler?(.reconnecting)
        isSettingsVisible = false
        await connectionClient.close()
    }

    @discardableResult
    func presentSignIn(
        for error: any Error,
        pending: PendingSignIn
    ) -> Bool {
        guard let signIn = error as? GatewaySignInRequiredError else {
            return false
        }
        pendingSignIn = pending
        gatewaySignInURL = signIn.loginURL
        connectedProfile = pending.profile
        state = pending.profile == nil ? .idle : .reconnecting
        isSettingsVisible = false
        return true
    }

    static func isRetryableConnectionFailure(
        _ error: any Error
    ) -> Bool {
        if let hermes = error as? HermesError {
            return hermes.isConnectionFailure && hermes.retryable
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        if let probe = error as? GatewayProbeError {
            guard case let .httpStatus(status) = probe else {
                return false
            }
            return status == 408 || status == 429 || status >= 500
        }
        return false
    }

    static func connectionMessage(for error: any Error) -> String {
        if let conflict = error as? GatewayCookieScopeConflictError {
            return conflict.localizedDescription
        }
        if let tokenError = error as? GatewayTokenRequiredError {
            return tokenError.localizedDescription
        }
        if let hermesError = error as? HermesError {
            return hermesError.localizedDescription
        }
        return GatewayProbePresentation.message(for: error)
    }
}
