import Foundation

private struct DelegationLiveOwner: Hashable {
    let gatewayID: String
    let liveSessionID: String
}

final class DelegationTurnRecord {
    let id: String
    let owner: DelegationOwner
    var agents: [String: DelegationAgentReducer.State] = [:]
    var startedAtEpochSeconds: Double?
    var finishedAtEpochSeconds: Double?
    var parentCompletionCount = 0
    var settled = false
    var persisted = false

    init(
        id: String,
        owner: DelegationOwner,
        startedAtEpochSeconds: Double?
    ) {
        self.id = id
        self.owner = owner
        self.startedAtEpochSeconds = startedAtEpochSeconds
    }
}

final class DelegationCoordinator {
    static let snapshotTurnPrefix = "delegation-snapshot:"

    let nowEpochSeconds: () -> Double
    private let newTurnID: () -> String
    var turnsByOwner: [DelegationOwner: [DelegationTurnRecord]] = [:]
    private var liveOwners: [DelegationLiveOwner: String] = [:]
    var loadedOwners: Set<DelegationOwner> = []
    let interruptLifecycle = DelegationInterruptLifecycle()
    var sequence: Int64 = 0
    var reconcileGeneration: Int64 = 0

    init(
        nowEpochSeconds: @escaping () -> Double = {
            Date().timeIntervalSince1970
        },
        newTurnID: @escaping () -> String = {
            "delegation-\(UUID().uuidString.lowercased())"
        }
    ) {
        self.nowEpochSeconds = nowEpochSeconds
        self.newTurnID = newTurnID
    }

    func bindLiveSession(
        owner: DelegationOwner,
        liveSessionID: String
    ) {
        liveOwners[
            DelegationLiveOwner(
                gatewayID: owner.gatewayID,
                liveSessionID: liveSessionID
            )
        ] = owner.storedSessionID
    }

    func ownerForLive(
        gatewayID: String?,
        liveSessionID: String,
        visibleLiveSessionID: String?,
        visibleStoredSessionID: String?
    ) -> DelegationOwner? {
        guard let gatewayID else {
            return nil
        }
        let liveOwner = DelegationLiveOwner(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID
        )
        if let storedSessionID = liveOwners[liveOwner] {
            return DelegationOwner(
                gatewayID: gatewayID,
                storedSessionID: storedSessionID
            )
        }
        guard visibleLiveSessionID == liveSessionID,
              let visibleStoredSessionID else {
            return nil
        }
        let owner = DelegationOwner(
            gatewayID: gatewayID,
            storedSessionID: visibleStoredSessionID
        )
        bindLiveSession(owner: owner, liveSessionID: liveSessionID)
        return owner
    }

    func applyEvent(
        owner: DelegationOwner,
        data: SubagentEventData,
        kind: SubagentEventKind
    ) -> DelegationSnapshot? {
        var turns = turnsByOwner[owner] ?? []
        let explicitID = DelegationAgentReducer.normalized(data.subagentID)
        let fallbackKey = DelegationAgentReducer.fallbackKey(data)
        if kind != .completed, let explicitID {
            turns.removeAll { candidate in
                candidate.persisted
                    && candidate.id.hasPrefix(Self.snapshotTurnPrefix)
                    && candidate.agents.values.contains {
                        $0.subagentID == explicitID
                    }
            }
        }

        var turn: DelegationTurnRecord?
        if kind == .completed, let explicitID {
            turn = turns.reversed().first { candidate in
                candidate.agents.values.contains {
                    $0.subagentID == explicitID
                }
            }
        }
        if turn == nil {
            turn = turns.reversed().first { candidate in
                guard !candidate.settled else {
                    return false
                }
                return (
                    explicitID != nil
                        && candidate.agents.values.contains {
                            $0.subagentID == explicitID
                        }
                )
                    || candidate.agents[fallbackKey] != nil
                    || !candidate.agents.isEmpty
            }
        }
        if turn == nil || turn?.settled == true {
            let created = DelegationTurnRecord(
                id: newTurnID(),
                owner: owner,
                startedAtEpochSeconds: nowEpochSeconds()
            )
            turns.append(created)
            turn = created
        }
        guard let turn else {
            return nil
        }

        let explicitKey = explicitID.map { "id:\($0)" }
        var currentKey = explicitKey.flatMap {
            turn.agents[$0] == nil ? nil : $0
        }
        if currentKey == nil, let explicitID {
            currentKey = turn.agents.first {
                $0.value.subagentID == explicitID
            }?.key
        }
        if currentKey == nil, turn.agents[fallbackKey] != nil {
            currentKey = fallbackKey
        }

        if let currentKey, var agent = turn.agents[currentKey] {
            if let explicitKey, currentKey != explicitKey {
                turn.agents.removeValue(forKey: currentKey)
                agent = DelegationAgentReducer.merge(
                    agent,
                    data: data,
                    kind: kind
                )
                turn.agents[explicitKey] = agent
            } else {
                turn.agents[currentKey] = DelegationAgentReducer.merge(
                    agent,
                    data: data,
                    kind: kind
                )
            }
        } else {
            let key = explicitKey ?? fallbackKey
            sequence += 1
            turn.agents[key] = DelegationAgentReducer.make(
                rowID: key,
                order: sequence,
                data: data,
                kind: kind
            )
        }

        if !turn.agents.isEmpty,
           turn.agents.values.allSatisfy(\.status.isFinished) {
            turn.finishedAtEpochSeconds =
                turn.finishedAtEpochSeconds ?? nowEpochSeconds()
            if turn.parentCompletionCount >= 2 {
                turn.settled = true
                trimSettledHistory(&turns)
            }
        }
        turnsByOwner[owner] = turns
        return claimPersistence(turn)
    }

    func markParentCompleted(
        owner: DelegationOwner
    ) -> DelegationSnapshot? {
        guard var turns = turnsByOwner[owner],
              let turn = turns.reversed().first(where: { !$0.settled }) else {
            return nil
        }
        let allTerminal = !turn.agents.isEmpty
            && turn.agents.values.allSatisfy(\.status.isFinished)
        turn.parentCompletionCount += 1
        if allTerminal {
            turn.settled = true
            trimSettledHistory(&turns)
        }
        turnsByOwner[owner] = turns
        return claimPersistence(turn)
    }

    func projection(
        gatewayID: String?,
        storedSessionID: String?,
        transcript: [TranscriptEntry]
    ) -> DelegationProjection {
        let turns: [DelegationTurnRecord]
        if let gatewayID, let storedSessionID {
            turns = turnsByOwner[
                DelegationOwner(
                    gatewayID: gatewayID,
                    storedSessionID: storedSessionID
                )
            ] ?? []
        } else {
            turns = []
        }
        let projected = turns.map(projectTurn)
        let turnIDs = Set(turns.map(\.id))
        var result = transcript.filter { entry in
            guard case let .delegation(anchor) = entry else {
                return true
            }
            return turnIDs.contains(anchor.turnID)
        }
        var existing = Set(result.compactMap { entry -> String? in
            guard case let .delegation(anchor) = entry else {
                return nil
            }
            return anchor.turnID
        })
        for turn in turns where !existing.contains(turn.id) {
            result.append(
                .delegation(
                    TranscriptDelegation(
                        id: "delegation-anchor:\(turn.id)",
                        turnID: turn.id
                    )
                )
            )
            existing.insert(turn.id)
        }
        return DelegationProjection(
            transcript: result,
            turns: projected,
            pinnedTurnID: projected.last(where: \.isPinned)?.id
        )
    }

    func clear() {
        turnsByOwner.removeAll()
        liveOwners.removeAll()
        loadedOwners.removeAll()
        interruptLifecycle.clear()
        reconcileGeneration += 1
    }

    private func projectTurn(_ turn: DelegationTurnRecord) -> DelegationTurnUI {
        DelegationTurnUI(
            id: turn.id,
            storedSessionID: turn.owner.storedSessionID,
            agents: turn.agents.values
                .sorted { $0.firstSeenOrder < $1.firstSeenOrder }
                .map { DelegationAgentReducer.ui($0) },
            startedAtEpochSeconds: turn.startedAtEpochSeconds,
            finishedAtEpochSeconds: turn.finishedAtEpochSeconds,
            isPinned: !turn.settled
        )
    }
}
