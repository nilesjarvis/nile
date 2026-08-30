import UIKit
import XCTest
@testable import Nile

final class TranscriptViewportPositionPolicyTests: XCTestCase {
    @MainActor
    func testPositionRuntimeOwnsDelegateAndOwnerActivation() {
        let runtime = TranscriptViewportPositionRuntime()
        let rootView = UIView()
        let coordinator = TranscriptScrollCoordinator()
        let owner = TranscriptScrollOwner(
            gatewayID: "gateway",
            sessionID: "session"
        )

        runtime.install(in: rootView)
        XCTAssertTrue(runtime.collectionView.delegate === runtime)
        XCTAssertTrue(rootView.subviews.contains(runtime.collectionView))
        XCTAssertTrue(runtime.ownerChanges(to: owner))

        runtime.update(
            rowsChanged: false,
            owner: owner,
            scrollState: coordinator,
            lastUserEntryID: "user-one",
            jumpToBottomRevision: 0,
            automaticTailPinEnabled: true,
            retainsTopInset: false,
            onAnchoredChange: { _ in },
            onAnchorTransition: { _ in }
        )

        XCTAssertFalse(runtime.ownerChanges(to: owner))
        XCTAssertTrue(coordinator.isAnchored(owner: owner))
    }

    func testGeometryClampsOffsetsAndDetectsTheBottomWithinTolerance() {
        let geometry = TranscriptViewportGeometry(
            contentOffsetY: 609.25,
            contentHeight: 1_000,
            viewportHeight: 400,
            adjustedTopInset: 14,
            adjustedBottomInset: 10
        )

        XCTAssertEqual(geometry.minimumOffsetY, -14)
        XCTAssertEqual(geometry.maximumOffsetY, 610)
        XCTAssertEqual(geometry.clampedOffsetY(-100), -14)
        XCTAssertEqual(geometry.clampedOffsetY(900), 610)
        XCTAssertTrue(geometry.isAtBottom())
        XCTAssertFalse(geometry.isAtBottom(tolerance: 0.5))
    }

    func testGeometryCollapsesRangeToMinimumWhenContentFits() {
        let geometry = TranscriptViewportGeometry(
            contentOffsetY: -14,
            contentHeight: 50,
            viewportHeight: 100,
            adjustedTopInset: 14,
            adjustedBottomInset: 10
        )

        XCTAssertEqual(geometry.minimumOffsetY, -14)
        XCTAssertEqual(geometry.maximumOffsetY, -14)
        XCTAssertEqual(geometry.clampedOffsetY(100), -14)
        XCTAssertTrue(geometry.isAtBottom())
    }

    func testResizeStatePreservesFittingContentAcrossRepeatedShrinks() {
        var state = TranscriptViewportResizeState()
        state.observe(
            viewportHeight: 300,
            contentHeight: 200,
            currentOffset: 0
        )
        XCTAssertNil(state.preservedOffset)

        state.observe(
            viewportHeight: 200,
            contentHeight: 200,
            currentOffset: -20
        )
        XCTAssertEqual(state.preservedOffset, -20)
        state.settlePreservedOffset(-14)

        state.observe(
            viewportHeight: 150,
            contentHeight: 400,
            currentOffset: 33
        )
        XCTAssertEqual(state.preservedOffset, 33)

        state.observe(
            viewportHeight: 300,
            contentHeight: 400,
            currentOffset: 33
        )
        XCTAssertNil(state.preservedOffset)
    }

    func testResizeStateDoesNotDetachLongContentOnFirstShrink() {
        var state = TranscriptViewportResizeState()
        state.observe(
            viewportHeight: 300,
            contentHeight: 600,
            currentOffset: 80
        )
        state.observe(
            viewportHeight: 200,
            contentHeight: 600,
            currentOffset: 80
        )

        XCTAssertNil(state.preservedOffset)
        state.settlePreservedOffset(80)
        XCTAssertEqual(state.preservedOffset, 80)
        state.clearPreservedOffset()
        XCTAssertNil(state.preservedOffset)
    }

    func testSettlementStateRetriesAnUnavailableOffsetBeforeClamping() {
        var state = TranscriptViewportSettlementState()
        state.apply(
            TranscriptScrollPresentation(
                isAnchored: false,
                contentOffsetY: 500
            )
        )
        let geometry = TranscriptViewportGeometry(
            contentOffsetY: 0,
            contentHeight: 200,
            viewportHeight: 100,
            adjustedTopInset: 0,
            adjustedBottomInset: 0
        )

        for _ in 0..<12 {
            XCTAssertEqual(
                state.nextAction(geometry: geometry),
                .retryOffset
            )
        }
        XCTAssertEqual(
            state.nextAction(geometry: geometry),
            .setOffset(100)
        )
        XCTAssertFalse(state.hasPendingPosition)
    }

    func testSettlementStateSeparatesTailPinFromDetachedOffsetRetention() {
        var state = TranscriptViewportSettlementState()
        let geometry = TranscriptViewportGeometry(
            contentOffsetY: 20,
            contentHeight: 400,
            viewportHeight: 200,
            adjustedTopInset: 0,
            adjustedBottomInset: 0
        )
        state.configure(
            automaticTailPinEnabled: true,
            retainsTopInset: false,
            currentTopInset: 0
        )
        state.apply(
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
        XCTAssertEqual(state.nextAction(geometry: geometry), .pinToBottom)

        state.configure(
            automaticTailPinEnabled: false,
            retainsTopInset: false,
            currentTopInset: 0
        )
        state.recordUserPosition(isAnchored: false, contentOffsetY: 42)
        state.applyContentChange(
            TranscriptScrollPresentation(
                isAnchored: false,
                contentOffsetY: 80
            ),
            currentOffset: 100
        )
        XCTAssertEqual(state.nextAction(geometry: geometry), .setOffset(42))
    }

    func testSettlementStateRetainsAndRecomputesTopInsetByMode() {
        var state = TranscriptViewportSettlementState()
        state.configure(
            automaticTailPinEnabled: true,
            retainsTopInset: false,
            currentTopInset: 0
        )
        XCTAssertEqual(
            state.desiredTopInset(
                bottomAligned: true,
                viewportHeight: 300,
                contentHeight: 200
            ),
            100
        )

        state.configure(
            automaticTailPinEnabled: true,
            retainsTopInset: true,
            currentTopInset: 100
        )
        XCTAssertEqual(
            state.desiredTopInset(
                bottomAligned: true,
                viewportHeight: 400,
                contentHeight: 200
            ),
            100
        )
        XCTAssertEqual(
            state.desiredTopInset(
                bottomAligned: false,
                viewportHeight: 400,
                contentHeight: 200
            ),
            0
        )
    }

    func testSettlementStateInvalidatesOlderLayoutGeneration() {
        var state = TranscriptViewportSettlementState()
        let firstGeneration = state.nextLayoutGeneration()
        let secondGeneration = state.nextLayoutGeneration()

        XCTAssertFalse(
            state.isCurrentLayoutGeneration(firstGeneration)
        )
        XCTAssertTrue(
            state.isCurrentLayoutGeneration(secondGeneration)
        )
    }
}
