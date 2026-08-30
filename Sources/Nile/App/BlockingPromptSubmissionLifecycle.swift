import Foundation

/// Applies response and approval-FIFO transitions to coordinator-owned safe records.
/// Raw response values remain parameters only and are never stored.
extension BlockingPromptCoordinator {
    func responseTarget(promptID: String) -> BlockingPromptResponseTarget? {
        guard let record = records.first(where: { $0.id == promptID }),
              record.prompt.status == .pending,
              record.prompt.actionable else {
            return nil
        }
        return responseTarget(record)
    }

    func beginResponse(
        promptID: String,
        response: String
    ) -> BlockingPromptSubmission? {
        guard let index = records.firstIndex(where: { $0.id == promptID }),
              records[index].prompt.status == .pending,
              records[index].prompt.actionable else {
            return nil
        }
        let record = records[index]
        let approvalChoice: ApprovalChoice?
        if record.prompt.kind == .approval {
            guard let choice = ApprovalChoice(rawValue: response),
                  record.prompt.actions.contains(where: {
                      $0.value == choice.rawValue
                  }),
                  approvalQueueHead(
                      gatewayID: record.gatewayID,
                      liveSessionID: record.liveSessionID
                  )?.id == record.id else {
                return nil
            }
            approvalChoice = choice
        } else {
            approvalChoice = nil
        }

        let summary = BlockingPromptPolicy.responseLabel(
            prompt: record.prompt,
            response: response
        )
        records[index].prompt.status = .submitting
        records[index].prompt.statusMessage = "Sending response…"
        records[index].prompt.actionable = false
        return BlockingPromptSubmission(
            promptID: record.id,
            kind: record.prompt.kind,
            requestID: record.requestID,
            liveSessionID: record.liveSessionID,
            approvalChoice: approvalChoice,
            resolvedStatusMessage: summary
        )
    }

    func submitResponse(
        _ submission: BlockingPromptSubmission,
        response: String,
        respond: (
            BlockingPromptSubmission,
            String
        ) async throws -> Bool
    ) async rethrows -> BlockingPromptSubmissionOutcome {
        let resolved: Bool
        do {
            resolved = try await respond(submission, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return settleResponseFailure(submission, error: error)
        }

        let changed: Bool
        if resolved {
            changed = resolveSubmission(
                promptID: submission.promptID,
                statusMessage: submission.resolvedStatusMessage
            )
        } else if submission.kind == .approval {
            changed = markApprovalQueueUnavailableForSubmission(
                promptID: submission.promptID,
                message: "These approval requests are no longer waiting."
            )
        } else {
            changed = markSubmissionUnavailable(
                promptID: submission.promptID,
                message: "This request is no longer waiting."
            )
        }
        return changed ? .settled : .stale
    }

    @discardableResult
    func resolveSubmission(
        promptID: String,
        statusMessage: String
    ) -> Bool {
        updateSubmitting(promptID: promptID) {
            $0.status = .resolved
            $0.statusMessage = statusMessage
            $0.actionable = false
        }
    }

    @discardableResult
    func markSubmissionUnavailable(
        promptID: String,
        message: String
    ) -> Bool {
        updateSubmitting(promptID: promptID) {
            $0.status = .unavailable
            $0.statusMessage = message
            $0.actionable = false
        }
    }

    @discardableResult
    func markSubmissionUncertain(
        promptID: String,
        message: String
    ) -> Bool {
        updateSubmitting(promptID: promptID) {
            $0.status = .uncertain
            $0.statusMessage = message
            $0.actionable = false
        }
    }

    @discardableResult
    func markSubmittingUncertain(gatewayID: String?) -> Bool {
        guard let gatewayID else {
            return false
        }
        for index in records.indices
        where records[index].gatewayID == gatewayID
            && records[index].prompt.status == .submitting {
            records[index].prompt.status = .uncertain
            records[index].prompt.statusMessage =
                "Hermes may have received the response. Stop the run if it stays blocked."
            records[index].prompt.actionable = false
        }
        return true
    }

    func retrySubmission(promptID: String) -> BlockingPromptResponseTarget? {
        guard let index = submittingIndex(promptID: promptID) else {
            return nil
        }
        records[index].prompt.status = .pending
        records[index].prompt.statusMessage = nil
        records[index].prompt.actionable = true
        return responseTarget(records[index])
    }

    @discardableResult
    func markApprovalQueueUnavailableForSubmission(
        promptID: String,
        message: String
    ) -> Bool {
        guard let index = submittingIndex(promptID: promptID) else {
            return false
        }
        let record = records[index]
        markApprovalQueueUnavailable(
            gatewayID: record.gatewayID,
            liveSessionID: record.liveSessionID,
            message: message
        )
        return true
    }

    private func settleResponseFailure(
        _ submission: BlockingPromptSubmission,
        error: any Error
    ) -> BlockingPromptSubmissionOutcome {
        let hermes = error as? HermesError
        if submission.kind == .approval, hermes?.code == 4001 {
            let changed = markApprovalQueueUnavailableForSubmission(
                promptID: submission.promptID,
                message: "These approval requests are no longer waiting."
            )
            return changed ? .failed : .stale
        }
        if hermes?.code == 4009 {
            let changed = markSubmissionUnavailable(
                promptID: submission.promptID,
                message:
                    "This request was answered elsewhere or timed out."
            )
            return changed ? .failed : .stale
        }
        if BlockingPromptPolicy.hasUncertainOutcome(error) {
            let changed = markSubmissionUncertain(
                promptID: submission.promptID,
                message:
                    "Hermes may have received the response. Stop the run if it stays blocked."
            )
            return changed ? .failed : .stale
        }
        if submission.kind == .approval, hermes?.code != 5032 {
            let changed = markSubmissionUncertain(
                promptID: submission.promptID,
                message:
                    "Hermes may have handled this approval. Stop the run if it stays blocked."
            )
            return changed ? .failed : .stale
        }
        guard let target = retrySubmission(promptID: submission.promptID) else {
            return .stale
        }
        return .retryableFailure(target: target, error: error)
    }

    private func approvalQueueHead(
        gatewayID: String,
        liveSessionID: String
    ) -> BlockingPromptRecord? {
        records
            .filter {
                $0.gatewayID == gatewayID
                    && $0.liveSessionID == liveSessionID
                    && $0.prompt.kind == .approval
                    && $0.prompt.status.isOpen
            }
            .min { $0.arrivalOrder < $1.arrivalOrder }
    }

    func actionable(record: BlockingPromptRecord) -> Bool {
        BlockingPromptPolicy.isActionable(
            prompt: record.prompt,
            isApprovalQueueHead: approvalQueueHead(
                gatewayID: record.gatewayID,
                liveSessionID: record.liveSessionID
            )?.id == record.id
        )
    }

    private func submittingIndex(promptID: String) -> Int? {
        records.firstIndex {
            $0.id == promptID && $0.prompt.status == .submitting
        }
    }

    private func updateSubmitting(
        promptID: String,
        update: (inout TranscriptBlockingPrompt) -> Void
    ) -> Bool {
        guard let index = submittingIndex(promptID: promptID) else {
            return false
        }
        update(&records[index].prompt)
        return true
    }

    private func markApprovalQueueUnavailable(
        gatewayID: String,
        liveSessionID: String,
        message: String
    ) {
        for index in records.indices
        where records[index].gatewayID == gatewayID
            && records[index].liveSessionID == liveSessionID
            && records[index].prompt.kind == .approval
            && records[index].prompt.status.isOpen {
            markUnavailable(index: index, message: message)
        }
    }

    private func responseTarget(
        _ record: BlockingPromptRecord
    ) -> BlockingPromptResponseTarget {
        BlockingPromptResponseTarget(
            gatewayID: record.gatewayID,
            liveSessionID: record.liveSessionID,
            storedSessionID: record.storedSessionID
        )
    }
}
