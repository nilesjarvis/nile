import Foundation

struct GatewayProfileSnapshot: Equatable, Sendable {
    let profiles: [GatewayProfile]
    let activeProfile: GatewayProfile?
}

protocol GatewayProfileStoring: Sendable {
    func load() async throws -> GatewayProfileSnapshot

    func save(
        connection: GatewayConnection,
        name: String?
    ) async throws -> GatewayProfile

    func selectGateway(id: String) async throws

    func removeGateway(id: String) async throws

    func saveLastSessionID(
        gatewayID: String,
        storedSessionID: String
    ) async throws
}

protocol GatewayCredentialStoring: Sendable {
    func token(credentialID: String) async throws -> String?
    func storeToken(_ token: String, credentialID: String) async throws
    func removeToken(credentialID: String) async throws
}

protocol GatewayProfileMetadataStoring: Sendable {
    func read() async throws -> Data?
    /// Atomically commits `data`; must not throw after the new bytes are visible.
    func write(_ data: Data) async throws
    func remove() async throws
}

enum GatewayProfileStoreError: LocalizedError, Equatable, Sendable {
    case malformedMetadata
    case unsupportedVersion(Int)
    case missingCredential(String)
    case credentialAccess
    case metadataAccess
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .malformedMetadata:
            "Saved gateway information is damaged."
        case let .unsupportedVersion(version):
            "Saved gateway information uses unsupported version \(version)."
        case .missingCredential:
            "A saved gateway credential is missing."
        case .credentialAccess:
            "Nile could not access the secure gateway credential."
        case .metadataAccess:
            "Nile could not access saved gateway information."
        case .rollbackFailed:
            "Nile could not safely finish updating the saved gateway."
        }
    }
}
