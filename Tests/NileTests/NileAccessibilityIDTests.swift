import XCTest
@testable import Nile

final class NileAccessibilityIDTests: XCTestCase {
    func testFeatureConstantsRetainStableExternalValues() {
        XCTAssertEqual(NileAccessibilityID.addGateway, "niles.gateway.add")
        XCTAssertEqual(NileAccessibilityID.sessionShell, "niles.session.shell")
        XCTAssertEqual(NileAccessibilityID.transcript, "niles.transcript")
        XCTAssertEqual(NileAccessibilityID.composer, "niles.composer")
        XCTAssertEqual(NileAccessibilityID.modelPicker, "niles.model_picker")
        XCTAssertEqual(NileAccessibilityID.goalButton, "niles.goal.button")
        XCTAssertEqual(
            NileAccessibilityID.delegationOverview,
            "niles.delegation.overview"
        )
    }

    func testDynamicIDsRetainRawIdentityComponents() {
        XCTAssertEqual(
            NileAccessibilityID.sessionPill("session/a"),
            "niles.session.pill.session/a"
        )
        XCTAssertEqual(
            NileAccessibilityID.markdownTableCell(row: 2, column: 3),
            "niles.markdown.table.cell.2.3"
        )
        XCTAssertEqual(
            NileAccessibilityID.blockingPrompt("prompt/a"),
            "niles.blocking.prompt.prompt/a"
        )
        XCTAssertEqual(
            NileAccessibilityID.delegationAgentRow("agent/a"),
            "niles.delegation.agent.agent/a"
        )
    }

    func testVoiceAndModelKeysRetainStableHashingAndFraming() {
        XCTAssertEqual(
            NileAccessibilityID.hermesVoicePreset(
                provider: "edge",
                voice: "en-US-AriaNeural"
            ),
            "niles.voice.preset.edge_en-US-AriaNeural-f990eac5"
        )
        XCTAssertEqual(
            NileAccessibilityID.modelPinAction(
                provider: nil,
                model: "openai/gpt-5"
            ),
            "niles.model_picker.pin.-1:|12:openai/gpt-5"
        )
    }
}
