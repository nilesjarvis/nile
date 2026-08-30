import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testEmptyFixtureOffersAndCreatesANewSession() async {
        let model = SessionListModel(fixture: .empty)

        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.selectedSessionID)
        XCTAssertTrue(model.canCreateSession)
        XCTAssertFalse(model.hasDraftWithoutOpenSession)

        model.composer = "preserved draft"
        XCTAssertTrue(model.hasDraftWithoutOpenSession)

        await model.createSession()

        XCTAssertEqual(model.sessions.map(\.id), ["fixture-created"])
        XCTAssertEqual(model.sessions.first?.title, "New session")
        XCTAssertEqual(model.selectedSessionID, "fixture-created")
        XCTAssertEqual(model.liveSession?.liveID, "live-fixture-created")
        XCTAssertTrue(model.showsComposer)
        XCTAssertFalse(model.hasDraftWithoutOpenSession)
    }

    func testCreateSessionAvailabilityEnforcesBusyAndConnectionGuards() {
        let model = SessionListModel(fixture: .empty)

        XCTAssertTrue(model.canCreateSession)
        model.connectionPhase = .offline
        XCTAssertFalse(model.canCreateSession)
        model.connectionPhase = .online
        model.isOpeningSession = true
        XCTAssertFalse(model.canCreateSession)
        model.isOpeningSession = false
        model.isGoalMutating = true
        XCTAssertFalse(model.canCreateSession)
        model.isGoalMutating = false
        model.state = .loading
        XCTAssertFalse(model.canCreateSession)
    }

    func testCreateSessionExplainsSecondaryMutationGuards() async {
        let model = SessionListModel(fixture: .empty)

        model.isUpdatingSessionControls = true
        await model.createSession()
        XCTAssertEqual(
            model.operationError,
            "Wait for the model setting to finish before creating a session."
        )
        XCTAssertTrue(model.sessions.isEmpty)

        model.isUpdatingSessionControls = false
        model.isGoalMutating = true
        await model.createSession()
        XCTAssertEqual(
            model.operationError,
            "Wait for the goal update to finish before creating a session."
        )
        XCTAssertTrue(model.sessions.isEmpty)

        model.isGoalMutating = false
        model.isAttaching = true
        await model.createSession()
        XCTAssertEqual(
            model.operationError,
            "Wait for the photo to finish before creating a session."
        )
        XCTAssertTrue(model.sessions.isEmpty)
    }

    func testCreateSessionCallsRepositoryAndSelectsListedSession() async {
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: nil)

        XCTAssertTrue(model.canCreateSession)
        await model.createSession()

        let createCallCount = await repository.callCount("session.create")
        XCTAssertEqual(createCallCount, 1)
        XCTAssertEqual(model.sessions.map(\.id), ["new"])
        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.liveSession?.liveID, "live-new")
        XCTAssertTrue(model.showsComposer)
    }

    func testCreateSessionRetainsLivePlaceholderUntilHermesListsFirstTurn() async {
        let ticks = AsyncStream<Void>.makeStream()
        let repository = SessionRepositoryStub(
            sessions: [],
            createAppearsInSessionList: false
        )
        let model = SessionListModel(
            repository: repository,
            refreshTicks: ticks.stream
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: nil)

        await model.createSession()

        XCTAssertEqual(model.sessions.map(\.id), ["new"])
        XCTAssertEqual(model.sessions.first?.title, "New session")
        XCTAssertEqual(model.sessions.first?.source, "niles")
        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.liveSession?.liveID, "live-new")
        XCTAssertTrue(model.showsComposer)

        ticks.continuation.yield()
        await eventuallyAsync {
            await repository.callCount("session.list") == 3
        }
        XCTAssertEqual(model.sessions.map(\.id), ["new"])
        XCTAssertTrue(model.showsComposer)

        await repository.replaceSessions([
            session(id: "new", title: "Persisted first turn", source: "niles"),
        ])
        ticks.continuation.yield()
        await eventuallyAsync {
            await repository.callCount("session.list") == 4
                && model.sessions.first?.title == "Persisted first turn"
        }
        XCTAssertTrue(model.showsComposer)
    }

    func testCreateSessionParksLiveComposerAndPhotoDraftUnderOldOwner()
        async throws {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let composerStore = ComposerDraftStoreStub()
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            draftStore: composerStore,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("park this draft")
        model.attachImageData(imageFixtureData())
        await eventually {
            model.pendingAttachments.count == 1 && !model.isAttaching
        }
        let parkedAttachment = try XCTUnwrap(model.pendingAttachments.first)

        await model.createSession()

        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.composer, "")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        await model.selectSession(id: "one")
        XCTAssertEqual(model.composer, "park this draft")
        XCTAssertEqual(model.pendingAttachments, [parkedAttachment])
        let composerRecord = await composerStore.record(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        XCTAssertEqual(composerRecord?.text, "park this draft")
        let attachmentSnapshot = await attachmentStore.snapshot()
        XCTAssertEqual(
            attachmentSnapshot.drafts.first {
                $0.storedSessionID == "one"
            }?.attachments,
            [parkedAttachment]
        )
    }

    func testCreateSessionStopsBeforeRPCWhenDraftProtectionFails() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let composerStore = ComposerDraftStoreStub(failsUpdates: true)
        let model = SessionListModel(
            repository: repository,
            draftStore: composerStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("keep this local")

        await model.createSession()

        let createCallCount = await repository.callCount("session.create")
        XCTAssertEqual(createCallCount, 0)
        XCTAssertEqual(model.selectedSessionID, "one")
        XCTAssertEqual(model.composer, "keep this local")
        XCTAssertFalse(model.isOpeningSession)
        XCTAssertEqual(
            model.operationError,
            "Nile could not save this draft before creating a session."
        )
    }

    func testSessionCreateSwipeOnlyArmsAtConnectedCollapsedStartEdge() {
        XCTAssertTrue(
            SessionCreateSwipePolicy.canBegin(
                collapsed: true,
                atStartEdge: true,
                sessionCount: 1,
                canCreateSession: true
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.canBegin(
                collapsed: false,
                atStartEdge: true,
                sessionCount: 1,
                canCreateSession: true
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.canBegin(
                collapsed: true,
                atStartEdge: false,
                sessionCount: 1,
                canCreateSession: true
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.canBegin(
                collapsed: true,
                atStartEdge: true,
                sessionCount: 0,
                canCreateSession: true
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.canBegin(
                collapsed: true,
                atStartEdge: true,
                sessionCount: 1,
                canCreateSession: false
            )
        )
    }

    func testSessionCreateSwipeClaimsOnlyDominantRightwardMotion() {
        XCTAssertTrue(
            SessionCreateSwipePolicy.shouldClaim(
                translation: CGSize(width: 30, height: 4)
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.shouldClaim(
                translation: CGSize(width: -30, height: 4)
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.shouldClaim(
                translation: CGSize(width: 12, height: 20)
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.shouldClaim(
                translation: CGSize(width: 8, height: 0)
            )
        )
    }

    func testSessionCreateSwipeCommitsAtEdgeOrFastFling() {
        XCTAssertTrue(
            SessionCreateSwipePolicy.shouldCreate(
                fingerX: 340,
                stripWidth: 400,
                velocityX: 0
            )
        )
        XCTAssertTrue(
            SessionCreateSwipePolicy.shouldCreate(
                fingerX: 300,
                stripWidth: 400,
                velocityX: 501
            )
        )
        XCTAssertFalse(
            SessionCreateSwipePolicy.shouldCreate(
                fingerX: 300,
                stripWidth: 400,
                velocityX: 500
            )
        )
        XCTAssertEqual(
            SessionCreateSwipePolicy.resistedOffset(
                currentOffset: 0,
                delta: 100,
                pillWidth: 170
            ),
            45,
            accuracy: 0.001
        )
    }

    func testSessionExpandSwipeClaimsOnlyDominantDownwardMotion() {
        XCTAssertTrue(
            SessionExpandSwipePolicy.shouldExpand(
                translation: CGSize(width: 4, height: 30)
            )
        )
        XCTAssertFalse(
            SessionExpandSwipePolicy.shouldExpand(
                translation: CGSize(width: 30, height: 4)
            )
        )
        XCTAssertFalse(
            SessionExpandSwipePolicy.shouldExpand(
                translation: CGSize(width: 4, height: -30)
            )
        )
        XCTAssertFalse(
            SessionExpandSwipePolicy.shouldExpand(
                translation: CGSize(width: 0, height: 10)
            )
        )
    }

    func testLoadListsStatusesAndOpensPreferredSessionOncePerGateway() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            statuses: ["two": "working"]
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "two")
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.sessions.map(\.id), ["one", "two"])
        XCTAssertEqual(model.activeStatuses, ["two": "working"])
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertEqual(model.liveSession?.liveID, "live-two")
        XCTAssertEqual(model.state, .loaded)
        let calls = await repository.calls
        XCTAssertEqual(calls.filter { $0 == "session.list" }.count, 1)
        XCTAssertEqual(calls.filter { $0 == "session.resume:two" }.count, 1)
    }

    func testMissingPreferredSessionFallsBackToFirstListedSession() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "first", source: "niles")]
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "missing")

        XCTAssertEqual(model.selectedSessionID, "first")
        XCTAssertEqual(model.liveSession?.storedID, "first")
    }

}
