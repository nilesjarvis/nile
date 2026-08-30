import Foundation

/// Executes exact protected attachment-record transactions against the store
/// actor's single envelope, validation policy, and gateway-removal fence.
extension ProtectedAttachmentDraftStore {
    func load() throws -> AttachmentRecoverySnapshot {
        let envelope = try loadEnvelope()
        return AttachmentRecoverySnapshot(
            drafts: envelope.drafts,
            markers: envelope.markers
        )
    }

    func updateDraft(_ draft: PersistedAttachmentDraft) throws -> Bool {
        try Self.validate(draft)
        guard permitsGateway(draft.gatewayID) else {
            return false
        }
        var envelope = try loadEnvelope()
        guard Self.apply(draft, to: &envelope.drafts) else {
            return false
        }
        try writeOrRemove(envelope)
        return true
    }

    func beginMutation(
        _ marker: AttachmentMutationMarker,
        replacingMarkerIDs: Set<String>,
        expectedDraft: PersistedAttachmentDraft?,
        tombstone: PersistedAttachmentDraft
    ) throws -> Bool {
        try Self.validate(marker)
        try Self.validate(tombstone)
        guard marker.stage == .uploadPending,
              marker.owner == tombstone.owner,
              tombstone.attachments.isEmpty,
              permitsGateway(marker.gatewayID) else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        var envelope = try loadEnvelope()
        if let expectedDraft {
            guard envelope.drafts.first(where: {
                $0.owner == expectedDraft.owner
            }) == expectedDraft else {
                return false
            }
        } else if envelope.drafts.contains(where: {
            $0.owner == marker.owner && !$0.attachments.isEmpty
        }) {
            return false
        }
        guard !envelope.markers.contains(where: {
            $0.id == marker.id && $0 != marker
        }) else {
            return false
        }
        envelope.markers.removeAll { replacingMarkerIDs.contains($0.id) }
        if !envelope.markers.contains(marker) {
            envelope.markers.append(marker)
        }
        guard Self.apply(tombstone, to: &envelope.drafts) else {
            return false
        }
        try write(envelope)
        return true
    }

    func advanceMutation(
        from expected: AttachmentMutationMarker,
        to replacement: AttachmentMutationMarker
    ) throws -> Bool {
        try Self.validate(expected)
        try Self.validate(replacement)
        guard expected.id == replacement.id,
              expected.owner == replacement.owner else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        var envelope = try loadEnvelope()
        guard let index = envelope.markers.firstIndex(of: expected) else {
            return false
        }
        envelope.markers[index] = replacement
        try write(envelope)
        return true
    }

    func recoverMutation(
        _ expected: AttachmentMutationMarker,
        as draft: PersistedAttachmentDraft
    ) throws -> Bool {
        try Self.validate(expected)
        try Self.validate(draft)
        guard expected.owner == draft.owner else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        var envelope = try loadEnvelope()
        guard let markerIndex = envelope.markers.firstIndex(of: expected) else {
            return false
        }
        guard Self.apply(draft, to: &envelope.drafts) else {
            return false
        }
        envelope.markers.remove(at: markerIndex)
        try write(envelope)
        return true
    }

    func migrateRecoveredDraft(
        mutations: [AttachmentMutationMigration],
        draftChanges: [AttachmentDraftMigrationChange],
        commitGuard: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> Bool {
        guard !mutations.isEmpty || !draftChanges.isEmpty else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        var markerIDs: Set<String> = []
        for mutation in mutations {
            try Self.validate(mutation.expected)
            try Self.validate(mutation.replacement)
            guard markerIDs.insert(mutation.expected.id).inserted,
                  mutation.replacement.id == mutation.expected.id,
                  mutation.expected.gatewayID
                    == mutation.replacement.gatewayID,
                  mutation.expected.stage == .draftRecovered,
                  mutation.replacement.stage == .draftRecovered,
                  permitsGateway(mutation.expected.gatewayID) else {
                throw AttachmentDraftStoreError.invalidRecord
            }
        }
        let mutationGatewayIDs = Set(
            mutations.map(\.expected.gatewayID)
        )
        let sourceOwners = Set(mutations.map(\.expected.owner))
        let replacementOwners = Set(mutations.map(\.replacement.owner))
        guard mutationGatewayIDs.count <= 1,
              sourceOwners.count <= 1,
              replacementOwners.count <= 1 else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        var draftOwners: Set<ComposerDraftOwner> = []
        for change in draftChanges {
            guard draftOwners.insert(change.owner).inserted,
                  change.replacement.owner == change.owner else {
                throw AttachmentDraftStoreError.invalidRecord
            }
            try Self.validate(change.replacement)
            if let expected = change.expected {
                guard expected.owner == change.owner else {
                    throw AttachmentDraftStoreError.invalidRecord
                }
                try Self.validate(expected)
            }
            guard permitsGateway(change.owner.gatewayID) else {
                return false
            }
        }
        let draftGatewayIDs = Set(draftChanges.map(\.owner.gatewayID))
        guard draftGatewayIDs.count <= 1,
              mutationGatewayIDs.isEmpty
                || draftGatewayIDs.isEmpty
                || mutationGatewayIDs == draftGatewayIDs else {
            throw AttachmentDraftStoreError.invalidRecord
        }

        guard await commitGuard() else {
            return false
        }
        // Reload after the actor hop so no reentrant store operation can make a
        // pre-guard snapshot stale.
        var envelope = try loadEnvelope()
        for mutation in mutations {
            guard envelope.markers.contains(mutation.expected) else {
                return false
            }
        }
        for change in draftChanges {
            let current = envelope.drafts.first {
                $0.owner == change.owner
            }
            guard current == change.expected else {
                return false
            }
        }
        for mutation in mutations {
            guard let index = envelope.markers.firstIndex(
                of: mutation.expected
            ) else {
                return false
            }
            envelope.markers[index] = mutation.replacement
        }
        for change in draftChanges {
            if let index = envelope.drafts.firstIndex(where: {
                $0.owner == change.owner
            }) {
                envelope.drafts[index] = change.replacement
            } else {
                envelope.drafts.append(change.replacement)
            }
        }
        try write(envelope)
        return true
    }

    func clearMutation(_ expected: AttachmentMutationMarker) throws -> Bool {
        try Self.validate(expected)
        var envelope = try loadEnvelope()
        guard let index = envelope.markers.firstIndex(of: expected) else {
            return false
        }
        envelope.markers.remove(at: index)
        try writeOrRemove(envelope)
        return true
    }

    func removeGateway(id: String) throws {
        retireGatewayID(id)
        var envelope = try loadEnvelope()
        envelope.drafts.removeAll { $0.gatewayID == id }
        envelope.markers.removeAll { $0.gatewayID == id }
        try writeOrRemove(envelope)
    }
}
