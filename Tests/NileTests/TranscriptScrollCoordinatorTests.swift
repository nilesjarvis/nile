import XCTest
@testable import Nile

@MainActor
final class TranscriptScrollCoordinatorTests: XCTestCase {
    func testOwnerStateKeyUsesKotlinUTF16LengthPrefix() {
        XCTAssertEqual(
            owner(gateway: "😀", session: "same").stateKey,
            "2:😀:same"
        )
    }

    func testFirstContentStartsAtBottomAndExternalAppendDoesNotRearm() {
        let coordinator = TranscriptScrollCoordinator()
        let owner = owner(gateway: "alpha", session: "shared")

        XCTAssertEqual(
            coordinator.activate(
                owner: owner,
                lastUserEntryID: "user-one"
            ),
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
        XCTAssertEqual(
            coordinator.recordUserScroll(
                owner: owner,
                contentOffsetY: 312.5,
                isBottomVisible: false
            ),
            .leftBottom
        )
        XCTAssertEqual(
            coordinator.contentChanged(
                owner: owner,
                lastUserEntryID: "user-one"
            ),
            TranscriptScrollPresentation(
                isAnchored: false,
                contentOffsetY: 312.5
            )
        )
    }

    func testNewUserEntryAlwaysRearmsBottomFollow() {
        let coordinator = TranscriptScrollCoordinator()
        let owner = owner(gateway: "gateway", session: "session")
        _ = coordinator.activate(
            owner: owner,
            lastUserEntryID: "user-one"
        )
        _ = coordinator.recordUserScroll(
            owner: owner,
            contentOffsetY: 120,
            isBottomVisible: false
        )

        XCTAssertEqual(
            coordinator.contentChanged(
                owner: owner,
                lastUserEntryID: "user-two"
            ),
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
    }

    func testReadingPositionsAreScopedByGatewayAndSession() {
        let coordinator = TranscriptScrollCoordinator()
        let alpha = owner(gateway: "alpha", session: "shared")
        let beta = owner(gateway: "beta", session: "shared")

        _ = coordinator.activate(owner: alpha, lastUserEntryID: nil)
        _ = coordinator.recordUserScroll(
            owner: alpha,
            contentOffsetY: 88,
            isBottomVisible: false
        )

        XCTAssertEqual(
            coordinator.activate(owner: beta, lastUserEntryID: nil),
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
        XCTAssertEqual(
            coordinator.activate(owner: alpha, lastUserEntryID: nil),
            TranscriptScrollPresentation(
                isAnchored: false,
                contentOffsetY: 88
            )
        )
    }

    func testRestorePreservesExactViewportOffset() {
        let coordinator = TranscriptScrollCoordinator()
        let owner = owner(gateway: "gateway", session: "session")
        _ = coordinator.activate(owner: owner, lastUserEntryID: nil)
        _ = coordinator.recordUserScroll(
            owner: owner,
            contentOffsetY: 417.25,
            isBottomVisible: false
        )

        XCTAssertEqual(
            coordinator.activate(owner: owner, lastUserEntryID: nil),
            TranscriptScrollPresentation(
                isAnchored: false,
                contentOffsetY: 417.25
            )
        )
    }

    func testProgrammaticPositionNeverChangesAnchorMode() {
        let coordinator = TranscriptScrollCoordinator()
        let owner = owner(gateway: "gateway", session: "session")
        _ = coordinator.activate(owner: owner, lastUserEntryID: nil)

        coordinator.recordProgrammaticPosition(
            owner: owner,
            contentOffsetY: 900
        )

        XCTAssertTrue(coordinator.isAnchored(owner: owner))
        XCTAssertEqual(
            coordinator.activate(owner: owner, lastUserEntryID: nil),
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
    }

    func testProgrammaticJumpRearmsBottomFollow() {
        let coordinator = TranscriptScrollCoordinator()
        let owner = owner(gateway: "gateway", session: "session")
        _ = coordinator.activate(owner: owner, lastUserEntryID: nil)
        _ = coordinator.recordUserScroll(
            owner: owner,
            contentOffsetY: 70,
            isBottomVisible: false
        )

        XCTAssertEqual(
            coordinator.jumpToBottom(owner: owner),
            TranscriptScrollPresentation(
                isAnchored: true,
                contentOffsetY: nil
            )
        )
    }

    private func owner(
        gateway: String,
        session: String
    ) -> TranscriptScrollOwner {
        TranscriptScrollOwner(
            gatewayID: gateway,
            sessionID: session
        )
    }
}
