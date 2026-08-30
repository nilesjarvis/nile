import Foundation

/// Transport-free ticket/logout request and response contract.
enum GatewayAuthenticationHTTPPolicy {
    static let responseLimit = GatewayResponseLimits.controlJSON

    static func ticketURL(for connection: GatewayConnection) throws -> URL {
        try connection.endpoint.apiURL(
            pathSegments: ["api", "auth", "ws-ticket"]
        )
    }

    static func ticketRequest(
        url: URL,
        cookieHeader: String?
    ) -> URLRequest {
        controlPOSTRequest(
            url: url,
            cookieHeader: cookieHeader,
            timeoutInterval: 30
        )
    }

    static func logoutURL(for connection: GatewayConnection) -> URL? {
        try? connection.endpoint.apiURL(pathSegments: ["auth", "logout"])
    }

    static func controlPOSTRequest(
        url: URL,
        cookieHeader: String?,
        timeoutInterval: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    static func ticket(
        from bounded: GatewayBoundedHTTPResponse,
        connection: GatewayConnection
    ) throws -> String {
        let response = bounded.response
        if response.statusCode == 401 {
            throw GatewaySignInRequiredError(
                loginURL: try GatewayDashboardResponsePolicy.safeLoginURL(
                    connection: connection,
                    responseData: response.data
                ),
                message:
                    "Your Hermes dashboard session has expired or requires sign-in"
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw HermesError(
                "Could not mint a gateway connection ticket "
                    + "(HTTP \(response.statusCode))",
                retryable: GatewayDashboardResponsePolicy.isRetryableHTTPStatus(
                    response.statusCode
                ),
                isConnectionFailure: true
            )
        }
        guard !bounded.tooLarge else {
            throw HermesError(
                "Gateway returned an oversized connection ticket",
                retryable: false,
                isConnectionFailure: true
            )
        }
        guard let raw = try? JSONSerialization.jsonObject(with: response.data),
              let object = raw as? [String: Any],
              let ticket = GatewayCookiePolicy.nonBlank(
                  object["ticket"] as? String
              )
        else {
            throw HermesError(
                "Gateway returned an invalid connection ticket",
                retryable: false,
                isConnectionFailure: true
            )
        }
        return ticket
    }
}
