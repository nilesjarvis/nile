import Foundation

/// Owns the delegation RPC contract independently of connection transport.
///
/// `TuiGatewayRepository` contributes this service directly to the session
/// capability bundle instead of implementing delegation operations itself.
struct GatewayDelegationService: HermesDelegationServing, Sendable {
    private let rpc: any GatewayRPCRequesting

    init(rpc: any GatewayRPCRequesting) {
        self.rpc = rpc
    }

    func delegationStatus() async throws -> DelegationStatus {
        try await decodeDelegationStatus(
            rpc.request(
                method: "delegation.status",
                params: [:],
                timeoutMilliseconds: 30_000,
                allowNullResult: false
            )
        )
    }

    func interruptSubagent(
        subagentID: String
    ) async throws -> SubagentInterruptResult {
        let normalized = subagentID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw HermesError(
                "subagent.interrupt requires a nonblank subagent id",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "subagent.interrupt",
            params: ["subagent_id": .string(normalized)],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        let responseID = try GatewayMutationCodec.requireString(
            result,
            method: "subagent.interrupt",
            name: "subagent_id",
            allowBlank: false
        )
        guard responseID == normalized else {
            throw GatewayMutationCodec.malformedResult(
                method: "subagent.interrupt",
                detail: "subagent_id did not match the request"
            )
        }
        return SubagentInterruptResult(
            found: try GatewayMutationCodec.requireBool(
                result,
                method: "subagent.interrupt",
                name: "found"
            ),
            subagentID: responseID
        )
    }

    func saveDelegationSnapshot(
        _ snapshot: DelegationSnapshot
    ) async throws -> String {
        let storedSessionID = snapshot.storedSessionID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storedSessionID.isEmpty else {
            throw HermesError(
                "spawn_tree.save requires a nonblank stored session id",
                retryable: false
            )
        }
        guard !snapshot.agents.isEmpty else {
            throw HermesError(
                "spawn_tree.save requires at least one subagent",
                retryable: false
            )
        }
        try delegationRequireFiniteNonNegativeInput(
            method: "spawn_tree.save",
            name: "finished timestamp",
            value: snapshot.finishedAtEpochSeconds
        )
        if let started = snapshot.startedAtEpochSeconds {
            try delegationRequireFiniteNonNegativeInput(
                method: "spawn_tree.save",
                name: "started timestamp",
                value: started
            )
        }
        var params: JSONValue.Object = [
            "session_id": .string(storedSessionID),
            "finished_at": .number(snapshot.finishedAtEpochSeconds),
            "label": .string(snapshot.label),
            "subagents": .array(
                try encodeDelegationSnapshotAgents(snapshot.agents)
            ),
        ]
        if let started = snapshot.startedAtEpochSeconds {
            params["started_at"] = .number(started)
        }
        let result = try await rpc.request(
            method: "spawn_tree.save",
            params: params,
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        try GatewayMutationCodec.requireLiteral(
            result,
            method: "spawn_tree.save",
            name: "session_id",
            expected: storedSessionID
        )
        return try GatewayMutationCodec.requireString(
            result,
            method: "spawn_tree.save",
            name: "path",
            allowBlank: false
        )
    }

    func listDelegationSnapshots(
        storedSessionID: String,
        limit: Int
    ) async throws -> [DelegationSnapshotInfo] {
        let normalized = storedSessionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw HermesError(
                "spawn_tree.list requires a nonblank stored session id",
                retryable: false
            )
        }
        return try await decodeDelegationSnapshotInfos(
            rpc.request(
                method: "spawn_tree.list",
                params: [
                    "session_id": .string(normalized),
                    "limit": .number(Double(max(1, limit))),
                    "cross_session": .bool(false),
                ],
                timeoutMilliseconds: 30_000,
                allowNullResult: false
            )
        )
    }

    func loadDelegationSnapshot(
        path: String
    ) async throws -> DelegationSnapshot {
        let normalized = path.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw HermesError(
                "spawn_tree.load requires a nonblank path",
                retryable: false
            )
        }
        return try await decodeDelegationSnapshot(
            rpc.request(
                method: "spawn_tree.load",
                params: ["path": .string(normalized)],
                timeoutMilliseconds: 30_000,
                allowNullResult: false
            )
        )
    }
}
