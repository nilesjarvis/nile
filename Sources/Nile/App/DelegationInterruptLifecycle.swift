import Foundation

final class DelegationInterruptLifecycle {
    private var active: [String: Int64] = [:]
    private var sequence: Int64 = 0

    func begin(
        subagentID: String,
        turnsByOwner: [DelegationOwner: [DelegationTurnRecord]]
    ) -> DelegationInterruptRequest? {
        guard active[subagentID] == nil,
              let located = findAgent(subagentID, in: turnsByOwner),
              !located.agent.status.isFinished else {
            return nil
        }
        sequence += 1
        let request = DelegationInterruptRequest(
            sequence: sequence,
            subagentID: subagentID
        )
        active[subagentID] = request.sequence
        setStatus(.interrupting, for: located)
        return request
    }

    func applyResult(
        _ request: DelegationInterruptRequest,
        found: Bool,
        turnsByOwner: [DelegationOwner: [DelegationTurnRecord]]
    ) -> Bool {
        guard isCurrent(request),
              let located = findAgent(request.subagentID, in: turnsByOwner),
              !located.agent.status.isFinished else {
            return false
        }
        setStatus(found ? .interrupting : .completionUnknown, for: located)
        return true
    }

    func applyFailure(
        _ request: DelegationInterruptRequest,
        uncertain: Bool,
        turnsByOwner: [DelegationOwner: [DelegationTurnRecord]]
    ) -> Bool {
        guard isCurrent(request),
              let located = findAgent(request.subagentID, in: turnsByOwner),
              !located.agent.status.isFinished else {
            return false
        }
        setStatus(uncertain ? .interruptUnconfirmed : .running, for: located)
        return true
    }

    func complete(_ request: DelegationInterruptRequest) {
        guard isCurrent(request) else {
            return
        }
        active.removeValue(forKey: request.subagentID)
    }

    func clear() {
        active.removeAll()
    }

    private func isCurrent(_ request: DelegationInterruptRequest) -> Bool {
        active[request.subagentID] == request.sequence
    }

    private func setStatus(
        _ status: DelegatedAgentStatus,
        for located: LocatedAgent
    ) {
        var agent = located.agent
        agent.status = status
        located.turn.agents[located.key] = agent
    }

    private func findAgent(
        _ subagentID: String,
        in turnsByOwner: [DelegationOwner: [DelegationTurnRecord]]
    ) -> LocatedAgent? {
        for turns in turnsByOwner.values {
            for turn in turns.reversed() {
                if let match = turn.agents.first(where: {
                    $0.value.subagentID == subagentID
                }) {
                    return LocatedAgent(
                        turn: turn,
                        key: match.key,
                        agent: match.value
                    )
                }
            }
        }
        return nil
    }

    private struct LocatedAgent {
        let turn: DelegationTurnRecord
        let key: String
        let agent: DelegationAgentReducer.State
    }
}

extension DelegationCoordinator {
    func beginInterrupt(
        subagentID: String
    ) -> DelegationInterruptRequest? {
        interruptLifecycle.begin(
            subagentID: subagentID,
            turnsByOwner: turnsByOwner
        )
    }

    func applyInterruptResult(
        _ request: DelegationInterruptRequest,
        found: Bool
    ) -> Bool {
        interruptLifecycle.applyResult(
            request,
            found: found,
            turnsByOwner: turnsByOwner
        )
    }

    func applyInterruptFailure(
        _ request: DelegationInterruptRequest,
        uncertain: Bool
    ) -> Bool {
        interruptLifecycle.applyFailure(
            request,
            uncertain: uncertain,
            turnsByOwner: turnsByOwner
        )
    }

    func completeInterrupt(_ request: DelegationInterruptRequest) {
        interruptLifecycle.complete(request)
    }
}
