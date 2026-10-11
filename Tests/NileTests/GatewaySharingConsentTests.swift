import Foundation
import XCTest
@testable import Nile

@MainActor
final class GatewaySharingConsentTests: XCTestCase {
    func testNewGatewayWaitsForExplicitPermissionBeforeAnyConnection() async throws {
        let (consent, _, _) = isolatedStore()
        let profiles = ModelGatewayStore()
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, profiles: profiles, client: client)
        model.state = .idle
        model.dashboardURL = "https://gateway.example/hermes"
        model.legacyToken = "secret"

        await model.connect()

        XCTAssertEqual(model.pendingSharingConsent?.endpoint.baseURL, model.dashboardURL)
        XCTAssertNil(model.pendingSharingConsent?.profileID)
        XCTAssertFalse(consent.isAccepted(for: try endpoint(model.dashboardURL)))
        let connections = await client.connections
        let saved = await profiles.savedConnections
        XCTAssertTrue(connections.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(model.state, .idle)
    }

    func testCancelDoesNotApproveOrConnect() async throws {
        let (consent, _, _) = isolatedStore()
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, client: client)
        model.dashboardURL = "https://gateway.example"
        await model.connect()

        model.cancelSharingConsent()
        await model.approveSharingConsent()

        XCTAssertNil(model.pendingSharingConsent)
        XCTAssertFalse(consent.isAccepted(for: try endpoint(model.dashboardURL)))
        let connections = await client.connections
        XCTAssertTrue(connections.isEmpty)
        await model.connect()
        XCTAssertNotNil(model.pendingSharingConsent)
    }

    func testApprovalConnectsAndSurvivesModelRelaunch() async throws {
        let (consent, defaults, _) = isolatedStore()
        let profiles = ModelGatewayStore()
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, profiles: profiles, client: client)
        model.dashboardURL = "https://gateway.example/hermes"
        await model.connect()
        await model.approveSharingConsent()

        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.pendingSharingConsent)
        let relaunchedClient = ModelGatewayClient()
        let relaunched = makeModel(
            consent: GatewaySharingConsentStore(defaults: defaults),
            profiles: profiles, client: relaunchedClient
        )
        await relaunched.restoreSavedGateway()
        XCTAssertTrue(relaunched.isConnected)
        XCTAssertNil(relaunched.pendingSharingConsent)
        let connections = await relaunchedClient.connections
        XCTAssertEqual(connections.map(\.endpoint.baseURL), ["https://gateway.example/hermes"])
    }

    func testChangingEndpointCannotApproveAStaleRequest() async throws {
        let (consent, _, _) = isolatedStore()
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, client: client)
        model.dashboardURL = "https://first.example"
        await model.connect()
        model.updateDashboardURL("https://second.example")

        await model.approveSharingConsent()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(consent.isAccepted(for: try endpoint("https://first.example")))
        XCTAssertFalse(consent.isAccepted(for: try endpoint("https://second.example")))
        let connections = await client.connections
        XCTAssertTrue(connections.isEmpty)
        await model.connect()
        XCTAssertEqual(model.pendingSharingConsent?.endpoint.baseURL, "https://second.example")
    }

    func testSavedGatewayWithoutConsentDoesNotRestoreItsNetworkSession() async throws {
        let (consent, _, _) = isolatedStore()
        let saved = try profile("saved")
        let client = ModelGatewayClient()
        let model = makeModel(
            consent: consent,
            profiles: ModelGatewayStore(profiles: [saved], activeID: saved.id),
            client: client
        )

        await model.restoreSavedGateway()

        XCTAssertEqual(model.pendingSharingConsent?.profileID, saved.id)
        XCTAssertNil(model.connectedProfile)
        XCTAssertEqual(model.legacyToken, "")
        let before = await client.connections
        XCTAssertTrue(before.isEmpty)
        await model.approveSharingConsent()
        let after = await client.connections
        XCTAssertEqual(after.map(\.token), [saved.token])
        XCTAssertEqual(model.connectedProfile, saved)
    }

    func testSwitchNeedsConsentForTheOtherGatewayAndCancelKeepsCurrentGateway() async throws {
        let (consent, _, _) = isolatedStore()
        let first = try profile("first"), second = try profile("second")
        consent.accept(for: first.endpoint)
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, client: client)
        model.savedGateways = [first, second]
        model.activeGatewayID = first.id
        model.connectedProfile = first
        model.state = .connected

        await model.useGateway(id: second.id)
        XCTAssertEqual(model.pendingSharingConsent?.profileID, second.id)
        model.cancelSharingConsent()

        XCTAssertEqual(model.connectedProfile, first)
        XCTAssertEqual(model.activeGatewayID, first.id)
        XCTAssertFalse(consent.isAccepted(for: second.endpoint))
        let connections = await client.connections
        XCTAssertTrue(connections.isEmpty)
    }

    func testRemovedSavedProfileCannotBeApprovedFromStaleRequest() async throws {
        let (consent, _, _) = isolatedStore()
        let saved = try profile("saved")
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, client: client)
        model.savedGateways = [saved]
        model.state = .idle
        await model.useGateway(id: saved.id)
        model.savedGateways = []

        await model.approveSharingConsent()

        XCTAssertFalse(consent.isAccepted(for: saved.endpoint))
        let connections = await client.connections
        XCTAssertTrue(connections.isEmpty)
    }

    func testRevocationDisconnectsAndRequiresFreshConsent() async throws {
        let (consent, _, _) = isolatedStore()
        let saved = try profile("saved")
        consent.accept(for: saved.endpoint)
        let client = ModelGatewayClient()
        let model = makeModel(consent: consent, client: client)
        let recorder = ModelGatewaySwitchRecorder(needsConfirmation: false)
        let withdrawalRecorder = ModelGatewaySwitchRecorder(needsConfirmation: false)
        model.installGatewayWillConnectHandler { recorder.recordWillConnect($0) }
        model.installSharingConsentRevokedHandler { withdrawalRecorder.recordWillConnect(nil) }
        model.savedGateways = [saved]
        model.activeGatewayID = saved.id
        model.connectedProfile = saved
        model.state = .reconnecting
        model.isHermesVoiceSheetVisible = true
        model.pendingSignIn = .init(connection: saved.connection, name: saved.name, profile: saved)
        model.gatewaySignInURL = URL(string: "https://saved.example/login")
        model.signInFixtureHTML = "fixture"
        model.legacyToken = "unsent-secret"

        await model.revokeSharingConsent()

        XCTAssertNil(model.connectedProfile)
        XCTAssertNil(model.pendingSignIn)
        XCTAssertNil(model.gatewaySignInURL)
        XCTAssertNil(model.signInFixtureHTML)
        XCTAssertFalse(model.isHermesVoiceSheetVisible)
        XCTAssertTrue(model.isSettingsVisible)
        XCTAssertEqual(model.legacyToken, "")
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(recorder.willConnectIDs.count, 1)
        XCTAssertNil(recorder.willConnectIDs[0])
        XCTAssertEqual(withdrawalRecorder.willConnectIDs.count, 1)
        XCTAssertFalse(consent.isAccepted(for: saved.endpoint))
        let closes = await client.closeCount
        XCTAssertEqual(closes, 1)
        await model.useGateway(id: saved.id)
        XCTAssertNotNil(model.pendingSharingConsent)
        let connections = await client.connections
        XCTAssertTrue(connections.isEmpty)
    }

    func testRevocationFencesAConnectionAlreadyInFlight() async throws {
        let (consent, _, _) = isolatedStore()
        let target = try endpoint("https://gateway.example")
        consent.accept(for: target)
        let client = ModelSuspendedGatewayClient()
        let profiles = ModelGatewayStore()
        let model = makeModel(consent: consent, profiles: profiles, client: client)
        model.dashboardURL = target.baseURL
        let connecting = Task { await model.connect() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await client.isWaiting), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let waiting = await client.isWaiting
        XCTAssertTrue(waiting)
        await model.revokeSharingConsent()
        await client.finishConnect()
        await connecting.value

        XCTAssertNil(model.connectedProfile)
        XCTAssertEqual(model.state, .idle)
        let saved = await profiles.savedConnections
        XCTAssertTrue(saved.isEmpty)
    }

    func testConsentIsCanonicalPrefixScopedVersionedAndContainsNoEndpointText() throws {
        let (consent, defaults, suite) = isolatedStore()
        let target = try endpoint("https://GATEWAY.example:443/hermes/")
        consent.accept(for: target)

        XCTAssertTrue(consent.isAccepted(for: try endpoint("https://gateway.example/hermes")))
        XCTAssertFalse(consent.isAccepted(for: try endpoint("https://gateway.example/other")))
        XCTAssertFalse(consent.isAccepted(for: try endpoint("https://gateway.example")))
        XCTAssertFalse(GatewaySharingConsentStore(defaults: defaults, version: 2).isAccepted(for: target))
        let data = try JSONSerialization.data(withJSONObject: defaults.persistentDomain(forName: suite) ?? [:])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("gateway.example"))
        consent.revokeAll()
        XCTAssertFalse(GatewaySharingConsentStore(defaults: defaults).isAccepted(for: target))
        let newer = GatewaySharingConsentStore(defaults: defaults, version: 2)
        newer.accept(for: target)
        XCTAssertTrue(newer.isAccepted(for: target))
        XCTAssertFalse(consent.isAccepted(for: target))
        consent.revokeAll()
        XCTAssertFalse(newer.isAccepted(for: target))
    }

    func testStaleConnectionFailureCannotCloseNewlyApprovedConnection() async throws {
        let (consent, _, _) = isolatedStore()
        let target = try endpoint("https://gateway.example")
        consent.accept(for: target)
        let client = ConsentRaceGatewayClient()
        let model = makeModel(consent: consent, client: client)
        model.dashboardURL = target.baseURL
        let oldConnection = Task { await model.connect() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await client.isWaiting), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let waiting = await client.isWaiting
        XCTAssertTrue(waiting)
        await model.revokeSharingConsent()
        await model.connect()
        await model.approveSharingConsent()
        XCTAssertTrue(model.isConnected)
        let before = await client.closeCount

        await client.finishOldConnection()
        await oldConnection.value

        let after = await client.closeCount
        XCTAssertEqual(after, before)
        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.errorMessage)
    }

    func testStaleSavedGatewaySuccessCannotReplaceNewlyApprovedSelection() async throws {
        let (consent, _, _) = isolatedStore()
        let first = try profile("first"), second = try profile("second")
        consent.accept(for: first.endpoint)
        let profiles = ModelGatewayStore(profiles: [first, second])
        let client = ConsentRaceGatewayClient()
        let model = makeModel(consent: consent, profiles: profiles, client: client)
        model.savedGateways = [first, second]
        let oldConnection = Task { await model.useGateway(id: first.id) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await client.isWaiting), ContinuousClock.now < deadline {
            await Task.yield()
        }
        let waiting = await client.isWaiting
        XCTAssertTrue(waiting)
        await model.revokeSharingConsent()
        await model.useGateway(id: second.id)
        await model.approveSharingConsent()
        XCTAssertEqual(model.connectedProfile, second)

        await client.finishOldConnection(success: true)
        await oldConnection.value

        let selections = await profiles.selectedIDs
        let persistedActiveID = await profiles.currentActiveID
        XCTAssertEqual(selections, [second.id])
        XCTAssertEqual(persistedActiveID, second.id)
        XCTAssertEqual(model.connectedProfile, second)
        XCTAssertEqual(model.activeGatewayID, second.id)
    }

    private func isolatedStore() -> (GatewaySharingConsentStore, UserDefaults, String) {
        let suite = "NileSharingConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (GatewaySharingConsentStore(defaults: defaults), defaults, suite)
    }

    private func makeModel(
        consent: any GatewaySharingConsentStoring,
        profiles: ModelGatewayStore = ModelGatewayStore(),
        client: any GatewayConnecting = ModelGatewayClient()
    ) -> GatewaySetupModel {
        GatewaySetupModel(
            arguments: [], profileStore: profiles, sharingConsentStore: consent,
            connectionClient: client, automaticallyRestore: false
        )
    }

    private func endpoint(_ url: String) throws -> GatewayEndpoint {
        try GatewayEndpoint.parse(url)
    }

    private func profile(_ name: String) throws -> GatewayProfile {
        try GatewayProfile(id: name, name: name, baseURL: "https://\(name).example", token: "saved-token")
    }
}
