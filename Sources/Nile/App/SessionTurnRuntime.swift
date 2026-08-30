import Foundation

/// Owns prompt, steering, and Stop transport lifecycles.
///
/// `SessionListModel` retains optimistic transcript, draft-recovery, and
/// background-turn projection through its ordered event-application boundary.
/// `SessionEventRuntime` separately owns the sole Hermes stream. Attachment
/// delivery owns its capability-narrow transport and correlation lifecycle.
@MainActor
final class SessionTurnRuntime {
    enum PromptOutcome: Sendable {
        case preparationFailed
        case accepted(PromptSubmitStatus)
        case failed(message: String, uncertain: Bool)
        case cancelled
    }

    enum SteerOutcome: Sendable {
        case preparationFailed
        case accepted
        case rejected
        case failed(message: String, uncertain: Bool)
        case cancelled
    }

    enum StopOutcome: Sendable {
        case succeeded
        case failed(message: String)
    }

    typealias Preparation = @MainActor @Sendable () async -> Bool
    typealias PromptOutcomeHandler = @MainActor @Sendable
        (PromptOutcome) async -> Void
    typealias SteerOutcomeHandler = @MainActor @Sendable
        (SteerOutcome) async -> Void
    typealias StopOutcomeHandler = @MainActor @Sendable
        (StopOutcome) -> Void

    private let repository: (any HermesTurnServing)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var lifecycleGeneration: Int64 = 0
    private var stopGeneration: Int64 = 0
    private var activeStopRequest: StopRequest?

    init(repository: (any HermesTurnServing)?) {
        self.repository = repository
    }

    isolated deinit {
        tasks.values.forEach { $0.cancel() }
    }

    /// Starts an ordinary prompt lifecycle. A nil repository represents a
    /// deterministic fixture and preserves the model's optimistic projection.
    @discardableResult
    func sendPrompt(
        liveSessionID: String,
        text: String,
        prepare: @escaping Preparation,
        onOutcome: @escaping PromptOutcomeHandler
    ) -> Bool {
        guard let repository else {
            return true
        }
        let operationID = UUID()
        let generation = lifecycleGeneration
        tasks[operationID] = Task { [weak self] in
            let outcome: PromptOutcome
            if await prepare() {
                do {
                    let status = try await repository.submitPrompt(
                        liveSessionID: liveSessionID,
                        text: text
                    )
                    try Task.checkCancellation()
                    outcome = .accepted(status)
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = .failed(
                        message: error.localizedDescription,
                        uncertain: Self.isUncertainMutationFailure(error)
                    )
                }
            } else {
                outcome = .preparationFailed
            }
            guard let self,
                  self.isCurrentTask(
                      operationID,
                      generation: generation
                  ) else {
                return
            }
            await onOutcome(outcome)
            self.finishTask(operationID, generation: generation)
        }
        return true
    }

    /// Starts a steering lifecycle. Multiple steering operations may coexist;
    /// draft-recovery tokens in the model preserve their ordered UI effects.
    @discardableResult
    func sendSteer(
        liveSessionID: String,
        text: String,
        prepare: @escaping Preparation,
        onOutcome: @escaping SteerOutcomeHandler
    ) -> Bool {
        guard let repository else {
            return true
        }
        let operationID = UUID()
        let generation = lifecycleGeneration
        tasks[operationID] = Task { [weak self] in
            let outcome: SteerOutcome
            if await prepare() {
                do {
                    let accepted = try await repository.steer(
                        liveSessionID: liveSessionID,
                        text: text
                    )
                    try Task.checkCancellation()
                    outcome = accepted ? .accepted : .rejected
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = .failed(
                        message: error.localizedDescription,
                        uncertain: Self.isUncertainMutationFailure(error)
                    )
                }
            } else {
                outcome = .preparationFailed
            }
            guard let self,
                  self.isCurrentTask(
                      operationID,
                      generation: generation
                  ) else {
                return
            }
            await onOutcome(outcome)
            self.finishTask(operationID, generation: generation)
        }
        return true
    }

    /// Starts the one active Stop request. Terminal stream events may
    /// invalidate it without cancelling unrelated prompt or steering work.
    @discardableResult
    func stop(
        liveSessionID: String,
        onOutcome: @escaping StopOutcomeHandler
    ) -> Bool {
        guard activeStopRequest == nil else {
            return false
        }
        stopGeneration &+= 1
        let request = StopRequest(
            id: UUID(),
            lifecycleGeneration: lifecycleGeneration,
            stopGeneration: stopGeneration,
            liveSessionID: liveSessionID
        )
        activeStopRequest = request

        guard let repository else {
            activeStopRequest = nil
            onOutcome(.succeeded)
            return true
        }
        tasks[request.id] = Task { [weak self] in
            let outcome: StopOutcome
            do {
                try await repository.interrupt(
                    liveSessionID: liveSessionID
                )
                try Task.checkCancellation()
                outcome = .succeeded
            } catch is CancellationError {
                outcome = .failed(
                    message: "The stop request was interrupted."
                )
            } catch {
                outcome = .failed(message: error.localizedDescription)
            }
            guard let self else {
                return
            }
            let shouldPublish = self.consumeStopRequest(request)
            self.tasks.removeValue(forKey: request.id)
            guard shouldPublish else {
                return
            }
            onOutcome(outcome)
        }
        return true
    }

    /// Invalidates only the active Stop acknowledgement. The request is left
    /// running so transport cleanup can finish, but its late result cannot
    /// settle a subsequent turn.
    func invalidateStop(liveSessionID: String? = nil) {
        if let liveSessionID,
           activeStopRequest?.liveSessionID != liveSessionID {
            return
        }
        stopGeneration &+= 1
        activeStopRequest = nil
    }

    func reset() {
        lifecycleGeneration &+= 1
        stopGeneration &+= 1
        activeStopRequest = nil
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
    }

    private func isCurrentTask(
        _ operationID: UUID,
        generation: Int64
    ) -> Bool {
        generation == lifecycleGeneration && tasks[operationID] != nil
    }

    private func finishTask(
        _ operationID: UUID,
        generation: Int64
    ) {
        guard generation == lifecycleGeneration else {
            return
        }
        tasks.removeValue(forKey: operationID)
    }

    private func consumeStopRequest(_ request: StopRequest) -> Bool {
        guard request.lifecycleGeneration == lifecycleGeneration,
              request.stopGeneration == stopGeneration,
              activeStopRequest == request else {
            return false
        }
        activeStopRequest = nil
        return true
    }

    private static func isUncertainMutationFailure(
        _ error: any Error
    ) -> Bool {
        guard let hermes = error as? HermesError else {
            return true
        }
        return hermes.isConnectionFailure || hermes.requestMayHaveSucceeded
    }
}

private struct StopRequest: Equatable, Sendable {
    let id: UUID
    let lifecycleGeneration: Int64
    let stopGeneration: Int64
    let liveSessionID: String
}
