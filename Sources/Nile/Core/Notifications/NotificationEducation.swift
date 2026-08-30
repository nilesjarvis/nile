import Foundation
import Observation
import UserNotifications

enum NileNotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol NotificationPermissionManaging: AnyObject {
    func authorizationStatus() async -> NileNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

@MainActor
final class SystemNotificationPermissionManager:
    NotificationPermissionManaging
{
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NileNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
}

protocol NotificationEducationStoring: Sendable {
    func isDismissed() -> Bool
    func dismiss()
}

final class UserDefaultsNotificationEducationStore:
    NotificationEducationStoring,
    @unchecked Sendable
{
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "notification_education_dismissed"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func isDismissed() -> Bool {
        defaults.bool(forKey: key)
    }

    func dismiss() {
        defaults.set(true, forKey: key)
    }
}

@MainActor
@Observable
final class NotificationEducationModel {
    private(set) var isVisible: Bool

    private let store: any NotificationEducationStoring
    private let permissions: any NotificationPermissionManaging
    private var presentationTask: Task<Void, Never>?

    init(
        store: any NotificationEducationStoring =
            UserDefaultsNotificationEducationStore(),
        permissions: any NotificationPermissionManaging =
            SystemNotificationPermissionManager(),
        initiallyVisible: Bool = false
    ) {
        self.store = store
        self.permissions = permissions
        isVisible = initiallyVisible
    }

    func considerPresentation() {
        guard !store.isDismissed() else {
            return
        }
        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            guard let self,
                  await permissions.authorizationStatus() == .notDetermined,
                  !Task.isCancelled,
                  !store.isDismissed()
            else {
                return
            }
            isVisible = true
        }
    }

    func enableNotifications() {
        isVisible = false
        presentationTask?.cancel()
        store.dismiss()
        Task { [permissions] in
            _ = try? await permissions.requestAuthorization()
        }
    }

    func dismiss() {
        isVisible = false
        presentationTask?.cancel()
        store.dismiss()
    }
}
