enum SubagentEventKind: String, Codable, Sendable {
    case spawnRequested
    case started
    case thinking
    case tool
    case progress
    case completed
}

enum SubagentTerminalStatus: String, Codable, Sendable {
    case completed
    case interrupted
    case failed
    case timeout
    case error
    case unknown
}

struct SubagentOutput: Equatable, Sendable {
    let tool: String
    let preview: String?
    let isError: Bool
    let status: String?

    init(
        tool: String,
        preview: String? = nil,
        isError: Bool = false,
        status: String? = nil
    ) {
        self.tool = tool
        self.preview = preview
        self.isError = isError
        self.status = status
    }
}

struct SubagentEventData: Equatable, Sendable {
    let goal: String
    let taskCount: Int
    let taskIndex: Int
    let subagentID: String?
    let parentID: String?
    let childSessionID: String?
    let depth: Int?
    let model: String?
    let toolCount: Int?
    let toolsets: [String]
    let text: String?
    let toolName: String?
    let toolPreview: String?
    let terminalStatus: SubagentTerminalStatus?
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
}

struct ActiveSubagent: Equatable, Sendable {
    let subagentID: String
    let parentID: String?
    let depth: Int?
    let goal: String?
    let model: String?
    let startedAtEpochSeconds: Double?
    let toolCount: Int?
    let status: String?
}

struct DelegationStatus: Equatable, Sendable {
    let active: [ActiveSubagent]
    let paused: Bool
    let maxSpawnDepth: Int
    let maxConcurrentChildren: Int
}

struct SubagentInterruptResult: Equatable, Sendable {
    let found: Bool
    let subagentID: String
}

struct DelegationSnapshotAgent: Equatable, Sendable {
    let goal: String
    let taskCount: Int
    let taskIndex: Int
    let subagentID: String?
    let parentID: String?
    let childSessionID: String?
    let depth: Int?
    let model: String?
    let toolCount: Int?
    let toolsets: [String]
    let text: String?
    let toolName: String?
    let toolPreview: String?
    let terminalStatus: SubagentTerminalStatus?
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
}

struct DelegationSnapshot: Equatable, Sendable {
    let storedSessionID: String
    let startedAtEpochSeconds: Double?
    let finishedAtEpochSeconds: Double
    let label: String
    let agents: [DelegationSnapshotAgent]
}

struct DelegationSnapshotInfo: Equatable, Sendable {
    let path: String
    let storedSessionID: String
    let startedAtEpochSeconds: Double?
    let finishedAtEpochSeconds: Double
    let label: String
    let count: Int
}

protocol HermesDelegationServing: Sendable {
    func delegationStatus() async throws -> DelegationStatus
    func interruptSubagent(subagentID: String) async throws -> SubagentInterruptResult
    func saveDelegationSnapshot(_ snapshot: DelegationSnapshot) async throws -> String
    func listDelegationSnapshots(
        storedSessionID: String,
        limit: Int
    ) async throws -> [DelegationSnapshotInfo]
    func loadDelegationSnapshot(path: String) async throws -> DelegationSnapshot
}

extension HermesDelegationServing {
    func listDelegationSnapshots(
        storedSessionID: String
    ) async throws -> [DelegationSnapshotInfo] {
        try await listDelegationSnapshots(
            storedSessionID: storedSessionID,
            limit: 50
        )
    }

    func delegationStatus() async throws -> DelegationStatus {
        throw HermesError(
            "Delegated-agent status is unavailable for this repository",
            retryable: false
        )
    }

    func interruptSubagent(
        subagentID: String
    ) async throws -> SubagentInterruptResult {
        throw HermesError(
            "Delegated-agent controls are unavailable for this repository",
            retryable: false
        )
    }

    func saveDelegationSnapshot(
        _ snapshot: DelegationSnapshot
    ) async throws -> String {
        throw HermesError(
            "Delegation snapshots are unavailable for this repository",
            retryable: false
        )
    }

    func listDelegationSnapshots(
        storedSessionID: String,
        limit: Int
    ) async throws -> [DelegationSnapshotInfo] {
        throw HermesError(
            "Delegation snapshots are unavailable for this repository",
            retryable: false
        )
    }

    func loadDelegationSnapshot(
        path: String
    ) async throws -> DelegationSnapshot {
        throw HermesError(
            "Delegation snapshots are unavailable for this repository",
            retryable: false
        )
    }
}
