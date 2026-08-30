import Foundation

/// Runtime-backed feature presentation adapters.
///
/// The core model retains mutable orchestration state, runtime construction,
/// and the single ordered Hermes event-application boundary. This extension
/// only forwards observable feature state.
@MainActor
extension SessionListModel {
    var pinnedSessionIDs: Set<String> {
        runtimes.pinRuntime.pinnedSessionIDs
    }

    var commandCatalog: CommandCatalog? {
        runtimes.commandRuntime.catalog
    }

    var slashCompletions: [SlashCompletion] {
        runtimes.commandRuntime.completions
    }

    var slashReplaceFrom: Int {
        runtimes.commandRuntime.replaceFrom
    }

    var modelOptions: ModelOptions? {
        get { runtimes.modelControlRuntime.modelOptions }
        set { runtimes.modelControlRuntime.modelOptions = newValue }
    }

    var modelOptionsError: String? {
        get { runtimes.modelControlRuntime.modelOptionsError }
        set { runtimes.modelControlRuntime.modelOptionsError = newValue }
    }

    var pinnedModelsGatewayID: String? {
        get { runtimes.modelControlRuntime.pinnedModelsGatewayID }
        set { runtimes.modelControlRuntime.pinnedModelsGatewayID = newValue }
    }

    var pinnedModels: Set<ModelPin> {
        get { runtimes.modelControlRuntime.pinnedModels }
        set { runtimes.modelControlRuntime.pinnedModels = newValue }
    }

    var isModelPickerVisible: Bool {
        get { runtimes.modelControlRuntime.isPickerVisible }
        set { runtimes.modelControlRuntime.isPickerVisible = newValue }
    }

    var isLoadingModelOptions: Bool {
        get { runtimes.modelControlRuntime.isLoadingOptions }
        set { runtimes.modelControlRuntime.isLoadingOptions = newValue }
    }

    var isUpdatingSessionControls: Bool {
        get { runtimes.modelControlRuntime.isUpdatingControls }
        set { runtimes.modelControlRuntime.isUpdatingControls = newValue }
    }

    var modelSwitchConfirmation: ModelSwitchConfirmation? {
        get { runtimes.modelControlRuntime.switchConfirmation }
        set { runtimes.modelControlRuntime.switchConfirmation = newValue }
    }

    var goalAvailability: GoalAvailability {
        get { runtimes.goalRuntime.availability }
        set { runtimes.goalRuntime.availability = newValue }
    }

    var goal: HermesGoal? {
        get { runtimes.goalRuntime.goal }
        set { runtimes.goalRuntime.goal = newValue }
    }

    var isGoalSheetVisible: Bool {
        get { runtimes.goalRuntime.isSheetVisible }
        set { runtimes.goalRuntime.isSheetVisible = newValue }
    }

    var isGoalMutating: Bool {
        get { runtimes.goalRuntime.isMutating }
        set { runtimes.goalRuntime.isMutating = newValue }
    }

    var isGoalFinalizing: Bool {
        get { runtimes.goalRuntime.isFinalizing }
        set { runtimes.goalRuntime.isFinalizing = newValue }
    }

    var goalError: String? {
        get { runtimes.goalRuntime.error }
        set { runtimes.goalRuntime.error = newValue }
    }

    var isListening: Bool {
        runtimes.voiceInputRuntime.isDraftListening
            || runtimes.talkRuntime.isListening
    }

    var isTranscribing: Bool {
        runtimes.voiceInputRuntime.isDraftTranscribing
            || runtimes.talkRuntime.isTranscribing
    }

    var speakRepliesEnabled: Bool {
        runtimes.speechRuntime.standardRepliesEnabled
    }

    var talk: TalkUIState? {
        runtimes.talkRuntime.presentation
    }

    var assistantDeltaPublicationCount: Int {
        runtimes.eventRuntime.assistantDeltaPublicationCount
    }

}
