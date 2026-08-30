import XCTest
@testable import Nile

@MainActor
final class SessionComposerRuntimeTests: XCTestCase {
    func testFailuresRenderInAdmissionOrderInsteadOfCompletionOrder() {
        let runtime = SessionComposerRuntime()
        let owner = makeOwner()
        runtime.update(owner: owner, text: "new draft")
        let first = runtime.capture(owner)
        let second = runtime.capture(owner)

        let secondFinished = runtime.recover(
            second,
            failedInput: "second"
        )
        let firstFinished = runtime.recover(
            first,
            failedInput: "first"
        )

        XCTAssertEqual(secondFinished, "second\n\nnew draft")
        XCTAssertEqual(firstFinished, "first\n\nsecond\n\nnew draft")
        XCTAssertEqual(runtime.text(for: owner), firstFinished)
    }

    func testComposerEditsRebaseRecoveryAndReplacementReleasesIt() {
        let runtime = SessionComposerRuntime()
        let owner = makeOwner()
        runtime.update(owner: owner, text: "original")
        let first = runtime.capture(owner)
        XCTAssertEqual(
            runtime.recover(first, failedInput: "first"),
            "first\n\noriginal"
        )

        runtime.update(owner: owner, text: "first\n\nedited")
        let second = runtime.capture(owner)
        XCTAssertEqual(
            runtime.recover(second, failedInput: "second"),
            "first\n\nsecond\n\nedited"
        )

        runtime.update(owner: owner, text: "replacement")
        let third = runtime.capture(owner)
        XCTAssertEqual(
            runtime.recover(third, failedInput: "third"),
            "third\n\nreplacement"
        )
    }

    func testGatewayInvalidationRejectsOnlyEarlierTokensForThatGateway() {
        let runtime = SessionComposerRuntime()
        let staleOwner = makeOwner(gatewayID: "one")
        let otherOwner = makeOwner(gatewayID: "two")
        let stale = runtime.capture(staleOwner)
        let other = runtime.capture(otherOwner)

        runtime.invalidateGateway("one")
        let current = runtime.capture(staleOwner)

        XCTAssertFalse(runtime.isCurrent(stale))
        XCTAssertNil(runtime.recover(stale, failedInput: "stale"))
        XCTAssertTrue(runtime.isCurrent(other))
        XCTAssertTrue(runtime.isCurrent(current))
    }

    func testUncertainNoticeCannotBeDowngradedAndIsConsumedOnce() {
        let runtime = SessionComposerRuntime()
        let owner = makeOwner()
        runtime.rememberSteerNotice(
            owner: owner,
            message: "uncertain",
            uncertain: true
        )
        runtime.rememberSteerNotice(
            owner: owner,
            message: "definite",
            uncertain: false
        )

        XCTAssertEqual(
            runtime.takeSteerNotice(owner: owner),
            SessionComposerRuntime.Notice(
                message: "uncertain",
                uncertain: true
            )
        )
        XCTAssertNil(runtime.takeSteerNotice(owner: owner))
    }

    func testProjectionOwnsRestorationMigrationAndClaimRollbackFacts() {
        let runtime = SessionComposerRuntime()
        let source = makeOwner(sessionID: "source")
        let target = makeOwner(sessionID: "target")
        runtime.seed(owner: source, text: "restored", restored: true)

        XCTAssertTrue(runtime.consumeRestored(owner: source))
        XCTAssertFalse(runtime.consumeRestored(owner: source))
        runtime.migrate(from: source, to: target, text: "restored")
        XCTAssertEqual(runtime.text(for: source), "")
        XCTAssertEqual(runtime.text(for: target), "restored")
        XCTAssertEqual(
            runtime.nonemptyOwners(gatewayID: "gateway"),
            [target]
        )
        XCTAssertFalse(runtime.clearIfEqual(owner: target, text: "other"))
        XCTAssertTrue(runtime.clearIfEqual(owner: target, text: "restored"))
        XCTAssertTrue(runtime.restoreIfEmpty(owner: target, text: "rollback"))
        XCTAssertFalse(runtime.restoreIfEmpty(owner: target, text: "ignored"))
        XCTAssertEqual(runtime.text(for: target), "rollback")
    }

    func testMergeRecoveredPreservesNewerWorkWithoutDuplication() {
        XCTAssertEqual(
            SessionComposerRuntime.mergeRecovered("", with: "draft"),
            "draft"
        )
        XCTAssertEqual(
            SessionComposerRuntime.mergeRecovered("failed", with: ""),
            "failed"
        )
        XCTAssertEqual(
            SessionComposerRuntime.mergeRecovered("failed", with: "failed"),
            "failed"
        )
        XCTAssertEqual(
            SessionComposerRuntime.mergeRecovered("failed", with: "new"),
            "failed\n\nnew"
        )
    }

    private func makeOwner(
        gatewayID: String = "gateway",
        sessionID: String = "session"
    ) -> ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: sessionID
        )
    }
}
