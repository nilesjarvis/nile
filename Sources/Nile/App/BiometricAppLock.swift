import Foundation
import Observation

@MainActor
@Observable
final class BiometricAppLockModel {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var showsPrivacyShield: Bool
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    private(set) var capability: NileBiometricCapability

    private let store: any BiometricAppLockStoring
    private let authenticator: any BiometricAuthenticating
    @ObservationIgnored private var backgroundGeneration = 0

    init(
        store: any BiometricAppLockStoring =
            UserDefaultsBiometricAppLockStore(),
        authenticator: any BiometricAuthenticating =
            LocalBiometricAuthenticator()
    ) {
        self.store = store
        self.authenticator = authenticator
        capability = authenticator.capability()
        let storedEnabled = store.isEnabled()
        isEnabled = storedEnabled
        isLocked = storedEnabled
        showsPrivacyShield = storedEnabled
    }

    var biometryName: String {
        capability.kind.displayName
    }

    var canEnable: Bool {
        capability.isAvailable
    }

    func refreshCapability() {
        capability = authenticator.capability()
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, !isAuthenticating else {
            return
        }
        errorMessage = nil
        if !enabled {
            store.setEnabled(false)
            isEnabled = false
            isLocked = false
            showsPrivacyShield = false
            return
        }

        refreshCapability()
        guard capability.isAvailable else {
            errorMessage = capability.unavailableMessage
            return
        }
        isAuthenticating = true
        let authenticationBackgroundGeneration = backgroundGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.authenticate(
                reason: "Use \(biometryName) to protect Nile when you open the app."
            ) else {
                errorMessage =
                    "Authentication was not completed. App lock remains off."
                return
            }
            store.setEnabled(true)
            isEnabled = true
            if backgroundGeneration != authenticationBackgroundGeneration {
                isLocked = true
                showsPrivacyShield = true
            } else {
                isLocked = false
                showsPrivacyShield = false
            }
        } catch {
            errorMessage = Self.authenticationMessage(
                for: error,
                locked: false
            )
        }
    }

    func appDidBecomeInactive() {
        guard isEnabled else {
            return
        }
        showsPrivacyShield = true
    }

    func appDidEnterBackground() {
        backgroundGeneration &+= 1
        guard isEnabled else {
            return
        }
        isLocked = true
        showsPrivacyShield = true
        errorMessage = nil
    }

    func appDidBecomeActive() async {
        guard isEnabled else {
            showsPrivacyShield = false
            return
        }
        guard isLocked else {
            showsPrivacyShield = false
            return
        }
        await unlock()
    }

    func unlock() async {
        guard isEnabled, isLocked, !isAuthenticating else {
            return
        }
        refreshCapability()
        guard capability.isAvailable else {
            errorMessage = capability.unavailableMessage
            showsPrivacyShield = true
            return
        }
        errorMessage = nil
        isAuthenticating = true
        let authenticationBackgroundGeneration = backgroundGeneration
        defer { isAuthenticating = false }
        do {
            guard try await authenticator.authenticate(
                reason: "Unlock Nile with \(biometryName)."
            ) else {
                errorMessage =
                    "Authentication was not completed. Nile remains locked."
                showsPrivacyShield = true
                return
            }
            guard backgroundGeneration
                == authenticationBackgroundGeneration
            else {
                isLocked = true
                showsPrivacyShield = true
                return
            }
            isLocked = false
            // Local Authentication temporarily makes the scene inactive while
            // its system UI is presented. Waiting for scene activation here
            // leaves the privacy shield visible after Face ID has succeeded.
            // A real trip to the background changes the generation above and
            // remains fail-closed, so reveal immediately after verified auth.
            showsPrivacyShield = false
        } catch {
            errorMessage = Self.authenticationMessage(
                for: error,
                locked: true
            )
            showsPrivacyShield = true
        }
    }

    private static func authenticationMessage(
        for error: any Error,
        locked: Bool
    ) -> String {
        let suffix = locked
            ? "Nile remains locked."
            : "App lock remains off."
        guard let failure = error as? NileBiometricAuthenticationFailure else {
            return "Authentication failed. \(suffix)"
        }
        switch failure {
        case .canceled:
            return "Authentication was canceled. \(suffix)"
        case .lockedOut:
            return "Biometrics are locked. Unlock your iPhone with its "
                + "passcode, then try again."
        case .notEnrolled:
            return "Set up Face ID or Touch ID in iOS Settings, then try again."
        case .failed:
            return "Authentication failed. \(suffix)"
        }
    }
}
