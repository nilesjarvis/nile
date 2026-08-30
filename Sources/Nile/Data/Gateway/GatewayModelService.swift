import Foundation

/// Owns model catalog and session-scoped model/reasoning mutation RPCs.
struct GatewayModelService: HermesModelServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let codec = GatewayModelCodec()

    init(rpc: any GatewayRPCRequesting) {
        self.rpc = rpc
    }

    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) async throws -> ModelOptions {
        var params: JSONValue.Object = [:]
        if let liveSessionID, !liveSessionID.isBlank {
            params["session_id"] = .string(liveSessionID)
        }
        if refresh {
            params["refresh"] = .bool(true)
        }
        let result = try await rpc.request(
            method: "model.options",
            params: params,
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try codec.decodeOptions(result)
    }

    func setSessionModel(
        liveSessionID: String,
        model: String,
        provider: String?,
        confirmExpensiveModel: Bool
    ) async throws -> ModelSwitchOutcome {
        guard !liveSessionID.isBlank else {
            throw HermesError(
                "config.set model requires a live session id",
                retryable: false
            )
        }
        try GatewayModelArgumentPolicy.requireSafeModelName(model)
        if let provider {
            try GatewayModelArgumentPolicy.requireSafeProviderIdentifier(
                provider
            )
        }
        var value = model
        if let provider {
            value += " --provider \(provider)"
        }
        value += " --session"
        let result = try await rpc.request(
            method: "config.set",
            params: [
                "session_id": .string(liveSessionID),
                "key": .string("model"),
                "value": .string(value),
                "confirm_expensive_model": .bool(confirmExpensiveModel),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try codec.decodeSwitchOutcome(result)
    }

    func setReasoningEffort(
        liveSessionID: String,
        effort: String
    ) async throws -> String {
        guard !liveSessionID.isBlank else {
            throw HermesError(
                "config.set reasoning requires a live session id",
                retryable: false
            )
        }
        let normalized = effort
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard reasoningEffortOptions.contains(normalized) else {
            throw HermesError(
                "config.set reasoning cannot encode that effort value safely",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "config.set",
            params: [
                "session_id": .string(liveSessionID),
                "key": .string("reasoning"),
                "value": .string(normalized),
                "scope": .string("session"),
            ],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        return try codec.decodeReasoningMutation(result)
    }
}
