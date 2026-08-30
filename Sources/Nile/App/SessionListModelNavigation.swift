import Foundation

@MainActor
extension SessionListModel {
    func selectSession(id: String) async {
        guard let session = sessions.first(where: { $0.id == id }) else {
            return
        }
        guard !isGoalMutating else {
            operationError =
                "Wait for the standing goal update to finish before switching sessions."
            return
        }
        runtimes.eventRuntime.flushPendingAssistantDelta()
        cacheVisibleLiveTimeline()
        let shouldSettleIncomingSession = selectedSessionID != nil
        let retainedPresentation = cachedSwitchPresentation(
            storedSessionID: id
        ) ?? sessionSwitchPresentation ?? currentSessionSwitchPresentation()
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        endTalkMode()
        runtimes.commandRuntime.resetCompletions()
        runtimes.modelControlRuntime.resetSessionControls()
        runtimes.goalRuntime.reset()
        resetSessionUsage()
        runtimes.claimRuntime.reset()
        runtimes.renameRuntime.reset()
        runtimes.turnRuntime.invalidateStop()
        runtimes.navigationRuntime.cancelDisplayTasks()
        runtimes.mediaRuntime.reset()
        let displayToken = beginSessionDisplayRequest()
        let requestGatewayGeneration = gatewayGeneration
        selectedSessionID = id
        delegationControlError = nil
        isExpanded = false
        liveSession = nil
        storedMessages = []
        transcriptEntries = []
        syncDelegationUI()
        activeTodos = nil
        composer = ""
        pendingAttachments = []
        isAttaching = false
        isAttachmentDraftLocked = false
        isSending = false
        isStopping = false
        turnStartedAt = nil
        attachedToExistingTurn = false
        liveTranscript = LiveTranscriptCoordinator()
        isReadOnlySession = isKnownTerminalSession(session)
        operationError = nil
        isOpeningSession = true
        sessionSwitchPresentation = retainedPresentation

        guard hasSessionRepository else {
            if let fixtureNavigationSwitchDelay,
               shouldSettleIncomingSession {
                try? await Task.sleep(for: fixtureNavigationSwitchDelay)
                guard isCurrentDisplayRequest(
                    displayToken,
                    sessionID: id,
                    gatewayGeneration: requestGatewayGeneration
                ) else {
                    return
                }
            }
            if isReadOnlySession {
                storedMessages = fixtureMessages(for: id)
                applyStoredTranscript(storedMessages)
            } else if let fixtureLiveSession = fixtureLiveSession(for: id) {
                liveSession = fixtureLiveSession
                applyLiveSessionTranscript(fixtureLiveSession)
            } else {
                storedMessages = fixtureMessages(for: id)
                applyStoredTranscript(storedMessages)
            }
            finishSessionDisplay(
                settlingIncomingContent: shouldSettleIncomingSession
            )
            state = .loaded
            return
        }
        guard let gatewayID = currentGatewayID else {
            return
        }
        await openProductionSession(
            SessionOpeningRequest(
                session: session,
                displayToken: displayToken,
                gatewayGeneration: requestGatewayGeneration,
                gatewayID: gatewayID,
                settlingIncomingContent: shouldSettleIncomingSession
            )
        )
    }

    private func currentSessionSwitchPresentation()
        -> SessionSwitchPresentation?
    {
        guard let selectedSessionID,
              !transcriptEntries.visibleTranscriptEntries(
                sending: isSending
              ).isEmpty else {
            return nil
        }
        return SessionSwitchPresentation(
            sessionID: selectedSessionID,
            entries: transcriptEntries,
            scrollOwner: transcriptScrollOwner,
            delegationTurns: delegationTurns,
            pinnedDelegationTurnID: pinnedDelegationTurnID,
            activeTodos: activeTodos,
            isSending: isSending
        )
    }

    func finishSessionDisplay(
        settlingIncomingContent: Bool
    ) {
        if settlingIncomingContent {
            sessionSettleGeneration &+= 1
        }
        sessionSwitchPresentation = nil
        isOpeningSession = false
    }

    func togglePin(id: String) {
        guard sessions.contains(where: { $0.id == id }),
              let gatewayID = currentGatewayID else {
            return
        }
        runtimes.pinRuntime.togglePin(
            sessionID: id,
            owner: SessionPinRuntime.GatewayOwner(
                gatewayGeneration: gatewayGeneration,
                gatewayID: gatewayID
            ),
            onError: { [weak self] message in
                self?.operationError = message
            }
        )
    }

    func beginSessionDisplayRequest() -> Int {
        displayGeneration += 1
        return displayGeneration
    }

    func isCurrentDisplayRequest(
        _ token: Int,
        sessionID: String,
        gatewayGeneration: Int
    ) -> Bool {
        token == displayGeneration
            && gatewayGeneration == self.gatewayGeneration
            && selectedSessionID == sessionID
    }

    func isCurrentGateway(_ gatewayID: String, generation: Int) -> Bool {
        productionGatewayID == gatewayID && gatewayGeneration == generation
    }

    var currentNavigationGatewayOwner:
        SessionNavigationRuntime.GatewayOwner? {
        guard let gatewayID = productionGatewayID else { return nil }
        return SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: gatewayGeneration,
            gatewayID: gatewayID
        )
    }

    func navigationDisplayOwner(
        storedSessionID: String,
        liveSessionID: String?
    ) -> SessionNavigationRuntime.DisplayOwner? {
        guard let gatewayOwner = currentNavigationGatewayOwner else { return nil }
        return SessionNavigationRuntime.DisplayOwner(
            gatewayGeneration: gatewayOwner.gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayOwner.gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    func isCurrentNavigationGatewayOwner(
        _ owner: SessionNavigationRuntime.GatewayOwner
    ) -> Bool {
        owner == currentNavigationGatewayOwner
    }

    func isCurrentNavigationDisplayOwner(
        _ owner: SessionNavigationRuntime.DisplayOwner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.displayGeneration == displayGeneration
            && owner.gatewayID == productionGatewayID
            && owner.storedSessionID == selectedSessionID
            && owner.liveSessionID == liveSession?.liveID
    }

    func applyActiveStatus(
        _ status: String?,
        storedSessionID: String
    ) {
        let normalized = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let normalized, !normalized.isEmpty {
            activeStatuses[storedSessionID] = normalized
        } else {
            activeStatuses.removeValue(forKey: storedSessionID)
        }
    }

    func overlaySelectedLiveSession(
        on fetched: [HermesSession]
    ) -> [HermesSession] {
        guard !isReadOnlySession,
              let selectedSessionID,
              let liveSession,
              liveSession.storedID == selectedSessionID,
              !fetched.contains(where: { $0.id == selectedSessionID }) else {
            return fetched
        }
        let placeholder = sessions.first {
            $0.id == selectedSessionID
        } ?? HermesSession(
            id: selectedSessionID,
            title: "New session",
            preview: nil,
            source: "niles",
            messageCount: 0,
            startedAt: nil,
            lastMessageAt: nil
        )
        return [placeholder] + fetched
    }

    func syncGoalState(
        liveSessionID: String,
        storedSessionID: String,
        displayToken: Int,
        gatewayGeneration requestGatewayGeneration: Int
    ) async {
        guard let gatewayID = currentGatewayID else {
            return
        }
        let owner = SessionGoalRuntime.Owner(
            gatewayGeneration: requestGatewayGeneration,
            displayGeneration: displayToken,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
        guard let synchronization = await runtimes.goalRuntime.synchronize(
            owner: owner
        ), isCurrentDisplayRequest(
            displayToken,
            sessionID: storedSessionID,
            gatewayGeneration: requestGatewayGeneration
        ), liveSession?.liveID == liveSessionID else {
            return
        }
        markStandingGoalPrompts(synchronization.goal)
    }
}
