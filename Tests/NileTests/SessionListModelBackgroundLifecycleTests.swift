import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testAcceptedTurnTracksExactOwnerAndCompletesFromStream() async {
        let controller = RecordingBackgroundController()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            backgroundController: controller
        )
        var educationRequests = 0
        model.installBackgroundTurnStartedHandler {
            educationRequests += 1
        }
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("Run the checks")
        XCTAssertTrue(model.sendMessage())

        let target = BackgroundTurnTarget(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )
        XCTAssertEqual(controller.events, [.started(target)])
        XCTAssertEqual(educationRequests, 1)

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Done",
                usage: nil
            )
        )
        await eventually {
            controller.events == [.started(target), .completed(target)]
        }

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Duplicate",
                usage: nil
            )
        )
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            controller.events,
            [.started(target), .completed(target)]
        )
    }

    func testDefiniteSubmitFailureStopsButUncertainFailureKeepsTracking()
        async
    {
        let definiteController = RecordingBackgroundController()
        let definiteRepository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError("rejected", retryable: false)
        )
        let definiteModel = SessionListModel(
            repository: definiteRepository,
            backgroundController: definiteController
        )
        await definiteModel.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        definiteModel.updateComposer("Definite")
        XCTAssertTrue(definiteModel.sendMessage())
        await eventually {
            definiteController.events.count == 2
        }
        let definiteTarget = BackgroundTurnTarget(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )
        XCTAssertEqual(
            definiteController.events,
            [.started(definiteTarget), .stopped(definiteTarget)]
        )

        let uncertainController = RecordingBackgroundController()
        let uncertainRepository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "connection dropped",
                retryable: true,
                isConnectionFailure: true
            )
        )
        let uncertainModel = SessionListModel(
            repository: uncertainRepository,
            backgroundController: uncertainController
        )
        await uncertainModel.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        uncertainModel.updateComposer("Uncertain")
        XCTAssertTrue(uncertainModel.sendMessage())
        await eventually { uncertainModel.operationError != nil }
        XCTAssertEqual(
            uncertainController.events,
            [.started(definiteTarget)]
        )
    }

    func testRetryableConnectionLossKeepsTurnAndTerminalLossStopsIt() async {
        let controller = RecordingBackgroundController()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            backgroundController: controller
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.updateComposer("Keep tracking")
        XCTAssertTrue(model.sendMessage())
        let target = BackgroundTurnTarget(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )

        await repository.yield(
            .connectionLost(
                message: "offline",
                authRejected: false,
                retryable: true
            )
        )
        await eventually { model.connectionPhase == .reconnecting }
        XCTAssertEqual(controller.events, [.started(target)])

        await repository.yield(
            .connectionLost(
                message: "closed",
                authRejected: false,
                retryable: false
            )
        )
        await eventually {
            controller.events == [.started(target), .stopped(target)]
        }
    }

    func testStatusRefreshReconcilesAttachedTurnMissingCompletionEvent() async {
        let ticks = AsyncStream<Void>.makeStream()
        let controller = RecordingBackgroundController()
        let inflight = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: true,
            status: "working",
            inflight: InflightTurn(user: "Keep tracking", assistant: "Working")
        )
        let completed = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [HermesMessage(role: "assistant", text: "Finished")],
            running: false,
            status: "idle",
            inflight: nil
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            statuses: ["one": "working"],
            openedSessions: [inflight, completed]
        )
        let model = SessionListModel(
            repository: repository,
            refreshTicks: ticks.stream,
            backgroundController: controller
        )
        model.onAppForegroundChanged(true)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        let target = BackgroundTurnTarget(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )

        await repository.setStatuses([:])
        ticks.continuation.yield()
        await eventuallyAsync {
            let activeListCalls = await repository.callCount(
                "session.active_list"
            )
            let resumeCalls = await repository.callCount("session.resume:one")
            return activeListCalls == 2
                && resumeCalls == 2
                && !model.isSending
        }

        XCTAssertEqual(
            model.transcriptEntries.compactMap { entry in
                guard case let .message(message) = entry else {
                    return nil
                }
                return message.content
            },
            ["Finished"]
        )
        XCTAssertEqual(
            controller.events,
            [.foregroundChanged(true), .started(target), .completed(target)]
        )
    }

    func testResumedInflightTurnStartsAndIdleReconnectReconcilesIt() async {
        let controller = RecordingBackgroundController()
        let inflight = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: true,
            status: "working",
            inflight: InflightTurn(user: "Run", assistant: "Working")
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            statuses: ["one": "working"],
            openedSessions: [inflight, liveSession(id: "one")]
        )
        let model = SessionListModel(
            repository: repository,
            backgroundController: controller
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        let target = BackgroundTurnTarget(
            gatewayID: "gateway-1",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )
        XCTAssertEqual(controller.events, [.started(target)])

        await repository.yield(
            .connectionLost(
                message: "offline",
                authRejected: false,
                retryable: true
            )
        )
        await eventually { model.connectionPhase == .reconnecting }
        await repository.setStatuses([:])
        let restored = await model.restoreAfterReconnect(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        XCTAssertTrue(restored)

        XCTAssertEqual(
            controller.events,
            [.started(target), .completed(target)]
        )
    }

    func testAppForegroundLifecycleIsForwardedToBackgroundController() {
        let controller = RecordingBackgroundController()
        let model = SessionListModel(
            fixture: .androidBrand,
            backgroundController: controller
        )

        model.onAppForegroundChanged(true)
        model.onAppForegroundChanged(false)
        model.onAppForegroundChanged(true)

        XCTAssertEqual(
            controller.events,
            [
                .foregroundChanged(true),
                .foregroundChanged(false),
                .foregroundChanged(true),
            ]
        )
    }

    func testForegroundReconcilesSelectedTurnWithAuthoritativeCompletion() async {
        let inflight = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: true,
            status: "working",
            inflight: InflightTurn(user: "Run", assistant: "Working")
        )
        let completed = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [
                HermesMessage(role: "user", text: "Run"),
                HermesMessage(role: "assistant", text: "Completed while away"),
            ],
            running: false,
            status: "idle",
            inflight: nil
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            statuses: ["one": "working"],
            openedSessions: [inflight, completed]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.onSessionSurfaceHidden()
        model.onAppForegroundChanged(true)

        await eventuallyAsync {
            await repository.callCount("session.resume:one") == 2
                && !model.isSending
        }
        XCTAssertEqual(model.transcriptEntries.compactMap { entry in
            guard case let .message(message) = entry else {
                return nil
            }
            return message.content
        }, ["Run", "Completed while away"])
    }

}
