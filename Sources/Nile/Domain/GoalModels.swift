struct HermesGoal: Equatable, Sendable {
    let objective: String
    let phase: GoalPhase
    let turnsUsed: Int
    let maxTurns: Int
    let lastReason: String?
    let pausedReason: String?

    init(
        objective: String,
        phase: GoalPhase,
        turnsUsed: Int,
        maxTurns: Int,
        lastReason: String? = nil,
        pausedReason: String? = nil
    ) {
        self.objective = objective
        self.phase = phase
        self.turnsUsed = turnsUsed
        self.maxTurns = maxTurns
        self.lastReason = lastReason
        self.pausedReason = pausedReason
    }

    var isLoopAlive: Bool {
        phase == .active || phase == .checking || phase == .waiting
    }
}

enum GoalPhase: String, Codable, Sendable {
    case active
    case checking
    case waiting
    case paused
    case finished
}

struct GoalStart: Equatable, Sendable {
    let goal: HermesGoal
    let kickoffPrompt: String
    let notice: String
}

struct GoalProgressUpdate: Equatable, Sendable {
    let phase: GoalPhase?
    let turnsUsed: Int?
    let maxTurns: Int?
    let reason: String?

    init(
        phase: GoalPhase?,
        turnsUsed: Int? = nil,
        maxTurns: Int? = nil,
        reason: String? = nil
    ) {
        self.phase = phase
        self.turnsUsed = turnsUsed
        self.maxTurns = maxTurns
        self.reason = reason
    }
}

protocol HermesGoalStatusServing: Sendable {
    func goalStatus(liveSessionID: String) async throws -> HermesGoal?
}

protocol HermesGoalServing: HermesGoalStatusServing {
    func setGoal(
        liveSessionID: String,
        objective: String,
        maxTurns: Int?
    ) async throws -> GoalStart
    func pauseGoal(liveSessionID: String) async throws -> HermesGoal?
    func resumeGoal(liveSessionID: String) async throws -> HermesGoal?
    func clearGoal(liveSessionID: String) async throws
}

extension HermesGoalServing {
    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        throw HermesError(
            "Standing goals are unavailable for this repository",
            retryable: false
        )
    }

    func setGoal(
        liveSessionID: String,
        objective: String,
        maxTurns: Int?
    ) async throws -> GoalStart {
        throw HermesError(
            "Standing goals are unavailable for this repository",
            retryable: false
        )
    }

    func pauseGoal(liveSessionID: String) async throws -> HermesGoal? {
        throw HermesError(
            "Standing goals are unavailable for this repository",
            retryable: false
        )
    }

    func resumeGoal(liveSessionID: String) async throws -> HermesGoal? {
        throw HermesError(
            "Standing goals are unavailable for this repository",
            retryable: false
        )
    }

    func clearGoal(liveSessionID: String) async throws {
        throw HermesError(
            "Standing goals are unavailable for this repository",
            retryable: false
        )
    }
}
