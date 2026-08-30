import Foundation
@testable import Nile

actor SessionRepositoryStub:
    SessionRepositoryCapabilityProviding,
    HermesEventStreaming,
    HermesDisconnectServing,
    HermesSessionServing,
    HermesTurnServing,
    HermesTalkServing,
    HermesDelegationServing,
    HermesBlockingPromptServing,
    HermesModelServing,
    HermesUsageServing,
    HermesAttachmentServing,
    HermesSpeechServing,
    HermesCommandServing,
    HermesGoalServing
{
    nonisolated let events: AsyncStream<HermesStreamEvent>

    nonisolated var sessionCapabilities: SessionRepositoryCapabilities {
        SessionRepositoryCapabilities(unified: self)
    }

    private var sessions: [HermesSession]
    private var statuses: [String: String]
    private var sources: [String: String?]
    private var histories: [String: [HermesMessage]]
    private var runtimeStatuses: [String: String]
    private var openedSessions: [LiveSession]
    private let listError: (any Error)?
    private let createAppearsInSessionList: Bool
    private let blockSourceLookup: Bool
    private let submitError: HermesError?
    private let steerAccepted: Bool
    private let steerError: HermesError?
    private let blockSubmit: Bool
    private let blockSteer: Bool
    private let blockInterrupt: Bool
    private let renameError: HermesError?
    private let blockRename: Bool
    private let blockClarificationResponse: Bool
    private let sudoResponseError: HermesError?
    private let attachError: HermesError?
    private let detachError: HermesError?
    private let detachResult: Bool
    private let attachmentPath: String
    private let downloadedAttachment: DownloadedAttachment?
    private let downloadError: HermesError?
    private let commandCatalogFixture: CommandCatalog?
    private let slashCompletionsFixture: SlashCompletions?
    private let commandExecutionFixture: CommandExecution?
    private let commandExecutionError: HermesError?
    private let modelOptionsFixture: ModelOptions?
    private var modelSwitchOutcomes: [ModelSwitchOutcome]
    private let modelSwitchError: HermesError?
    private let reasoningEffortFixture: String?
    private let reasoningEffortError: HermesError?
    private let blockModelSwitch: Bool
    private let submitStatus: PromptSubmitStatus
    private let synthesizedSpeech: SynthesizedSpeech?
    private var usageResponses: [SessionUsage]
    private var statsFixtures: [Int: GatewayStats]
    private var delegationStatusFixture: DelegationStatus
    private var delegationSnapshotInfos: [DelegationSnapshotInfo]
    private var delegationSnapshots: [String: DelegationSnapshot]
    private let subagentInterruptResult: SubagentInterruptResult
    private let subagentInterruptError: HermesError?
    private(set) var savedDelegationSnapshots: [DelegationSnapshot] = []
    private var shouldBlockFirstUsage: Bool
    private var usageContinuation: CheckedContinuation<Void, Never>?
    private let goalFeatureEnabled: Bool
    private var goalFixture: HermesGoal?
    private let blockGoalMutation: Bool
    private var goalMutationContinuation: CheckedContinuation<Void, Never>?
    private var sourceContinuation: CheckedContinuation<String?, Never>?
    private var submitContinuation: CheckedContinuation<Void, Never>?
    private var steerContinuation: CheckedContinuation<Void, Never>?
    private var interruptContinuation: CheckedContinuation<Void, Never>?
    private var renameContinuation: CheckedContinuation<Void, Never>?
    private var clarificationResponseContinuation:
        CheckedContinuation<Void, Never>?
    private var modelSwitchContinuation: CheckedContinuation<Void, Never>?
    private let eventContinuation: AsyncStream<HermesStreamEvent>.Continuation
    private(set) var calls: [String] = []

    init(
        sessions: [HermesSession],
        statuses: [String: String] = [:],
        sources: [String: String?] = [:],
        histories: [String: [HermesMessage]] = [:],
        runtimeStatuses: [String: String] = [:],
        openedSessions: [LiveSession] = [],
        blockSourceLookup: Bool = false,
        submitError: HermesError? = nil,
        steerAccepted: Bool = true,
        steerError: HermesError? = nil,
        blockSubmit: Bool = false,
        blockSteer: Bool = false,
        blockInterrupt: Bool = false,
        renameError: HermesError? = nil,
        blockRename: Bool = false,
        blockClarificationResponse: Bool = false,
        sudoResponseError: HermesError? = nil,
        attachError: HermesError? = nil,
        detachError: HermesError? = nil,
        detachResult: Bool = true,
        attachmentPath: String = "/tmp/hermes/photo.jpg",
        downloadedAttachment: DownloadedAttachment? = nil,
        downloadError: HermesError? = nil,
        commandCatalog: CommandCatalog? = nil,
        slashCompletions: SlashCompletions? = nil,
        commandExecution: CommandExecution? = nil,
        commandExecutionError: HermesError? = nil,
        modelOptions: ModelOptions? = nil,
        modelSwitchOutcomes: [ModelSwitchOutcome] = [],
        modelSwitchError: HermesError? = nil,
        reasoningEffort: String? = nil,
        reasoningEffortError: HermesError? = nil,
        blockModelSwitch: Bool = false,
        submitStatus: PromptSubmitStatus = .streaming,
        synthesizedSpeech: SynthesizedSpeech? = nil,
        usageResponses: [SessionUsage] = [],
        statsFixtures: [Int: GatewayStats] = [:],
        delegationStatus: DelegationStatus = DelegationStatus(
            active: [],
            paused: false,
            maxSpawnDepth: 3,
            maxConcurrentChildren: 4
        ),
        delegationSnapshotInfos: [DelegationSnapshotInfo] = [],
        delegationSnapshots: [String: DelegationSnapshot] = [:],
        subagentInterruptResult: SubagentInterruptResult =
            SubagentInterruptResult(found: true, subagentID: "agent-1"),
        subagentInterruptError: HermesError? = nil,
        blockFirstUsage: Bool = false,
        goalFeatureEnabled: Bool = false,
        goal: HermesGoal? = nil,
        blockGoalMutation: Bool = false,
        listError: (any Error)? = nil,
        createAppearsInSessionList: Bool = true
    ) {
        let pair = AsyncStream<HermesStreamEvent>.makeStream()
        events = pair.stream
        eventContinuation = pair.continuation
        self.sessions = sessions
        self.statuses = statuses
        self.sources = sources
        self.histories = histories
        self.runtimeStatuses = runtimeStatuses
        self.openedSessions = openedSessions
        self.blockSourceLookup = blockSourceLookup
        self.submitError = submitError
        self.steerAccepted = steerAccepted
        self.steerError = steerError
        self.blockSubmit = blockSubmit
        self.blockSteer = blockSteer
        self.blockInterrupt = blockInterrupt
        self.renameError = renameError
        self.blockRename = blockRename
        self.blockClarificationResponse = blockClarificationResponse
        self.sudoResponseError = sudoResponseError
        self.attachError = attachError
        self.detachError = detachError
        self.detachResult = detachResult
        self.attachmentPath = attachmentPath
        self.downloadedAttachment = downloadedAttachment
        self.downloadError = downloadError
        commandCatalogFixture = commandCatalog
        slashCompletionsFixture = slashCompletions
        commandExecutionFixture = commandExecution
        self.commandExecutionError = commandExecutionError
        modelOptionsFixture = modelOptions
        self.modelSwitchOutcomes = modelSwitchOutcomes
        self.modelSwitchError = modelSwitchError
        reasoningEffortFixture = reasoningEffort
        self.reasoningEffortError = reasoningEffortError
        self.blockModelSwitch = blockModelSwitch
        self.submitStatus = submitStatus
        self.synthesizedSpeech = synthesizedSpeech
        self.usageResponses = usageResponses
        self.statsFixtures = statsFixtures
        delegationStatusFixture = delegationStatus
        self.delegationSnapshotInfos = delegationSnapshotInfos
        self.delegationSnapshots = delegationSnapshots
        self.subagentInterruptResult = subagentInterruptResult
        self.subagentInterruptError = subagentInterruptError
        shouldBlockFirstUsage = blockFirstUsage
        self.goalFeatureEnabled = goalFeatureEnabled
        goalFixture = goal
        self.blockGoalMutation = blockGoalMutation
        self.listError = listError
        self.createAppearsInSessionList = createAppearsInSessionList
    }

    func connect(_ connection: GatewayConnection) async throws {}
    func disconnect() async {}

    func yield(_ event: HermesStreamEvent) {
        eventContinuation.yield(event)
    }

    func listSessions(limit: Int) async throws -> [HermesSession] {
        calls.append("session.list")
        if let listError {
            throw listError
        }
        return sessions
    }

    func replaceSessions(_ sessions: [HermesSession]) {
        self.sessions = sessions
    }

    func readStoredSessionSource(
        storedSessionID: String
    ) async throws -> String? {
        calls.append("source:\(storedSessionID)")
        if blockSourceLookup {
            return await withCheckedContinuation { continuation in
                sourceContinuation = continuation
            }
        }
        return sources[storedSessionID] ?? nil
    }

    func readStoredSession(
        storedSessionID: String
    ) async throws -> [HermesMessage] {
        calls.append("history:\(storedSessionID)")
        return histories[storedSessionID] ?? []
    }

    func openSession(storedSessionID: String) async throws -> LiveSession {
        calls.append("session.resume:\(storedSessionID)")
        if !openedSessions.isEmpty {
            return openedSessions.removeFirst()
        }
        return LiveSession(
            liveID: "live-\(storedSessionID)",
            storedID: storedSessionID,
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
    }

    func liveSessionStatus(storedSessionID: String) async throws -> String? {
        calls.append("session.status:\(storedSessionID)")
        return statuses[storedSessionID]
    }

    func liveRuntimeStatus(liveSessionID: String) async throws -> String? {
        calls.append("runtime.status:\(liveSessionID)")
        return runtimeStatuses[liveSessionID]
    }

    func activeSessionStatuses() async throws -> [String: String] {
        calls.append("session.active_list")
        return statuses
    }

    func createSession(title: String?) async throws -> LiveSession {
        calls.append("session.create")
        if createAppearsInSessionList,
           !sessions.contains(where: { $0.id == "new" }) {
            sessions.append(
                HermesSession(
                    id: "new",
                    title: "New session",
                    preview: nil,
                    source: "niles",
                    messageCount: 0,
                    startedAt: nil,
                    lastMessageAt: nil
                )
            )
        }
        return LiveSession(
            liveID: "live-new",
            storedID: "new",
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
    }

    func renameSession(liveSessionID: String, title: String) async throws {
        calls.append("session.title:\(liveSessionID):\(title)")
        if blockRename {
            await withCheckedContinuation { continuation in
                renameContinuation = continuation
            }
        }
        if let renameError {
            throw renameError
        }
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        calls.append("prompt.submit:\(liveSessionID):\(text)")
        if blockSubmit {
            await withCheckedContinuation { continuation in
                submitContinuation = continuation
            }
        }
        if let submitError {
            throw submitError
        }
        return submitStatus
    }

    func steer(liveSessionID: String, text: String) async throws -> Bool {
        calls.append("session.steer:\(liveSessionID):\(text)")
        if blockSteer {
            await withCheckedContinuation { continuation in
                steerContinuation = continuation
            }
        }
        if let steerError {
            throw steerError
        }
        return steerAccepted
    }

    func interrupt(liveSessionID: String) async throws {
        calls.append("session.interrupt:\(liveSessionID)")
        if blockInterrupt {
            await withCheckedContinuation { continuation in
                interruptContinuation = continuation
            }
        }
    }

    func respondToClarification(
        requestID: String,
        answer: String
    ) async throws {
        calls.append("clarify.respond:\(requestID):\(answer)")
        if blockClarificationResponse {
            await withCheckedContinuation { continuation in
                clarificationResponseContinuation = continuation
            }
        }
    }

    func respondToSudo(
        requestID: String,
        password: String
    ) async throws {
        calls.append("sudo.respond:\(requestID)")
        if let sudoResponseError {
            throw sudoResponseError
        }
    }

    func respondToSecret(
        requestID: String,
        value: String
    ) async throws {
        calls.append("secret.respond:\(requestID)")
    }

    func respondToApproval(
        liveSessionID: String,
        choice: ApprovalChoice
    ) async throws -> Bool {
        calls.append("approval.respond:\(liveSessionID):\(choice.rawValue)")
        return true
    }

    func attachImage(
        liveSessionID: String,
        base64: String,
        fileExtension: String,
        filename: String
    ) async throws -> AttachedImage {
        calls.append(
            "image.attach_bytes:\(liveSessionID):\(fileExtension):\(filename)"
        )
        if let attachError {
            throw attachError
        }
        return AttachedImage(path: attachmentPath, filename: filename)
    }

    func detachImage(
        liveSessionID: String,
        path: String
    ) async throws -> Bool {
        calls.append("image.detach:\(liveSessionID):\(path)")
        if let detachError {
            throw detachError
        }
        return detachResult
    }

    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async throws -> DownloadedAttachment {
        calls.append("attachment.download:\(path):\(maxBytes)")
        if let downloadError {
            throw downloadError
        }
        if let downloadedAttachment {
            return downloadedAttachment
        }
        throw HermesError(
            "No download fixture",
            retryable: false
        )
    }

    func synthesizeSpeech(text: String) async throws -> SynthesizedSpeech {
        calls.append("speech.synthesize:\(text)")
        guard let synthesizedSpeech else {
            throw SpeechSynthesisUnavailableError()
        }
        return synthesizedSpeech
    }

    func commandsCatalog() async throws -> CommandCatalog {
        guard let commandCatalogFixture else {
            throw HermesError(
                "No command catalog fixture",
                retryable: false
            )
        }
        calls.append("commands.catalog")
        return commandCatalogFixture
    }

    func completeSlash(text: String) async throws -> SlashCompletions {
        guard let slashCompletionsFixture else {
            throw HermesError(
                "No slash completion fixture",
                retryable: false
            )
        }
        calls.append("complete.slash:\(text)")
        return slashCompletionsFixture
    }

    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution {
        calls.append(
            "\(route == .slashExec ? "slash.exec" : "command.dispatch"):\(liveSessionID):\(command)"
        )
        if let commandExecutionError {
            throw commandExecutionError
        }
        guard let commandExecutionFixture else {
            throw HermesError(
                "No command execution fixture",
                retryable: false
            )
        }
        return commandExecutionFixture
    }

    func modelOptions(
        liveSessionID: String?,
        refresh: Bool
    ) async throws -> ModelOptions {
        guard let modelOptionsFixture else {
            throw HermesError("No model options fixture", retryable: false)
        }
        calls.append(
            "model.options:\(liveSessionID ?? ""):\(refresh)"
        )
        return modelOptionsFixture
    }

    func setSessionModel(
        liveSessionID: String,
        model: String,
        provider: String?,
        confirmExpensiveModel: Bool
    ) async throws -> ModelSwitchOutcome {
        calls.append(
            "config.set.model:\(liveSessionID):\(provider ?? ""):\(model):\(confirmExpensiveModel)"
        )
        if blockModelSwitch {
            await withCheckedContinuation { continuation in
                modelSwitchContinuation = continuation
            }
        }
        if let modelSwitchError {
            throw modelSwitchError
        }
        guard !modelSwitchOutcomes.isEmpty else {
            throw HermesError("No model switch fixture", retryable: false)
        }
        return modelSwitchOutcomes.removeFirst()
    }

    func setReasoningEffort(
        liveSessionID: String,
        effort: String
    ) async throws -> String {
        calls.append(
            "config.set.reasoning:\(liveSessionID):\(effort)"
        )
        if let reasoningEffortError {
            throw reasoningEffortError
        }
        guard let reasoningEffortFixture else {
            throw HermesError("No reasoning fixture", retryable: false)
        }
        return reasoningEffortFixture
    }

    func sessionUsage(liveSessionID: String) async throws -> SessionUsage {
        calls.append("session.usage:\(liveSessionID)")
        guard !usageResponses.isEmpty else {
            throw HermesError("No usage fixture", retryable: false)
        }
        let response = usageResponses.removeFirst()
        if shouldBlockFirstUsage {
            shouldBlockFirstUsage = false
            await withCheckedContinuation { continuation in
                usageContinuation = continuation
            }
        }
        return response
    }

    func gatewayStats(days: Int) async throws -> GatewayStats {
        calls.append("gateway.stats:\(days)")
        guard let fixture = statsFixtures[days] else {
            throw HermesError("No stats fixture", retryable: false)
        }
        return fixture
    }

    func delegationStatus() async throws -> DelegationStatus {
        calls.append("delegation.status")
        return delegationStatusFixture
    }

    func interruptSubagent(
        subagentID: String
    ) async throws -> SubagentInterruptResult {
        calls.append("subagent.interrupt:\(subagentID)")
        if let subagentInterruptError {
            throw subagentInterruptError
        }
        return SubagentInterruptResult(
            found: subagentInterruptResult.found,
            subagentID: subagentID
        )
    }

    func saveDelegationSnapshot(
        _ snapshot: DelegationSnapshot
    ) async throws -> String {
        calls.append(
            "spawn_tree.save:\(snapshot.storedSessionID):\(snapshot.agents.count)"
        )
        savedDelegationSnapshots.append(snapshot)
        return "/snapshot-\(savedDelegationSnapshots.count)"
    }

    func listDelegationSnapshots(
        storedSessionID: String,
        limit: Int
    ) async throws -> [DelegationSnapshotInfo] {
        calls.append("spawn_tree.list:\(storedSessionID):\(limit)")
        return Array(delegationSnapshotInfos.prefix(limit))
    }

    func loadDelegationSnapshot(
        path: String
    ) async throws -> DelegationSnapshot {
        calls.append("spawn_tree.load:\(path)")
        guard let snapshot = delegationSnapshots[path] else {
            throw HermesError("No delegation snapshot fixture", retryable: false)
        }
        return snapshot
    }

    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        guard goalFeatureEnabled else {
            throw HermesError(
                "Standing goals unavailable",
                retryable: false
            )
        }
        calls.append("goal.status:\(liveSessionID)")
        return goalFixture
    }

    func setGoal(
        liveSessionID: String,
        objective: String,
        maxTurns: Int?
    ) async throws -> GoalStart {
        guard goalFeatureEnabled else {
            throw HermesError(
                "Standing goals unavailable",
                retryable: false
            )
        }
        calls.append(
            "goal.set:\(liveSessionID):\(objective):\(maxTurns.map(String.init) ?? "default")"
        )
        if blockGoalMutation {
            await withCheckedContinuation { continuation in
                goalMutationContinuation = continuation
            }
        }
        let goal = HermesGoal(
            objective: objective,
            phase: .active,
            turnsUsed: 0,
            maxTurns: maxTurns ?? 20
        )
        goalFixture = goal
        return GoalStart(
            goal: goal,
            kickoffPrompt: objective,
            notice:
                "⊙ Goal set (\(goal.maxTurns)-turn budget): \(objective)"
        )
    }

    func pauseGoal(liveSessionID: String) async throws -> HermesGoal? {
        calls.append("goal.pause:\(liveSessionID)")
        if let goalFixture {
            self.goalFixture = HermesGoal(
                objective: goalFixture.objective,
                phase: .paused,
                turnsUsed: goalFixture.turnsUsed,
                maxTurns: goalFixture.maxTurns,
                lastReason: goalFixture.lastReason,
                pausedReason: "user-paused"
            )
        }
        return goalFixture
    }

    func resumeGoal(liveSessionID: String) async throws -> HermesGoal? {
        calls.append("goal.resume:\(liveSessionID)")
        if let goalFixture {
            self.goalFixture = HermesGoal(
                objective: goalFixture.objective,
                phase: .active,
                turnsUsed: goalFixture.turnsUsed,
                maxTurns: goalFixture.maxTurns,
                lastReason: goalFixture.lastReason,
                pausedReason: goalFixture.pausedReason
            )
        }
        return goalFixture
    }

    func clearGoal(liveSessionID: String) async throws {
        calls.append("goal.clear:\(liveSessionID)")
        goalFixture = nil
    }

    func releaseSubmit() {
        submitContinuation?.resume()
        submitContinuation = nil
    }

    func releaseSteer() {
        steerContinuation?.resume()
        steerContinuation = nil
    }

    func releaseInterrupt() {
        interruptContinuation?.resume()
        interruptContinuation = nil
    }

    func releaseRename() {
        renameContinuation?.resume()
        renameContinuation = nil
    }

    func releaseClarificationResponse() {
        clarificationResponseContinuation?.resume()
        clarificationResponseContinuation = nil
    }

    func releaseModelSwitch() {
        modelSwitchContinuation?.resume()
        modelSwitchContinuation = nil
    }

    func releaseGoalMutation() {
        goalMutationContinuation?.resume()
        goalMutationContinuation = nil
    }

    func releaseUsage() {
        usageContinuation?.resume()
        usageContinuation = nil
    }

    func setHistory(_ messages: [HermesMessage], for storedSessionID: String) {
        histories[storedSessionID] = messages
    }

    func setSessions(_ sessions: [HermesSession]) {
        self.sessions = sessions
    }

    func setStatuses(_ statuses: [String: String]) {
        self.statuses = statuses
    }

    func resolveBlockedSource(_ source: String?) {
        sourceContinuation?.resume(returning: source)
        sourceContinuation = nil
    }

    func callCount(_ call: String) -> Int {
        calls.filter { $0 == call }.count
    }
}
