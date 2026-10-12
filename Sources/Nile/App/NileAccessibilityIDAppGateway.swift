import Foundation

extension NileAccessibilityID {
    static let reducedMotionFixture =
        "niles.accessibility.reduced_motion"
    static let settings = "niles.settings"
    static let settingsDone = "niles.settings.done"
    static let gatewayManagement = "niles.gateway.management"
    static let gatewayList = "niles.gateway.list"
    static let gatewayActions = "niles.gateway.actions"
    static let addGateway = "niles.gateway.add"
    static let gatewayName = "niles.gateway.name"
    static let gatewayURL = "niles.gateway.url"
    static let gatewayToken = "niles.gateway.token"
    static let approveCleartext = "niles.gateway.approve_cleartext"
    static let gatewayCleartextWarning = "niles.gateway.cleartext_warning"
    static let connectGateway = "niles.gateway.connect"
    static let gatewayError = "niles.gateway.error"
    static let gatewayStatus = "niles.gateway.status"
    static let gatewaySignIn = "niles.gateway.sign_in"
    static let gatewaySignInWebView = "niles.gateway.sign_in.web"
    static let gatewaySignInError = "niles.gateway.sign_in.error"
    static let gatewaySignInCancel = "niles.gateway.sign_in.cancel"
    static let gatewaySignInRetry = "niles.gateway.sign_in.retry"
    static let gatewaySignInContinue = "niles.gateway.sign_in.continue"
    static let gatewaySignInApproveExternal =
        "niles.gateway.sign_in.approve_external"
    static let notificationEducation = "niles.notifications.education"
    static let notificationEducationEnable =
        "niles.notifications.education.enable"
    static let notificationEducationDismiss =
        "niles.notifications.education.dismiss"
    static let biometricLock = "niles.security.biometric_lock"
    static let biometricLockToggle =
        "niles.security.biometric_lock.toggle"
    static let biometricLockError =
        "niles.security.biometric_lock.error"
    static let biometricLockUnlock =
        "niles.security.biometric_lock.unlock"
    static let removeGateway = "niles.gateway.remove"
    static let cancelRemoveGateway = "niles.gateway.remove.cancel"
    static let confirmRemoveGateway = "niles.gateway.remove.confirm"
    static let gatewaySwitchDialog =
        "niles.gateway.switch.confirmation"
    static let dismissGatewaySwitch = "niles.gateway.switch.dismiss"
    static let confirmGatewaySwitch = "niles.gateway.switch.confirm"
    static let hermesVoiceEntry = "niles.voice.entry"
    static let hermesVoiceSheet = "niles.voice.sheet"
    static let hermesVoiceDragHandle = "niles.voice.drag_handle"
    static let hermesVoiceContent = "niles.voice.content"
    static let hermesVoiceProvider = "niles.voice.provider"
    static let hermesVoiceCurrent = "niles.voice.current"
    static let hermesVoiceInput = "niles.voice.input"
    static let hermesVoicePresets = "niles.voice.presets"
    static let hermesVoiceLoading = "niles.voice.loading"
    static let hermesVoiceError = "niles.voice.error"
    static let hermesVoiceRetry = "niles.voice.retry"
    static let hermesVoiceApply = "niles.voice.apply"
    static let hermesVoiceGlobalWarning = "niles.voice.global_warning"

    static func hermesVoicePreset(
        provider: String,
        voice: String
    ) -> String {
        "niles.voice.preset.\(stableVoiceKey("\(provider)/\(voice)"))"
    }

    private static func stableVoiceKey(_ value: String) -> String {
        let sanitized = String(
            value.map { character in
                if character == "-" || character == "_" {
                    return character
                }
                return character.unicodeScalars.allSatisfy(
                    CharacterSet.alphanumerics.contains
                ) ? character : "_"
            }
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        .prefix(48)
        var hash: Int32 = 0
        for unit in value.utf16 {
            hash = hash &* 31 &+ Int32(unit)
        }
        return "\(sanitized.isEmpty ? "unknown" : String(sanitized))-\(String(UInt32(bitPattern: hash), radix: 16))"
    }
}
