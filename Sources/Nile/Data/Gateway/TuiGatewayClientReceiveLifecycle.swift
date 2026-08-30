import Foundation

extension TuiGatewayClient {
    func receiveLoop(
        generation: Int64,
        socket: any GatewayWebSocket
    ) async {
        do {
            while !Task.isCancelled {
                switch try await socket.receive() {
                case let .text(text):
                    for line in text.split(
                        omittingEmptySubsequences: false,
                        whereSeparator: \.isNewline
                    ) where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await handleLine(
                            generation: generation,
                            socket: socket,
                            line: String(line)
                        )
                    }
                case .data:
                    await protocolViolation(
                        generation: generation,
                        socket: socket,
                        detail: "binary messages are not supported"
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await receiveFailed(generation: generation, error: error)
        }
    }

    private func handleLine(
        generation: Int64,
        socket: any GatewayWebSocket,
        line: String
    ) async {
        guard acceptsCallback(generation: generation, socket: socket) else {
            return
        }
        switch frameCodec.decodeInbound(line) {
        case let .invalid(reason):
            await protocolViolation(
                generation: generation,
                socket: socket,
                detail: reason
            )
        case .ignored:
            break
        case .ready:
            handleReady(generation: generation)
        case let .event(frame):
            if currentAttempt?.phase != .ready {
                await protocolViolation(
                    generation: generation,
                    socket: socket,
                    detail: "event arrived before gateway.ready"
                )
            } else {
                yieldSignal(.event(generation: generation, frame: frame))
            }
        case let .response(id, _):
            handleResponse(
                generation: generation,
                id: id,
                response: frameCodec.decodeInbound(line)
            )
        }
    }

    private func handleReady(generation: Int64) {
        guard
            var attempt = currentAttempt,
            attempt.generation == generation,
            attempt.phase == .connecting
        else {
            return
        }
        attempt.phase = .ready
        currentAttempt = attempt
        attempt.ready.succeed(())
    }

    private func protocolViolation(
        generation: Int64,
        socket: any GatewayWebSocket,
        detail: String
    ) async {
        guard acceptsCallback(generation: generation, socket: socket) else {
            return
        }
        let message = "Gateway sent an invalid protocol frame: \(detail)"
        let effects = terminalEffects(
            for: generation,
            details: GatewayFailureClassification(
                message: message,
                authRejected: false,
                retryable: false
            ),
            socketAction: .close(code: 1_002, reason: "Invalid JSON-RPC frame"),
            emitFailure: true,
            clearCurrent: false
        )
        await apply(effects)
    }

    private func receiveFailed(generation: Int64, error: any Error) async {
        let details = GatewayConnectionFailurePolicy.classify(error)
        let effects = terminalEffects(
            for: generation,
            details: details,
            socketAction: .none,
            emitFailure: true,
            clearCurrent: false
        )
        await apply(effects)
    }

    func terminateAfterRequestSendFailure(generation: Int64) async -> HermesError {
        let error = HermesError(
            "Gateway connection lost",
            retryable: true,
            isConnectionFailure: true
        )
        let effects = terminalEffects(
            for: generation,
            details: GatewayFailureClassification(error),
            socketAction: .cancel,
            emitFailure: true,
            clearCurrent: false
        )
        await apply(effects)
        return error
    }

    func terminalEffects(
        for generation: Int64?,
        details: GatewayFailureClassification,
        socketAction: SocketAction,
        emitFailure: Bool,
        clearCurrent: Bool
    ) -> TerminalEffects? {
        guard
            let generation,
            var attempt = currentAttempt,
            attempt.generation == generation
        else {
            return nil
        }
        if attempt.phase == .terminal {
            if clearCurrent {
                currentAttempt = nil
            }
            return nil
        }

        let wasReady = attempt.phase == .ready
        attempt.phase = .terminal
        let pending = Array(attempt.pending.values)
        attempt.pending.removeAll(keepingCapacity: false)
        if clearCurrent {
            currentAttempt = nil
        } else {
            currentAttempt = attempt
        }

        if emitFailure && wasReady {
            yieldSignal(
                .failure(
                    generation: generation,
                    failure: GatewayFailure(
                        message: details.message,
                        authRejected: details.authRejected,
                        retryable: details.retryable
                    )
                )
            )
        }

        return TerminalEffects(
            socket: attempt.socket,
            receiveTask: attempt.receiveTask,
            ready: attempt.ready,
            pending: pending,
            details: details,
            socketAction: socketAction
        )
    }

    func apply(_ effects: TerminalEffects?) async {
        guard let effects else { return }
        effects.receiveTask?.cancel()
        switch effects.socketAction {
        case .none:
            break
        case .cancel:
            await effects.socket.cancel()
        case let .close(code, reason):
            await effects.socket.close(code: code, reason: reason)
        }

        effects.ready.fail(
            HermesError(
                effects.details.message,
                authRejected: effects.details.authRejected,
                retryable: effects.details.retryable,
                isConnectionFailure: true
            )
        )
        for pending in effects.pending {
            pending.gate.fail(
                HermesError(
                    "\(effects.details.message) while waiting for \(pending.method)",
                    authRejected: effects.details.authRejected,
                    retryable: effects.details.retryable,
                    isConnectionFailure: true,
                    requestMayHaveSucceeded: true
                )
            )
        }
    }

    private func acceptsCallback(
        generation: Int64,
        socket: any GatewayWebSocket
    ) -> Bool {
        guard
            let attempt = currentAttempt,
            attempt.generation == generation,
            attempt.phase != .terminal
        else {
            return false
        }
        return ObjectIdentifier(attempt.socket as AnyObject)
            == ObjectIdentifier(socket as AnyObject)
    }
}

struct TerminalEffects {
    let socket: any GatewayWebSocket
    let receiveTask: Task<Void, Never>?
    let ready: GatewayOneShot<Void>
    let pending: [PendingCall]
    let details: GatewayFailureClassification
    let socketAction: SocketAction
}

enum SocketAction {
    case none
    case cancel
    case close(code: Int, reason: String?)
}
