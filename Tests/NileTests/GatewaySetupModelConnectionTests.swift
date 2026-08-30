import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testSuccessfulReadyHandshakePersistsThenTransitionsAndClearsFormSecret() async throws {
        let store = ModelGatewayStore()
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .idle
        model.gatewayName = "Home"
        model.dashboardURL = "https://gateway.example/hermes"
        model.legacyToken = "  secret  "

        await model.connect()

        XCTAssertEqual(model.state, .connected)
        XCTAssertEqual(model.connectedProfile?.name, "Home")
        XCTAssertEqual(model.connectedProfile?.token, "secret")
        XCTAssertEqual(model.legacyToken, "")
        XCTAssertFalse(model.isSettingsVisible)
        let clientTokens = await client.connections.map(\.token)
        let savedTokens = await store.savedConnections.map(\.token)
        XCTAssertEqual(clientTokens, ["secret"])
        XCTAssertEqual(savedTokens, ["secret"])
    }

    func testHandshakeFailureDoesNotPersistProfileOrClearTypedToken() async {
        let store = ModelGatewayStore()
        let client = ModelGatewayClient(
            failure: HermesError(
                "Gateway rejected the token",
                authRejected: true,
                isConnectionFailure: true
            )
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .idle
        model.dashboardURL = "https://gateway.example"
        model.legacyToken = "typed-secret"

        await model.connect()

        XCTAssertEqual(model.errorMessage, "Gateway rejected the token")
        XCTAssertEqual(model.legacyToken, "typed-secret")
        let savedConnections = await store.savedConnections
        XCTAssertTrue(savedConnections.isEmpty)
    }

    func testStartupReconnectUsesKeychainProfileWithoutPuttingTokenInForm() async throws {
        let endpoint = try GatewayEndpoint.parse("https://saved.example")
        let saved = GatewayProfile(
            id: "gateway-saved",
            name: "Saved",
            endpoint: endpoint,
            token: "keychain-secret"
        )
        let store = ModelGatewayStore(
            profiles: [saved],
            activeID: saved.id
        )
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )

        await model.restoreSavedGateway()

        XCTAssertEqual(model.state, .connected)
        XCTAssertEqual(model.connectedProfile, saved)
        XCTAssertEqual(model.legacyToken, "")
        XCTAssertEqual(model.dashboardURL, "https://saved.example")
        let restoredTokens = await client.connections.map(\.token)
        XCTAssertEqual(restoredTokens, ["keychain-secret"])
    }

    func testCleartextConfirmationPrecedesAllTransportAndPersistenceWork() async {
        let store = ModelGatewayStore()
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .idle
        model.dashboardURL = "http://gateway.local:9119"
        model.legacyToken = "secret"

        await model.connect()

        let attemptedConnections = await client.connections
        let savedConnections = await store.savedConnections
        XCTAssertTrue(model.showCleartextConfirmation)
        XCTAssertTrue(attemptedConnections.isEmpty)
        XCTAssertTrue(savedConnections.isEmpty)
    }

    func testApprovedCleartextConnectionPersistsPermission() async {
        let store = ModelGatewayStore()
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .idle
        model.dashboardURL = "http://gateway.local:9119"

        await model.approveCleartextAndConnect()

        let attemptedConnections = await client.connections
        let savedConnections = await store.savedConnections
        XCTAssertEqual(model.state, .connected)
        XCTAssertEqual(
            attemptedConnections.map(\.cleartextPermission),
            [.approved]
        )
        XCTAssertEqual(
            savedConnections.map(\.cleartextPermission),
            [.approved]
        )
    }

    func testEditingEndpointRevokesInlineCleartextApproval() {
        let model = GatewaySetupModel(
            arguments: [],
            automaticallyRestore: false
        )
        model.cleartextApproved = true
        model.showCleartextConfirmation = true

        model.updateDashboardURL("https://gateway.example")

        XCTAssertEqual(model.dashboardURL, "https://gateway.example")
        XCTAssertFalse(model.cleartextApproved)
        XCTAssertFalse(model.showCleartextConfirmation)
    }

}
