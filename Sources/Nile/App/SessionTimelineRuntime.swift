import Foundation

struct SessionSwitchPresentation: Equatable, Sendable {
    let sessionID: String
    let entries: [TranscriptEntry]
    let scrollOwner: TranscriptScrollOwner?
    let delegationTurns: [DelegationTurnUI]
    let pinnedDelegationTurnID: String?
    let activeTodos: [TodoItem]?
    let isSending: Bool
}

/// Owns bounded presentation timelines for live sessions parked offscreen.
///
/// `SessionEventRuntime` owns the sole Hermes stream and forwards offscreen
/// events synchronously through the model. This runtime never consumes the
/// stream or performs repository work.
@MainActor
final class SessionTimelineRuntime {
    struct Snapshot {
        let liveSession: LiveSession
        let storedSessionID: String
        let entries: [TranscriptEntry]
        let activeTodos: [TodoItem]?
        let delegationTurns: [DelegationTurnUI]
        let pinnedDelegationTurnID: String?
        let isSending: Bool
        let turnStartedAt: Date?
        let attachedToExistingTurn: Bool
        let coordinator: LiveTranscriptCoordinator
    }

    enum ActiveStatusMutation: Equatable, Sendable {
        case unchanged
        case set(String)
        case remove
    }

    struct EventProjection {
        let storedSessionID: String
        let activeStatusMutation: ActiveStatusMutation
        let switchPresentation: SessionSwitchPresentation?
    }

    private let maximumTimelineCount: Int
    private var timelinesByLiveID: [String: SessionTimelineProjectionState] = [:]
    private var liveIDsByStoredID: [String: String] = [:]
    private var recency: [String] = []

    init(maximumTimelineCount: Int = 8) {
        self.maximumTimelineCount = max(1, maximumTimelineCount)
    }

    var cachedTimelineCount: Int {
        timelinesByLiveID.count
    }

    func capture(
        _ snapshot: Snapshot,
        observedLiveEvent: Bool = false
    ) {
        let liveSessionID = snapshot.liveSession.liveID
        let storedSessionID = snapshot.storedSessionID
        if let previousLiveID = liveIDsByStoredID[storedSessionID],
           previousLiveID != liveSessionID {
            remove(liveSessionID: previousLiveID)
        }

        if let existing = timelinesByLiveID[liveSessionID],
           existing.storedSessionID != storedSessionID {
            remove(liveSessionID: liveSessionID)
        }
        if let existing = timelinesByLiveID[liveSessionID] {
            existing.update(
                from: snapshot,
                observedLiveEvent: observedLiveEvent
            )
        } else {
            timelinesByLiveID[liveSessionID] = SessionTimelineProjectionState(
                snapshot: snapshot,
                observedLiveEvents: observedLiveEvent
            )
        }
        liveIDsByStoredID[storedSessionID] = liveSessionID
        touch(liveSessionID)
        evictIfNeeded(protectedLiveSessionID: liveSessionID)
    }

    func consume(
        _ event: HermesStreamEvent,
        gatewayID: String?
    ) -> EventProjection? {
        guard let timeline = timelinesByLiveID[event.sessionID] else {
            return nil
        }
        let projection = timeline.apply(event, gatewayID: gatewayID)
        touch(timeline.liveSessionID)
        return projection
    }

    func restore(
        storedSessionID: String,
        resumed: LiveSession
    ) -> Snapshot? {
        guard liveIDsByStoredID[storedSessionID] == resumed.liveID,
              let timeline = timelinesByLiveID[resumed.liveID],
              let snapshot = timeline.restore(resumed: resumed) else {
            return nil
        }
        touch(timeline.liveSessionID)
        return snapshot
    }

    func switchPresentation(
        storedSessionID: String,
        gatewayID: String?
    ) -> SessionSwitchPresentation? {
        guard let liveSessionID = liveIDsByStoredID[storedSessionID],
              let timeline = timelinesByLiveID[liveSessionID] else {
            return nil
        }
        return timeline.switchPresentation(gatewayID: gatewayID)
    }

    func remove(storedSessionID: String) {
        guard let liveSessionID = liveIDsByStoredID[storedSessionID] else {
            return
        }
        remove(liveSessionID: liveSessionID)
    }

    func reset() {
        timelinesByLiveID.removeAll()
        liveIDsByStoredID.removeAll()
        recency.removeAll()
    }

    private func touch(_ liveSessionID: String) {
        recency.removeAll { $0 == liveSessionID }
        recency.append(liveSessionID)
    }

    private func evictIfNeeded(protectedLiveSessionID: String) {
        while timelinesByLiveID.count > maximumTimelineCount,
              let candidate = recency.first(where: {
                  $0 != protectedLiveSessionID
              }) {
            remove(liveSessionID: candidate)
        }
    }

    private func remove(liveSessionID: String) {
        guard let removed = timelinesByLiveID.removeValue(
            forKey: liveSessionID
        ) else {
            return
        }
        if liveIDsByStoredID[removed.storedSessionID] == liveSessionID {
            liveIDsByStoredID.removeValue(forKey: removed.storedSessionID)
        }
        recency.removeAll { $0 == liveSessionID }
    }
}
