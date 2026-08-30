import Foundation

/// Executes the upload-to-prompt pipeline behind the single attachment runtime
/// capability and task authority.
@MainActor
extension SessionAttachmentRuntime {
    @discardableResult
    func startDelivery(
        batch: OutboundAttachmentBatch,
        marker: AttachmentMutationMarker,
        prepare: @escaping Preparation,
        preparePrompt: @escaping PromptPreparation,
        didUpload: @escaping UploadHandler,
        onOutcome: @escaping OutcomeHandler,
        onStartTimeout: @escaping StartTimeoutHandler
    ) -> Bool {
        guard deliveryTasks[batch.id] == nil,
              coordinator.batch(id: batch.id) == nil else {
            return false
        }
        coordinator.track(batch)
        let generation = lifecycleGeneration
        deliveryTasks[batch.id] = Task { [weak self] in
            guard let self else {
                return
            }
            let preparation = await prepare()
            guard self.isCurrentDelivery(
                batchID: batch.id,
                generation: generation
            ) else {
                return
            }
            guard case .ready = preparation else {
                guard case let .rejected(message) = preparation else {
                    return
                }
                await onOutcome(.preparationFailed(message: message))
                self.finishDelivery(
                    batchID: batch.id,
                    generation: generation
                )
                return
            }

            var currentMarker = marker
            do {
                for attachment in batch.attachments {
                    self.coordinator.beginUpload(for: batch)
                    let attached: AttachedImage
                    if let attachments = self.attachments {
                        attached = try await attachments.attachImage(
                            liveSessionID: batch.liveSessionID,
                            base64: attachment.base64,
                            fileExtension: attachment.fileExtension,
                            filename: attachment.filename
                        )
                    } else {
                        attached = AttachedImage(
                            path: "fixture://\(attachment.id)",
                            filename: attachment.filename
                        )
                    }
                    guard self.isCurrentDelivery(
                        batchID: batch.id,
                        generation: generation
                    ) else {
                        return
                    }
                    _ = self.coordinator.recordUploadedPath(
                        attached.path,
                        for: batch
                    )
                    didUpload(attachment, attached)
                    try Task.checkCancellation()
                }

                let promptPending = marker.advancing(to: .promptPending)
                guard await preparePrompt(marker, promptPending) else {
                    throw HermesError(
                        "Photo recovery state changed before submit",
                        retryable: false
                    )
                }
                guard self.isCurrentDelivery(
                    batchID: batch.id,
                    generation: generation
                ) else {
                    return
                }
                currentMarker = promptPending
                self.coordinator.beginSubmit(batchID: batch.id)
                let status: PromptSubmitStatus
                if let prompts = self.prompts {
                    status = try await prompts.submitPrompt(
                        liveSessionID: batch.liveSessionID,
                        text: batch.input
                    )
                } else {
                    status = .streaming
                }
                guard self.isCurrentDelivery(
                    batchID: batch.id,
                    generation: generation
                ) else {
                    return
                }
                let resolution = self.coordinator.resolveSubmitResponse(
                    batch: batch,
                    status: status
                )
                switch resolution {
                case .streamingAccepted, .previouslyAccepted:
                    await onOutcome(
                        .accepted(batch: batch, marker: promptPending)
                    )
                case .awaitStreamingStart:
                    self.scheduleStartConfirmation(
                        batch: batch,
                        marker: promptPending,
                        generation: generation,
                        onTimeout: onStartTimeout
                    )
                case .steered:
                    await onOutcome(
                        .failed(
                            batch: batch,
                            marker: promptPending,
                            message:
                                "Hermes accepted this as steering, but delivery was not guaranteed. The text and photo were restored so you can retry them.",
                            uncertain: false
                        )
                    )
                case let .preStartError(message):
                    await onOutcome(
                        .failed(
                            batch: batch,
                            marker: promptPending,
                            message: message,
                            uncertain: false
                        )
                    )
                case .noFollowUp:
                    await onOutcome(
                        .failed(
                            batch: batch,
                            marker: promptPending,
                            message: "Hermes did not accept the photo prompt.",
                            uncertain: false
                        )
                    )
                }
            } catch is CancellationError {
                guard self.isCurrentDelivery(
                    batchID: batch.id,
                    generation: generation
                ) else {
                    return
                }
                if self.coordinator.acceptBufferedStart(for: batch) {
                    await onOutcome(
                        .accepted(batch: batch, marker: currentMarker)
                    )
                } else {
                    _ = self.coordinator.interruptUpload()
                    await onOutcome(
                        .failed(
                            batch: batch,
                            marker: currentMarker,
                            message:
                                "Photo delivery was interrupted before Nile received confirmation.",
                            uncertain: true
                        )
                    )
                }
            } catch {
                guard self.isCurrentDelivery(
                    batchID: batch.id,
                    generation: generation
                ) else {
                    return
                }
                if self.coordinator.acceptBufferedStart(for: batch) {
                    await onOutcome(
                        .accepted(batch: batch, marker: currentMarker)
                    )
                } else {
                    self.coordinator.stopAwaitingResponse(batchID: batch.id)
                    let uncertain = currentMarker.stage == .uploadPending
                        ? Self.isUncertainUploadFailure(error)
                        : Self.promptMayHaveExecuted(error)
                    if uncertain {
                        _ = self.coordinator.interruptUpload()
                    } else {
                        self.coordinator.finishDefinitelyRejectedUpload()
                    }
                    await onOutcome(
                        .failed(
                            batch: batch,
                            marker: currentMarker,
                            message: error.localizedDescription,
                            uncertain: uncertain
                        )
                    )
                }
            }
            self.finishDelivery(
                batchID: batch.id,
                generation: generation
            )
        }
        return true
    }

    private func scheduleStartConfirmation(
        batch: OutboundAttachmentBatch,
        marker: AttachmentMutationMarker,
        generation: Int64,
        onTimeout: @escaping StartTimeoutHandler
    ) {
        startConfirmationTasks.removeValue(forKey: batch.id)?.cancel()
        startConfirmationTasks[batch.id] = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.startConfirmationDelay ?? .zero)
            } catch {
                return
            }
            guard let self,
                  generation == self.lifecycleGeneration,
                  self.startConfirmationTasks[batch.id] != nil,
                  self.coordinator.state(batchID: batch.id).batch != nil else {
                return
            }
            self.startConfirmationTasks.removeValue(forKey: batch.id)
            await onTimeout(batch, marker)
            await self.disconnector?.disconnect()
        }
    }

    private func isCurrentDelivery(
        batchID: String,
        generation: Int64
    ) -> Bool {
        generation == lifecycleGeneration && deliveryTasks[batchID] != nil
    }

    private func finishDelivery(
        batchID: String,
        generation: Int64
    ) {
        guard generation == lifecycleGeneration else {
            return
        }
        deliveryTasks.removeValue(forKey: batchID)
    }

    private static func isUncertainUploadFailure(
        _ error: any Error
    ) -> Bool {
        guard let hermes = error as? HermesError else {
            return true
        }
        return hermes.isConnectionFailure
            || hermes.requestMayHaveSucceeded
            || hermes.code == nil
    }

    private static func promptMayHaveExecuted(
        _ error: any Error
    ) -> Bool {
        guard let hermes = error as? HermesError else {
            return true
        }
        if hermes.isConnectionFailure || hermes.requestMayHaveSucceeded {
            return true
        }
        return ![4001, 4004, 4009].contains(hermes.code)
    }
}
