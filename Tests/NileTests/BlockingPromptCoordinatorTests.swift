import XCTest
@testable import Nile

@MainActor
final class BlockingPromptCoordinatorTests: XCTestCase {
    func testSafeCardsDeduplicateRequestIDsAndExposeMalformedRequests() {
        let coordinator = BlockingPromptCoordinator(
            monotonicMilliseconds: { 100 }
        )
        let clarification = clarification(requestID: "shared")

        XCTAssertEqual(
            coordinator.handleEvent(
                clarification,
                gatewayID: "gateway",
                fallbackStoredSessionID: "stored"
            ),
            .added(liveSessionID: "live")
        )
        XCTAssertEqual(
            coordinator.handleEvent(
                clarification,
                gatewayID: "gateway",
                fallbackStoredSessionID: "stored"
            ),
            .consumed
        )
        _ = coordinator.handleEvent(
            .sudoRequest(sessionID: "live", requestID: "shared"),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        _ = coordinator.handleEvent(
            .secretRequest(
                sessionID: "live",
                requestID: "secret",
                envVar: "DEPLOY_TOKEN",
                prompt: "Enter token",
                metadata: SecretRequestMetadata(
                    skillName: "deploy",
                    help: "Stored nowhere",
                    requiredFor: "release"
                )
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        _ = coordinator.handleEvent(
            .blockingRequestInvalid(
                sessionID: "live",
                requestType: "secret.request",
                message: "Malformed secret request"
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )

        let prompts = coordinator.visiblePrompts(
            gatewayID: "gateway",
            liveSessionID: "live",
            storedSessionID: "stored"
        )
        XCTAssertEqual(
            prompts.map(\.id),
            [
                "blocking-clarify-shared-1",
                "blocking-sudo-shared-2",
                "blocking-secret-secret-3",
                "blocking-invalid-4",
            ]
        )
        XCTAssertEqual(
            prompts[2].detail,
            "Environment variable: DEPLOY_TOKEN\nSkill: deploy\nRequired for: release\nStored nowhere"
        )
        XCTAssertTrue(prompts[1].sensitive)
        XCTAssertTrue(prompts[2].sensitive)
        XCTAssertEqual(prompts[3].kind, .unavailable)
        XCTAssertEqual(prompts[3].status, .uncertain)
        XCTAssertFalse(prompts[3].actionable)
    }

    func testApprovalFIFOAndAllowedChoicesAreExact() {
        let coordinator = BlockingPromptCoordinator()
        _ = coordinator.handleEvent(
            approval(command: "first", allowPermanent: true),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        _ = coordinator.handleEvent(
            approval(command: "second", allowPermanent: false),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        coordinator.refreshPresentation(gatewayID: "gateway")
        var prompts = visible(coordinator)

        XCTAssertTrue(prompts[0].actionable)
        XCTAssertFalse(prompts[1].actionable)
        XCTAssertEqual(
            prompts[0].actions.map(\.value),
            ["once", "session", "always", "deny"]
        )
        XCTAssertEqual(
            prompts[1].actions.map(\.value),
            ["once", "session", "deny"]
        )
        XCTAssertNil(
            coordinator.beginResponse(
                promptID: prompts[1].id,
                response: "once"
            )
        )
        XCTAssertNil(
            coordinator.beginResponse(
                promptID: prompts[0].id,
                response: "invalid"
            )
        )

        let submission = coordinator.beginResponse(
            promptID: prompts[0].id,
            response: "always"
        )
        XCTAssertEqual(submission?.approvalChoice, .always)
        XCTAssertEqual(submission?.resolvedStatusMessage, "Always allowed")
        XCTAssertNil(coordinator.responseTarget(promptID: prompts[0].id))
        XCTAssertTrue(
            coordinator.resolveSubmission(
                promptID: prompts[0].id,
                statusMessage: submission!.resolvedStatusMessage
            )
        )
        coordinator.refreshPresentation(gatewayID: "gateway")
        prompts = visible(coordinator)
        XCTAssertEqual(prompts[0].status, .resolved)
        XCTAssertTrue(prompts[1].actionable)
    }

    func testSensitiveSubmissionRetainsOnlySafeSummary() {
        let coordinator = BlockingPromptCoordinator()
        _ = coordinator.handleEvent(
            .secretRequest(
                sessionID: "live",
                requestID: "secret",
                envVar: "TOKEN",
                prompt: "Enter token",
                metadata: nil
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        let promptID = visible(coordinator).single!.id
        let secret = "secret-value-never-retain"

        let submission = coordinator.beginResponse(
            promptID: promptID,
            response: secret
        )

        XCTAssertEqual(submission?.resolvedStatusMessage, "Secret sent")
        XCTAssertFalse(String(describing: submission).contains(secret))
        XCTAssertFalse(String(describing: visible(coordinator)).contains(secret))
        XCTAssertTrue(
            coordinator.markSubmissionUncertain(
                promptID: promptID,
                message: "Hermes may have received the response."
            )
        )
        XCTAssertEqual(visible(coordinator).single?.status, .uncertain)
        XCTAssertNil(coordinator.retrySubmission(promptID: promptID))
    }

    func testSubmissionFailureBoundariesMatchHermesSafetyRules() async throws {
        let retryCoordinator = BlockingPromptCoordinator()
        _ = retryCoordinator.handleEvent(
            clarification(requestID: "retry"),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        let retryID = visible(retryCoordinator).single!.id
        let retrySubmission = retryCoordinator.beginResponse(
            promptID: retryID,
            response: "answer"
        )!
        let retryOutcome = try await retryCoordinator.submitResponse(
            retrySubmission,
            response: "answer"
        ) { _, _ in
            throw HermesError("definitely rejected")
        }
        guard case let .retryableFailure(target, error) = retryOutcome else {
            return XCTFail("Expected a definite retry")
        }
        XCTAssertEqual(
            target,
            BlockingPromptResponseTarget(
                gatewayID: "gateway",
                liveSessionID: "live",
                storedSessionID: "stored"
            )
        )
        XCTAssertEqual(error.localizedDescription, "definitely rejected")
        XCTAssertEqual(visible(retryCoordinator).single?.status, .pending)

        let uncertainSubmission = retryCoordinator.beginResponse(
            promptID: retryID,
            response: "second"
        )!
        _ = try await retryCoordinator.submitResponse(
            uncertainSubmission,
            response: "second"
        ) { _, _ in
            throw HermesError(
                "acknowledgement lost",
                requestMayHaveSucceeded: true
            )
        }
        XCTAssertEqual(visible(retryCoordinator).single?.status, .uncertain)

        let approvalCoordinator = BlockingPromptCoordinator()
        _ = approvalCoordinator.handleEvent(
            approval(command: "deploy", allowPermanent: true),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        let approvalID = visible(approvalCoordinator).single!.id
        let approvalSubmission = approvalCoordinator.beginResponse(
            promptID: approvalID,
            response: "once"
        )!
        _ = try await approvalCoordinator.submitResponse(
            approvalSubmission,
            response: "once"
        ) { _, _ in
            throw HermesError("resolver failed", code: 5004)
        }
        XCTAssertEqual(
            visible(approvalCoordinator).single?.status,
            .uncertain
        )
        XCTAssertEqual(
            visible(approvalCoordinator).single?.statusMessage,
            "Hermes may have handled this approval. Stop the run if it stays blocked."
        )
    }

    func testApprovalNegativeResultClosesTheRuntimeFIFO() async throws {
        let coordinator = BlockingPromptCoordinator()
        _ = coordinator.handleEvent(
            approval(command: "first", allowPermanent: true),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        _ = coordinator.handleEvent(
            approval(command: "second", allowPermanent: true),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        coordinator.refreshPresentation(gatewayID: "gateway")
        let submission = coordinator.beginResponse(
            promptID: visible(coordinator)[0].id,
            response: "session"
        )!

        let outcome = await coordinator.submitResponse(
            submission,
            response: "session"
        ) { _, _ in false }

        guard case .settled = outcome else {
            return XCTFail("Expected settled")
        }
        XCTAssertTrue(
            visible(coordinator).allSatisfy {
                $0.status == .unavailable
                    && $0.statusMessage
                        == "These approval requests are no longer waiting."
            }
        )
    }

    func testBindingReplacementExpiryAndStatusWatermarkStayScoped() {
        var now: Int64 = 0
        let coordinator = BlockingPromptCoordinator(
            monotonicMilliseconds: { now }
        )
        _ = coordinator.handleEvent(
            clarification(requestID: "old"),
            gatewayID: "gateway",
            fallbackStoredSessionID: nil
        )
        coordinator.bindSession(
            gatewayID: "gateway",
            liveSessionID: "live",
            storedSessionID: "stored",
            turnInFlight: true
        )
        XCTAssertEqual(visible(coordinator).count, 1)

        let poll = coordinator.beginStatusPoll()
        _ = coordinator.handleEvent(
            .sudoRequest(sessionID: "replacement", requestID: "new"),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored-2"
        )
        XCTAssertTrue(
            coordinator.reconcileStatusPoll(
                token: poll,
                gatewayID: "gateway",
                currentGatewayID: "gateway",
                statuses: ["stored": "idle", "stored-2": "idle"]
            )
        )
        XCTAssertEqual(visible(coordinator).single?.status, .unavailable)
        XCTAssertEqual(
            coordinator.visiblePrompts(
                gatewayID: "gateway",
                liveSessionID: "replacement",
                storedSessionID: "stored-2"
            ).single?.status,
            .pending
        )

        now = 120_001
        coordinator.refreshPresentation(gatewayID: "gateway")
        XCTAssertEqual(
            coordinator.visiblePrompts(
                gatewayID: "gateway",
                liveSessionID: "replacement",
                storedSessionID: "stored-2"
            ).single?.statusMessage,
            "This request timed out."
        )
    }

    func testProjectionReplacesVisibleCardsAndKeepsAttentionGatewayScoped() {
        let coordinator = BlockingPromptCoordinator()
        _ = coordinator.handleEvent(
            clarification(requestID: "request"),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        let prompt = visible(coordinator).single!
        let stale = TranscriptBlockingPrompt(
            id: "stale",
            kind: .secret,
            title: "stale"
        )
        let transcript: [TranscriptEntry] = [
            .message(
                TranscriptMessage(
                    id: "message",
                    role: .user,
                    content: "hello"
                )
            ),
            .blockingPrompt(prompt),
            .blockingPrompt(stale),
        ]

        let projection = coordinator.project(
            gatewayID: "gateway",
            liveSessionID: "live",
            storedSessionID: "stored",
            transcript: transcript
        )

        XCTAssertEqual(
            projection.transcript.map(\.id),
            ["message", prompt.id]
        )
        XCTAssertEqual(projection.sessionsNeedingInput, ["stored"])
    }

    private func visible(
        _ coordinator: BlockingPromptCoordinator
    ) -> [TranscriptBlockingPrompt] {
        coordinator.visiblePrompts(
            gatewayID: "gateway",
            liveSessionID: "live",
            storedSessionID: "stored"
        )
    }

    private func clarification(requestID: String) -> HermesStreamEvent {
        .clarificationRequest(
            sessionID: "live",
            requestID: requestID,
            question: "Which environment?",
            choices: ["Staging", "Production"]
        )
    }

    private func approval(
        command: String,
        allowPermanent: Bool
    ) -> HermesStreamEvent {
        .approvalRequest(
            sessionID: "live",
            command: "./deploy \(command)",
            description: command,
            allowPermanent: allowPermanent
        )
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
