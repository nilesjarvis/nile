import XCTest
@testable import Nile

@MainActor
final class GoalStatusRuntimeTests: XCTestCase {
    func testSynchronizeMapsAvailabilityThroughReadOnlyCapability() async {
        let expected = goal(phase: .paused)
        let service = GoalStatusServiceStub(
            results: [
                .success(expected),
                .failure(.unavailable),
            ]
        )
        let runtime = GoalStatusRuntime(repository: service)

        let available = await runtime.synchronize(liveSessionID: "live")
        let unavailable = await runtime.synchronize(liveSessionID: "live")
        let requestedSessionIDs = await service.requestedSessionIDs()

        XCTAssertEqual(available, .available(expected))
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(requestedSessionIDs, ["live", "live"])
    }

    func testCancellationFencesSuspendedLookup() async {
        let service = SuspendedGoalStatusService()
        let runtime = GoalStatusRuntime(repository: service)
        let lookup = Task {
            await runtime.synchronize(liveSessionID: "old-live")
        }
        await waitForCallCount(1, service: service)

        runtime.cancel()
        await service.resumeNext(with: goal(phase: .active))
        let result = await lookup.value

        XCTAssertNil(result)
    }

    func testRefreshReplacementPublishesOnlyLatestResult() async {
        let service = SuspendedGoalStatusService()
        let runtime = GoalStatusRuntime(repository: service)
        let latest = expectation(description: "Latest refresh published")
        var received: [GoalStatusRefreshResult] = []

        runtime.refresh(liveSessionID: "old-live") { result in
            received.append(result)
        }
        await waitForCallCount(1, service: service)
        runtime.refresh(liveSessionID: "new-live") { result in
            received.append(result)
            latest.fulfill()
        }
        await waitForCallCount(2, service: service)

        await service.resumeNext(with: goal(phase: .paused))
        await service.resumeNext(with: goal(phase: .active))
        await fulfillment(of: [latest], timeout: 1)

        XCTAssertEqual(received, [.success(goal(phase: .active))])
    }

    private func waitForCallCount(
        _ expected: Int,
        service: SuspendedGoalStatusService
    ) async {
        for _ in 0..<100 {
            if await service.callCount() == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expected) status calls")
    }

    private func goal(phase: GoalPhase) -> HermesGoal {
        HermesGoal(
            objective: "Ship safely",
            phase: phase,
            turnsUsed: 1,
            maxTurns: 5
        )
    }
}

private enum GoalStatusStubError: Error, Sendable {
    case unavailable
}

private actor GoalStatusServiceStub: HermesGoalStatusServing {
    private var results: [Result<HermesGoal?, GoalStatusStubError>]
    private var sessionIDs: [String] = []

    init(results: [Result<HermesGoal?, GoalStatusStubError>]) {
        self.results = results
    }

    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        sessionIDs.append(liveSessionID)
        guard !results.isEmpty else {
            throw GoalStatusStubError.unavailable
        }
        return try results.removeFirst().get()
    }

    func requestedSessionIDs() -> [String] {
        sessionIDs
    }
}

private actor SuspendedGoalStatusService: HermesGoalStatusServing {
    private var continuations: [
        CheckedContinuation<HermesGoal?, any Error>
    ] = []

    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func callCount() -> Int {
        continuations.count
    }

    func resumeNext(with goal: HermesGoal?) {
        continuations.removeFirst().resume(returning: goal)
    }
}
