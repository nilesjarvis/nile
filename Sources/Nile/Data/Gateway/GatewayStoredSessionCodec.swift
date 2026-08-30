import Foundation

struct GatewayStoredSessionCodec: Sendable {
    func decodeMessages(_ result: JSONValue.Object) throws -> [HermesMessage] {
        var callsByID: [String: StoredToolCall] = [:]
        var messages: [HermesMessage] = []
        for row in try result.requireObjectArray(
            method: "stored session history",
            name: "messages"
        ) {
            let role = row.string("role")
            let content = messageText(row["content"])
            if role == "assistant" {
                for call in row["tool_calls"]?.arrayValue?.objectValues ?? [] {
                    if let parsed = storedToolCall(call), !parsed.id.isBlank {
                        callsByID[parsed.id] = parsed
                    }
                }
                if content.isBlank {
                    continue
                }
            }
            switch role {
            case "tool":
                let call = row.string("tool_call_id").isBlank
                    ? nil
                    : callsByID[row.string("tool_call_id")]
                let name = !row.string("tool_name").isBlank
                    ? row.string("tool_name")
                    : call?.name ?? "tool"
                let decoded = displayToolResult(content, toolName: name)
                messages.append(
                    HermesMessage(
                        role: "tool",
                        text: decoded.text,
                        toolName: name,
                        toolContext: call?.context,
                        toolOutcome: decoded.outcome
                    )
                )
            case "user", "assistant", "system":
                guard
                    !content.isBlank,
                    !(role == "assistant" && content.isProtocolNullText),
                    !(role == "user"
                        && GatewaySessionMessagePolicy
                            .isPrivateGoalContinuation(content))
                else {
                    continue
                }
                let modelNotice = role == "user"
                    ? GatewaySessionMessagePolicy.modelSwitchNotice(content)
                    : nil
                messages.append(
                    HermesMessage(
                        role: modelNotice == nil ? role : "system",
                        text: modelNotice ?? content
                    )
                )
            default:
                continue
            }
        }
        return messages
    }

    private func storedToolCall(_ object: JSONValue.Object) -> StoredToolCall? {
        let function = object["function"]?.objectValue ?? object
        let name = function.string("name")
        guard !name.isBlank else {
            return nil
        }
        return StoredToolCall(
            id: object.string("id"),
            name: name,
            context: toolContext(function["arguments"])
        )
    }

    private func toolContext(_ value: JSONValue?) -> String? {
        let parsed: JSONValue.Object?
        switch value {
        case let .object(object):
            parsed = object
        case let .string(string):
            parsed = parseObject(string)
        default:
            parsed = nil
        }
        for key in ["command", "code", "query", "path", "url", "task", "skill"] {
            if let candidate = parsed?[key], candidate != .null {
                let text = candidate.lenientStringValue
                if !text.isBlank {
                    return text
                }
            }
        }
        guard let value, value != .null else {
            return nil
        }
        let fallback = value.lenientStringValue
        guard !fallback.isBlank else {
            return nil
        }
        return String(fallback.prefix(240))
    }

    private func messageText(_ value: JSONValue?) -> String {
        guard let value else {
            return ""
        }
        switch value {
        case .null:
            return ""
        case let .string(string):
            return string
        case let .array(values):
            return values
                .map(messageText)
                .filter { !$0.isBlank }
                .joined(separator: "\n")
        case let .object(object):
            switch object.string("type") {
            case "text", "input_text", "output_text":
                let text = messageText(object["text"])
                return text.isBlank ? messageText(object["content"]) : text
            case "image", "input_image", "image_url":
                return "[screenshot]"
            case "audio", "input_audio":
                return "[audio]"
            default:
                let text = messageText(object["text"])
                return text.isBlank ? value.lenientStringValue : text
            }
        case .number, .bool:
            return value.lenientStringValue
        }
    }

    private func parseObject(_ string: String) -> JSONValue.Object? {
        guard
            let data = string.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data),
            let value = try? JSONValue(any: raw)
        else {
            return nil
        }
        return value.objectValue
    }
}

private struct StoredToolCall {
    let id: String
    let name: String
    let context: String?
}
