import XCTest
@testable import Nile

@MainActor
final class SessionNavigationRuntimeTests: XCTestCase {
    func testDirectoryLoadRequiresSessionsAndTreatsStatusesAsBestEffort()
        async throws {
        let repository = NavigationRepositoryStub(
            sessions: [session("one")],
            statusError: TestNavigationFailure()
        )
        let runtime = SessionNavigationRuntime(repository: repository)
        let owner = gatewayOwner()
        runtime.resetGateway(owner: owner)

        let snapshot = try await runtime.loadDirectory(owner: owner)
        let calls = await repository.recordedCalls()

        XCTAssertEqual(snapshot.sessions.map(\.id), ["one"])
        XCTAssertTrue(snapshot.activeStatuses.isEmpty)
        XCTAssertEqual(
            calls.sorted(),
            ["session.active_list", "session.list"].sorted()
        )
    }

    func testInjectedRefreshPreservesDirectoryStatusFenceAndHistoryOrder()
        async {
        let ticks = AsyncStream<Void>.makeStream()
        let repository = NavigationRepositoryStub(
            sessions: [session("terminal")],
            statuses: ["terminal": "idle"],
            histories: [
                "terminal": [HermesMessage(role: "assistant", text: "done")],
            ]
        )
        let runtime = SessionNavigationRuntime(
            repository: repository,
            refreshTicks: ticks.stream
        )
        let gatewayOwner = gatewayOwner()
        let displayOwner = SessionNavigationRuntime.DisplayOwner(
            gatewayGeneration: 1,
            displayGeneration: 4,
            gatewayID: "gateway",
            storedSessionID: "terminal",
            liveSessionID: nil
        )
        runtime.resetGateway(owner: gatewayOwner)
        var phases: [String] = []
        runtime.startRefreshing(
            sink: SessionNavigationRuntime.RefreshSink(
                request: {
                    SessionNavigationRuntime.RefreshRequest(
                        gatewayOwner: gatewayOwner,
                        readOnlyDisplayOwner: displayOwner
                    )
                },
                sessions: { owner, sessions in
                    XCTAssertEqual(owner, gatewayOwner)
                    XCTAssertEqual(sessions.map(\.id), ["terminal"])
                    phases.append("sessions")
                },
                prepareStatuses: { owner in
                    XCTAssertEqual(owner, gatewayOwner)
                    phases.append("status-fence")
                    return { statuses in
                        XCTAssertEqual(statuses, ["terminal": "idle"])
                        phases.append("statuses")
                    }
                },
                history: { owner, messages in
                    XCTAssertEqual(owner, displayOwner)
                    XCTAssertEqual(messages.map(\.text), ["done"])
                    phases.append("history")
                }
            )
        )

        ticks.continuation.yield()
        await eventually { phases.count == 4 }
        let calls = await repository.recordedCalls()

        XCTAssertEqual(
            phases,
            ["sessions", "status-fence", "statuses", "history"]
        )
        XCTAssertEqual(
            calls,
            ["session.list", "session.active_list", "history:terminal"]
        )
    }

    func testGatewayResetFencesLateReconciliationResult() async {
        let repository = NavigationRepositoryStub(
            sessions: [],
            openedSessions: [liveSession("one")],
            blocksFirstOpen: true
        )
        let runtime = SessionNavigationRuntime(repository: repository)
        let firstOwner = gatewayOwner()
        runtime.resetGateway(owner: firstOwner)
        var applied: [String] = []
        runtime.reconcileDisplay(owner: displayOwner()) { _, session in
            applied.append(session.liveID)
        }
        await eventuallyAsync {
            await repository.openCallCount() == 1
        }

        runtime.resetGateway(
            owner: gatewayOwner(generation: 2, gatewayID: "replacement")
        )
        await repository.releaseFirstOpen()
        await eventuallyAsync {
            await repository.completedOpenCount() == 1
        }
        await Task.yield()

        XCTAssertTrue(applied.isEmpty)
    }

    func testReplacementAttachedRefreshPublishesOnlyNewestResult() async {
        let repository = NavigationRepositoryStub(
            sessions: [],
            openedSessions: [liveSession("old"), liveSession("new")],
            blocksFirstOpen: true
        )
        let runtime = SessionNavigationRuntime(repository: repository)
        let gatewayOwner = gatewayOwner()
        runtime.resetGateway(owner: gatewayOwner)
        var applied: [String] = []
        let oldOwner = displayOwner(storedSessionID: "old")
        let newOwner = displayOwner(
            displayGeneration: 2,
            storedSessionID: "new",
            liveSessionID: "live-new"
        )
        runtime.refreshCompletedAttachedTurn(owner: oldOwner) { _, session in
            applied.append(session.liveID)
        }
        await eventuallyAsync {
            await repository.openCallCount() == 1
        }

        runtime.refreshCompletedAttachedTurn(owner: newOwner) { _, session in
            applied.append(session.liveID)
        }
        await eventuallyAsync { applied == ["live-new"] }
        await repository.releaseFirstOpen()
        await eventuallyAsync {
            await repository.completedOpenCount() == 2
        }
        await Task.yield()

        XCTAssertEqual(applied, ["live-new"])
    }

    private func gatewayOwner(
        generation: Int = 1,
        gatewayID: String = "gateway"
    ) -> SessionNavigationRuntime.GatewayOwner {
        SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: generation,
            gatewayID: gatewayID
        )
    }

    private func displayOwner(
        displayGeneration: Int = 1,
        storedSessionID: String = "one",
        liveSessionID: String = "live-one"
    ) -> SessionNavigationRuntime.DisplayOwner {
        SessionNavigationRuntime.DisplayOwner(
            gatewayGeneration: 1,
            displayGeneration: displayGeneration,
            gatewayID: "gateway",
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    private func session(_ id: String) -> HermesSession {
        HermesSession(
            id: id,
            title: id,
            preview: nil,
            source: "niles",
            messageCount: 0,
            startedAt: nil,
            lastMessageAt: nil
        )
    }

    private func liveSession(_ id: String) -> LiveSession {
        LiveSession(
            liveID: "live-\(id)",
            storedID: id,
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
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

private struct TestNavigationFailure: LocalizedError, Sendable {
    var errorDescription: String? { "Navigation failure" }
}

private actor NavigationRepositoryStub: HermesSessionServing {
    private let sessions: [HermesSession]
    private let statuses: [String: String]
    private let histories: [String: [HermesMessage]]
    private var openedSessions: [LiveSession]
    private let statusError: (any Error)?
    private let blocksFirstOpen: Bool
    private var firstOpenContinuation: CheckedContinuation<Void, Never>?
    private var calls: [String] = []
    private var completedOpens = 0

    init(
        sessions: [HermesSession],
        statuses: [String: String] = [:],
        histories: [String: [HermesMessage]] = [:],
        openedSessions: [LiveSession] = [],
        statusError: (any Error)? = nil,
        blocksFirstOpen: Bool = false
    ) {
        self.sessions = sessions
        self.statuses = statuses
        self.histories = histories
        self.openedSessions = openedSessions
        self.statusError = statusError
        self.blocksFirstOpen = blocksFirstOpen
    }

    func listSessions(limit: Int) -> [HermesSession] {
        calls.append("session.list")
        return sessions
    }

    func readStoredSessionSource(storedSessionID: String) -> String? {
        "niles"
    }

    func readStoredSession(
        storedSessionID: String
    ) -> [HermesMessage] {
        calls.append("history:\(storedSessionID)")
        return histories[storedSessionID] ?? []
    }

    func openSession(storedSessionID: String) async -> LiveSession {
        calls.append("session.resume:\(storedSessionID)")
        let callIndex = calls.filter {
            $0.hasPrefix("session.resume:")
        }.count
        let result = openedSessions.isEmpty
            ? LiveSession(
                liveID: "live-\(storedSessionID)",
                storedID: storedSessionID,
                info: SessionInfo(model: nil, provider: nil),
                messages: [],
                running: false,
                status: "idle",
                inflight: nil
            )
            : openedSessions.removeFirst()
        if blocksFirstOpen, callIndex == 1 {
            await withCheckedContinuation { continuation in
                firstOpenContinuation = continuation
            }
        }
        completedOpens += 1
        return result
    }

    func liveSessionStatus(storedSessionID: String) -> String? {
        statuses[storedSessionID]
    }

    func renameSession(liveSessionID: String, title: String) {}

    func liveRuntimeStatus(liveSessionID: String) -> String? {
        nil
    }

    func activeSessionStatuses() throws -> [String: String] {
        calls.append("session.active_list")
        if let statusError {
            throw statusError
        }
        return statuses
    }

    func createSession(title: String?) -> LiveSession {
        LiveSession(
            liveID: "live-new",
            storedID: "new",
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
    }

    func recordedCalls() -> [String] {
        calls
    }

    func openCallCount() -> Int {
        calls.filter { $0.hasPrefix("session.resume:") }.count
    }

    func completedOpenCount() -> Int {
        completedOpens
    }

    func releaseFirstOpen() {
        firstOpenContinuation?.resume()
        firstOpenContinuation = nil
    }
}
