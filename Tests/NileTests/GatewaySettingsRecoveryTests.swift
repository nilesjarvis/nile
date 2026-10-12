import Foundation
import XCTest
@testable import Nile

@MainActor
final class GatewaySettingsRecoveryTests: XCTestCase {
    func testInvalidGatewayFormDoesNotCancelPendingRecovery() async throws {
        let client = ModelSuspendedGatewayClient()
        let model = try makeModel(client: client)
        model.handleConnectionLoss(loss)
        try await waitUntil { await client.isWaiting }
        model.showSettings()
        model.dashboardURL = "not a gateway URL"
        await model.connect()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.reconnectCoordinator.isScheduled)
        await client.finishConnect()
        try await waitUntil { model.isConnected }
        XCTAssertEqual(model.connectedProfile?.id, "saved")
    }

    func testTransientStartupFailureRecoversWithoutManualRetry() async throws {
        let client = StartupRetryGatewayClient()
        let network = ModelGatewayNetwork(available: false)
        let model = try makeModel(client: client, network: network)
        model.state = .loading
        model.connectedProfile = nil
        model.isSettingsVisible = true
        await model.restoreSavedGateway()
        try await waitUntil { model.state == .offline }
        XCTAssertTrue(model.showsSessionShell)

        await network.setAvailable()
        try await waitUntil { model.isConnected }
        XCTAssertFalse(model.isSettingsVisible)
        let attempts = await client.attempts
        XCTAssertEqual(attempts, 2)
    }

    func testRejectedStartupCredentialStillRequiresUserAction() async throws {
        let client = ModelGatewayClient(failure: HermesError(
            "Sign in required", authRejected: true, isConnectionFailure: true
        ))
        let model = try makeModel(client: client)
        model.state = .loading
        model.connectedProfile = nil
        model.isSettingsVisible = true
        await model.restoreSavedGateway()

        XCTAssertEqual(model.errorMessage, "Sign in required")
        XCTAssertTrue(model.isSettingsVisible)
        XCTAssertFalse(model.reconnectCoordinator.isScheduled)
        XCTAssertNil(model.connectedProfile)
    }

    func testSlowStartupKeepsLaunchStateUntilSavedGatewayConnects() async throws {
        let client = ModelSuspendedGatewayClient()
        let model = try makeModel(client: client)
        model.state = .loading
        model.connectedProfile = nil
        model.isSettingsVisible = true
        let launch = Task { await model.restoreSavedGateway() }
        try await waitUntil { await client.isWaiting }

        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.connectedProfile)
        await client.finishConnect()
        await launch.value

        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.showsSessionShell)
        XCTAssertFalse(model.isSettingsVisible)
    }

    func testOpeningSettingsDuringHandshakeDoesNotCancelRecovery() async throws {
        let client = ModelSuspendedGatewayClient()
        let model = try makeModel(client: client)
        let restored = ModelReconnectRestoreRecorder()
        model.installReconnectRestorer { _ in
            await restored.record()
            return true
        }
        model.handleConnectionLoss(loss)
        try await waitUntil { await client.isWaiting }

        model.showSettings()
        XCTAssertTrue(model.reconnectCoordinator.isScheduled)
        XCTAssertEqual(model.connectionStatusText, "Reconnecting…")
        await client.finishConnect()
        try await waitUntil { model.isConnected }

        XCTAssertTrue(model.isSettingsVisible)
        let restoreCount = await restored.count
        let closeCount = await client.closeCount
        XCTAssertEqual(restoreCount, 1)
        XCTAssertEqual(closeCount, 0)
        model.dismissSettings()
        XCTAssertTrue(model.showsSessionShell)
    }

    func testNetworkReturnRecoversAutomaticallyWhileSettingsIsOpen() async throws {
        let network = ModelGatewayNetwork(available: false)
        let client = ModelGatewayClient()
        let model = try makeModel(client: client, network: network)
        model.handleConnectionLoss(loss)
        try await waitUntil { model.state == .offline }
        model.showSettings()

        XCTAssertEqual(model.connectionStatusText, "Waiting for network…")
        await network.setAvailable()
        try await waitUntil { model.isConnected }

        XCTAssertTrue(model.isSettingsVisible)
        let connections = await client.connections
        XCTAssertEqual(connections.count, 1)
        model.dismissSettings()
        XCTAssertTrue(model.showsSessionShell)
    }

    func testDoneReturnsToExistingGatewayDuringEachRecoveryPhase() throws {
        let model = try makeModel()
        for phase: GatewaySetupModel.ProbeState in [.offline, .reconnecting, .restoring, .connected] {
            model.state = phase
            model.showSettings()
            model.dismissSettings()
            XCTAssertFalse(model.isSettingsVisible, "\(phase)")
            XCTAssertTrue(model.showsSessionShell, "\(phase)")
            XCTAssertEqual(model.state, phase)
        }
        model.state = .failed("Access denied")
        model.showSettings()
        model.dismissSettings()
        XCTAssertFalse(model.isSettingsVisible)
        XCTAssertFalse(model.isConnected)
    }

    func testDoneStillProtectsGatewayMutationsAndMissingProfile() throws {
        let model = try makeModel()
        model.showSettings()
        model.state = .checking
        model.dismissSettings()
        XCTAssertTrue(model.isSettingsVisible)
        model.state = .connected
        model.isUpdatingHermesVoice = true
        model.dismissSettings()
        XCTAssertTrue(model.isSettingsVisible)
        model.isUpdatingHermesVoice = false
        model.connectedProfile = nil
        model.dismissSettings()
        XCTAssertTrue(model.isSettingsVisible)
    }

    func testConnectionLossDoesNotDismissSettingsOpenedByUser() async throws {
        let client = ModelGatewayClient()
        let model = try makeModel(client: client)
        model.showSettings()
        model.handleConnectionLoss(loss)
        XCTAssertTrue(model.isSettingsVisible)
        try await waitUntil { model.isConnected }
        XCTAssertTrue(model.isSettingsVisible)
    }

    func testForegroundRestartsRecoveryWithSettingsOpen() async throws {
        let model = try makeModel()
        model.state = .offline
        model.showSettings()
        model.onAppForeground()
        try await waitUntil { model.isConnected }
        XCTAssertTrue(model.isSettingsVisible)
    }

    func testGatewaySwitchFencesCancelledSessionRestoration() async throws {
        let client = ModelGatewayClient()
        let replacement = try profile(id: "replacement")
        let model = try makeModel(client: client, otherProfiles: [replacement])
        let gate = ModelReconnectRestoreGate()
        model.installReconnectRestorer { _ in await gate.restore() }
        model.handleConnectionLoss(loss)
        try await waitUntil { await gate.isWaiting }
        model.showSettings()
        await model.useGateway(id: replacement.id)
        XCTAssertEqual(model.connectedProfile, replacement)

        await gate.finish(true)
        // A foreground turn and actor round-trip also let the cancelled
        // restoration return without giving it ownership of the new socket.
        let saved = try await model.profileStore.load()
        let closeCount = await client.closeCount
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(model.activeGatewayID, replacement.id)
        XCTAssertEqual(model.connectedProfile, replacement)
        XCTAssertEqual(saved.activeProfile, replacement)
        XCTAssertTrue(model.isConnected)
    }

    private var loss: GatewayConnectionLossNotice {
        GatewayConnectionLossNotice(message: "Connection lost", retryable: true)
    }

    private func profile(id: String = "saved") throws -> GatewayProfile {
        try GatewayProfile(id: id, name: id, baseURL: "https://\(id).example", token: "")
    }

    private func makeModel(
        client: any GatewayConnecting = ModelGatewayClient(),
        network: any GatewayNetworkWaiting = ModelGatewayNetwork(available: true),
        otherProfiles: [GatewayProfile] = []
    ) throws -> GatewaySetupModel {
        let saved = try profile()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(profiles: [saved] + otherProfiles, activeID: saved.id),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: client,
            reconnectCoordinator: GatewayReconnectCoordinator(network: network),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [saved] + otherProfiles
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.isSettingsVisible = false
        return model
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for recovery")
                throw URLError(.timedOut)
            }
            await Task.yield()
        }
    }
}

private actor StartupRetryGatewayClient: GatewayConnecting {
    private(set) var attempts = 0

    func connect(_ connection: GatewayConnection, timeoutMilliseconds: Int64) throws {
        attempts += 1
        if attempts == 1 { throw URLError(.cannotConnectToHost) }
    }

    func close() {}
}
