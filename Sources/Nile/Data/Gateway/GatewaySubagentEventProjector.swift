import Foundation

struct GatewaySubagentEventProjector: Sendable {
    func project(_ frame: GatewayEventFrame) -> HermesStreamEvent? {
        guard let eventData = eventData(frame.payload ?? [:]) else {
            return nil
        }
        let kind: SubagentEventKind
        switch frame.type {
        case "subagent.spawn_requested":
            kind = .spawnRequested
        case "subagent.start":
            kind = .started
        case "subagent.thinking":
            kind = .thinking
        case "subagent.tool":
            kind = .tool
        case "subagent.progress":
            kind = .progress
        default:
            kind = .completed
        }
        return .subagentUpdate(
            sessionID: frame.sessionID,
            kind: kind,
            data: eventData
        )
    }

    private func eventData(
        _ object: JSONValue.Object
    ) -> SubagentEventData? {
        guard
            let goal = cleanString(object["goal"]),
            let taskCount = nonNegativeInteger(object["task_count"]),
            let taskIndex = nonNegativeInteger(object["task_index"])
        else {
            return nil
        }
        let rawStatus = cleanString(object["status"])
        return SubagentEventData(
            goal: goal,
            taskCount: taskCount,
            taskIndex: taskIndex,
            subagentID: cleanString(object["subagent_id"]),
            parentID: cleanString(object["parent_id"]),
            childSessionID: cleanString(object["child_session_id"]),
            depth: nonNegativeInteger(object["depth"]),
            model: cleanString(object["model"]),
            toolCount: nonNegativeInteger(object["tool_count"]),
            toolsets: cleanStrings(object["toolsets"]),
            text: cleanString(object["text"]),
            toolName: cleanString(object["tool_name"]),
            toolPreview: cleanString(object["tool_preview"]),
            terminalStatus: rawStatus.map(terminalStatus),
            rawTerminalStatus: rawStatus,
            summary: cleanString(object["summary"]),
            durationSeconds: finiteNonNegativeDouble(
                object["duration_seconds"]
            ),
            inputTokens: nonNegativeInteger(object["input_tokens"]),
            outputTokens: nonNegativeInteger(object["output_tokens"]),
            reasoningTokens: nonNegativeInteger(object["reasoning_tokens"]),
            apiCalls: nonNegativeInteger(object["api_calls"]),
            filesRead: cleanStrings(object["files_read"]),
            filesWritten: cleanStrings(object["files_written"]),
            outputTail: outputs(object["output_tail"])
        )
    }

    private func cleanString(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue?.strippingANSI(), !string.isBlank else {
            return nil
        }
        return string
    }

    private func cleanStrings(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(cleanString) ?? []
    }

    private func nonNegativeInteger(_ value: JSONValue?) -> Int? {
        guard
            case let .number(number)? = value,
            number.isFinite,
            number >= 0,
            number.rounded(.towardZero) == number,
            number <= Double(Int32.max)
        else {
            return nil
        }
        return Int(number)
    }

    private func finiteNonNegativeDouble(_ value: JSONValue?) -> Double? {
        guard
            case let .number(number)? = value,
            number.isFinite,
            number >= 0
        else {
            return nil
        }
        return number
    }

    private func terminalStatus(_ value: String) -> SubagentTerminalStatus {
        switch value.lowercased() {
        case "completed", "complete":
            .completed
        case "interrupted", "cancelled", "canceled":
            .interrupted
        case "failed", "failure":
            .failed
        case "timeout", "timed_out":
            .timeout
        case "error":
            .error
        default:
            .unknown
        }
    }

    private func outputs(_ value: JSONValue?) -> [SubagentOutput] {
        value?.arrayValue?.compactMap { value in
            guard
                let object = value.objectValue,
                let tool = cleanString(object["tool"])
            else {
                return nil
            }
            let status = cleanString(object["status"])
            let explicitError: Bool?
            if case let .bool(value)? = object["is_error"] {
                explicitError = value
            } else {
                explicitError = nil
            }
            let inferredError = [
                "error", "failed", "failure", "timeout", "timed_out",
            ].contains(status?.lowercased() ?? "")
            return SubagentOutput(
                tool: tool,
                preview: cleanString(object["preview"]),
                isError: explicitError ?? inferredError,
                status: status
            )
        } ?? []
    }
}
