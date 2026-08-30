import Foundation
import XCTest
@testable import Nile

actor ModelGatewayClient: GatewayConnecting {
    private let failure: (any Error)?
    private(set) var connections: [GatewayConnection] = []
    private(set) var closeCount = 0

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) throws {
        connections.append(connection)
        if let failure {
            throw failure
        }
    }

    func close() {
        closeCount += 1
    }
}

@MainActor
final class ModelGatewaySwitchRecorder {
    let needsConfirmation: Bool
    private(set) var confirmationQueries: [String] = []
    private(set) var willConnectIDs: [String?] = []

    init(needsConfirmation: Bool) {
        self.needsConfirmation = needsConfirmation
    }

    func recordConfirmationQuery(_ gatewayID: String) -> Bool {
        confirmationQueries.append(gatewayID)
        return needsConfirmation
    }

    func recordWillConnect(_ gatewayID: String?) {
        willConnectIDs.append(gatewayID)
    }
}

actor ModelSuspendedGatewayClient: GatewayConnecting {
    private var continuation:
        CheckedContinuation<Void, any Error>?
    private(set) var closeCount = 0

    var isWaiting: Bool {
        continuation != nil
    }

    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) async throws {
        try await withCheckedThrowingContinuation {
            continuation = $0
        }
    }

    func close() {
        closeCount += 1
    }

    func finishConnect() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

actor ModelGatewayNetwork: GatewayNetworkWaiting {
    private var available: Bool
    private var waiters: [
        CheckedContinuation<Void, any Error>
    ] = []

    init(available: Bool) {
        self.available = available
    }

    func isNetworkAvailable() -> Bool {
        available
    }

    func waitUntilNetworkAvailable() async throws {
        guard !available else {
            return
        }
        try await withCheckedThrowingContinuation {
            (
                continuation: CheckedContinuation<Void, any Error>
            ) in
            waiters.append(continuation)
        }
    }
}

actor ModelReconnectRestoreGate {
    private var continuation: CheckedContinuation<Bool, Never>?

    var isWaiting: Bool {
        continuation != nil
    }

    func restore() async -> Bool {
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func finish(_ restored: Bool) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: restored)
    }
}

actor ModelReconnectRestoreRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
