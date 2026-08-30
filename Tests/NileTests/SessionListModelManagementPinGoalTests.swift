import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testRenameSessionTrimsUpdatesSelectedTitleAndClosesDialog() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.setRenameDialogVisible(true)
        model.renameCurrentSession("  Release notes  ")

        await eventually { !model.isRenamingSession }
        let renameCallCount = await repository.callCount(
            "session.title:live-one:Release notes"
        )
        XCTAssertEqual(renameCallCount, 1)
        XCTAssertEqual(model.sessions.first?.title, "Release notes")
        XCTAssertFalse(model.isRenameDialogVisible)
        XCTAssertNil(model.renameSessionError)
    }

    func testRenameFailureStaysLocalAndKeepsDialogOpen() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            renameError: HermesError(
                "Rename rejected",
                retryable: false
            )
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.operationError = "Send outcome is still uncertain"

        model.setRenameDialogVisible(true)
        model.renameCurrentSession("Edited title")

        await eventually { !model.isRenamingSession }
        XCTAssertTrue(model.isRenameDialogVisible)
        XCTAssertEqual(model.sessions.first?.title, "one")
        XCTAssertEqual(model.renameSessionError, "Rename rejected")
        XCTAssertEqual(
            model.operationError,
            "Send outcome is still uncertain"
        )
    }

    func testLateRenameCompletionCannotMutateAnotherSession() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            blockRename: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setRenameDialogVisible(true)
        model.renameCurrentSession("Stale title")
        await eventuallyAsync {
            await repository.callCount(
                "session.title:live-one:Stale title"
            ) == 1
        }

        await model.selectSession(id: "two")
        await repository.releaseRename()
        await Task.yield()

        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertEqual(
            model.sessions.first { $0.id == "one" }?.title,
            "one"
        )
        XCTAssertEqual(
            model.sessions.first { $0.id == "two" }?.title,
            "two"
        )
        XCTAssertFalse(model.isRenameDialogVisible)
        XCTAssertFalse(model.isRenamingSession)
        XCTAssertNil(model.renameSessionError)
    }

    func testRenameDialogIsUnavailableForOfflineAndReadOnlySessions() async {
        let writable = SessionListModel(fixture: .androidBrand)
        writable.setConnectionRecoveryPhase(.offline)
        writable.setRenameDialogVisible(true)
        XCTAssertFalse(writable.isRenameDialogVisible)

        let readOnly = SessionListModel(fixture: .terminalBusy)
        readOnly.setRenameDialogVisible(true)
        XCTAssertFalse(readOnly.isRenameDialogVisible)
    }

    func testSessionRenameForwarderPublishesNestedRuntimeObservation()
        async
    {
        let model = SessionListModel(fixture: .androidBrand)
        let changed = expectation(
            description: "Session management observation changed"
        )

        withObservationTracking {
            _ = model.isRenameDialogVisible
        } onChange: {
            changed.fulfill()
        }

        model.setRenameDialogVisible(true)

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(model.isRenameDialogVisible)
    }

    func testSessionMediaForwarderPublishesNestedRuntimeObservation() async {
        let downloaded = DownloadedAttachment(
            path: "/tmp/report.pdf",
            filename: "report.pdf",
            mimeType: "application/pdf",
            bytes: Data("pdf".utf8)
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            downloadedAttachment: downloaded
        )
        let cache = BlockingFirstAttachmentCacheStub()
        let model = SessionListModel(
            repository: repository,
            attachmentCache: cache
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        let changed = expectation(
            description: "Session media observation changed"
        )

        withObservationTracking {
            _ = model.isOpeningAttachment
        } onChange: {
            changed.fulfill()
        }

        model.openAttachment(path: downloaded.path)

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(model.isOpeningAttachment)
        await cache.releaseFirst()
        await eventually { !model.isOpeningAttachment }
    }

    func testSessionPinsRestorePerGatewayAndPrioritizeTheCollapsedStrip()
        async
    {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ]
        )
        let pinStore = SessionPinStoreStub(
            pinsByGateway: ["gateway-1": ["two"]]
        )
        let model = SessionListModel(
            repository: repository,
            sessionPinStore: pinStore
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.pinnedSessionIDs, ["two"])
        XCTAssertEqual(model.collapsedSessions.map(\.id), ["two", "one"])
    }

    func testSessionPinToggleIsOptimisticAndPersistsTheDesiredValue() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let pinStore = SessionPinStoreStub()
        let model = SessionListModel(
            repository: repository,
            sessionPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.togglePin(id: "one")

        XCTAssertEqual(model.pinnedSessionIDs, ["one"])
        await eventuallyAsync {
            await pinStore.pins(gatewayID: "gateway-1") == ["one"]
        }
        let calls = await pinStore.setCalls()
        XCTAssertEqual(calls, ["gateway-1:one:true"])
    }

    func testSessionPinWriteFailureRollsBackOnlyTheMatchingIntent() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let pinStore = SessionPinStoreStub(
            setError: HermesError("Disk full", retryable: false)
        )
        let model = SessionListModel(
            repository: repository,
            sessionPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.togglePin(id: "one")

        XCTAssertEqual(model.pinnedSessionIDs, ["one"])
        await eventually { model.pinnedSessionIDs.isEmpty }
        XCTAssertEqual(
            model.operationError,
            "Could not save the session pin: Disk full"
        )
    }

    func testRapidSessionPinTapsPersistInFIFOOrder() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let pinStore = SessionPinStoreStub(blockFirstSet: true)
        let writeQueue = SessionPinWriteQueue(store: pinStore)
        let model = SessionListModel(
            repository: repository,
            sessionPinStore: pinStore,
            sessionPinWriteQueue: writeQueue
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.togglePin(id: "one")
        model.togglePin(id: "one")
        XCTAssertTrue(model.pinnedSessionIDs.isEmpty)
        await eventuallyAsync {
            await pinStore.setCalls() == ["gateway-1:one:true"]
        }

        await pinStore.releaseFirstSet()

        await eventuallyAsync {
            await pinStore.setCalls() == [
                "gateway-1:one:true",
                "gateway-1:one:false",
            ]
        }
        let persistedPins = await pinStore.pins(gatewayID: "gateway-1")
        XCTAssertTrue(persistedPins.isEmpty)
        XCTAssertTrue(model.pinnedSessionIDs.isEmpty)
    }

    func testLateSessionPinFailureCannotRollbackAnotherGateway() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let pinStore = SessionPinStoreStub(
            setError: HermesError("Disk full", retryable: false),
            blockFirstSet: true
        )
        let model = SessionListModel(
            repository: repository,
            sessionPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.togglePin(id: "one")
        await eventuallyAsync {
            await pinStore.setCalls() == ["gateway-1:one:true"]
        }

        await model.load(gatewayID: "gateway-2", preferredSessionID: "one")
        await pinStore.releaseFirstSet()
        await eventuallyAsync {
            await pinStore.completedSetCount() == 1
        }
        await Task.yield()

        XCTAssertTrue(model.pinnedSessionIDs.isEmpty)
        XCTAssertNil(model.operationError)
    }

    func testGoalRestoresForOpenedSessionAndMarksAvailability() async {
        let expected = HermesGoal(
            objective: "Finish release",
            phase: .paused,
            turnsUsed: 4,
            maxTurns: 20,
            pausedReason: "user-paused"
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            goalFeatureEnabled: true,
            goal: expected
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.goalAvailability, .available)
        XCTAssertEqual(model.goal, expected)
        let calls = await repository.calls
        XCTAssertTrue(calls.contains("goal.status:live-one"))
    }

    func testGoalStartPreservesComposerAndSubmitsKickoff() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            goalFeatureEnabled: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("keep this ordinary draft")
        model.setGoalSheetVisible(true)

        model.startGoal("Fix and verify the current issue", maxTurns: 10)

        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:Fix and verify the current issue"
            ) == 1
        }
        XCTAssertEqual(model.composer, "keep this ordinary draft")
        XCTAssertEqual(model.goal?.objective, "Fix and verify the current issue")
        XCTAssertEqual(model.goal?.maxTurns, 10)
        XCTAssertTrue(model.isSending)
        XCTAssertFalse(model.isGoalSheetVisible)
        let messages = model.transcriptEntries.compactMap {
            entry -> TranscriptMessage? in
            guard case let .message(message) = entry else {
                return nil
            }
            return message
        }
        XCTAssertEqual(messages.last?.isGoalPrompt, true)
    }

    func testGoalMutationPreventsSessionOwnershipChange() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            goalFeatureEnabled: true,
            blockGoalMutation: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.startGoal("Ship safely", maxTurns: nil)
        await eventually { model.isGoalMutating }
        await eventuallyAsync {
            await repository.callCount(
                "goal.set:live-one:Ship safely:default"
            ) == 1
        }
        await model.selectSession(id: "two")

        XCTAssertEqual(model.selectedSessionID, "one")
        XCTAssertTrue(model.isGoalMutating)
        XCTAssertEqual(
            model.operationError,
            "Wait for the standing goal update to finish before switching sessions."
        )
        await repository.releaseGoalMutation()
        await eventually { !model.isGoalMutating && model.isSending }
    }

    func testGoalCompletionWaitsForAuthoritativeStatus() async {
        let active = HermesGoal(
            objective: "Finish only after verification",
            phase: .active,
            turnsUsed: 0,
            maxTurns: 5
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [
                LiveSession(
                    liveID: "live-one",
                    storedID: "one",
                    info: SessionInfo(model: nil, provider: nil),
                    messages: [],
                    running: true,
                    status: "working",
                    inflight: nil
                ),
            ],
            goalFeatureEnabled: true,
            goal: active
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await repository.yield(
            .goalUpdate(
                sessionID: "live-one",
                text: "✓ Goal achieved: verified",
                update: GoalProgressUpdate(
                    phase: .finished,
                    reason: "verified"
                )
            )
        )
        await eventually { model.isGoalFinalizing }
        XCTAssertEqual(model.goal?.phase, .active)

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "verified",
                usage: nil
            )
        )
        await eventually { model.goal?.phase == .checking }
        XCTAssertFalse(model.isSending)
    }

    func testGoalForwarderPublishesNestedRuntimeObservation() async {
        let model = SessionListModel(fixture: .empty)
        let changed = expectation(description: "Goal observation changed")

        withObservationTracking {
            _ = model.goal
        } onChange: {
            changed.fulfill()
        }

        model.goal = HermesGoal(
            objective: "Observe runtime state",
            phase: .active,
            turnsUsed: 0,
            maxTurns: 5
        )

        await fulfillment(of: [changed], timeout: 1)
    }

    func testLateGoalMutationCannotReplaceDisconnectedOwner() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            goalFeatureEnabled: true,
            blockGoalMutation: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.startGoal("Do not cross owners", maxTurns: 5)
        await eventually { model.isGoalMutating }
        await eventuallyAsync {
            await repository.callCount(
                "goal.set:live-one:Do not cross owners:5"
            ) == 1
        }

        await repository.yield(
            .connectionLost(
                message: "connection lost",
                authRejected: false,
                retryable: true
            )
        )
        await eventually { model.state == .failed("connection lost") }
        await repository.releaseGoalMutation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(model.goalAvailability, .unknown)
        XCTAssertNil(model.goal)
        XCTAssertFalse(model.isGoalMutating)
        XCTAssertFalse(model.isGoalSheetVisible)
    }

    func testGoalPauseAndClearStayWithinGoalRuntime() async {
        let active = HermesGoal(
            objective: "Finish safely",
            phase: .active,
            turnsUsed: 2,
            maxTurns: 10
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            goalFeatureEnabled: true,
            goal: active
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.pauseGoal()
        await eventually {
            model.goal?.phase == .paused && !model.isGoalMutating
        }
        model.clearGoal()
        await eventually { model.goal == nil && !model.isGoalMutating }

        let calls = await repository.calls
        XCTAssertTrue(calls.contains("goal.pause:live-one"))
        XCTAssertTrue(calls.contains("goal.clear:live-one"))
    }

    func testGoalResumeSubmitsObjectiveThroughModelTurnBoundary() async {
        let paused = HermesGoal(
            objective: "Resume through the turn boundary",
            phase: .paused,
            turnsUsed: 2,
            maxTurns: 10,
            pausedReason: "user-paused"
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            goalFeatureEnabled: true,
            goal: paused
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.resumeGoal()

        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:Resume through the turn boundary"
            ) == 1
        }
        XCTAssertEqual(model.goal?.phase, .active)
        XCTAssertTrue(model.isSending)
        XCTAssertFalse(model.isGoalSheetVisible)
    }

}
