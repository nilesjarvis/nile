import Foundation

func decodeDelegationSnapshotInfos(
    _ object: JSONValue.Object
) throws -> [DelegationSnapshotInfo] {
    try object.requireObjectArray(
        method: "spawn_tree.list",
        name: "entries"
    ).map { row in
        DelegationSnapshotInfo(
            path: try delegationRequireCleanString(
                row,
                method: "spawn_tree.list",
                name: "path"
            ),
            storedSessionID: try delegationRequireCleanString(
                row,
                method: "spawn_tree.list",
                name: "session_id"
            ),
            startedAtEpochSeconds: try delegationOptionalTimestamp(
                row,
                method: "spawn_tree.list",
                name: "started_at"
            ),
            finishedAtEpochSeconds: try delegationRequireTimestamp(
                row,
                method: "spawn_tree.list",
                name: "finished_at"
            ),
            label: try delegationRequireString(
                row,
                method: "spawn_tree.list",
                name: "label",
                allowBlank: true
            ).strippingANSI(),
            count: try delegationRequireNonNegativeInt(
                row,
                method: "spawn_tree.list",
                name: "count"
            )
        )
    }
}

func decodeDelegationSnapshot(
    _ object: JSONValue.Object
) throws -> DelegationSnapshot {
    DelegationSnapshot(
        storedSessionID: try delegationRequireCleanString(
            object,
            method: "spawn_tree.load",
            name: "session_id"
        ),
        startedAtEpochSeconds: try delegationOptionalTimestamp(
            object,
            method: "spawn_tree.load",
            name: "started_at"
        ),
        finishedAtEpochSeconds: try delegationRequireTimestamp(
            object,
            method: "spawn_tree.load",
            name: "finished_at"
        ),
        label: try delegationRequireString(
            object,
            method: "spawn_tree.load",
            name: "label",
            allowBlank: true
        ).strippingANSI(),
        agents: try object.requireObjectArray(
            method: "spawn_tree.load",
            name: "subagents"
        ).map(decodeDelegationSnapshotAgent)
    )
}

private func decodeDelegationSnapshotAgent(
    _ row: JSONValue.Object
) throws -> DelegationSnapshotAgent {
    let rawStatus = delegationCleanString(row["status"])
    return DelegationSnapshotAgent(
        goal: try delegationRequireCleanString(
            row,
            method: "spawn_tree.load",
            name: "goal"
        ),
        taskCount: try delegationRequireNonNegativeInt(
            row,
            method: "spawn_tree.load",
            name: "task_count"
        ),
        taskIndex: try delegationRequireNonNegativeInt(
            row,
            method: "spawn_tree.load",
            name: "task_index"
        ),
        subagentID: delegationCleanString(row["subagent_id"]),
        parentID: delegationCleanString(row["parent_id"]),
        childSessionID: delegationCleanString(row["child_session_id"]),
        depth: delegationOptionalNonNegativeInt(row["depth"]),
        model: delegationCleanString(row["model"]),
        toolCount: delegationOptionalNonNegativeInt(row["tool_count"]),
        toolsets: delegationCleanStrings(row["toolsets"]),
        text: delegationCleanString(row["text"]),
        toolName: delegationCleanString(row["tool_name"]),
        toolPreview: delegationCleanString(row["tool_preview"]),
        terminalStatus: rawStatus.map(delegationTerminalStatus),
        rawTerminalStatus: rawStatus,
        summary: delegationCleanString(row["summary"]),
        durationSeconds:
            delegationOptionalFiniteNonNegativeDouble(row["duration_seconds"]),
        inputTokens: delegationOptionalNonNegativeInt(row["input_tokens"]),
        outputTokens: delegationOptionalNonNegativeInt(row["output_tokens"]),
        reasoningTokens:
            delegationOptionalNonNegativeInt(row["reasoning_tokens"]),
        apiCalls: delegationOptionalNonNegativeInt(row["api_calls"]),
        filesRead: delegationCleanStrings(row["files_read"]),
        filesWritten: delegationCleanStrings(row["files_written"]),
        outputTail: delegationOutputs(row["output_tail"])
    )
}

private func delegationOutputs(_ value: JSONValue?) -> [SubagentOutput] {
    (value?.arrayValue?.objectValues ?? []).compactMap { row in
        guard let tool = delegationCleanString(row["tool"]) else {
            return nil
        }
        let status = delegationCleanString(row["status"])
        let explicitError: Bool? = if case let .bool(value)? = row["is_error"] {
            value
        } else {
            nil
        }
        return SubagentOutput(
            tool: tool,
            preview: delegationCleanString(row["preview"]),
            isError: explicitError ?? [
                "error", "failed", "failure", "timeout", "timed_out",
            ].contains(status?.lowercased() ?? ""),
            status: status
        )
    }
}

private func delegationTerminalStatus(_ value: String) -> SubagentTerminalStatus {
    switch value.lowercased() {
    case "completed", "complete": .completed
    case "interrupted", "cancelled", "canceled": .interrupted
    case "failed", "failure": .failed
    case "timeout", "timed_out": .timeout
    case "error": .error
    default: .unknown
    }
}
