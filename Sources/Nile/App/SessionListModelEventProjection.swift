import Foundation

/// Visible and cached projections invoked by the sole ordered event router.
@MainActor
extension SessionListModel {
    func handleGoalUpdate(
        sessionID: String,
        update: GoalProgressUpdate
    ) {
        guard sessionID == liveSession?.liveID else {
            return
        }
        runtimes.goalRuntime.handleProgressUpdate(
            owner: captureGoalOwner(),
            update: update,
            isSending: isSending,
            isSessionSending: { [weak self] in
                self?.isSending ?? false
            },
            onSynchronized: { [weak self] authoritative in
                self?.markStandingGoalPrompts(authoritative)
            }
        )
    }

    func markStandingGoalPrompts(_ authoritative: HermesGoal?) {
        transcriptEntries = transcriptEntries.markingStandingGoalPrompts(
            objective: authoritative?.objective ?? goal?.objective
        )
    }

    func applyAssistantDelta(_ event: HermesStreamEvent) -> Bool {
        guard case let .assistantDelta(sessionID, text) = event else {
            return false
        }
        guard sessionID == liveSession?.liveID else {
            consumeCachedLiveEvent(event)
            return false
        }
        liveTranscript.appendAssistant(text, to: &transcriptEntries)
        if !isSending {
            isSending = true
        }
        cacheVisibleLiveTimeline(observedLiveEvent: true)
        return true
    }

    func consumeCachedLiveEvent(_ event: HermesStreamEvent) {
        guard let projection = runtimes.timelineRuntime.consume(
            event,
            gatewayID: currentGatewayID
        ) else {
            return
        }
        switch projection.activeStatusMutation {
        case .unchanged:
            break
        case let .set(status):
            activeStatuses[projection.storedSessionID] = status
        case .remove:
            activeStatuses.removeValue(
                forKey: projection.storedSessionID
            )
        }
        if isOpeningSession,
           selectedSessionID == projection.storedSessionID {
            sessionSwitchPresentation = projection.switchPresentation
        }
    }

    func refreshCompletedAttachedTurn(
        storedSessionID: String,
        liveSessionID: String
    ) {
        guard let owner = navigationDisplayOwner(
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        ) else {
            return
        }
        runtimes.navigationRuntime.refreshCompletedAttachedTurn(owner: owner) {
            [weak self] owner, resumed in
            guard let self,
                  self.isCurrentNavigationDisplayOwner(owner),
                  !self.isReadOnlySession,
                  !self.isSending else {
                return
            }
            self.liveSession = resumed
            self.storedMessages = []
            self.applyLiveSessionTranscript(resumed)
        }
    }

    func applyToolEvent(_ event: LiveToolEvent) {
        let projection = liveTranscript.upsertTool(
            in: transcriptEntries,
            activeTodos: activeTodos,
            event: event
        )
        transcriptEntries = projection.transcript
        activeTodos = projection.activeTodos
        hydrateVisibleMediaAttachments()
    }

}
