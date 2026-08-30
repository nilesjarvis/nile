import Foundation

/// Owns session-directory capabilities and their refresh/reconciliation tasks.
///
/// `SessionListModel` supplies immutable owners and applies presentation
/// callbacks through its ordered event-application boundary. This runtime does
/// not consume the Hermes event stream.
@MainActor
final class SessionNavigationRuntime {
    struct GatewayOwner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String
    }

    struct DisplayOwner: Equatable, Sendable {
        let gatewayGeneration: Int
        let displayGeneration: Int
        let gatewayID: String
        let storedSessionID: String
        let liveSessionID: String?

        var gatewayOwner: GatewayOwner {
            GatewayOwner(
                gatewayGeneration: gatewayGeneration,
                gatewayID: gatewayID
            )
        }
    }

    struct DirectorySnapshot: Sendable {
        let sessions: [HermesSession]
        let activeStatuses: [String: String]
    }

    struct RefreshRequest: Sendable {
        let gatewayOwner: GatewayOwner
        let readOnlyDisplayOwner: DisplayOwner?
    }

    typealias RefreshRequestProvider = @MainActor @Sendable () ->
        RefreshRequest?
    typealias SessionsHandler = @MainActor @Sendable (
        GatewayOwner,
        [HermesSession]
    ) -> Void
    typealias StatusHandler = @MainActor @Sendable (
        [String: String]
    ) -> Void
    typealias StatusHandlerFactory = @MainActor @Sendable (
        GatewayOwner
    ) -> StatusHandler
    typealias HistoryHandler = @MainActor @Sendable (
        DisplayOwner,
        [HermesMessage]
    ) -> Void
    typealias DisplayHandler = @MainActor @Sendable (
        DisplayOwner,
        LiveSession
    ) -> Void

    struct RefreshSink: Sendable {
        let request: RefreshRequestProvider
        let sessions: SessionsHandler
        let prepareStatuses: StatusHandlerFactory
        let history: HistoryHandler
    }

    let repository: (any HermesSessionServing)?
    let refreshTicks: AsyncStream<Void>?
    var currentGatewayOwner: GatewayOwner?
    var refreshTask: Task<Void, Never>?
    var reconciliationTask: Task<Void, Never>?
    var reconciliationID: UUID?
    var attachedTurnRefreshTask: Task<Void, Never>?
    var attachedTurnRefreshID: UUID?

    init(
        repository: (any HermesSessionServing)?,
        refreshTicks: AsyncStream<Void>? = nil
    ) {
        self.repository = repository
        self.refreshTicks = refreshTicks
    }

    isolated deinit {
        refreshTask?.cancel()
        reconciliationTask?.cancel()
        attachedTurnRefreshTask?.cancel()
    }

    func resetGateway(owner: GatewayOwner) {
        cancelAllTasks()
        currentGatewayOwner = owner
    }

    func synchronizeGateway(owner: GatewayOwner) {
        cancelAllTasks()
        currentGatewayOwner = owner
    }

    func loadDirectory(owner: GatewayOwner) async throws
        -> DirectorySnapshot {
        let repository = try currentRepository(owner: owner)
        async let statuses = bestEffortActiveStatuses(repository)
        let sessions = try await repository.listSessions(limit: 50)
        let activeStatuses = await statuses
        try validate(owner)
        return DirectorySnapshot(
            sessions: sessions,
            activeStatuses: activeStatuses
        )
    }

    func listSessions(owner: GatewayOwner) async throws
        -> [HermesSession] {
        let repository = try currentRepository(owner: owner)
        let sessions = try await repository.listSessions(limit: 50)
        try validate(owner)
        return sessions
    }

    func readStoredSessionSource(
        storedSessionID: String,
        owner: GatewayOwner
    ) async throws -> String? {
        let repository = try currentRepository(owner: owner)
        let source = try await repository.readStoredSessionSource(
            storedSessionID: storedSessionID
        )
        try validate(owner)
        return source
    }

    func readStoredSession(
        storedSessionID: String,
        owner: GatewayOwner
    ) async throws -> [HermesMessage] {
        let repository = try currentRepository(owner: owner)
        let messages = try await repository.readStoredSession(
            storedSessionID: storedSessionID
        )
        try validate(owner)
        return messages
    }

    func openSession(
        storedSessionID: String,
        owner: GatewayOwner
    ) async throws -> LiveSession {
        let repository = try currentRepository(owner: owner)
        let session = try await repository.openSession(
            storedSessionID: storedSessionID
        )
        try validate(owner)
        return session
    }

    func liveRuntimeStatus(
        liveSessionID: String,
        owner: GatewayOwner
    ) async throws -> String? {
        let repository = try currentRepository(owner: owner)
        let status = try await repository.liveRuntimeStatus(
            liveSessionID: liveSessionID
        )
        try validate(owner)
        return status
    }

    func createSession(owner: GatewayOwner) async throws -> LiveSession {
        let repository = try currentRepository(owner: owner)
        let session = try await repository.createSession(title: nil)
        try validate(owner)
        return session
    }

    private func bestEffortActiveStatuses(
        _ repository: any HermesSessionServing
    ) async -> [String: String] {
        (try? await repository.activeSessionStatuses()) ?? [:]
    }

    private func currentRepository(owner: GatewayOwner) throws
        -> any HermesSessionServing {
        try validate(owner)
        guard let repository else {
            throw CancellationError()
        }
        return repository
    }

    private func validate(_ owner: GatewayOwner) throws {
        guard currentGatewayOwner == owner, !Task.isCancelled else {
            throw CancellationError()
        }
    }

}
