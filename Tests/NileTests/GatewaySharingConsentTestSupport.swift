import Foundation
@testable import Nile

/// Existing gateway tests exercise post-consent connection behavior explicitly.
@MainActor
final class AcceptedGatewaySharingConsentStore: GatewaySharingConsentStoring {
    private var accepted = true
    func isAccepted(for endpoint: GatewayEndpoint) -> Bool { accepted }
    func accept(for endpoint: GatewayEndpoint) { accepted = true }
    func revokeAll() { accepted = false }
}

actor ConsentRaceGatewayClient: GatewayConnecting {
    private var firstConnection: CheckedContinuation<Void, any Error>?
    private var connectionCount = 0
    private(set) var closeCount = 0
    var isWaiting: Bool { firstConnection != nil }

    func connect(_ connection: GatewayConnection, timeoutMilliseconds: Int64) async throws {
        connectionCount += 1
        if connectionCount == 1 {
            try await withCheckedThrowingContinuation { firstConnection = $0 }
        }
    }

    func close() { closeCount += 1 }

    func finishOldConnection(success: Bool = false) {
        let pending = firstConnection
        firstConnection = nil
        if success {
            pending?.resume()
        } else {
            pending?.resume(throwing: URLError(.cancelled))
        }
    }
}
