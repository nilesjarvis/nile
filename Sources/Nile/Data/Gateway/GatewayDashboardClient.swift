import Foundation

/// Bounded dashboard JSON transport.
///
/// Attachment downloading is implemented by a dedicated transport extension;
/// response classification and login admission are transport-free policy.
struct GatewayDashboardClient: GatewayDashboardReading, Sendable {
    let transport: any GatewayHTTPTransport

    init(transport: any GatewayHTTPTransport = URLSessionGatewayHTTPTransport()) {
        self.transport = transport
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String]
    ) async throws -> JSONValue.Object {
        try await getJSON(
            connection: connection,
            pathSegments: pathSegments,
            query: [:]
        )
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String],
        query: [String: String]
    ) async throws -> JSONValue.Object {
        try await jsonRequest(
            connection: connection,
            method: "GET",
            pathSegments: pathSegments,
            query: query,
            body: nil,
            maximumBytes: GatewayResponseLimits.dashboardJSON,
            includeErrorDetail: false
        )
    }

    func getJSONWithErrorDetail(
        connection: GatewayConnection,
        pathSegments: [String],
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        try await jsonRequest(
            connection: connection,
            method: "GET",
            pathSegments: pathSegments,
            body: nil,
            maximumBytes: maximumBytes,
            includeErrorDetail: true
        )
    }

    func sendJSON(
        connection: GatewayConnection,
        method: String,
        pathSegments: [String],
        body: JSONValue.Object,
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        let normalizedMethod = method.uppercased()
        guard ["POST", "PUT"].contains(normalizedMethod) else {
            throw HermesError(
                "Dashboard JSON method is not supported",
                retryable: false
            )
        }
        return try await jsonRequest(
            connection: connection,
            method: normalizedMethod,
            pathSegments: pathSegments,
            body: body,
            maximumBytes: maximumBytes,
            includeErrorDetail: true
        )
    }

    private func jsonRequest(
        connection: GatewayConnection,
        method: String,
        pathSegments: [String],
        query: [String: String] = [:],
        body: JSONValue.Object?,
        maximumBytes: Int64,
        includeErrorDetail: Bool
    ) async throws -> JSONValue.Object {
        guard maximumBytes > 0 else {
            throw HermesError(
                "Dashboard response limit must be positive",
                retryable: false
            )
        }
        let baseURL = try connection.endpoint.apiURL(
            pathSegments: ["api"] + pathSegments
        )
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw HermesError(
                "Could not build the dashboard request",
                retryable: false
            )
        }
        components.queryItems = query.isEmpty
            ? nil
            : query.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        guard let url = components.url else {
            throw HermesError(
                "Could not build the dashboard request",
                retryable: false
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let body {
            do {
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: body.mapValues(\.foundationValue),
                    options: [.sortedKeys]
                )
            } catch {
                throw HermesError(
                    "Dashboard request body is invalid",
                    retryable: false
                )
            }
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        if !connection.token.isBlank {
            request.setValue(
                connection.token,
                forHTTPHeaderField: "X-Hermes-Session-Token"
            )
        }

        let bounded = try await transport.data(
            for: request,
            maximumBytes: maximumBytes
        )
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
        let operation = method == "GET" ? "read" : "write"
        guard (200...299).contains(response.statusCode) else {
            let detail = includeErrorDetail
                ? GatewayDashboardResponsePolicy.errorDetail(response.data)
                : nil
            throw HermesError(
                "Could not \(operation) dashboard data (HTTP \(response.statusCode))"
                    + (detail.map { ": \($0)" } ?? ""),
                retryable: GatewayDashboardResponsePolicy
                    .isRetryableHTTPStatus(response.statusCode)
            )
        }
        guard !bounded.tooLarge else {
            throw HermesError(
                "Gateway returned too much dashboard data",
                retryable: false
            )
        }
        do {
            let raw = try JSONSerialization.jsonObject(with: response.data)
            guard let object = try JSONValue(any: raw).objectValue else {
                throw GatewayDashboardDecodeError.invalidTopLevel
            }
            return object
        } catch {
            throw HermesError(
                "Gateway returned invalid dashboard data",
                retryable: false
            )
        }
    }

}

private enum GatewayDashboardDecodeError: Error {
    case invalidTopLevel
}
