import Foundation

/// Shared default-port-aware origin comparison for gateway security policy.
enum GatewayURLOriginPolicy {
    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = URLComponents(
            url: lhs,
            resolvingAgainstBaseURL: false
        ), let right = URLComponents(
            url: rhs,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
    }

    static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        switch components.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }
}
