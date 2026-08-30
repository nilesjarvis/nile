import Foundation

struct GatewayEventFrame: Equatable, Sendable {
    let type: String
    let sessionID: String
    let payload: JSONValue.Object?
}

enum GatewayInboundFrame: Equatable, Sendable {
    case ready
    case event(GatewayEventFrame)
    case response(id: Int64, envelope: JSONValue.Object)
    case ignored
    case invalid(reason: String)
}

enum GatewayDecodedResponse: Equatable, Sendable {
    case result(JSONValue.Object)
    case error(code: Int, message: String)
    case invalid(reason: String)
}

struct GatewayFrameCodec: Sendable {
    func encodeRequest(
        id: Int64,
        method: String,
        params: JSONValue.Object
    ) throws -> String {
        let frame: JSONValue.Object = [
            "jsonrpc": .string(Self.jsonRPCVersion),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": .object(params),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: JSONValue.object(frame).foundationValue,
            options: [.sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw GatewayCodecError.encodingFailed
        }
        return json + "\n"
    }

    func decodeInbound(_ line: String) -> GatewayInboundFrame {
        guard let data = line.data(using: .utf8) else {
            return .invalid(reason: "message was not valid JSON")
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .invalid(reason: "message was not valid JSON")
        }
        guard
            let value = try? JSONValue(any: raw),
            let frame = value.objectValue
        else {
            return .invalid(reason: "message was not a response or notification")
        }

        let method = frame["method"]?.stringValue
        if method == Self.eventMethod {
            return decodeEvent(frame)
        }
        if frame["id"] != nil {
            return decodeResponseEnvelope(frame)
        }
        if method != nil {
            guard frame["jsonrpc"] == .string(Self.jsonRPCVersion) else {
                return .invalid(reason: "notification did not declare JSON-RPC 2.0")
            }
            return .ignored
        }
        return .invalid(reason: "message was not a response or notification")
    }

    func decodeResponse(
        _ response: GatewayInboundFrame,
        allowNullResult: Bool
    ) -> GatewayDecodedResponse {
        guard case let .response(_, frame) = response else {
            return .invalid(reason: "message was not a response")
        }
        if let invalid = malformedResponseReason(
            frame,
            allowNullResult: allowNullResult
        ) {
            return .invalid(reason: invalid)
        }

        if let error = frame["error"]?.objectValue {
            let code = Int(error["code"]!.integralInt64Value!)
            let message = error["message"]!.stringValue!
            return .error(code: code, message: message)
        }
        if case let .object(result)? = frame["result"] {
            return .result(result)
        }
        return .result([:])
    }

    private func decodeEvent(_ frame: JSONValue.Object) -> GatewayInboundFrame {
        guard frame["jsonrpc"] == .string(Self.jsonRPCVersion) else {
            return .invalid(reason: "event did not declare JSON-RPC 2.0")
        }
        if frame["id"] != nil || frame["result"] != nil || frame["error"] != nil {
            return .invalid(reason: "event contained response fields")
        }
        guard let params = frame["params"]?.objectValue else {
            return .invalid(reason: "event params were missing or not an object")
        }
        guard
            let type = params["type"]?.stringValue,
            !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .invalid(reason: "event type was missing or blank")
        }

        if type != Self.readyEvent && !Self.sessionEventTypes.contains(type) {
            return .ignored
        }

        let payloadValue = params["payload"]
        let payload = payloadValue?.objectValue
        let malformedPayload = payloadValue != nil
            && payloadValue != .null
            && payload == nil
        if malformedPayload && !Self.blockingEventTypes.contains(type) {
            return .invalid(reason: "event payload was not an object")
        }

        if type == Self.readyEvent {
            return .ready
        }

        guard
            let sessionID = params["session_id"]?.stringValue,
            !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .invalid(reason: "\(type) event had no session id")
        }
        return .event(
            GatewayEventFrame(
                type: type,
                sessionID: sessionID,
                payload: payload
            )
        )
    }

    private func decodeResponseEnvelope(
        _ frame: JSONValue.Object
    ) -> GatewayInboundFrame {
        guard
            let id = frame["id"]?.integralInt64Value,
            id > 0
        else {
            return .invalid(reason: "response id was not a positive integer")
        }
        return .response(id: id, envelope: frame)
    }

    private func malformedResponseReason(
        _ frame: JSONValue.Object,
        allowNullResult: Bool
    ) -> String? {
        guard frame["jsonrpc"] == .string(Self.jsonRPCVersion) else {
            return "jsonrpc was not 2.0"
        }
        guard frame["method"] == nil else {
            return "response also contained a method"
        }

        let hasResult = frame["result"] != nil
        let hasError = frame["error"] != nil
        guard hasResult != hasError else {
            return "exactly one of result or error is required"
        }
        if let result = frame["result"] {
            if result.objectValue == nil && !(allowNullResult && result == .null) {
                return "result was not an object"
            }
        }
        if let errorValue = frame["error"] {
            guard let error = errorValue.objectValue else {
                return "error was not an object"
            }
            guard
                let code = error["code"]?.integralInt64Value,
                code >= Int64(Int32.min),
                code <= Int64(Int32.max)
            else {
                return "error code was not an integer"
            }
            guard
                let message = error["message"]?.stringValue,
                !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "error message was missing or blank"
            }
        }
        return nil
    }

    private static let jsonRPCVersion = "2.0"
    private static let eventMethod = "event"
    private static let readyEvent = "gateway.ready"

    private static let blockingEventTypes: Set<String> = [
        "clarify.request",
        "approval.request",
        "sudo.request",
        "secret.request",
    ]

    private static let sessionEventTypes: Set<String> = Set([
        "message.start",
        "message.delta",
        "message.interim",
        "message.complete",
        "thinking.delta",
        "reasoning.delta",
        "tool.start",
        "tool.generating",
        "tool.complete",
        "status.update",
        "review.summary",
        "session.info",
        "subagent.spawn_requested",
        "subagent.start",
        "subagent.thinking",
        "subagent.tool",
        "subagent.progress",
        "subagent.complete",
        "error",
    ]).union(blockingEventTypes)
}

enum GatewayCodecError: Error {
    case encodingFailed
}
