import Foundation

enum TalkSubmissionSettlement: Equatable {
    case acknowledged
    case paused(message: String)
}

struct TalkSubmissionFailureDisposition: Equatable {
    let uncertain: Bool
    let message: String
}

enum TalkSubmissionPolicy {
    static func canSubmit(
        remoteStatus: String?,
        expectedOwner: TalkOwner,
        currentOwner: TalkOwner?,
        canListen: Bool
    ) -> Bool {
        !busyStatuses.contains(normalizedStatus(remoteStatus))
            && currentOwner == expectedOwner
            && canListen
    }

    static func settlement(
        for status: PromptSubmitStatus,
        terminalArrivedBeforeAcknowledgement: Bool
    ) -> TalkSubmissionSettlement {
        switch status {
        case .streaming:
            terminalArrivedBeforeAcknowledgement
                ? .paused(message: uncorrelatedCompletionMessage)
                : .acknowledged
        case .queued:
            .paused(
                message:
                    "Hermes queued that utterance. Talk is paused so it cannot join a different turn."
            )
        case .steered:
            .paused(
                message:
                    "Hermes added that utterance to an active turn. Talk is paused to avoid speaking the wrong reply."
            )
        }
    }

    static func failure(
        for error: any Error
    ) -> TalkSubmissionFailureDisposition {
        guard let hermes = error as? HermesError else {
            return uncertainFailure
        }
        let uncertain = hermes.isConnectionFailure
            || hermes.requestMayHaveSucceeded
        return TalkSubmissionFailureDisposition(
            uncertain: uncertain,
            message: uncertain
                ? uncertainFailureMessage
                : "Could not send that utterance: \(error.localizedDescription)"
        )
    }

    static let uncertainFailure = TalkSubmissionFailureDisposition(
        uncertain: true,
        message: uncertainFailureMessage
    )

    private static func normalizedStatus(_ status: String?) -> String {
        status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static let busyStatuses = Set([
        "working",
        "waiting",
        "starting",
    ])

    private static let uncertainFailureMessage =
        "Nile could not confirm whether Hermes received that utterance. Check the transcript before continuing."

    private static let uncorrelatedCompletionMessage =
        "Talk paused because a reply arrived before Nile could safely match it to your utterance. Check the transcript before continuing."
}
