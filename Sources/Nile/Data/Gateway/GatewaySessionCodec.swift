import Foundation

struct GatewaySessionCodec: Sendable {
    func decodeSessionList(_ result: JSONValue.Object) throws -> [HermesSession] {
        try result.requireObjectArray(method: "session.list", name: "sessions").map { row in
            let startedAt = epochSeconds(row["started_at"])
            return HermesSession(
                id: try row.requireNonBlankString(method: "session.list", name: "id"),
                title: row.optionalString("title"),
                preview: row.optionalString("preview"),
                source: row.optionalString("source"),
                messageCount: row.int("message_count"),
                startedAt: startedAt,
                lastMessageAt: epochSeconds(row["last_message_at"])
                    ?? epochSeconds(row["updated_at"])
                    ?? epochSeconds(row["last_activity_at"])
                    ?? startedAt
            )
        }
    }

    func decodeLiveSession(
        _ result: JSONValue.Object,
        fallbackStoredID: String?
    ) -> LiveSession {
        let messages: [HermesMessage] = result["messages"]?
            .arrayValue?
            .objectValues
            .compactMap { row -> HermesMessage? in
            let role = row.string("role", default: "assistant")
            if role == "tool" {
                let context = row.optionalString("context") ?? ""
                return HermesMessage(
                    role: "tool",
                    text: context,
                    toolName: row.optionalString("name"),
                    toolContext: row.optionalString("context")
                )
            }
            let text = row.string("text")
            guard !text.isBlank else {
                return nil
            }
            if
                role == "user",
                GatewaySessionMessagePolicy.isPrivateGoalContinuation(text)
            {
                return nil
            }
            let modelNotice = role == "user"
                ? GatewaySessionMessagePolicy.modelSwitchNotice(text)
                : nil
            return HermesMessage(
                role: modelNotice == nil ? role : "system",
                text: modelNotice ?? text
            )
            } ?? []
        let inflight = result["inflight"]?.objectValue.map { turn in
            let rawUser = turn.string("user")
            return InflightTurn(
                user: GatewaySessionMessagePolicy.isPrivateGoalContinuation(
                    rawUser
                ) ? "" : rawUser,
                assistant: turn.string("assistant")
            )
        }
        return LiveSession(
            liveID: result.string("session_id"),
            storedID: result.optionalString("stored_session_id") ?? fallbackStoredID,
            info: decodeSessionInfo(result["info"]?.objectValue ?? [:]),
            messages: messages,
            running: result.bool("running"),
            status: result.optionalString("status"),
            inflight: inflight
        )
    }

    func requireLiveID(_ session: LiveSession, method: String) throws -> LiveSession {
        guard !session.liveID.isBlank else {
            throw HermesError(
                "Malformed response to \(method): session_id was missing or blank",
                retryable: false
            )
        }
        return session
    }

    func decodeStoredStatuses(_ result: JSONValue.Object) throws -> [String: String] {
        var statuses: [String: String] = [:]
        for row in try result.requireObjectArray(
            method: "session.active_list",
            name: "sessions"
        ) {
            let key = row.string("session_key")
            let status = row.string("status")
            if !key.isBlank, !status.isBlank {
                statuses[key] = status
            }
        }
        return statuses
    }

    func decodeRuntimeStatuses(_ result: JSONValue.Object) throws -> [String: String] {
        var statuses: [String: String] = [:]
        for row in try result.requireObjectArray(
            method: "session.active_list",
            name: "sessions"
        ) {
            statuses[
                try row.requireNonBlankString(method: "session.active_list", name: "id")
            ] = try row.requireNonBlankString(
                method: "session.active_list",
                name: "status"
            )
        }
        return statuses
    }

    func decodeSessionInfo(_ object: JSONValue.Object) -> SessionInfo {
        SessionInfo(
            model: object.optionalString("model"),
            provider: object.optionalString("provider"),
            reasoningEffort: object.optionalString("reasoning_effort"),
            reasoningEffortSessionScopeSupported:
                object["reasoning_effort_session_scope"] == .bool(true),
            isLazy: object["lazy"] == .bool(true)
        )
    }

    private func epochSeconds(_ value: JSONValue?) -> Double? {
        guard let raw = value?.lenientDoubleValue, raw > 0 else {
            return nil
        }
        return raw > 10_000_000_000 ? raw / 1_000 : raw
    }

}
