import XCTest
@testable import Nile

@MainActor
final class VoiceCoordinatorTests: XCTestCase {
    func testVoiceDraftCoordinatorJoinsAgainstOneExactBase() {
        let input = RecordingVoiceInput()
        let coordinator = VoiceInputCoordinator(input: input)

        coordinator.start(composer: "note:  ")

        XCTAssertEqual(input.starts, 1)
        XCTAssertTrue(coordinator.eventsAreEnabled)
        XCTAssertEqual(
            coordinator.transition(event: .preparing),
            .preparing
        )
        XCTAssertEqual(
            coordinator.transition(
                event: .listening(
                    partialText: "check the battery"
                )
            ),
            .listening(composer: "note: check the battery")
        )
        XCTAssertEqual(
            coordinator.transition(
                event: .listening(partialText: "   ")
            ),
            .listening(composer: "note:  ")
        )
        XCTAssertEqual(
            coordinator.transition(event: .transcribing),
            .transcribing
        )
        XCTAssertEqual(
            coordinator.transition(
                event: .finished(text: "final words")
            ),
            .finished(composer: "note: final words")
        )

        coordinator.finishEvents()
        XCTAssertFalse(coordinator.eventsAreEnabled)
        XCTAssertNil(
            coordinator.transition(
                event: .finished(text: "late")
            )
        )
    }

    func testVoiceDraftCancelRejectsOldCallbacksAndRestoresErrors() {
        let input = RecordingVoiceInput(isAvailable: false)
        let coordinator = VoiceInputCoordinator(input: input)
        XCTAssertFalse(coordinator.isAvailable)

        coordinator.start(composer: "draft with spaces  ")
        XCTAssertEqual(
            coordinator.transition(
                event: .error(message: "recognizer failed")
            ),
            .error(
                composer: "draft with spaces  ",
                message: "recognizer failed"
            )
        )
        coordinator.cancel()
        XCTAssertEqual(input.cancels, 1)
        XCTAssertNil(
            coordinator.transition(
                event: .listening(partialText: "late")
            )
        )

        coordinator.start(composer: "read-only apply")
        coordinator.cancelAdapter()
        coordinator.stop()
        XCTAssertEqual(input.cancels, 2)
        XCTAssertEqual(input.stops, 1)
        XCTAssertEqual(
            coordinator.transition(
                event: .finished(text: "still admitted")
            ),
            .finished(
                composer: "read-only apply still admitted"
            )
        )
    }

    func testHermesVoiceRequestReplacementFencesLateGatewayResult() async throws {
        let firstGate = VoiceCoordinatorGate()
        let secondGate = VoiceCoordinatorGate()
        let results = HermesVoiceResultCollector()
        let coordinator = HermesVoiceCoordinator(
            loadVoice: {
                await firstGate.wait()
                return HermesVoiceConfig(
                    provider: "old",
                    voice: "old-voice"
                )
            },
            updateVoice: { provider, voice in
                await secondGate.wait()
                return HermesVoiceConfig(
                    provider: provider,
                    voice: voice
                )
            }
        )

        coordinator.load(
            gatewayID: "gateway-old",
            onStarted: {},
            onResult: { result in
                Task { await results.append(result) }
            }
        )
        coordinator.update(
            gatewayID: "gateway-new",
            expectedProvider: "edge",
            voice: "en-US-AriaNeural",
            onStarted: {},
            onResult: { result in
                Task { await results.append(result) }
            }
        )

        await firstGate.open()
        await secondGate.open()
        for _ in 0..<100 {
            if await results.count == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let values = await results.values
        XCTAssertEqual(values.count, 1)
        guard case let .success(request, config) = values[0] else {
            return XCTFail("Expected the replacement request to succeed")
        }
        XCTAssertEqual(request.gatewayID, "gateway-new")
        XCTAssertTrue(coordinator.isCurrent(request))
        XCTAssertEqual(
            config,
            HermesVoiceConfig(
                provider: "edge",
                voice: "en-US-AriaNeural"
            )
        )
    }
}

@MainActor
final class TalkModeCoordinatorTests: XCTestCase {
    func testPartialsNeverEnterTalkUIStateAndFinalCreatesOneTurn() {
        let coordinator = TalkModeCoordinator()
        let mode = coordinator.begin(owner: owner())
        XCTAssertEqual(
            coordinator.state,
            TalkUIState(phase: .preparingInput)
        )
        XCTAssertTrue(coordinator.markListening(mode))
        XCTAssertTrue(
            coordinator.observePartial(
                mode,
                text: "private partial words"
            )
        )
        XCTAssertEqual(
            coordinator.state,
            TalkUIState(phase: .listening)
        )

        guard case let .submit(turn, text) =
            coordinator.finishRecognition(
                mode,
                text: "  hello Hermes  "
            ) else {
            return XCTFail("Expected a submit decision")
        }
        XCTAssertEqual(text, "hello Hermes")
        XCTAssertTrue(coordinator.currentTurn() === turn)
        XCTAssertEqual(
            coordinator.state,
            TalkUIState(phase: .submitting)
        )
        XCTAssertTrue(coordinator.isCurrent(turn))
        guard case .ignored = coordinator.finishRecognition(
            mode,
            text: "duplicate callback"
        ) else {
            return XCTFail("Duplicate transcript was admitted")
        }
    }

    func testProviderNeutralTranscribingPrecedesSubmission() {
        let coordinator = TalkModeCoordinator()
        let mode = coordinator.begin(owner: owner())
        XCTAssertTrue(coordinator.markListening(mode))
        XCTAssertTrue(coordinator.markTranscribing(mode))
        XCTAssertEqual(coordinator.state.phase, .transcribing)

        guard case let .submit(_, text) =
            coordinator.finishRecognition(
                mode,
                text: "backend transcript"
            ) else {
            return XCTFail("Expected submission")
        }
        XCTAssertEqual(text, "backend transcript")
        XCTAssertEqual(coordinator.state.phase, .submitting)
    }

    func testThreeConsecutiveBlankResultsPauseAndAcceptedTurnResets() {
        let coordinator = TalkModeCoordinator()
        let expectedOwner = owner()
        let mode = coordinator.begin(owner: expectedOwner)
        XCTAssertTrue(coordinator.markListening(mode))

        for _ in 0..<2 {
            guard case let .relisten(request) =
                coordinator.finishRecognition(mode, text: " ") else {
                return XCTFail("Expected relisten")
            }
            guard case let .start(startedMode) =
                coordinator.claimRelisten(
                    request,
                    currentOwner: expectedOwner,
                    canListen: true
                ) else {
                return XCTFail("Expected microphone restart")
            }
            XCTAssertTrue(startedMode === mode)
            XCTAssertTrue(coordinator.markListening(mode))
        }
        guard case let .paused(message) =
            coordinator.finishRecognition(mode, text: "") else {
            return XCTFail("Expected blank-loop pause")
        }
        XCTAssertEqual(
            message,
            TalkModeCoordinator.repeatedBlankResultsMessage
        )
        XCTAssertEqual(coordinator.state.phase, .paused)
        XCTAssertNil(coordinator.currentTurn())
    }

    func testTurnProgressionAndReplacementGenerationRejectStaleTokens() {
        let coordinator = TalkModeCoordinator()
        let firstMode = coordinator.begin(owner: owner())
        XCTAssertTrue(coordinator.markListening(firstMode))
        guard case let .submit(firstTurn, _) =
            coordinator.finishRecognition(
                firstMode,
                text: "first"
            ) else {
            return XCTFail("Expected turn")
        }

        XCTAssertFalse(coordinator.markSpeaking(firstTurn))
        XCTAssertTrue(coordinator.markWorking(firstTurn))
        XCTAssertTrue(
            coordinator.markPreparingSpeech(firstTurn)
        )
        XCTAssertTrue(coordinator.markSpeaking(firstTurn))
        XCTAssertEqual(coordinator.state.phase, .speaking)

        let replacement = coordinator.begin(
            owner: owner(liveSessionID: "live-2")
        )
        XCTAssertFalse(firstMode === replacement)
        XCTAssertFalse(coordinator.isCurrent(firstMode))
        XCTAssertFalse(coordinator.isCurrent(firstTurn))
        XCTAssertFalse(coordinator.markWorking(firstTurn))
        XCTAssertEqual(coordinator.state.phase, .preparingInput)
    }

    func testRelistenAndResumeRevalidateOwnerAndIdleGuard() {
        let coordinator = TalkModeCoordinator()
        let expectedOwner = owner()
        let mode = coordinator.begin(owner: expectedOwner)
        XCTAssertTrue(coordinator.markListening(mode))
        guard case let .submit(turn, _) =
            coordinator.finishRecognition(mode, text: "hello") else {
            return XCTFail("Expected turn")
        }
        XCTAssertTrue(coordinator.markWorking(turn))
        XCTAssertTrue(coordinator.markPreparingSpeech(turn))
        XCTAssertTrue(coordinator.markSpeaking(turn))
        let request = try! XCTUnwrap(
            coordinator.requestRelistenAfterTurn(turn)
        )

        guard case let .paused(message) =
            coordinator.claimRelisten(
                request,
                currentOwner: expectedOwner,
                canListen: false,
                unavailableMessage: "Hermes is still busy"
            ) else {
            return XCTFail("Expected pause")
        }
        XCTAssertEqual(message, "Hermes is still busy")

        guard case .paused = coordinator.resume(
            mode,
            currentOwner: expectedOwner,
            canListen: false,
            unavailableMessage: "Still busy"
        ) else {
            return XCTFail("Expected paused resume")
        }
        guard case let .start(resumed) = coordinator.resume(
            mode,
            currentOwner: expectedOwner,
            canListen: true
        ) else {
            return XCTFail("Expected resume")
        }
        XCTAssertTrue(resumed === mode)
        XCTAssertTrue(coordinator.markListening(mode))
    }

    func testOwnerMismatchAndStaleRelistenCannotOpenMicrophone() {
        let coordinator = TalkModeCoordinator()
        let mode = coordinator.begin(owner: owner())
        XCTAssertTrue(coordinator.markListening(mode))
        guard case let .relisten(request) =
            coordinator.finishRecognition(mode, text: "") else {
            return XCTFail("Expected relisten")
        }
        guard case .invalidated = coordinator.claimRelisten(
            request,
            currentOwner: owner(liveSessionID: "replacement"),
            canListen: true
        ) else {
            return XCTFail("Owner mismatch was not invalidated")
        }
        XCTAssertEqual(coordinator.state, TalkUIState())
        XCTAssertFalse(coordinator.isCurrent(mode))

        let oldMode = coordinator.begin(owner: owner())
        XCTAssertTrue(coordinator.markListening(oldMode))
        guard case let .relisten(oldRequest) =
            coordinator.finishRecognition(oldMode, text: "") else {
            return XCTFail("Expected old relisten")
        }
        let replacement = coordinator.begin(
            owner: owner(liveSessionID: "live-2")
        )
        guard case .ignored = coordinator.claimRelisten(
            oldRequest,
            currentOwner: owner(),
            canListen: true
        ) else {
            return XCTFail("Stale relisten affected replacement")
        }
        XCTAssertTrue(coordinator.isCurrent(replacement))
    }

    func testPauseEndAndOwnershipAuditAreGenerationCorrelated() {
        let coordinator = TalkModeCoordinator()
        let oldMode = coordinator.begin(owner: owner())
        XCTAssertTrue(coordinator.markListening(oldMode))
        guard case let .submit(oldTurn, _) =
            coordinator.finishRecognition(oldMode, text: "first") else {
            return XCTFail("Expected old turn")
        }
        let currentMode = coordinator.begin(
            owner: owner(liveSessionID: "live-2")
        )
        XCTAssertTrue(coordinator.markListening(currentMode))
        guard case let .submit(currentTurn, _) =
            coordinator.finishRecognition(
                currentMode,
                text: "second"
            ) else {
            return XCTFail("Expected current turn")
        }

        XCTAssertFalse(
            coordinator.pauseTurn(oldTurn, message: "stale")
        )
        XCTAssertFalse(coordinator.end(oldMode))
        XCTAssertTrue(
            coordinator.pauseTurn(
                currentTurn,
                message: "submit was queued"
            )
        )
        XCTAssertEqual(coordinator.state.phase, .paused)
        XCTAssertTrue(coordinator.end(currentMode))
        XCTAssertEqual(coordinator.state, TalkUIState())

        let auditMode = coordinator.begin(owner: owner())
        XCTAssertFalse(
            coordinator.invalidateIfOwnerChanged(
                currentOwner: owner()
            )
        )
        XCTAssertTrue(coordinator.isCurrent(auditMode))
        XCTAssertTrue(
            coordinator.invalidateIfOwnerChanged(
                currentOwner: nil
            )
        )
        XCTAssertFalse(coordinator.isCurrent(auditMode))
    }

    private func owner(
        liveSessionID: String = "live-1"
    ) -> TalkOwner {
        TalkOwner(
            connectionGeneration: 7,
            gatewayID: "gateway-1",
            gatewayKey: "http://gateway.example/",
            selectedSessionID: "stored-1",
            transcriptSessionID: "stored-1",
            liveSessionID: liveSessionID
        )
    }
}

private final class RecordingVoiceInput:
    VoiceInput,
    @unchecked Sendable
{
    let isAvailable: Bool
    let events: AsyncStream<VoiceInputEvent>
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        events = AsyncStream { _ in }
    }

    func start() { starts += 1 }
    func stop() { stops += 1 }
    func cancel() { cancels += 1 }
}

private actor HermesVoiceResultCollector {
    private(set) var values: [HermesVoiceResult] = []
    var count: Int { values.count }

    func append(_ result: HermesVoiceResult) {
        values.append(result)
    }
}

private actor VoiceCoordinatorGate {
    private var openState = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !openState else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        openState = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
