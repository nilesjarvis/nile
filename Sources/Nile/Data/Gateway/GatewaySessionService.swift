import Foundation

/// Session/history/status transport sharing the repository's active connection.
struct GatewaySessionService: HermesSessionServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let connectionState: GatewayConnectionState
    private let dashboard: (any GatewayDashboardReading)?
    private let sessionCodec = GatewaySessionCodec()
    private let storedSessionCodec = GatewayStoredSessionCodec()

    init(
        rpc: any GatewayRPCRequesting,
        connectionState: GatewayConnectionState,
        dashboard: (any GatewayDashboardReading)?
    ) {
        self.rpc = rpc
        self.connectionState = connectionState
        self.dashboard = dashboard
    }

    func listSessions(limit: Int) async throws -> [HermesSession] {
        let result = try await rpc.request(
            method: "session.list",
            params: ["limit": .number(Double(limit))],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try sessionCodec.decodeSessionList(result)
    }

    func readStoredSessionSource(
        storedSessionID: String
    ) async throws -> String? {
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Stored session metadata is unavailable for this gateway",
                retryable: false
            )
        }
        let result = try await dashboard.getJSON(
            connection: connection,
            pathSegments: ["sessions", storedSessionID]
        )
        return result.optionalString("source")
    }

    func readStoredSession(
        storedSessionID: String
    ) async throws -> [HermesMessage] {
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Stored session history is unavailable for this gateway",
                retryable: false
            )
        }
        let result = try await dashboard.getJSON(
            connection: connection,
            pathSegments: ["sessions", storedSessionID, "messages"]
        )
        return try storedSessionCodec.decodeMessages(result)
    }

    func openSession(storedSessionID: String) async throws -> LiveSession {
        let result = try await rpc.request(
            method: "session.resume",
            params: ["session_id": .string(storedSessionID)],
            timeoutMilliseconds: 60_000,
            allowNullResult: false
        )
        return try sessionCodec.requireLiveID(
            sessionCodec.decodeLiveSession(
                result,
                fallbackStoredID: storedSessionID
            ),
            method: "session.resume"
        )
    }

    func liveSessionStatus(storedSessionID: String) async throws -> String? {
        try await activeSessionStatuses()[storedSessionID]
    }

    func liveRuntimeStatus(liveSessionID: String) async throws -> String? {
        let result = try await activeList()
        return try sessionCodec.decodeRuntimeStatuses(result)[liveSessionID]
    }

    func activeSessionStatuses() async throws -> [String: String] {
        try sessionCodec.decodeStoredStatuses(await activeList())
    }

    func createSession(title: String?) async throws -> LiveSession {
        var params: JSONValue.Object = ["source": .string("niles")]
        if let title, !title.isBlank {
            params["title"] = .string(title)
        }
        let result = try await rpc.request(
            method: "session.create",
            params: params,
            timeoutMilliseconds: 60_000,
            allowNullResult: false
        )
        return try sessionCodec.requireLiveID(
            sessionCodec.decodeLiveSession(result, fallbackStoredID: nil),
            method: "session.create"
        )
    }

    func renameSession(liveSessionID: String, title: String) async throws {
        _ = try await rpc.request(
            method: "session.title",
            params: [
                "session_id": .string(liveSessionID),
                "title": .string(title),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: true
        )
    }

    private func activeList() async throws -> JSONValue.Object {
        try await rpc.request(
            method: "session.active_list",
            params: [:],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
    }
}
