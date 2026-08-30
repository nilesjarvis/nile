import Foundation

extension TuiGatewayClient {
    func request(
        method: String,
        params: JSONValue.Object = [:],
        timeoutMilliseconds: Int64 = 30_000,
        allowNullResult: Bool = false
    ) async throws -> JSONValue.Object {
        guard !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesError("Gateway request method cannot be blank", retryable: false)
        }
        try Task.checkCancellation()

        guard
            var attempt = currentAttempt,
            attempt.phase == .ready
        else {
            throw HermesError(
                "Not connected to the Hermes gateway",
                retryable: true,
                isConnectionFailure: true
            )
        }

        let id = try allocateRequestID()
        let frame: String
        do {
            frame = try frameCodec.encodeRequest(id: id, method: method, params: params)
        } catch {
            throw HermesError("Could not encode the gateway request", retryable: false)
        }

        let token = UUID()
        let gate = GatewayOneShot<JSONValue.Object>()
        attempt.pending[id] = PendingCall(
            token: token,
            method: method,
            allowNullResult: allowNullResult,
            gate: gate
        )
        currentAttempt = attempt

        do {
            try Task.checkCancellation()
            try await attempt.socket.send(text: frame)
        } catch is CancellationError {
            removePending(id: id, token: token, generation: attempt.generation)
            throw CancellationError()
        } catch {
            removePending(id: id, token: token, generation: attempt.generation)
            throw await terminateAfterRequestSendFailure(generation: attempt.generation)
        }

        do {
            let response = try await GatewayDeadline.run(
                milliseconds: timeoutMilliseconds
            ) {
                try await gate.value()
            }
            removePending(id: id, token: token, generation: attempt.generation)
            return response
        } catch is GatewayDeadlineExceeded {
            removePending(id: id, token: token, generation: attempt.generation)
            throw HermesError(
                "Gateway request timed out: \(method)",
                retryable: true,
                requestMayHaveSucceeded: true
            )
        } catch is CancellationError {
            removePending(id: id, token: token, generation: attempt.generation)
            throw CancellationError()
        } catch {
            removePending(id: id, token: token, generation: attempt.generation)
            throw error
        }
    }

    func handleResponse(
        generation: Int64,
        id: Int64,
        response: GatewayInboundFrame
    ) {
        guard
            var attempt = currentAttempt,
            attempt.generation == generation,
            attempt.phase != .terminal,
            let pending = attempt.pending.removeValue(forKey: id)
        else {
            return
        }
        currentAttempt = attempt

        switch frameCodec.decodeResponse(
            response,
            allowNullResult: pending.allowNullResult
        ) {
        case let .invalid(reason):
            pending.gate.fail(
                HermesError(
                    "Malformed response to \(pending.method) (id \(id)): \(reason)",
                    retryable: false,
                    requestMayHaveSucceeded: true
                )
            )
        case let .error(code, message):
            pending.gate.fail(HermesError(message, code: code))
        case let .result(value):
            pending.gate.succeed(value)
        }
    }

    private func removePending(id: Int64, token: UUID, generation: Int64) {
        guard
            var attempt = currentAttempt,
            attempt.generation == generation,
            attempt.pending[id]?.token == token
        else {
            return
        }
        attempt.pending.removeValue(forKey: id)
        currentAttempt = attempt
    }

    private func allocateRequestID() throws -> Int64 {
        guard nextRequestID > 0, nextRequestID < Int64.max else {
            throw HermesError("Gateway request id space exhausted", retryable: false)
        }
        let allocated = nextRequestID
        nextRequestID += 1
        return allocated
    }
}

struct PendingCall {
    let token: UUID
    let method: String
    let allowNullResult: Bool
    let gate: GatewayOneShot<JSONValue.Object>
}
