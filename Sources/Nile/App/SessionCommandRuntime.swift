import Foundation
import Observation

@MainActor
@Observable
final class SessionCommandRuntime {
    struct CompletionOwner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String?
    }

    struct ExecutionOwner: Hashable, Sendable {
        let gatewayID: String
        let storedSessionID: String
    }

    enum ExecutionOutcome: Equatable, Sendable {
        case preparationFailed
        case completed(CommandExecution)
        case failed(message: String, uncertain: Bool)
        case cancelled
    }

    typealias Preparation = @MainActor @Sendable () async -> Bool
    typealias OutcomeHandler = @MainActor @Sendable (
        ExecutionOutcome
    ) async -> Void

    var catalog: CommandCatalog?
    var completions: [SlashCompletion] = []
    var replaceFrom = 1

    private let repository: (any HermesCommandServing)?
    private let completionDebounce: Duration
    private let executionLifecycle = SessionCommandExecutionLifecycle()
    private var extensionNames: Set<String> = []
    private var blockedNames: Set<String> = []
    private var completionTask: Task<Void, Never>?
    private var completionGeneration: Int64 = 0
    private var currentCompletionRequest: CompletionRequest?

    init(
        repository: (any HermesCommandServing)?,
        completionDebounce: Duration = .milliseconds(120)
    ) {
        self.repository = repository
        self.completionDebounce = completionDebounce
    }

    isolated deinit {
        completionTask?.cancel()
    }

    var hasRepository: Bool {
        repository != nil
    }

    func fetchCatalog() async -> CommandCatalog? {
        guard let repository else {
            return nil
        }
        return try? await repository.commandsCatalog()
    }

    func applyCatalog(_ catalog: CommandCatalog?) {
        guard let catalog else {
            self.catalog = nil
            extensionNames = []
            blockedNames = []
            return
        }
        let curated = NileSlashCatalogPolicy.curateCatalog(catalog)
        self.catalog = curated.catalog
        extensionNames = curated.extensionNames
        blockedNames = curated.blockedNames
    }

    func decision(for input: String) -> NileSlashDecision {
        NileSlashPolicy.decide(
            input,
            extensionNames: extensionNames,
            blockedNames: blockedNames
        )
    }

    func refreshCompletions(
        query: String,
        owner: CompletionOwner
    ) {
        completionTask?.cancel()
        completionTask = nil
        completionGeneration &+= 1
        guard query.hasPrefix("/"),
              !query.contains("\n"),
              let repository else {
            resetCompletions()
            return
        }
        let request = CompletionRequest(
            generation: completionGeneration,
            owner: owner,
            query: query
        )
        currentCompletionRequest = request
        let debounce = completionDebounce
        let policyExtensionNames = extensionNames
        let policyBlockedNames = blockedNames
        completionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                let response = try await repository.completeSlash(text: query)
                try Task.checkCancellation()
                guard let self,
                      self.currentCompletionRequest == request else {
                    return
                }
                let curated = NileSlashCatalogPolicy.filterCompletions(
                    query: query,
                    completions: response,
                    extensionNames: policyExtensionNames,
                    blockedNames: policyBlockedNames
                )
                self.completions = curated.items
                self.replaceFrom = curated.replaceFrom
                self.completionTask = nil
            } catch {
                guard let self,
                      self.currentCompletionRequest == request else {
                    return
                }
                self.completionTask = nil
            }
        }
    }

    func resetCompletions() {
        completionTask?.cancel()
        completionTask = nil
        completionGeneration &+= 1
        currentCompletionRequest = nil
        completions = []
        replaceFrom = 1
    }

    func resetGateway() {
        resetCompletions()
        catalog = nil
        extensionNames = []
        blockedNames = []
        executionLifecycle.cancelAll()
    }

    func isExecuting(owner: ExecutionOwner) -> Bool {
        executionLifecycle.isExecuting(owner: owner)
    }

    @discardableResult
    func startExecution(
        owner: ExecutionOwner,
        liveSessionID: String,
        input: String,
        prepare: @escaping Preparation,
        onOutcome: @escaping OutcomeHandler
    ) -> Bool {
        guard let repository else {
            return false
        }
        return executionLifecycle.start(
            repository: repository,
            owner: owner,
            liveSessionID: liveSessionID,
            input: input,
            extensionNames: extensionNames,
            blockedNames: blockedNames,
            prepare: prepare,
            onOutcome: onOutcome
        )
    }
}

private struct CompletionRequest: Equatable, Sendable {
    let generation: Int64
    let owner: SessionCommandRuntime.CompletionOwner
    let query: String
}
