import Foundation
import XCTest
@testable import Nile

final class TalkSubmissionPolicyTests: XCTestCase {
    func testAdmissionNormalizesBusyStatusAndRequiresExactOwner() {
        let owner = makeOwner(liveSessionID: "live")

        XCTAssertFalse(
            TalkSubmissionPolicy.canSubmit(
                remoteStatus: " Waiting \n",
                expectedOwner: owner,
                currentOwner: owner,
                canListen: true
            )
        )
        XCTAssertFalse(
            TalkSubmissionPolicy.canSubmit(
                remoteStatus: "idle",
                expectedOwner: owner,
                currentOwner: makeOwner(liveSessionID: "replacement"),
                canListen: true
            )
        )
        XCTAssertTrue(
            TalkSubmissionPolicy.canSubmit(
                remoteStatus: "idle",
                expectedOwner: owner,
                currentOwner: owner,
                canListen: true
            )
        )
    }

    func testSettlementsKeepOnlyCorrelatedStreamingReplyActionable() {
        XCTAssertEqual(
            TalkSubmissionPolicy.settlement(
                for: .streaming,
                terminalArrivedBeforeAcknowledgement: false
            ),
            .acknowledged
        )
        XCTAssertEqual(
            TalkSubmissionPolicy.settlement(
                for: .streaming,
                terminalArrivedBeforeAcknowledgement: true
            ),
            .paused(
                message:
                    "Talk paused because a reply arrived before Nile could safely match it to your utterance. Check the transcript before continuing."
            )
        )
        XCTAssertEqual(
            TalkSubmissionPolicy.settlement(
                for: .queued,
                terminalArrivedBeforeAcknowledgement: false
            ),
            .paused(
                message:
                    "Hermes queued that utterance. Talk is paused so it cannot join a different turn."
            )
        )
        XCTAssertEqual(
            TalkSubmissionPolicy.settlement(
                for: .steered,
                terminalArrivedBeforeAcknowledgement: false
            ),
            .paused(
                message:
                    "Hermes added that utterance to an active turn. Talk is paused to avoid speaking the wrong reply."
            )
        )
    }

    func testFailureClassificationRetriesOnlyDefiniteHermesRejection() {
        let definite = TalkSubmissionPolicy.failure(
            for: HermesError("rejected")
        )
        let connection = TalkSubmissionPolicy.failure(
            for: HermesError("lost", isConnectionFailure: true)
        )
        let unknown = TalkSubmissionPolicy.failure(
            for: URLError(.networkConnectionLost)
        )

        XCTAssertFalse(definite.uncertain)
        XCTAssertEqual(
            definite.message,
            "Could not send that utterance: rejected"
        )
        XCTAssertTrue(connection.uncertain)
        XCTAssertEqual(
            connection.message,
            TalkSubmissionPolicy.uncertainFailure.message
        )
        XCTAssertEqual(unknown, TalkSubmissionPolicy.uncertainFailure)
    }

    private func makeOwner(liveSessionID: String) -> TalkOwner {
        TalkOwner(
            connectionGeneration: 3,
            gatewayID: "gateway",
            gatewayKey: "gateway",
            selectedSessionID: "stored",
            transcriptSessionID: "stored",
            liveSessionID: liveSessionID
        )
    }
}
