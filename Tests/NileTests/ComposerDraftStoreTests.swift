import XCTest
@testable import Nile

final class ComposerDraftStoreTests: XCTestCase {
    func testNewerRevisionsRoundTripAndStaleOrConflictingWritesAreRejected() async throws {
        let fixture = try TemporaryDraftStore()
        let store = ProtectedComposerDraftStore(fileURL: fixture.fileURL)
        let first = draft(revision: 1, text: "first", timestamp: 100)
        let newer = draft(revision: 2, text: "newer", timestamp: 101)

        let inserted = try await store.update(first)
        let idempotent = try await store.update(first)
        let replaced = try await store.update(newer)
        let stale = try await store.update(first)
        let conflict = try await store.update(
            draft(revision: 2, text: "conflict", timestamp: 102)
        )
        let loaded = try await store.load()

        XCTAssertTrue(inserted)
        XCTAssertTrue(idempotent)
        XCTAssertTrue(replaced)
        XCTAssertFalse(stale)
        XCTAssertFalse(conflict)
        XCTAssertEqual(loaded, [newer])
    }

    func testEmptyRevisionTombstoneSurvivesRelaunchAndGatewayRemovalCleansIt() async throws {
        let fixture = try TemporaryDraftStore()
        let firstStore = ProtectedComposerDraftStore(fileURL: fixture.fileURL)
        let tombstone = draft(revision: 2, text: "", timestamp: 101)
        let inserted = try await firstStore.update(
            draft(revision: 1, text: "sent", timestamp: 100)
        )
        let retired = try await firstStore.update(tombstone)
        XCTAssertTrue(inserted)
        XCTAssertTrue(retired)

        let relaunchedStore = ProtectedComposerDraftStore(
            fileURL: fixture.fileURL
        )
        let restored = try await relaunchedStore.load()
        XCTAssertEqual(restored, [tombstone])

        try await relaunchedStore.removeGateway(id: "gateway")
        let removed = try await relaunchedStore.load()
        XCTAssertEqual(removed, [])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
        let staleRewrite = try await relaunchedStore.update(tombstone)
        XCTAssertFalse(staleRewrite)
        let stillRemoved = try await relaunchedStore.load()
        XCTAssertEqual(stillRemoved, [])
    }

    func testProtectedDraftFileIsExcludedFromBackup() async throws {
        let fixture = try TemporaryDraftStore()
        let store = ProtectedComposerDraftStore(fileURL: fixture.fileURL)
        let inserted = try await store.update(
            draft(revision: 1, text: "private draft", timestamp: 100)
        )
        XCTAssertTrue(inserted)

        let values = try fixture.directory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
#if targetEnvironment(simulator)
        // APFS in Simulator accepts file protection but may not surface it.
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
    }

    func testOwnerMigrationUsesOneExactSnapshotCommit() async throws {
        let fixture = try TemporaryDraftStore()
        let store = ProtectedComposerDraftStore(fileURL: fixture.fileURL)
        let source = draft(
            storedSessionID: "source",
            revision: 2,
            text: "recovered",
            timestamp: 100
        )
        let target = draft(
            storedSessionID: "target",
            revision: 4,
            text: "stale target",
            timestamp: 101
        )
        let sourceSaved = try await store.update(source)
        let targetSaved = try await store.update(target)
        XCTAssertTrue(sourceSaved)
        XCTAssertTrue(targetSaved)
        let sourceTombstone = draft(
            storedSessionID: "source",
            revision: 3,
            text: "",
            timestamp: 200
        )
        let movedTarget = draft(
            storedSessionID: "target",
            revision: 6,
            text: "",
            timestamp: 200
        )

        let moved = try await store.migrate([
            ComposerDraftMigrationChange(
                owner: source.owner,
                expected: source,
                replacement: sourceTombstone
            ),
            ComposerDraftMigrationChange(
                owner: target.owner,
                expected: target,
                replacement: movedTarget
            ),
        ])

        XCTAssertTrue(moved)
        let records = Dictionary(
            uniqueKeysWithValues: try await store.load().map {
                ($0.owner, $0)
            }
        )
        XCTAssertEqual(
            records,
            [
                source.owner: sourceTombstone,
                target.owner: movedTarget,
            ]
        )
        let stale = try await store.migrate([
            ComposerDraftMigrationChange(
                owner: source.owner,
                expected: source,
                replacement: sourceTombstone
            ),
        ])
        XCTAssertFalse(stale)
        let afterStale = try await store.load()
        XCTAssertEqual(
            afterStale.first { $0.owner == source.owner },
            sourceTombstone
        )
    }

    func testMalformedEnvelopeFailsClosed() async throws {
        let fixture = try TemporaryDraftStore()
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"version\":1,\"drafts\":[".utf8).write(
            to: fixture.fileURL
        )
        let store = ProtectedComposerDraftStore(fileURL: fixture.fileURL)

        do {
            _ = try await store.load()
            XCTFail("Expected malformed data to be rejected")
        } catch let error as ComposerDraftStoreError {
            XCTAssertEqual(error, .malformedData)
        }
    }

    private func draft(
        storedSessionID: String = "session",
        revision: Int64,
        text: String,
        timestamp: Int64
    ) -> PersistedComposerDraft {
        PersistedComposerDraft(
            gatewayID: "gateway",
            storedSessionID: storedSessionID,
            revision: revision,
            text: text,
            updatedAtMilliseconds: timestamp
        )
    }
}

private final class TemporaryDraftStore: @unchecked Sendable {
    let directory: URL
    let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "nile-draft-test-\(UUID())", directoryHint: .isDirectory)
        fileURL = directory.appending(
            path: "composer-drafts.json",
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
