import Foundation

@MainActor
final class UserDefaultsBiometricAppLockStore: BiometricAppLockStoring {
    private static let enabledKey =
        "security.biometric_app_lock.enabled.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled() -> Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
    }
}
