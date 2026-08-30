import XCTest
@testable import Nile

@MainActor
final class GatewayReconnectCoordinatorTests: XCTestCase {
    func testReconnectWaitsForNetworkBeforeAttempting() async {
        let network = TestGatewayNetwork(available: false)
        let attempts = ReconnectAttemptRecorder()
        let coordinator = GatewayReconnectCoordinator(
            network: network,
            jitter: { $0 },
            sleep: { _ in }
        )
        var phases: [GatewayReconnectLoopPhase] = []

        coordinator.schedule(
            onPhase: { phases.append($0) },
            attempt: {
                await attempts.record()
                return .stop
            }
        )
        await network.waitForAvailabilityWaiter()
        XCTAssertEqual(phases, [.waitingForNetwork])
        let attemptsBeforeNetwork = await attempts.count
        XCTAssertEqual(attemptsBeforeNetwork, 0)

        await network.setAvailable(true)
        await attempts.waitForCount(1)
        XCTAssertEqual(
            phases,
            [.waitingForNetwork, .attempting]
        )
    }

    func testReconnectUsesJitteredCappedExponentialBackoff() async {
        let network = TestGatewayNetwork(available: true)
        let clock = TestReconnectSleep()
        let attempts = ReconnectAttemptRecorder()
        let jitterInputs = LockedInt64Recorder()
        var phases: [GatewayReconnectLoopPhase] = []
        let coordinator = GatewayReconnectCoordinator(
            network: network,
            jitter: {
                jitterInputs.append($0)
                return $0 + 1
            },
            initialDelayMilliseconds: 4,
            maximumDelayMilliseconds: 7,
            sleep: { milliseconds in
                try await clock.sleep(milliseconds)
            }
        )

        coordinator.schedule(
            onPhase: { phases.append($0) },
            attempt: {
                let count = await attempts.record()
                return count < 3 ? .retry : .stop
            }
        )
        await clock.waitForSleepCount(1)
        XCTAssertEqual(jitterInputs.snapshot, [4])
        let firstWaits = await clock.waits
        XCTAssertEqual(firstWaits, [5])
        await clock.releaseNext()

        await clock.waitForSleepCount(2)
        XCTAssertEqual(jitterInputs.snapshot, [4, 7])
        let secondWaits = await clock.waits
        XCTAssertEqual(secondWaits, [5, 8])
        await clock.releaseNext()

        await attempts.waitForCount(3)
        XCTAssertEqual(
            phases,
            [
                .attempting,
                .backingOff(milliseconds: 5),
                .attempting,
                .backingOff(milliseconds: 8),
                .attempting,
            ]
        )
    }

    func testActiveReconnectIsFirstWinsAndRestartReplacesIt() async {
        let network = TestGatewayNetwork(available: true)
        let clock = TestReconnectSleep()
        let attempts = ReconnectAttemptRecorder()
        let coordinator = GatewayReconnectCoordinator(
            network: network,
            jitter: { $0 },
            sleep: { milliseconds in
                try await clock.sleep(milliseconds)
            }
        )

        coordinator.schedule(onPhase: { _ in }) {
            _ = await attempts.record(label: "first")
            return .retry
        }
        await clock.waitForSleepCount(1)
        coordinator.schedule(onPhase: { _ in }) {
            _ = await attempts.record(label: "ignored")
            return .stop
        }
        await Task.yield()
        let firstLabels = await attempts.labels
        XCTAssertEqual(firstLabels, ["first"])

        coordinator.restart(onPhase: { _ in }) {
            _ = await attempts.record(label: "replacement")
            return .stop
        }
        await attempts.waitForCount(2)
        let finalLabels = await attempts.labels
        XCTAssertEqual(
            finalLabels,
            ["first", "replacement"]
        )
    }

    func testDefaultJitterStaysWithinAndroidQuarterSpread() {
        for delay in [2, 4, 1_000, 20_000] {
            let value = defaultGatewayReconnectJitter(Int64(delay))
            let spread = max(1, Int64(delay) / 4)
            let lowerBound = max(1, Int64(delay) - spread)
            let upperBound = Int64(delay) + spread
            XCTAssertTrue(
                (lowerBound...upperBound).contains(value)
            )
        }
    }
}

private actor TestGatewayNetwork: GatewayNetworkWaiting {
    private var available: Bool
    private var availabilityWaiters: [
        CheckedContinuation<Void, any Error>
    ] = []
    private var observerWaiters: [CheckedContinuation<Void, Never>] = []

    init(available: Bool) {
        self.available = available
    }

    func isNetworkAvailable() -> Bool {
        available
    }

    func waitUntilNetworkAvailable() async throws {
        guard !available else {
            return
        }
        observerWaiters.forEach { $0.resume() }
        observerWaiters.removeAll()
        try await withCheckedThrowingContinuation {
            (
                continuation: CheckedContinuation<Void, any Error>
            ) in
            availabilityWaiters.append(continuation)
        }
    }

    func waitForAvailabilityWaiter() async {
        guard availabilityWaiters.isEmpty else {
            return
        }
        await withCheckedContinuation { continuation in
            observerWaiters.append(continuation)
        }
    }

    func setAvailable(_ value: Bool) {
        available = value
        guard value else {
            return
        }
        availabilityWaiters.forEach { $0.resume() }
        availabilityWaiters.removeAll()
    }
}

private actor TestReconnectSleep {
    private(set) var waits: [Int64] = []
    private var sleepers: [
        CheckedContinuation<Void, any Error>
    ] = []
    private var observers: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    func sleep(_ milliseconds: Int64) async throws {
        waits.append(milliseconds)
        let ready = observers.filter { waits.count >= $0.count }
        observers.removeAll { waits.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
        try await withCheckedThrowingContinuation {
            (
                continuation: CheckedContinuation<Void, any Error>
            ) in
            sleepers.append(continuation)
        }
    }

    func waitForSleepCount(_ count: Int) async {
        guard waits.count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            observers.append((count, continuation))
        }
    }

    func releaseNext() {
        sleepers.removeFirst().resume()
    }
}

private actor ReconnectAttemptRecorder {
    private(set) var labels: [String] = []
    private var waiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    var count: Int {
        labels.count
    }

    @discardableResult
    func record(label: String = "attempt") -> Int {
        labels.append(label)
        let ready = waiters.filter { labels.count >= $0.count }
        waiters.removeAll { labels.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
        return labels.count
    }

    func waitForCount(_ count: Int) async {
        guard labels.count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

private final class LockedInt64Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64] = []

    var snapshot: [Int64] {
        lock.withLock {
            storage
        }
    }

    func append(_ value: Int64) {
        lock.withLock {
            storage.append(value)
        }
    }
}
