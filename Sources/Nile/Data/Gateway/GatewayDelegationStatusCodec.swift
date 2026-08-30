import Foundation

func decodeDelegationStatus(
    _ object: JSONValue.Object
) throws -> DelegationStatus {
    let active = try object.requireObjectArray(
        method: "delegation.status",
        name: "active"
    ).compactMap { row -> ActiveSubagent? in
        guard let id = delegationCleanString(row["subagent_id"]) else {
            return nil
        }
        return ActiveSubagent(
            subagentID: id,
            parentID: delegationCleanString(row["parent_id"]),
            depth: delegationOptionalNonNegativeInt(row["depth"]),
            goal: delegationCleanString(row["goal"]),
            model: delegationCleanString(row["model"]),
            startedAtEpochSeconds:
                delegationOptionalFiniteNonNegativeDouble(row["started_at"]),
            toolCount: delegationOptionalNonNegativeInt(row["tool_count"]),
            status: delegationCleanString(row["status"])
        )
    }
    return DelegationStatus(
        active: active,
        paused: try delegationRequireBool(
            object,
            method: "delegation.status",
            name: "paused"
        ),
        maxSpawnDepth: try delegationRequireNonNegativeInt(
            object,
            method: "delegation.status",
            name: "max_spawn_depth"
        ),
        maxConcurrentChildren: try delegationRequireNonNegativeInt(
            object,
            method: "delegation.status",
            name: "max_concurrent_children"
        )
    )
}
