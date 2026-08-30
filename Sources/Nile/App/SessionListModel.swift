import Foundation
import Observation

@MainActor
@Observable
final class SessionListModel {
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var sessions: [HermesSession]
    var activeStatuses: [String: String]
    var sessionsNeedingInput: Set<String>
    private(set) var pendingActionableBlockingPromptIDs: Set<String> = []
    var selectedSessionID: String?
    var liveSession: LiveSession?
    var storedMessages: [HermesMessage]
    var transcriptEntries: [TranscriptEntry]
    var activeTodos: [TodoItem]?
    var composer = ""
    var pendingAttachments: [PendingAttachment] = []
    var isAttaching = false
    var isAttachmentDraftLocked = false
    var isSending = false
    var isStopping = false
    var turnStartedAt: Date?
    var searchText = ""
    var isExpanded = false
    var state: LoadingState
    var isOpeningSession = false
    var sessionSwitchPresentation: SessionSwitchPresentation?
    var sessionSettleGeneration = 0
    var isReadOnlySession = false
    var operationError: String?
    var connectionPhase: SessionConnectionPhase = .online

    @ObservationIgnored let runtimes: SessionRuntimeComposition
    let transcriptScrollCoordinator = TranscriptScrollCoordinator()
    let fixtureAllowsSessionCreation: Bool
    private let fixtureStoredMessages: [String: [HermesMessage]]
    private let fixtureLiveSessions: [String: LiveSession]
    let fixtureAttentionSessionIDs: Set<String>
    private let fixtureSessionSwitchDelay: Duration?
    var outboundTasks: [UUID: Task<Void, Never>] = [:]
    var liveTranscript = LiveTranscriptCoordinator()
    var attachedToExistingTurn = false
    var gatewayGeneration = 0
    var displayGeneration = 0

    init(
        repository capabilityProvider:
            any SessionRepositoryCapabilityProviding,
        refreshTicks: AsyncStream<Void>? = nil,
        draftStore: (any ComposerDraftStoring)? = nil,
        attachmentDraftStore: (any AttachmentDraftStoring)? = nil,
        sessionPinStore: (any SessionPinStoring)? = nil,
        sessionPinWriteQueue: SessionPinWriteQueue? = nil,
        modelPinStore: (any ModelPinStoring)? = nil,
        modelPinWriteQueue: ModelPinWriteQueue? = nil,
        attachmentCache: any AttachmentCaching = PrivateAttachmentCache(),
        voiceInput: (any VoiceInput)? = nil,
        speechOutput: (any SpeechOutput)? = nil,
        backgroundController: any TurnBackgroundControlling =
            NoOpTurnBackgroundController(),
        usagePollInterval: Duration = .milliseconds(1_200),
        usageMaxAttempts: Int = 600,
        assistantDeltaPublicationInterval: Duration =
            SessionEventRuntime.defaultAssistantDeltaPublicationInterval,
        monotonicMilliseconds: @escaping () -> Int64 = {
            Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        }
    ) {
        runtimes = SessionRuntimeComposition.production(
            capabilityProvider: capabilityProvider,
            refreshTicks: refreshTicks,
            draftStore: draftStore,
            attachmentDraftStore: attachmentDraftStore,
            sessionPinStore: sessionPinStore,
            sessionPinWriteQueue: sessionPinWriteQueue,
            modelPinStore: modelPinStore,
            modelPinWriteQueue: modelPinWriteQueue,
            attachmentCache: attachmentCache,
            voiceInput: voiceInput,
            speechOutput: speechOutput,
            backgroundController: backgroundController,
            usagePollInterval: usagePollInterval,
            usageMaxAttempts: usageMaxAttempts,
            assistantDeltaPublicationInterval:
                assistantDeltaPublicationInterval,
            monotonicMilliseconds: monotonicMilliseconds
        )
        fixtureAllowsSessionCreation = false
        fixtureStoredMessages = [:]
        fixtureLiveSessions = [:]
        fixtureAttentionSessionIDs = []
        fixtureSessionSwitchDelay = nil
        sessions = []
        activeStatuses = [:]
        sessionsNeedingInput = []
        storedMessages = []
        transcriptEntries = []
        state = .idle
        beginRoutingVoiceEvents()
    }

#if DEBUG || NILE_LOCAL_RELEASE
    init(
        fixture: SessionListFixture,
        voiceInput: any VoiceInput = UnavailableVoiceInput(),
        speechOutput: any SpeechOutput = NoOpSpeechOutput(),
        backgroundController: any TurnBackgroundControlling =
            NoOpTurnBackgroundController(),
        sessionSwitchDelay: Duration? = nil,
        startsWithEmptyTranscript: Bool = false
    ) {
        runtimes = SessionRuntimeComposition.fixture(
            voiceInput: voiceInput,
            speechOutput: speechOutput,
            backgroundController: backgroundController
        )
        fixtureAllowsSessionCreation =
            fixture == .empty || fixture == .showcase
        fixtureStoredMessages = fixture.storedMessages
        fixtureLiveSessions = fixture.liveSessions
        fixtureAttentionSessionIDs = fixture.sessionsNeedingInput
        fixtureSessionSwitchDelay = sessionSwitchDelay
        sessions = fixture.sessions
        activeStatuses = fixture.activeStatuses
        sessionsNeedingInput = fixture.sessionsNeedingInput
        runtimes.pinRuntime.synchronizeGateway(
            owner: SessionPinRuntime.GatewayOwner(
                gatewayGeneration: 0,
                gatewayID: "fixture"
            )
        )
        selectedSessionID = fixture.selectedSessionID
        composer = fixture.composer
        liveSession = fixture.selectedSessionID.flatMap {
            fixture.liveSessions[$0]
        }
        storedMessages = fixture.selectedSessionID
            .flatMap { fixture.storedMessages[$0] } ?? []
        transcriptEntries = []
        pendingAttachments = fixture.pendingAttachments
        isReadOnlySession = fixture.selectedSessionID
            .flatMap { selectedID in
                fixture.sessions.first { $0.id == selectedID }?.isTerminalOwned
        } ?? false
        state = .loaded
        if let selectedSessionID, !fixture.composer.isEmpty {
            runtimes.composerRuntime.seed(
                owner: ComposerDraftOwner(
                    gatewayID: "fixture",
                    storedSessionID: selectedSessionID
                ),
                text: fixture.composer
            )
        }
        if let selectedSessionID, !fixture.pendingAttachments.isEmpty {
            runtimes.attachmentPersistenceRuntime.seedDraft(
                owner: ComposerDraftOwner(
                    gatewayID: "fixture",
                    storedSessionID: selectedSessionID
                ),
                attachments: fixture.pendingAttachments
            )
        }
        runtimes.gatewayContextRuntime.recordListedSessions(fixture.sessions)
        if let liveSession = fixture.liveSession {
            applyLiveSessionTranscript(liveSession)
        } else {
            applyStoredTranscript(storedMessages)
        }
        if let transcriptEntries = fixture.transcriptEntries {
            self.transcriptEntries = transcriptEntries
        }
        if startsWithEmptyTranscript {
            transcriptEntries = []
        }
        usage = fixture.usage
        for event in fixture.blockingEvents {
            _ = runtimes.blockingPromptRuntime.handleEvent(
                event,
                gatewayID: currentGatewayID,
                fallbackStoredSessionID: selectedSessionID
            )
        }
        if let fixtureModelOptions = fixture.modelPickerOptions {
            runtimes.modelControlRuntime.installFixture(
                options: fixtureModelOptions,
                pins: fixture.modelPins,
                gatewayID:
                    fixture == .visualRegressionModelPicker ? nil : "fixture"
            )
        }
        runtimes.goalRuntime.installFixture(
            goal: fixture.goal,
            showsSheet: fixture.showsGoalSheet
        )
        syncBlockingPromptUI()
        beginRoutingVoiceEvents()
    }
#endif

    isolated deinit {
        runtimes.eventRuntime.cancel()
        outboundTasks.values.forEach { $0.cancel() }
        runtimes.voiceInputRuntime.cancelCapture()
        runtimes.lifecycleRuntime.stopAllTurns()
    }

    var fixtureNavigationSwitchDelay: Duration? {
        fixtureSessionSwitchDelay
    }

    func fixtureMessages(for sessionID: String) -> [HermesMessage] {
        fixtureStoredMessages[sessionID] ?? []
    }

    func fixtureLiveSession(for sessionID: String) -> LiveSession? {
        fixtureLiveSessions[sessionID]
    }

    func applyPendingActionableBlockingPromptIDs(_ promptIDs: Set<String>) {
        if pendingActionableBlockingPromptIDs != promptIDs {
            pendingActionableBlockingPromptIDs = promptIDs
        }
    }

}
