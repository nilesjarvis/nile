import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func repository(rpc: RecordingRPC) -> TuiGatewayRepository {
        TuiGatewayRepository(
            rpc: rpc,
            connectionClient: NoopConnectionClient(),
            signals: AsyncStream { $0.finish() }
        )
    }

    func delegationService(
        rpc: RecordingRPC
    ) -> any HermesDelegationServing {
        repository(rpc: rpc).sessionCapabilities.delegation
    }

    func blockingPromptService(
        rpc: RecordingRPC
    ) -> any HermesBlockingPromptServing {
        repository(rpc: rpc).sessionCapabilities.blockingPrompts
    }

    func modelService(
        rpc: RecordingRPC
    ) -> any HermesModelServing {
        repository(rpc: rpc).sessionCapabilities.models
    }

    func usageService(
        rpc: RecordingRPC
    ) -> any HermesSessionUsageServing {
        repository(rpc: rpc).sessionCapabilities.sessionUsage
    }

    func commandService(
        rpc: RecordingRPC
    ) -> any HermesCommandServing {
        repository(rpc: rpc).sessionCapabilities.commands
    }

    func goalService(
        rpc: RecordingRPC
    ) -> any HermesGoalServing {
        repository(rpc: rpc).sessionCapabilities.goals
    }

    func connection() -> GatewayConnection {
        GatewayConnection(
            endpoint: try! GatewayEndpoint.parse(
                "https://gateway.example/hermes"
            ),
            token: "token"
        )
    }

    func emptyCommandCatalog() -> JSONValue.Object {
        [
            "warning": .string(""),
            "categories": .array([
                .object([
                    "name": .string("User commands"),
                    "pairs": .array([]),
                ]),
            ]),
            "pairs": .array([]),
            "skill_count": .number(0),
        ]
    }
}

struct RPCRequest: Equatable, Sendable {
    let method: String
    let params: JSONValue.Object
    let timeoutMilliseconds: Int64
    let allowNullResult: Bool
}

actor RecordingRPC: GatewayRPCRequesting {
    private let responses: [String: JSONValue.Object]
    private(set) var requests: [RPCRequest] = []

    init(responses: [String: JSONValue.Object]) {
        self.responses = responses
    }

    func request(
        method: String,
        params: JSONValue.Object,
        timeoutMilliseconds: Int64,
        allowNullResult: Bool
    ) async throws -> JSONValue.Object {
        requests.append(
            RPCRequest(
                method: method,
                params: params,
                timeoutMilliseconds: timeoutMilliseconds,
                allowNullResult: allowNullResult
            )
        )
        guard let response = responses[method] else {
            throw HermesError("No fixture for \(method)", retryable: false)
        }
        return response
    }
}

struct DashboardRequest: Equatable, Sendable {
    let connection: GatewayConnection
    let pathSegments: [String]
}

actor RecordingDashboard: GatewayDashboardReading {
    private let responses: [[String]: JSONValue.Object]
    private(set) var requests: [DashboardRequest] = []

    init(responses: [[String]: JSONValue.Object]) {
        self.responses = responses
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String]
    ) async throws -> JSONValue.Object {
        requests.append(
            DashboardRequest(
                connection: connection,
                pathSegments: pathSegments
            )
        )
        guard let response = responses[pathSegments] else {
            throw HermesError(
                "No dashboard fixture for \(pathSegments)",
                retryable: false
            )
        }
        return response
    }
}

struct QueryDashboardRequest: Equatable, Sendable {
    let connection: GatewayConnection
    let pathSegments: [String]
    let query: [String: String]
}

actor QueryRecordingDashboard: GatewayDashboardReading {
    private let response: JSONValue.Object
    private(set) var requests: [QueryDashboardRequest] = []

    init(response: JSONValue.Object) {
        self.response = response
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String]
    ) async throws -> JSONValue.Object {
        throw HermesError("Expected a bounded query", retryable: false)
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String],
        query: [String: String]
    ) async throws -> JSONValue.Object {
        requests.append(
            QueryDashboardRequest(
                connection: connection,
                pathSegments: pathSegments,
                query: query
            )
        )
        return response
    }
}

struct VoiceDashboardCall: Equatable, Sendable {
    let method: String
    let pathSegments: [String]
    let body: JSONValue.Object?
    let maximumBytes: Int64
}

actor RecordingVoiceDashboard: GatewayDashboardReading {
    private let getResponse: JSONValue.Object
    private var sendResponses: [JSONValue.Object]
    private let sendFailure: HermesError?
    private(set) var calls: [VoiceDashboardCall] = []

    init(
        getResponse: JSONValue.Object,
        sendResponses: [JSONValue.Object],
        sendFailure: HermesError? = nil
    ) {
        self.getResponse = getResponse
        self.sendResponses = sendResponses
        self.sendFailure = sendFailure
    }

    func getJSON(
        connection: GatewayConnection,
        pathSegments: [String]
    ) async throws -> JSONValue.Object {
        throw HermesError(
            "Unbounded dashboard reads are not expected",
            retryable: false
        )
    }

    func getJSONWithErrorDetail(
        connection: GatewayConnection,
        pathSegments: [String],
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        calls.append(
            VoiceDashboardCall(
                method: "GET",
                pathSegments: pathSegments,
                body: nil,
                maximumBytes: maximumBytes
            )
        )
        return getResponse
    }

    func sendJSON(
        connection: GatewayConnection,
        method: String,
        pathSegments: [String],
        body: JSONValue.Object,
        maximumBytes: Int64
    ) async throws -> JSONValue.Object {
        calls.append(
            VoiceDashboardCall(
                method: method,
                pathSegments: pathSegments,
                body: body,
                maximumBytes: maximumBytes
            )
        )
        if let sendFailure {
            throw sendFailure
        }
        guard !sendResponses.isEmpty else {
            throw HermesError(
                "No voice dashboard fixture",
                retryable: false
            )
        }
        return sendResponses.removeFirst()
    }
}

actor NoopConnectionClient: GatewayConnecting {
    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) async throws {}

    func close() async {}
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        handler(error)
    }
}
