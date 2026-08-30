import Foundation

extension DelegationCoordinator {
    func beginSnapshotLoad(owner: DelegationOwner) -> Bool {
        loadedOwners.insert(owner).inserted
    }

    func releaseSnapshotLoad(owner: DelegationOwner) {
        loadedOwners.remove(owner)
    }

    func addSnapshot(
        owner: DelegationOwner,
        path: String,
        snapshot: DelegationSnapshot
    ) {
        var turns = turnsByOwner[owner] ?? []
        let turnID = "\(Self.snapshotTurnPrefix)\(path)"
        guard !turns.contains(where: { $0.id == turnID }) else {
            return
        }
        let explicitIDs = Set(snapshot.agents.compactMap(\.subagentID))
        if !explicitIDs.isEmpty,
           turns.contains(where: { turn in
               turn.agents.values.contains { agent in
                   agent.subagentID.map(explicitIDs.contains) == true
               }
           }) {
            return
        }
        let loaded = DelegationTurnRecord(
            id: turnID,
            owner: owner,
            startedAtEpochSeconds: snapshot.startedAtEpochSeconds
        )
        loaded.finishedAtEpochSeconds = snapshot.finishedAtEpochSeconds
        loaded.parentCompletionCount = 1
        loaded.settled = true
        loaded.persisted = true
        for snapshotAgent in snapshot.agents {
            let data = DelegationAgentReducer.eventData(snapshotAgent)
            let key = snapshotAgent.subagentID.map { "id:\($0)" }
                ?? DelegationAgentReducer.fallbackKey(data)
            sequence += 1
            loaded.agents[key] = DelegationAgentReducer.make(
                rowID: key,
                order: sequence,
                data: data,
                kind: .completed
            )
        }
        turns.append(loaded)
        turnsByOwner[owner] = turns
    }

    func completeSnapshotLoad(owner: DelegationOwner) {
        guard var turns = turnsByOwner[owner] else {
            return
        }
        turns.sort {
            ($0.startedAtEpochSeconds ?? .greatestFiniteMagnitude)
                < ($1.startedAtEpochSeconds ?? .greatestFiniteMagnitude)
        }
        trimSettledHistory(&turns)
        turnsByOwner[owner] = turns
    }

    func beginReconciliation(gatewayID: String) -> Int64 {
        reconcileGeneration += 1
        return reconcileGeneration
    }

    func isCurrentReconciliation(_ generation: Int64) -> Bool {
        generation == reconcileGeneration
    }

    func applyReconciliation(
        generation: Int64,
        gatewayID: String,
        currentGatewayID: String?,
        activeByID: [String: ActiveSubagent]
    ) -> Bool {
        guard generation == reconcileGeneration,
              gatewayID == currentGatewayID else {
            return false
        }
        for (owner, turns) in turnsByOwner where owner.gatewayID == gatewayID {
            for turn in turns {
                for (key, existing) in turn.agents {
                    guard let id = existing.subagentID,
                          !existing.status.isFinished else {
                        continue
                    }
                    var agent = existing
                    if let recovered = activeByID[id] {
                        agent.parentID = DelegationAgentReducer.normalized(
                            recovered.parentID
                        ) ?? agent.parentID
                        agent.goal = DelegationAgentReducer.normalized(
                            recovered.goal
                        ) ?? agent.goal
                        agent.depth = recovered.depth ?? agent.depth
                        agent.model = DelegationAgentReducer.normalized(
                            recovered.model
                        ) ?? agent.model
                        if agent.status != .interrupting {
                            agent.status = .running
                        }
                        agent.toolCount = max(
                            agent.toolCount,
                            DelegationAgentReducer.absoluteToolCount(
                                recovered.toolCount
                            )
                        )
                        agent.latestActivity = DelegationAgentReducer.normalized(
                            recovered.status
                        ) ?? agent.latestActivity
                    } else if agent.status != .requested {
                        agent.status = .completionUnknown
                    }
                    turn.agents[key] = agent
                }
            }
        }
        return true
    }

    func claimPersistence(
        _ turn: DelegationTurnRecord
    ) -> DelegationSnapshot? {
        guard !turn.persisted,
              turn.settled,
              !turn.agents.isEmpty,
              turn.agents.values.allSatisfy(\.status.isFinished) else {
            return nil
        }
        turn.persisted = true
        let agents = turn.agents.values.sorted {
            $0.firstSeenOrder < $1.firstSeenOrder
        }
        let firstGoal = agents.first?.goal.prefix(120) ?? ""
        let label = firstGoal.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return DelegationSnapshot(
            storedSessionID: turn.owner.storedSessionID,
            startedAtEpochSeconds: turn.startedAtEpochSeconds,
            finishedAtEpochSeconds:
                turn.finishedAtEpochSeconds ?? nowEpochSeconds(),
            label: label.isEmpty ? "delegated agents" : label,
            agents: agents.map { DelegationAgentReducer.snapshot($0) }
        )
    }

    func trimSettledHistory(
        _ turns: inout [DelegationTurnRecord]
    ) {
        let retained = Set(
            turns.enumerated()
                .filter(\.element.settled)
                .sorted { left, right in
                    let leftFinished = left.element.finishedAtEpochSeconds
                    let rightFinished = right.element.finishedAtEpochSeconds
                    if (leftFinished != nil) != (rightFinished != nil) {
                        return leftFinished != nil
                    }
                    if leftFinished != rightFinished {
                        return (leftFinished ?? 0) > (rightFinished ?? 0)
                    }
                    let leftStarted = left.element.startedAtEpochSeconds
                    let rightStarted = right.element.startedAtEpochSeconds
                    if (leftStarted != nil) != (rightStarted != nil) {
                        return leftStarted != nil
                    }
                    if leftStarted != rightStarted {
                        return (leftStarted ?? 0) > (rightStarted ?? 0)
                    }
                    return left.offset > right.offset
                }
                .prefix(retainedSettledDelegationTurns)
                .map(\.element.id)
        )
        turns.removeAll { $0.settled && !retained.contains($0.id) }
    }
}
