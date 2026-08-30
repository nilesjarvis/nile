import Foundation

/// The sole ordered Hermes event-application boundary for SessionListModel.
///
/// SessionEventRuntime owns the repository event task and assistant-delta
/// cadence. This extension alone orders cross-feature settlement and visible
/// projection stages; same-model helpers cannot consume the stream directly.
@MainActor
extension SessionListModel {
    func beginRoutingEventsIfNeeded() {
        runtimes.eventRuntime.beginRouting(
            visibleSessionID: { [weak self] in
                self?.liveSession?.liveID
            },
            onOrderedEvent: { [weak self] event in
                self?.consume(event)
            },
            onVisibleAssistantDelta: { [weak self] event in
                self?.applyAssistantDelta(event) ?? false
            },
            onHiddenAssistantDelta: { [weak self] event in
                self?.consumeCachedLiveEvent(event)
            }
        )
    }

    private func consume(_ event: HermesStreamEvent) {
        let visibleSessionID = liveSession?.liveID
        let targetsVisibleSession = !event.sessionID.isEmpty
            && event.sessionID == visibleSessionID
        if !event.sessionID.isEmpty, !targetsVisibleSession {
            consumeCachedLiveEvent(event)
        }
        defer {
            if targetsVisibleSession {
                cacheVisibleLiveTimeline(observedLiveEvent: true)
            }
        }

        applyDelegationLifecycle(event)
        settleTurnLifecycle(event)
        guard !consumeBlockingPromptEvent(event) else {
            return
        }
        settleTerminalResources(event)
        applyVisibleEvent(event)
    }
}
