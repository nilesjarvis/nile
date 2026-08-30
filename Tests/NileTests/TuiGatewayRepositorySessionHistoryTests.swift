import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testSessionOperationsUseExactMethodsParametersAndTimeouts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "session.list": [
                    "sessions": .array([
                        .object(["id": .string("stored-1")]),
                    ]),
                ],
                "session.resume": [
                    "session_id": .string("live-1"),
                    "stored_session_id": .string("stored-1"),
                ],
                "session.create": ["session_id": .string("live-2")],
                "session.title": [:],
            ]
        )
        let repository = repository(rpc: rpc)
        let sessions = repository.sessionCapabilities.sessions

        let listed = try await sessions.listSessions(limit: 25)
        let opened = try await sessions.openSession(storedSessionID: "stored-1")
        let created = try await sessions.createSession(title: " New ")
        XCTAssertEqual(listed.map(\.id), ["stored-1"])
        XCTAssertEqual(opened.liveID, "live-1")
        XCTAssertEqual(created.liveID, "live-2")
        try await sessions.renameSession(
            liveSessionID: "live-2",
            title: "Renamed"
        )

        let requests = await rpc.requests
        XCTAssertEqual(
            requests,
            [
                RPCRequest(
                    method: "session.list",
                    params: ["limit": .number(25)],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "session.resume",
                    params: ["session_id": .string("stored-1")],
                    timeoutMilliseconds: 60_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "session.create",
                    params: ["source": .string("niles"), "title": .string(" New ")],
                    timeoutMilliseconds: 60_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "session.title",
                    params: [
                        "session_id": .string("live-2"),
                        "title": .string("Renamed"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: true
                ),
            ]
        )
    }

    func testBlankCreateTitleIsOmittedAndMissingLiveIDFailsClosed() async {
        let rpc = RecordingRPC(
            responses: ["session.create": ["session_id": .string(" ")]]
        )
        let repository = repository(rpc: rpc)
        let sessions = repository.sessionCapabilities.sessions

        await XCTAssertThrowsErrorAsync(
            try await sessions.createSession(title: " ")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to session.create: session_id was missing or blank"
            )
        }
        let requests = await rpc.requests
        XCTAssertEqual(requests.first?.params, ["source": .string("niles")])
    }

    func testStatusOperationsPreserveStoredAndRuntimeIdentifierDomains() async throws {
        let rpc = RecordingRPC(
            responses: [
                "session.active_list": [
                    "sessions": .array([
                        .object([
                            "id": .string("live-1"),
                            "session_key": .string("stored-1"),
                            "status": .string("working"),
                        ]),
                    ]),
                ],
            ]
        )
        let repository = repository(rpc: rpc)
        let sessions = repository.sessionCapabilities.sessions

        let storedStatus = try await sessions.liveSessionStatus(
            storedSessionID: "stored-1"
        )
        let runtimeStatus = try await sessions.liveRuntimeStatus(
            liveSessionID: "live-1"
        )
        XCTAssertEqual(storedStatus, "working")
        XCTAssertEqual(runtimeStatus, "working")
    }

    func testStoredReadsRequireConnectionBeforeDashboardCapability() async {
        let repository = repository(rpc: RecordingRPC(responses: [:]))
        let sessions = repository.sessionCapabilities.sessions

        await XCTAssertThrowsErrorAsync(
            try await sessions.readStoredSessionSource(
                storedSessionID: "stored-1"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Not connected to the Hermes gateway"
            )
            XCTAssertEqual(hermes?.retryable, true)
            XCTAssertEqual(hermes?.isConnectionFailure, true)
        }
        await XCTAssertThrowsErrorAsync(
            try await sessions.readStoredSession(
                storedSessionID: "stored-1"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Not connected to the Hermes gateway"
            )
        }
    }

    func testUnavailableDashboardCapabilityUsesOperationSpecificErrors() async throws {
        let repository = repository(rpc: RecordingRPC(responses: [:]))
        let sessions = repository.sessionCapabilities.sessions
        try await repository.connect(connection())

        await XCTAssertThrowsErrorAsync(
            try await sessions.readStoredSessionSource(
                storedSessionID: "stored-1"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Stored session metadata is unavailable for this gateway"
            )
            XCTAssertEqual(hermes?.retryable, false)
        }
        await XCTAssertThrowsErrorAsync(
            try await sessions.readStoredSession(
                storedSessionID: "stored-1"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Stored session history is unavailable for this gateway"
            )
            XCTAssertEqual(hermes?.retryable, false)
        }
    }

    func testGatewayStatsUsesSharedConnectionLifecycleBeforeDashboard()
        async throws
    {
        let repository = repository(rpc: RecordingRPC(responses: [:]))
        let usage = repository.sessionCapabilities.gatewayStatistics

        await XCTAssertThrowsErrorAsync(
            try await usage.gatewayStats(days: 30)
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Not connected to the Hermes gateway"
            )
            XCTAssertEqual(hermes?.retryable, true)
            XCTAssertEqual(hermes?.isConnectionFailure, true)
        }

        try await repository.connect(connection())
        await XCTAssertThrowsErrorAsync(
            try await usage.gatewayStats(days: 30)
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Gateway analytics are unavailable for this connection"
            )
            XCTAssertEqual(hermes?.retryable, false)
        }

        await repository.disconnect()
        await XCTAssertThrowsErrorAsync(
            try await usage.gatewayStats(days: 30)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Not connected to the Hermes gateway"
            )
        }
    }

    func testStoredReadsUseActiveConnectionExactPathsAndStrictCodec() async throws {
        let dashboard = RecordingDashboard(
            responses: [
                ["sessions", "stored/1"]: [
                    "source": .string("cli"),
                ],
                ["sessions", "stored/1", "messages"]: [
                    "messages": .array([
                        .object([
                            "role": .string("user"),
                            "content": .string("hello"),
                        ]),
                        .object([
                            "role": .string("assistant"),
                            "content": .string("world"),
                        ]),
                    ]),
                ],
            ]
        )
        let repository = TuiGatewayRepository(
            rpc: RecordingRPC(responses: [:]),
            connectionClient: NoopConnectionClient(),
            signals: AsyncStream { $0.finish() },
            dashboard: dashboard
        )
        let activeConnection = connection()
        try await repository.connect(activeConnection)
        let sessions = repository.sessionCapabilities.sessions

        let source = try await sessions.readStoredSessionSource(
            storedSessionID: "stored/1"
        )
        let messages = try await sessions.readStoredSession(
            storedSessionID: "stored/1"
        )

        XCTAssertEqual(source, "cli")
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.map(\.text), ["hello", "world"])
        let requests = await dashboard.requests
        XCTAssertEqual(
            requests,
            [
                DashboardRequest(
                    connection: activeConnection,
                    pathSegments: ["sessions", "stored/1"]
                ),
                DashboardRequest(
                    connection: activeConnection,
                    pathSegments: ["sessions", "stored/1", "messages"]
                ),
            ]
        )

        await repository.disconnect()
        await XCTAssertThrowsErrorAsync(
            try await sessions.readStoredSession(
                storedSessionID: "stored/1"
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Not connected to the Hermes gateway"
            )
        }
    }

}
