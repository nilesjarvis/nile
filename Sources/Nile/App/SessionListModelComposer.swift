import Foundation

/// Displayed-session composer projection and protected draft integration.
///
/// Composer, draft-lifecycle, and attachment-recovery runtimes retain their
/// owner-scoped state and persistence authority. This extension owns visible
/// draft admission, projection, and recovery callbacks without repository or
/// Hermes event-stream access.
@MainActor
extension SessionListModel {
    var composerIsBlocked: Bool {
        guard let selectedSessionID else {
            return false
        }
        return sessionsNeedingInput.contains(selectedSessionID)
            || (
                isSending
                    && activeStatuses[selectedSessionID]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() == "waiting"
            )
    }

    var composerCanSend: Bool {
        showsComposer
            && !isOpeningSession
            && !composerIsBlocked
            && !isAttaching
            && !isAttachmentDraftLocked
            && !isTranscribing
            && !isCurrentAttachmentOwnerQuarantined
            && (
                !composer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    || !pendingAttachments.isEmpty
            )
    }

    func updateComposer(_ text: String) {
        guard showsComposer,
              !isOpeningSession,
              !composerIsBlocked,
              let owner = currentDraftOwner() else {
            return
        }
        composer = text
        runtimes.composerRuntime.update(owner: owner, text: text)
        let recoveredMarkers = runtimes.attachmentPersistenceRuntime.markers(
            for: owner,
            stage: .draftRecovered
        )
        if !recoveredMarkers.isEmpty {
            runtimes.attachmentRecoveryRuntime.scheduleRecoveredComposerEdit(
                owner: owner,
                markers: recoveredMarkers,
                text: text,
                onFailure: { [weak self] failure in
                    guard let self,
                          self.transcriptIsVisible(for: failure.owner),
                          self.composer == failure.attemptedText else {
                        return
                    }
                    self.composer = failure.fallbackText
                    self.operationError =
                        "Could not save the recovered draft edit. Try again."
                }
            )
            refreshSlashCompletions(text)
            return
        }
        _ = runtimes.draftLifecycleRuntime.storeText(
            owner: owner,
            text: text,
            onFailure: draftFailureHandler()
        )
        refreshSlashCompletions(text)
    }

    @discardableResult
    func sendMessage(_ inputOverride: String? = nil) -> Bool {
        guard showsComposer,
              !isOpeningSession,
              !composerIsBlocked,
              !isAttaching,
              !isAttachmentDraftLocked,
              !isCurrentAttachmentOwnerQuarantined,
              let liveSession,
              let owner = currentDraftOwner() else {
            return false
        }
        let input = (inputOverride ?? composer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !input.isEmpty || !attachments.isEmpty else {
            return false
        }
        if input.hasPrefix("/"), attachments.isEmpty {
            return runSlashCommand(
                input,
                liveSession: liveSession,
                owner: owner
            )
        }

        let persistenceClaim = input.isEmpty
            ? nil
            : runtimes.draftLifecycleRuntime.captureClaim(
                owner: owner,
                fallbackText: input
            )
        let token = runtimes.composerRuntime.capture(owner)
        runtimes.composerRuntime.claim(owner: owner)
        composer = ""
        pendingAttachments = []
        operationError = nil

        if !attachments.isEmpty {
            return submitAttachmentPrompt(
                input,
                attachments: attachments,
                liveSession: liveSession,
                owner: owner,
                token: token,
                persistenceClaim: persistenceClaim
            )
        }

        if isSending {
            return queueSteer(
                input,
                liveSessionID: liveSession.liveID,
                token: token,
                persistenceClaim: persistenceClaim
            )
        }
        return submitPrompt(
            input,
            liveSessionID: liveSession.liveID,
            token: token,
            persistenceClaim: persistenceClaim
        )
    }

    func flushDrafts() {
        runtimes.draftLifecycleRuntime.flushAll(
            onFailure: draftFailureHandler()
        )
    }

    func applyDraftClaimRetirement(
        owner: ComposerDraftOwner,
        claim: PersistedComposerDraft?
    ) async {
        await runtimes.draftLifecycleRuntime.retireClaim(
            owner: owner,
            claim: claim,
            onProjection: { [weak self] projection in
                guard let self,
                      self.composerIsVisible(for: projection.owner) else {
                    return
                }
                self.composer = projection.text
            },
            onFailure: { [weak self] failure in
                guard let self,
                      self.transcriptIsVisible(for: failure.owner) else {
                    return
                }
                self.operationError = failure.message
            }
        )
    }

    func draftFailureHandler()
        -> SessionDraftLifecycleRuntime.FailureHandler
    {
        { [weak self] failure in
            guard let self,
                  self.transcriptIsVisible(for: failure.owner),
                  self.operationError == nil else {
                return
            }
            self.operationError = failure.message
        }
    }

    func currentDraftOwner() -> ComposerDraftOwner? {
        guard let gatewayID = currentGatewayID,
              let selectedSessionID else {
            return nil
        }
        return ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: selectedSessionID
        )
    }

    func transcriptIsVisible(for owner: ComposerDraftOwner) -> Bool {
        currentGatewayID == owner.gatewayID
            && selectedSessionID == owner.storedSessionID
    }

    func composerIsVisible(for owner: ComposerDraftOwner) -> Bool {
        transcriptIsVisible(for: owner)
            && showsComposer
            && !isOpeningSession
    }

    func restoreComposerPresentation() {
        guard let owner = currentDraftOwner() else {
            composer = ""
            pendingAttachments = []
            return
        }
        composer = runtimes.composerRuntime.text(for: owner)
        pendingAttachments = runtimes.attachmentPersistenceRuntime.draft(for: owner)
        refreshSlashCompletions(composer)
        if runtimes.composerRuntime.consumeRestored(owner: owner) {
            operationError = Self.restoredDraftMessage
        }
        if runtimes.attachmentPersistenceRuntime.consumeRestored(owner: owner) {
            operationError =
                "Unsent photo draft restored from this device. If Nile closed during Send, check the conversation before resending."
        }
        if let notice = runtimes.composerRuntime.takeSteerNotice(owner: owner) {
            transcriptEntries = liveTranscript.appendSystem(
                notice.message,
                isError: true,
                to: transcriptEntries
            )
            if notice.showBanner {
                operationError = notice.message
            }
        }
        if let notice = runtimes.composerRuntime.takeOperationNotice(owner: owner),
           notice.showBanner {
            operationError = notice.message
        }
    }

    static let draftFlushFailureMessage =
        "Nile could not safely save this draft, so it was not sent. Your message was restored."

    private static let restoredDraftMessage =
        "Unsent draft restored from this device. If Nile closed during Send, check the conversation before resending."
}
