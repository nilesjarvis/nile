import Foundation

let retainedSettledDelegationTurns = 3

struct DelegationOwner: Hashable, Sendable {
    let gatewayID: String
    let storedSessionID: String
}

enum DelegatedAgentStatus: Equatable, Sendable {
    case requested
    case running
    case interrupting
    case interruptUnconfirmed
    case completionUnknown
    case finished(SubagentTerminalStatus)

    var isFinished: Bool {
        if case .finished = self {
            return true
        }
        return false
    }

    var isActive: Bool {
        !isFinished
    }

    var isUnsuccessful: Bool {
        guard case let .finished(status) = self else {
            return false
        }
        return [.failed, .timeout, .error].contains(status)
    }
}

struct DelegatedAgentUI: Equatable, Sendable, Identifiable {
    let rowID: String
    let subagentID: String?
    let parentID: String?
    let childSessionID: String?
    let goal: String
    let taskCount: Int
    let taskIndex: Int
    let depth: Int?
    let model: String?
    let status: DelegatedAgentStatus
    let toolCount: Int
    let toolsets: [String]
    let latestActivity: String?
    let toolName: String?
    let toolPreview: String?
    let rawTerminalStatus: String?
    let summary: String?
    let durationSeconds: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let reasoningTokens: Int?
    let apiCalls: Int?
    let filesRead: [String]
    let filesWritten: [String]
    let outputTail: [SubagentOutput]

    var id: String { rowID }
}

struct DelegationTurnUI: Equatable, Sendable, Identifiable {
    let id: String
    let storedSessionID: String
    let agents: [DelegatedAgentUI]
    let startedAtEpochSeconds: Double?
    let finishedAtEpochSeconds: Double?
    let isPinned: Bool
}

struct DelegationProjection: Equatable, Sendable {
    let transcript: [TranscriptEntry]
    let turns: [DelegationTurnUI]
    let pinnedTurnID: String?
}

struct DelegationInterruptRequest: Equatable, Sendable {
    let sequence: Int64
    let subagentID: String
}
