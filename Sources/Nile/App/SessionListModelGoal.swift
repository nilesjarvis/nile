import Foundation

/// Model-facing standing-goal actions and turn integration.
///
/// SessionGoalRuntime retains goal capability tasks, lifecycle generations,
/// validation, and progress state. This extension projects those decisions
/// into the visible session while authoritative Hermes events remain at the
/// core model's single ordered application boundary.
@MainActor
extension SessionListModel {
    func setGoalSheetVisible(_ visible: Bool) {
        guard visible else {
            runtimes.goalRuntime.dismissSheet()
            return
        }
        guard goalAvailability == .available,
              showsComposer,
              !isOpeningSession else {
            operationError = goalAvailability == .unknown
                ? "Nile is still checking whether this Hermes session supports standing goals."
                : "Standing goals are unavailable on this Hermes profile."
            isGoalSheetVisible = false
            return
        }
        runtimes.goalRuntime.presentSheet()
    }

    func startGoal(_ objective: String, maxTurns: Int?) {
        runtimes.goalRuntime.start(
            objective: objective,
            maxTurns: maxTurns,
            context: goalActionContext()
        ) { [weak self] owner, prompt in
            self?.submitGoalPrompt(owner: owner, prompt: prompt)
        }
    }

    func pauseGoal() {
        runtimes.goalRuntime.pause(context: goalActionContext())
    }

    func resumeGoal() {
        runtimes.goalRuntime.resume(context: goalActionContext()) {
            [weak self] owner, prompt in
            self?.submitGoalPrompt(owner: owner, prompt: prompt)
        }
    }

    func continueGoal() {
        if let (owner, prompt) = runtimes.goalRuntime.continuePrompt(
            context: goalActionContext()
        ) {
            submitGoalPrompt(owner: owner, prompt: prompt)
        }
    }

    func clearGoal() {
        runtimes.goalRuntime.clear(context: goalActionContext())
    }

    private func submitGoalPrompt(
        owner: SessionGoalRuntime.Owner,
        prompt: String
    ) {
        guard isCurrentGoalOwner(owner),
              !isSending,
              !isUpdatingSessionControls,
              pendingAttachments.isEmpty,
              runtimes.goalRuntime.beginPrompt(owner: owner) else {
            return
        }
        let entryID = "goal-\(UUID().uuidString)"
        liveTranscript.beginTurn()
        transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: entryID,
                    role: .user,
                    content: prompt,
                    isGoalPrompt: true
                )
            )
        )
        isSending = true
        turnStartedAt = Date()
        activeTodos = nil
        activeStatuses[owner.storedSessionID] = "working"
        beginBackgroundTurn(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: owner.liveSessionID
        )

        _ = runtimes.turnRuntime.sendPrompt(
            liveSessionID: owner.liveSessionID,
            text: prompt,
            prepare: { true },
            onOutcome: { [weak self] outcome in
                switch outcome {
                case .accepted:
                    break
                case .preparationFailed:
                    self?.settleGoalPromptFailure(
                        owner: owner,
                        entryID: entryID,
                        errorMessage: "turn preparation failed",
                        uncertain: false
                    )
                case .cancelled:
                    self?.settleGoalPromptFailure(
                        owner: owner,
                        entryID: entryID,
                        errorMessage: nil,
                        uncertain: true
                    )
                case let .failed(message, uncertain):
                    self?.settleGoalPromptFailure(
                        owner: owner,
                        entryID: entryID,
                        errorMessage: message,
                        uncertain: uncertain
                    )
                }
            }
        )
    }

    private func settleGoalPromptFailure(
        owner: SessionGoalRuntime.Owner,
        entryID: String,
        errorMessage: String?,
        uncertain: Bool
    ) {
        guard isCurrentGoalOwner(owner) else {
            return
        }
        if !uncertain {
            stopBackgroundTurn(
                gatewayID: owner.gatewayID,
                liveSessionID: owner.liveSessionID
            )
            transcriptEntries.removeAll { $0.id == entryID }
            activeStatuses.removeValue(forKey: owner.storedSessionID)
            isSending = false
            turnStartedAt = nil
        }
        runtimes.goalRuntime.recordPromptFailure(
            owner: owner,
            errorMessage: errorMessage,
            uncertain: uncertain
        )
    }

    private func goalActionContext() -> SessionGoalRuntime.ActionContext {
        SessionGoalRuntime.ActionContext(
            owner: captureGoalOwner(),
            isUpdatingSessionControls: isUpdatingSessionControls,
            isSending: isSending,
            isStopping: isStopping,
            hasPendingAttachments: !pendingAttachments.isEmpty,
            isAttaching: isAttaching
        )
    }

    func captureGoalOwner() -> SessionGoalRuntime.Owner? {
        guard state == .loaded,
              !isReadOnlySession,
              !isOpeningSession,
              let gatewayID = currentGatewayID,
              let storedSessionID = selectedSessionID,
              let liveSessionID = liveSession?.liveID else {
            return nil
        }
        return SessionGoalRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    private func isCurrentGoalOwner(
        _ owner: SessionGoalRuntime.Owner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.displayGeneration == displayGeneration
            && owner.gatewayID == currentGatewayID
            && owner.storedSessionID == selectedSessionID
            && owner.liveSessionID == liveSession?.liveID
            && runtimes.goalRuntime.matches(owner: owner)
    }
}
