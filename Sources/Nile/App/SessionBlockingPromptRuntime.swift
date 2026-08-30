import Foundation

/// Owns blocking-input coordination and projection.
///
/// `SessionEventRuntime` owns the sole ordered stream. `SessionListModel`
/// synchronously forwards structural events here from its one application
/// boundary, then retains transcript and session-list presentation. Response
/// values are delegated to a task-local response lifecycle and are never copied
/// into observable or persistent runtime state.
@MainActor
final class SessionBlockingPromptRuntime {
    typealias TargetValidator = @MainActor @Sendable
        (BlockingPromptResponseTarget) -> Bool
    typealias ChangeHandler = @MainActor @Sendable () -> Void
    typealias ErrorHandler = @MainActor @Sendable
        (BlockingPromptResponseTarget, any Error) -> Void

    private let coordinator: BlockingPromptCoordinator
    private let responseLifecycle: SessionBlockingPromptResponseLifecycle

    init(
        repository: (any HermesBlockingPromptServing)?,
        monotonicMilliseconds: @escaping () -> Int64 = {
            Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        }
    ) {
        let coordinator = BlockingPromptCoordinator(
            monotonicMilliseconds: monotonicMilliseconds
        )
        self.coordinator = coordinator
        responseLifecycle = SessionBlockingPromptResponseLifecycle(
            repository: repository,
            coordinator: coordinator
        )
    }

    func handleEvent(
        _ event: HermesStreamEvent,
        gatewayID: String?,
        fallbackStoredSessionID: String?
    ) -> BlockingPromptEventResult {
        coordinator.handleEvent(
            event,
            gatewayID: gatewayID,
            fallbackStoredSessionID: fallbackStoredSessionID
        )
    }

    func responseTarget(promptID: String) -> BlockingPromptResponseTarget? {
        coordinator.responseTarget(promptID: promptID)
    }

    @discardableResult
    func respond(
        promptID: String,
        response: String,
        isCurrentTarget: @escaping TargetValidator,
        onChanged: @escaping ChangeHandler,
        onError: @escaping ErrorHandler
    ) -> Bool {
        responseLifecycle.respond(
            promptID: promptID,
            response: response,
            isCurrentTarget: isCurrentTarget,
            onChanged: onChanged,
            onError: onError
        )
    }

    func bindSession(
        gatewayID: String,
        liveSessionID: String,
        storedSessionID: String?,
        turnInFlight: Bool
    ) {
        coordinator.bindSession(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            storedSessionID: storedSessionID,
            turnInFlight: turnInFlight
        )
    }

    func finalizeRuntime(
        gatewayID: String,
        liveSessionID: String,
        message: String
    ) {
        coordinator.finalizeRuntime(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            message: message
        )
    }

    func finalizeGateway(gatewayID: String, message: String) {
        coordinator.finalizeGateway(gatewayID: gatewayID, message: message)
    }

    @discardableResult
    func markSubmittingUncertain(gatewayID: String?) -> Bool {
        coordinator.markSubmittingUncertain(gatewayID: gatewayID)
    }

    func beginStatusPoll() -> BlockingPromptStatusPollToken {
        coordinator.beginStatusPoll()
    }

    @discardableResult
    func reconcileStatusPoll(
        token: BlockingPromptStatusPollToken,
        gatewayID: String?,
        currentGatewayID: String?,
        statuses: [String: String]
    ) -> Bool {
        coordinator.reconcileStatusPoll(
            token: token,
            gatewayID: gatewayID,
            currentGatewayID: currentGatewayID,
            statuses: statuses
        )
    }

    func project(
        gatewayID: String?,
        liveSessionID: String?,
        storedSessionID: String?,
        transcript: [TranscriptEntry]
    ) -> (
        transcript: [TranscriptEntry],
        sessionsNeedingInput: Set<String>
    ) {
        coordinator.refreshPresentation(gatewayID: gatewayID)
        return coordinator.project(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            storedSessionID: storedSessionID,
            transcript: transcript
        )
    }

    func reset() {
        responseLifecycle.reset()
        coordinator.clearRuntimeRecords()
    }
}
