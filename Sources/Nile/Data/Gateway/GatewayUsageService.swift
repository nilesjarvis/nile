import Foundation

/// Owns live-session usage RPCs and authenticated gateway analytics reads.
struct GatewayUsageService: HermesUsageServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let connectionState: GatewayConnectionState
    private let dashboard: (any GatewayDashboardReading)?

    init(
        rpc: any GatewayRPCRequesting,
        connectionState: GatewayConnectionState,
        dashboard: (any GatewayDashboardReading)?
    ) {
        self.rpc = rpc
        self.connectionState = connectionState
        self.dashboard = dashboard
    }

    func sessionUsage(liveSessionID: String) async throws -> SessionUsage {
        let usage = try await rpc.request(
            method: "session.usage",
            params: ["session_id": .string(liveSessionID)],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        let breakdown: JSONValue.Object?
        do {
            breakdown = try await rpc.request(
                method: "session.context_breakdown",
                params: ["session_id": .string(liveSessionID)],
                timeoutMilliseconds: 30_000,
                allowNullResult: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            breakdown = nil
        }
        return decodeSessionUsage(usage, breakdown: breakdown)
    }

    func gatewayStats(days: Int) async throws -> GatewayStats {
        let connection = try await connectionState.requireActive()
        guard let dashboard else {
            throw HermesError(
                "Gateway analytics are unavailable for this connection",
                retryable: false
            )
        }
        let safeDays = min(365, max(1, days))
        let result = try await dashboard.getJSON(
            connection: connection,
            pathSegments: ["analytics", "usage"],
            query: ["days": String(safeDays)]
        )
        return decodeGatewayStats(result, fallbackDays: safeDays)
    }
}
