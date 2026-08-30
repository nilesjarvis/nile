import Foundation

/// Transport-free HTTP classification and profile-scoped login admission.
enum GatewayDashboardResponsePolicy {
    static func isRetryableHTTPStatus(_ status: Int) -> Bool {
        status >= 500 || status == 408 || status == 425 || status == 429
    }

    static func errorDetail(_ data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any] else {
            return nil
        }
        for key in ["detail", "error"] {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func safeLoginURL(
        connection: GatewayConnection,
        responseData: Data
    ) throws -> URL {
        let fallback = try connection.endpoint.apiURL(pathSegments: ["login"])
        guard
            let raw = try? JSONSerialization.jsonObject(with: responseData),
            let object = raw as? [String: Any],
            let advertised = object["login_url"] as? String,
            !advertised.isBlank,
            let prefixRoot = URL(string: connection.baseURL + "/"),
            let candidate = URL(
                string: advertised,
                relativeTo: prefixRoot
            )?.absoluteURL,
            isSafeLoginCandidate(candidate, fallback: fallback)
        else {
            return fallback
        }
        return canonicalizeDefaultPort(candidate)
    }

    private static func isSafeLoginCandidate(
        _ candidate: URL,
        fallback: URL
    ) -> Bool {
        guard
            let candidateComponents = URLComponents(
                url: candidate,
                resolvingAgainstBaseURL: false
            ),
            let fallbackComponents = URLComponents(
                url: fallback,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }
        return GatewayURLOriginPolicy.sameOrigin(candidate, fallback)
            && candidateComponents.user == nil
            && candidateComponents.password == nil
            && candidateComponents.percentEncodedPath
                == fallbackComponents.percentEncodedPath
            && candidateComponents.fragment == nil
    }

    private static func canonicalizeDefaultPort(_ url: URL) -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        if (components.scheme?.lowercased() == "https" && components.port == 443)
            || (components.scheme?.lowercased() == "http" && components.port == 80) {
            components.port = nil
        }
        return components.url ?? url
    }
}
