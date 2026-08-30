import Foundation

struct GatewayDeadlineExceeded: Error {}

enum GatewayDeadline {
    static func run<Value: Sendable>(
        milliseconds: Int64,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let boundedMilliseconds = max(0, milliseconds)
                try await Task.sleep(
                    nanoseconds: UInt64(boundedMilliseconds) * 1_000_000
                )
                throw GatewayDeadlineExceeded()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

struct GatewayOneShot<Value: Sendable>: Sendable {
    private let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation

    init() {
        let pair = AsyncThrowingStream<Value, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    func value() async throws -> Value {
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw CancellationError()
        }
        return value
    }

    func succeed(_ value: Value) {
        continuation.yield(value)
        continuation.finish()
    }

    func fail(_ error: any Error) {
        continuation.finish(throwing: error)
    }
}
