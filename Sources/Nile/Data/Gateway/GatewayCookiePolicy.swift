import Foundation

enum GatewayCookiePolicy {
    static func scopesOverlap(
        _ first: GatewayEndpoint,
        _ second: GatewayEndpoint
    ) -> Bool {
        guard let firstComponents = URLComponents(string: first.baseURL),
              let secondComponents = URLComponents(string: second.baseURL),
              firstComponents.host?.caseInsensitiveCompare(
                  secondComponents.host ?? ""
              ) == .orderedSame
        else {
            return false
        }
        let firstPath = normalizedPath(firstComponents.percentEncodedPath)
        let secondPath = normalizedPath(secondComponents.percentEncodedPath)
        return firstPath == "/"
            || secondPath == "/"
            || firstPath == secondPath
            || firstPath.hasPrefix(secondPath + "/")
            || secondPath.hasPrefix(firstPath + "/")
    }

    static func contains(_ url: URL, in endpoint: GatewayEndpoint) -> Bool {
        guard let endpointComponents = URLComponents(
            string: endpoint.baseURL
        ) else {
            return false
        }
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), components.user == nil, components.password == nil,
           components.scheme?.lowercased()
            == endpointComponents.scheme?.lowercased(),
           components.host?.lowercased()
            == endpointComponents.host?.lowercased(),
           effectivePort(components) == effectivePort(endpointComponents)
        else {
            return false
        }
        let prefix = normalizedPath(endpointComponents.percentEncodedPath)
        let path = normalizedPath(components.percentEncodedPath)
        return prefix == "/"
            || path == prefix
            || path.hasPrefix(prefix + "/")
    }

    static func header(
        from cookies: [HTTPCookie],
        for url: URL,
        now: Date = Date()
    ) -> String? {
        let eligible = cookies
            .filter { matches($0, url: url, now: now) }
            .filter { nameAllowed($0.name, for: url) }
        return nonBlank(
            HTTPCookie.requestHeaderFields(with: eligible)["Cookie"]
        )
    }

    static func cookiesToClear(
        from cookies: [HTTPCookie],
        for endpoint: GatewayEndpoint,
        includeHostWideCookies: Bool
    ) throws -> [HTTPCookie] {
        let baseURL = try endpoint.apiURL(pathSegments: [])
        let host = baseURL.host?.lowercased()
        let prefix = normalizedPath(baseURL.path)
        let paths: Set<String> = if prefix == "/" {
            ["/"]
        } else if includeHostWideCookies {
            ["/", prefix, prefix + "/"]
        } else {
            [prefix, prefix + "/"]
        }
        return cookies.filter { cookie in
            sessionCookieNames.contains(cookie.name)
                && domainMatches(cookie.domain, host: host)
                && paths.contains(normalizedPath(cookie.path))
                && (
                    includeHostWideCookies
                        || !cookie.name.hasPrefix("__Host-")
                )
        }
    }

    static func nonBlank(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return value.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? nil : value
    }

    private static let sessionCookieNames: Set<String> = [
        "hermes_session_at",
        "hermes_session_rt",
        "__Host-hermes_session_at",
        "__Host-hermes_session_rt",
        "__Secure-hermes_session_at",
        "__Secure-hermes_session_rt",
    ]

    private static let bareCookieNames: Set<String> = [
        "hermes_session_at",
        "hermes_session_rt",
    ]

    private static let hostCookieNames: Set<String> = [
        "__Host-hermes_session_at",
        "__Host-hermes_session_rt",
    ]

    private static let secureCookieNames: Set<String> = [
        "__Secure-hermes_session_at",
        "__Secure-hermes_session_rt",
    ]

    private static func nameAllowed(_ name: String, for url: URL) -> Bool {
        let path = normalizedPath(url.path)
        let suffixes = ["/api/auth/ws-ticket", "/auth/logout"]
        guard let suffix = suffixes.first(where: { path.hasSuffix($0) }) else {
            return true
        }
        let basePath = normalizedPath(
            String(path.dropLast(suffix.count))
        )
        if url.scheme?.lowercased() != "https" {
            return bareCookieNames.contains(name)
        }
        if basePath == "/" {
            return bareCookieNames.contains(name)
                || hostCookieNames.contains(name)
        }
        return bareCookieNames.contains(name)
            || secureCookieNames.contains(name)
    }

    private static func matches(
        _ cookie: HTTPCookie,
        url: URL,
        now: Date
    ) -> Bool {
        guard let host = url.host?.lowercased(),
              domainMatches(cookie.domain, host: host),
              !(cookie.isSecure && url.scheme?.lowercased() != "https"),
              cookie.expiresDate.map({ $0 > now }) ?? true
        else {
            return false
        }
        let cookiePath = normalizedPath(cookie.path)
        let requestPath = normalizedPath(url.path)
        return cookiePath == "/"
            || requestPath == cookiePath
            || requestPath.hasPrefix(
                cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/"
            )
    }

    private static func domainMatches(
        _ cookieDomain: String,
        host: String?
    ) -> Bool {
        guard let host else {
            return false
        }
        let domain = cookieDomain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    private static func normalizedPath(_ path: String) -> String {
        let normalized = path.isEmpty ? "/" : path
        if normalized == "/" {
            return normalized
        }
        return normalized.hasSuffix("/")
            ? String(normalized.dropLast())
            : normalized
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        components.port
            ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
