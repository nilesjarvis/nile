import Foundation

@MainActor
extension SessionListModel {
    func startRefreshingIfNeeded() {
        guard state == .loaded else {
            return
        }
        runtimes.navigationRuntime.startRefreshing(
            sink: SessionNavigationRuntime.RefreshSink(
                request: { [weak self] in self?.navigationRefreshRequest() },
                sessions: { [weak self] owner, sessions in
                    self?.applyRefreshedSessions(sessions, owner: owner)
                },
                prepareStatuses: { [weak self] owner in
                    guard let self else {
                        return { _ in }
                    }
                    let poll = self.runtimes.blockingPromptRuntime.beginStatusPoll()
                    return { [weak self] statuses in
                        self?.applyRefreshedStatuses(
                            statuses, poll: poll, owner: owner
                        )
                    }
                },
                history: { [weak self] owner, messages in
                    self?.applyRefreshedHistory(messages, owner: owner)
                }
            )
        )
    }

    private func navigationRefreshRequest()
        -> SessionNavigationRuntime.RefreshRequest? {
        guard let gatewayOwner = currentNavigationGatewayOwner,
              state == .loaded,
              !isOpeningSession,
              !isClaimingSession else {
            return nil
        }
        let readOnlyDisplayOwner: SessionNavigationRuntime.DisplayOwner? =
            if isReadOnlySession, let selectedSessionID {
                SessionNavigationRuntime.DisplayOwner(
                    gatewayGeneration: gatewayOwner.gatewayGeneration,
                    displayGeneration: displayGeneration,
                    gatewayID: gatewayOwner.gatewayID,
                    storedSessionID: selectedSessionID,
                    liveSessionID: nil
                )
            } else {
                nil
            }
        return SessionNavigationRuntime.RefreshRequest(
            gatewayOwner: gatewayOwner,
            readOnlyDisplayOwner: readOnlyDisplayOwner
        )
    }

    private func applyRefreshedSessions(
        _ fetched: [HermesSession],
        owner: SessionNavigationRuntime.GatewayOwner
    ) {
        guard isCurrentNavigationGatewayOwner(owner) else { return }
        recordListedSessionOwnership(fetched)
        sessions = overlaySelectedLiveSession(on: fetched)
    }

    private func applyRefreshedStatuses(
        _ statuses: [String: String],
        poll: BlockingPromptStatusPollToken,
        owner: SessionNavigationRuntime.GatewayOwner
    ) {
        guard isCurrentNavigationGatewayOwner(owner) else { return }
        activeStatuses = statuses
        _ = runtimes.blockingPromptRuntime.reconcileStatusPoll(
            token: poll,
            gatewayID: owner.gatewayID,
            currentGatewayID: currentGatewayID,
            statuses: statuses
        )
        syncBlockingPromptUI()
        if attachedToExistingTurn,
           isSending,
           let selectedSessionID,
           !SessionClaimRuntime.busyStatuses.contains(
               statuses[selectedSessionID]?
                   .trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased() ?? ""
           ) {
            scheduleVisibleSessionReconciliation()
        }
    }

    private func applyRefreshedHistory(
        _ messages: [HermesMessage],
        owner: SessionNavigationRuntime.DisplayOwner
    ) {
        guard isCurrentNavigationDisplayOwner(owner),
              isReadOnlySession,
              !isOpeningSession,
              !isClaimingSession else {
            return
        }
        storedMessages = messages
        applyStoredTranscript(messages)
    }
}
