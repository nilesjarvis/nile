import XCTest
@testable import Nile

@MainActor
final class SessionPinRuntimeTests: XCTestCase {
    func testRestorePinsAppliesOnlyToTheCurrentGatewayOwner() async {
        let store = SessionPinRuntimeStore(
            pinsByGateway: ["gateway-one": ["session-one"]],
            blocksLoad: true
        )
        let runtime = SessionPinRuntime(store: store)
        let firstOwner = owner(generation: 1, gatewayID: "gateway-one")
        let secondOwner = owner(generation: 2, gatewayID: "gateway-two")
        runtime.resetGateway(owner: firstOwner)

        let restore = Task { await runtime.restorePins(owner: firstOwner) }
        await eventuallyAsync { await store.loadStarted }
        runtime.resetGateway(owner: secondOwner)
        await store.releaseLoad()

        let restoreError = await restore.value
        XCTAssertNil(restoreError)
        XCTAssertTrue(runtime.pinnedSessionIDs.isEmpty)
    }

    func testToggleIsOptimisticAndPersistsDesiredValue() async {
        let store = SessionPinRuntimeStore()
        let runtime = SessionPinRuntime(store: store)
        let owner = owner()
        runtime.resetGateway(owner: owner)

        runtime.togglePin(
            sessionID: "session-one",
            owner: owner,
            onError: { _ in XCTFail("Unexpected persistence failure") }
        )

        XCTAssertEqual(runtime.pinnedSessionIDs, ["session-one"])
        await eventuallyAsync {
            await store.setCalls == ["gateway:session-one:true"]
        }
        let persistedPins = await store.pins(gatewayID: "gateway")
        XCTAssertEqual(persistedPins, ["session-one"])
    }

    func testMatchingWriteFailureRollsBackOptimisticState() async {
        let store = SessionPinRuntimeStore(setError: TestFailure())
        let runtime = SessionPinRuntime(store: store)
        let owner = owner()
        runtime.resetGateway(owner: owner)
        var errorMessage: String?

        runtime.togglePin(
            sessionID: "session-one",
            owner: owner,
            onError: { errorMessage = $0 }
        )

        XCTAssertEqual(runtime.pinnedSessionIDs, ["session-one"])
        await eventually { runtime.pinnedSessionIDs.isEmpty }
        XCTAssertEqual(
            errorMessage,
            "Could not save the session pin: Test failure"
        )
    }

    func testLateWriteFailureCannotMutateReplacementGateway() async {
        let store = SessionPinRuntimeStore(
            setError: TestFailure(),
            blocksFirstSet: true
        )
        let runtime = SessionPinRuntime(store: store)
        let firstOwner = owner(generation: 1, gatewayID: "gateway-one")
        let secondOwner = owner(generation: 2, gatewayID: "gateway-two")
        runtime.resetGateway(owner: firstOwner)
        var errorMessage: String?
        runtime.togglePin(
            sessionID: "session-one",
            owner: firstOwner,
            onError: { errorMessage = $0 }
        )
        await eventuallyAsync { await store.setCalls.count == 1 }

        runtime.resetGateway(owner: secondOwner)
        await store.releaseFirstSet()
        await eventuallyAsync { await store.completedSetCount == 1 }
        await Task.yield()

        XCTAssertTrue(runtime.pinnedSessionIDs.isEmpty)
        XCTAssertNil(errorMessage)
    }

    private func owner(
        generation: Int = 1,
        gatewayID: String = "gateway"
    ) -> SessionPinRuntime.GatewayOwner {
        SessionPinRuntime.GatewayOwner(
            gatewayGeneration: generation,
            gatewayID: gatewayID
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition was not met before the timeout")
    }

    private func eventuallyAsync(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition was not met before the timeout")
    }
}

private struct TestFailure: LocalizedError, Sendable {
    var errorDescription: String? { "Test failure" }
}

private actor SessionPinRuntimeStore: SessionPinStoring {
    private var pinsByGateway: [String: Set<String>]
    private let setError: (any Error)?
    private let blocksLoad: Bool
    private let blocksFirstSet: Bool
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var firstSetContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadStarted = false
    private(set) var setCalls: [String] = []
    private(set) var completedSetCount = 0

    init(
        pinsByGateway: [String: Set<String>] = [:],
        setError: (any Error)? = nil,
        blocksLoad: Bool = false,
        blocksFirstSet: Bool = false
    ) {
        self.pinsByGateway = pinsByGateway
        self.setError = setError
        self.blocksLoad = blocksLoad
        self.blocksFirstSet = blocksFirstSet
    }

    func load(gatewayID: String) async -> Set<String> {
        loadStarted = true
        if blocksLoad {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
        }
        return pinsByGateway[gatewayID] ?? []
    }

    func setPinned(
        gatewayID: String,
        sessionID: String,
        pinned: Bool
    ) async throws {
        setCalls.append("\(gatewayID):\(sessionID):\(pinned)")
        if blocksFirstSet, setCalls.count == 1 {
            await withCheckedContinuation { continuation in
                firstSetContinuation = continuation
            }
        }
        completedSetCount += 1
        if let setError {
            throw setError
        }
        if pinned {
            pinsByGateway[gatewayID, default: []].insert(sessionID)
        } else {
            pinsByGateway[gatewayID, default: []].remove(sessionID)
        }
    }

    func removeGateway(id: String) {
        pinsByGateway.removeValue(forKey: id)
    }

    func pins(gatewayID: String) -> Set<String> {
        pinsByGateway[gatewayID] ?? []
    }

    func releaseLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func releaseFirstSet() {
        firstSetContinuation?.resume()
        firstSetContinuation = nil
    }
}
