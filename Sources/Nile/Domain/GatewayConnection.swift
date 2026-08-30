import Foundation

enum CleartextPermission: String, Codable, CaseIterable, Sendable {
    case denied
    case approved
    case legacyAllowed

    var allowsCleartext: Bool {
#if NILE_CLEARTEXT_GATEWAYS_SUPPORTED
        self != .denied
#else
        false
#endif
    }
}

struct GatewayConnection: Hashable, Codable, Sendable {
    let endpoint: GatewayEndpoint
    let token: String
    let cleartextPermission: CleartextPermission

    init(
        endpoint: GatewayEndpoint,
        token: String,
        cleartextPermission: CleartextPermission = .denied
    ) {
        self.endpoint = endpoint
        self.token = token
        self.cleartextPermission = cleartextPermission
    }

    init(
        baseURL: String,
        token: String,
        cleartextPermission: CleartextPermission = .denied
    ) throws {
        self.init(
            endpoint: try GatewayEndpoint.parse(baseURL),
            token: token,
            cleartextPermission: cleartextPermission
        )
    }

    var baseURL: String {
        endpoint.baseURL
    }

    var normalizedBaseURL: String {
        endpoint.baseURL
    }

    func webSocketURL(
        credentialName: String = "token",
        credential: String? = nil
    ) throws -> URL {
        if endpoint.isCleartext && !cleartextPermission.allowsCleartext {
            throw GatewayEndpointError(
                "Unencrypted gateways require explicit approval for this profile"
            )
        }
        return try endpoint.webSocketURL(
            credentialName: credentialName,
            credential: credential ?? token
        )
    }
}
