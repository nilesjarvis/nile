import XCTest
@testable import Nile

final class AttachmentDraftStoreTests: XCTestCase {
    func testOrdinaryDraftMutationHandoffAndRecoveryAreAtomic() async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let original = draft(revision: 1, attachments: [photo("one")])
        let originalSaved = try await store.updateDraft(original)
        XCTAssertTrue(originalSaved)

        let marker = mutation(
            attachments: original.attachments,
            stage: .uploadPending
        )
        let tombstone = draft(revision: 2, attachments: [])
        let began = try await store.beginMutation(
            marker,
            replacingMarkerIDs: [],
            expectedDraft: original,
            tombstone: tombstone
        )
        XCTAssertTrue(began)
        var snapshot = try await store.load()
        XCTAssertEqual(snapshot.drafts, [tombstone])
        XCTAssertEqual(snapshot.markers, [marker])

        let promptPending = marker.advancing(to: .promptPending)
        let advanced = try await store.advanceMutation(
            from: marker,
            to: promptPending
        )
        XCTAssertTrue(advanced)
        let recovered = draft(
            revision: 3,
            attachments: marker.attachments
        )
        let mutationRecovered = try await store.recoverMutation(
            promptPending,
            as: recovered
        )
        XCTAssertTrue(mutationRecovered)
        snapshot = try await store.load()
        XCTAssertEqual(snapshot.drafts, [recovered])
        XCTAssertTrue(snapshot.markers.isEmpty)
    }

    func testStaleDraftAndMarkerCASCannotOverwriteCurrentAuthority() async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let first = draft(revision: 1, attachments: [photo("one")])
        let second = draft(revision: 2, attachments: [photo("two")])
        let firstSaved = try await store.updateDraft(first)
        let secondSaved = try await store.updateDraft(second)
        let staleSaved = try await store.updateDraft(first)
        XCTAssertTrue(firstSaved)
        XCTAssertTrue(secondSaved)
        XCTAssertFalse(staleSaved)

        let marker = mutation(
            attachments: second.attachments,
            stage: .uploadPending
        )
        let staleHandoff = try await store.beginMutation(
            marker,
            replacingMarkerIDs: [],
            expectedDraft: first,
            tombstone: draft(revision: 3, attachments: [])
        )
        XCTAssertFalse(staleHandoff)
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.drafts, [second])
    }

    func testMutationReplacementIsSingleCommit() async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let original = draft(revision: 1, attachments: [photo("old")])
        let originalSaved = try await store.updateDraft(original)
        XCTAssertTrue(originalSaved)
        let oldMarker = mutation(
            id: "old-marker",
            attachments: original.attachments,
            stage: .uploadPending
        )
        let beganOld = try await store.beginMutation(
            oldMarker,
            replacingMarkerIDs: [],
            expectedDraft: original,
            tombstone: draft(revision: 2, attachments: [])
        )
        XCTAssertTrue(beganOld)

        let replacementPhoto = photo("replacement")
        let recoveredDraft = draft(
            revision: 3,
            attachments: [replacementPhoto]
        )
        let recoveredSaved = try await store.updateDraft(recoveredDraft)
        XCTAssertTrue(recoveredSaved)
        let replacement = mutation(
            id: "new-marker",
            attachments: [replacementPhoto],
            stage: .uploadPending
        )
        let replaced = try await store.beginMutation(
            replacement,
            replacingMarkerIDs: [oldMarker.id],
            expectedDraft: recoveredDraft,
            tombstone: draft(revision: 4, attachments: [])
        )
        XCTAssertTrue(replaced)
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.markers, [replacement])
        XCTAssertEqual(snapshot.drafts, [draft(revision: 4, attachments: [])])
    }

    func testAcceptedMutationKeepsRevisionTombstoneAgainstLateWriter() async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let original = draft(revision: 1, attachments: [photo("one")])
        let originalSaved = try await store.updateDraft(original)
        XCTAssertTrue(originalSaved)
        let marker = mutation(
            attachments: original.attachments,
            stage: .uploadPending
        )
        let tombstone = draft(revision: 2, attachments: [])
        let began = try await store.beginMutation(
            marker,
            replacingMarkerIDs: [],
            expectedDraft: original,
            tombstone: tombstone
        )
        XCTAssertTrue(began)
        let cleared = try await store.clearMutation(marker)
        XCTAssertTrue(cleared)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.drafts, [tombstone])
        let staleSaved = try await store.updateDraft(original)
        XCTAssertFalse(staleSaved)
    }

    func testRecoveredOwnerMigrationRetargetsMarkerAndDraftsAtomically()
        async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let original = draft(
            storedSessionID: "source",
            revision: 1,
            attachments: [photo("one")]
        )
        let originalSaved = try await store.updateDraft(original)
        XCTAssertTrue(originalSaved)
        let upload = mutation(
            storedSessionID: "source",
            attachments: original.attachments,
            stage: .uploadPending
        )
        let sourceTombstone = draft(
            storedSessionID: "source",
            revision: 2,
            attachments: []
        )
        let began = try await store.beginMutation(
            upload,
            replacingMarkerIDs: [],
            expectedDraft: original,
            tombstone: sourceTombstone
        )
        XCTAssertTrue(began)
        let recovered = upload.advancing(to: .draftRecovered)
        let advanced = try await store.advanceMutation(
            from: upload,
            to: recovered
        )
        XCTAssertTrue(advanced)
        let replacement = recovered.retargeting(
            storedSessionID: "target",
            liveSessionID: "live-target",
            input: "inspect",
            attachments: recovered.attachments
        )
        let retiredSource = draft(
            storedSessionID: "source",
            revision: 3,
            attachments: []
        )
        let targetDraft = draft(
            storedSessionID: "target",
            revision: 4,
            attachments: []
        )

        let moved = try await store.migrateRecoveredDraft(
            mutations: [
                AttachmentMutationMigration(
                    expected: recovered,
                    replacement: replacement
                ),
            ],
            draftChanges: [
                AttachmentDraftMigrationChange(
                    owner: sourceTombstone.owner,
                    expected: sourceTombstone,
                    replacement: retiredSource
                ),
                AttachmentDraftMigrationChange(
                    owner: targetDraft.owner,
                    expected: nil,
                    replacement: targetDraft
                ),
            ],
            commitGuard: { true }
        )

        XCTAssertTrue(moved)
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.markers, [replacement])
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: snapshot.drafts.map {
                    ($0.owner, $0)
                }
            ),
            [
                retiredSource.owner: retiredSource,
                targetDraft.owner: targetDraft,
            ]
        )

        let stale = try await store.migrateRecoveredDraft(
            mutations: [
                AttachmentMutationMigration(
                    expected: recovered,
                    replacement: replacement
                ),
            ],
            draftChanges: [],
            commitGuard: { true }
        )
        XCTAssertFalse(stale)
        let afterStale = try await store.load()
        XCTAssertEqual(afterStale, snapshot)
    }

    func testRecoveredOwnerMigrationGuardRejectsBeforeCommit()
        async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let original = draft(revision: 1, attachments: [photo("one")])
        let originalSaved = try await store.updateDraft(original)
        XCTAssertTrue(originalSaved)
        let upload = mutation(
            attachments: original.attachments,
            stage: .uploadPending
        )
        let tombstone = draft(revision: 2, attachments: [])
        let began = try await store.beginMutation(
            upload,
            replacingMarkerIDs: [],
            expectedDraft: original,
            tombstone: tombstone
        )
        XCTAssertTrue(began)
        let recovered = upload.advancing(to: .draftRecovered)
        let advanced = try await store.advanceMutation(
            from: upload,
            to: recovered
        )
        XCTAssertTrue(advanced)
        let before = try await store.load()

        let moved = try await store.migrateRecoveredDraft(
            mutations: [
                AttachmentMutationMigration(
                    expected: recovered,
                    replacement: recovered.retargeting(
                        storedSessionID: "target",
                        liveSessionID: "live-target",
                        input: recovered.input,
                        attachments: recovered.attachments
                    )
                ),
            ],
            draftChanges: [],
            commitGuard: { false }
        )

        XCTAssertFalse(moved)
        let after = try await store.load()
        XCTAssertEqual(after, before)
    }

    func testProtectedFileIsBackupExcludedAndGatewayRemovalScrubsIt() async throws {
        let fixture = try TemporaryAttachmentStore()
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        let saved = try await store.updateDraft(
            draft(revision: 1, attachments: [photo("one")])
        )
        XCTAssertTrue(saved)

        let values = try fixture.fileURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
#if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(
                protection,
                .completeUntilFirstUserAuthentication
            )
        }
#else
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
#endif

        try await store.removeGateway(id: "gateway")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
    }

    func testMalformedPayloadFailsClosedWithoutLeakingBytesInError() async throws {
        let fixture = try TemporaryAttachmentStore()
        try Data(#"{"version":1,"drafts":["#.utf8).write(
            to: fixture.fileURL
        )
        let store = ProtectedAttachmentDraftStore(fileURL: fixture.fileURL)
        do {
            _ = try await store.load()
            XCTFail("Expected malformed protected state to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Saved photo drafts are damaged."
            )
            XCTAssertFalse(error.localizedDescription.contains("base64"))
        }
    }

    private func photo(_ id: String) -> PendingAttachment {
        PendingAttachment(
            id: id,
            filename: "\(id).jpg",
            data: Data("private-\(id)".utf8)
        )
    }

    private func draft(
        storedSessionID: String = "session",
        revision: Int64,
        attachments: [PendingAttachment]
    ) -> PersistedAttachmentDraft {
        PersistedAttachmentDraft(
            gatewayID: "gateway",
            storedSessionID: storedSessionID,
            revision: revision,
            attachments: attachments,
            updatedAtMilliseconds: revision
        )
    }

    private func mutation(
        id: String = "mutation",
        storedSessionID: String = "session",
        attachments: [PendingAttachment],
        stage: AttachmentMutationStage
    ) -> AttachmentMutationMarker {
        AttachmentMutationMarker(
            id: id,
            gatewayID: "gateway",
            storedSessionID: storedSessionID,
            liveSessionID: "live-\(storedSessionID)",
            input: "inspect",
            attachments: attachments,
            userEntryID: "user-entry",
            userMessagesBefore: 1,
            stage: stage
        )
    }

}

private final class TemporaryAttachmentStore: @unchecked Sendable {
    let directory: URL
    let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "nile-attachment-store-test-\(UUID())",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(
            path: "attachment-drafts.json",
            directoryHint: .notDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
