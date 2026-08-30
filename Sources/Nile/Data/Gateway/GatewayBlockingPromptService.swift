import Foundation

/// Owns typed, fail-closed blocking-prompt response RPCs.
struct GatewayBlockingPromptService: HermesBlockingPromptServing, Sendable {
    private let rpc: any GatewayRPCRequesting

    init(rpc: any GatewayRPCRequesting) {
        self.rpc = rpc
    }

    func respondToClarification(
        requestID: String,
        answer: String
    ) async throws {
        try requireResponseID(requestID, method: "clarify.respond")
        let result = try await rpc.request(
            method: "clarify.respond",
            params: [
                "request_id": .string(requestID),
                "answer": .string(answer),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        try requireOKMutation(result, method: "clarify.respond")
    }

    func respondToSudo(
        requestID: String,
        password: String
    ) async throws {
        try requireResponseID(requestID, method: "sudo.respond")
        let result = try await rpc.request(
            method: "sudo.respond",
            params: [
                "request_id": .string(requestID),
                "password": .string(password),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        try requireOKMutation(result, method: "sudo.respond")
    }

    func respondToSecret(
        requestID: String,
        value: String
    ) async throws {
        try requireResponseID(requestID, method: "secret.respond")
        let result = try await rpc.request(
            method: "secret.respond",
            params: [
                "request_id": .string(requestID),
                "value": .string(value),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        try requireOKMutation(result, method: "secret.respond")
    }

    func respondToApproval(
        liveSessionID: String,
        choice: ApprovalChoice
    ) async throws -> Bool {
        guard !liveSessionID.isBlank else {
            throw HermesError(
                "approval.respond requires a live session id",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "approval.respond",
            params: [
                "session_id": .string(liveSessionID),
                "choice": .string(choice.rawValue),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        guard case let .number(value)? = result["resolved"],
              value.isFinite,
              value.rounded(.towardZero) == value,
              value == 0 || value == 1 else {
            throw HermesError(
                "Malformed response to approval.respond: resolved was not 0 or 1",
                retryable: false,
                requestMayHaveSucceeded: true
            )
        }
        return value == 1
    }

    private func requireResponseID(
        _ requestID: String,
        method: String
    ) throws {
        guard !requestID.isBlank else {
            throw HermesError(
                "\(method) requires a request id",
                retryable: false
            )
        }
    }

    private func requireOKMutation(
        _ result: JSONValue.Object,
        method: String
    ) throws {
        guard result["status"] == .string("ok") else {
            throw HermesError(
                "Malformed response to \(method): status was not ok",
                retryable: false,
                requestMayHaveSucceeded: true
            )
        }
    }
}
