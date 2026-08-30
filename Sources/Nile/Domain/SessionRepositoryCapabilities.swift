import Foundation

/// Explicit repository capabilities consumed by the session feature graph.
///
/// A provider may assemble these capabilities from one transport-backed object
/// or from independent implementations. `SessionRuntimeComposition` unwraps
/// the bundle once, then gives every feature runtime only its narrow protocol.
struct SessionRepositoryCapabilities: Sendable {
    let events: any HermesEventStreaming
    let sessions: any HermesSessionServing
    let sessionClaim: any HermesSessionClaimServing
    let sessionRenaming: any HermesSessionRenaming
    let turns: any HermesTurnServing
    let talk: any HermesTalkServing
    let delegation: any HermesDelegationServing
    let blockingPrompts: any HermesBlockingPromptServing
    let models: any HermesModelServing
    let sessionUsage: any HermesSessionUsageServing
    let gatewayStatistics: any HermesGatewayStatsServing
    let attachmentReading: any HermesAttachmentReading
    let attachmentMutating: any HermesAttachmentMutating
    let prompts: any HermesPromptServing
    let disconnect: any HermesDisconnectServing
    let transcription: any HermesTranscriptionServing
    let speechSynthesis: any HermesSpeechSynthesisServing
    let commands: any HermesCommandServing
    let goals: any HermesGoalServing

    init(
        events: any HermesEventStreaming,
        sessions: any HermesSessionServing,
        sessionClaim: any HermesSessionClaimServing,
        sessionRenaming: any HermesSessionRenaming,
        turns: any HermesTurnServing,
        talk: any HermesTalkServing,
        delegation: any HermesDelegationServing,
        blockingPrompts: any HermesBlockingPromptServing,
        models: any HermesModelServing,
        sessionUsage: any HermesSessionUsageServing,
        gatewayStatistics: any HermesGatewayStatsServing,
        attachmentReading: any HermesAttachmentReading,
        attachmentMutating: any HermesAttachmentMutating,
        prompts: any HermesPromptServing,
        disconnect: any HermesDisconnectServing,
        transcription: any HermesTranscriptionServing,
        speechSynthesis: any HermesSpeechSynthesisServing,
        commands: any HermesCommandServing,
        goals: any HermesGoalServing
    ) {
        self.events = events
        self.sessions = sessions
        self.sessionClaim = sessionClaim
        self.sessionRenaming = sessionRenaming
        self.turns = turns
        self.talk = talk
        self.delegation = delegation
        self.blockingPrompts = blockingPrompts
        self.models = models
        self.sessionUsage = sessionUsage
        self.gatewayStatistics = gatewayStatistics
        self.attachmentReading = attachmentReading
        self.attachmentMutating = attachmentMutating
        self.prompts = prompts
        self.disconnect = disconnect
        self.transcription = transcription
        self.speechSynthesis = speechSynthesis
        self.commands = commands
        self.goals = goals
    }

    init<Repository>(unified repository: Repository)
    where
        Repository: HermesEventStreaming,
        Repository: HermesDisconnectServing,
        Repository: HermesSessionServing,
        Repository: HermesTurnServing,
        Repository: HermesTalkServing,
        Repository: HermesDelegationServing,
        Repository: HermesBlockingPromptServing,
        Repository: HermesModelServing,
        Repository: HermesUsageServing,
        Repository: HermesAttachmentServing,
        Repository: HermesSpeechServing,
        Repository: HermesCommandServing,
        Repository: HermesGoalServing
    {
        self.init(
            events: repository,
            sessions: repository,
            sessionClaim: repository,
            sessionRenaming: repository,
            turns: repository,
            talk: repository,
            delegation: repository,
            blockingPrompts: repository,
            models: repository,
            sessionUsage: repository,
            gatewayStatistics: repository,
            attachmentReading: repository,
            attachmentMutating: repository,
            prompts: repository,
            disconnect: repository,
            transcription: repository,
            speechSynthesis: repository,
            commands: repository,
            goals: repository
        )
    }
}

/// Composition-root boundary for session repository dependencies.
///
/// Unlike the former all-capabilities repository protocol, conformers may
/// provide a bundle assembled from multiple independent collaborators.
protocol SessionRepositoryCapabilityProviding: Sendable {
    var sessionCapabilities: SessionRepositoryCapabilities { get }
}
