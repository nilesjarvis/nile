import Foundation
import XCTest
@testable import Nile

final class TuiGatewayClientTests: XCTestCase, @unchecked Sendable {
    func testCleartextConnectionIsRejectedBeforeCredentialOrSocketWork() async throws {
        let factory = ScriptedWebSocketFactory([])
        let client = TuiGatewayClient(webSocketFactory: factory)
        let denied = try GatewayConnection(
            baseURL: "http://example.test/hermes",
            token: "secret",
            cleartextPermission: .denied
        )

        let error = await captureError {
            try await client.connect(denied, timeoutMilliseconds: 1_000)
        } as? HermesError
        let requests = await factory.requests

        XCTAssertTrue(error?.message.contains("not been approved") == true)
        XCTAssertFalse(error?.retryable ?? true)
        XCTAssertTrue(requests.isEmpty)
    }

    func testReadyHandshakeUsesProxyPrefixAndEncodesTokenOnce() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let factory = ScriptedWebSocketFactory([socket])
        let client = TuiGatewayClient(webSocketFactory: factory)
        addTeardownBlock { await client.close() }

        let token = "one&two #percent%"
        try await client.connect(try connection(token: token), timeoutMilliseconds: 1_000)

        let isConnected = await client.isConnected
        let capturedRequests = await factory.requests
        XCTAssertTrue(isConnected)
        let request = try XCTUnwrap(capturedRequests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/hermes/api/ws")
        XCTAssertEqual(
            components.queryItems?.filter { $0.name == "token" }.map(\.value),
            [token]
        )
    }

    func testHandshakeTimeoutCancelsOnlyThatGenerationAndNextConnectSucceeds() async throws {
        let silent = ScriptedWebSocket(autoReady: false)
        let healthy = ScriptedWebSocket(autoReady: true)
        let factory = ScriptedWebSocketFactory([silent, healthy])
        let client = TuiGatewayClient(webSocketFactory: factory)
        addTeardownBlock { await client.close() }

        let firstError = await captureError {
            try await client.connect(try connection(token: "first"), timeoutMilliseconds: 30)
        }
        XCTAssertTrue((firstError as? HermesError)?.message.contains("connection timeout") == true)
        let silentCancelCount = await silent.cancelCount
        let connectedAfterTimeout = await client.isConnected
        XCTAssertEqual(silentCancelCount, 1)
        XCTAssertFalse(connectedAfterTimeout)

        try await client.connect(try connection(token: "second"), timeoutMilliseconds: 1_000)
        let connectedAfterRetry = await client.isConnected
        XCTAssertTrue(connectedAfterRetry)
    }

    func testOverlappingConnectSupersedesOldAttemptAndIgnoresItsLateReady() async throws {
        let oldSocket = ScriptedWebSocket(autoReady: false)
        let newSocket = ScriptedWebSocket(autoReady: true)
        let factory = ScriptedWebSocketFactory([oldSocket, newSocket])
        let client = TuiGatewayClient(webSocketFactory: factory)
        addTeardownBlock { await client.close() }

        let oldConnect = Task {
            await captureError {
                try await client.connect(
                    try connection(token: "old"),
                    timeoutMilliseconds: 1_000
                )
            }
        }
        await oldSocket.waitUntilStarted()

        try await client.connect(try connection(token: "new"), timeoutMilliseconds: 1_000)
        await oldSocket.pushText(readyFrame)

        let oldError = await oldConnect.value as? HermesError
        let currentConnected = await client.isConnected
        let oldCancelCount = await oldSocket.cancelCount
        XCTAssertTrue(oldError?.message.contains("replaced") == true)
        XCTAssertTrue(currentConnected)
        XCTAssertEqual(oldCancelCount, 1)
    }

    func testCloseInvalidatesCredentialDiscoveryBeforeItCanInstallASocket() async throws {
        let factoryStarted = TestGate()
        let releaseFactory = TestGate()
        let requestFactory = ClosureRequestFactory { connection in
            await factoryStarted.open()
            await releaseFactory.wait()
            return URLRequest(url: try connection.webSocketURL())
        }
        let socketFactory = ScriptedWebSocketFactory([])
        let client = TuiGatewayClient(
            webSocketFactory: socketFactory,
            requestFactory: requestFactory
        )

        let connecting = Task {
            await captureError {
                try await client.connect(try connection(), timeoutMilliseconds: 1_000)
            }
        }
        await factoryStarted.wait()
        await client.close()
        await releaseFactory.open()

        let connectionError = await connecting.value
        let capturedRequests = await socketFactory.requests
        let connected = await client.isConnected
        XCTAssertTrue(connectionError is CancellationError)
        XCTAssertTrue(capturedRequests.isEmpty)
        XCTAssertFalse(connected)
    }

    func testConcurrentRequestsCorrelateOutOfOrderResponses() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let first = Task {
            try await client.request(method: "request.first", timeoutMilliseconds: 1_000)
        }
        let second = Task {
            try await client.request(method: "request.second", timeoutMilliseconds: 1_000)
        }
        let frames = [
            await socket.nextSentText(),
            await socket.nextSentText(),
        ]
        let byMethod = try Dictionary(
            uniqueKeysWithValues: frames.map { frame in
                (try requestMethod(frame), frame)
            }
        )

        try await respond(
            on: socket,
            to: byMethod["request.second"]!,
            result: ["value": "second"]
        )
        try await respond(
            on: socket,
            to: byMethod["request.first"]!,
            result: ["value": "first"]
        )

        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue["value"], .string("first"))
        XCTAssertEqual(secondValue["value"], .string("second"))
    }

    func testCancelledRequestDropsLateResponseWithoutAffectingNextCall() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let cancelled = Task {
            try await client.request(method: "request.cancelled", timeoutMilliseconds: 1_000)
        }
        let abandoned = await socket.nextSentText()
        cancelled.cancel()
        guard case .failure(let cancellation) = await cancelled.result else {
            return XCTFail("Expected cancellation")
        }
        XCTAssertTrue(cancellation is CancellationError)
        try await respond(on: socket, to: abandoned, result: ["stale": true])

        let next = Task {
            try await client.request(method: "request.next", timeoutMilliseconds: 1_000)
        }
        let nextFrame = await socket.nextSentText()
        try await respond(on: socket, to: nextFrame, result: ["fresh": true])
        let nextValue = try await next.value
        XCTAssertEqual(nextValue["fresh"], .bool(true))
    }

    func testClosePromptlyFailsPendingRequestAsOutcomeUncertain() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let pending = Task {
            await captureError {
                _ = try await client.request(
                    method: "approval.respond",
                    timeoutMilliseconds: 10_000
                )
            }
        }
        _ = await socket.nextSentText()
        await client.close()

        let error = await pending.value as? HermesError
        XCTAssertTrue(error?.message.contains("connection closed") == true)
        XCTAssertTrue(error?.requestMayHaveSucceeded == true)
        XCTAssertTrue(error?.isConnectionFailure == true)
        let connected = await client.isConnected
        XCTAssertFalse(connected)
    }

    func testPeerDisconnectFailsPendingRequestAndEmitsOrderedFailure() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let pending = Task {
            await captureError {
                _ = try await client.request(
                    method: "approval.respond",
                    timeoutMilliseconds: 10_000
                )
            }
        }
        _ = await socket.nextSentText()
        await socket.fail(
            GatewayWebSocketFailure(
                "closed",
                closeCode: 1_011,
                closeReason: "reply lost"
            )
        )

        let error = await pending.value as? HermesError
        XCTAssertTrue(error?.requestMayHaveSucceeded == true)
        XCTAssertTrue(error?.isConnectionFailure == true)
        var signals = client.signals.makeAsyncIterator()
        guard case let .failure(_, failure)? = await signals.next() else {
            return XCTFail("Expected terminal failure signal")
        }
        XCTAssertTrue(failure.retryable)
        XCTAssertTrue(failure.message.contains("reply lost"))
        let connected = await client.isConnected
        XCTAssertFalse(connected)
    }

    func testMalformedMatchingResponseFailsCallButKeepsSocketUsable() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let malformed = Task {
            await captureError {
                _ = try await client.request(
                    method: "strict.method",
                    timeoutMilliseconds: 1_000
                )
            }
        }
        let malformedFrame = await socket.nextSentText()
        try await respond(on: socket, to: malformedFrame, result: ["not", "object"])

        let error = await malformed.value as? HermesError
        XCTAssertTrue(error?.message.contains("strict.method") == true)
        XCTAssertTrue(error?.message.contains(String(try requestID(malformedFrame))) == true)
        XCTAssertTrue(error?.requestMayHaveSucceeded == true)
        XCTAssertFalse(error?.retryable ?? true)
        let connectedAfterMalformedResponse = await client.isConnected
        XCTAssertTrue(connectedAfterMalformedResponse)

        let valid = Task {
            try await client.request(method: "still.works", timeoutMilliseconds: 1_000)
        }
        let validFrame = await socket.nextSentText()
        try await respond(on: socket, to: validFrame, result: ["ok": true])
        let validValue = try await valid.value
        XCTAssertEqual(validValue["ok"], .bool(true))
    }

    func testNullResultsAreAcceptedOnlyWhenExplicitlyAllowed() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let voidCall = Task {
            try await client.request(
                method: "prompt.submit",
                timeoutMilliseconds: 1_000,
                allowNullResult: true
            )
        }
        let voidFrame = await socket.nextSentText()
        try await respond(on: socket, to: voidFrame, result: NSNull())
        let voidValue = try await voidCall.value
        XCTAssertTrue(voidValue.isEmpty)

        let objectCall = Task {
            await captureError {
                _ = try await client.request(
                    method: "session.list",
                    timeoutMilliseconds: 1_000
                )
            }
        }
        let objectFrame = await socket.nextSentText()
        try await respond(on: socket, to: objectFrame, result: NSNull())
        let error = await objectCall.value as? HermesError
        XCTAssertFalse(error?.retryable ?? true)
        XCTAssertTrue(error?.requestMayHaveSucceeded == true)
    }

    func testRequestTimeoutMarksSentMutationOutcomeUncertainWithoutClosingSocket() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let timedOut = Task {
            await captureError {
                _ = try await client.request(
                    method: "prompt.submit",
                    timeoutMilliseconds: 30,
                    allowNullResult: true
                )
            }
        }
        _ = await socket.nextSentText()
        let error = await timedOut.value as? HermesError

        XCTAssertTrue(error?.message.contains("timed out") == true)
        XCTAssertTrue(error?.requestMayHaveSucceeded == true)
        let connected = await client.isConnected
        XCTAssertTrue(connected)
    }

    func testEventBeforeReadyAndBinaryFramesFailClosed() async throws {
        let beforeReady = ScriptedWebSocket(autoReady: false)
        let firstClient = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([beforeReady])
        )
        let connecting = Task {
            await captureError {
                try await firstClient.connect(try connection(), timeoutMilliseconds: 1_000)
            }
        }
        await beforeReady.waitUntilStarted()
        await beforeReady.pushText(
            try eventFrame(type: "status.update", text: "too early")
        )
        let earlyError = await connecting.value as? HermesError
        XCTAssertTrue(earlyError?.message.contains("before gateway.ready") == true)
        let beforeReadyClosed = await beforeReady.closed
        let firstConnected = await firstClient.isConnected
        XCTAssertEqual(beforeReadyClosed.last?.code, 1_002)
        XCTAssertFalse(firstConnected)

        let binary = ScriptedWebSocket(autoReady: true)
        let secondClient = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([binary])
        )
        addTeardownBlock {
            await firstClient.close()
            await secondClient.close()
        }
        try await secondClient.connect(try connection(), timeoutMilliseconds: 1_000)
        await binary.pushData(Data([0x01, 0x02]))
        var signals = secondClient.signals.makeAsyncIterator()
        guard case let .failure(_, failure)? = await signals.next() else {
            return XCTFail("Expected binary protocol failure")
        }
        XCTAssertFalse(failure.retryable)
        let binaryClosed = await binary.closed
        let secondConnected = await secondClient.isConnected
        XCTAssertEqual(binaryClosed.last?.code, 1_002)
        XCTAssertFalse(secondConnected)
    }

    func testStaleBufferedSignalsAreDiscardedAfterGenerationChanges() async throws {
        let oldSocket = ScriptedWebSocket(autoReady: true)
        let newSocket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([oldSocket, newSocket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(token: "old"), timeoutMilliseconds: 1_000)
        await oldSocket.pushText(try eventFrame(type: "message.delta", text: "stale"))
        await Task.yield()

        try await client.connect(try connection(token: "new"), timeoutMilliseconds: 1_000)
        await newSocket.pushText(try eventFrame(type: "message.delta", text: "fresh"))

        var signals = client.signals.makeAsyncIterator()
        guard case let .event(_, frame)? = await signals.next() else {
            return XCTFail("Expected current-generation event")
        }
        XCTAssertEqual(frame.payload?["text"], .string("fresh"))
    }

    func testBufferedEventsRemainInWireOrderAheadOfTerminalFailure() async throws {
        let socket = ScriptedWebSocket(autoReady: true)
        let client = TuiGatewayClient(
            webSocketFactory: ScriptedWebSocketFactory([socket])
        )
        addTeardownBlock { await client.close() }
        try await client.connect(try connection(), timeoutMilliseconds: 1_000)

        let collector = Task { () -> [GatewaySignal] in
            var iterator = client.signals.makeAsyncIterator()
            var collected: [GatewaySignal] = []
            while collected.count < 102, let signal = await iterator.next() {
                collected.append(signal)
            }
            return collected
        }
        for index in 0..<100 {
            await socket.pushText(
                try eventFrame(type: "message.delta", text: String(index))
            )
        }
        await socket.pushText(
            try eventFrame(type: "message.complete", text: "done")
        )
        await socket.fail(
            GatewayWebSocketFailure(
                "closed",
                closeCode: 1_000,
                closeReason: "restart"
            )
        )

        let signals = await collector.value
        XCTAssertEqual(signals.count, 102)
        for index in 0..<100 {
            guard case let .event(_, frame) = signals[index] else {
                return XCTFail("Expected event at index \(index)")
            }
            XCTAssertEqual(frame.payload?["text"], .string(String(index)))
        }
        guard case let .event(_, complete) = signals[100] else {
            return XCTFail("Expected completion event")
        }
        XCTAssertEqual(complete.type, "message.complete")
        guard case .failure = signals[101] else {
            return XCTFail("Expected failure after every buffered event")
        }
    }

    func testAuthenticationAndPolicyFailuresRemainDistinctAndRedacted() async throws {
        for (failure, authRejected, phrase) in [
            (
                GatewayWebSocketFailure("upgrade", httpStatusCode: 401),
                true,
                "HTTP 401"
            ),
            (
                GatewayWebSocketFailure("upgrade", httpStatusCode: 403),
                false,
                "Host policy"
            ),
            (
                GatewayWebSocketFailure(
                    "closed",
                    closeCode: 4_401,
                    closeReason: "expired ?token=should-not-appear"
                ),
                true,
                "4401"
            ),
            (
                GatewayWebSocketFailure(
                    "closed",
                    closeCode: 4_403,
                    closeReason: "host denied"
                ),
                false,
                "access policy"
            ),
        ] {
            let socket = ScriptedWebSocket(
                autoReady: false,
                initialFailure: failure
            )
            let client = TuiGatewayClient(
                webSocketFactory: ScriptedWebSocketFactory([socket])
            )
            let error = await captureError {
                try await client.connect(try connection(), timeoutMilliseconds: 1_000)
            } as? HermesError
            XCTAssertEqual(error?.authRejected, authRejected)
            XCTAssertTrue(error?.message.contains(phrase) == true)
            XCTAssertFalse(error?.message.contains("should-not-appear") == true)
            await client.close()
        }
    }
}

private actor ScriptedWebSocketFactory: GatewayWebSocketFactory {
    private var sockets: [ScriptedWebSocket]
    private(set) var requests: [URLRequest] = []

    init(_ sockets: [ScriptedWebSocket]) {
        self.sockets = sockets
    }

    func makeWebSocket(for request: URLRequest) async throws -> any GatewayWebSocket {
        requests.append(request)
        guard !sockets.isEmpty else {
            throw GatewayWebSocketFailure("No scripted socket was available")
        }
        return sockets.removeFirst()
    }
}

private actor ScriptedWebSocket: GatewayWebSocket {
    struct Closed: Equatable, Sendable {
        let code: Int
        let reason: String?
    }

    private enum Inbound: Sendable {
        case message(GatewayWebSocketMessage)
        case failure(GatewayWebSocketFailure)
    }

    private let autoReady: Bool
    private let initialFailure: GatewayWebSocketFailure?
    private var inbound: [Inbound] = []
    private var receiveWaiters: [CheckedContinuation<GatewayWebSocketMessage, Error>] = []
    private var sent: [String] = []
    private var sendWaiters: [CheckedContinuation<String, Never>] = []
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelCount = 0
    private(set) var closed: [Closed] = []

    init(
        autoReady: Bool,
        initialFailure: GatewayWebSocketFailure? = nil
    ) {
        self.autoReady = autoReady
        self.initialFailure = initialFailure
    }

    func start() async throws {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if let initialFailure {
            enqueue(.failure(initialFailure))
        } else if autoReady {
            enqueue(.message(.text(readyFrame)))
        }
    }

    func send(text: String) async throws {
        if sendWaiters.isEmpty {
            sent.append(text)
        } else {
            sendWaiters.removeFirst().resume(returning: text)
        }
    }

    func receive() async throws -> GatewayWebSocketMessage {
        if !inbound.isEmpty {
            return try resolve(inbound.removeFirst())
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveWaiters.append(continuation)
        }
    }

    func close(code: Int, reason: String?) async {
        closed.append(Closed(code: code, reason: reason))
        finishReceivers()
    }

    func cancel() async {
        cancelCount += 1
        finishReceivers()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func nextSentText() async -> String {
        if !sent.isEmpty {
            return sent.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            sendWaiters.append(continuation)
        }
    }

    func pushText(_ text: String) {
        enqueue(.message(.text(text)))
    }

    func pushData(_ data: Data) {
        enqueue(.message(.data(data)))
    }

    func fail(_ failure: GatewayWebSocketFailure) {
        enqueue(.failure(failure))
    }

    private func enqueue(_ item: Inbound) {
        guard !receiveWaiters.isEmpty else {
            inbound.append(item)
            return
        }
        let waiter = receiveWaiters.removeFirst()
        switch item {
        case let .message(message):
            waiter.resume(returning: message)
        case let .failure(error):
            waiter.resume(throwing: error)
        }
    }

    private func resolve(_ item: Inbound) throws -> GatewayWebSocketMessage {
        switch item {
        case let .message(message):
            message
        case let .failure(error):
            throw error
        }
    }

    private func finishReceivers() {
        let waiters = receiveWaiters
        receiveWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private struct ClosureRequestFactory: GatewayRequestFactory {
    let body: @Sendable (GatewayConnection) async throws -> URLRequest

    func makeRequest(for connection: GatewayConnection) async throws -> URLRequest {
        try await body(connection)
    }
}

private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private let readyFrame =
    #"{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}}"# + "\n"

private func connection(token: String = "secret") throws -> GatewayConnection {
    try GatewayConnection(
        baseURL: "http://example.test/hermes",
        token: token,
        cleartextPermission: .approved
    )
}

private func eventFrame(type: String, text: String) throws -> String {
    try jsonLine([
        "jsonrpc": "2.0",
        "method": "event",
        "params": [
            "type": type,
            "session_id": "live-1",
            "payload": ["text": text],
        ],
    ])
}

private func respond(
    on socket: ScriptedWebSocket,
    to request: String,
    result: Any
) async throws {
    await socket.pushText(
        try jsonLine([
            "jsonrpc": "2.0",
            "id": try requestID(request),
            "result": result,
        ])
    )
}

private func requestMethod(_ text: String) throws -> String {
    let object = try requestObject(text)
    return try XCTUnwrap(object["method"] as? String)
}

private func requestID(_ text: String) throws -> Int64 {
    let object = try requestObject(text)
    return try XCTUnwrap((object["id"] as? NSNumber)?.int64Value)
}

private func requestObject(_ text: String) throws -> [String: Any] {
    let data = try XCTUnwrap(text.data(using: .utf8))
    return try XCTUnwrap(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
}

private func jsonLine(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try XCTUnwrap(String(data: data, encoding: .utf8)) + "\n"
}

private func captureError(
    _ operation: @Sendable () async throws -> Void
) async -> any Error {
    do {
        try await operation()
        return TestFailure.expectedError
    } catch {
        return error
    }
}

private enum TestFailure: Error {
    case expectedError
}
