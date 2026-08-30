import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testPromptSendOptimisticallyClearsDraftAndStreamsToCompletion() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("  hello Nile  ")
        XCTAssertTrue(model.sendMessage())

        XCTAssertEqual(model.composer, "")
        XCTAssertTrue(model.isSending)
        XCTAssertNotNil(model.turnStartedAt)
        XCTAssertTrue(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.role == .user
                    && message.content == "hello Nile"
                    && !message.pending
            }
        )
        await eventuallyAsync {
            await repository.callCount("prompt.submit:live-one:hello Nile") == 1
        }

        await repository.yield(.messageStart(sessionID: "live-one"))
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "Hello")
        )
        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Hello back",
                usage: nil
            )
        )
        await eventually {
            !model.isSending
                && model.turnStartedAt == nil
                && model.transcriptEntries.contains {
                    guard case let .message(message) = $0 else {
                        return false
                    }
                    return message.role == .assistant
                        && message.content == "Hello back"
                }
        }
    }

    func testMidTurnSendQueuesSteerGhostUntilTurnCompletes() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("run the build")
        XCTAssertTrue(model.sendMessage())
        model.updateComposer("also check lint")
        XCTAssertTrue(model.sendMessage())

        await eventuallyAsync {
            await repository.callCount("session.steer:live-one:also check lint") == 1
        }
        XCTAssertEqual(model.composer, "")
        XCTAssertTrue(model.isSending)
        XCTAssertTrue(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.content == "also check lint" && message.pending
            }
        )

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "done",
                usage: nil
            )
        )
        await eventually {
            !model.isSending
                && !model.transcriptEntries.contains {
                    guard case let .message(message) = $0 else {
                        return false
                    }
                    return message.pending
                }
        }
    }

    func testRejectedSteerRestoresAheadOfTextTypedWhileRequestWaits() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            steerAccepted: false,
            blockSteer: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("run the build")
        XCTAssertTrue(model.sendMessage())
        model.updateComposer("also run lint")
        XCTAssertTrue(model.sendMessage())
        await eventuallyAsync {
            await repository.callCount("session.steer:live-one:also run lint") == 1
        }

        model.updateComposer("new draft")
        await repository.releaseSteer()
        await eventually {
            model.composer == "also run lint\n\nnew draft"
        }

        XCTAssertTrue(model.isSending)
        XCTAssertTrue(
            model.operationError?.contains("was not queued") == true
        )
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.pending
            }
        )
        XCTAssertTrue(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.role == .system
                    && message.isError
                    && message.content.contains("was restored")
            }
        )
    }

    func testFailedPromptRestoresAheadOfNewDraftAndRemovesOptimisticRow() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError("submit rejected", retryable: false),
            blockSubmit: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("failed input")
        XCTAssertTrue(model.sendMessage())
        await eventuallyAsync {
            await repository.callCount("prompt.submit:live-one:failed input") == 1
        }
        model.updateComposer("new draft")
        await repository.releaseSubmit()
        await eventually {
            model.composer == "failed input\n\nnew draft"
        }

        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.operationError, "submit rejected")
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.role == .user
                    && message.content == "failed input"
            }
        )
    }

    func testStopRunUsesInterruptAndSettlesBusyPresentation() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            blockInterrupt: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("run")
        XCTAssertTrue(model.sendMessage())

        model.stopActiveRun()
        XCTAssertTrue(model.isStopping)
        await eventuallyAsync {
            await repository.callCount("session.interrupt:live-one") == 1
        }
        await repository.releaseInterrupt()
        await eventually {
            !model.isStopping && !model.isSending
        }

        XCTAssertNil(model.turnStartedAt)
        XCTAssertTrue(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.role == .system
                    && message.content == "stop requested"
            }
        )
    }

    func testStaleStopAcknowledgementCannotStopTheNextTurn() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            blockInterrupt: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("first turn")
        XCTAssertTrue(model.sendMessage())
        model.stopActiveRun()
        await eventuallyAsync {
            await repository.callCount("session.interrupt:live-one") == 1
        }
        XCTAssertTrue(model.isStopping)

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "first done",
                usage: nil
            )
        )
        await eventually {
            !model.isSending && !model.isStopping
        }

        model.updateComposer("second turn")
        XCTAssertTrue(model.sendMessage())
        XCTAssertTrue(model.isSending)
        await repository.releaseInterrupt()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(model.isSending)
        XCTAssertFalse(model.isStopping)
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.role == .system
                    && message.content == "stop requested"
            }
        )
    }

    func testComposerDraftsRemainIsolatedPerGatewaySessionOwner() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("draft one")

        await model.selectSession(id: "two")
        XCTAssertEqual(model.composer, "")
        model.updateComposer("draft two")

        await model.selectSession(id: "one")
        XCTAssertEqual(model.composer, "draft one")
        await model.selectSession(id: "two")
        XCTAssertEqual(model.composer, "draft two")
    }

    func testProtectedDraftRestoresOnceForItsGatewaySessionOwner() async {
        let stored = PersistedComposerDraft(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            revision: 4,
            text: "recover this",
            updatedAtMilliseconds: 100
        )
        let draftStore = ComposerDraftStoreStub(records: [stored])
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: draftStore
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.composer, "recover this")
        XCTAssertEqual(
            model.operationError,
            "Unsent draft restored from this device. If Nile closed during Send, check the conversation before resending."
        )

        await model.selectSession(id: "one")
        XCTAssertEqual(model.composer, "recover this")
        XCTAssertNil(model.operationError)
    }

    func testTombstonedDraftDoesNotReappearAfterProcessRestoration() async {
        let tombstone = PersistedComposerDraft(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            revision: 5,
            text: "",
            updatedAtMilliseconds: 101
        )
        let draftStore = ComposerDraftStoreStub(records: [tombstone])
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: draftStore
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.composer, "")
        XCTAssertNil(model.operationError)
    }

    func testSendFlushesDraftBeforeRemoteMutationThenPersistsTombstone() async {
        let draftStore = ComposerDraftStoreStub()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: draftStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("durable send")
        XCTAssertTrue(model.sendMessage())

        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:durable send"
            ) == 1
        }
        await eventuallyAsync {
            await draftStore.updatedTexts == ["durable send", ""]
        }

        let latest = await draftStore.record(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        XCTAssertEqual(latest?.text, "")
        XCTAssertEqual(latest?.revision, 2)
    }

    func testDraftPersistenceFailurePreventsRemoteMutationAndRestoresInput() async {
        let draftStore = ComposerDraftStoreStub(failsUpdates: true)
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: draftStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("must survive")
        XCTAssertTrue(model.sendMessage())

        await eventually {
            model.composer == "must survive" && !model.isSending
        }
        let submitCalls = await repository.callCount(
            "prompt.submit:live-one:must survive"
        )
        XCTAssertEqual(submitCalls, 0)
        XCTAssertEqual(
            model.operationError,
            "Nile could not safely save this draft, so it was not sent. Your message was restored."
        )
    }

    func testNewDraftTypedDuringSendSurvivesOldDraftRetirement() async {
        let draftStore = ComposerDraftStoreStub()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            blockSubmit: true
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: draftStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("first")
        XCTAssertTrue(model.sendMessage())
        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:first"
            ) == 1
        }

        model.updateComposer("second")
        model.flushDrafts()
        await eventuallyAsync {
            await draftStore.record(
                gatewayID: "gateway-1",
                storedSessionID: "one"
            )?.text == "second"
        }
        await repository.releaseSubmit()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(model.composer, "second")
        let latest = await draftStore.record(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        let updatedTexts = await draftStore.updatedTexts
        XCTAssertEqual(latest?.text, "second")
        XCTAssertFalse(updatedTexts.contains(""))
    }

}
