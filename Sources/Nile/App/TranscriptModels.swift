import Foundation

enum TranscriptRole: Equatable, Sendable {
    case user
    case assistant
    case system
}

enum ToolKind: Equatable, Sendable {
    case terminal
    case skill
    case memory
    case tool
}

struct MessageImage: Equatable, Sendable {
    let base64: String?
    let label: String
}

enum MessageAttachmentKind: Equatable, Sendable {
    case image
    case audio
    case video
    case file
}

struct MessageAttachment: Equatable, Sendable {
    let path: String
    let filename: String
    let kind: MessageAttachmentKind
    var previewBase64: String?
    var mimeType: String?

    init(
        path: String,
        filename: String,
        kind: MessageAttachmentKind,
        previewBase64: String? = nil,
        mimeType: String? = nil
    ) {
        self.path = path
        self.filename = filename
        self.kind = kind
        self.previewBase64 = previewBase64
        self.mimeType = mimeType
    }
}

struct TranscriptMessage: Equatable, Sendable, Identifiable {
    let id: String
    let role: TranscriptRole
    var content: String
    var images: [MessageImage]
    var attachments: [MessageAttachment]
    var pending: Bool
    var isError: Bool
    var isGoalPrompt: Bool

    init(
        id: String,
        role: TranscriptRole,
        content: String,
        images: [MessageImage] = [],
        attachments: [MessageAttachment] = [],
        pending: Bool = false,
        isError: Bool = false,
        isGoalPrompt: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.attachments = attachments
        self.pending = pending
        self.isError = isError
        self.isGoalPrompt = isGoalPrompt
    }
}

struct TranscriptTool: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    var status: String
    var content: String
    var outcome: ToolCompletionOutcome
    var kind: ToolKind
    var label: String?
    var summary: String?
    var durationSeconds: Double?
    var todos: [TodoItem]?
    var inlineDiff: String?
    var startedAtMilliseconds: Int64?

    init(
        id: String,
        name: String,
        status: String,
        content: String,
        outcome: ToolCompletionOutcome = .unknown,
        kind: ToolKind = .tool,
        label: String? = nil,
        summary: String? = nil,
        durationSeconds: Double? = nil,
        todos: [TodoItem]? = nil,
        inlineDiff: String? = nil,
        startedAtMilliseconds: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.content = content
        self.outcome = outcome
        self.kind = kind
        self.label = label
        self.summary = summary
        self.durationSeconds = durationSeconds
        self.todos = todos
        self.inlineDiff = inlineDiff
        self.startedAtMilliseconds = startedAtMilliseconds
    }
}

enum BlockingPromptKind: Equatable, Sendable {
    case clarification
    case approval
    case sudo
    case secret
    case unavailable
}

enum BlockingPromptStatus: Equatable, Sendable {
    case pending
    case submitting
    case resolved
    case uncertain
    case unavailable

    var isOpen: Bool {
        self == .pending || self == .submitting || self == .uncertain
    }
}

struct BlockingPromptAction: Equatable, Sendable, Identifiable {
    let value: String
    let label: String
    let destructive: Bool

    init(
        value: String,
        label: String,
        destructive: Bool = false
    ) {
        self.value = value
        self.label = label
        self.destructive = destructive
    }

    var id: String { value }
}

/// Safe display metadata for a one-shot Hermes input request.
///
/// Passwords, secrets, and free-text answers deliberately have no field here.
/// They flow directly from the view's ephemeral state to a typed repository call.
struct TranscriptBlockingPrompt: Equatable, Sendable, Identifiable {
    let id: String
    let kind: BlockingPromptKind
    let title: String
    let message: String?
    let detail: String?
    let actions: [BlockingPromptAction]
    let acceptsText: Bool
    let sensitive: Bool
    let skipLabel: String?
    var status: BlockingPromptStatus
    var statusMessage: String?
    var actionable: Bool

    init(
        id: String,
        kind: BlockingPromptKind,
        title: String,
        message: String? = nil,
        detail: String? = nil,
        actions: [BlockingPromptAction] = [],
        acceptsText: Bool = false,
        sensitive: Bool = false,
        skipLabel: String? = nil,
        status: BlockingPromptStatus = .pending,
        statusMessage: String? = nil,
        actionable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.detail = detail
        self.actions = actions
        self.acceptsText = acceptsText
        self.sensitive = sensitive
        self.skipLabel = skipLabel
        self.status = status
        self.statusMessage = statusMessage
        self.actionable = actionable
    }
}

struct TranscriptCommand: Equatable, Sendable, Identifiable {
    enum Status: String, Equatable, Sendable {
        case running
        case done
        case error
    }

    let id: String
    let command: String
    var output: String?
    var status: Status = .running
}

struct TranscriptDelegation: Equatable, Sendable, Identifiable {
    let id: String
    let turnID: String
}

enum TranscriptEntry: Equatable, Sendable, Identifiable {
    case message(TranscriptMessage)
    case tool(TranscriptTool)
    case blockingPrompt(TranscriptBlockingPrompt)
    case command(TranscriptCommand)
    case delegation(TranscriptDelegation)

    var id: String {
        switch self {
        case let .message(message):
            message.id
        case let .tool(tool):
            tool.id
        case let .blockingPrompt(prompt):
            prompt.id
        case let .command(command):
            command.id
        case let .delegation(delegation):
            delegation.id
        }
    }
}
