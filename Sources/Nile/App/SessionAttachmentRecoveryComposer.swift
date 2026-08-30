import Foundation

/// Reconstructs recovered composer state behind relaunch decisions made by
/// `SessionAttachmentRecoveryRuntime`.
@MainActor
extension SessionAttachmentRecoveryRuntime {
    func scheduleRecoveredComposerEdit(
        owner: ComposerDraftOwner,
        markers: [AttachmentMutationMarker],
        text: String,
        onFailure: @escaping EditFailureHandler
    ) {
        attachmentPersistenceRuntime.scheduleRecoveredMarkerEdit(
            owner: owner,
            markers: markers,
            text: text,
            isCurrent: { [weak self] in
                self?.composerRuntime.text(for: owner) == text
            },
            onFailure: { [weak self] durableMarkers in
                guard let self else {
                    return
                }
                let recovered = durableMarkers.reduce("") {
                    current,
                    marker in
                    SessionComposerRuntime.mergeRecovered(
                        marker.input,
                        with: current
                    )
                }
                let fallback = Self.mergedRecoveredComposer(
                    recovered,
                    ordinary:
                        self.draftPersistenceRuntime.record(for: owner)?.text
                            ?? ""
                )
                self.composerRuntime.replace(owner: owner, text: fallback)
                onFailure(
                    RecoveredEditFailure(
                        owner: owner,
                        attemptedText: text,
                        fallbackText: fallback
                    )
                )
            }
        )
    }

    func mergeAttachments(
        _ prefix: [PendingAttachment],
        _ suffix: [PendingAttachment]
    ) -> [PendingAttachment] {
        var seen: Set<String> = []
        return (prefix + suffix).filter { seen.insert($0.id).inserted }
    }

    func consolidateComposerOwnership(
        owner: ComposerDraftOwner,
        commitGuard: @escaping CommitGuard
    ) async {
        guard let ordinary = draftPersistenceRuntime.record(for: owner),
              !ordinary.text.isEmpty else {
            return
        }
        let markers = attachmentPersistenceRuntime.markers(
            for: owner,
            stage: .draftRecovered
        )
        guard !markers.isEmpty else {
            return
        }
        let recovered = markers.reduce("") { current, marker in
            SessionComposerRuntime.mergeRecovered(marker.input, with: current)
        }
        let merged = Self.mergedRecoveredComposer(
            recovered,
            ordinary: ordinary.text
        )
        let migrations = markers.map { marker in
            AttachmentMutationMigration(
                expected: marker,
                replacement: marker.retargeting(
                    storedSessionID: marker.storedSessionID,
                    liveSessionID: marker.liveSessionID,
                    input: merged,
                    attachments: marker.attachments
                )
            )
        }
        if migrations.contains(where: {
            $0.expected != $0.replacement
        }) {
            let updated = await attachmentPersistenceRuntime.migrateMarkers(
                migrations,
                commitGuard: commitGuard
            )
            guard updated else {
                return
            }
        }

        composerRuntime.replace(owner: owner, text: merged)
        _ = await draftPersistenceRuntime.retireStoredDraft(owner: owner)
    }

    func restoreRecoveredMarkers(owner: ComposerDraftOwner) {
        let markers = attachmentPersistenceRuntime.markers(
            for: owner,
            stage: .draftRecovered
        )
        guard !markers.isEmpty else {
            return
        }
        let recoveredComposer = markers.reduce("") { current, marker in
            SessionComposerRuntime.mergeRecovered(marker.input, with: current)
        }
        let mergedComposer = Self.mergedRecoveredComposer(
            recoveredComposer,
            ordinary: composerRuntime.text(for: owner)
        )
        let recoveredAttachments = markers.reduce(
            [PendingAttachment]()
        ) { current, marker in
            mergeAttachments(current, marker.attachments)
        }
        let mergedAttachments = mergeAttachments(
            recoveredAttachments,
            attachmentPersistenceRuntime.draft(for: owner)
        )
        composerRuntime.seed(
            owner: owner,
            text: mergedComposer,
            restored: !mergedComposer.isEmpty
        )
        attachmentPersistenceRuntime.replaceDraft(
            for: owner,
            with: mergedAttachments
        )
        if !mergedAttachments.isEmpty {
            attachmentPersistenceRuntime.markRestored(owner: owner)
        }
    }

    private static func mergedRecoveredComposer(
        _ recovered: String,
        ordinary: String
    ) -> String {
        if ordinary.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return recovered
        }
        if recovered == ordinary
            || recovered.hasSuffix("\n\n\(ordinary)") {
            return recovered
        }
        return SessionComposerRuntime.mergeRecovered(
            recovered,
            with: ordinary
        )
    }
}
