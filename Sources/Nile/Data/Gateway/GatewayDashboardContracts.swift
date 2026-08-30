import Foundation

protocol GatewayDashboardReading: Sendable {
    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String]
    ) async throws -> JSONValue.Object

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String],
        query: [String: String]
    ) async throws -> JSONValue.Object

    func download(
        connection: GatewayConnection,
        path: String,
        maximumBytes: Int64
    ) async throws -> DownloadedAttachment

    func getJSONWithErrorDetail(
        connection: GatewayConnection,
        pathSegments: [String],
        maximumBytes: Int64
    ) async throws -> JSONValue.Object

    func sendJSON(
        connection: GatewayConnection,
        method: String,
        pathSegments: [String],
        body: JSONValue.Object,
        maximumBytes: Int64
    ) async throws -> JSONValue.Object
}

extension GatewayDashboardReading {
    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String],
        query: [String: String]
    ) async throws -> JSONValue.Object {
        guard query.isEmpty else {
            throw HermesError(
                "Dashboard queries are unavailable for this gateway",
                retryable: false
            )
        }
        return try await getJSON(
            connection: connection,
            pathSegments: pathSegments
        )
    }

    func download(
        connection: GatewayConnection,
        path: String,
        maximumBytes: Int64
    ) async throws -> DownloadedAttachment {
        throw HermesError(
            "Attachment downloads are unavailable for this gateway",
            retryable: false
        )
    }

    func getJSONWithErrorDetail(
        connection: GatewayConnection,
        pathSegments: [String],
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        try await getJSON(
            connection: connection,
            pathSegments: pathSegments
        )
    }

    func sendJSON(
        connection: GatewayConnection,
        method: String,
        pathSegments: [String],
        body: JSONValue.Object,
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        throw HermesError(
            "Dashboard mutations are unavailable for this gateway",
            retryable: false
        )
    }
}
