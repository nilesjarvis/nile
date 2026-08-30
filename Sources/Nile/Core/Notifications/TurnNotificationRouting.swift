import Foundation

struct TurnNotificationRoute: Equatable, Sendable {
    static let gatewayIDKey = "nile.gateway_id"
    static let storedSessionIDKey = "nile.stored_session_id"

    let gatewayID: String
    let storedSessionID: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let gatewayID = (userInfo[Self.gatewayIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !gatewayID.isEmpty
        else {
            return nil
        }
        let storedSessionID = (
            userInfo[Self.storedSessionIDKey] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gatewayID = gatewayID
        self.storedSessionID = storedSessionID?.isEmpty == false
            ? storedSessionID
            : nil
    }

    init(gatewayID: String, storedSessionID: String?) {
        self.gatewayID = gatewayID
        self.storedSessionID = storedSessionID
    }

    var userInfo: [String: String] {
        var result = [Self.gatewayIDKey: gatewayID]
        if let storedSessionID {
            result[Self.storedSessionIDKey] = storedSessionID
        }
        return result
    }
}

@MainActor
final class TurnNotificationRouteCenter {
    static let shared = TurnNotificationRouteCenter()

    private let continuation: AsyncStream<TurnNotificationRoute>.Continuation
    let routes: AsyncStream<TurnNotificationRoute>

    private init() {
        let channel = AsyncStream<TurnNotificationRoute>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        routes = channel.stream
        continuation = channel.continuation
    }

    func publish(userInfo: [AnyHashable: Any]) {
        guard let route = TurnNotificationRoute(userInfo: userInfo) else {
            return
        }
        publish(route)
    }

    func publish(_ route: TurnNotificationRoute) {
        continuation.yield(route)
    }
}
