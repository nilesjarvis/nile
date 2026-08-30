import Foundation

/// The session feature's construction root.
///
/// Production capability narrowing and fixture/no-op wiring live here so
/// `SessionListModel` owns presentation orchestration rather than duplicating
/// the dependency graph across its initializers.
@MainActor
struct SessionRuntimeComposition {
    let gatewayContextRuntime: SessionGatewayContextRuntime
    let lifecycleRuntime: SessionLifecycleRuntime
    let eventRuntime: SessionEventRuntime
    let goalRuntime: SessionGoalRuntime
    let usageRuntime: SessionUsageRuntime
    let gatewayStatsRuntime: GatewayStatsRuntime
    let modelControlRuntime: SessionModelControlRuntime
    let delegationRuntime: SessionDelegationRuntime
    let commandRuntime: SessionCommandRuntime
    let voiceInputRuntime: SessionVoiceInputRuntime
    let speechRuntime: SessionSpeechRuntime
    let talkRuntime: SessionTalkRuntime
    let claimRuntime: SessionClaimRuntime
    let renameRuntime: SessionRenameRuntime
    let mediaRuntime: SessionMediaRuntime
    let attachmentRuntime: SessionAttachmentRuntime
    let attachmentPersistenceRuntime: SessionAttachmentPersistenceRuntime
    let composerRuntime: SessionComposerRuntime
    let draftLifecycleRuntime: SessionDraftLifecycleRuntime
    let creationDraftRuntime: SessionCreationDraftRuntime
    let attachmentRecoveryRuntime: SessionAttachmentRecoveryRuntime
    let blockingPromptRuntime: SessionBlockingPromptRuntime
    let turnRuntime: SessionTurnRuntime
    let timelineRuntime: SessionTimelineRuntime
    let pinRuntime: SessionPinRuntime
    let navigationRuntime: SessionNavigationRuntime

    static func production(
        capabilityProvider:
            any SessionRepositoryCapabilityProviding,
        refreshTicks: AsyncStream<Void>?,
        draftStore: (any ComposerDraftStoring)?,
        attachmentDraftStore: (any AttachmentDraftStoring)?,
        sessionPinStore: (any SessionPinStoring)?,
        sessionPinWriteQueue: SessionPinWriteQueue?,
        modelPinStore: (any ModelPinStoring)?,
        modelPinWriteQueue: ModelPinWriteQueue?,
        attachmentCache: any AttachmentCaching,
        voiceInput: (any VoiceInput)?,
        speechOutput: (any SpeechOutput)?,
        backgroundController: any TurnBackgroundControlling,
        usagePollInterval: Duration,
        usageMaxAttempts: Int,
        assistantDeltaPublicationInterval: Duration,
        monotonicMilliseconds: @escaping () -> Int64
    ) -> Self {
        let capabilities = capabilityProvider.sessionCapabilities
        let draftPersistenceRuntime = SessionDraftPersistenceRuntime(
            store: draftStore
        )
        let attachmentPersistenceRuntime =
            SessionAttachmentPersistenceRuntime(store: attachmentDraftStore)
        let composerRuntime = SessionComposerRuntime()
        let navigationRuntime = SessionNavigationRuntime(
            repository: capabilities.sessions,
            refreshTicks: refreshTicks
        )
        let voiceInputRuntime = SessionVoiceInputRuntime(
            repository: capabilities.transcription,
            input: voiceInput
        )
        let speechRuntime = SessionSpeechRuntime(
            repository: capabilities.speechSynthesis,
            output: speechOutput ?? AVSpeechOutput()
        )

        return Self(
            gatewayContextRuntime: SessionGatewayContextRuntime(
                hasSessionRepository: true
            ),
            lifecycleRuntime: SessionLifecycleRuntime(
                backgroundController: backgroundController
            ),
            eventRuntime: SessionEventRuntime(
                repository: capabilities.events,
                assistantDeltaPublicationInterval:
                    assistantDeltaPublicationInterval
            ),
            goalRuntime: SessionGoalRuntime(repository: capabilities.goals),
            usageRuntime: SessionUsageRuntime(
                repository: capabilities.sessionUsage,
                usagePollInterval: usagePollInterval,
                usageMaxAttempts: usageMaxAttempts
            ),
            gatewayStatsRuntime: GatewayStatsRuntime(
                repository: capabilities.gatewayStatistics
            ),
            modelControlRuntime: SessionModelControlRuntime(
                repository: capabilities.models,
                pinStore: modelPinStore,
                pinWriteQueue: modelPinWriteQueue
            ),
            delegationRuntime: SessionDelegationRuntime(
                repository: capabilities.delegation
            ),
            commandRuntime: SessionCommandRuntime(
                repository: capabilities.commands
            ),
            voiceInputRuntime: voiceInputRuntime,
            speechRuntime: speechRuntime,
            talkRuntime: SessionTalkRuntime(
                repository: capabilities.talk,
                voice: voiceInputRuntime,
                speech: speechRuntime
            ),
            claimRuntime: SessionClaimRuntime(
                repository: capabilities.sessionClaim
            ),
            renameRuntime: SessionRenameRuntime(
                repository: capabilities.sessionRenaming
            ),
            mediaRuntime: SessionMediaRuntime(
                repository: capabilities.attachmentReading,
                cache: attachmentCache
            ),
            attachmentRuntime: SessionAttachmentRuntime(
                attachments: capabilities.attachmentMutating,
                prompts: capabilities.prompts,
                disconnector: capabilities.disconnect
            ),
            attachmentPersistenceRuntime: attachmentPersistenceRuntime,
            composerRuntime: composerRuntime,
            draftLifecycleRuntime: SessionDraftLifecycleRuntime(
                composerRuntime: composerRuntime,
                persistenceRuntime: draftPersistenceRuntime
            ),
            creationDraftRuntime: SessionCreationDraftRuntime(
                composerRuntime: composerRuntime,
                draftPersistenceRuntime: draftPersistenceRuntime,
                attachmentPersistenceRuntime:
                    attachmentPersistenceRuntime
            ),
            attachmentRecoveryRuntime: SessionAttachmentRecoveryRuntime(
                composerRuntime: composerRuntime,
                draftPersistenceRuntime: draftPersistenceRuntime,
                attachmentPersistenceRuntime:
                    attachmentPersistenceRuntime,
                navigationRuntime: navigationRuntime
            ),
            blockingPromptRuntime: SessionBlockingPromptRuntime(
                repository: capabilities.blockingPrompts,
                monotonicMilliseconds: monotonicMilliseconds
            ),
            turnRuntime: SessionTurnRuntime(repository: capabilities.turns),
            timelineRuntime: SessionTimelineRuntime(),
            pinRuntime: SessionPinRuntime(
                store: sessionPinStore,
                writeQueue: sessionPinWriteQueue
            ),
            navigationRuntime: navigationRuntime
        )
    }

    static func fixture(
        voiceInput: any VoiceInput,
        speechOutput: any SpeechOutput,
        backgroundController: any TurnBackgroundControlling
    ) -> Self {
        let draftPersistenceRuntime = SessionDraftPersistenceRuntime(store: nil)
        let attachmentPersistenceRuntime =
            SessionAttachmentPersistenceRuntime(store: nil)
        let composerRuntime = SessionComposerRuntime()
        let navigationRuntime = SessionNavigationRuntime(repository: nil)
        let voiceInputRuntime = SessionVoiceInputRuntime(
            repository: nil,
            input: voiceInput
        )
        let speechRuntime = SessionSpeechRuntime(
            repository: nil,
            output: speechOutput
        )

        return Self(
            gatewayContextRuntime: SessionGatewayContextRuntime(
                hasSessionRepository: false
            ),
            lifecycleRuntime: SessionLifecycleRuntime(
                backgroundController: backgroundController
            ),
            eventRuntime: SessionEventRuntime(repository: nil),
            goalRuntime: SessionGoalRuntime(repository: nil),
            usageRuntime: SessionUsageRuntime(repository: nil),
            gatewayStatsRuntime: GatewayStatsRuntime(repository: nil),
            modelControlRuntime: SessionModelControlRuntime(repository: nil),
            delegationRuntime: SessionDelegationRuntime(repository: nil),
            commandRuntime: SessionCommandRuntime(repository: nil),
            voiceInputRuntime: voiceInputRuntime,
            speechRuntime: speechRuntime,
            talkRuntime: SessionTalkRuntime(
                repository: nil,
                voice: voiceInputRuntime,
                speech: speechRuntime
            ),
            claimRuntime: SessionClaimRuntime(repository: nil),
            renameRuntime: SessionRenameRuntime(repository: nil),
            mediaRuntime: SessionMediaRuntime(
                repository: nil,
                cache: PrivateAttachmentCache()
            ),
            attachmentRuntime: SessionAttachmentRuntime(
                attachments: nil,
                prompts: nil,
                disconnector: nil
            ),
            attachmentPersistenceRuntime: attachmentPersistenceRuntime,
            composerRuntime: composerRuntime,
            draftLifecycleRuntime: SessionDraftLifecycleRuntime(
                composerRuntime: composerRuntime,
                persistenceRuntime: draftPersistenceRuntime
            ),
            creationDraftRuntime: SessionCreationDraftRuntime(
                composerRuntime: composerRuntime,
                draftPersistenceRuntime: draftPersistenceRuntime,
                attachmentPersistenceRuntime:
                    attachmentPersistenceRuntime
            ),
            attachmentRecoveryRuntime: SessionAttachmentRecoveryRuntime(
                composerRuntime: composerRuntime,
                draftPersistenceRuntime: draftPersistenceRuntime,
                attachmentPersistenceRuntime:
                    attachmentPersistenceRuntime,
                navigationRuntime: navigationRuntime
            ),
            blockingPromptRuntime: SessionBlockingPromptRuntime(repository: nil),
            turnRuntime: SessionTurnRuntime(repository: nil),
            timelineRuntime: SessionTimelineRuntime(),
            pinRuntime: SessionPinRuntime(store: nil),
            navigationRuntime: navigationRuntime
        )
    }
}
