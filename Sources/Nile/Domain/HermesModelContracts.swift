struct ModelCapabilities: Equatable, Sendable {
    let fast: Bool
    let reasoning: Bool
}

struct ModelPricing: Equatable, Sendable {
    let input: String?
    let output: String?
    let cache: String?
    let free: Bool
}

struct ModelPin: Hashable, Codable, Sendable {
    let providerSlug: String?
    let modelID: String
}

struct ModelProvider: Equatable, Sendable {
    let slug: String
    let name: String?
    let authenticated: Bool
    let isCurrent: Bool
    let models: [String]
    let capabilities: [String: ModelCapabilities]
    let pricing: [String: ModelPricing]
    let freeTier: Bool?
    let unavailableModels: Set<String>

    init(
        slug: String,
        name: String?,
        authenticated: Bool,
        isCurrent: Bool,
        models: [String],
        capabilities: [String: ModelCapabilities] = [:],
        pricing: [String: ModelPricing] = [:],
        freeTier: Bool? = nil,
        unavailableModels: Set<String> = []
    ) {
        self.slug = slug
        self.name = name
        self.authenticated = authenticated
        self.isCurrent = isCurrent
        self.models = models
        self.capabilities = capabilities
        self.pricing = pricing
        self.freeTier = freeTier
        self.unavailableModels = unavailableModels
    }
}

struct ModelOptions: Equatable, Sendable {
    let model: String?
    let provider: String?
    let providers: [ModelProvider]
}

let reasoningEffortOptions = [
    "none",
    "minimal",
    "low",
    "medium",
    "high",
    "xhigh",
    "max",
]

enum ModelSwitchOutcome: Equatable, Sendable {
    case applied(resolvedModel: String, warning: String?)
    case confirmationRequired(resolvedModel: String, message: String)
}

protocol HermesModelOptionsServing: Sendable {
    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) async throws -> ModelOptions
}

protocol HermesModelMutationServing: Sendable {
    func setSessionModel(
        liveSessionID: String,
        model: String,
        provider: String?,
        confirmExpensiveModel: Bool
    ) async throws -> ModelSwitchOutcome
    func setReasoningEffort(
        liveSessionID: String,
        effort: String
    ) async throws -> String
}

protocol HermesModelServing:
    HermesModelOptionsServing,
    HermesModelMutationServing
{}

extension HermesModelServing {
    func modelOptions() async throws -> ModelOptions {
        try await modelOptions(liveSessionID: nil, refresh: false)
    }

    func setSessionModel(
        liveSessionID: String,
        model: String,
        provider: String?
    ) async throws -> ModelSwitchOutcome {
        try await setSessionModel(
            liveSessionID: liveSessionID,
            model: model,
            provider: provider,
            confirmExpensiveModel: false
        )
    }

    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) async throws -> ModelOptions {
        throw HermesError(
            "Model controls are unavailable for this repository",
            retryable: false
        )
    }

    func setSessionModel(
        liveSessionID: String,
        model: String,
        provider: String?,
        confirmExpensiveModel: Bool
    ) async throws -> ModelSwitchOutcome {
        throw HermesError(
            "Model controls are unavailable for this repository",
            retryable: false
        )
    }

    func setReasoningEffort(
        liveSessionID: String,
        effort: String
    ) async throws -> String {
        throw HermesError(
            "Reasoning controls are unavailable for this repository",
            retryable: false
        )
    }
}
