import Foundation

/// Displayed-session delegated-agent presentation and control integration.
///
/// SessionDelegationRuntime retains capability requests, persistence, tasks,
/// lifecycle generations, and coordination state. This extension owns only
/// observable forwarding, visible transcript projection, child navigation, and
/// callbacks from the core model's single ordered Hermes event boundary.
@MainActor
extension SessionListModel {
    var delegationTurns: [DelegationTurnUI] {
        get { runtimes.delegationRuntime.turns }
        set { runtimes.delegationRuntime.turns = newValue }
    }

    var pinnedDelegationTurnID: String? {
        get { runtimes.delegationRuntime.pinnedTurnID }
        set { runtimes.delegationRuntime.pinnedTurnID = newValue }
    }

    var isReconcilingDelegations: Bool {
        get { runtimes.delegationRuntime.isReconciling }
        set { runtimes.delegationRuntime.isReconciling = newValue }
    }

    var delegationControlError: String? {
        get { runtimes.delegationRuntime.controlError }
        set { runtimes.delegationRuntime.controlError = newValue }
    }

    var pinnedDelegationTurn: DelegationTurnUI? {
        guard let pinnedDelegationTurnID else {
            return nil
        }
        return delegationTurns.first { $0.id == pinnedDelegationTurnID }
    }

    var delegationControlsEnabled: Bool {
        state == .loaded
            && !isOpeningSession
            && !isReconcilingDelegations
            && liveSession != nil
    }

    func interruptDelegatedAgent(_ subagentID: String) {
        guard delegationControlsEnabled else {
            return
        }
        runtimes.delegationRuntime.interrupt(
            subagentID: subagentID,
            gatewayID: currentGatewayID,
            onProjection: { [weak self] in
                self?.syncDelegationUI()
            }
        )
    }

    func openDelegatedChild(_ storedSessionID: String) {
        guard delegationControlsEnabled else {
            return
        }
        guard !isUpdatingSessionControls,
              !isGoalMutating,
              !isAttaching else {
            delegationControlError =
                "Wait for the current session action to finish."
            return
        }
        let normalized = storedSessionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            return
        }
        if !sessions.contains(where: { $0.id == normalized }) {
            sessions.append(
                HermesSession(
                    id: normalized,
                    title: "Delegated session",
                    preview: "Opening delegated child session…",
                    source: "niles",
                    messageCount: 0,
                    startedAt: nil,
                    lastMessageAt: nil
                )
            )
        }
        Task { [weak self] in
            await self?.selectSession(id: normalized)
        }
    }

    func handleDelegationEvent(
        sessionID: String,
        kind: SubagentEventKind,
        data: SubagentEventData
    ) {
        runtimes.delegationRuntime.handleEvent(
            gatewayID: currentGatewayID,
            visibleStoredSessionID: selectedSessionID,
            visibleLiveSessionID: liveSession?.liveID,
            liveSessionID: sessionID,
            kind: kind,
            data: data,
            onProjection: { [weak self] in
                self?.syncDelegationUI()
            }
        )
    }

    func markDelegationParentCompleted(
        liveSessionID: String
    ) {
        runtimes.delegationRuntime.markParentCompleted(
            gatewayID: currentGatewayID,
            visibleStoredSessionID: selectedSessionID,
            visibleLiveSessionID: liveSession?.liveID,
            liveSessionID: liveSessionID,
            onProjection: { [weak self] in
                self?.syncDelegationUI()
            }
        )
    }

    func ensureDelegationSnapshotsLoaded(
        owner: DelegationOwner
    ) {
        runtimes.delegationRuntime.loadSnapshots(
            owner: owner,
            onProjection: { [weak self] in
                self?.syncDelegationUI()
            }
        )
    }

    func reconcileDelegations() {
        runtimes.delegationRuntime.reconcile(
            gatewayID: currentGatewayID,
            onProjection: { [weak self] in
                self?.syncDelegationUI()
            }
        )
    }

    func syncDelegationUI() {
        transcriptEntries = runtimes.delegationRuntime.project(
            gatewayID: currentGatewayID,
            storedSessionID: selectedSessionID,
            transcript:
                transcriptEntries.withoutDelegationCompletionEnvelopes()
        )
    }

    func clearDelegationState() {
        runtimes.delegationRuntime.reset()
    }

}
