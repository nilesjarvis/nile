import Foundation

struct GatewayEndpoint: Hashable, Codable, Sendable, CustomStringConvertible {
    let baseURL: String

    var isCleartext: Bool {
        baseURL.hasPrefix("http://")
    }

    var description: String {
        baseURL
    }

    static func parse(_ value: String) throws -> GatewayEndpoint {
        try GatewayEndpointParser.parse(value, legacy: false)
    }

    static func parseLegacy(_ value: String) throws -> GatewayEndpoint {
        try GatewayEndpointParser.parse(value, legacy: true)
    }

    static func parseOrNil(_ value: String) -> GatewayEndpoint? {
        try? parse(value)
    }

    func apiURL(pathSegments: [String]) throws -> URL {
        var result = baseURL
        for segment in pathSegments {
            guard !segment.isEmpty else {
                throw GatewayEndpointError("Gateway API path was invalid")
            }
            result += "/" + percentEncodePathSegment(segment)
        }
        guard let url = URL(string: result) else {
            throw GatewayEndpointError("Enter a valid gateway URL")
        }
        return url
    }

    func webSocketURL(
        credentialName: String = "token",
        credential: String
    ) throws -> URL {
        guard credentialName == "token" || credentialName == "ticket" else {
            throw GatewayEndpointError("Unsupported gateway credential")
        }
        let socketScheme = isCleartext ? "ws" : "wss"
        let httpScheme = isCleartext ? "http" : "https"
        let socketBase = socketScheme + baseURL.dropFirst(httpScheme.count)
        let encodedCredential = percentEncodeQueryValue(credential)
        guard let url = URL(
            string: "\(socketBase)/api/ws?\(credentialName)=\(encodedCredential)"
        ) else {
            throw GatewayEndpointError("Enter a valid gateway URL")
        }
        return url
    }

}

struct GatewayEndpointError: LocalizedError, Equatable, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private let unreservedURLBytes = Set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8
)

private func percentEncodeQueryValue(_ value: String) -> String {
    value.utf8.map { byte in
        if unreservedURLBytes.contains(byte) {
            return String(UnicodeScalar(byte))
        }
        return String(format: "%%%02X", byte)
    }.joined()
}

private func percentEncodePathSegment(_ value: String) -> String {
    percentEncodeQueryValue(value)
}
