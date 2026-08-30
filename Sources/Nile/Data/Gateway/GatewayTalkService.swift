import Foundation

/// Talk-mode composition over prompt and live-runtime-status capabilities.
struct GatewayTalkService: HermesTalkServing, Sendable {
    private let prompts: any HermesPromptServing
    private let runtimeStatus: any HermesLiveRuntimeStatusServing

    init(
        prompts: any HermesPromptServing,
        runtimeStatus: any HermesLiveRuntimeStatusServing
    ) {
        self.prompts = prompts
        self.runtimeStatus = runtimeStatus
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        try await prompts.submitPrompt(
            liveSessionID: liveSessionID,
            text: text
        )
    }

    func liveRuntimeStatus(liveSessionID: String) async throws -> String? {
        try await runtimeStatus.liveRuntimeStatus(
            liveSessionID: liveSessionID
        )
    }
}
