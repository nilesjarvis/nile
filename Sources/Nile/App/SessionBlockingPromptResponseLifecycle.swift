import Foundation

@MainActor
final class SessionBlockingPromptResponseLifecycle {
    typealias TargetValidator =
        SessionBlockingPromptRuntime.TargetValidator
    typealias ChangeHandler = SessionBlockingPromptRuntime.ChangeHandler
    typealias ErrorHandler = SessionBlockingPromptRuntime.ErrorHandler

    private let repository: (any HermesBlockingPromptServing)?
    private let coordinator: BlockingPromptCoordinator
    private var responseTasks: [UUID: Task<Void, Never>] = [:]
    private var responseGeneration: Int64 = 0

    init(
        repository: (any HermesBlockingPromptServing)?,
        coordinator: BlockingPromptCoordinator
    ) {
        self.repository = repository
        self.coordinator = coordinator
    }

    isolated deinit {
        responseTasks.values.forEach { $0.cancel() }
    }

    @discardableResult
    func respond(
        promptID: String,
        response: String,
        isCurrentTarget: @escaping TargetValidator,
        onChanged: @escaping ChangeHandler,
        onError: @escaping ErrorHandler
    ) -> Bool {
        guard let target = coordinator.responseTarget(promptID: promptID),
              isCurrentTarget(target),
              let submission = coordinator.beginResponse(
                  promptID: promptID,
                  response: response
              ) else {
            return false
        }
        onChanged()

        guard let repository else {
            resolveFixture(submission: submission, response: response)
            onChanged()
            return true
        }

        let operationID = UUID()
        let generation = responseGeneration
        responseTasks[operationID] = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let outcome = try await self.coordinator.submitResponse(
                    submission,
                    response: response
                ) { request, answer in
                    try await Self.dispatch(
                        request,
                        answer: answer,
                        repository: repository
                    )
                }
                self.finishResponse(
                    operationID: operationID,
                    generation: generation,
                    outcome: outcome,
                    isCurrentTarget: isCurrentTarget,
                    onChanged: onChanged,
                    onError: onError
                )
            } catch is CancellationError {
                self.finishCancelledResponse(
                    operationID: operationID,
                    generation: generation,
                    gatewayID: target.gatewayID,
                    onChanged: onChanged
                )
            } catch {
                self.finishUnexpectedFailure(
                    operationID: operationID,
                    generation: generation,
                    target: target,
                    error: error,
                    isCurrentTarget: isCurrentTarget,
                    onChanged: onChanged,
                    onError: onError
                )
            }
        }
        return true
    }

    func reset() {
        responseGeneration &+= 1
        let tasks = Array(responseTasks.values)
        responseTasks.removeAll()
        tasks.forEach { $0.cancel() }
    }

    private func finishResponse(
        operationID: UUID,
        generation: Int64,
        outcome: BlockingPromptSubmissionOutcome,
        isCurrentTarget: TargetValidator,
        onChanged: ChangeHandler,
        onError: ErrorHandler
    ) {
        guard consumeResponseTask(
            operationID: operationID,
            generation: generation
        ) else {
            return
        }
        if case let .retryableFailure(target, error) = outcome,
           isCurrentTarget(target) {
            onError(target, error)
        }
        onChanged()
    }

    private func finishCancelledResponse(
        operationID: UUID,
        generation: Int64,
        gatewayID: String,
        onChanged: ChangeHandler
    ) {
        guard consumeResponseTask(
            operationID: operationID,
            generation: generation
        ) else {
            return
        }
        _ = coordinator.markSubmittingUncertain(gatewayID: gatewayID)
        onChanged()
    }

    private func finishUnexpectedFailure(
        operationID: UUID,
        generation: Int64,
        target: BlockingPromptResponseTarget,
        error: any Error,
        isCurrentTarget: TargetValidator,
        onChanged: ChangeHandler,
        onError: ErrorHandler
    ) {
        guard consumeResponseTask(
            operationID: operationID,
            generation: generation
        ) else {
            return
        }
        if isCurrentTarget(target) {
            onError(target, error)
        }
        onChanged()
    }

    private func consumeResponseTask(
        operationID: UUID,
        generation: Int64
    ) -> Bool {
        guard generation == responseGeneration,
              responseTasks.removeValue(forKey: operationID) != nil else {
            return false
        }
        return true
    }

    private func resolveFixture(
        submission: BlockingPromptSubmission,
        response: String
    ) {
        let statusMessage = if submission.kind == .approval,
                               response == ApprovalChoice.deny.rawValue {
            "Denied"
        } else {
            submission.resolvedStatusMessage
        }
        _ = coordinator.resolveSubmission(
            promptID: submission.promptID,
            statusMessage: statusMessage
        )
    }

    private static func dispatch(
        _ request: BlockingPromptSubmission,
        answer: String,
        repository: any HermesBlockingPromptServing
    ) async throws -> Bool {
        switch request.kind {
        case .clarification:
            guard let requestID = request.requestID else {
                throw HermesError(
                    "Clarification response was missing its request id",
                    retryable: false
                )
            }
            try await repository.respondToClarification(
                requestID: requestID,
                answer: answer
            )
            return true
        case .approval:
            guard let choice = request.approvalChoice else {
                throw HermesError(
                    "Approval response was missing its choice",
                    retryable: false
                )
            }
            return try await repository.respondToApproval(
                liveSessionID: request.liveSessionID,
                choice: choice
            )
        case .sudo:
            guard let requestID = request.requestID else {
                throw HermesError(
                    "Sudo response was missing its request id",
                    retryable: false
                )
            }
            try await repository.respondToSudo(
                requestID: requestID,
                password: answer
            )
            return true
        case .secret:
            guard let requestID = request.requestID else {
                throw HermesError(
                    "Secret response was missing its request id",
                    retryable: false
                )
            }
            try await repository.respondToSecret(
                requestID: requestID,
                value: answer
            )
            return true
        case .unavailable:
            return false
        }
    }
}
