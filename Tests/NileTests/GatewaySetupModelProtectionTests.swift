import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testInvalidAddWhileConnectedKeepsCurrentGatewayLive() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Active",
            baseURL: "https://active.example",
            token: "active-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active],
            activeID: active.id
        )
        let client = ModelGatewayClient()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.dashboardURL = "missing-scheme.example"

        await model.connect()

        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.connectedProfile, active)
        XCTAssertNotNil(model.errorMessage)
        let closeCount = await client.closeCount
        let connections = await client.connections
        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(connections.isEmpty)
    }

    func testRemovingGatewayAlsoErasesItsProtectedLocalState() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Active",
            baseURL: "https://active.example",
            token: "active-secret"
        )
        let removed = try GatewayProfile(
            id: "gateway-removed",
            name: "Removed",
            baseURL: "https://removed.example",
            token: "removed-secret"
        )
        let profileStore = ModelGatewayStore(
            profiles: [active, removed],
            activeID: active.id
        )
        let draftStore = ModelComposerDraftStore(
            records: [
                PersistedComposerDraft(
                    gatewayID: removed.id,
                    storedSessionID: "session",
                    revision: 1,
                    text: "private draft",
                    updatedAtMilliseconds: 100
                ),
            ]
        )
        let pinStore = GatewayModelPinStore(
            pinsByGateway: [
                removed.id: [
                    ModelPin(
                        providerSlug: "openai",
                        modelID: "gpt-5"
                    ),
                ],
            ]
        )
        let sessionPinStore = GatewaySessionPinStore(
            pinsByGateway: [removed.id: ["session"]]
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: profileStore,
            composerDraftStore: draftStore,
            sessionPinStore: sessionPinStore,
            modelPinStore: pinStore,
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, removed]
        model.activeGatewayID = active.id
        model.connectedProfile = active

        await model.removeGateway(id: removed.id)

        XCTAssertEqual(model.savedGateways, [active])
        XCTAssertEqual(model.connectedProfile, active)
        let drafts = await draftStore.load()
        XCTAssertTrue(drafts.isEmpty)
        let pins = await pinStore.load(gatewayID: removed.id)
        XCTAssertTrue(pins.isEmpty)
        let sessionPins = await sessionPinStore.load(
            gatewayID: removed.id
        )
        XCTAssertTrue(sessionPins.isEmpty)
    }

}
