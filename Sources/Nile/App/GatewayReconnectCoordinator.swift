import Foundation
import Network

enum GatewayReconnectDirective: Sendable {
    case stop
    case retry
}

enum GatewayReconnectLoopPhase: Equatable, Sendable {
    case waitingForNetwork
    case attempting
    case backingOff(milliseconds: Int64)
}

protocol GatewayNetworkWaiting: Sendable {
    func isNetworkAvailable() async -> Bool
    func waitUntilNetworkAvailable() async throws
}

final class NWPathGatewayNetworkWaiter:
    GatewayNetworkWaiting,
    @unchecked Sendable
{
    private let monitor: NWPathMonitor
    private let state: GatewayNetworkAvailabilityState

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(
            label: "com.niles.nile.gateway-network-path"
        )
    ) {
        self.monitor = monitor
        state = GatewayNetworkAvailabilityState(
            available: monitor.currentPath.status == .satisfied
        )
        monitor.pathUpdateHandler = { [state] path in
            Task {
                await state.update(path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func isNetworkAvailable() async -> Bool {
        await state.isAvailable
    }

    func waitUntilNetworkAvailable() async throws {
        try await state.waitUntilAvailable()
    }
}

@MainActor
final class GatewayReconnectCoordinator {
    typealias Attempt = @MainActor @Sendable () async
        -> GatewayReconnectDirective
    typealias PhaseHandler = @MainActor @Sendable
        (GatewayReconnectLoopPhase) -> Void
    typealias Jitter = @Sendable (Int64) -> Int64
    typealias Sleep = @Sendable (Int64) async throws -> Void

    private let network: any GatewayNetworkWaiting
    private let jitter: Jitter
    private let sleep: Sleep
    private let initialDelayMilliseconds: Int64
    private let maximumDelayMilliseconds: Int64
    private var reconnectTask: Task<Void, Never>?
    private var reconnectID: UUID?

    init(
        network: any GatewayNetworkWaiting = NWPathGatewayNetworkWaiter(),
        jitter: @escaping Jitter = defaultGatewayReconnectJitter,
        initialDelayMilliseconds: Int64 = 1_000,
        maximumDelayMilliseconds: Int64 = 20_000,
        sleep: @escaping Sleep = { milliseconds in
            try await ContinuousClock().sleep(
                for: .milliseconds(milliseconds)
            )
        }
    ) {
        self.network = network
        self.jitter = jitter
        self.sleep = sleep
        self.initialDelayMilliseconds = initialDelayMilliseconds
        self.maximumDelayMilliseconds = maximumDelayMilliseconds
    }

    var isScheduled: Bool {
        reconnectTask != nil
    }

    func schedule(
        onPhase: @escaping PhaseHandler,
        attempt: @escaping Attempt
    ) {
        guard reconnectTask == nil else {
            return
        }
        let id = UUID()
        reconnectID = id
        reconnectTask = Task { [weak self] in
            guard let self else {
                return
            }
            var delayMilliseconds = initialDelayMilliseconds
            while !Task.isCancelled {
                if !(await network.isNetworkAvailable()) {
                    onPhase(.waitingForNetwork)
                    do {
                        try await network.waitUntilNetworkAvailable()
                    } catch {
                        break
                    }
                }
                guard !Task.isCancelled else {
                    break
                }
                onPhase(.attempting)
                if await attempt() == .stop {
                    break
                }
                let waitMilliseconds = jitter(delayMilliseconds)
                onPhase(.backingOff(milliseconds: waitMilliseconds))
                do {
                    try await sleep(waitMilliseconds)
                } catch {
                    break
                }
                delayMilliseconds = min(
                    delayMilliseconds * 2,
                    maximumDelayMilliseconds
                )
            }
            finish(id: id)
        }
    }

    func cancel() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectID = nil
    }

    func restart(
        onPhase: @escaping PhaseHandler,
        attempt: @escaping Attempt
    ) {
        cancel()
        schedule(onPhase: onPhase, attempt: attempt)
    }

    private func finish(id: UUID) {
        guard reconnectID == id else {
            return
        }
        reconnectTask = nil
        reconnectID = nil
    }
}

func defaultGatewayReconnectJitter(_ delayMilliseconds: Int64) -> Int64 {
    guard delayMilliseconds > 1 else {
        return max(0, delayMilliseconds)
    }
    let spread = max(1, delayMilliseconds / 4)
    let lowerBound = max(1, delayMilliseconds - spread)
    let upperBound = delayMilliseconds + spread
    return Int64.random(in: lowerBound...upperBound)
}

private actor GatewayNetworkAvailabilityState {
    private(set) var isAvailable: Bool
    private var waiters: [
        UUID: CheckedContinuation<Void, any Error>
    ] = [:]

    init(available: Bool) {
        isAvailable = available
    }

    func update(_ available: Bool) {
        isAvailable = available
        guard available else {
            return
        }
        let pending = waiters.values
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitUntilAvailable() async throws {
        try Task.checkCancellation()
        guard !isAvailable else {
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (
                    continuation: CheckedContinuation<Void, any Error>
                ) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if isAvailable {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
        try Task.checkCancellation()
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(
            throwing: CancellationError()
        )
    }
}
