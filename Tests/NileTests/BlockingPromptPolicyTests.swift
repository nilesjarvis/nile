import XCTest
@testable import Nile

final class BlockingPromptPolicyTests: XCTestCase {
    func testEventFactoryBuildsExactApprovalAndFailClosedInvalidCards() {
        let approval = BlockingPromptEventRequest(
            .approvalRequest(
                sessionID: "live",
                command: "./deploy",
                description: "Deploy production",
                allowPermanent: true
            )
        )
        let approvalPrompt = approval?.makePrompt(sequence: 4)

        XCTAssertEqual(approval?.liveSessionID, "live")
        XCTAssertNil(approval?.requestID)
        XCTAssertNil(approval?.deduplicationKind)
        XCTAssertEqual(approvalPrompt?.id, "blocking-approval-4")
        XCTAssertEqual(
            approvalPrompt?.actions.map(\.value),
            ["once", "session", "always", "deny"]
        )
        XCTAssertEqual(approvalPrompt?.actions.last?.destructive, true)

        let invalid = BlockingPromptEventRequest(
            .blockingRequestInvalid(
                sessionID: "live",
                requestType: "secret.request",
                message: "Malformed secret request"
            )
        )?.makePrompt(sequence: 5)

        XCTAssertEqual(invalid?.id, "blocking-invalid-5")
        XCTAssertEqual(invalid?.kind, .unavailable)
        XCTAssertEqual(invalid?.status, .uncertain)
        XCTAssertFalse(invalid?.actionable ?? true)
        XCTAssertNil(
            BlockingPromptEventRequest(
                .assistantDelta(sessionID: "live", text: "hello")
            )
        )
    }

    func testSensitiveResponseLabelsNeverRetainResponseValues() {
        let secret = BlockingPromptEventRequest(
            .secretRequest(
                sessionID: "live",
                requestID: "request",
                envVar: "TOKEN",
                prompt: "Enter token",
                metadata: nil
            )
        )?.makePrompt(sequence: 1)
        let response = "sensitive-value-never-retain"
        let label = BlockingPromptPolicy.responseLabel(
            prompt: secret!,
            response: response
        )

        XCTAssertEqual(label, "Secret sent")
        XCTAssertFalse(label.contains(response))
        XCTAssertEqual(
            BlockingPromptPolicy.timeoutMilliseconds(for: .secret),
            300_000
        )
        XCTAssertTrue(BlockingPromptPolicy.isRuntimeBusy(status: " Waiting "))
        XCTAssertFalse(BlockingPromptPolicy.isRuntimeBusy(status: "idle"))
    }

    func testProjectionPolicyReplacesKnownCardsAndDropsStaleCards() {
        let prompt = BlockingPromptEventRequest(
            .clarificationRequest(
                sessionID: "live",
                requestID: "request",
                question: "Which environment?",
                choices: ["Staging"]
            )
        )!.makePrompt(sequence: 1)
        let stale = TranscriptBlockingPrompt(
            id: "stale",
            kind: .secret,
            title: "stale"
        )
        let updated = TranscriptBlockingPrompt(
            id: prompt.id,
            kind: prompt.kind,
            title: prompt.title,
            message: prompt.message,
            actions: prompt.actions,
            acceptsText: prompt.acceptsText,
            skipLabel: prompt.skipLabel,
            status: .resolved,
            statusMessage: "Answered",
            actionable: false
        )
        let message = TranscriptMessage(
            id: "message",
            role: .user,
            content: "hello"
        )

        let merged = BlockingPromptPolicy.merge(
            visiblePrompts: [updated],
            into: [
                .message(message),
                .blockingPrompt(prompt),
                .blockingPrompt(stale),
            ]
        )

        XCTAssertEqual(merged.map(\.id), ["message", prompt.id])
        guard case let .blockingPrompt(projected) = merged.last else {
            return XCTFail("Expected the authoritative blocking card")
        }
        XCTAssertEqual(projected.status, .resolved)
        XCTAssertEqual(projected.statusMessage, "Answered")
    }
}
