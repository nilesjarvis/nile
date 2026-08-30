import Foundation

/// Owns Talk prompt admission, transport, and response/event correlation.
@MainActor
final class TalkSubmissionRuntime {
    typealias TurnPredicate =
        @MainActor @Sendable (TalkTurnToken) -> Bool
    typealias TurnHandler =
        @MainActor @Sendable (TalkTurnToken) -> Void
    typealias PauseHandler =
        @MainActor @Sendable (TalkTurnToken, String) -> Void

    private let repository: (any HermesTalkServing)?
    private var task: Task<Void, Never>?
    private var generation: Int64 = 0
    private var acknowledgedTurn: TalkTurnToken?
    private var unacknowledgedTurn: TalkTurnToken?
    private var uncorrelatedTerminal: TalkTurnToken?

    init(repository: (any HermesTalkServing)?) {
        self.repository = repository
    }

    isolated deinit {
        task?.cancel()
    }

    func submit(
        _ turn: TalkTurnToken,
        input: String,
        environmentProvider: @escaping TalkEnvironmentProvider,
        onSubmissionStarted: @escaping TalkSubmissionHandler,
        onSubmissionFailed: @escaping TalkSubmissionFailureHandler,
        isCurrent: @escaping TurnPredicate,
        onWorking: @escaping TurnHandler,
        onPause: @escaping PauseHandler
    ) {
        let owner = turn.mode.owner
        let repository = repository
        generation &+= 1
        let taskGeneration = generation
        task?.cancel()
        task = Task { [weak self] in
            guard let self else {
                return
            }
            var submittedEntryID: String?
            defer {
                if generation == taskGeneration {
                    task = nil
                }
            }
            do {
                let remoteStatus = try await repository?.liveRuntimeStatus(
                    liveSessionID: owner.liveSessionID
                )
                guard isCurrent(turn) else {
                    return
                }
                let environment = environmentProvider()
                guard TalkSubmissionPolicy.canSubmit(
                    remoteStatus: remoteStatus,
                    expectedOwner: owner,
                    currentOwner: environment.owner,
                    canListen: environment.canListen
                ) else {
                    onPause(
                        turn,
                        "Talk paused because another turn became active before the utterance was sent."
                    )
                    return
                }

                let entryID = "talk-user-\(UUID().uuidString)"
                submittedEntryID = entryID
                unacknowledgedTurn = turn
                uncorrelatedTerminal = nil
                onSubmissionStarted(
                    TalkSubmission(
                        owner: owner,
                        entryID: entryID,
                        text: input
                    )
                )

                let status = try await repository?.submitPrompt(
                    liveSessionID: owner.liveSessionID,
                    text: input
                ) ?? .streaming
                guard unacknowledgedTurn === turn else {
                    return
                }
                let terminalArrived = uncorrelatedTerminal === turn
                unacknowledgedTurn = nil
                uncorrelatedTerminal = nil
                switch TalkSubmissionPolicy.settlement(
                    for: status,
                    terminalArrivedBeforeAcknowledgement: terminalArrived
                ) {
                case .acknowledged:
                    guard isCurrent(turn),
                          environmentProvider().owner == owner else {
                        return
                    }
                    acknowledgedTurn = turn
                    onWorking(turn)
                case let .paused(message):
                    onPause(turn, message)
                }
            } catch is CancellationError {
                settleFailure(
                    turn,
                    submittedEntryID: submittedEntryID,
                    disposition: TalkSubmissionPolicy.uncertainFailure,
                    onSubmissionFailed: onSubmissionFailed,
                    isCurrent: isCurrent,
                    onPause: onPause
                )
            } catch {
                settleFailure(
                    turn,
                    submittedEntryID: submittedEntryID,
                    disposition: TalkSubmissionPolicy.failure(for: error),
                    onSubmissionFailed: onSubmissionFailed,
                    isCurrent: isCurrent,
                    onPause: onPause
                )
            }
        }
    }

    func noteTerminalBeforeAcknowledgement(liveSessionID: String) {
        guard let pending = unacknowledgedTurn,
              pending.mode.owner.liveSessionID == liveSessionID else {
            return
        }
        uncorrelatedTerminal = pending
    }

    func takeAcknowledgement(for turn: TalkTurnToken) -> Bool {
        guard acknowledgedTurn === turn else {
            return false
        }
        acknowledgedTurn = nil
        return true
    }

    func hasUncorrelatedTerminal(for turn: TalkTurnToken) -> Bool {
        uncorrelatedTerminal === turn
    }

    func clearAcknowledgement(for turn: TalkTurnToken? = nil) {
        guard let turn else {
            acknowledgedTurn = nil
            return
        }
        if acknowledgedTurn === turn {
            acknowledgedTurn = nil
        }
    }

    func resetCorrelation() {
        acknowledgedTurn = nil
        unacknowledgedTurn = nil
        uncorrelatedTerminal = nil
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        resetCorrelation()
    }

    private func settleFailure(
        _ turn: TalkTurnToken,
        submittedEntryID: String?,
        disposition: TalkSubmissionFailureDisposition,
        onSubmissionFailed: TalkSubmissionFailureHandler,
        isCurrent: TurnPredicate,
        onPause: PauseHandler
    ) {
        guard unacknowledgedTurn === turn || isCurrent(turn) else {
            return
        }
        unacknowledgedTurn = nil
        uncorrelatedTerminal = nil
        onSubmissionFailed(
            TalkSubmissionFailure(
                owner: turn.mode.owner,
                entryID: submittedEntryID,
                uncertain: disposition.uncertain,
                message: disposition.message
            )
        )
        onPause(turn, disposition.message)
    }
}
