struct ModelSwitchConfirmation: Equatable, Sendable, Identifiable {
    let model: String
    let provider: String
    let message: String

    var id: String {
        "\(provider)/\(model)"
    }
}

struct ModelControlGatewayOwner: Equatable, Sendable {
    let gatewayGeneration: Int
    let gatewayID: String
}

struct ModelControlSessionOwner: Equatable, Sendable {
    let gatewayGeneration: Int
    let displayGeneration: Int
    let gatewayID: String
    let storedSessionID: String
    let liveSessionID: String
}

struct AppliedModelControl: Sendable {
    let owner: ModelControlSessionOwner
    let model: String?
    let provider: String?
    let reasoningEffort: String?
    let notice: String
}

typealias ModelControlAppliedHandler = @MainActor @Sendable (
    AppliedModelControl
) -> Void
typealias ModelControlErrorHandler = @MainActor @Sendable (String?) -> Void

extension SessionModelControlRuntime {
    typealias GatewayOwner = ModelControlGatewayOwner
    typealias SessionOwner = ModelControlSessionOwner
    typealias AppliedControl = AppliedModelControl
    typealias AppliedHandler = ModelControlAppliedHandler
    typealias ErrorHandler = ModelControlErrorHandler
}
