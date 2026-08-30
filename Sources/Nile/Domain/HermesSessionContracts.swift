struct HermesSession: Equatable, Sendable, Identifiable {
    let id: String
    let title: String?
    let preview: String?
    let source: String?
    let messageCount: Int
    let startedAt: Double?
    let lastMessageAt: Double?
}

struct SessionInfo: Equatable, Sendable {
    let model: String?
    let provider: String?
    let reasoningEffort: String?
    let reasoningEffortSessionScopeSupported: Bool
    let isLazy: Bool

    init(
        model: String?,
        provider: String?,
        reasoningEffort: String? = nil,
        reasoningEffortSessionScopeSupported: Bool = false,
        isLazy: Bool = false
    ) {
        self.model = model
        self.provider = provider
        self.reasoningEffort = reasoningEffort
        self.reasoningEffortSessionScopeSupported = reasoningEffortSessionScopeSupported
        self.isLazy = isLazy
    }
}

struct InflightTurn: Equatable, Sendable {
    let user: String
    let assistant: String
}

struct LiveSession: Equatable, Sendable {
    let liveID: String
    let storedID: String?
    let info: SessionInfo
    let messages: [HermesMessage]
    let running: Bool
    let status: String?
    let inflight: InflightTurn?

    var turnInFlight: Bool {
        running && (
            status == nil
                || status == "working"
                || status == "waiting"
                || status == "starting"
        )
    }
}

struct TodoItem: Equatable, Sendable {
    let content: String
    let status: String
}

enum ToolCompletionOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case interrupted
    case unknown
}

struct HermesMessage: Equatable, Sendable {
    let role: String
    let text: String
    let toolName: String?
    let toolContext: String?
    let toolOutcome: ToolCompletionOutcome

    init(
        role: String,
        text: String,
        toolName: String? = nil,
        toolContext: String? = nil,
        toolOutcome: ToolCompletionOutcome = .unknown
    ) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolContext = toolContext
        self.toolOutcome = toolOutcome
    }
}

enum ApprovalChoice: String, CaseIterable, Codable, Sendable {
    case once
    case session
    case always
    case deny
}

struct SecretRequestMetadata: Equatable, Sendable {
    let skillName: String?
    let help: String?
    let requiredFor: String?
}

enum PromptSubmitStatus: String, Codable, Sendable {
    case streaming
    case queued
    case steered
}

protocol HermesSessionClaimServing: Sendable {
    func openSession(storedSessionID: String) async throws -> LiveSession
    func liveSessionStatus(storedSessionID: String) async throws -> String?
}

protocol HermesSessionRenaming: Sendable {
    func renameSession(liveSessionID: String, title: String) async throws
}

protocol HermesLiveRuntimeStatusServing: Sendable {
    func liveRuntimeStatus(liveSessionID: String) async throws -> String?
}

protocol HermesSessionServing:
    HermesSessionClaimServing,
    HermesSessionRenaming,
    HermesLiveRuntimeStatusServing,
    Sendable
{
    func listSessions(limit: Int) async throws -> [HermesSession]
    func readStoredSessionSource(storedSessionID: String) async throws -> String?
    func readStoredSession(storedSessionID: String) async throws -> [HermesMessage]
    func activeSessionStatuses() async throws -> [String: String]
    func createSession(title: String?) async throws -> LiveSession
}

protocol HermesPromptServing: Sendable {
    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus
}

protocol HermesTurnServing: HermesPromptServing, Sendable {
    func steer(liveSessionID: String, text: String) async throws -> Bool
    func interrupt(liveSessionID: String) async throws
}

protocol HermesTalkServing:
    HermesPromptServing,
    HermesLiveRuntimeStatusServing,
    Sendable
{}

protocol HermesBlockingPromptServing: Sendable {
    func respondToClarification(requestID: String, answer: String) async throws
    func respondToSudo(requestID: String, password: String) async throws
    func respondToSecret(requestID: String, value: String) async throws
    func respondToApproval(
        liveSessionID: String,
        choice: ApprovalChoice
    ) async throws -> Bool
}

extension HermesSessionServing {
    func listSessions() async throws -> [HermesSession] {
        try await listSessions(limit: 50)
    }
}
