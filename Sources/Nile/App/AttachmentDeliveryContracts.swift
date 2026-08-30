import Foundation

struct OutboundAttachmentBatch: Equatable, Sendable, Identifiable {
    let id: String
    let owner: ComposerDraftOwner
    let liveSessionID: String
    let input: String
    let attachments: [PendingAttachment]
    let userEntryID: String
    let userMessagesBefore: Int
}

struct ServerAttachmentLease: Hashable, Sendable {
    let owner: ComposerDraftOwner
    let liveSessionID: String
    let path: String
}

enum AttachmentUncertainty: String, Equatable, Sendable {
    case uploadPath
    case promptOutcome
}

struct UncertainAttachmentRuntime: Hashable, Sendable {
    let mutationID: String
    let owner: ComposerDraftOwner
    let liveSessionID: String
    let kind: AttachmentUncertainty
}

enum AttachmentSubmitResolution: Equatable, Sendable {
    case streamingAccepted(turnEndedBeforeResponse: Bool)
    case previouslyAccepted
    case steered(turnAlreadyCompleted: Bool)
    case preStartError(String)
    case awaitStreamingStart
    case noFollowUp
}

struct AttachmentBatchState: Equatable, Sendable {
    let batch: OutboundAttachmentBatch?
    let dispatched: Bool
    let accepted: Bool
    let awaitingResponse: Bool
    let submitStatus: PromptSubmitStatus?
    let bufferedStart: Bool
    let bufferedCompletion: Bool
    let bufferedError: String?
}
