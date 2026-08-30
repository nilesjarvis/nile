import Foundation

enum GatewayProfileStoreCodec {
    static func decode(_ data: Data) throws -> GatewayProfilesEnvelope {
        let envelope: GatewayProfilesEnvelope
        do {
            envelope = try JSONDecoder().decode(
                GatewayProfilesEnvelope.self,
                from: data
            )
        } catch {
            throw GatewayProfileStoreError.malformedMetadata
        }

        do {
            try envelope.validate()
        } catch let error as GatewayProfileStoreError {
            throw error
        } catch {
            throw GatewayProfileStoreError.malformedMetadata
        }
        return envelope
    }

    static func encode(_ envelope: GatewayProfilesEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    static func defaultName(for baseURL: String) -> String {
        let stripped = baseURL
            .replacingOccurrences(of: "https://", with: "", options: .anchored)
            .replacingOccurrences(of: "http://", with: "", options: .anchored)
        return stripped.isEmpty ? "Hermes gateway" : stripped
    }
}

struct GatewayProfilesEnvelope: Codable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var activeGatewayID: String?
    var profiles: [PersistedGatewayProfile] = []
    var pendingCredentialDeletions: [String] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case activeGatewayID
        case profiles
        case pendingCredentialDeletions
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        activeGatewayID = try container.decodeIfPresent(
            String.self,
            forKey: .activeGatewayID
        )
        profiles = try container.decode(
            [PersistedGatewayProfile].self,
            forKey: .profiles
        )
        pendingCredentialDeletions = try container.decodeIfPresent(
            [String].self,
            forKey: .pendingCredentialDeletions
        ) ?? []
    }

    func validate() throws {
        guard version == Self.currentVersion else {
            throw GatewayProfileStoreError.unsupportedVersion(version)
        }
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.baseURL)).count == profiles.count,
              Set(profiles.map(\.credentialID)).count == profiles.count,
              Set(pendingCredentialDeletions).count == pendingCredentialDeletions.count,
              pendingCredentialDeletions.allSatisfy({
                  $0.hasPrefix("credential-") && $0.nonBlank != nil
              }),
              Set(profiles.map(\.credentialID)).isDisjoint(
                with: Set(pendingCredentialDeletions)
              )
        else {
            throw GatewayProfileStoreError.malformedMetadata
        }
        if let activeGatewayID,
           !profiles.contains(where: { $0.id == activeGatewayID }) {
            throw GatewayProfileStoreError.malformedMetadata
        }
        for metadata in profiles {
            try metadata.validate()
        }
    }
}

struct PersistedGatewayProfile: Codable, Sendable {
    let id: String
    let credentialID: String
    let name: String
    let baseURL: String
    var lastSessionID: String?
    let cleartextPermission: CleartextPermission

    var resolvedName: String {
        name.nonBlank ?? GatewayProfileStoreCodec.defaultName(for: baseURL)
    }

    func validate() throws {
        guard id.hasPrefix("gateway-"),
              id.nonBlank != nil,
              credentialID.hasPrefix("credential-"),
              credentialID.nonBlank != nil
        else {
            throw GatewayProfileStoreError.malformedMetadata
        }
        let endpoint = try GatewayEndpoint.parse(baseURL)
        guard endpoint.baseURL == baseURL,
              endpoint.isCleartext || cleartextPermission == .denied
        else {
            throw GatewayProfileStoreError.malformedMetadata
        }
    }

    func profile(token: String) throws -> GatewayProfile {
        try validate()
        let endpoint = try GatewayEndpoint.parse(baseURL)
        return GatewayProfile(
            id: id,
            name: resolvedName,
            endpoint: endpoint,
            token: token,
            lastSessionID: lastSessionID?.nonBlank,
            cleartextPermission: endpoint.isCleartext ? cleartextPermission : .denied
        )
    }
}

private extension String {
    var nonBlank: String? {
        isEmpty || allSatisfy(\.isWhitespace) ? nil : self
    }
}
