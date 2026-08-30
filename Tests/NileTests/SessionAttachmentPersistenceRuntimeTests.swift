import XCTest
@testable import Nile

@MainActor
final class SessionAttachmentPersistenceRuntimeTests: XCTestCase {
    func testDraftUpdatesOwnRevisionTimestampAndRuntimeProjection() async {
        let store = AttachmentPersistenceStoreStub()
        let clock = AttachmentPersistenceClock(100)
        let runtime = makeRuntime(store: store, clock: clock)
        let owner = makeOwner()
        let firstAttachment = makeAttachment(id: "one")
        let secondAttachment = makeAttachment(id: "two")

        let first = runtime.makeDraft(
            owner: owner,
            attachments: [firstAttachment]
        )
        let persistedFirst = await runtime.updateDraft(first)
        XCTAssertTrue(persistedFirst)
        let second = runtime.makeDraft(
            owner: owner,
            attachments: [firstAttachment, secondAttachment]
        )
        let persistedSecond = await runtime.updateDraft(second)
        XCTAssertTrue(persistedSecond)

        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.updatedAtMilliseconds, 100)
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(second.updatedAtMilliseconds, 101)
        XCTAssertEqual(runtime.record(for: owner), second)
        XCTAssertEqual(runtime.draft(for: owner), second.attachments)
        let stored = await store.record(for: owner)
        XCTAssertEqual(stored, second)
    }

    func testRestoreFiltersGatewayAndClassifiesMarkerOwnership() async throws {
        let owner = makeOwner()
        let quarantinedOwner = makeOwner(storedSessionID: "quarantined")
        let otherOwner = makeOwner(gatewayID: "other")
        let draft = makeRecord(
            owner: owner,
            revision: 3,
            attachments: [makeAttachment(id: "draft")]
        )
        let recovered = makeMarker(owner: owner, stage: .draftRecovered)
        let quarantined = makeMarker(
            owner: quarantinedOwner,
            id: "quarantined-marker",
            stage: .quarantineOnly
        )
        let unrelated = makeRecord(
            owner: otherOwner,
            revision: 9,
            attachments: [makeAttachment(id: "hidden")]
        )
        let store = AttachmentPersistenceStoreStub(
            drafts: [draft, unrelated],
            markers: [recovered, quarantined]
        )
        let runtime = makeRuntime(store: store)

        let result = try await runtime.restore(gatewayID: owner.gatewayID)

        XCTAssertEqual(result.recoveredOwners, [owner])
        XCTAssertEqual(runtime.draft(for: owner), draft.attachments)
        XCTAssertTrue(runtime.consumeRestored(owner: owner))
        XCTAssertTrue(runtime.isQuarantined(owner: quarantinedOwner))
        XCTAssertNil(runtime.record(for: otherOwner))
    }

    func testMutationHandoffAdvanceAndRecoveryUpdateOneAuthority() async {
        let owner = makeOwner()
        let store = AttachmentPersistenceStoreStub()
        let runtime = makeRuntime(store: store)
        let attachment = makeAttachment()
        let initial = runtime.makeDraft(
            owner: owner,
            attachments: [attachment]
        )
        let persistedInitial = await runtime.updateDraft(initial)
        XCTAssertTrue(persistedInitial)
        let marker = makeMarker(owner: owner, attachments: [attachment])
        let tombstone = runtime.makeDraft(owner: owner, attachments: [])

        let began = await runtime.beginMutation(
            marker,
            replacingMarkerIDs: [],
            expectedDraft: initial,
            tombstone: tombstone
        )
        XCTAssertTrue(began)
        XCTAssertTrue(runtime.draft(for: owner).isEmpty)
        XCTAssertEqual(runtime.marker(id: marker.id), marker)

        let promptPending = marker.advancing(to: .promptPending)
        let advanced = await runtime.advanceMutation(
            from: marker,
            to: promptPending
        )
        XCTAssertTrue(advanced)
        XCTAssertEqual(runtime.marker(id: marker.id), promptPending)

        let recovered = runtime.makeDraft(
            owner: owner,
            attachments: [attachment]
        )
        let didRecover = await runtime.recoverMutation(
            promptPending,
            as: recovered
        )
        XCTAssertTrue(didRecover)
        XCTAssertNil(runtime.marker(id: marker.id))
        XCTAssertEqual(runtime.record(for: owner), recovered)
        XCTAssertEqual(runtime.draft(for: owner), [attachment])
    }

    func testRecoveredMigrationCommitsMarkersRecordsAndProjectionTogether()
        async throws
    {
        let source = makeOwner(storedSessionID: "missing")
        let target = makeOwner(storedSessionID: "created")
        let recoveredPhoto = makeAttachment(id: "recovered")
        let ordinaryPhoto = makeAttachment(id: "ordinary")
        let sourceRecord = makeRecord(
            owner: source,
            revision: 4,
            attachments: [ordinaryPhoto],
            timestamp: 40
        )
        let targetRecord = makeRecord(
            owner: target,
            revision: 2,
            attachments: [],
            timestamp: 50
        )
        let marker = makeMarker(
            owner: source,
            attachments: [recoveredPhoto],
            stage: .draftRecovered
        )
        let replacement = marker.retargeting(
            storedSessionID: target.storedSessionID,
            liveSessionID: "live-created",
            input: marker.input,
            attachments: marker.attachments
        )
        let store = AttachmentPersistenceStoreStub(
            drafts: [sourceRecord, targetRecord],
            markers: [marker]
        )
        let clock = AttachmentPersistenceClock(500)
        let runtime = makeRuntime(store: store, clock: clock)
        _ = try await runtime.restore(gatewayID: source.gatewayID)

        let migrated = await runtime.migrateRecoveredDraft(
            mutations: [
                AttachmentMutationMigration(
                    expected: marker,
                    replacement: replacement
                )
            ],
            from: source,
            to: target,
            ordinaryAttachments: [ordinaryPhoto],
            visibleAttachments: [recoveredPhoto, ordinaryPhoto],
            commitGuard: { true }
        )

        XCTAssertTrue(migrated)
        XCTAssertEqual(runtime.marker(id: marker.id), replacement)
        XCTAssertTrue(runtime.draft(for: source).isEmpty)
        XCTAssertEqual(
            runtime.draft(for: target),
            [recoveredPhoto, ordinaryPhoto]
        )
        XCTAssertEqual(runtime.record(for: source)?.attachments, [])
        XCTAssertEqual(
            runtime.record(for: target)?.attachments,
            [ordinaryPhoto]
        )
        XCTAssertEqual(runtime.record(for: source)?.revision, 5)
        XCTAssertEqual(runtime.record(for: target)?.revision, 6)
        let storedMarkers = await store.snapshot().markers
        XCTAssertEqual(storedMarkers, [replacement])
    }

    func testRecoveredEditRetriesLatestSnapshotAndPublishesReplacement()
        async
    {
        let owner = makeOwner()
        let marker = makeMarker(owner: owner, stage: .draftRecovered)
        let externallyAdvanced = marker.retargeting(
            storedSessionID: marker.storedSessionID,
            liveSessionID: marker.liveSessionID,
            input: "external",
            attachments: marker.attachments
        )
        let store = AttachmentPersistenceStoreStub(
            markers: [externallyAdvanced]
        )
        let runtime = makeRuntime(store: store)
        var failures = 0

        runtime.scheduleRecoveredMarkerEdit(
            owner: owner,
            markers: [marker],
            text: "latest",
            isCurrent: { true },
            onFailure: { _ in failures += 1 }
        )

        await eventually {
            runtime.marker(id: marker.id)?.input == "latest"
        }
        XCTAssertEqual(failures, 0)
        let storedInput = await store.snapshot().markers.first?.input
        let migrationCallCount = await store.migrationCallCount
        XCTAssertEqual(storedInput, "latest")
        XCTAssertEqual(migrationCallCount, 2)
    }

    func testTrackedQuarantineImmediatelyLocksOwnerAndAdvancesMarker()
        async
    {
        let owner = makeOwner()
        let marker = makeMarker(owner: owner)
        let store = AttachmentPersistenceStoreStub(markers: [marker])
        let runtime = makeRuntime(store: store)
        _ = try? await runtime.restore(gatewayID: owner.gatewayID)
        let batch = OutboundAttachmentBatch(
            id: marker.id,
            owner: owner,
            liveSessionID: marker.liveSessionID,
            input: marker.input,
            attachments: marker.attachments,
            userEntryID: marker.userEntryID,
            userMessagesBefore: marker.userMessagesBefore
        )

        runtime.quarantineTrackedBatches([batch])

        XCTAssertTrue(runtime.isQuarantined(owner: owner))
        XCTAssertEqual(runtime.marker(id: marker.id)?.stage, .quarantineOnly)
        await eventually {
            await store.snapshot().markers.first?.stage == .quarantineOnly
        }
    }

    private func makeRuntime(
        store: AttachmentPersistenceStoreStub,
        clock: AttachmentPersistenceClock = AttachmentPersistenceClock(1_000)
    ) -> SessionAttachmentPersistenceRuntime {
        SessionAttachmentPersistenceRuntime(
            store: store,
            nowMilliseconds: { clock.now() }
        )
    }

    private func makeOwner(
        gatewayID: String = "gateway",
        storedSessionID: String = "session"
    ) -> ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }

    private func makeAttachment(id: String = "photo") -> PendingAttachment {
        PendingAttachment(
            id: id,
            filename: "\(id).jpg",
            data: Data(id.utf8)
        )
    }

    private func makeRecord(
        owner: ComposerDraftOwner,
        revision: Int64,
        attachments: [PendingAttachment],
        timestamp: Int64 = 100
    ) -> PersistedAttachmentDraft {
        PersistedAttachmentDraft(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            revision: revision,
            attachments: attachments,
            updatedAtMilliseconds: timestamp
        )
    }

    private func makeMarker(
        owner: ComposerDraftOwner,
        id: String = "mutation",
        attachments: [PendingAttachment]? = nil,
        stage: AttachmentMutationStage = .uploadPending
    ) -> AttachmentMutationMarker {
        AttachmentMutationMarker(
            id: id,
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "live-session",
            input: "prompt",
            attachments: attachments ?? [makeAttachment()],
            userEntryID: "user-entry",
            userMessagesBefore: 2,
            stage: stage
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class AttachmentPersistenceClock {
    private var value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    func now() -> Int64 {
        defer { value += 1 }
        return value
    }
}

private actor AttachmentPersistenceStoreStub: AttachmentDraftStoring {
    private var drafts: [ComposerDraftOwner: PersistedAttachmentDraft]
    private var markers: [String: AttachmentMutationMarker]
    private(set) var migrationCallCount = 0

    init(
        drafts: [PersistedAttachmentDraft] = [],
        markers: [AttachmentMutationMarker] = []
    ) {
        self.drafts = Dictionary(
            uniqueKeysWithValues: drafts.map { ($0.owner, $0) }
        )
        self.markers = Dictionary(
            uniqueKeysWithValues: markers.map { ($0.id, $0) }
        )
    }

    func snapshot() -> AttachmentRecoverySnapshot {
        AttachmentRecoverySnapshot(
            drafts: drafts.values.sorted {
                $0.storedSessionID < $1.storedSessionID
            },
            markers: markers.values.sorted { $0.id < $1.id }
        )
    }

    func record(
        for owner: ComposerDraftOwner
    ) -> PersistedAttachmentDraft? {
        drafts[owner]
    }

    func load() -> AttachmentRecoverySnapshot {
        snapshot()
    }

    func updateDraft(_ draft: PersistedAttachmentDraft) -> Bool {
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

    func beginMutation(
        _ marker: AttachmentMutationMarker,
        replacingMarkerIDs: Set<String>,
        expectedDraft: PersistedAttachmentDraft?,
        tombstone: PersistedAttachmentDraft
    ) -> Bool {
        guard drafts[marker.owner] == expectedDraft else {
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
}
