import Foundation

enum NileBiometryKind: Equatable, Sendable {
    case faceID
    case touchID
    case biometrics

    var displayName: String {
        switch self {
        case .faceID:
            "Face ID"
        case .touchID:
            "Touch ID"
        case .biometrics:
            "biometrics"
        }
    }
}

struct NileBiometricCapability: Equatable, Sendable {
    let kind: NileBiometryKind
    let isAvailable: Bool
    let unavailableMessage: String?

    static func available(
        _ kind: NileBiometryKind
    ) -> NileBiometricCapability {
        NileBiometricCapability(
            kind: kind,
            isAvailable: true,
            unavailableMessage: nil
        )
    }

    static func unavailable(
        _ kind: NileBiometryKind = .biometrics,
        message: String
    ) -> NileBiometricCapability {
        NileBiometricCapability(
            kind: kind,
            isAvailable: false,
            unavailableMessage: message
        )
    }
}

enum NileBiometricAuthenticationFailure: Error, Equatable, Sendable {
    case canceled
    case lockedOut
    case notEnrolled
    case failed
}

@MainActor
protocol BiometricAppLockStoring: AnyObject {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool)
}

@MainActor
protocol BiometricAuthenticating: AnyObject {
    func capability() -> NileBiometricCapability
    func authenticate(reason: String) async throws -> Bool
}
