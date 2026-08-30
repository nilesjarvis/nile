import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testClarificationProjectsAChoiceAndRetainsOnlyItsSafeLabel() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await repository.yield(
            .clarificationRequest(
                sessionID: "live-one",
                requestID: "clarify-1",
                question: "Which environment?",
                choices: ["Staging", "Production"]
            )
        )
        await eventually {
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        }
        guard case let .blockingPrompt(prompt) =
            model.transcriptEntries.last else {
            return XCTFail("Expected a blocking prompt")
        }
        XCTAssertEqual(prompt.actions.map(\.value), ["Staging", "Production"])
        XCTAssertEqual(model.sessionsNeedingInput, ["one"])
        XCTAssertEqual(
            model.pendingActionableBlockingPromptIDs,
            [prompt.id]
        )
        XCTAssertTrue(model.composerIsBlocked)

        model.respondToBlockingPrompt(
            promptID: prompt.id,
            response: "Production"
        )
        await eventuallyAsync {
            await repository.callCount(
                "clarify.respond:clarify-1:Production"
            ) == 1
        }
        await eventually {
            guard case let .blockingPrompt(updated) =
                model.transcriptEntries.last else {
                return false
            }
            return updated.status == .resolved
                && updated.statusMessage == "Answered: Production"
        }
        XCTAssertTrue(model.sessionsNeedingInput.isEmpty)
        XCTAssertTrue(model.pendingActionableBlockingPromptIDs.isEmpty)
        XCTAssertFalse(
            String(describing: model.transcriptEntries)
                .contains("private-response-never-retain")
        )
    }

    func testSudoResponseUsesTypedCallWithoutRetainingSensitiveInput() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .sudoRequest(sessionID: "live-one", requestID: "sudo-1")
        )
        await eventually {
            model.transcriptEntries.contains {
                guard case let .blockingPrompt(prompt) = $0 else {
                    return false
                }
                return prompt.kind == .sudo
            }
        }
        guard case let .blockingPrompt(prompt) =
            model.transcriptEntries.last else {
            return XCTFail("Expected a sudo prompt")
        }
        let value = "ephemeral-fixture-value"

        model.respondToBlockingPrompt(promptID: prompt.id, response: value)

        await eventuallyAsync {
            await repository.callCount("sudo.respond:sudo-1") == 1
        }
        await eventually {
            guard case let .blockingPrompt(updated) =
                model.transcriptEntries.last else {
                return false
            }
            return updated.status == .resolved
        }
        XCTAssertFalse(String(describing: model).contains(value))
        XCTAssertFalse(
            String(describing: model.transcriptEntries).contains(value)
        )
    }

    func testApprovalFIFOAndDuplicateTapDispatchOnlyTheHeadOnce() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .approvalRequest(
                sessionID: "live-one",
                command: "first",
                description: "First",
                allowPermanent: true
            )
        )
        await repository.yield(
            .approvalRequest(
                sessionID: "live-one",
                command: "second",
                description: "Second",
                allowPermanent: true
            )
        )
        await eventually {
            model.transcriptEntries.compactMap { entry
                -> TranscriptBlockingPrompt? in
                guard case let .blockingPrompt(prompt) = entry else {
                    return nil
                }
                return prompt
            }.count == 2
        }
        let prompts = model.transcriptEntries.compactMap { entry
            -> TranscriptBlockingPrompt? in
            guard case let .blockingPrompt(prompt) = entry else {
                return nil
            }
            return prompt
        }
        XCTAssertTrue(prompts[0].actionable)
        XCTAssertFalse(prompts[1].actionable)
        XCTAssertEqual(
            model.pendingActionableBlockingPromptIDs,
            [prompts[0].id]
        )

        model.respondToBlockingPrompt(
            promptID: prompts[1].id,
            response: "deny"
        )
        model.respondToBlockingPrompt(
            promptID: prompts[0].id,
            response: "once"
        )
        model.respondToBlockingPrompt(
            promptID: prompts[0].id,
            response: "once"
        )

        await eventuallyAsync {
            await repository.callCount(
                "approval.respond:live-one:once"
            ) == 1
        }
        await eventually {
            let updated = model.transcriptEntries.compactMap { entry
                -> TranscriptBlockingPrompt? in
                guard case let .blockingPrompt(prompt) = entry else {
                    return nil
                }
                return prompt
            }
            return updated[0].status == .resolved
                && updated[1].actionable
        }
        XCTAssertEqual(
            model.pendingActionableBlockingPromptIDs,
            [prompts[1].id]
        )
    }

    func testUncertainBlockingResponseFailureDisablesUnsafeRetry() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            sudoResponseError: HermesError(
                "acknowledgement lost",
                requestMayHaveSucceeded: true
            )
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .sudoRequest(sessionID: "live-one", requestID: "sudo-1")
        )
        await eventually {
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        }
        guard case let .blockingPrompt(prompt) =
            model.transcriptEntries.last else {
            return XCTFail("Expected a prompt")
        }

        model.respondToBlockingPrompt(
            promptID: prompt.id,
            response: "ephemeral-fixture-value"
        )

        await eventually {
            guard case let .blockingPrompt(updated) =
                model.transcriptEntries.last else {
                return false
            }
            return updated.status == .uncertain
                && !updated.actionable
        }
        XCTAssertEqual(model.sessionsNeedingInput, ["one"])
    }

    func testBlockingResponseCompletionAfterSwitchCannotMutateDestination() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            blockClarificationResponse: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .clarificationRequest(
                sessionID: "live-one",
                requestID: "clarify-switch",
                question: "Continue?",
                choices: ["Yes", "No"]
            )
        )
        await eventually {
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        }
        guard case let .blockingPrompt(prompt) =
            model.transcriptEntries.last else {
            return XCTFail("Expected a prompt")
        }
        model.respondToBlockingPrompt(promptID: prompt.id, response: "Yes")
        await eventuallyAsync {
            await repository.callCount(
                "clarify.respond:clarify-switch:Yes"
            ) == 1
        }

        await model.selectSession(id: "two")
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        )

        await repository.releaseClarificationResponse()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        )
    }

    func testMessageStartDoesNotCloseAStillWaitingBlockingRequest() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .clarificationRequest(
                sessionID: "live-one",
                requestID: "clarify-still-waiting",
                question: "Continue?",
                choices: ["Yes", "No"]
            )
        )
        await eventually {
            model.sessionsNeedingInput == ["one"]
        }

        await repository.yield(.messageStart(sessionID: "live-one"))
        await eventually {
            guard case let .blockingPrompt(prompt) =
                model.transcriptEntries.last else {
                return false
            }
            return prompt.status == .pending
                && model.sessionsNeedingInput == ["one"]
        }
    }

    func testBackgroundRuntimeCompletionFinalizesItsParkedPrompt() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(
            .sudoRequest(
                sessionID: "live-one",
                requestID: "sudo-background"
            )
        )
        await eventually {
            model.sessionsNeedingInput == ["one"]
        }
        await model.selectSession(id: "two")
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        )

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "done",
                usage: nil
            )
        )

        await eventually {
            model.sessionsNeedingInput.isEmpty
        }
        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case .blockingPrompt = $0 else {
                    return false
                }
                return true
            }
        )
    }

}
