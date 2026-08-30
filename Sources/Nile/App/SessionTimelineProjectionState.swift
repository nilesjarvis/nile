import Foundation

/// Owns the mutable presentation projection for one parked live session.
/// Cache indexes, retention, and eviction remain in `SessionTimelineRuntime`.
@MainActor
final class SessionTimelineProjectionState {
    let liveSessionID: String
    let storedSessionID: String

    private var liveSession: LiveSession
    private var entries: [TranscriptEntry]
    private var activeTodos: [TodoItem]?
    private var delegationTurns: [DelegationTurnUI]
    private var pinnedDelegationTurnID: String?
    private var isSending: Bool
    private var turnStartedAt: Date?
    private var attachedToExistingTurn: Bool
    private var observedLiveEvents: Bool
    private var coordinator: LiveTranscriptCoordinator

    init(
        snapshot: SessionTimelineRuntime.Snapshot,
        observedLiveEvents: Bool
    ) {
        liveSessionID = snapshot.liveSession.liveID
        storedSessionID = snapshot.storedSessionID
        liveSession = snapshot.liveSession
        entries = snapshot.entries
        activeTodos = snapshot.activeTodos
        delegationTurns = snapshot.delegationTurns
        pinnedDelegationTurnID = snapshot.pinnedDelegationTurnID
        isSending = snapshot.isSending
        turnStartedAt = snapshot.turnStartedAt
        attachedToExistingTurn = snapshot.attachedToExistingTurn
        self.observedLiveEvents = observedLiveEvents
        coordinator = snapshot.coordinator
    }

    func update(
        from snapshot: SessionTimelineRuntime.Snapshot,
        observedLiveEvent: Bool
    ) {
        liveSession = snapshot.liveSession
        entries = snapshot.entries
        activeTodos = snapshot.activeTodos
        delegationTurns = snapshot.delegationTurns
        pinnedDelegationTurnID = snapshot.pinnedDelegationTurnID
        isSending = snapshot.isSending
        turnStartedAt = snapshot.turnStartedAt
        attachedToExistingTurn = snapshot.attachedToExistingTurn
        observedLiveEvents = observedLiveEvents || observedLiveEvent
        coordinator = snapshot.coordinator
    }

    func apply(
        _ event: HermesStreamEvent,
        gatewayID: String?
    ) -> SessionTimelineRuntime.EventProjection {
        var statusMutation =
            SessionTimelineRuntime.ActiveStatusMutation.unchanged
        switch event {
        case .messageStart:
            coordinator.beginTurn()
            isSending = true
            turnStartedAt = turnStartedAt ?? Date()
            activeTodos = nil
            liveSession = replacingRuntimeState(
                in: liveSession,
                running: true,
                status: "working"
            )
            statusMutation = .set("working")
        case let .assistantDelta(_, text):
            coordinator.appendAssistant(text, to: &entries)
            if !isSending {
                isSending = true
            }
        case let .assistantInterim(_, text):
            entries = coordinator.finalizeInterimAssistant(
                text,
                in: entries
            )
            isSending = true
        case let .assistantCompleted(_, text, _):
            entries = coordinator.completeAssistant(text, in: entries)
            entries.removeAll { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.pending
            }
            isSending = false
            turnStartedAt = nil
            attachedToExistingTurn = false
            liveSession = replacingRuntimeState(
                in: liveSession,
                running: false,
                status: "idle",
                inflight: nil
            )
            statusMutation = .remove
        case let .toolStart(_, toolID, name, detail, context, _):
            updateTool(
                LiveToolEvent(
                    toolID: toolID,
                    name: name,
                    status: "running",
                    content: detail ?? "",
                    label: context
                )
            )
        case let .toolComplete(
            _,
            toolID,
            name,
            result,
            outcome,
            summary,
            durationSeconds,
            todos,
            inlineDiff
        ):
            let status = switch outcome {
            case .interrupted:
                "stopped"
            case .failed:
                "failed"
            case .succeeded, .unknown:
                "done"
            }
            updateTool(
                LiveToolEvent(
                    toolID: toolID,
                    name: name,
                    status: status,
                    content: result ?? "",
                    outcome: outcome,
                    summary: summary,
                    durationSeconds: durationSeconds,
                    todos: todos,
                    inlineDiff: inlineDiff
                )
            )
        case let .statusUpdate(_, text):
            if !text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                entries = coordinator.appendSystem(text, to: entries)
            }
        case let .error(_, message):
            entries = coordinator.appendSystem(
                message,
                isError: true,
                to: entries
            )
            isSending = false
            turnStartedAt = nil
            attachedToExistingTurn = false
            liveSession = replacingRuntimeState(
                in: liveSession,
                running: false,
                status: "idle",
                inflight: nil
            )
            statusMutation = .remove
        case let .sessionInfoUpdate(_, info):
            liveSession = LiveSession(
                liveID: liveSession.liveID,
                storedID: liveSession.storedID,
                info: info,
                messages: liveSession.messages,
                running: liveSession.running,
                status: liveSession.status,
                inflight: liveSession.inflight
            )
        default:
            break
        }
        observedLiveEvents = true
        return SessionTimelineRuntime.EventProjection(
            storedSessionID: storedSessionID,
            activeStatusMutation: statusMutation,
            switchPresentation: switchPresentation(gatewayID: gatewayID)
        )
    }

    func restore(
        resumed: LiveSession
    ) -> SessionTimelineRuntime.Snapshot? {
        guard resumed.turnInFlight, observedLiveEvents else {
            return nil
        }
        liveSession = resumed
        isSending = true
        attachedToExistingTurn = true
        return snapshot
    }

    func switchPresentation(
        gatewayID: String?
    ) -> SessionSwitchPresentation? {
        guard !entries.isEmpty else {
            return nil
        }
        return SessionSwitchPresentation(
            sessionID: storedSessionID,
            entries: entries,
            scrollOwner: gatewayID.map {
                TranscriptScrollOwner(
                    gatewayID: $0,
                    sessionID: storedSessionID
                )
            },
            delegationTurns: delegationTurns,
            pinnedDelegationTurnID: pinnedDelegationTurnID,
            activeTodos: activeTodos,
            isSending: isSending
        )
    }

    private var snapshot: SessionTimelineRuntime.Snapshot {
        SessionTimelineRuntime.Snapshot(
            liveSession: liveSession,
            storedSessionID: storedSessionID,
            entries: entries,
            activeTodos: activeTodos,
            delegationTurns: delegationTurns,
            pinnedDelegationTurnID: pinnedDelegationTurnID,
            isSending: isSending,
            turnStartedAt: turnStartedAt,
            attachedToExistingTurn: attachedToExistingTurn,
            coordinator: coordinator
        )
    }

    private func updateTool(_ event: LiveToolEvent) {
        let projection = coordinator.upsertTool(
            in: entries,
            activeTodos: activeTodos,
            event: event
        )
        entries = projection.transcript
        activeTodos = projection.activeTodos
    }

    private func replacingRuntimeState(
        in session: LiveSession,
        running: Bool,
        status: String?,
        inflight: InflightTurn? = nil
    ) -> LiveSession {
        LiveSession(
            liveID: session.liveID,
            storedID: session.storedID,
            info: session.info,
            messages: session.messages,
            running: running,
            status: status,
            inflight: inflight
        )
    }
}
