import Foundation

struct BlockingPromptResponseTarget: Equatable {
    let gatewayID: String
    let liveSessionID: String
    let storedSessionID: String?
}

struct BlockingPromptSubmission {
    let promptID: String
    let kind: BlockingPromptKind
    let requestID: String?
    let liveSessionID: String
    let approvalChoice: ApprovalChoice?
    let resolvedStatusMessage: String
}

enum BlockingPromptSubmissionOutcome {
    case stale
    case settled
    case failed
    case retryableFailure(
        target: BlockingPromptResponseTarget,
        error: any Error
    )
}

struct BlockingPromptStatusPollToken: Equatable {
    let generation: Int64
    let arrivalWatermark: Int64
}

enum BlockingPromptEventResult: Equatable {
    case notHandled
    case consumed
    case added(liveSessionID: String)
}
