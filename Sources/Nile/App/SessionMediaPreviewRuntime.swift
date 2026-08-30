import Foundation

/// Executes bounded image-preview hydration behind the media runtime's single
/// attachment-read capability and preview-operation registries.
@MainActor
extension SessionMediaRuntime {
    func reconcilePreviews(
        in transcript: [TranscriptEntry],
        owner: Owner?,
        isCurrentOwner: @escaping OwnerValidator,
        onPreview: @escaping PreviewHandler,
        onNeedsReconcile: @escaping ReconcileHandler
    ) -> [TranscriptEntry] {
        guard repository != nil,
              let owner,
              isCurrentOwner(owner) else {
            resetPreviews()
            return transcript
        }

        let occurrences = transcript.compactMap {
            entry -> (String, [MessageAttachment])? in
            guard case let .message(message) = entry else {
                return nil
            }
            return (message.id, message.attachments)
        }.flatMap { messageID, attachments in
            attachments.enumerated().compactMap {
                index, attachment -> PreviewOccurrence? in
                guard attachment.kind == .image else {
                    return nil
                }
                return PreviewOccurrence(
                    messageID: messageID,
                    attachmentIndex: index,
                    attachment: attachment
                )
            }
        }
        let retained = Array(
            occurrences.suffix(Self.retainedPreviewCount)
        )
        let retainedKeys = Set(retained.map {
            previewKey(owner: owner, occurrence: $0)
        })
        let projected = prunePreviews(
            from: transcript,
            retaining: retainedKeys,
            owner: owner
        )

        for key in previewOperations.keys where !retainedKeys.contains(key) {
            previewOperations.removeValue(forKey: key)?.task.cancel()
        }
        failedPreviewKeys.formIntersection(retainedKeys)

        let candidates = retained.filter { occurrence in
            let key = previewKey(owner: owner, occurrence: occurrence)
            return occurrence.attachment.previewBase64 == nil
                && previewOperations[key] == nil
                && !failedPreviewKeys.contains(key)
        }
        let available = max(
            0,
            Self.concurrentPreviewCount - previewOperations.count
        )
        for occurrence in candidates.prefix(available) {
            startPreview(
                occurrence,
                owner: owner,
                isCurrentOwner: isCurrentOwner,
                onPreview: onPreview,
                onNeedsReconcile: onNeedsReconcile
            )
        }
        return projected
    }

    private func startPreview(
        _ occurrence: PreviewOccurrence,
        owner: Owner,
        isCurrentOwner: @escaping OwnerValidator,
        onPreview: @escaping PreviewHandler,
        onNeedsReconcile: @escaping ReconcileHandler
    ) {
        guard let repository else {
            return
        }
        let key = previewKey(owner: owner, occurrence: occurrence)
        let operationID = UUID()
        let task = Task { [weak self] in
            do {
                let downloaded = try await repository.downloadAttachment(
                    path: occurrence.attachment.path,
                    maxBytes: Self.previewMaximumBytes
                )
                guard let self,
                      self.isCurrentPreview(
                        key,
                        operationID: operationID,
                        isCurrentOwner: isCurrentOwner
                      ) else {
                    self?.finishPreview(
                        key,
                        operationID: operationID,
                        isCurrentOwner: isCurrentOwner,
                        onNeedsReconcile: onNeedsReconcile
                    )
                    return
                }
                guard downloaded.mimeType.lowercased().hasPrefix("image/") else {
                    self.failedPreviewKeys.insert(key)
                    self.finishPreview(
                        key,
                        operationID: operationID,
                        isCurrentOwner: isCurrentOwner,
                        onNeedsReconcile: onNeedsReconcile
                    )
                    return
                }
                let preview = downloaded.bytes.base64EncodedString()
                onPreview(
                    PreviewUpdate(
                        owner: owner,
                        messageID: occurrence.messageID,
                        attachmentIndex: occurrence.attachmentIndex,
                        path: occurrence.attachment.path,
                        attachment: MessageAttachment(
                            path: occurrence.attachment.path,
                            filename: downloaded.filename,
                            kind: .image,
                            previewBase64: preview,
                            mimeType: downloaded.mimeType
                        )
                    )
                )
                self.finishPreview(
                    key,
                    operationID: operationID,
                    isCurrentOwner: isCurrentOwner,
                    onNeedsReconcile: onNeedsReconcile
                )
            } catch is CancellationError {
                self?.finishPreview(
                    key,
                    operationID: operationID,
                    isCurrentOwner: isCurrentOwner,
                    onNeedsReconcile: onNeedsReconcile
                )
            } catch {
                guard let self else {
                    return
                }
                if self.isCurrentPreview(
                    key,
                    operationID: operationID,
                    isCurrentOwner: isCurrentOwner
                ) {
                    self.failedPreviewKeys.insert(key)
                }
                self.finishPreview(
                    key,
                    operationID: operationID,
                    isCurrentOwner: isCurrentOwner,
                    onNeedsReconcile: onNeedsReconcile
                )
            }
        }
        previewOperations[key] = PreviewOperation(
            id: operationID,
            task: task
        )
    }

    private func finishPreview(
        _ key: PreviewKey,
        operationID: UUID,
        isCurrentOwner: OwnerValidator,
        onNeedsReconcile: ReconcileHandler
    ) {
        guard previewOperations[key]?.id == operationID else {
            return
        }
        previewOperations.removeValue(forKey: key)
        if isCurrentOwner(key.owner) {
            onNeedsReconcile()
        }
    }

    private func isCurrentPreview(
        _ key: PreviewKey,
        operationID: UUID,
        isCurrentOwner: OwnerValidator
    ) -> Bool {
        previewOperations[key]?.id == operationID
            && isCurrentOwner(key.owner)
    }

    func resetPreviews() {
        previewOperations.values.forEach { $0.task.cancel() }
        previewOperations.removeAll()
        failedPreviewKeys.removeAll()
    }

    private func prunePreviews(
        from transcript: [TranscriptEntry],
        retaining retainedKeys: Set<PreviewKey>,
        owner: Owner
    ) -> [TranscriptEntry] {
        transcript.map { entry in
            guard case var .message(message) = entry else {
                return entry
            }
            for index in message.attachments.indices {
                let attachment = message.attachments[index]
                let key = PreviewKey(
                    owner: owner,
                    messageID: message.id,
                    attachmentIndex: index,
                    path: attachment.path
                )
                if attachment.kind == .image,
                   attachment.previewBase64 != nil,
                   !retainedKeys.contains(key) {
                    message.attachments[index].previewBase64 = nil
                }
            }
            return .message(message)
        }
    }

    private func previewKey(
        owner: Owner,
        occurrence: PreviewOccurrence
    ) -> PreviewKey {
        PreviewKey(
            owner: owner,
            messageID: occurrence.messageID,
            attachmentIndex: occurrence.attachmentIndex,
            path: occurrence.attachment.path
        )
    }
}
