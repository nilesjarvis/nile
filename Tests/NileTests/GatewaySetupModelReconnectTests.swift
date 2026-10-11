import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testTransientSavedGatewayFailureRetainsProfileAndWaitsOffline() async throws {
        let saved = try GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            baseURL: "https://saved.example",
            token: "keychain-secret"
        )
        let store = ModelGatewayStore(
            profiles: [saved],
            activeID: saved.id
        )
        let network = ModelGatewayNetwork(available: false)
        let client = ModelGatewayClient(
            failure: URLError(.cannotConnectToHost)
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: client,
            reconnectCoordinator: GatewayReconnectCoordinator(
                network: network,
                jitter: { $0 },
                sleep: { _ in }
            ),
            automaticallyRestore: false
        )

        await model.restoreSavedGateway()
        try await waitUntil { model.state == .offline }

        XCTAssertEqual(model.connectedProfile, saved)
        XCTAssertTrue(model.showsSessionShell)
        XCTAssertFalse(model.isConnected)
        XCTAssertEqual(model.legacyToken, "")
        let connectionCount = await client.connections.count
        XCTAssertEqual(connectionCount, 1)
    }

    func testReconnectPublishesConnectedOnlyAfterSessionRestoration() async throws {
        let saved = try GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            baseURL: "https://saved.example",
            token: "keychain-secret"
        )
        let network = ModelGatewayNetwork(available: true)
        let restoreGate = ModelReconnectRestoreGate()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [saved],
                activeID: saved.id
            ),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: ModelGatewayClient(),
            reconnectCoordinator: GatewayReconnectCoordinator(
                network: network,
                jitter: { $0 },
                sleep: { _ in }
            ),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [saved]
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.isSettingsVisible = false
        model.installReconnectRestorer { _ in
            await restoreGate.restore()
        }

        model.handleConnectionLoss(
            GatewayConnectionLossNotice(
                message: "connection lost",
                retryable: true
            )
        )

        try await waitUntil { model.state == .restoring }
        try await waitUntil { await restoreGate.isWaiting }
        XCTAssertFalse(model.isConnected)
        XCTAssertTrue(model.showsSessionShell)

        await restoreGate.finish(true)
        try await waitUntil { model.state == .connected }
        XCTAssertTrue(model.isConnected)
    }

    func testReconnectSignInRetainsSavedProfileContext() async throws {
        let saved = try GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            baseURL: "https://saved.example",
            token: ""
        )
        let login = URL(string: "https://saved.example/login")!
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [saved],
                activeID: saved.id
            ),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: ModelGatewayClient(
                failure: GatewaySignInRequiredError(loginURL: login)
            ),
            reconnectCoordinator: GatewayReconnectCoordinator(
                network: ModelGatewayNetwork(available: true),
                jitter: { $0 },
                sleep: { _ in }
            ),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [saved]
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.isSettingsVisible = false

        model.handleConnectionLoss(
            GatewayConnectionLossNotice(
                message: "session expired",
                retryable: true
            )
        )
        try await waitUntil { model.gatewaySignInURL == login }

        XCTAssertEqual(model.connectedProfile, saved)
        XCTAssertEqual(model.state, .reconnecting)
        XCTAssertFalse(model.isSettingsVisible)
    }

    func testDashboardExpiryClosesSocketAndPresentsSavedProfileSignIn() async throws {
        let saved = try GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            baseURL: "https://saved.example/hermes",
            token: ""
        )
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [saved],
                activeID: saved.id
            ),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [saved]
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.isSettingsVisible = false
        let eventChannel = AsyncStream<GatewayAuthenticationEvent>
            .makeStream()
        model.observeAuthenticationEvents(eventChannel.stream)
        let login = URL(
            string: "https://saved.example/hermes/login"
        )!

        eventChannel.continuation.yield(
            GatewayAuthenticationEvent(
                profileID: saved.id,
                loginURL: login
            )
        )
        try await waitUntil { model.gatewaySignInURL == login }
        try await waitUntil { await client.closeCount == 1 }

        XCTAssertEqual(model.connectedProfile, saved)
        XCTAssertEqual(model.state, .reconnecting)
        XCTAssertFalse(model.isSettingsVisible)
        XCTAssertFalse(model.isConnected)
    }

    func testDashboardExpiryFencesSuspendedReconnectBeforeRestoration() async throws {
        let saved = try GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            baseURL: "https://saved.example/hermes",
            token: ""
        )
        let client = ModelSuspendedGatewayClient()
        let restoreRecorder = ModelReconnectRestoreRecorder()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [saved],
                activeID: saved.id
            ),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: client,
            reconnectCoordinator: GatewayReconnectCoordinator(
                network: ModelGatewayNetwork(available: true),
                jitter: { $0 },
                sleep: { _ in }
            ),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [saved]
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.isSettingsVisible = false
        model.installReconnectRestorer { _ in
            await restoreRecorder.record()
            return true
        }
        let eventChannel = AsyncStream<GatewayAuthenticationEvent>
            .makeStream()
        model.observeAuthenticationEvents(eventChannel.stream)

        model.handleConnectionLoss(
            GatewayConnectionLossNotice(
                message: "connection lost",
                retryable: true
            )
        )
        try await waitUntil { await client.isWaiting }

        let login = URL(
            string: "https://saved.example/hermes/login"
        )!
        eventChannel.continuation.yield(
            GatewayAuthenticationEvent(
                profileID: saved.id,
                loginURL: login
            )
        )
        try await waitUntil { model.gatewaySignInURL == login }
        await client.finishConnect()
        try await waitUntil { await client.closeCount == 2 }

        let restoreCount = await restoreRecorder.count
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(model.gatewaySignInURL, login)
        XCTAssertEqual(model.state, .reconnecting)
        XCTAssertFalse(model.isConnected)
    }

}
