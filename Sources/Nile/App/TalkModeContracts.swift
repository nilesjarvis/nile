import Foundation

enum TalkPhase: Equatable, Sendable {
    case off
    case preparingInput
    case listening
    case transcribing
    case submitting
    case working
    case preparingSpeech
    case speaking
    case paused
}

struct TalkUIState: Equatable, Sendable {
    var phase: TalkPhase = .off
    var message: String?

    var isActive: Bool { phase != .off }
}

struct TalkOwner: Equatable, Sendable {
    let connectionGeneration: Int64
    let gatewayID: String
    let gatewayKey: String
    let selectedSessionID: String
    let transcriptSessionID: String
    let liveSessionID: String

    init(
        connectionGeneration: Int64,
        gatewayID: String,
        gatewayKey: String,
        selectedSessionID: String,
        transcriptSessionID: String,
        liveSessionID: String
    ) {
        precondition(connectionGeneration >= 0)
        precondition(!gatewayID.isBlank)
        precondition(!gatewayKey.isBlank)
        precondition(!selectedSessionID.isBlank)
        precondition(!transcriptSessionID.isBlank)
        precondition(!liveSessionID.isBlank)
        precondition(selectedSessionID == transcriptSessionID)
        self.connectionGeneration = connectionGeneration
        self.gatewayID = gatewayID
        self.gatewayKey = gatewayKey
        self.selectedSessionID = selectedSessionID
        self.transcriptSessionID = transcriptSessionID
        self.liveSessionID = liveSessionID
    }
}

final class TalkModeToken {
    let generation: Int64
    let owner: TalkOwner

    init(generation: Int64, owner: TalkOwner) {
        self.generation = generation
        self.owner = owner
    }
}

final class TalkTurnToken {
    let mode: TalkModeToken
    let sequence: Int64

    init(mode: TalkModeToken, sequence: Int64) {
        self.mode = mode
        self.sequence = sequence
    }
}

final class TalkRelistenToken {
    let mode: TalkModeToken
    let sequence: Int64

    init(mode: TalkModeToken, sequence: Int64) {
        self.mode = mode
        self.sequence = sequence
    }
}

enum TalkRecognitionDecision {
    case ignored
    case submit(turn: TalkTurnToken, text: String)
    case relisten(request: TalkRelistenToken)
    case paused(message: String)
}

enum TalkRelistenDecision {
    case ignored
    case invalidated
    case start(mode: TalkModeToken)
    case paused(message: String)
}
