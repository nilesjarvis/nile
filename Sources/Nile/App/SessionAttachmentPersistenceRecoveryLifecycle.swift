import Foundation

/// Recovered attachment promotion, migration, editing, and quarantine.
///
/// The core runtime remains the sole store and protected-state declaration
/// authority. This same-runtime extension coordinates recovery transitions
/// without introducing another store owner, task registry, or event path.
@MainActor
extension SessionAttachmentPersistenceRuntime {
    /// Promotes an ordinary photo draft into recovered mutation authority
    /// before creating a missing session.
    func promoteOrdinaryDraft(
        marker: AttachmentMutationMarker,
        attachments: [PendingAttachment]
    ) async -> Bool {
        guard store != nil else {
            return attachments.isEmpty
        }
        let expected = records[marker.owner]
        let tombstone = makeDraft(owner: marker.owner, attachments: [])
        guard await beginMutation(
            marker,
            replacingMarkerIDs: [],
            expectedDraft: expected,
            tombstone: tombstone
        ) else {
            return false
        }
        let recovered = marker.advancing(to: .draftRecovered)
        guard await advanceMutation(from: marker, to: recovered) else {
            return false
        }
        quarantinedOwners.remove(marker.owner)
        return true
    }

    /// Atomically retargets recovered markers plus ordinary records, then moves
    /// the runtime draft projection only after the protected-file CAS commits.
    func migrateRecoveredDraft(
        mutations: [AttachmentMutationMigration],
        from sourceOwner: ComposerDraftOwner,
        to targetOwner: ComposerDraftOwner,
        ordinaryAttachments: [PendingAttachment],
        visibleAttachments: [PendingAttachment],
        commitGuard: @escaping CommitGuard
    ) async -> Bool {
        let source = records[sourceOwner]
        let target = records[targetOwner]
        var changes: [AttachmentDraftMigrationChange] = []
        if source != nil || target != nil || !ordinaryAttachments.isEmpty {
            let timestamp = max(
                nowMilliseconds(),
                lastTimestamp + 1,
                (source?.updatedAtMilliseconds ?? -1) + 1,
                (target?.updatedAtMilliseconds ?? -1) + 1
            )
            lastTimestamp = timestamp
            if let source {
                changes.append(
                    AttachmentDraftMigrationChange(
                        owner: sourceOwner,
                        expected: source,
                        replacement: PersistedAttachmentDraft(
                            gatewayID: sourceOwner.gatewayID,
                            storedSessionID: sourceOwner.storedSessionID,
                            revision: source.revision + 1,
                            attachments: [],
                            updatedAtMilliseconds: timestamp
                        )
                    )
                )
            }
            changes.append(
                AttachmentDraftMigrationChange(
                    owner: targetOwner,
                    expected: target,
                    replacement: PersistedAttachmentDraft(
                        gatewayID: targetOwner.gatewayID,
                        storedSessionID: targetOwner.storedSessionID,
                        revision: max(
                            source?.revision ?? 0,
                            target?.revision ?? 0
                        ) + 2,
                        attachments: ordinaryAttachments,
                        updatedAtMilliseconds: timestamp
                    )
                )
            )
        }

        if !mutations.isEmpty || !changes.isEmpty {
            guard await migrateRecoveredState(
                mutations: mutations,
                draftChanges: changes,
                commitGuard: commitGuard
            ) else {
                return false
            }
        }

        for mutation in mutations {
            markers.removeValue(forKey: mutation.expected.id)
            markers[mutation.replacement.id] = mutation.replacement
        }
        for change in changes {
            records[change.owner] = change.replacement
        }
        drafts.removeValue(forKey: sourceOwner)
        restoredOwners.remove(sourceOwner)
        quarantinedOwners.remove(sourceOwner)
        drafts[targetOwner] = visibleAttachments
        quarantinedOwners.remove(targetOwner)
        return true
    }

    func migrateMarkers(
        _ mutations: [AttachmentMutationMigration],
        commitGuard: @escaping CommitGuard
    ) async -> Bool {
        guard !mutations.isEmpty else {
            return true
        }
        guard await migrateRecoveredState(
            mutations: mutations,
            draftChanges: [],
            commitGuard: commitGuard
        ) else {
            return false
        }
        for mutation in mutations {
            markers[mutation.replacement.id] = mutation.replacement
        }
        return true
    }

    /// Updates recovered marker text with exact-marker CAS, bounded reload
    /// retries, and one replaceable task per owner.
    func scheduleRecoveredMarkerEdit(
        owner: ComposerDraftOwner,
        markers initialMarkers: [AttachmentMutationMarker],
        text: String,
        isCurrent: @escaping CommitGuard,
        onFailure: @escaping RecoveredEditFailure
    ) {
        guard store != nil else {
            return
        }
        recoveredEditRuntime.schedule(
            owner: owner,
            markers: initialMarkers,
            text: text,
            isCurrent: isCurrent,
            migrate: { [weak self] migrations, commitGuard in
                await self?.migrateRecoveredState(
                    mutations: migrations,
                    draftChanges: [],
                    commitGuard: commitGuard
                ) ?? false
            },
            load: { [weak self] in
                await self?.loadRecoverySnapshot()
            },
            markerSource: { [weak self] owner in
                self?.markers(for: owner, stage: .draftRecovered) ?? []
            },
            markerSink: { [weak self] marker in
                self?.markers[marker.id] = marker
            },
            onFailure: onFailure
        )
    }

    /// Immediately quarantines in-memory state on connection loss, then makes
    /// a best-effort protected marker advance without delaying disconnect UI.
    func quarantineTrackedBatches(_ batches: [OutboundAttachmentBatch]) {
        for batch in batches {
            quarantinedOwners.insert(batch.owner)
            guard let marker = markers[batch.id],
                  marker.stage != .quarantineOnly else {
                continue
            }
            let quarantined = marker.advancing(to: .quarantineOnly)
            markers[marker.id] = quarantined
            persistQuarantineAdvance(from: marker, to: quarantined)
        }
    }
}
