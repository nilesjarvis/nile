import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testTerminalSelectionNeverResumesOrClaimsWritableRuntime() async {
        let stored = HermesMessage(role: "assistant", text: "stored history")
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "mobile", source: "niles"),
                session(id: "terminal", source: "cli"),
            ],
            histories: ["terminal": [stored]]
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "mobile")
        await model.selectSession(id: "terminal")

        XCTAssertEqual(model.selectedSessionID, "terminal")
        XCTAssertNil(model.liveSession)
        XCTAssertTrue(model.isReadOnlySession)
        XCTAssertEqual(model.storedMessages, [stored])
        let calls = await repository.calls
        XCTAssertTrue(calls.contains("history:terminal"))
        XCTAssertFalse(calls.contains("session.resume:terminal"))
    }

    func testMissingListedSourceIsLookedUpBeforeChoosingHistoryOrResume() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "terminal", source: ""),
                session(id: "mobile", source: ""),
            ],
            sources: ["terminal": "tui", "mobile": "cron"],
            histories: [
                "terminal": [HermesMessage(role: "assistant", text: "mirror")],
            ]
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")
        XCTAssertTrue(model.isReadOnlySession)
        XCTAssertEqual(model.storedMessages.map(\.text), ["mirror"])

        await model.selectSession(id: "mobile")
        XCTAssertFalse(model.isReadOnlySession)
        XCTAssertEqual(model.liveSession?.liveID, "live-mobile")

        let calls = await repository.calls
        XCTAssertTrue(calls.contains("source:terminal"))
        XCTAssertTrue(calls.contains("history:terminal"))
        XCTAssertTrue(calls.contains("source:mobile"))
        XCTAssertTrue(calls.contains("session.resume:mobile"))
        XCTAssertFalse(calls.contains("session.resume:terminal"))
    }

    func testBlankSourceLookupFailsClosedWithoutResuming() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "unknown", source: "")],
            sources: ["unknown": " "]
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "unknown")

        XCTAssertEqual(
            model.operationError,
            "Could not determine who owns the stored session"
        )
        XCTAssertNil(model.liveSession)
        let calls = await repository.calls
        XCTAssertFalse(calls.contains("session.resume:unknown"))
        XCTAssertFalse(calls.contains("history:unknown"))
    }

    func testFiveSecondTickRefreshesTerminalListStatusAndDurableHistoryOnly() async {
        let ticks = AsyncStream<Void>.makeStream()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "terminal", source: "cli")],
            histories: [
                "terminal": [HermesMessage(role: "assistant", text: "first")],
            ]
        )
        let model = SessionListModel(
            repository: repository,
            refreshTicks: ticks.stream
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")
        await repository.setHistory(
            [HermesMessage(role: "assistant", text: "second")],
            for: "terminal"
        )
        ticks.continuation.yield()

        await eventuallyAsync {
            await repository.callCount("history:terminal") == 2
                && model.storedMessages.map(\.text) == ["second"]
        }
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "session.resume:terminal" }.count,
            0
        )
        XCTAssertEqual(calls.filter { $0 == "session.list" }.count, 2)
        XCTAssertEqual(calls.filter { $0 == "session.active_list" }.count, 2)
    }

    func testClaimRechecksBusyStatusAndNeverResumesUnsafeTerminal() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "terminal", source: "cli")],
            statuses: ["terminal": "waiting"]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")

        await model.claimCurrentSession()

        XCTAssertTrue(model.isReadOnlySession)
        XCTAssertFalse(model.isClaimingSession)
        XCTAssertEqual(
            model.operationError,
            "The terminal session is still working. Stop its current turn, then try Claim again."
        )
        let calls = await repository.calls
        XCTAssertTrue(calls.contains("session.status:terminal"))
        XCTAssertFalse(calls.contains("session.resume:terminal"))
    }

    func testClaimRechecksAfterDialogPreviewBecauseRuntimeCanBecomeBusy() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "terminal", source: "cli")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")

        model.setClaimDialogVisible(true)
        await eventuallyAsync {
            await repository.callCount("session.status:terminal") == 1
        }
        XCTAssertTrue(model.isClaimDialogVisible)
        XCTAssertNil(model.selectedSessionRuntime)

        await repository.setStatuses(["terminal": "starting"])
        await model.claimCurrentSession()

        XCTAssertTrue(model.isReadOnlySession)
        XCTAssertEqual(model.selectedSessionRuntime, .starting)
        XCTAssertEqual(
            model.operationError,
            "The terminal session is still working. Stop its current turn, then try Claim again."
        )
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "session.status:terminal" }.count,
            2
        )
        XCTAssertFalse(calls.contains("session.resume:terminal"))
    }

    func testSuccessfulClaimOverridesRememberedTerminalOwnership() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "terminal", source: "cli")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")

        await model.claimCurrentSession()

        XCTAssertFalse(model.isReadOnlySession)
        XCTAssertEqual(model.liveSession?.liveID, "live-terminal")
        XCTAssertTrue(model.storedMessages.isEmpty)

        await model.selectSession(id: "terminal")
        XCTAssertFalse(model.isReadOnlySession)
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "session.resume:terminal" }.count,
            2
        )
        XCTAssertEqual(
            calls.filter { $0 == "history:terminal" }.count,
            1
        )
    }

    func testSessionSwitchRetainsOnlyOutgoingPresentationUntilReady()
        async
    {
        let outgoingMessage = HermesMessage(
            role: "assistant",
            text: "Outgoing private conversation"
        )
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: ""),
            ],
            openedSessions: [
                LiveSession(
                    liveID: "live-one",
                    storedID: "one",
                    info: SessionInfo(model: nil, provider: nil),
                    messages: [outgoingMessage],
                    running: false,
                    status: "idle",
                    inflight: nil
                ),
            ],
            blockSourceLookup: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        let outgoingEntries = model.transcriptEntries

        let selection = Task {
            await model.selectSession(id: "two")
        }
        await eventuallyAsync {
            await repository.callCount("source:two") == 1
        }

        XCTAssertTrue(model.isOpeningSession)
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertTrue(model.transcriptEntries.isEmpty)
        XCTAssertNil(model.liveSession)
        XCTAssertEqual(
            model.sessionSwitchPresentation,
            SessionSwitchPresentation(
                sessionID: "one",
                entries: outgoingEntries,
                scrollOwner: TranscriptScrollOwner(
                    gatewayID: "gateway-1",
                    sessionID: "one"
                ),
                delegationTurns: [],
                pinnedDelegationTurnID: nil,
                activeTodos: nil,
                isSending: false
            )
        )
        XCTAssertEqual(model.sessionSettleGeneration, 0)

        await repository.resolveBlockedSource("niles")
        await selection.value

        XCTAssertFalse(model.isOpeningSession)
        XCTAssertNil(model.sessionSwitchPresentation)
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertEqual(model.liveSession?.liveID, "live-two")
        XCTAssertEqual(model.sessionSettleGeneration, 1)
    }

    func testStaleSourceLookupCannotReplaceNewerSelection() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "unknown", source: ""),
                session(id: "mobile", source: "niles"),
            ],
            blockSourceLookup: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "mobile")

        let staleSelection = Task {
            await model.selectSession(id: "unknown")
        }
        await eventuallyAsync {
            await repository.callCount("source:unknown") == 1
        }
        await model.selectSession(id: "mobile")
        await repository.resolveBlockedSource("cli")
        await staleSelection.value

        XCTAssertEqual(model.selectedSessionID, "mobile")
        XCTAssertEqual(model.liveSession?.liveID, "live-mobile")
        XCTAssertFalse(model.isReadOnlySession)
        let calls = await repository.calls
        XCTAssertFalse(calls.contains("history:unknown"))
        XCTAssertFalse(calls.contains("session.resume:unknown"))
    }

    func testFilteringMatchesRenderedSourceAndPriorityIsStable() {
        let model = SessionListModel(fixture: .showcase)

        XCTAssertEqual(
            model.displayedSessions.map(\.id),
            ["release", "gateway", "brand", "cli"]
        )
        model.togglePin(id: "cli")
        XCTAssertEqual(
            model.displayedSessions.map(\.id),
            ["cli", "release", "gateway", "brand"]
        )
        model.searchText = "terminal"
        XCTAssertEqual(model.displayedSessions.map(\.id), ["cli"])
        model.searchText = "TOKEN-handling"
        XCTAssertEqual(model.displayedSessions.map(\.id), ["gateway"])
    }

    func testLoadFailureIsVisibleAndRetryPerformsFreshRequest() async {
        let repository = SessionRepositoryStub(
            sessions: [],
            listError: HermesError("list failed", retryable: true)
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: nil)
        XCTAssertEqual(model.state, .failed("list failed"))

        await model.retry(gatewayID: "gateway-1", preferredSessionID: nil)
        let calls = await repository.calls
        XCTAssertEqual(calls.filter { $0 == "session.list" }.count, 2)
    }

    func testSameGatewayRetryPreservesRememberedTerminalOwnership() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "terminal", source: "cli")],
            histories: [
                "terminal": [HermesMessage(role: "assistant", text: "mirror")],
            ]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "terminal")

        await repository.yield(
            .connectionLost(
                message: "connection lost",
                authRejected: false,
                retryable: true
            )
        )
        await eventually {
            model.state == .failed("connection lost")
        }
        model.setClaimDialogVisible(true)
        await model.claimCurrentSession()

        XCTAssertFalse(model.isClaimDialogVisible)
        await repository.setSessions([
            session(id: "terminal", source: ""),
        ])

        await model.retry(
            gatewayID: "gateway-1",
            preferredSessionID: "terminal"
        )

        XCTAssertTrue(model.isReadOnlySession)
        XCTAssertEqual(model.storedMessages.map(\.text), ["mirror"])
        let calls = await repository.calls
        XCTAssertFalse(calls.contains("source:terminal"))
        XCTAssertFalse(calls.contains("session.resume:terminal"))
        XCTAssertEqual(
            calls.filter { $0 == "history:terminal" }.count,
            2
        )
    }

    func testConnectionLossFencesInFlightSourceLookup() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "unknown", source: "")],
            blockSourceLookup: true
        )
        let model = SessionListModel(repository: repository)

        let loading = Task {
            await model.load(
                gatewayID: "gateway-1",
                preferredSessionID: "unknown"
            )
        }
        await eventuallyAsync {
            await repository.callCount("source:unknown") == 1
        }
        await repository.yield(
            .connectionLost(
                message: "connection lost",
                authRejected: false,
                retryable: true
            )
        )
        await eventually {
            model.state == .failed("connection lost")
        }
        await repository.resolveBlockedSource("cli")
        await loading.value

        XCTAssertEqual(model.state, .failed("connection lost"))
        XCTAssertNil(model.liveSession)
        XCTAssertTrue(model.storedMessages.isEmpty)
        XCTAssertFalse(model.isOpeningSession)
        let calls = await repository.calls
        XCTAssertFalse(calls.contains("history:unknown"))
        XCTAssertFalse(calls.contains("session.resume:unknown"))
    }

}
