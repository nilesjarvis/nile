import XCTest
@testable import Nile

@MainActor
final class ModelOptionsRuntimeTests: XCTestCase {
    func testLoadUsesReadOnlyCapabilityAndPublishesResult() async {
        let expected = options(model: "gpt-5")
        let service = ModelOptionsServiceStub(results: [.success(expected)])
        let runtime = ModelOptionsRuntime(repository: service)
        let published = expectation(description: "Options published")
        var result: ModelOptionsLoadResult?

        XCTAssertTrue(
            runtime.load(liveSessionID: "live", refresh: true) { value in
                result = value
                published.fulfill()
            }
        )
        await fulfillment(of: [published], timeout: 1)
        let calls = await service.recordedCalls()

        XCTAssertEqual(result, .success(expected))
        XCTAssertEqual(calls, [ModelOptionsCall(sessionID: "live", refresh: true)])
        XCTAssertFalse(runtime.isLoading)
    }

    func testReplacementPublishesOnlyLatestCatalog() async {
        let service = SuspendedModelOptionsService()
        let runtime = ModelOptionsRuntime(repository: service)
        let latest = expectation(description: "Latest options published")
        var received: [ModelOptionsLoadResult] = []

        runtime.load(liveSessionID: "old", refresh: false) {
            received.append($0)
        }
        await waitForCallCount(1, service: service)
        runtime.load(liveSessionID: "new", refresh: true) {
            received.append($0)
            latest.fulfill()
        }
        await waitForCallCount(2, service: service)

        await service.resumeNext(with: options(model: "old"))
        await service.resumeNext(with: options(model: "new"))
        await fulfillment(of: [latest], timeout: 1)

        XCTAssertEqual(received, [.success(options(model: "new"))])
    }

    func testCancelFencesSuspendedCatalog() async {
        let service = SuspendedModelOptionsService()
        let runtime = ModelOptionsRuntime(repository: service)
        var received: [ModelOptionsLoadResult] = []

        runtime.load(liveSessionID: "live", refresh: false) {
            received.append($0)
        }
        await waitForCallCount(1, service: service)
        runtime.cancel()
        await service.resumeNext(with: options(model: "late"))
        await Task.yield()

        XCTAssertTrue(received.isEmpty)
        XCTAssertFalse(runtime.isLoading)
    }

    private func waitForCallCount(
        _ expected: Int,
        service: SuspendedModelOptionsService
    ) async {
        for _ in 0..<100 {
            if await service.callCount() == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(expected) model-option calls")
    }

    private func options(model: String) -> ModelOptions {
        ModelOptions(model: model, provider: nil, providers: [])
    }
}

private struct ModelOptionsCall: Equatable, Sendable {
    let sessionID: String?
    let refresh: Bool
}

private actor ModelOptionsServiceStub: HermesModelOptionsServing {
    private var results: [Result<ModelOptions, any Error>]
    private var calls: [ModelOptionsCall] = []

    init(results: [Result<ModelOptions, any Error>]) {
        self.results = results
    }

    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) throws -> ModelOptions {
        calls.append(
            ModelOptionsCall(sessionID: liveSessionID, refresh: refresh)
        )
        return try results.removeFirst().get()
    }

    func recordedCalls() -> [ModelOptionsCall] {
        calls
    }
}

private actor SuspendedModelOptionsService: HermesModelOptionsServing {
    private var continuations: [
        CheckedContinuation<ModelOptions, any Error>
    ] = []

    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) async throws -> ModelOptions {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func callCount() -> Int {
        continuations.count
    }

    func resumeNext(with options: ModelOptions) {
        continuations.removeFirst().resume(returning: options)
    }
}
