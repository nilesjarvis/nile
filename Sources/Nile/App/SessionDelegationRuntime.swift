import Foundation
import Observation

@MainActor
@Observable
final class SessionDelegationRuntime {
    typealias ProjectionHandler = @MainActor @Sendable () -> Void

    var turns: [DelegationTurnUI] = []
    var pinnedTurnID: String?
    var isReconciling = false
    var controlError: String?

    let repository: (any HermesDelegationServing)?
    var coordinator = DelegationCoordinator()
    var tasks: [UUID: Task<Void, Never>] = [:]
    var lifecycleGeneration: Int64 = 0
    var activeGatewayID: String?

    init(repository: (any HermesDelegationServing)?) {
        self.repository = repository
    }

    isolated deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func reset() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        lifecycleGeneration &+= 1
        activeGatewayID = nil
        coordinator.clear()
        turns = []
        pinnedTurnID = nil
        isReconciling = false
        controlError = nil
    }

    func project(
        gatewayID: String?,
        storedSessionID: String?,
        transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        let projection = coordinator.projection(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            transcript: transcript
        )
        turns = projection.turns
        pinnedTurnID = projection.pinnedTurnID
        return projection.transcript
    }

    func bindLiveSession(
        owner: DelegationOwner,
        liveSessionID: String
    ) {
        guard activateGateway(owner.gatewayID) else {
            return
        }
        coordinator.bindLiveSession(
            owner: owner,
            liveSessionID: liveSessionID
        )
    }

    func handleEvent(
        gatewayID: String?,
        visibleStoredSessionID: String?,
        visibleLiveSessionID: String?,
        liveSessionID: String,
        kind: SubagentEventKind,
        data: SubagentEventData,
        onProjection: @escaping ProjectionHandler
    ) {
        guard let owner = coordinator.ownerForLive(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            visibleLiveSessionID: visibleLiveSessionID,
            visibleStoredSessionID: visibleStoredSessionID
        ), activateGateway(owner.gatewayID) else {
            return
        }
        let snapshot = coordinator.applyEvent(
            owner: owner,
            data: data,
            kind: kind
        )
        onProjection()
        persist(snapshot, owner: owner)
    }

    func markParentCompleted(
        gatewayID: String?,
        visibleStoredSessionID: String?,
        visibleLiveSessionID: String?,
        liveSessionID: String,
        onProjection: @escaping ProjectionHandler
    ) {
        guard let owner = coordinator.ownerForLive(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            visibleLiveSessionID: visibleLiveSessionID,
            visibleStoredSessionID: visibleStoredSessionID
        ), activateGateway(owner.gatewayID) else {
            return
        }
        let snapshot = coordinator.markParentCompleted(owner: owner)
        onProjection()
        persist(snapshot, owner: owner)
    }

    func activateGateway(_ gatewayID: String) -> Bool {
        if activeGatewayID == nil {
            activeGatewayID = gatewayID
        }
        return activeGatewayID == gatewayID
    }

    func isCurrent(
        lifecycle: Int64,
        gatewayID: String
    ) -> Bool {
        lifecycle == lifecycleGeneration && activeGatewayID == gatewayID
    }

}
