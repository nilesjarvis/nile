import XCTest
@testable import Nile

final class NileSlashPolicyTests: XCTestCase {
    func testNativeCommandsAndSubgoalFormsMatchPinnedMobilePolicy() {
        XCTAssertEqual(NileSlashPolicy.decide("/new").surface, .nativeNew)
        XCTAssertEqual(NileSlashPolicy.decide("/reset").surface, .nativeNew)
        XCTAssertEqual(NileSlashPolicy.decide("/model").surface, .nativeModel)
        XCTAssertEqual(NileSlashPolicy.decide("/help").surface, .nativeHelp)
        XCTAssertEqual(NileSlashPolicy.decide("/commands").surface, .nativeHelp)
        XCTAssertEqual(NileSlashPolicy.decide("/goal").surface, .nativeGoal)
        XCTAssertEqual(
            NileSlashPolicy.decide("/reasoning xhigh"),
            NileSlashDecision(
                name: "reasoning",
                surface: .nativeReasoning,
                argument: "xhigh"
            )
        )
        XCTAssertEqual(NileSlashPolicy.decide("/subgoal").surface, .slashExec)
        XCTAssertEqual(
            NileSlashPolicy.decide("/subgoal release must pass").surface,
            .slashExec
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/subgoal remove 2").surface,
            .slashExec
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/subgoal clear").surface,
            .slashExec
        )
    }

    func testUnsafeAndMalformedCommandsKeepDraftWithExactGuidance() {
        let history = NileSlashPolicy.decide("/undo")
        XCTAssertEqual(history.surface, .blocked)
        XCTAssertTrue(history.message?.contains("rewrite conversation") == true)
        XCTAssertTrue(history.message?.contains("draft was kept") == true)

        XCTAssertEqual(
            NileSlashPolicy.decide("/new title").surface,
            .blocked
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/reasoning future").surface,
            .blocked
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/subgoal remove 0").surface,
            .blocked
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/subgoal clear now").surface,
            .blocked
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/status\n/approve").surface,
            .blocked
        )
        XCTAssertEqual(
            NileSlashPolicy.decide("/unknown").surface,
            .blocked
        )
    }

}
