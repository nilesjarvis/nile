import Foundation

/// Owns protected composer-draft records and exact transactions.
///
/// `SessionDraftLifecycleRuntime` composes this authority with the composer
/// projection for ordinary restoration, claim, and recovery transactions. This
/// runtime alone declares `ComposerDraftStoring`, versions records, sequences
/// timestamps, and owns replaceable write tasks; a same-runtime extension
/// executes debounced writes without another state authority.
@MainActor
final class SessionDraftPersistenceRuntime {
    typealias FailureHandler = @MainActor @Sendable
        (ComposerDraftOwner, String) -> Void
    typealias RetirementHandler = @MainActor @Sendable (String) -> Void

    struct WriteOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    let store: (any ComposerDraftStoring)?
    let nowMilliseconds: @MainActor @Sendable () -> Int64
    var records: [ComposerDraftOwner: PersistedComposerDraft] = [:]
    var writeOperations: [ComposerDraftOwner: WriteOperation] = [:]
    var lastTimestamp: Int64 = 0

    init(
        store: (any ComposerDraftStoring)?,
        nowMilliseconds: @escaping @MainActor @Sendable () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) {
        self.store = store
        self.nowMilliseconds = nowMilliseconds
    }

    isolated deinit {
        writeOperations.values.forEach { $0.task.cancel() }
    }

    func record(for owner: ComposerDraftOwner) -> PersistedComposerDraft? {
        records[owner]
    }

    /// Loads and merges only newer records for the requested gateway.
    /// Returned records are exactly those newly accepted into runtime state.
    func restore(gatewayID: String) async throws -> [PersistedComposerDraft] {
        guard let store else {
            return []
        }
        let loaded = try await store.load()
        var restored: [PersistedComposerDraft] = []
        for record in loaded where record.gatewayID == gatewayID {
            lastTimestamp = max(lastTimestamp, record.updatedAtMilliseconds)
            if let current = records[record.owner],
               current.revision >= record.revision {
                continue
            }
            records[record.owner] = record
            restored.append(record)
        }
        return restored
    }

    func captureClaim(
        owner: ComposerDraftOwner,
        fallbackText: String
    ) -> PersistedComposerDraft? {
        if let current = records[owner], !current.text.isEmpty {
            return current
        }
        guard store != nil else {
            return nil
        }
        let record = makeRecord(owner: owner, text: fallbackText)
        records[owner] = record
        return record
    }

    func flushClaim(
        owner: ComposerDraftOwner,
        claim: PersistedComposerDraft?
    ) async -> Bool {
        writeOperations.removeValue(forKey: owner)?.task.cancel()
        guard let claim,
              records[owner] == claim,
              let store else {
            return true
        }
        do {
            return try await store.update(claim)
        } catch {
            return false
        }
    }

    /// Retires the exact claim while preserving a newer draft typed during the
    /// remote operation. The callbacks let the model mirror the transient
    /// visible clear and the exact rollback without owning persistence state.
    func retireClaim(
        owner: ComposerDraftOwner,
        claim: PersistedComposerDraft?,
        onRetiring: @escaping RetirementHandler,
        onRollback: @escaping RetirementHandler,
        onFailure: @escaping FailureHandler
    ) async {
        guard let claim,
              records[owner] == claim,
              let store else {
            return
        }
        writeOperations.removeValue(forKey: owner)?.task.cancel()
        let tombstone = makeRecord(owner: owner, text: "")
        records[owner] = tombstone
        onRetiring(claim.text)

        let retired: Bool
        do {
            retired = try await store.update(tombstone)
        } catch {
            retired = false
        }
        guard !retired, records[owner] == tombstone else {
            return
        }
        records[owner] = claim
        onRollback(claim.text)
        onFailure(
            owner,
            "Nile sent the message but could not retire its recovery draft. Check the conversation before resending."
        )
    }

    /// Moves an ordinary recovered draft to a newly created session with one
    /// exact-owner protected-file CAS. A source tombstone and target record use
    /// the same monotonic timestamp, matching the attachment migration commit.
    func migrateRecoveredDraft(
        from sourceOwner: ComposerDraftOwner,
        to targetOwner: ComposerDraftOwner,
        targetText: String
    ) async -> Bool {
        let source = records[sourceOwner]
        let target = records[targetOwner]
        guard source != nil || target != nil else {
            return true
        }
        guard let store else {
            return false
        }
        let timestamp = max(
            nowMilliseconds(),
            lastTimestamp + 1,
            (source?.updatedAtMilliseconds ?? -1) + 1,
            (target?.updatedAtMilliseconds ?? -1) + 1
        )
        lastTimestamp = timestamp
        var changes: [ComposerDraftMigrationChange] = []
        if let source {
            changes.append(
                ComposerDraftMigrationChange(
                    owner: sourceOwner,
                    expected: source,
                    replacement: PersistedComposerDraft(
                        gatewayID: sourceOwner.gatewayID,
                        storedSessionID: sourceOwner.storedSessionID,
                        revision: source.revision + 1,
                        text: "",
                        updatedAtMilliseconds: timestamp
                    )
                )
            )
        }
        changes.append(
            ComposerDraftMigrationChange(
                owner: targetOwner,
                expected: target,
                replacement: PersistedComposerDraft(
                    gatewayID: targetOwner.gatewayID,
                    storedSessionID: targetOwner.storedSessionID,
                    revision: max(
                        source?.revision ?? 0,
                        target?.revision ?? 0
                    ) + 2,
                    text: targetText,
                    updatedAtMilliseconds: timestamp
                )
            )
        )

        let migrated: Bool
        do {
            migrated = try await store.migrate(changes)
        } catch {
            return false
        }
        guard migrated else {
            return false
        }
        for change in changes {
            records[change.owner] = change.replacement
        }
        return true
    }

    /// Persists a tombstone for a record already absorbed by attachment
    /// recovery. Runtime state advances only after protected storage accepts it.
    func retireStoredDraft(owner: ComposerDraftOwner) async -> Bool {
        guard let current = records[owner],
              !current.text.isEmpty,
              let store else {
            return false
        }
        let tombstone = makeRecord(owner: owner, text: "")
        let retired: Bool
        do {
            retired = try await store.update(tombstone)
        } catch {
            retired = false
        }
        if retired {
            records[owner] = tombstone
        }
        return retired
    }

    func makeRecord(
        owner: ComposerDraftOwner,
        text: String
    ) -> PersistedComposerDraft {
        let previous = records[owner]
        let timestamp = max(
            nowMilliseconds(),
            lastTimestamp + 1,
            (previous?.updatedAtMilliseconds ?? -1) + 1
        )
        lastTimestamp = timestamp
        return PersistedComposerDraft(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            revision: (previous?.revision ?? 0) + 1,
            text: text,
            updatedAtMilliseconds: timestamp
        )
    }
}
