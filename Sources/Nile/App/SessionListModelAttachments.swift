import Foundation

/// Displayed-session photo draft intake and delivery admission.
///
/// The attachment runtimes retain protected persistence, transport tasks,
/// mutation correlation, and uncertainty quarantine. This extension owns
/// visible draft projection and starts delivery; a same-model settlement
/// extension applies typed outcomes without another repository or event stream.
@MainActor
extension SessionListModel {
    static let attachmentQuarantineMessage =
        "Hermes may still be handling the interrupted photo. Nile is keeping this conversation closed until Hermes safely releases it; use a new session in the meantime."

    var isCurrentAttachmentOwnerQuarantined: Bool {
        guard let owner = currentDraftOwner() else {
            return false
        }
        return runtimes.attachmentPersistenceRuntime.isQuarantined(owner: owner)
    }

    func attachImageData(_ data: Data) {
        guard showsComposer,
              !isSending,
              !isOpeningSession,
              !composerIsBlocked,
              !isAttaching,
              !isAttachmentDraftLocked,
              !isCurrentAttachmentOwnerQuarantined,
              let owner = currentDraftOwner() else {
            return
        }
        isAttaching = true
        operationError = nil
        let operationID = UUID()
        outboundTasks[operationID] = Task { [weak self] in
            guard let self else {
                return
            }
            let attachment = await Task.detached(priority: .userInitiated) {
                NileImageEncoder.encode(data)
            }.value
            guard let attachment else {
                self.isAttaching = false
                self.operationError = "Could not read that image"
                self.outboundTasks.removeValue(forKey: operationID)
                return
            }
            guard self.currentDraftOwner() == owner,
                  !self.isOpeningSession,
                  !self.isSending else {
                self.isAttaching = false
                self.outboundTasks.removeValue(forKey: operationID)
                return
            }
            let previous = self.runtimes.attachmentPersistenceRuntime.draft(
                for: owner
            )
            let next = previous + [attachment]
            let record = self.runtimes.attachmentPersistenceRuntime.makeDraft(
                owner: owner,
                attachments: next
            )
            let persisted = await self.runtimes.attachmentPersistenceRuntime
                .updateDraft(record)
            guard self.currentDraftOwner() == owner else {
                self.outboundTasks.removeValue(forKey: operationID)
                return
            }
            if persisted {
                self.pendingAttachments = next
                self.isAttachmentDraftLocked = false
            } else {
                self.operationError =
                    "Could not save that photo draft. Add the photo again."
            }
            self.isAttaching = false
            self.outboundTasks.removeValue(forKey: operationID)
        }
    }

    func removeAttachment(id: String) {
        guard showsComposer,
              !isOpeningSession,
              !isAttaching,
              !isAttachmentDraftLocked,
              !isCurrentAttachmentOwnerQuarantined,
              let owner = currentDraftOwner(),
              pendingAttachments.contains(where: { $0.id == id }) else {
            return
        }
        let next = pendingAttachments.filter { $0.id != id }
        let record = runtimes.attachmentPersistenceRuntime.makeDraft(
            owner: owner,
            attachments: next
        )
        isAttaching = true
        isAttachmentDraftLocked = true
        operationError = nil
        let operationID = UUID()
        outboundTasks[operationID] = Task { [weak self] in
            guard let self else {
                return
            }
            let persisted = await self.runtimes.attachmentPersistenceRuntime
                .updateDraft(record)
            guard self.currentDraftOwner() == owner else {
                self.outboundTasks.removeValue(forKey: operationID)
                return
            }
            if persisted {
                self.pendingAttachments = next
            } else {
                self.operationError =
                    "Could not save the photo removal. Try again."
            }
            self.isAttaching = false
            self.isAttachmentDraftLocked = false
            self.outboundTasks.removeValue(forKey: operationID)
        }
    }

    func submitAttachmentPrompt(
        _ input: String,
        attachments: [PendingAttachment],
        liveSession: LiveSession,
        owner: ComposerDraftOwner,
        token: SessionComposerRuntime.RecoveryToken,
        persistenceClaim: PersistedComposerDraft?
    ) -> Bool {
        let entryID = "user-\(UUID().uuidString)"
        let batch = OutboundAttachmentBatch(
            id: "attachment-\(UUID().uuidString)",
            owner: owner,
            liveSessionID: liveSession.liveID,
            input: input,
            attachments: attachments,
            userEntryID: entryID,
            userMessagesBefore: liveSession.messages.filter {
                $0.role.caseInsensitiveCompare("user") == .orderedSame
            }.count
        )
        let wasSending = isSending
        if !wasSending {
            liveTranscript.beginTurn()
        }
        transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: entryID,
                    role: .user,
                    content: input,
                    images: attachments.map {
                        MessageImage(
                            base64: $0.base64,
                            label: $0.filename
                        )
                    },
                    pending: wasSending
                )
            )
        )
        isSending = true
        turnStartedAt = turnStartedAt ?? Date()
        activeTodos = nil
        activeStatuses[owner.storedSessionID] = "working"
        beginBackgroundTurn(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: liveSession.liveID
        )

        let expectedDraft = runtimes.attachmentPersistenceRuntime.record(for: owner)
        let tombstone = runtimes.attachmentPersistenceRuntime.makeDraft(
            owner: owner,
            attachments: []
        )
        let marker = AttachmentMutationMarker(
            id: batch.id,
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: batch.liveSessionID,
            input: input,
            attachments: attachments,
            userEntryID: entryID,
            userMessagesBefore: batch.userMessagesBefore,
            stage: .uploadPending
        )
        let replacedMarkerIDs = Set(
            runtimes.attachmentPersistenceRuntime.markers(for: owner).filter {
                $0.stage == .uploadPending
                    || $0.stage == .draftRecovered
            }.map(\.id)
        )
        let started = runtimes.attachmentRuntime.startDelivery(
            batch: batch,
            marker: marker,
            prepare: { [weak self] in
                guard let self else {
                    return .rejected(message: Self.draftFlushFailureMessage)
                }
                guard await self.runtimes.draftLifecycleRuntime.flushClaim(
                    owner: owner,
                    claim: persistenceClaim
                ) else {
                    return .rejected(message: Self.draftFlushFailureMessage)
                }

                let markerCommitted = await self
                    .runtimes.attachmentPersistenceRuntime.beginMutation(
                        marker,
                        replacingMarkerIDs: replacedMarkerIDs,
                        expectedDraft: expectedDraft,
                        tombstone: tombstone
                    )
                guard markerCommitted else {
                    return .rejected(
                        message:
                            "Could not save the photo recovery state, so nothing was sent."
                    )
                }
                await self.applyDraftClaimRetirement(
                    owner: owner,
                    claim: persistenceClaim
                )
                return .ready
            },
            preparePrompt: { [weak self] current, promptPending in
                guard let self else {
                    return false
                }
                return await self.runtimes.attachmentPersistenceRuntime
                    .advanceMutation(
                        from: current,
                        to: promptPending
                    )
            },
            didUpload: { [weak self] attachment, attached in
                self?.liveTranscript.rememberImage(
                    path: attached.path,
                    base64: attachment.base64
                )
            },
            onOutcome: { [weak self] outcome in
                guard let self else {
                    return
                }
                switch outcome {
                case let .preparationFailed(message):
                    self.restoreAttachmentBeforeMutation(
                        batch,
                        token: token,
                        message: message
                    )
                case let .accepted(batch, marker):
                    await self.settleAcceptedAttachmentBatch(
                        batch,
                        marker: marker
                    )
                case let .failed(batch, marker, message, uncertain):
                    await self.settleFailedAttachmentBatch(
                        batch,
                        marker: marker,
                        token: token,
                        message: message,
                        uncertain: uncertain
                    )
                }
            },
            onStartTimeout: { [weak self] batch, marker in
                guard let self else {
                    return
                }
                await self.settleFailedAttachmentBatch(
                    batch,
                    marker: marker,
                    token: self.runtimes.composerRuntime.capture(batch.owner),
                    message: "Confirming whether Hermes started the photo prompt",
                    uncertain: true
                )
            }
        )
        guard started else {
            restoreAttachmentBeforeMutation(
                batch,
                token: token,
                message: "Photo delivery was already being processed."
            )
            return false
        }
        return true
    }

}
