import Foundation

actor TuiGatewayClient: GatewayConnecting {
    private let webSocketFactory: any GatewayWebSocketFactory
    private let requestFactory: any GatewayRequestFactory
    let frameCodec = GatewayFrameCodec()
    private let rawSignalContinuation: AsyncStream<GatewaySignal>.Continuation
    private nonisolated let rawSignals: AsyncStream<GatewaySignal>

    private var nextGeneration: Int64 = 1
    private var latestConnectRequest: Int64 = 0
    var nextRequestID: Int64 = 1
    var currentAttempt: ConnectionAttempt?

    init(
        webSocketFactory: any GatewayWebSocketFactory = URLSessionGatewayWebSocketFactory(),
        requestFactory: any GatewayRequestFactory = LegacyGatewayRequestFactory()
    ) {
        self.webSocketFactory = webSocketFactory
        self.requestFactory = requestFactory
        let pair = AsyncStream<GatewaySignal>.makeStream(bufferingPolicy: .unbounded)
        rawSignals = pair.stream
        rawSignalContinuation = pair.continuation
    }

    nonisolated var signals: GatewaySignalSequence {
        GatewaySignalSequence(
            stream: rawSignals,
            acceptsGeneration: { [self] generation in
                await acceptsSignal(from: generation)
            }
        )
    }

    var isConnected: Bool {
        currentAttempt?.phase == .ready
    }

    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64 = 15_000
    ) async throws {
        if connection.endpoint.isCleartext
            && !connection.cleartextPermission.allowsCleartext {
            throw HermesError(
                "Cleartext gateway access has not been approved",
                retryable: false
            )
        }

        let generation = allocateGeneration()
        latestConnectRequest = generation
        let replaced = terminalEffects(
            for: currentAttempt?.generation,
            details: GatewayFailureClassification(
                message: "Gateway connection replaced",
                authRejected: false,
                retryable: false
            ),
            socketAction: currentAttempt?.phase == .ready
                ? .close(code: 1_000, reason: "Gateway connection replaced")
                : .cancel,
            emitFailure: false,
            clearCurrent: true
        )
        await apply(replaced)

        do {
            try await GatewayDeadline.run(
                milliseconds: timeoutMilliseconds
            ) { [self] in
                try await establish(connection, generation: generation)
            }
        } catch is GatewayDeadlineExceeded {
            let timeout = HermesError(
                "Gateway did not answer before the connection timeout",
                retryable: true,
                isConnectionFailure: true
            )
            let effects = terminalEffects(
                for: generation,
                details: GatewayFailureClassification(timeout),
                socketAction: .cancel,
                emitFailure: false,
                clearCurrent: true
            )
            await apply(effects)
            throw timeout
        } catch is CancellationError {
            let effects = terminalEffects(
                for: generation,
                details: GatewayFailureClassification(
                    message: "Gateway connection cancelled",
                    authRejected: false,
                    retryable: false
                ),
                socketAction: .cancel,
                emitFailure: false,
                clearCurrent: true
            )
            await apply(effects)
            throw CancellationError()
        } catch let error as GatewaySignInRequiredError {
            await discardConnectAttempt(generation: generation)
            throw error
        } catch let error as GatewayTokenRequiredError {
            await discardConnectAttempt(generation: generation)
            throw error
        } catch let error as GatewayProbeError {
            await discardConnectAttempt(generation: generation)
            throw error
        } catch let error as URLError {
            await discardConnectAttempt(generation: generation)
            throw error
        } catch let error as HermesError {
            let effects = terminalEffects(
                for: generation,
                details: GatewayFailureClassification(error),
                socketAction: .cancel,
                emitFailure: false,
                clearCurrent: true
            )
            await apply(effects)
            throw error
        } catch {
            let wrapped = HermesError(
                "Could not open the gateway connection",
                retryable: true,
                isConnectionFailure: true
            )
            let effects = terminalEffects(
                for: generation,
                details: GatewayFailureClassification(wrapped),
                socketAction: .cancel,
                emitFailure: false,
                clearCurrent: true
            )
            await apply(effects)
            throw wrapped
        }
    }

    private func discardConnectAttempt(generation: Int64) async {
        let effects = terminalEffects(
            for: generation,
            details: GatewayFailureClassification(
                message: "Gateway connection preparation failed",
                authRejected: false,
                retryable: false
            ),
            socketAction: .cancel,
            emitFailure: false,
            clearCurrent: true
        )
        await apply(effects)
    }

    func close() async {
        latestConnectRequest = allocateGeneration()
        let phase = currentAttempt?.phase
        let effects = terminalEffects(
            for: currentAttempt?.generation,
            details: GatewayFailureClassification(
                message: "Gateway connection closed",
                authRejected: false,
                retryable: false
            ),
            socketAction: phase == .ready
                ? .close(code: 1_000, reason: "Client disconnected")
                : .cancel,
            emitFailure: false,
            clearCurrent: true
        )
        await apply(effects)
    }

    private func acceptsSignal(from generation: Int64) -> Bool {
        currentAttempt?.generation == generation
    }

    func yieldSignal(_ signal: GatewaySignal) {
        rawSignalContinuation.yield(signal)
    }

    private func establish(
        _ connection: GatewayConnection,
        generation: Int64
    ) async throws {
        let request = try await requestFactory.makeRequest(for: connection)
        try Task.checkCancellation()
        guard latestConnectRequest == generation else {
            throw CancellationError()
        }

        let socket = try await webSocketFactory.makeWebSocket(for: request)
        try Task.checkCancellation()
        guard latestConnectRequest == generation else {
            await socket.cancel()
            throw CancellationError()
        }

        let ready = GatewayOneShot<Void>()
        currentAttempt = ConnectionAttempt(
            generation: generation,
            socket: socket,
            ready: ready
        )

        do {
            try await socket.start()
        } catch {
            throw GatewayConnectionFailurePolicy.connectionError(for: error)
        }
        try Task.checkCancellation()
        guard
            currentAttempt?.generation == generation,
            currentAttempt?.phase != .terminal
        else {
            await socket.cancel()
            throw CancellationError()
        }

        let receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(generation: generation, socket: socket)
        }
        currentAttempt?.receiveTask = receiveTask
        try await ready.value()
    }

    private func allocateGeneration() -> Int64 {
        let allocated = nextGeneration
        if nextGeneration == Int64.max {
            nextGeneration = 1
        } else {
            nextGeneration += 1
        }
        return allocated
    }
}

struct ConnectionAttempt {
    let generation: Int64
    let socket: any GatewayWebSocket
    let ready: GatewayOneShot<Void>
    var phase: ConnectionPhase = .connecting
    var pending: [Int64: PendingCall] = [:]
    var receiveTask: Task<Void, Never>?
}

enum ConnectionPhase {
    case connecting
    case ready
    case terminal
}
