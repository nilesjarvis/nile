import XCTest
@testable import Nile

@MainActor
final class SessionDraftPersistenceRuntimeTests: XCTestCase {
    func testStoreTextVersionsRecordsAndFlushesOnlyLatestDebouncedEdit() async {
        let store = DraftPersistenceStoreStub()
        let clock = DraftPersistenceClock(100)
        let runtime = makeRuntime(store: store, clock: clock)
        let owner = makeOwner()
        var failures: [String] = []

        let first = runtime.storeText(
            owner: owner,
            text: "first",
            onFailure: { _, message in failures.append(message) }
        )
        let second = runtime.storeText(
            owner: owner,
            text: "second",
            onFailure: { _, message in failures.append(message) }
        )
        runtime.flushAll { _, message in failures.append(message) }

        await eventuallyAsync { await store.record(for: owner)?.text == "second" }
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(first.updatedAtMilliseconds, 100)
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(second.updatedAtMilliseconds, 101)
        let updatedTexts = await store.updatedTexts
        XCTAssertEqual(updatedTexts, ["second"])
        XCTAssertEqual(runtime.record(for: owner), second)
        XCTAssertTrue(failures.isEmpty)
    }

    func testRestoreFiltersGatewayAndAcceptsOnlyNewerRecords() async throws {
        let owner = makeOwner()
        let otherGateway = makeOwner(gatewayID: "other")
        let stored = makeRecord(owner: owner, revision: 4, text: "restored")
        let unrelated = makeRecord(
            owner: otherGateway,
            revision: 8,
            text: "hidden"
        )
        let store = DraftPersistenceStoreStub(records: [stored, unrelated])
        let runtime = makeRuntime(store: store)

        let restored = try await runtime.restore(gatewayID: owner.gatewayID)
        let duplicate = try await runtime.restore(gatewayID: owner.gatewayID)

        XCTAssertEqual(restored, [stored])
        XCTAssertTrue(duplicate.isEmpty)
        XCTAssertEqual(runtime.record(for: owner), stored)
        XCTAssertNil(runtime.record(for: otherGateway))
    }

    func testFlushAndSuccessfulRetirementPersistExactClaimThenTombstone()
        async
    {
        let store = DraftPersistenceStoreStub()
        let runtime = makeRuntime(store: store)
        let owner = makeOwner()
        var retiring: [String] = []
        var rollbacks: [String] = []
        var failures: [String] = []
        let claim = runtime.storeText(
            owner: owner,
            text: "send me",
            onFailure: { _, _ in }
        )

        let flushed = await runtime.flushClaim(owner: owner, claim: claim)
        XCTAssertTrue(flushed)
        await runtime.retireClaim(
            owner: owner,
            claim: claim,
            onRetiring: { retiring.append($0) },
            onRollback: { rollbacks.append($0) },
            onFailure: { _, message in failures.append(message) }
        )

        XCTAssertEqual(retiring, ["send me"])
        XCTAssertTrue(rollbacks.isEmpty)
        XCTAssertTrue(failures.isEmpty)
        let updatedTexts = await store.updatedTexts
        XCTAssertEqual(updatedTexts, ["send me", ""])
        XCTAssertEqual(runtime.record(for: owner)?.text, "")
        XCTAssertEqual(runtime.record(for: owner)?.revision, 2)
    }

    func testFailedRetirementRollsBackExactClaimAndReportsFailure() async {
        let store = DraftPersistenceStoreStub(failEmptyUpdates: true)
        let runtime = makeRuntime(store: store)
        let owner = makeOwner()
        var retiring: [String] = []
        var rollbacks: [String] = []
        var failures: [String] = []
        let claim = runtime.storeText(
            owner: owner,
            text: "keep me",
            onFailure: { _, _ in }
        )
        let flushed = await runtime.flushClaim(owner: owner, claim: claim)
        XCTAssertTrue(flushed)

        await runtime.retireClaim(
            owner: owner,
            claim: claim,
            onRetiring: { retiring.append($0) },
            onRollback: { rollbacks.append($0) },
            onFailure: { failureOwner, message in
                XCTAssertEqual(failureOwner, owner)
                failures.append(message)
            }
        )

        XCTAssertEqual(retiring, ["keep me"])
        XCTAssertEqual(rollbacks, ["keep me"])
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(runtime.record(for: owner), claim)
        let stored = await store.record(for: owner)
        XCTAssertEqual(stored, claim)
    }

    func testNewerEditSupersedesBlockedRetirementWithoutRollback() async {
        let store = DraftPersistenceStoreStub(blockEmptyUpdate: true)
        let runtime = makeRuntime(store: store)
        let owner = makeOwner()
        var rollbacks: [String] = []
        var failures: [String] = []
        let claim = runtime.storeText(
            owner: owner,
            text: "first",
            onFailure: { _, _ in }
        )
        let flushed = await runtime.flushClaim(owner: owner, claim: claim)
        XCTAssertTrue(flushed)

        let retirement = Task {
            await runtime.retireClaim(
                owner: owner,
                claim: claim,
                onRetiring: { _ in },
                onRollback: { rollbacks.append($0) },
                onFailure: { _, message in failures.append(message) }
            )
        }
        await eventuallyAsync { await store.emptyUpdateStarted }
        let newer = runtime.storeText(
            owner: owner,
            text: "second",
            debounce: false,
            onFailure: { _, message in failures.append(message) }
        )
        await store.releaseEmptyUpdate()
        await retirement.value
        await eventuallyAsync { await store.record(for: owner) == newer }

        XCTAssertEqual(runtime.record(for: owner), newer)
        XCTAssertTrue(rollbacks.isEmpty)
        XCTAssertTrue(failures.isEmpty)
        let updatedTexts = await store.updatedTexts
        XCTAssertEqual(updatedTexts.last, "second")
    }

    func testRecoveredMigrationUsesOneExactOwnerCASAndMonotonicRecords()
        async throws
    {
        let sourceOwner = makeOwner(storedSessionID: "missing")
        let targetOwner = makeOwner(storedSessionID: "created")
        let source = makeRecord(
            owner: sourceOwner,
            revision: 3,
            text: "move me",
            timestamp: 40
        )
        let target = makeRecord(
            owner: targetOwner,
            revision: 5,
            text: "older target",
            timestamp: 50
        )
        let store = DraftPersistenceStoreStub(records: [source, target])
        let clock = DraftPersistenceClock(500)
        let runtime = makeRuntime(store: store, clock: clock)
        _ = try await runtime.restore(gatewayID: sourceOwner.gatewayID)

        let migrated = await runtime.migrateRecoveredDraft(
            from: sourceOwner,
            to: targetOwner,
            targetText: "move me"
        )
        XCTAssertTrue(migrated)

        let sourceResult = try XCTUnwrap(runtime.record(for: sourceOwner))
        let targetResult = try XCTUnwrap(runtime.record(for: targetOwner))
        XCTAssertEqual(sourceResult.text, "")
        XCTAssertEqual(sourceResult.revision, 4)
        XCTAssertEqual(targetResult.text, "move me")
        XCTAssertEqual(targetResult.revision, 7)
        XCTAssertEqual(sourceResult.updatedAtMilliseconds, 500)
        XCTAssertEqual(targetResult.updatedAtMilliseconds, 500)
        let migrationCount = await store.migrationCount
        let storedSource = await store.record(for: sourceOwner)
        let storedTarget = await store.record(for: targetOwner)
        XCTAssertEqual(migrationCount, 1)
        XCTAssertEqual(storedSource, sourceResult)
        XCTAssertEqual(storedTarget, targetResult)
    }

    private func makeRuntime(
        store: DraftPersistenceStoreStub,
        clock: DraftPersistenceClock = DraftPersistenceClock(1_000)
    ) -> SessionDraftPersistenceRuntime {
        SessionDraftPersistenceRuntime(
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

    private func makeRecord(
        owner: ComposerDraftOwner,
        revision: Int64,
        text: String,
        timestamp: Int64 = 100
    ) -> PersistedComposerDraft {
        PersistedComposerDraft(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            revision: revision,
            text: text,
            updatedAtMilliseconds: timestamp
        )
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
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
private final class DraftPersistenceClock {
    private var value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    func now() -> Int64 {
        defer { value += 1 }
        return value
    }
}

private actor DraftPersistenceStoreStub: ComposerDraftStoring {
    private var records: [ComposerDraftOwner: PersistedComposerDraft]
    private let failEmptyUpdates: Bool
    private let blockEmptyUpdate: Bool
    private var emptyUpdateContinuation: CheckedContinuation<Void, Never>?
    private(set) var emptyUpdateStarted = false
    private(set) var updatedTexts: [String] = []
    private(set) var migrationCount = 0

    init(
        records: [PersistedComposerDraft] = [],
        failEmptyUpdates: Bool = false,
        blockEmptyUpdate: Bool = false
    ) {
        self.records = Dictionary(
            uniqueKeysWithValues: records.map { ($0.owner, $0) }
        )
        self.failEmptyUpdates = failEmptyUpdates
        self.blockEmptyUpdate = blockEmptyUpdate
    }

    func load() -> [PersistedComposerDraft] {
        Array(records.values)
    }

    func update(_ draft: PersistedComposerDraft) async throws -> Bool {
        if draft.text.isEmpty, blockEmptyUpdate {
            emptyUpdateStarted = true
            await withCheckedContinuation { continuation in
                emptyUpdateContinuation = continuation
            }
        }
        if draft.text.isEmpty, failEmptyUpdates {
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

    func migrate(_ changes: [ComposerDraftMigrationChange]) -> Bool {
        migrationCount += 1
        for change in changes {
            guard records[change.owner] == change.expected else {
                return false
            }
        }
        for change in changes {
            records[change.owner] = change.replacement
        }
        return true
    }

    func removeGateway(id: String) {
        records = records.filter { $0.key.gatewayID != id }
    }

    func record(for owner: ComposerDraftOwner) -> PersistedComposerDraft? {
        records[owner]
    }

    func releaseEmptyUpdate() {
        emptyUpdateContinuation?.resume()
        emptyUpdateContinuation = nil
    }
}
