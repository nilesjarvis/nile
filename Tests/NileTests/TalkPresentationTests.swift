import XCTest
@testable import Nile

final class TalkPresentationTests: XCTestCase {
    func testEveryPhaseProjectsPinnedCopyAndPrimaryAction() {
        let cases: [(
            phase: TalkPhase,
            status: String,
            detail: String,
            action: TalkPresentation.PrimaryAction?
        )] = [
            (
                .off,
                "Getting ready…",
                "Starting the conversation on this device.",
                nil
            ),
            (
                .preparingInput,
                "Preparing microphone…",
                "Nile records the utterance; Hermes handles transcription.",
                .pause
            ),
            (
                .listening,
                "Listening…",
                "Speak naturally. Hermes will respond when you pause.",
                .pause
            ),
            (
                .transcribing,
                "Hermes is transcribing…",
                "The microphone is closed while Hermes processes your recording.",
                .pause
            ),
            (
                .submitting,
                "Sending…",
                "Your utterance is being sent to Hermes.",
                nil
            ),
            (
                .working,
                "Working…",
                "Hermes is preparing a response.",
                nil
            ),
            (
                .preparingSpeech,
                "Preparing voice…",
                "The first part of Hermes's response will begin shortly.",
                .interruptSpeech
            ),
            (
                .speaking,
                "Speaking…",
                "Tap Listen to skip the rest of the reply.",
                .interruptSpeech
            ),
            (
                .paused,
                "Microphone paused",
                "Resume when you are ready to continue.",
                .resume
            ),
        ]

        for expected in cases {
            let presentation = TalkPresentation(
                phase: expected.phase,
                workingLabel: nil,
                hasBlockingPrompt: false,
                runActive: false
            )

            XCTAssertEqual(presentation.status, expected.status)
            XCTAssertEqual(presentation.detail, expected.detail)
            XCTAssertEqual(presentation.primaryAction, expected.action)
        }
    }

    func testBlockingPromptOverridesPhaseAndOnlyOffersActiveRunStop() {
        let inactive = TalkPresentation(
            phase: .listening,
            workingLabel: nil,
            hasBlockingPrompt: true,
            runActive: false
        )
        let active = TalkPresentation(
            phase: .speaking,
            workingLabel: "Downloading",
            hasBlockingPrompt: true,
            runActive: true
        )

        XCTAssertEqual(inactive.status, "Hermes needs your input")
        XCTAssertEqual(
            inactive.detail,
            "Listening is paused until the request is resolved."
        )
        XCTAssertNil(inactive.primaryAction)
        XCTAssertEqual(active.status, inactive.status)
        XCTAssertEqual(active.detail, inactive.detail)
        XCTAssertEqual(active.primaryAction, .stopRun)
    }

    func testRemoteTurnPhasesOfferStopOnlyWhileRunIsActive() {
        for phase in [TalkPhase.submitting, .working] {
            XCTAssertNil(
                TalkPresentation(
                    phase: phase,
                    workingLabel: nil,
                    hasBlockingPrompt: false,
                    runActive: false
                ).primaryAction
            )
            XCTAssertEqual(
                TalkPresentation(
                    phase: phase,
                    workingLabel: nil,
                    hasBlockingPrompt: false,
                    runActive: true
                ).primaryAction,
                .stopRun
            )
        }
    }

    func testWorkingLabelAndSpeakingDetailReflectAuthoritativeRunState() {
        let working = TalkPresentation(
            phase: .working,
            workingLabel: "Using tools",
            hasBlockingPrompt: false,
            runActive: true
        )
        let blankWorking = TalkPresentation(
            phase: .working,
            workingLabel: "  ",
            hasBlockingPrompt: false,
            runActive: false
        )
        let speaking = TalkPresentation(
            phase: .speaking,
            workingLabel: nil,
            hasBlockingPrompt: false,
            runActive: true
        )

        XCTAssertEqual(working.status, "Using tools")
        XCTAssertEqual(blankWorking.status, "Working…")
        XCTAssertEqual(
            speaking.detail,
            "Hermes is still responding. Tap Listen to interrupt and start a new turn."
        )
        XCTAssertEqual(speaking.primaryAction, .interruptSpeech)
    }
}
