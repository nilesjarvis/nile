import Foundation

/// Owns protected attachment drafts and mutation-marker persistence.
///
/// `SessionListModel` retains visible composer and transcript orchestration.
/// This runtime is the only session feature object that owns
/// `AttachmentDraftStoring`, mirrors durable attachment state, sequences draft
/// revisions and timestamps, or fences recovered-marker edit writes. Async
/// storage transactions live in its same-type transaction extension.
@MainActor
final class SessionAttachmentPersistenceRuntime {
    struct RestoreResult: Equatable, Sendable {
        let recoveredOwners: Set<ComposerDraftOwner>
    }

    typealias CommitGuard = @MainActor @Sendable () -> Bool
    typealias RecoveredEditFailure = @MainActor @Sendable
        ([AttachmentMutationMarker]) -> Void

    let store: (any AttachmentDraftStoring)?
    let nowMilliseconds: @MainActor @Sendable () -> Int64
    let recoveredEditRuntime: SessionAttachmentRecoveredEditRuntime
    var drafts: [ComposerDraftOwner: [PendingAttachment]] = [:]
    var records: [
        ComposerDraftOwner: PersistedAttachmentDraft
    ] = [:]
    var markers: [String: AttachmentMutationMarker] = [:]
    var restoredOwners: Set<ComposerDraftOwner> = []
    var quarantinedOwners: Set<ComposerDraftOwner> = []
    var lastTimestamp: Int64 = 0

    init(
        store: (any AttachmentDraftStoring)?,
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.store = store
        self.nowMilliseconds = nowMilliseconds
        recoveredEditRuntime = SessionAttachmentRecoveredEditRuntime()
    }

    func seedDraft(
        owner: ComposerDraftOwner,
        attachments: [PendingAttachment]
    ) {
        drafts[owner] = attachments
    }

    func draft(for owner: ComposerDraftOwner) -> [PendingAttachment] {
        drafts[owner] ?? []
    }

    func record(
        for owner: ComposerDraftOwner
    ) -> PersistedAttachmentDraft? {
        records[owner]
    }

    func marker(id: String) -> AttachmentMutationMarker? {
        markers[id]
    }

    func markers(
        for owner: ComposerDraftOwner,
        stage: AttachmentMutationStage? = nil
    ) -> [AttachmentMutationMarker] {
        markers.values.filter {
            $0.owner == owner && (stage == nil || $0.stage == stage)
        }.sorted { $0.id < $1.id }
    }

    func markerOwners(gatewayID: String) -> [ComposerDraftOwner] {
        markers.values.compactMap {
            $0.gatewayID == gatewayID ? $0.owner : nil
        }
    }

    func draftOwners(gatewayID: String) -> [ComposerDraftOwner] {
        drafts.compactMap { owner, attachments in
            owner.gatewayID == gatewayID && !attachments.isEmpty
                ? owner
                : nil
        }
    }

    func containsMarker(_ marker: AttachmentMutationMarker) -> Bool {
        markers[marker.id] == marker
    }

    func replaceDraft(
        for owner: ComposerDraftOwner,
        with attachments: [PendingAttachment]
    ) {
        drafts[owner] = attachments
    }

    func markRestored(owner: ComposerDraftOwner) {
        restoredOwners.insert(owner)
    }

    func consumeRestored(owner: ComposerDraftOwner) -> Bool {
        restoredOwners.remove(owner) != nil
    }

    func isQuarantined(owner: ComposerDraftOwner) -> Bool {
        quarantinedOwners.contains(owner)
    }

    func quarantine(owner: ComposerDraftOwner) {
        quarantinedOwners.insert(owner)
    }

    func releaseQuarantine(owner: ComposerDraftOwner) {
        quarantinedOwners.remove(owner)
    }

    func resetQuarantine() {
        quarantinedOwners.removeAll()
    }
}
