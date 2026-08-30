import Foundation

/// Prompt and active-turn mutation transport.
struct GatewayTurnService: HermesTurnServing, Sendable {
    private let rpc: any GatewayRPCRequesting

    init(rpc: any GatewayRPCRequesting) {
        self.rpc = rpc
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        let result = try await rpc.request(
            method: "prompt.submit",
            params: [
                "session_id": .string(liveSessionID),
                "text": .string(text),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: true
        )
        switch result.string("status") {
        case "streaming":
            return .streaming
        case "queued":
            return .queued
        case "steered":
            return .steered
        default:
            throw HermesError(
                "prompt.submit returned an unknown status",
                retryable: false,
                requestMayHaveSucceeded: true
            )
        }
    }

    func steer(liveSessionID: String, text: String) async throws -> Bool {
        let result = try await rpc.request(
            method: "session.steer",
            params: [
                "session_id": .string(liveSessionID),
                "text": .string(text),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try result.requireNonBlankString(
            method: "session.steer",
            name: "status"
        ) == "queued"
    }

    func interrupt(liveSessionID: String) async throws {
        _ = try await rpc.request(
            method: "session.interrupt",
            params: ["session_id": .string(liveSessionID)],
            timeoutMilliseconds: 30_000,
            allowNullResult: true
        )
    }
}
