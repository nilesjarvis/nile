import Foundation

struct GatewayFailure: Equatable, Sendable {
    let message: String
    let authRejected: Bool
    let retryable: Bool
}

enum GatewaySignal: Equatable, Sendable {
    case event(generation: Int64, frame: GatewayEventFrame)
    case failure(generation: Int64, failure: GatewayFailure)

    var generation: Int64 {
        switch self {
        case let .event(generation, _), let .failure(generation, _):
            generation
        }
    }
}

struct GatewaySignalSequence: AsyncSequence, Sendable {
    typealias Element = GatewaySignal

    struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var base: AsyncStream<GatewaySignal>.AsyncIterator
        fileprivate let acceptsGeneration:
            @Sendable (Int64) async -> Bool

        mutating func next() async -> GatewaySignal? {
            while let signal = await base.next() {
                if await acceptsGeneration(signal.generation) {
                    return signal
                }
            }
            return nil
        }
    }

    fileprivate let stream: AsyncStream<GatewaySignal>
    fileprivate let acceptsGeneration:
        @Sendable (Int64) async -> Bool

    init(
        stream: AsyncStream<GatewaySignal>,
        acceptsGeneration:
            @escaping @Sendable (Int64) async -> Bool
    ) {
        self.stream = stream
        self.acceptsGeneration = acceptsGeneration
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: stream.makeAsyncIterator(),
            acceptsGeneration: acceptsGeneration
        )
    }
}

protocol GatewayConnecting: Sendable {
    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) async throws

    func close() async
}
