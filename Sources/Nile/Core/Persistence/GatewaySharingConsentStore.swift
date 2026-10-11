import CryptoKit
import Foundation

@MainActor
protocol GatewaySharingConsentStoring {
    func isAccepted(for endpoint: GatewayEndpoint) -> Bool
    func accept(for endpoint: GatewayEndpoint)
    func revokeAll()
}

/// Stores only versioned, hashed canonical endpoints, never credentials or content.
@MainActor
final class GatewaySharingConsentStore: GatewaySharingConsentStoring {
    private let defaults: UserDefaults
    private let storageKey = "privacy.gateway_sharing_consent"
    private let version: Int

    init(defaults: UserDefaults = .standard, version: Int = 1) {
        self.defaults = defaults
        self.version = version
    }

    func isAccepted(for endpoint: GatewayEndpoint) -> Bool {
        acceptedEndpoints.contains(key(for: endpoint))
    }

    func accept(for endpoint: GatewayEndpoint) {
        var accepted = acceptedEndpoints
        accepted.insert(key(for: endpoint))
        let record: [String: Any] = ["version": version, "endpoints": accepted.sorted()]
        defaults.set(record, forKey: storageKey)
    }

    func revokeAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private var acceptedEndpoints: Set<String> {
        guard let record = defaults.dictionary(forKey: storageKey),
              record["version"] as? Int == version,
              let endpoints = record["endpoints"] as? [String]
        else { return [] }
        return Set(endpoints)
    }

    private func key(for endpoint: GatewayEndpoint) -> String {
        SHA256.hash(data: Data(endpoint.baseURL.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
