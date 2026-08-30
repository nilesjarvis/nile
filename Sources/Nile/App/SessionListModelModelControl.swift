import Foundation

/// Model-facing model picker, reasoning, and pin integration.
///
/// SessionModelControlRuntime retains model capability tasks, mutation
/// generations, confirmation state, and protected pin persistence. This
/// extension projects that runtime into the currently displayed session while
/// authoritative Hermes events remain at the core model's ordered boundary.
@MainActor
extension SessionListModel {
    var selectableModelProviders: [ModelProvider] {
        runtimes.modelControlRuntime.selectableProviders
    }

    var currentModelSupportsReasoning: Bool {
        runtimes.modelControlRuntime.currentModelSupportsReasoning(
            info: liveSession?.info
        )
    }

    var canModifyModelPins: Bool {
        runtimes.modelControlRuntime.canModifyPins(gatewayID: currentGatewayID)
    }

    var resolvedPinnedModels: Set<ModelPin> {
        runtimes.modelControlRuntime.resolvedPinnedModels
    }

    var unresolvedPinnedModels: Set<ModelPin> {
        runtimes.modelControlRuntime.unresolvedPinnedModels
    }

    func isModelPinned(provider: String, model: String) -> Bool {
        runtimes.modelControlRuntime.isModelPinned(
            provider: provider,
            model: model
        )
    }

    var resolvedCurrentModelProviderSlug: String? {
        runtimes.modelControlRuntime.resolvedCurrentProviderSlug(
            info: liveSession?.info
        )
    }

    func setModelPickerVisible(_ visible: Bool) {
        runtimes.modelControlRuntime.setPickerVisible(
            visible,
            owner: captureSessionControlOwner(requireIdle: true),
            onError: setModelControlError
        )
    }

    func refreshModelOptions() {
        runtimes.modelControlRuntime.refreshOptions(
            owner: captureSessionControlOwner(requireIdle: true)
        )
    }

    func prepareCompactModelMenu() {
        runtimes.modelControlRuntime.prepareCompactMenu(
            owner: captureSessionControlOwner(requireIdle: true)
        )
    }

    func selectModel(_ model: String, provider: String) {
        guard let info = liveSession?.info else {
            return
        }
        runtimes.modelControlRuntime.selectModel(
            model,
            provider: provider,
            currentInfo: info,
            owner: captureSessionControlOwner(requireIdle: true),
            onApplied: applyModelControl,
            onError: setModelControlError
        )
    }

    func setReasoningEffort(_ effort: String) {
        guard let info = liveSession?.info else {
            return
        }
        runtimes.modelControlRuntime.setReasoningEffort(
            effort,
            currentInfo: info,
            owner: captureSessionControlOwner(requireIdle: true),
            onApplied: applyModelControl,
            onError: setModelControlError
        )
    }

    func confirmModelSwitch() {
        guard let info = liveSession?.info else {
            return
        }
        runtimes.modelControlRuntime.confirmModelSwitch(
            owner: captureSessionControlOwner(requireIdle: true),
            currentInfo: info,
            onApplied: applyModelControl,
            onError: setModelControlError
        )
    }

    func dismissModelSwitchConfirmation() {
        runtimes.modelControlRuntime.dismissSwitchConfirmation(
            onError: setModelControlError
        )
    }

    var canConfirmModelSwitch: Bool {
        runtimes.modelControlRuntime.canConfirmModelSwitch(
            owner: captureSessionControlOwner(requireIdle: true)
        )
    }

    func toggleModelPin(provider: String?, model: String) {
        runtimes.modelControlRuntime.togglePin(
            gatewayOwner: currentModelControlGatewayOwner,
            provider: provider,
            model: model,
            onError: setModelControlError
        )
    }

    private func captureSessionControlOwner(
        requireIdle: Bool
    ) -> SessionModelControlRuntime.SessionOwner? {
        guard showsComposer,
              !isOpeningSession,
              !isReadOnlySession,
              !isAttaching,
              !isAttachmentDraftLocked,
              !composerIsBlocked,
              !isUpdatingSessionControls,
              let gatewayID = currentGatewayID,
              let selectedSessionID,
              let liveSession,
              liveSession.storedID == nil
                || liveSession.storedID == selectedSessionID,
              !requireIdle || !isSending else {
            return nil
        }
        return SessionModelControlRuntime.SessionOwner(
            gatewayGeneration: gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayID,
            storedSessionID: selectedSessionID,
            liveSessionID: liveSession.liveID
        )
    }

    private func isCurrentSessionControlOwner(
        _ owner: SessionModelControlRuntime.SessionOwner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.displayGeneration == displayGeneration
            && owner.gatewayID == currentGatewayID
            && owner.storedSessionID == selectedSessionID
            && owner.liveSessionID == liveSession?.liveID
            && !isReadOnlySession
    }

    private var currentModelControlGatewayOwner:
        SessionModelControlRuntime.GatewayOwner? {
        guard let gatewayID = currentGatewayID else {
            return nil
        }
        return SessionModelControlRuntime.GatewayOwner(
            gatewayGeneration: gatewayGeneration,
            gatewayID: gatewayID
        )
    }

    private func applyModelControl(
        _ control: SessionModelControlRuntime.AppliedControl
    ) {
        guard isCurrentSessionControlOwner(control.owner) else {
            return
        }
        updateLiveSessionInfo(
            model: control.model,
            provider: control.provider,
            reasoningEffort: control.reasoningEffort
        )
        transcriptEntries = liveTranscript.appendSystem(
            control.notice,
            to: transcriptEntries
        )
    }

    private func setModelControlError(_ message: String?) {
        operationError = message
    }

    private func updateLiveSessionInfo(
        model: String?,
        provider: String?,
        reasoningEffort: String?
    ) {
        guard let liveSession else {
            return
        }
        self.liveSession = LiveSession(
            liveID: liveSession.liveID,
            storedID: liveSession.storedID,
            info: SessionInfo(
                model: model,
                provider: provider,
                reasoningEffort: reasoningEffort,
                reasoningEffortSessionScopeSupported:
                    liveSession.info.reasoningEffortSessionScopeSupported,
                isLazy: liveSession.info.isLazy
            ),
            messages: liveSession.messages,
            running: liveSession.running,
            status: liveSession.status,
            inflight: liveSession.inflight
        )
    }
}
