import Foundation

/// Pure sparse-event reduction and presentation/snapshot projection for one
/// delegated agent. Turn ownership and lifecycle remain in the coordinator.
enum DelegationAgentReducer {
    struct State {
        let rowID: String
        let firstSeenOrder: Int64
        var subagentID: String?
        var parentID: String?
        var childSessionID: String?
        var goal: String
        var taskCount: Int
        var taskIndex: Int
        var depth: Int?
        var model: String?
        var status: DelegatedAgentStatus
        var toolCount: Int
        var toolsets: [String]
        var latestActivity: String?
        var toolName: String?
        var toolPreview: String?
        var rawTerminalStatus: String?
        var summary: String?
        var durationSeconds: Double?
        var inputTokens: Int?
        var outputTokens: Int?
        var reasoningTokens: Int?
        var apiCalls: Int?
        var filesRead: [String]
        var filesWritten: [String]
        var outputTail: [SubagentOutput]
    }

    static func fallbackKey(_ data: SubagentEventData) -> String {
        let parent = data.parentID ?? ""
        let goal = data.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
        return "fallback:\(parent):\(data.taskIndex):\(goal)"
    }

    static func make(
        rowID: String,
        order: Int64,
        data: SubagentEventData,
        kind: SubagentEventKind
    ) -> State {
        State(
            rowID: rowID,
            firstSeenOrder: order,
            subagentID: normalized(data.subagentID),
            parentID: normalized(data.parentID),
            childSessionID: normalized(data.childSessionID),
            goal: data.goal,
            taskCount: data.taskCount,
            taskIndex: data.taskIndex,
            depth: data.depth,
            model: normalized(data.model),
            status: status(for: kind, terminalStatus: data.terminalStatus),
            toolCount: absoluteToolCount(data.toolCount),
            toolsets: data.toolsets,
            latestActivity: normalized(data.text)
                ?? normalized(data.toolPreview)
                ?? normalized(data.toolName),
            toolName: normalized(data.toolName),
            toolPreview: normalized(data.toolPreview),
            rawTerminalStatus: normalized(data.rawTerminalStatus),
            summary: normalized(data.summary),
            durationSeconds: data.durationSeconds,
            inputTokens: data.inputTokens,
            outputTokens: data.outputTokens,
            reasoningTokens: data.reasoningTokens,
            apiCalls: data.apiCalls,
            filesRead: data.filesRead,
            filesWritten: data.filesWritten,
            outputTail: data.outputTail
        )
    }

    static func merge(
        _ existing: State,
        data: SubagentEventData,
        kind: SubagentEventKind
    ) -> State {
        var agent = existing
        agent.subagentID = normalized(data.subagentID) ?? agent.subagentID
        agent.parentID = normalized(data.parentID) ?? agent.parentID
        agent.childSessionID = normalized(data.childSessionID)
            ?? agent.childSessionID
        if !data.goal.isBlank {
            agent.goal = data.goal
        }
        if data.taskCount > 0 {
            agent.taskCount = data.taskCount
        }
        if data.taskIndex >= 0 {
            agent.taskIndex = data.taskIndex
        }
        agent.depth = data.depth ?? agent.depth
        agent.model = normalized(data.model) ?? agent.model
        if !agent.status.isFinished,
           agent.status != .interrupting || kind == .completed {
            agent.status = status(
                for: kind,
                terminalStatus: data.terminalStatus
            )
        }
        agent.toolCount = max(
            agent.toolCount,
            absoluteToolCount(data.toolCount)
        )
        if !data.toolsets.isEmpty {
            agent.toolsets = data.toolsets
        }
        agent.latestActivity = normalized(data.text)
            ?? normalized(data.toolPreview)
            ?? normalized(data.toolName)
            ?? agent.latestActivity
        agent.toolName = normalized(data.toolName) ?? agent.toolName
        agent.toolPreview = normalized(data.toolPreview) ?? agent.toolPreview
        agent.rawTerminalStatus = normalized(data.rawTerminalStatus)
            ?? agent.rawTerminalStatus
        agent.summary = normalized(data.summary) ?? agent.summary
        agent.durationSeconds = data.durationSeconds ?? agent.durationSeconds
        agent.inputTokens = data.inputTokens ?? agent.inputTokens
        agent.outputTokens = data.outputTokens ?? agent.outputTokens
        agent.reasoningTokens = data.reasoningTokens ?? agent.reasoningTokens
        agent.apiCalls = data.apiCalls ?? agent.apiCalls
        if !data.filesRead.isEmpty {
            agent.filesRead = data.filesRead
        }
        if !data.filesWritten.isEmpty {
            agent.filesWritten = data.filesWritten
        }
        if !data.outputTail.isEmpty {
            agent.outputTail = data.outputTail
        }
        return agent
    }

    static func ui(_ state: State) -> DelegatedAgentUI {
        DelegatedAgentUI(
            rowID: state.rowID,
            subagentID: state.subagentID,
            parentID: state.parentID,
            childSessionID: state.childSessionID,
            goal: state.goal,
            taskCount: state.taskCount,
            taskIndex: state.taskIndex,
            depth: state.depth,
            model: state.model,
            status: state.status,
            toolCount: state.toolCount,
            toolsets: state.toolsets,
            latestActivity: state.latestActivity,
            toolName: state.toolName,
            toolPreview: state.toolPreview,
            rawTerminalStatus: state.rawTerminalStatus,
            summary: state.summary,
            durationSeconds: state.durationSeconds,
            inputTokens: state.inputTokens,
            outputTokens: state.outputTokens,
            reasoningTokens: state.reasoningTokens,
            apiCalls: state.apiCalls,
            filesRead: state.filesRead,
            filesWritten: state.filesWritten,
            outputTail: state.outputTail
        )
    }

    static func snapshot(_ state: State) -> DelegationSnapshotAgent {
        let terminal: SubagentTerminalStatus? =
            if case let .finished(value) = state.status {
                value
            } else {
                nil
            }
        return DelegationSnapshotAgent(
            goal: state.goal,
            taskCount: state.taskCount,
            taskIndex: state.taskIndex,
            subagentID: state.subagentID,
            parentID: state.parentID,
            childSessionID: state.childSessionID,
            depth: state.depth,
            model: state.model,
            toolCount: state.toolCount,
            toolsets: state.toolsets,
            text: state.latestActivity,
            toolName: state.toolName,
            toolPreview: state.toolPreview,
            terminalStatus: terminal,
            rawTerminalStatus: state.rawTerminalStatus,
            summary: state.summary,
            durationSeconds: state.durationSeconds,
            inputTokens: state.inputTokens,
            outputTokens: state.outputTokens,
            reasoningTokens: state.reasoningTokens,
            apiCalls: state.apiCalls,
            filesRead: state.filesRead,
            filesWritten: state.filesWritten,
            outputTail: state.outputTail
        )
    }

    static func eventData(_ snapshot: DelegationSnapshotAgent)
        -> SubagentEventData
    {
        SubagentEventData(
            goal: snapshot.goal,
            taskCount: snapshot.taskCount,
            taskIndex: snapshot.taskIndex,
            subagentID: snapshot.subagentID,
            parentID: snapshot.parentID,
            childSessionID: snapshot.childSessionID,
            depth: snapshot.depth,
            model: snapshot.model,
            toolCount: snapshot.toolCount,
            toolsets: snapshot.toolsets,
            text: snapshot.text,
            toolName: snapshot.toolName,
            toolPreview: snapshot.toolPreview,
            terminalStatus: snapshot.terminalStatus ?? .unknown,
            rawTerminalStatus: snapshot.rawTerminalStatus,
            summary: snapshot.summary,
            durationSeconds: snapshot.durationSeconds,
            inputTokens: snapshot.inputTokens,
            outputTokens: snapshot.outputTokens,
            reasoningTokens: snapshot.reasoningTokens,
            apiCalls: snapshot.apiCalls,
            filesRead: snapshot.filesRead,
            filesWritten: snapshot.filesWritten,
            outputTail: snapshot.outputTail
        )
    }

    static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false ? normalized : nil
    }

    static func absoluteToolCount(_ value: Int?) -> Int {
        guard let value else {
            return 0
        }
        if value == Int.min {
            return Int.max
        }
        return abs(value)
    }

    private static func status(
        for kind: SubagentEventKind,
        terminalStatus: SubagentTerminalStatus?
    ) -> DelegatedAgentStatus {
        switch kind {
        case .spawnRequested:
            .requested
        case .started, .thinking, .tool, .progress:
            .running
        case .completed:
            .finished(terminalStatus ?? .unknown)
        }
    }
}
