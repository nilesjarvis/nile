import Foundation

func encodeDelegationSnapshotAgents(
    _ agents: [DelegationSnapshotAgent]
) throws -> [JSONValue] {
    try agents.map { agent in
        try delegationRequireNonNegativeInput(
            method: "spawn_tree.save",
            name: "task_count",
            value: agent.taskCount
        )
        try delegationRequireNonNegativeInput(
            method: "spawn_tree.save",
            name: "task_index",
            value: agent.taskIndex
        )
        var object: JSONValue.Object = [
            "goal": .string(
                try delegationRequireNonBlankInput(
                    method: "spawn_tree.save",
                    name: "goal",
                    value: agent.goal
                )
            ),
            "task_count": .number(Double(agent.taskCount)),
            "task_index": .number(Double(agent.taskIndex)),
        ]
        delegationPutString(&object, name: "subagent_id", value: agent.subagentID)
        delegationPutString(&object, name: "parent_id", value: agent.parentID)
        delegationPutString(
            &object,
            name: "child_session_id",
            value: agent.childSessionID
        )
        try delegationPutNonNegativeInt(&object, name: "depth", value: agent.depth)
        delegationPutString(&object, name: "model", value: agent.model)
        try delegationPutNonNegativeInt(
            &object,
            name: "tool_count",
            value: agent.toolCount
        )
        delegationPutStrings(&object, name: "toolsets", values: agent.toolsets)
        delegationPutString(&object, name: "text", value: agent.text)
        delegationPutString(&object, name: "tool_name", value: agent.toolName)
        delegationPutString(
            &object,
            name: "tool_preview",
            value: agent.toolPreview
        )
        let status = delegationCleanString(agent.rawTerminalStatus.map(JSONValue.string))
            ?? delegationTerminalWireValue(agent.terminalStatus)
        delegationPutString(&object, name: "status", value: status)
        delegationPutString(&object, name: "summary", value: agent.summary)
        try delegationPutFiniteNonNegativeDouble(
            &object,
            name: "duration_seconds",
            value: agent.durationSeconds
        )
        try delegationPutNonNegativeInt(
            &object,
            name: "input_tokens",
            value: agent.inputTokens
        )
        try delegationPutNonNegativeInt(
            &object,
            name: "output_tokens",
            value: agent.outputTokens
        )
        try delegationPutNonNegativeInt(
            &object,
            name: "reasoning_tokens",
            value: agent.reasoningTokens
        )
        try delegationPutNonNegativeInt(
            &object,
            name: "api_calls",
            value: agent.apiCalls
        )
        delegationPutStrings(
            &object,
            name: "files_read",
            values: agent.filesRead
        )
        delegationPutStrings(
            &object,
            name: "files_written",
            values: agent.filesWritten
        )
        if !agent.outputTail.isEmpty {
            object["output_tail"] = .array(
                try agent.outputTail.map { output in
                    var row: JSONValue.Object = [
                        "tool": .string(
                            try delegationRequireNonBlankInput(
                                method: "spawn_tree.save",
                                name: "output tool",
                                value: output.tool
                            )
                        ),
                        "is_error": .bool(output.isError),
                    ]
                    delegationPutString(
                        &row,
                        name: "preview",
                        value: output.preview
                    )
                    delegationPutString(
                        &row,
                        name: "status",
                        value: output.status
                    )
                    return .object(row)
                }
            )
        }
        return .object(object)
    }
}

private func delegationTerminalWireValue(
    _ status: SubagentTerminalStatus?
) -> String? {
    switch status {
    case .completed: "completed"
    case .interrupted: "interrupted"
    case .failed: "failed"
    case .timeout: "timeout"
    case .error: "error"
    case .unknown, nil: nil
    }
}
