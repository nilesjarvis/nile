import Foundation

/// Shares the currently authenticated connection with dashboard-backed
/// capability services without exposing repository transport state.
actor GatewayConnectionState {
    private var connection: GatewayConnection?

    func set(_ connection: GatewayConnection) {
        self.connection = connection
    }

    func clear() {
        connection = nil
    }

    func requireActive() throws -> GatewayConnection {
        guard let connection else {
            throw HermesError(
                "Not connected to the Hermes gateway",
                retryable: true,
                isConnectionFailure: true
            )
        }
        return connection
    }
}
