import XCTest
@testable import Nile

@MainActor
final class SharingConsentSessionRaceTests: XCTestCase {
    func testWithdrawalDuringDraftRestoreDoesNotStartGatewayRequests() async {
        let repository = makeRepository()
        let boundary = ConsentSuspendedBoundary()
        await boundary.arm()
        let model = SessionListModel(
            repository: repository,
            draftStore: ConsentSuspendedDraftStore(boundary: boundary)
        )
        let loading = Task { await model.load(gatewayID: "gateway", preferredSessionID: "one") }
        await waitUntil { await boundary.isWaiting }

        model.stopForSharingConsentWithdrawal()
        let withdrawnState = model.state
        await boundary.release()
        await loading.value

        let calls = await repository.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.state, withdrawnState)
        XCTAssertNil(model.liveSession)
    }

    func testWithdrawalDuringCatalogLoadCannotReopenSessionOrPublishCatalog() async {
        let repository = makeRepository()
        let boundary = ConsentSuspendedBoundary()
        await boundary.arm()
        let services = ConsentSuspendedServices(catalogBoundary: boundary)
        let model = SessionListModel(repository: ConsentSessionCapabilities(base: repository, services: services))
        let loading = Task { await model.load(gatewayID: "gateway", preferredSessionID: "one") }
        await waitUntil { await boundary.isWaiting && model.sessions.count == 1 }

        model.stopForSharingConsentWithdrawal()
        let withdrawnState = model.state
        await boundary.release()
        await loading.value

        let resumes = await repository.callCount("session.resume:one")
        XCTAssertEqual(resumes, 0)
        XCTAssertEqual(model.state, withdrawnState)
        XCTAssertNil(model.runtimes.commandRuntime.catalog)
        XCTAssertNil(model.liveSession)
        await model.load(gatewayID: "gateway", preferredSessionID: "one")
        XCTAssertEqual(model.liveSession?.liveID, "live-one")
    }

    func testWithdrawalDuringSessionGoalReadPreservesFailedStateAndAllowsReopen() async {
        let repository = makeRepository()
        let boundary = ConsentSuspendedBoundary()
        await boundary.arm()
        let services = ConsentSuspendedServices(goalBoundary: boundary)
        let model = SessionListModel(repository: ConsentSessionCapabilities(base: repository, services: services))
        let loading = Task { await model.load(gatewayID: "gateway", preferredSessionID: "one") }
        await waitUntil { await boundary.isWaiting }
        XCTAssertEqual(model.liveSession?.liveID, "live-one")

        model.stopForSharingConsentWithdrawal()
        let withdrawnState = model.state
        await boundary.release()
        await loading.value

        XCTAssertEqual(model.state, withdrawnState)
        XCTAssertNil(model.liveSession)
        XCTAssertFalse(model.isOpeningSession)
        await model.load(gatewayID: "gateway", preferredSessionID: "one")
        let resumes = await repository.callCount("session.resume:one")
        XCTAssertEqual(resumes, 2)
        XCTAssertEqual(model.liveSession?.liveID, "live-one")
    }

    func testWithdrawalDuringCreatedSessionGoalReadCannotRestoreLoadedState() async {
        let repository = makeRepository()
        let boundary = ConsentSuspendedBoundary()
        let services = ConsentSuspendedServices(goalBoundary: boundary)
        let model = SessionListModel(repository: ConsentSessionCapabilities(base: repository, services: services))
        await model.load(gatewayID: "gateway", preferredSessionID: "one")
        await boundary.arm()
        let creating = Task { await model.createSession() }
        await waitUntil { await boundary.isWaiting }
        XCTAssertEqual(model.liveSession?.liveID, "live-new")

        model.stopForSharingConsentWithdrawal()
        let withdrawnState = model.state
        await boundary.release()
        await creating.value

        XCTAssertEqual(model.state, withdrawnState)
        XCTAssertNil(model.liveSession)
        XCTAssertFalse(model.isOpeningSession)
        await model.load(gatewayID: "gateway", preferredSessionID: "new")
        XCTAssertEqual(model.liveSession?.liveID, "live-new")
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("The suspended operation did not reach its expected boundary")
    }

    private func makeRepository() -> SessionRepositoryStub {
        SessionRepositoryStub(sessions: [
            HermesSession(
                id: "one", title: "One", preview: nil, source: "niles",
                messageCount: 0, startedAt: nil, lastMessageAt: nil
            ),
        ])
    }
}

private actor ConsentSuspendedBoundary {
    private var isArmed = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func arm() { isArmed = true }

    func waitIfArmed() async {
        guard isArmed else { return }
        isArmed = false
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

private struct ConsentSuspendedServices: HermesCommandServing, HermesGoalServing {
    var catalogBoundary: ConsentSuspendedBoundary?
    var goalBoundary: ConsentSuspendedBoundary?

    func commandsCatalog() async throws -> CommandCatalog {
        await catalogBoundary?.waitIfArmed()
        return CommandCatalog(categories: [], skillCommands: [])
    }

    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        await goalBoundary?.waitIfArmed()
        return nil
    }
}

private struct ConsentSuspendedDraftStore: ComposerDraftStoring {
    let boundary: ConsentSuspendedBoundary
    func load() async throws -> [PersistedComposerDraft] {
        await boundary.waitIfArmed()
        return []
    }
    func update(_ draft: PersistedComposerDraft) async throws -> Bool { true }
    func migrate(_ changes: [ComposerDraftMigrationChange]) async throws -> Bool { true }
    func removeGateway(id: String) async throws {}
}

private struct ConsentSessionCapabilities: SessionRepositoryCapabilityProviding {
    let base: SessionRepositoryStub
    let services: ConsentSuspendedServices

    var sessionCapabilities: SessionRepositoryCapabilities {
        SessionRepositoryCapabilities(
            events: base, sessions: base, sessionClaim: base,
            sessionRenaming: base, turns: base, talk: base,
            delegation: base, blockingPrompts: base, models: base,
            sessionUsage: base, gatewayStatistics: base,
            attachmentReading: base, attachmentMutating: base,
            prompts: base, disconnect: base, transcription: base,
            speechSynthesis: base, commands: services, goals: services
        )
    }
}
