import Foundation

protocol GatewayRPCRequesting: Sendable {
    func request(
        method: String,
        params: JSONValue.Object,
        timeoutMilliseconds: Int64,
        allowNullResult: Bool
    ) async throws -> JSONValue.Object
}

extension TuiGatewayClient: GatewayRPCRequesting {}
