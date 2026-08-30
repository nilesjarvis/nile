import Foundation
@testable import Nile

actor ComposerDraftStoreStub: ComposerDraftStoring {
    private var records: [ComposerDraftOwner: PersistedComposerDraft]
    private let failsUpdates: Bool
    private(set) var updatedTexts: [String] = []

    init(
        records: [PersistedComposerDraft] = [],
        failsUpdates: Bool = false
    ) {
        self.records = Dictionary(
            uniqueKeysWithValues: records.map { ($0.owner, $0) }
        )
        self.failsUpdates = failsUpdates
    }

    func load() -> [PersistedComposerDraft] {
        Array(records.values)
    }

    func update(_ draft: PersistedComposerDraft) throws -> Bool {
        if failsUpdates {
            throw ComposerDraftStoreError.storageAccess
        }
        if let current = records[draft.owner] {
            if current.revision > draft.revision {
                return false
            }
            if current.revision == draft.revision {
                return current == draft
            }
        }
        records[draft.owner] = draft
        updatedTexts.append(draft.text)
        return true
    }

    func migrate(_ changes: [ComposerDraftMigrationChange]) throws -> Bool {
        if failsUpdates {
            throw ComposerDraftStoreError.storageAccess
        }
        for change in changes {
            guard records[change.owner] == change.expected else {
                return false
            }
        }
        for change in changes {
            records[change.owner] = change.replacement
            updatedTexts.append(change.replacement.text)
        }
        return true
    }

    func removeGateway(id: String) {
        records = records.filter { $0.key.gatewayID != id }
    }

    func record(
        gatewayID: String,
        storedSessionID: String
    ) -> PersistedComposerDraft? {
        records[
            ComposerDraftOwner(
                gatewayID: gatewayID,
                storedSessionID: storedSessionID
            )
        ]
    }
}

actor AttachmentDraftStoreStub: AttachmentDraftStoring {
    private var drafts: [ComposerDraftOwner: PersistedAttachmentDraft]
    private var markers: [String: AttachmentMutationMarker]
    private let failsDraftUpdates: Bool
    private let migrationReturnsFalse: Bool
    private let mutationBeginReturnsFalse: Bool
    private let blocksMigration: Bool
    private var migrationContinuation:
        CheckedContinuation<Void, Never>?
    private(set) var migrationCallCount = 0
    private let blockedDraftUpdateNumbers: Set<Int>
    private var draftUpdateContinuations: [
        Int: CheckedContinuation<Void, Never>
    ] = [:]
    private(set) var draftUpdateCallCount = 0
    private(set) var completedDraftUpdateCount = 0

    init(
        snapshot: AttachmentRecoverySnapshot = AttachmentRecoverySnapshot(
            drafts: [],
            markers: []
        ),
        failsDraftUpdates: Bool = false,
        migrationReturnsFalse: Bool = false,
        mutationBeginReturnsFalse: Bool = false,
        blocksMigration: Bool = false,
        blockedDraftUpdateNumbers: Set<Int> = []
    ) {
        drafts = Dictionary(
            uniqueKeysWithValues: snapshot.drafts.map { ($0.owner, $0) }
        )
        markers = Dictionary(
            uniqueKeysWithValues: snapshot.markers.map { ($0.id, $0) }
        )
        self.failsDraftUpdates = failsDraftUpdates
        self.migrationReturnsFalse = migrationReturnsFalse
        self.mutationBeginReturnsFalse = mutationBeginReturnsFalse
        self.blocksMigration = blocksMigration
        self.blockedDraftUpdateNumbers = blockedDraftUpdateNumbers
    }

    func load() -> AttachmentRecoverySnapshot {
        snapshot()
    }

    func updateDraft(_ draft: PersistedAttachmentDraft) async -> Bool {
        draftUpdateCallCount += 1
        let call = draftUpdateCallCount
        if blockedDraftUpdateNumbers.contains(call) {
            await withCheckedContinuation { continuation in
                draftUpdateContinuations[call] = continuation
            }
        }
        defer { completedDraftUpdateCount += 1 }
        guard !failsDraftUpdates else {
            return false
        }
        if let current = drafts[draft.owner] {
            if current.revision > draft.revision {
                return false
            }
            if current.revision == draft.revision {
                return current == draft
            }
        }
        drafts[draft.owner] = draft
        return true
    }

    func releaseDraftUpdate(_ call: Int) {
        draftUpdateContinuations.removeValue(forKey: call)?.resume()
    }

    func beginMutation(
        _ marker: AttachmentMutationMarker,
        replacingMarkerIDs: Set<String>,
        expectedDraft: PersistedAttachmentDraft?,
        tombstone: PersistedAttachmentDraft
    ) -> Bool {
        guard !mutationBeginReturnsFalse else {
            return false
        }
        if let expectedDraft, drafts[marker.owner] != expectedDraft {
            return false
        }
        for id in replacingMarkerIDs {
            markers.removeValue(forKey: id)
        }
        markers[marker.id] = marker
        drafts[tombstone.owner] = tombstone
        return true
    }

    func advanceMutation(
        from expected: AttachmentMutationMarker,
        to replacement: AttachmentMutationMarker
    ) -> Bool {
        guard markers[expected.id] == expected else {
            return false
        }
        markers[replacement.id] = replacement
        return true
    }

    func recoverMutation(
        _ expected: AttachmentMutationMarker,
        as draft: PersistedAttachmentDraft
    ) -> Bool {
        guard markers[expected.id] == expected else {
            return false
        }
        markers.removeValue(forKey: expected.id)
        drafts[draft.owner] = draft
        return true
    }

    func migrateRecoveredDraft(
        mutations: [AttachmentMutationMigration],
        draftChanges: [AttachmentDraftMigrationChange],
        commitGuard: @escaping @MainActor @Sendable () -> Bool
    ) async -> Bool {
        migrationCallCount += 1
        if blocksMigration {
            await withCheckedContinuation { continuation in
                migrationContinuation = continuation
            }
        }
        guard !migrationReturnsFalse else {
            return false
        }
        guard await commitGuard() else {
            return false
        }
        for mutation in mutations {
            guard markers[mutation.expected.id] == mutation.expected else {
                return false
            }
        }
        for change in draftChanges {
            guard drafts[change.owner] == change.expected else {
                return false
            }
        }
        for mutation in mutations {
            markers[mutation.replacement.id] = mutation.replacement
        }
        for change in draftChanges {
            drafts[change.owner] = change.replacement
        }
        return true
    }

    func releaseMigration() {
        migrationContinuation?.resume()
        migrationContinuation = nil
    }

    func clearMutation(_ expected: AttachmentMutationMarker) -> Bool {
        guard markers[expected.id] == expected else {
            return false
        }
        markers.removeValue(forKey: expected.id)
        return true
    }

    func removeGateway(id: String) {
        drafts = drafts.filter { $0.key.gatewayID != id }
        markers = markers.filter { $0.value.gatewayID != id }
    }

    func snapshot() -> AttachmentRecoverySnapshot {
        AttachmentRecoverySnapshot(
            drafts: drafts.values.sorted {
                $0.storedSessionID < $1.storedSessionID
            },
            markers: markers.values.sorted { $0.id < $1.id }
        )
    }
}
