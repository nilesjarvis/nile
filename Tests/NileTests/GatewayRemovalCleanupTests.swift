import XCTest
@testable import Nile

@MainActor
final class GatewayRemovalCleanupTests: XCTestCase {
    func testFailedDraftErasureStillErasesPinsAndKeepsProfileForRetry() async throws {
        let profile = try GatewayProfile(
            id: "gateway",
            name: "Saved gateway",
            baseURL: "https://example.com",
            token: "fixture-token"
        )
        let profileStore = ModelGatewayStore(profiles: [profile])
        let draftStore = FailingRemovalDraftStore()
        let pinStore = GatewaySessionPinStore(
            pinsByGateway: [profile.id: ["session"]]
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: profileStore,
            composerDraftStore: draftStore,
            sessionPinStore: pinStore,
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        model.state = .idle
        model.savedGateways = [profile]

        await model.removeGateway(id: profile.id)

        let retained = await profileStore.load()
        let pins = await pinStore.load(gatewayID: profile.id)
        XCTAssertEqual(retained.profiles, [profile])
        XCTAssertEqual(model.savedGateways, [profile])
        XCTAssertTrue(pins.isEmpty)
        XCTAssertTrue(model.errorMessage?.contains("retry Remove gateway") == true)

        await draftStore.allowRemoval()
        await model.removeGateway(id: profile.id)

        let removed = await profileStore.load()
        XCTAssertTrue(removed.profiles.isEmpty)
        XCTAssertTrue(model.savedGateways.isEmpty)
        XCTAssertEqual(model.state, .idle)
        let attempts = await draftStore.removalAttempts
        XCTAssertEqual(attempts, 2)
    }
}

private actor FailingRemovalDraftStore: ComposerDraftStoring {
    var removalAttempts = 0
    private var fails = true

    func load() -> [PersistedComposerDraft] { [] }
    func update(_ draft: PersistedComposerDraft) -> Bool { true }
    func migrate(_ changes: [ComposerDraftMigrationChange]) -> Bool { true }
    func removeGateway(id: String) throws {
        removalAttempts += 1
        if fails { throw ComposerDraftStoreError.storageAccess }
    }
    func allowRemoval() { fails = false }
}
