import Foundation

struct GatewayProfile: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let endpoint: GatewayEndpoint
    let token: String
    var lastSessionID: String?
    let cleartextPermission: CleartextPermission

    init(
        id: String,
        name: String,
        endpoint: GatewayEndpoint,
        token: String,
        lastSessionID: String? = nil,
        cleartextPermission: CleartextPermission = .denied
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.token = token
        self.lastSessionID = lastSessionID
        self.cleartextPermission = cleartextPermission
    }

    init(
        id: String,
        name: String,
        baseURL: String,
        token: String,
        lastSessionID: String? = nil,
        cleartextPermission: CleartextPermission = .denied
    ) throws {
        self.init(
            id: id,
            name: name,
            endpoint: try GatewayEndpoint.parse(baseURL),
            token: token,
            lastSessionID: lastSessionID,
            cleartextPermission: cleartextPermission
        )
    }

    var normalizedBaseURL: String { endpoint.baseURL }
    var displayName: String { name.isEmpty ? normalizedBaseURL : name }
    var connection: GatewayConnection {
        GatewayConnection(
            endpoint: endpoint,
            token: token,
            cleartextPermission: cleartextPermission
        )
    }
}

struct HermesError: LocalizedError, Equatable, Sendable {
    let message: String
    let authRejected: Bool
    let code: Int?
    let retryable: Bool
    let isConnectionFailure: Bool
    let requestMayHaveSucceeded: Bool

    init(
        _ message: String,
        authRejected: Bool = false,
        code: Int? = nil,
        retryable: Bool? = nil,
        isConnectionFailure: Bool = false,
        requestMayHaveSucceeded: Bool = false
    ) {
        self.message = message
        self.authRejected = authRejected
        self.code = code
        self.retryable = retryable ?? !authRejected
        self.isConnectionFailure = isConnectionFailure
        self.requestMayHaveSucceeded = requestMayHaveSucceeded
    }

    var errorDescription: String? { message }
}

protocol HermesDisconnectServing: Sendable {
    func disconnect() async
}

protocol HermesConnectionServing: HermesDisconnectServing, Sendable {
    func connect(_ connection: GatewayConnection) async throws
}
