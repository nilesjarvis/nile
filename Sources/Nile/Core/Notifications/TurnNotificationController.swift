import Foundation
import UIKit
import UserNotifications

@MainActor
protocol BackgroundExecutionOperating: AnyObject {
    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class UIApplicationBackgroundExecution:
    BackgroundExecutionOperating
{
    func begin(
        name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(
            withName: name,
            expirationHandler: expiration
        )
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
protocol TurnNotificationScheduling: AnyObject {
    func scheduleCompletion(for target: BackgroundTurnTarget)
}

@MainActor
final class SystemTurnNotificationScheduler: TurnNotificationScheduling {
    static let categoryIdentifier = "nile.turn.result"
    static let title = "Turn finished"
    static let body = "Open Nile to view the result"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleCompletion(for target: BackgroundTurnTarget) {
        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = Self.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = TurnNotificationRoute(
            gatewayID: target.gatewayID,
            storedSessionID: target.storedSessionID
        ).userInfo
        center.add(
            UNNotificationRequest(
                identifier: "nile.turn.result.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }
}

struct BackgroundExecutionUnavailableError: LocalizedError, Sendable {
    var errorDescription: String? {
        "iOS did not grant background execution time."
    }
}

@MainActor
final class IOSTurnBackgroundController: TurnBackgroundControlling {
    private let execution: any BackgroundExecutionOperating
    private let notifications: any TurnNotificationScheduling
    private var activeTarget: BackgroundTurnTarget?
    private var activeIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var appIsForeground = false
    private var expirationHandler: (
        @MainActor @Sendable (BackgroundTurnTarget) -> Void
    )?

    init(
        execution: any BackgroundExecutionOperating =
            UIApplicationBackgroundExecution(),
        notifications: any TurnNotificationScheduling =
            SystemTurnNotificationScheduler()
    ) {
        self.execution = execution
        self.notifications = notifications
    }

    func installExpirationHandler(
        _ handler: @escaping @MainActor @Sendable
            (BackgroundTurnTarget) -> Void
    ) {
        expirationHandler = handler
    }

    func onAppForegroundChanged(_ isForeground: Bool) {
        appIsForeground = isForeground
    }

    func turnStarted(_ target: BackgroundTurnTarget) throws {
        if activeTarget == target {
            return
        }
        guard activeTarget == nil else {
            throw BackgroundExecutionUnavailableError()
        }
        let identifier = execution.begin(
            name: "Nile agent turn"
        ) { [weak self] in
            self?.expire(target)
        }
        guard identifier != .invalid else {
            throw BackgroundExecutionUnavailableError()
        }
        activeTarget = target
        activeIdentifier = identifier
    }

    func turnCompleted(_ target: BackgroundTurnTarget) {
        finishExecution(for: target)
        if !appIsForeground {
            notifications.scheduleCompletion(for: target)
        }
    }

    func turnStopped(_ target: BackgroundTurnTarget) {
        finishExecution(for: target)
    }

    private func expire(_ target: BackgroundTurnTarget) {
        guard activeTarget == target else {
            return
        }
        finishExecution(for: target)
        expirationHandler?(target)
    }

    private func finishExecution(for target: BackgroundTurnTarget) {
        guard activeTarget == target,
              activeIdentifier != .invalid else {
            return
        }
        let identifier = activeIdentifier
        activeTarget = nil
        activeIdentifier = .invalid
        execution.end(identifier)
    }
}
