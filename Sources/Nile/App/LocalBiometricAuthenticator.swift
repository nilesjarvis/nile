import Foundation
import LocalAuthentication

@MainActor
final class LocalBiometricAuthenticator: BiometricAuthenticating {
    func capability() -> NileBiometricCapability {
        let context = LAContext()
        var error: NSError?
        let isAvailable = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        let kind = Self.kind(for: context.biometryType)
        guard isAvailable else {
            return .unavailable(
                kind,
                message: Self.unavailableMessage(for: error)
            )
        }
        return .available(kind)
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            throw Self.authenticationFailure(for: error)
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            throw Self.authenticationFailure(for: error as NSError)
        }
    }

    private static func kind(
        for biometryType: LABiometryType
    ) -> NileBiometryKind {
        switch biometryType {
        case .faceID:
            .faceID
        case .touchID:
            .touchID
        case .opticID:
            .biometrics
        case .none:
            .biometrics
        @unknown default:
            .biometrics
        }
    }

    private static func unavailableMessage(
        for error: NSError?
    ) -> String {
        switch errorCode(for: error) {
        case .biometryNotEnrolled:
            return "Set up Face ID or Touch ID in iOS Settings to enable app lock."
        case .biometryLockout:
            return "Biometrics are locked. Unlock your iPhone with its "
                + "passcode, then try again."
        default:
            return "Face ID or Touch ID is not available on this device."
        }
    }

    private static func authenticationFailure(
        for error: NSError?
    ) -> NileBiometricAuthenticationFailure {
        switch errorCode(for: error) {
        case .userCancel, .appCancel, .systemCancel:
            .canceled
        case .biometryLockout:
            .lockedOut
        case .biometryNotEnrolled:
            .notEnrolled
        default:
            .failed
        }
    }

    private static func errorCode(
        for error: NSError?
    ) -> LAError.Code? {
        guard error?.domain == LAError.errorDomain else {
            return nil
        }
        return error.flatMap { LAError.Code(rawValue: $0.code) }
    }
}
