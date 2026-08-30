import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testFailedGatewaySwitchClearsReplacedConnectionState() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Active",
            baseURL: "https://active.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Target",
            baseURL: "https://target.example",
            token: "target-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active, target],
            activeID: active.id
        )
        let client = ModelGatewayClient(
            failure: GatewayTokenRequiredError()
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active

        await model.useGateway(id: target.id)

        XCTAssertNil(model.connectedProfile)
        XCTAssertFalse(model.isConnected)
        let closeCount = await client.closeCount
        let selectedID = await store.currentActiveID
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(selectedID, active.id)
    }

    func testRunningTurnGatewaySwitchStagesWithoutSideEffectsAndDismisses() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Lab Hermes",
            baseURL: "https://lab.example",
            token: "target-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active, target],
            activeID: active.id
        )
        let client = ModelGatewayClient()
        let recorder = ModelGatewaySwitchRecorder(
            needsConfirmation: true
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler {
            recorder.recordConfirmationQuery($0)
        }
        model.installGatewayWillConnectHandler {
            recorder.recordWillConnect($0)
        }

        await model.requestGatewayUse(id: target.id)

        XCTAssertEqual(model.pendingGatewaySwitch, target)
        XCTAssertEqual(model.connectedProfile, active)
        XCTAssertEqual(model.activeGatewayID, active.id)
        XCTAssertTrue(model.isSettingsVisible)
        XCTAssertEqual(recorder.confirmationQueries, [target.id])
        XCTAssertTrue(recorder.willConnectIDs.isEmpty)
        let connections = await client.connections
        let selectedIDs = await store.selectedIDs
        XCTAssertTrue(connections.isEmpty)
        XCTAssertTrue(selectedIDs.isEmpty)

        model.dismissGatewaySwitchConfirmation()

        XCTAssertNil(model.pendingGatewaySwitch)
        XCTAssertEqual(model.connectedProfile, active)
        XCTAssertEqual(model.activeGatewayID, active.id)
    }

    func testConfirmingRunningTurnGatewaySwitchPerformsItExactlyOnce() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Lab Hermes",
            baseURL: "https://lab.example",
            token: "target-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active, target],
            activeID: active.id
        )
        let client = ModelGatewayClient()
        let recorder = ModelGatewaySwitchRecorder(
            needsConfirmation: true
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler {
            recorder.recordConfirmationQuery($0)
        }
        model.installGatewayWillConnectHandler {
            recorder.recordWillConnect($0)
        }

        await model.requestGatewayUse(id: target.id)
        await model.confirmGatewaySwitch()
        await model.confirmGatewaySwitch()

        XCTAssertNil(model.pendingGatewaySwitch)
        XCTAssertEqual(model.connectedProfile, target)
        XCTAssertEqual(model.activeGatewayID, target.id)
        XCTAssertFalse(model.isSettingsVisible)
        XCTAssertEqual(recorder.willConnectIDs, [target.id])
        let connections = await client.connections
        let selectedIDs = await store.selectedIDs
        XCTAssertEqual(connections, [target.connection])
        XCTAssertEqual(selectedIDs, [target.id])
    }

    func testGatewaySwitchWithoutRunningTurnDoesNotPrompt() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Lab Hermes",
            baseURL: "https://lab.example",
            token: "target-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active, target],
            activeID: active.id
        )
        let recorder = ModelGatewaySwitchRecorder(
            needsConfirmation: false
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler {
            recorder.recordConfirmationQuery($0)
        }

        await model.requestGatewayUse(id: target.id)

        XCTAssertNil(model.pendingGatewaySwitch)
        XCTAssertEqual(model.connectedProfile, target)
        XCTAssertEqual(model.activeGatewayID, target.id)
        XCTAssertFalse(model.isSettingsVisible)
        let selectedIDs = await store.selectedIDs
        XCTAssertEqual(selectedIDs, [target.id])
    }

    func testRequestingConnectedActiveGatewayOnlyDismissesSettings() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let store = ModelGatewayStore(
            profiles: [active],
            activeID: active.id
        )
        let client = ModelGatewayClient()
        let recorder = ModelGatewaySwitchRecorder(
            needsConfirmation: true
        )
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
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler {
            recorder.recordConfirmationQuery($0)
        }

        await model.requestGatewayUse(id: active.id)

        XCTAssertFalse(model.isSettingsVisible)
        XCTAssertNil(model.pendingGatewaySwitch)
        XCTAssertTrue(recorder.confirmationQueries.isEmpty)
        let connections = await client.connections
        let selectedIDs = await store.selectedIDs
        XCTAssertTrue(connections.isEmpty)
        XCTAssertTrue(selectedIDs.isEmpty)
    }

    func testConnectionLossDoesNotCancelPendingGatewaySwitch() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Lab Hermes",
            baseURL: "https://lab.example",
            token: "target-secret"
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [active, target],
                activeID: active.id
            ),
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler { _ in true }

        await model.requestGatewayUse(id: target.id)
        model.handleConnectionLoss(
            GatewayConnectionLossNotice(
                message: "old gateway disconnected",
                retryable: false
            )
        )

        XCTAssertEqual(model.pendingGatewaySwitch, target)
        XCTAssertEqual(model.activeGatewayID, active.id)
    }

    func testRemovingPendingGatewaySwitchTargetClearsConfirmation() async throws {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Home Hermes",
            baseURL: "https://home.example",
            token: "active-secret"
        )
        let target = try GatewayProfile(
            id: "gateway-target",
            name: "Lab Hermes",
            baseURL: "https://lab.example",
            token: "target-secret"
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [active, target],
                activeID: active.id
            ),
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active, target]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        model.installGatewaySwitchNeedsConfirmationHandler { _ in true }

        await model.requestGatewayUse(id: target.id)
        XCTAssertEqual(model.pendingGatewaySwitch, target)

        await model.removeGateway(id: target.id)

        XCTAssertNil(model.pendingGatewaySwitch)
        XCTAssertEqual(model.savedGateways, [active])
        XCTAssertEqual(model.connectedProfile, active)
        XCTAssertEqual(model.activeGatewayID, active.id)
    }

}
