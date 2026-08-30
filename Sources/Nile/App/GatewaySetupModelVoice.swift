import Foundation

/// Model-facing Hermes voice-settings presentation.
///
/// `HermesVoiceCoordinator` retains request cancellation and generation
/// fencing; this extension owns only the gateway-settings UI projection.
@MainActor
extension GatewaySetupModel {
    func setHermesVoiceSheetVisible(_ visible: Bool) {
        if !visible {
            guard !isUpdatingHermesVoice else {
                return
            }
            hermesVoice.invalidate()
            isHermesVoiceSheetVisible = false
            isLoadingHermesVoice = false
            isUpdatingHermesVoice = false
            hermesVoiceError = nil
            return
        }
        guard isConnected,
              isSettingsVisible,
              state == .connected,
              connectedProfile != nil,
              !isChecking,
              !isUpdatingHermesVoice
        else {
            return
        }
        isHermesVoiceSheetVisible = true
        isLoadingHermesVoice = true
        isUpdatingHermesVoice = false
        hermesVoiceError = nil
        operationError = nil
        loadHermesVoice(clearExisting: false)
    }

    func refreshHermesVoice() {
        guard isConnected,
              isSettingsVisible,
              isHermesVoiceSheetVisible,
              !isUpdatingHermesVoice
        else {
            return
        }
        loadHermesVoice(clearExisting: false)
    }

    func applyHermesVoice(
        expectedProvider: String,
        voice: String
    ) {
        guard let current = hermesVoiceConfig else {
            return
        }
        let normalizedVoice = voice.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard isConnected,
              isSettingsVisible,
              isHermesVoiceSheetVisible,
              !isLoadingHermesVoice,
              !isUpdatingHermesVoice,
              current.provider == expectedProvider,
              connectedProfile != nil
        else {
            return
        }
        guard normalizedVoice.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            hermesVoiceError =
                "Voice IDs may use letters, numbers, periods, underscores, and hyphens."
            return
        }
        guard normalizedVoice != current.voice else {
            return
        }
        hermesVoice.update(
            gatewayID: connectedProfile?.id ?? activeGatewayID,
            expectedProvider: expectedProvider,
            voice: normalizedVoice,
            onStarted: { [weak self] in
                self?.isUpdatingHermesVoice = true
                self?.hermesVoiceError = nil
            },
            onResult: { [weak self] result in
                self?.applyHermesVoiceResult(result)
            }
        )
    }

    private func loadHermesVoice(clearExisting: Bool) {
        hermesVoice.load(
            gatewayID: connectedProfile?.id ?? activeGatewayID,
            onStarted: { [weak self] in
                guard let self else {
                    return
                }
                if clearExisting {
                    hermesVoiceConfig = nil
                }
                isLoadingHermesVoice = true
                hermesVoiceError = nil
            },
            onResult: { [weak self] result in
                self?.applyHermesVoiceResult(result)
            }
        )
    }

    private func applyHermesVoiceResult(_ result: HermesVoiceResult) {
        guard hermesVoice.isCurrent(result.request),
              isConnected,
              isSettingsVisible,
              isHermesVoiceSheetVisible,
              activeGatewayID == result.request.gatewayID
        else {
            return
        }
        switch result {
        case let .success(_, config):
            hermesVoiceConfig = config
            isLoadingHermesVoice = false
            isUpdatingHermesVoice = false
            hermesVoiceError = nil
        case let .failure(_, error):
            isLoadingHermesVoice = false
            isUpdatingHermesVoice = false
            hermesVoiceError = Self.hermesVoiceMessage(for: error)
        }
    }

    func resetHermesVoice() {
        hermesVoice.invalidate()
        isHermesVoiceSheetVisible = false
        hermesVoiceConfig = nil
        isLoadingHermesVoice = false
        isUpdatingHermesVoice = false
        hermesVoiceError = nil
    }

    private static func hermesVoiceMessage(for error: any Error) -> String {
        let message: String
        if let hermesError = error as? HermesError {
            message = hermesError.localizedDescription
        } else {
            message = error.localizedDescription
        }
        if message.contains("HTTP 404") {
            return "This gateway does not expose app-managed Hermes voice settings."
        }
        return message.replacingOccurrences(
            of: #"^Could not (?:read|write) dashboard data \(HTTP \d+\):\s*"#,
            with: "",
            options: .regularExpression
        )
    }
}
