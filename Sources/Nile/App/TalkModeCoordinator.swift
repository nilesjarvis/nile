import Foundation

@MainActor
final class TalkModeCoordinator {
    static let repeatedBlankResultsMessage =
        "I didn't catch anything three times. Tap to resume."
    static let relistenUnavailableMessage =
        "Talk paused because this conversation is not ready to listen."

    private let blankResultLimit: Int
    private var generation: Int64 = 0
    private var turnSequence: Int64 = 0
    private var relistenSequence: Int64 = 0
    private var consecutiveBlankResults = 0
    private var activeMode: TalkModeToken?
    private var activeTurn: TalkTurnToken?
    private var pendingRelisten: TalkRelistenToken?

    private(set) var state = TalkUIState()

    init(blankResultLimit: Int = 3) {
        precondition(blankResultLimit > 0)
        self.blankResultLimit = blankResultLimit
    }

    func begin(owner: TalkOwner) -> TalkModeToken {
        generation += 1
        let mode = TalkModeToken(
            generation: generation,
            owner: owner
        )
        activeMode = mode
        activeTurn = nil
        pendingRelisten = nil
        consecutiveBlankResults = 0
        state = TalkUIState(phase: .preparingInput)
        return mode
    }

    func markListening(_ mode: TalkModeToken) -> Bool {
        guard isCurrent(mode),
              pendingRelisten == nil,
              [.preparingInput, .listening].contains(state.phase) else {
            return false
        }
        state = TalkUIState(phase: .listening)
        return true
    }

    func observePartial(
        _ mode: TalkModeToken,
        text: String
    ) -> Bool {
        isCurrent(mode)
            && state.phase == .listening
            && pendingRelisten == nil
    }

    func markTranscribing(_ mode: TalkModeToken) -> Bool {
        guard isCurrent(mode),
              state.phase == .listening,
              pendingRelisten == nil else {
            return false
        }
        state = TalkUIState(phase: .transcribing)
        return true
    }

    func finishRecognition(
        _ mode: TalkModeToken,
        text: String
    ) -> TalkRecognitionDecision {
        guard isCurrent(mode),
              [.listening, .transcribing].contains(state.phase),
              pendingRelisten == nil else {
            return .ignored
        }
        let finalText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if finalText.isEmpty {
            consecutiveBlankResults += 1
            if consecutiveBlankResults >= blankResultLimit {
                pendingRelisten = nil
                state = TalkUIState(
                    phase: .paused,
                    message: Self.repeatedBlankResultsMessage
                )
                return .paused(
                    message: Self.repeatedBlankResultsMessage
                )
            }
            return .relisten(request: newRelistenRequest(mode))
        }

        consecutiveBlankResults = 0
        pendingRelisten = nil
        turnSequence += 1
        let turn = TalkTurnToken(
            mode: mode,
            sequence: turnSequence
        )
        activeTurn = turn
        state = TalkUIState(phase: .submitting)
        return .submit(turn: turn, text: finalText)
    }

    func markWorking(_ turn: TalkTurnToken) -> Bool {
        transitionTurn(
            turn,
            allowedPhases: [.submitting, .working],
            target: .working
        )
    }

    func markPreparingSpeech(_ turn: TalkTurnToken) -> Bool {
        transitionTurn(
            turn,
            allowedPhases: [
                .submitting,
                .working,
                .preparingSpeech,
            ],
            target: .preparingSpeech
        )
    }

    func markSpeaking(_ turn: TalkTurnToken) -> Bool {
        transitionTurn(
            turn,
            allowedPhases: [.preparingSpeech, .speaking],
            target: .speaking
        )
    }

    func requestRelistenAfterTurn(
        _ turn: TalkTurnToken
    ) -> TalkRelistenToken? {
        guard isCurrent(turn),
              [
                  .working,
                  .preparingSpeech,
                  .speaking,
              ].contains(state.phase) else {
            return nil
        }
        activeTurn = nil
        consecutiveBlankResults = 0
        state = TalkUIState(phase: .preparingInput)
        return newRelistenRequest(turn.mode)
    }

    func claimRelisten(
        _ request: TalkRelistenToken,
        currentOwner: TalkOwner?,
        canListen: Bool,
        unavailableMessage: String =
            TalkModeCoordinator.relistenUnavailableMessage
    ) -> TalkRelistenDecision {
        guard isCurrent(request) else {
            return .ignored
        }
        pendingRelisten = nil
        guard let mode = activeMode else {
            return .ignored
        }
        guard currentOwner == mode.owner else {
            invalidate()
            return .invalidated
        }
        guard canListen else {
            state = TalkUIState(
                phase: .paused,
                message: unavailableMessage
            )
            return .paused(message: unavailableMessage)
        }
        guard state.phase == .preparingInput else {
            return .ignored
        }
        state = TalkUIState(phase: .preparingInput)
        return .start(mode: mode)
    }

    func resume(
        _ mode: TalkModeToken,
        currentOwner: TalkOwner?,
        canListen: Bool,
        unavailableMessage: String =
            TalkModeCoordinator.relistenUnavailableMessage
    ) -> TalkRelistenDecision {
        guard isCurrent(mode), state.phase == .paused else {
            return .ignored
        }
        guard currentOwner == mode.owner else {
            invalidate()
            return .invalidated
        }
        guard canListen else {
            state = TalkUIState(
                phase: .paused,
                message: unavailableMessage
            )
            return .paused(message: unavailableMessage)
        }
        activeTurn = nil
        pendingRelisten = nil
        consecutiveBlankResults = 0
        state = TalkUIState(phase: .preparingInput)
        return .start(mode: mode)
    }

    func pause(
        _ mode: TalkModeToken,
        message: String
    ) -> Bool {
        guard isCurrent(mode) else {
            return false
        }
        activeTurn = nil
        pendingRelisten = nil
        consecutiveBlankResults = 0
        state = TalkUIState(phase: .paused, message: message)
        return true
    }

    func pauseTurn(
        _ turn: TalkTurnToken,
        message: String
    ) -> Bool {
        isCurrent(turn) && pause(turn.mode, message: message)
    }

    func end(_ mode: TalkModeToken) -> Bool {
        guard isCurrent(mode) else {
            return false
        }
        invalidate()
        return true
    }

    func invalidate() {
        generation += 1
        activeMode = nil
        activeTurn = nil
        pendingRelisten = nil
        consecutiveBlankResults = 0
        state = TalkUIState()
    }

    func invalidateIfOwnerChanged(
        currentOwner: TalkOwner?
    ) -> Bool {
        guard let mode = activeMode else {
            return false
        }
        guard mode.owner != currentOwner else {
            return false
        }
        invalidate()
        return true
    }

    func currentMode() -> TalkModeToken? { activeMode }
    func currentTurn() -> TalkTurnToken? { activeTurn }

    func isCurrent(_ mode: TalkModeToken) -> Bool {
        activeMode === mode && mode.generation == generation
    }

    func isCurrent(_ turn: TalkTurnToken) -> Bool {
        activeTurn === turn && isCurrent(turn.mode)
    }

    private func isCurrent(_ request: TalkRelistenToken) -> Bool {
        pendingRelisten === request && isCurrent(request.mode)
    }

    private func transitionTurn(
        _ turn: TalkTurnToken,
        allowedPhases: Set<TalkPhase>,
        target: TalkPhase
    ) -> Bool {
        guard isCurrent(turn),
              allowedPhases.contains(state.phase) else {
            return false
        }
        state = TalkUIState(phase: target)
        return true
    }

    private func newRelistenRequest(
        _ mode: TalkModeToken
    ) -> TalkRelistenToken {
        relistenSequence += 1
        let request = TalkRelistenToken(
            mode: mode,
            sequence: relistenSequence
        )
        pendingRelisten = request
        state = TalkUIState(phase: .preparingInput)
        return request
    }
}
