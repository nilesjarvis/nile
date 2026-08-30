import XCTest
@testable import Nile

@MainActor
final class SessionTurnRuntimeTests: XCTestCase {
    func testPromptPreparationAndAcceptedStatusUseNarrowCapability() async {
        let repository = TurnRepositoryStub(promptResult: .success(.queued))
        let runtime = SessionTurnRuntime(repository: repository)
        let probe = TurnRuntimeProbe()
        var preparationCount = 0

        XCTAssertTrue(
            runtime.sendPrompt(
                liveSessionID: "live-one",
                text: "first",
                prepare: {
                    preparationCount += 1
                    return false
                },
                onOutcome: { probe.promptOutcomes.append($0) }
            )
        )
        await eventually { probe.promptOutcomes.count == 1 }
        guard case .preparationFailed = probe.promptOutcomes[0] else {
            return XCTFail("Expected preparation failure")
        }
        var calls = await repository.calls
        XCTAssertEqual(calls, [])

        XCTAssertTrue(
            runtime.sendPrompt(
                liveSessionID: "live-one",
                text: "second",
                prepare: {
                    preparationCount += 1
                    return true
                },
                onOutcome: { probe.promptOutcomes.append($0) }
            )
        )
        await eventually { probe.promptOutcomes.count == 2 }

        guard case let .accepted(status) = probe.promptOutcomes[1] else {
            return XCTFail("Expected accepted prompt")
        }
        XCTAssertEqual(status, .queued)
        XCTAssertEqual(preparationCount, 2)
        calls = await repository.calls
        XCTAssertEqual(
            calls,
            [.prompt(liveSessionID: "live-one", text: "second")]
        )
    }

    func testPromptFailureClassificationIsFailClosed() async {
        let definiteRepository = TurnRepositoryStub(
            promptResult: .failure(
                HermesError("definitely rejected", retryable: false)
            )
        )
        let definiteRuntime = SessionTurnRuntime(
            repository: definiteRepository
        )
        let definiteProbe = TurnRuntimeProbe()
        _ = definiteRuntime.sendPrompt(
            liveSessionID: "live",
            text: "definite",
            prepare: { true },
            onOutcome: { definiteProbe.promptOutcomes.append($0) }
        )
        await eventually { definiteProbe.promptOutcomes.count == 1 }
        guard case let .failed(message, uncertain) =
            definiteProbe.promptOutcomes[0] else {
            return XCTFail("Expected definite failure")
        }
        XCTAssertEqual(message, "definitely rejected")
        XCTAssertFalse(uncertain)

        let uncertainRepository = TurnRepositoryStub(
            promptResult: .failure(
                HermesError(
                    "connection dropped",
                    retryable: true,
                    isConnectionFailure: true
                )
            )
        )
        let uncertainRuntime = SessionTurnRuntime(
            repository: uncertainRepository
        )
        let uncertainProbe = TurnRuntimeProbe()
        _ = uncertainRuntime.sendPrompt(
            liveSessionID: "live",
            text: "uncertain",
            prepare: { true },
            onOutcome: { uncertainProbe.promptOutcomes.append($0) }
        )
        await eventually { uncertainProbe.promptOutcomes.count == 1 }
        guard case let .failed(message, uncertain) =
            uncertainProbe.promptOutcomes[0] else {
            return XCTFail("Expected uncertain failure")
        }
        XCTAssertEqual(message, "connection dropped")
        XCTAssertTrue(uncertain)
    }

    func testSteerDistinguishesAcceptedRejectedAndPreparationFailure() async {
        let repository = TurnRepositoryStub(
            steerResults: [.success(false), .success(true)]
        )
        let runtime = SessionTurnRuntime(repository: repository)
        let probe = TurnRuntimeProbe()

        _ = runtime.sendSteer(
            liveSessionID: "live",
            text: "not sent",
            prepare: { false },
            onOutcome: { probe.steerOutcomes.append($0) }
        )
        await eventually { probe.steerOutcomes.count == 1 }
        guard case .preparationFailed = probe.steerOutcomes[0] else {
            return XCTFail("Expected preparation failure")
        }

        _ = runtime.sendSteer(
            liveSessionID: "live",
            text: "rejected",
            prepare: { true },
            onOutcome: { probe.steerOutcomes.append($0) }
        )
        await eventually { probe.steerOutcomes.count == 2 }
        guard case .rejected = probe.steerOutcomes[1] else {
            return XCTFail("Expected rejected steering")
        }

        _ = runtime.sendSteer(
            liveSessionID: "live",
            text: "accepted",
            prepare: { true },
            onOutcome: { probe.steerOutcomes.append($0) }
        )
        await eventually { probe.steerOutcomes.count == 3 }
        guard case .accepted = probe.steerOutcomes[2] else {
            return XCTFail("Expected accepted steering")
        }
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            [
                .steer(liveSessionID: "live", text: "rejected"),
                .steer(liveSessionID: "live", text: "accepted"),
            ]
        )
    }

    func testInvalidatedStopCannotSettleTheNextTurn() async {
        let repository = TurnRepositoryStub(blockInterrupt: true)
        let runtime = SessionTurnRuntime(repository: repository)
        let probe = TurnRuntimeProbe()

        XCTAssertTrue(
            runtime.stop(liveSessionID: "live") {
                probe.stopOutcomes.append($0)
            }
        )
        await eventuallyAsync { await repository.interruptStarted }
        runtime.invalidateStop(liveSessionID: "live")
        await repository.releaseInterrupt()
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(probe.stopOutcomes.isEmpty)

        XCTAssertTrue(
            runtime.stop(liveSessionID: "live") {
                probe.stopOutcomes.append($0)
            }
        )
        await eventually { probe.stopOutcomes.count == 1 }
        guard case .succeeded = probe.stopOutcomes[0] else {
            return XCTFail("Expected the replacement Stop to succeed")
        }
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            [.interrupt(liveSessionID: "live"), .interrupt(liveSessionID: "live")]
        )
    }

    func testResetCancelsBlockedWorkWithoutPublishingOutcomes() async {
        let repository = TurnRepositoryStub(blockPrompt: true)
        let runtime = SessionTurnRuntime(repository: repository)
        let probe = TurnRuntimeProbe()

        _ = runtime.sendPrompt(
            liveSessionID: "old-live",
            text: "old prompt",
            prepare: { true },
            onOutcome: { probe.promptOutcomes.append($0) }
        )
        await eventuallyAsync { await repository.promptStarted }

        runtime.reset()
        await repository.releasePrompt()
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(probe.promptOutcomes.isEmpty)
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<300 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<300 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class TurnRuntimeProbe {
    var promptOutcomes: [SessionTurnRuntime.PromptOutcome] = []
    var steerOutcomes: [SessionTurnRuntime.SteerOutcome] = []
    var stopOutcomes: [SessionTurnRuntime.StopOutcome] = []
}

private actor TurnRepositoryStub: HermesTurnServing {
    enum Call: Equatable, Sendable {
        case prompt(liveSessionID: String, text: String)
        case steer(liveSessionID: String, text: String)
        case interrupt(liveSessionID: String)
    }

    private let promptResult: Result<PromptSubmitStatus, HermesError>
    private var steerResults: [Result<Bool, HermesError>]
    private var shouldBlockPrompt: Bool
    private var shouldBlockInterrupt: Bool
    private var promptContinuation: CheckedContinuation<Void, Never>?
    private var interruptContinuation: CheckedContinuation<Void, Never>?
    private(set) var calls: [Call] = []

    init(
        promptResult: Result<PromptSubmitStatus, HermesError> =
            .success(.streaming),
        steerResults: [Result<Bool, HermesError>] = [.success(true)],
        blockPrompt: Bool = false,
        blockInterrupt: Bool = false
    ) {
        self.promptResult = promptResult
        self.steerResults = steerResults
        shouldBlockPrompt = blockPrompt
        shouldBlockInterrupt = blockInterrupt
    }

    var promptStarted: Bool {
        calls.contains {
            if case .prompt = $0 { true } else { false }
        }
    }

    var interruptStarted: Bool {
        calls.contains {
            if case .interrupt = $0 { true } else { false }
        }
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        calls.append(.prompt(liveSessionID: liveSessionID, text: text))
        if shouldBlockPrompt {
            await withCheckedContinuation { continuation in
                promptContinuation = continuation
            }
        }
        return try promptResult.get()
    }

    func steer(liveSessionID: String, text: String) async throws -> Bool {
        calls.append(.steer(liveSessionID: liveSessionID, text: text))
        guard !steerResults.isEmpty else {
            return true
        }
        return try steerResults.removeFirst().get()
    }

    func interrupt(liveSessionID: String) async throws {
        calls.append(.interrupt(liveSessionID: liveSessionID))
        if shouldBlockInterrupt {
            await withCheckedContinuation { continuation in
                interruptContinuation = continuation
            }
        }
    }

    func releasePrompt() {
        shouldBlockPrompt = false
        promptContinuation?.resume()
        promptContinuation = nil
    }

    func releaseInterrupt() {
        shouldBlockInterrupt = false
        interruptContinuation?.resume()
        interruptContinuation = nil
    }
}
