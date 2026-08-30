import Foundation

struct GatewayLoginNavigationPolicy: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case allow
        case approveExternal
        case block(String)
    }

    let gatewayLoginURL: URL

    func decision(
        for target: URL,
        approvedExternalOrigins: Set<String>
    ) -> Decision {
        guard let components = URLComponents(
            url: target,
            resolvingAgainstBaseURL: false
        ), components.user == nil, components.password == nil,
           let targetOrigin = gatewayOriginKey(target),
           let gatewayOrigin = gatewayOriginKey(gatewayLoginURL)
        else {
            return .block("Blocked an invalid sign-in navigation")
        }
        if gatewayURLIsWithinLoginPrefix(
            target,
            gatewayLoginURL: gatewayLoginURL
        ) {
            return .allow
        }
        if targetOrigin == gatewayOrigin {
            return .block(
                "Blocked navigation outside this gateway's configured path"
            )
        }
        guard components.scheme?.lowercased() == "https" else {
            return .block(
                "Blocked an unencrypted or unsupported external sign-in page"
            )
        }
        return approvedExternalOrigins.contains(targetOrigin)
            ? .allow
            : .approveExternal
    }
}

func gatewayOriginKey(_ url: URL) -> String? {
    guard let components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
    ), let scheme = components.scheme?.lowercased(),
       let host = components.host?.lowercased()
    else {
        return nil
    }
    let port = components.port ?? (scheme == "https" ? 443 : 80)
    return "\(scheme)://\(host):\(port)"
}

func gatewayDisplayOrigin(_ url: URL) -> String {
    guard let components = URLComponents(
        url: url,
        resolvingAgainstBaseURL: false
    ), let scheme = components.scheme?.lowercased(),
       let host = components.host
    else {
        return "unknown origin"
    }
    let port = components.port ?? (scheme == "https" ? 443 : 80)
    let defaultPort = (scheme == "https" && port == 443)
        || (scheme == "http" && port == 80)
    let printableHost = host.contains(":") ? "[\(host)]" : host
    return "\(scheme)://\(printableHost)"
        + (defaultPort ? "" : ":\(port)")
}

private func gatewayURLIsWithinLoginPrefix(
    _ target: URL,
    gatewayLoginURL: URL
) -> Bool {
    guard gatewayOriginKey(target) == gatewayOriginKey(gatewayLoginURL),
          let targetComponents = URLComponents(
              url: target,
              resolvingAgainstBaseURL: false
          ),
          targetComponents.user == nil,
          targetComponents.password == nil
    else {
        return false
    }
    let loginPath = gatewayLoginURL.path
    let withoutLogin = loginPath.hasSuffix("/login")
        ? String(loginPath.dropLast("/login".count))
        : loginPath
    let prefix = withoutLogin.isEmpty ? "/" : withoutLogin
    let path = target.path.isEmpty ? "/" : target.path
    return prefix == "/" || path == prefix || path.hasPrefix(prefix + "/")
}
