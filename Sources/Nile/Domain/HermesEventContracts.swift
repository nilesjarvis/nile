protocol HermesEventStreaming: Sendable {
    var events: AsyncStream<HermesStreamEvent> { get }
}

enum HermesStreamEvent: Equatable, Sendable {
    case messageStart(sessionID: String)
    case subagentUpdate(
        sessionID: String,
        kind: SubagentEventKind,
        data: SubagentEventData
    )
    case assistantDelta(sessionID: String, text: String)
    case assistantInterim(sessionID: String, text: String)
    case assistantCompleted(
        sessionID: String,
        text: String,
        usage: UsageSummary?
    )
    case thinkingDelta(sessionID: String, text: String)
    case thinkingStatus(sessionID: String, text: String)
    case toolStart(
        sessionID: String,
        toolID: String?,
        name: String,
        detail: String?,
        context: String?,
        generating: Bool
    )
    case toolComplete(
        sessionID: String,
        toolID: String?,
        name: String,
        result: String?,
        outcome: ToolCompletionOutcome,
        summary: String?,
        durationSeconds: Double?,
        todos: [TodoItem]?,
        inlineDiff: String?
    )
    case clarificationRequest(
        sessionID: String,
        requestID: String,
        question: String,
        choices: [String]?
    )
    case approvalRequest(
        sessionID: String,
        command: String,
        description: String,
        allowPermanent: Bool
    )
    case sudoRequest(sessionID: String, requestID: String)
    case secretRequest(
        sessionID: String,
        requestID: String,
        envVar: String,
        prompt: String,
        metadata: SecretRequestMetadata?
    )
    case blockingRequestInvalid(
        sessionID: String,
        requestType: String,
        message: String
    )
    case compactionStarted(sessionID: String, estimatedTokens: Int64?)
    case statusUpdate(sessionID: String, text: String)
    case goalUpdate(
        sessionID: String,
        text: String,
        update: GoalProgressUpdate
    )
    case sessionInfoUpdate(sessionID: String, info: SessionInfo)
    case error(sessionID: String, message: String)
    case connectionLost(message: String, authRejected: Bool, retryable: Bool)

    var sessionID: String {
        switch self {
        case let .messageStart(sessionID),
            let .subagentUpdate(sessionID, _, _),
            let .assistantDelta(sessionID, _),
            let .assistantInterim(sessionID, _),
            let .assistantCompleted(sessionID, _, _),
            let .thinkingDelta(sessionID, _),
            let .thinkingStatus(sessionID, _),
            let .toolStart(sessionID, _, _, _, _, _),
            let .toolComplete(sessionID, _, _, _, _, _, _, _, _),
            let .clarificationRequest(sessionID, _, _, _),
            let .approvalRequest(sessionID, _, _, _),
            let .sudoRequest(sessionID, _),
            let .secretRequest(sessionID, _, _, _, _),
            let .blockingRequestInvalid(sessionID, _, _),
            let .compactionStarted(sessionID, _),
            let .statusUpdate(sessionID, _),
            let .goalUpdate(sessionID, _, _),
            let .sessionInfoUpdate(sessionID, _),
            let .error(sessionID, _):
            sessionID
        case .connectionLost:
            ""
        }
    }
}
