import XCTest
@testable import Nile

@MainActor
final class SessionClaimRuntimeTests: XCTestCase {
    func testClaimRefusesBusyStatusBeforeOpeningSession() async {
        let repository = ImmediateClaimRepository(status: " WORKING ")
        let runtime = SessionClaimRuntime(repository: repository)
        let owner = claimOwner()
        let capture = ClaimStatusCapture()

        let outcome = await runtime.claim(
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onStatus: { capture.values.append($0) }
        )

        guard case let .failed(message) = outcome else {
            return XCTFail("Expected a definite busy Claim failure")
        }
        XCTAssertEqual(
            message,
            "The terminal session is still working. Stop its current turn, then try Claim again."
        )
        XCTAssertEqual(capture.values, ["working"])
        let openCount = await repository.openCount
        XCTAssertEqual(openCount, 0)
        XCTAssertFalse(runtime.isClaiming)
    }

    func testResetInvalidatesLateClaimOpenResult() async {
        let repository = BlockingClaimOpenRepository()
        let runtime = SessionClaimRuntime(repository: repository)
        let owner = claimOwner()
        let task = Task {
            await runtime.claim(
                owner: owner,
                isCurrentOwner: { $0 == owner },
                onStatus: { _ in }
            )
        }
        await eventuallyAsync { await repository.openStarted }

        runtime.reset()
        await repository.releaseOpen()
        let outcome = await task.value

        guard case .stale = outcome else {
            return XCTFail("A reset Claim must reject the late open result")
        }
        XCTAssertFalse(runtime.isClaiming)
        XCTAssertFalse(runtime.isDialogVisible)
    }

    func testCancellingDialogStatusDoesNotInvalidateActiveClaim() async {
        let repository = BlockingClaimOpenRepository()
        let runtime = SessionClaimRuntime(repository: repository)
        let owner = claimOwner()
        let task = Task {
            await runtime.claim(
                owner: owner,
                isCurrentOwner: { $0 == owner },
                onStatus: { _ in }
            )
        }
        await eventuallyAsync { await repository.openStarted }

        runtime.cancelStatus()
        await repository.releaseOpen()
        let outcome = await task.value

        guard case let .succeeded(session) = outcome else {
            return XCTFail("Advisory status cancellation must preserve Claim")
        }
        XCTAssertEqual(session.storedID, owner.storedSessionID)
        XCTAssertFalse(runtime.isClaiming)
    }

    func testResetSuppressesLateClaimDialogStatus() async {
        let repository = BlockingClaimStatusRepository()
        let runtime = SessionClaimRuntime(repository: repository)
        let owner = claimOwner()
        let capture = ClaimStatusCapture()

        runtime.setDialogVisible(
            true,
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onStatus: { capture.values.append($0) }
        )
        await eventuallyAsync { await repository.statusStarted }

        runtime.reset()
        await repository.releaseStatus("working")
        await Task.yield()

        XCTAssertTrue(capture.values.isEmpty)
        XCTAssertFalse(runtime.isDialogVisible)
    }

    private func claimOwner() -> SessionClaimRuntime.Owner {
        SessionClaimRuntime.Owner(
            gatewayGeneration: 1,
            displayGeneration: 2,
            gatewayID: "gateway-one",
            storedSessionID: "one"
        )
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class ClaimStatusCapture {
    var values: [String?] = []
}

private actor ImmediateClaimRepository: HermesSessionClaimServing {
    private let status: String?
    private(set) var openCount = 0

    init(status: String? = nil) {
        self.status = status
    }

    func openSession(storedSessionID: String) async throws -> LiveSession {
        openCount += 1
        return claimLiveSession(storedSessionID: storedSessionID)
    }

    func liveSessionStatus(storedSessionID: String) async throws -> String? {
        status
    }
}

private actor BlockingClaimOpenRepository: HermesSessionClaimServing {
    private(set) var openStarted = false
    private var openContinuation: CheckedContinuation<Void, Never>?

    func openSession(storedSessionID: String) async throws -> LiveSession {
        openStarted = true
        await withCheckedContinuation { continuation in
            openContinuation = continuation
        }
        return claimLiveSession(storedSessionID: storedSessionID)
    }

    func liveSessionStatus(storedSessionID: String) async throws -> String? {
        "idle"
    }

    func releaseOpen() {
        openContinuation?.resume()
        openContinuation = nil
    }
}

private actor BlockingClaimStatusRepository: HermesSessionClaimServing {
    private(set) var statusStarted = false
    private var statusContinuation: CheckedContinuation<String?, Never>?

    func openSession(storedSessionID: String) async throws -> LiveSession {
        claimLiveSession(storedSessionID: storedSessionID)
    }

    func liveSessionStatus(storedSessionID: String) async throws -> String? {
        statusStarted = true
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func releaseStatus(_ status: String?) {
        statusContinuation?.resume(returning: status)
        statusContinuation = nil
    }
}

private func claimLiveSession(storedSessionID: String) -> LiveSession {
    LiveSession(
        liveID: "live-\(storedSessionID)",
        storedID: storedSessionID,
        info: SessionInfo(model: nil, provider: nil),
        messages: [],
        running: false,
        status: "idle",
        inflight: nil
    )
}
