import Foundation

/// The model-facing boundary for cached timelines and transcript projection.
///
/// SessionTimelineRuntime owns bounded offscreen storage and event projection.
/// This extension binds that runtime to visible live/stored transcript state
/// without consuming Hermes events or constructing repository capabilities.
@MainActor
extension SessionListModel {
    func cacheVisibleLiveTimeline(
        observedLiveEvent: Bool = false
    ) {
        guard let liveSession,
              let storedSessionID = liveSession.storedID ?? selectedSessionID
        else {
            return
        }
        runtimes.timelineRuntime.capture(
            SessionTimelineRuntime.Snapshot(
                liveSession: liveSession,
                storedSessionID: storedSessionID,
                entries: transcriptEntries,
                activeTodos: activeTodos,
                delegationTurns: delegationTurns,
                pinnedDelegationTurnID: pinnedDelegationTurnID,
                isSending: isSending,
                turnStartedAt: turnStartedAt,
                attachedToExistingTurn: attachedToExistingTurn,
                coordinator: liveTranscript
            ),
            observedLiveEvent: observedLiveEvent
        )
    }

    func restoreCachedLiveTimeline(
        storedSessionID: String,
        resumed: LiveSession
    ) -> Bool {
        guard let timeline = runtimes.timelineRuntime.restore(
            storedSessionID: storedSessionID,
            resumed: resumed
        ) else {
            return false
        }
        liveSession = timeline.liveSession
        liveTranscript = timeline.coordinator
        transcriptEntries = timeline.entries
        activeTodos = timeline.activeTodos
        delegationTurns = timeline.delegationTurns
        pinnedDelegationTurnID = timeline.pinnedDelegationTurnID
        isSending = true
        isStopping = false
        turnStartedAt = timeline.turnStartedAt
        attachedToExistingTurn = true
        bindLiveSessionRuntime(resumed)
        applyActiveStatus(
            resumed.status ?? "working",
            storedSessionID: storedSessionID
        )
        syncDelegationUI()
        syncBlockingPromptUI()
        restoreComposerPresentation()
        hydrateVisibleMediaAttachments()
        cacheVisibleLiveTimeline()
        return true
    }

    func cachedSwitchPresentation(
        storedSessionID: String
    ) -> SessionSwitchPresentation? {
        runtimes.timelineRuntime.switchPresentation(
            storedSessionID: storedSessionID,
            gatewayID: currentGatewayID
        )
    }

    func scheduleVisibleSessionReconciliation() {
        guard runtimes.lifecycleRuntime.isForeground,
              state == .loaded,
              connectionPhase == .online,
              !isOpeningSession,
              !isClaimingSession,
              !isReadOnlySession,
              let storedSessionID = selectedSessionID,
              let liveSessionID = liveSession?.liveID,
              let owner = navigationDisplayOwner(
                  storedSessionID: storedSessionID,
                  liveSessionID: liveSessionID
              ) else {
            return
        }
        runtimes.navigationRuntime.reconcileDisplay(owner: owner) { [weak self] owner, resumed in
            guard let self,
                  self.isCurrentNavigationDisplayOwner(owner),
                  !self.isReadOnlySession else {
                return
            }
            self.storedMessages = []
            if !self.restoreCachedLiveTimeline(
                storedSessionID: owner.storedSessionID,
                resumed: resumed
            ) {
                self.liveSession = resumed
                self.applyLiveSessionTranscript(resumed)
            }
        }
    }

    func applyStoredTranscript(_ messages: [HermesMessage]) {
        resetSessionUsage()
        attachedToExistingTurn = false
        liveTranscript = LiveTranscriptCoordinator()
        if let selectedSessionID {
            runtimes.timelineRuntime.remove(storedSessionID: selectedSessionID)
        }
        transcriptEntries = messages.enumerated().map { index, message in
            message.transcriptEntry(
                index: index,
                imageCache: liveTranscript.cachedImages()
            )
        }
        activeTodos = nil
        composer = ""
        isSending = false
        isStopping = false
        turnStartedAt = nil
        if let gatewayID = currentGatewayID, let selectedSessionID {
            ensureDelegationSnapshotsLoaded(
                owner: DelegationOwner(
                    gatewayID: gatewayID,
                    storedSessionID: selectedSessionID
                )
            )
        }
        syncDelegationUI()
        syncBlockingPromptUI()
        hydrateVisibleMediaAttachments()
    }

    func applyLiveSessionTranscript(_ live: LiveSession) {
        liveTranscript = LiveTranscriptCoordinator()
        bindLiveSessionRuntime(live)
        var entries = live.messages.enumerated().map { index, message in
            message.transcriptEntry(
                index: index,
                imageCache: liveTranscript.cachedImages()
            )
        }
        var seededAssistantID: String?
        if let inflight = live.inflight,
           !inflight.user
               .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entries.append(
                HermesMessage(role: "user", text: inflight.user)
                    .transcriptEntry(
                        index: entries.count,
                        imageCache: liveTranscript.cachedImages()
                    )
            )
        }
        if let inflight = live.inflight,
           !inflight.assistant
               .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let id = "inflight-assistant-\(live.liveID)"
            seededAssistantID = id
            entries.append(
                .message(
                    TranscriptMessage(
                        id: id,
                        role: .assistant,
                        content: inflight.assistant
                    )
                )
            )
        }
        if live.turnInFlight {
            let message = live.status == "waiting"
                ? "the agent is waiting for input requested before this device attached — answer from another client, or stop the run"
                : "catching up with a running turn — tool detail appears when it finishes"
            entries.append(
                .message(
                    TranscriptMessage(
                        id: "attached-status-\(live.liveID)",
                        role: .system,
                        content: message
                    )
                )
            )
        }
        transcriptEntries = entries
        activeTodos = nil
        isSending = live.turnInFlight
        isStopping = false
        turnStartedAt = nil
        attachedToExistingTurn = live.inflight != nil || live.turnInFlight
        liveTranscript.restoreTurn(
            activeAssistantID: live.turnInFlight ? seededAssistantID : nil,
            turnProducedText: seededAssistantID != nil
        )
        syncDelegationUI()
        syncBlockingPromptUI()
        restoreComposerPresentation()
        hydrateVisibleMediaAttachments()
        cacheVisibleLiveTimeline()
    }

    private func bindLiveSessionRuntime(_ live: LiveSession) {
        if let gatewayID = currentGatewayID {
            let storedSessionID = live.storedID ?? selectedSessionID
            if live.turnInFlight {
                beginBackgroundTurn(
                    gatewayID: gatewayID,
                    storedSessionID: storedSessionID,
                    liveSessionID: live.liveID
                )
            } else {
                runtimes.lifecycleRuntime.completeReconciledTurn(
                    gatewayID: gatewayID,
                    storedSessionID: storedSessionID
                )
            }
            runtimes.blockingPromptRuntime.bindSession(
                gatewayID: gatewayID,
                liveSessionID: live.liveID,
                storedSessionID: storedSessionID,
                turnInFlight: live.turnInFlight
            )
            if let storedSessionID = live.storedID ?? selectedSessionID {
                let owner = DelegationOwner(
                    gatewayID: gatewayID,
                    storedSessionID: storedSessionID
                )
                runtimes.delegationRuntime.bindLiveSession(
                    owner: owner,
                    liveSessionID: live.liveID
                )
                ensureDelegationSnapshotsLoaded(owner: owner)
            }
        }
    }
}
