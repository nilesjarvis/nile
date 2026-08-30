import Foundation

/// Model-facing dictation, spoken-reply, and app lifecycle integration.
///
/// Capability implementations and their tasks remain in the dedicated voice and
/// speech runtimes. Talk owner gating, routing, and submission projection live
/// in `SessionListModelTalk`; authoritative Hermes events still enter through
/// the core model's single ordered boundary.
@MainActor
extension SessionListModel {
    var composerPlaceholder: String {
        if composerIsBlocked {
            return "Answer the request above"
        }
        if isSending {
            return "Steer the current agent…"
        }
        if isTranscribing {
            return "Hermes is transcribing…"
        }
        if isListening {
            return "Listening…"
        }
        return "Ask Nile"
    }

    var voiceInputAvailable: Bool {
        runtimes.voiceInputRuntime.isAvailable
    }

    func startVoiceInput() {
        guard !runtimes.talkRuntime.isActive,
              !runtimes.voiceInputRuntime.eventsAreEnabled,
              voiceInputAvailable,
              runtimes.lifecycleRuntime.isForeground,
              showsComposer,
              !isOpeningSession,
              !isReadOnlySession,
              !composerIsBlocked,
              !isAttaching,
              !isAttachmentDraftLocked,
              !isOpeningAttachment,
              !isTranscribing,
              !isCurrentAttachmentOwnerQuarantined else {
            return
        }
        runtimes.speechRuntime.stop()
        operationError = nil
        runtimes.voiceInputRuntime.startDraft(composer: composer)
    }

    func stopVoiceInput() {
        guard !runtimes.talkRuntime.isActive,
              runtimes.voiceInputRuntime.eventsAreEnabled else {
            return
        }
        runtimes.voiceInputRuntime.stopCapture()
    }

    func setSpeakRepliesEnabled(_ enabled: Bool) {
        runtimes.speechRuntime.setStandardRepliesEnabled(enabled)
    }

    func onAppForegroundChanged(_ foreground: Bool) {
        let shouldReconcile = runtimes.lifecycleRuntime.setForeground(
            foreground
        )
        if shouldReconcile {
            scheduleVisibleSessionReconciliation()
        }
        guard !foreground else {
            return
        }
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        runtimes.talkRuntime.pause(
            message: "Talk paused while Nile is in the background.",
            stopSpeech: false
        )
    }

    func onSessionSurfaceHidden() {
        runtimes.lifecycleRuntime.hideSurface()
        runtimes.renameRuntime.reset()
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        endTalkMode()
    }

    func cancelVoiceForOwnershipChange() {
        runtimes.talkRuntime.cancelInput()
    }

    func speakCompletedReply(_ rawText: String) {
        guard speakRepliesEnabled,
              runtimes.lifecycleRuntime.isForeground,
              !runtimes.talkRuntime.isActive else {
            return
        }
        let owner = SessionSpeechRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            gatewayID: currentGatewayID,
            storedSessionID: selectedSessionID,
            liveSessionID: liveSession?.liveID
        )
        runtimes.speechRuntime.playStandardReply(
            rawText,
            owner: owner,
            isCurrentOwner: { [weak self] owner in
                guard let self else {
                    return false
                }
                return owner.gatewayGeneration == self.gatewayGeneration
                    && owner.gatewayID == self.currentGatewayID
                    && owner.storedSessionID == self.selectedSessionID
                    && owner.liveSessionID == self.liveSession?.liveID
                    && self.runtimes.lifecycleRuntime.isForeground
                    && self.speakRepliesEnabled
                    && !self.runtimes.talkRuntime.isActive
            },
            onFailure: { [weak self] failure in
                self?.operationError =
                    "Spoken reply unavailable: \(failure.description)"
            }
        )
    }

}
