import Foundation

struct GatewayEventProjector: Sendable {
    private let blocking = GatewayBlockingEventProjector()
    private let sessions = GatewaySessionCodec()
    private let status = GatewayStatusEventProjector()
    private let subagents = GatewaySubagentEventProjector()

    func project(_ frame: GatewayEventFrame) -> HermesStreamEvent? {
        let data = frame.payload ?? [:]
        switch frame.type {
        case "message.start":
            return .messageStart(sessionID: frame.sessionID)
        case "subagent.spawn_requested",
             "subagent.start",
             "subagent.thinking",
             "subagent.tool",
             "subagent.progress",
             "subagent.complete":
            return subagents.project(frame)
        case "message.delta":
            return .assistantDelta(
                sessionID: frame.sessionID,
                text: data.string("text")
            )
        case "message.interim":
            let text = data.string("text")
            guard !text.isBlank else {
                return nil
            }
            return .assistantInterim(
                sessionID: frame.sessionID,
                text: text
            )
        case "message.complete":
            let rawText = data.string("text")
            let usage = data["usage"]?.objectValue.map {
                UsageSummary(
                    inputTokens: $0.int("input"),
                    outputTokens: $0.int("output")
                )
            }
            return .assistantCompleted(
                sessionID: frame.sessionID,
                text: rawText.isProtocolNullText ? "" : rawText,
                usage: usage
            )
        case "thinking.delta":
            return .thinkingStatus(
                sessionID: frame.sessionID,
                text: data.string("text")
            )
        case "reasoning.delta":
            return .thinkingDelta(
                sessionID: frame.sessionID,
                text: data.string("text")
            )
        case "tool.start", "tool.generating":
            return .toolStart(
                sessionID: frame.sessionID,
                toolID: data.optionalString("tool_id"),
                name: data.string("name").isBlank ? "tool" : data.string("name"),
                detail: data.optionalString("args_text") ?? data.optionalString("preview"),
                context: data.optionalString("context"),
                generating: frame.type == "tool.generating"
            )
        case "tool.complete":
            let name = data.string("name").isBlank ? "tool" : data.string("name")
            let rawResult = data.optionalString("result_text")
                ?? data.optionalString("result")
                ?? data.optionalString("preview")
            let decoded = rawResult.map { displayToolResult($0, toolName: name) }
            return .toolComplete(
                sessionID: frame.sessionID,
                toolID: data.optionalString("tool_id"),
                name: name,
                result: decoded?.text,
                outcome: decoded?.outcome ?? .unknown,
                summary: data.optionalString("summary"),
                durationSeconds: positiveDouble(data["duration_s"]),
                todos: data["todos"]?.arrayValue.map(todoItems),
                inlineDiff: data.optionalString("inline_diff")?.strippingANSI()
            )
        case "clarify.request",
             "approval.request",
             "sudo.request",
             "secret.request":
            return blocking.project(frame)
        case "status.update":
            return status.project(frame)
        case "review.summary":
            return .statusUpdate(
                sessionID: frame.sessionID,
                text: data.string("text")
            )
        case "session.info":
            return .sessionInfoUpdate(
                sessionID: frame.sessionID,
                info: sessions.decodeSessionInfo(data)
            )
        case "error":
            return .error(
                sessionID: frame.sessionID,
                message: data.optionalString("message")
                    ?? data.optionalString("text")
                    ?? "Gateway error"
            )
        default:
            return nil
        }
    }

    private func positiveDouble(_ value: JSONValue?) -> Double? {
        guard let value = value?.lenientDoubleValue, value > 0 else {
            return nil
        }
        return value
    }

    private func todoItems(_ values: [JSONValue]) -> [TodoItem] {
        values.compactMap { value in
            guard let object = value.objectValue else {
                return nil
            }
            let content = object.string("content")
            guard !content.isBlank else {
                return nil
            }
            let status = object.string("status")
            return TodoItem(
                content: content,
                status: status.isBlank ? "pending" : status
            )
        }
    }
}
