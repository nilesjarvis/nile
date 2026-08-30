import XCTest
@testable import Nile

@MainActor
final class SessionDraftLifecycleRuntimeTests: XCTestCase {
    func testRestoreSeedsProtectedRecordsIntoComposerProjection() async throws {
        let owner = makeOwner()
        let record = PersistedComposerDraft(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            revision: 3,
            text: "restored",
            updatedAtMilliseconds: 20
        )
        let store = ComposerDraftStoreStub(records: [record])
        let harness = makeHarness(store: store)

        let restored = try await harness.lifecycle.restore(
            gatewayID: owner.gatewayID
        )

        XCTAssertEqual(
            restored,
            [
                SessionDraftLifecycleRuntime.ComposerProjection(
                    owner: owner,
                    text: "restored"
                ),
            ]
        )
        XCTAssertEqual(harness.composer.text(for: owner), "restored")
        XCTAssertTrue(harness.composer.consumeRestored(owner: owner))
        XCTAssertFalse(harness.composer.consumeRestored(owner: owner))
    }

    func testSuccessfulClaimRetirementClearsComposerAndProtectedRecord()
        async throws
    {
        let owner = makeOwner()
        let store = ComposerDraftStoreStub()
        let harness = makeHarness(store: store)
        harness.composer.update(owner: owner, text: "send me")
        let claim = try XCTUnwrap(
            harness.lifecycle.captureClaim(
                owner: owner,
                fallbackText: "send me"
            )
        )
        var projections: [SessionDraftLifecycleRuntime.ComposerProjection] = []
        var failures: [SessionDraftLifecycleRuntime.Failure] = []

        let flushed = await harness.lifecycle.flushClaim(
            owner: owner,
            claim: claim
        )
        XCTAssertTrue(flushed)
        await harness.lifecycle.retireClaim(
            owner: owner,
            claim: claim,
            onProjection: { projections.append($0) },
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(
            projections,
            [
                SessionDraftLifecycleRuntime.ComposerProjection(
                    owner: owner,
                    text: ""
                ),
            ]
        )
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(harness.composer.text(for: owner), "")
        let stored = await store.record(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        XCTAssertEqual(stored?.text, "")
    }

    func testFailedClaimRetirementRollsComposerBackAndReportsFailure() async {
        let owner = makeOwner()
        let store = ComposerDraftStoreStub(failsUpdates: true)
        let harness = makeHarness(store: store)
        harness.composer.update(owner: owner, text: "keep me")
        let claim = harness.lifecycle.captureClaim(
            owner: owner,
            fallbackText: "keep me"
        )
        var projections: [SessionDraftLifecycleRuntime.ComposerProjection] = []
        var failures: [SessionDraftLifecycleRuntime.Failure] = []

        await harness.lifecycle.retireClaim(
            owner: owner,
            claim: claim,
            onProjection: { projections.append($0) },
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(projections.map(\.text), ["", "keep me"])
        XCTAssertEqual(harness.composer.text(for: owner), "keep me")
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.owner, owner)
    }

    func testVisibleRecoveryPersistsAdmissionOrderedComposerOutcome() async {
        let owner = makeOwner()
        let store = ComposerDraftStoreStub()
        let harness = makeHarness(store: store)
        harness.composer.update(owner: owner, text: "failed")
        let token = harness.composer.capture(owner)
        harness.composer.claim(owner: owner)
        harness.composer.update(owner: owner, text: "new draft")
        var failures: [SessionDraftLifecycleRuntime.Failure] = []

        let resolution = harness.lifecycle.recover(
            token: token,
            failedInput: "failed",
            notice: "restored",
            uncertain: false,
            noticeChannel: .operation,
            isVisible: true,
            onFailure: { failures.append($0) }
        )

        XCTAssertEqual(
            resolution,
            .visible(
                SessionDraftLifecycleRuntime.RecoveryPresentation(
                    owner: owner,
                    restoredText: "failed\n\nnew draft",
                    notice: "restored",
                    uncertain: false
                )
            )
        )
        await eventually {
            await store.record(
                gatewayID: owner.gatewayID,
                storedSessionID: owner.storedSessionID
            )?.text == "failed\n\nnew draft"
        }
        XCTAssertTrue(failures.isEmpty)
    }

    func testOffscreenSteerRecoveryDefersExactUncertainNotice() {
        let owner = makeOwner()
        let harness = makeHarness(store: ComposerDraftStoreStub())
        let token = harness.composer.capture(owner)

        let resolution = harness.lifecycle.recover(
            token: token,
            failedInput: "steer",
            notice: "inspect before retrying",
            uncertain: true,
            noticeChannel: .steer,
            isVisible: false,
            onFailure: { _ in }
        )

        XCTAssertEqual(resolution, .deferred)
        XCTAssertEqual(
            harness.composer.takeSteerNotice(owner: owner),
            SessionComposerRuntime.Notice(
                message: "inspect before retrying",
                uncertain: true
            )
        )
        XCTAssertNil(harness.composer.takeOperationNotice(owner: owner))
    }

    func testGatewayInvalidationRejectsStaleRecoveryWithoutPersistence() async {
        let owner = makeOwner()
        let store = ComposerDraftStoreStub()
        let harness = makeHarness(store: store)
        let token = harness.composer.capture(owner)
        harness.composer.invalidateGateway(owner.gatewayID)

        let resolution = harness.lifecycle.recover(
            token: token,
            failedInput: "stale",
            notice: "ignored",
            uncertain: true,
            noticeChannel: .operation,
            isVisible: false,
            onFailure: { _ in }
        )

        XCTAssertEqual(resolution, .stale)
        await Task.yield()
        let stored = await store.record(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        XCTAssertNil(stored)
        XCTAssertNil(harness.composer.takeOperationNotice(owner: owner))
    }

    private struct Harness {
        let lifecycle: SessionDraftLifecycleRuntime
        let composer: SessionComposerRuntime
    }

    private func makeHarness(
        store: ComposerDraftStoreStub
    ) -> Harness {
        let composer = SessionComposerRuntime()
        let persistence = SessionDraftPersistenceRuntime(store: store)
        return Harness(
            lifecycle: SessionDraftLifecycleRuntime(
                composerRuntime: composer,
                persistenceRuntime: persistence
            ),
            composer: composer
        )
    }

    private func makeOwner() -> ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: "gateway",
            storedSessionID: "session"
        )
    }

    private func eventually(
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
