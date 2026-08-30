enum GoalAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable
}

struct GoalRuntimeOwner: Equatable, Sendable {
    let gatewayGeneration: Int
    let displayGeneration: Int
    let gatewayID: String
    let storedSessionID: String
    let liveSessionID: String
}

struct GoalActionContext: Sendable {
    let owner: GoalRuntimeOwner?
    let isUpdatingSessionControls: Bool
    let isSending: Bool
    let isStopping: Bool
    let hasPendingAttachments: Bool
    let isAttaching: Bool
}

struct GoalSynchronization: Sendable {
    let goal: HermesGoal?
}

typealias GoalPromptHandler = @MainActor @Sendable (
    GoalRuntimeOwner,
    String
) -> Void
typealias GoalSynchronizationHandler = @MainActor @Sendable (
    HermesGoal?
) -> Void

extension SessionGoalRuntime {
    typealias Owner = GoalRuntimeOwner
    typealias ActionContext = GoalActionContext
    typealias Synchronization = GoalSynchronization
    typealias PromptHandler = GoalPromptHandler
    typealias SynchronizationHandler = GoalSynchronizationHandler
}
