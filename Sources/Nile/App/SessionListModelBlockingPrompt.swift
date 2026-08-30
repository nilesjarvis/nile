import Foundation

/// Sensitive response admission and visible blocking-prompt projection.
/// Response values remain task-local inside `SessionBlockingPromptRuntime`.
@MainActor
extension SessionListModel {
    func respondToBlockingPrompt(promptID: String, response: String) {
        _ = runtimes.blockingPromptRuntime.respond(
            promptID: promptID,
            response: response,
            isCurrentTarget: { [weak self] target in
                guard let self else {
                    return false
                }
                return target.gatewayID == self.currentGatewayID
                    && target.liveSessionID == self.liveSession?.liveID
                    && target.storedSessionID == self.selectedSessionID
                    && !self.isOpeningSession
                    && !self.isReadOnlySession
                    && self.state == .loaded
            },
            onChanged: { [weak self] in
                self?.syncBlockingPromptUI()
            },
            onError: { [weak self] _, error in
                self?.operationError = error.localizedDescription
            }
        )
    }

    func syncBlockingPromptUI() {
        let projection = runtimes.blockingPromptRuntime.project(
            gatewayID: currentGatewayID,
            liveSessionID: liveSession?.liveID,
            storedSessionID: selectedSessionID,
            transcript: transcriptEntries
        )
        if transcriptEntries != projection.transcript {
            transcriptEntries = projection.transcript
        }
        let actionablePromptIDs = Set(
            projection.transcript.compactMap { entry -> String? in
                guard case let .blockingPrompt(prompt) = entry,
                      prompt.status == .pending,
                      prompt.actionable else {
                    return nil
                }
                return prompt.id
            }
        )
        applyPendingActionableBlockingPromptIDs(actionablePromptIDs)
        let needingInput = projection.sessionsNeedingInput
            .union(fixtureAttentionSessionIDs)
        if sessionsNeedingInput != needingInput {
            sessionsNeedingInput = needingInput
        }
    }
}
