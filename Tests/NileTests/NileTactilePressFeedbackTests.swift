import XCTest
@testable import Nile

final class NileTactilePressFeedbackTests: XCTestCase {
    func testTouchDownCompressesWithoutChangingUnpressedPresentation() {
        XCTAssertEqual(
            NileTactilePressFeedback.scale(
                isPressed: false,
                reduceMotion: false
            ),
            1
        )
        XCTAssertEqual(
            NileTactilePressFeedback.opacity(
                isPressed: false,
                reduceMotion: false
            ),
            1
        )
        XCTAssertEqual(
            NileTactilePressFeedback.scale(
                isPressed: true,
                reduceMotion: false
            ),
            0.96
        )
        XCTAssertEqual(
            NileTactilePressFeedback.opacity(
                isPressed: true,
                reduceMotion: false
            ),
            0.9
        )
    }

    func testReducedMotionUsesFadeWithoutMovement() {
        XCTAssertEqual(
            NileTactilePressFeedback.scale(
                isPressed: true,
                reduceMotion: true
            ),
            1
        )
        XCTAssertEqual(
            NileTactilePressFeedback.opacity(
                isPressed: true,
                reduceMotion: true
            ),
            0.76
        )
    }

    func testComposerSurfaceExpandsForHoverOrActivationUnlessMotionIsReduced() {
        XCTAssertEqual(
            NileComposerSurfaceFeedback.scale(
                isHovered: false,
                isActivated: false,
                reduceMotion: false
            ),
            1
        )
        XCTAssertEqual(
            NileComposerSurfaceFeedback.scale(
                isHovered: true,
                isActivated: false,
                reduceMotion: false
            ),
            1.04
        )
        XCTAssertEqual(
            NileComposerSurfaceFeedback.scale(
                isHovered: false,
                isActivated: true,
                reduceMotion: false
            ),
            NileComposerSurfaceFeedback.expandedScale
        )
        XCTAssertEqual(
            NileComposerSurfaceFeedback.scale(
                isHovered: true,
                isActivated: true,
                reduceMotion: true
            ),
            1
        )
    }
}
