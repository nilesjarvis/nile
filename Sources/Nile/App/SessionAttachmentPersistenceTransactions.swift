import Foundation

/// Executes protected attachment-draft transactions for the state authority
/// declared by `SessionAttachmentPersistenceRuntime`.
@MainActor
extension SessionAttachmentPersistenceRuntime {
    func migrateRecoveredState(
        mutations: [AttachmentMutationMigration],
        draftChanges: [AttachmentDraftMigrationChange],
        commitGuard: @escaping CommitGuard
    ) async -> Bool {
        guard let store else {
            return false
        }
        do {
            return try await store.migrateRecoveredDraft(
                mutations: mutations,
                draftChanges: draftChanges,
                commitGuard: commitGuard
            )
        } catch {
            return false
        }
    }

    func loadRecoverySnapshot() async -> AttachmentRecoverySnapshot? {
        guard let store else {
            return nil
        }
        return try? await store.load()
    }

    func persistQuarantineAdvance(
        from marker: AttachmentMutationMarker,
        to quarantined: AttachmentMutationMarker
    ) {
        guard let store else {
            return
        }
        Task {
            _ = try? await store.advanceMutation(
                from: marker,
                to: quarantined
            )
        }
    }

    func makeDraft(
        owner: ComposerDraftOwner,
        attachments: [PendingAttachment]
    ) -> PersistedAttachmentDraft {
        let previous = records[owner]
        let timestamp = max(
            nowMilliseconds(),
            lastTimestamp + 1,
            (previous?.updatedAtMilliseconds ?? -1) + 1
        )
        lastTimestamp = timestamp
        return PersistedAttachmentDraft(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            revision: (previous?.revision ?? 0) + 1,
            attachments: attachments,
            updatedAtMilliseconds: timestamp
        )
    }

    func updateDraft(_ draft: PersistedAttachmentDraft) async -> Bool {
        let persisted: Bool
        if let store {
            do {
                persisted = try await store.updateDraft(draft)
            } catch {
                persisted = false
            }
        } else {
            persisted = true
        }
        if persisted {
            records[draft.owner] = draft
            drafts[draft.owner] = draft.attachments
        }
        return persisted
    }

    func beginMutation(
        _ marker: AttachmentMutationMarker,
        replacingMarkerIDs: Set<String>,
        expectedDraft: PersistedAttachmentDraft?,
        tombstone: PersistedAttachmentDraft
    ) async -> Bool {
        let persisted: Bool
        if let store {
            do {
                persisted = try await store.beginMutation(
                    marker,
                    replacingMarkerIDs: replacingMarkerIDs,
                    expectedDraft: expectedDraft,
                    tombstone: tombstone
                )
            } catch {
                persisted = false
            }
        } else {
            persisted = true
        }
        guard persisted else {
            return false
        }
        for id in replacingMarkerIDs {
            markers.removeValue(forKey: id)
        }
        markers[marker.id] = marker
        records[marker.owner] = tombstone
        drafts[marker.owner] = []
        return true
    }

    func advanceMutation(
        from expected: AttachmentMutationMarker,
        to replacement: AttachmentMutationMarker
    ) async -> Bool {
        do {
            return try await advanceMutationPreservingError(
                from: expected,
                to: replacement
            )
        } catch {
            return false
        }
    }

    func advanceMutationPreservingError(
        from expected: AttachmentMutationMarker,
        to replacement: AttachmentMutationMarker
    ) async throws -> Bool {
        let persisted = if let store {
            try await store.advanceMutation(
                from: expected,
                to: replacement
            )
        } else {
            true
        }
        if persisted {
            markers[expected.id] = replacement
        }
        return persisted
    }

    func clearMutation(_ marker: AttachmentMutationMarker) async -> Bool {
        do {
            return try await clearMutationPreservingError(marker)
        } catch {
            return false
        }
    }

    func clearMutationPreservingError(
        _ marker: AttachmentMutationMarker
    ) async throws -> Bool {
        let persisted = if let store {
            try await store.clearMutation(marker)
        } else {
            true
        }
        if persisted {
            markers.removeValue(forKey: marker.id)
        }
        return persisted
    }

    func recoverMutation(
        _ marker: AttachmentMutationMarker,
        as draft: PersistedAttachmentDraft
    ) async -> Bool {
        let persisted: Bool
        if let store {
            do {
                persisted = try await store.recoverMutation(marker, as: draft)
            } catch {
                persisted = false
            }
        } else {
            persisted = true
        }
        guard persisted else {
            return false
        }
        markers.removeValue(forKey: marker.id)
        records[draft.owner] = draft
        drafts[draft.owner] = draft.attachments
        return true
    }

    /// Restores newer records for one gateway and classifies recovered versus
    /// still-uncertain marker ownership. Composer merging remains model-owned.
    func restore(gatewayID: String) async throws -> RestoreResult {
        guard let store else {
            return RestoreResult(recoveredOwners: [])
        }
        let snapshot = try await store.load()
        for record in snapshot.drafts where record.gatewayID == gatewayID {
            lastTimestamp = max(lastTimestamp, record.updatedAtMilliseconds)
            if let current = records[record.owner],
               current.revision >= record.revision {
                continue
            }
            records[record.owner] = record
            drafts[record.owner] = record.attachments
            if !record.attachments.isEmpty {
                restoredOwners.insert(record.owner)
            }
        }
        var recoveredOwners: Set<ComposerDraftOwner> = []
        for marker in snapshot.markers where marker.gatewayID == gatewayID {
            markers[marker.id] = marker
            if marker.stage == .draftRecovered {
                recoveredOwners.insert(marker.owner)
            } else {
                quarantinedOwners.insert(marker.owner)
            }
        }
        return RestoreResult(recoveredOwners: recoveredOwners)
    }
}
