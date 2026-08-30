import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testVoiceInputPreservesExistingDraftAndPublishesCapturePhases() async {
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(
            fixture: .androidBrand,
            voiceInput: voice
        )
        model.onAppForegroundChanged(true)
        model.updateComposer("Existing draft")

        model.startVoiceInput()
        voice.emit(.preparing)
        voice.emit(.listening(partialText: "spoken words"))

        await eventually {
            model.isListening
                && model.composer == "Existing draft spoken words"
        }
        voice.emit(.transcribing)
        await eventually {
            model.isTranscribing && !model.isListening
        }
        voice.emit(.finished(text: "final words"))
        await eventually {
            !model.isTranscribing
                && !model.isListening
                && model.composer == "Existing draft final words"
        }
    }

    func testTalkKeepsPartialPrivateSubmitsOnceSpeaksAndRelistens() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            synthesizedSpeech: SynthesizedSpeech(
                mimeType: "audio/mpeg",
                bytes: Data([1, 2, 3]),
                provider: "edge"
            )
        )
        let voice = SessionVoiceInputStub()
        let output = SessionSpeechOutputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice,
            speechOutput: output
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)

        model.startTalkMode()
        voice.emit(.preparing)
        voice.emit(.listening(partialText: "private partial"))
        await eventually {
            model.talk?.phase == .listening && model.isListening
        }
        XCTAssertEqual(model.composer, "")
        XCTAssertFalse(
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.content.contains("private partial")
            }
        )

        voice.emit(.transcribing)
        voice.emit(.finished(text: "Hello Hermes"))
        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:Hello Hermes"
            ) == 1
        }
        await eventually {
            model.talk?.phase == .working
        }
        XCTAssertEqual(model.composer, "")

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text:
                    "Here is the answer.\n\nMEDIA:/tmp/private.png",
                usage: nil
            )
        )
        await eventuallyAsync {
            await repository.callCount(
                "speech.synthesize:Here is the answer."
            ) == 1
        }
        await eventually {
            output.played.count == 1
        }
        await eventually {
            voice.startCount == 2
                && model.talk?.phase == .preparingInput
        }
        XCTAssertEqual(output.played.first?.mimeType, "audio/mpeg")
    }

    func testTalkForwarderPublishesNestedRuntimeObservation() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            voiceInput: SessionVoiceInputStub()
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        let changed = expectation(description: "Talk observation changed")

        withObservationTracking {
            _ = model.talk
        } onChange: {
            changed.fulfill()
        }

        model.startTalkMode()

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(model.talk?.phase, .preparingInput)
    }

    func testSpokenReplyUsesSanitizedCompletionAndSessionSwitchStopsOutput() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            synthesizedSpeech: SynthesizedSpeech(
                mimeType: "audio/mpeg",
                bytes: Data([7]),
                provider: nil
            )
        )
        let output = SessionSpeechOutputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: UnavailableVoiceInput(),
            speechOutput: output
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        model.setSpeakRepliesEnabled(true)
        model.updateComposer("Question")
        XCTAssertTrue(model.sendMessage())

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text:
                    "**Answer** with [details](https://example.com).\n\nMEDIA:/tmp/chart.png",
                usage: nil
            )
        )
        await eventuallyAsync {
            await repository.callCount(
                "speech.synthesize:Answer with details."
            ) == 1
        }
        await eventually {
            output.played.count == 1
        }
        let stopsBeforeSwitch = output.stopCount

        await model.selectSession(id: "two")

        XCTAssertGreaterThan(output.stopCount, stopsBeforeSwitch)
        XCTAssertEqual(model.selectedSessionID, "two")
    }

    func testTalkQueuedAdmissionPausesInsteadOfOwningAnotherReply() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitStatus: .queued
        )
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        voice.emit(.listening(partialText: ""))
        voice.emit(.finished(text: "Queue this"))

        await eventually {
            model.talk?.phase == .paused
        }
        XCTAssertEqual(
            model.talk?.message,
            "Hermes queued that utterance. Talk is paused so it cannot join a different turn."
        )
    }

    func testTalkEarlyCompletionBeforeAdmissionIsNeverSpoken() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            blockSubmit: true,
            synthesizedSpeech: SynthesizedSpeech(
                mimeType: "audio/mpeg",
                bytes: Data([1]),
                provider: nil
            )
        )
        let voice = SessionVoiceInputStub()
        let output = SessionSpeechOutputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice,
            speechOutput: output
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        voice.emit(.listening(partialText: ""))
        voice.emit(.finished(text: "Race-safe utterance"))
        await eventuallyAsync {
            await repository.callCount(
                "prompt.submit:live-one:Race-safe utterance"
            ) == 1
        }

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "An unmatched reply",
                usage: nil
            )
        )
        await eventually {
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.role == .assistant
                    && message.content == "An unmatched reply"
            }
        }
        await repository.releaseSubmit()

        await eventually {
            model.talk?.phase == .paused
        }
        XCTAssertEqual(
            model.talk?.message,
            "Talk paused because a reply arrived before Nile could safely match it to your utterance. Check the transcript before continuing."
        )
        XCTAssertTrue(output.played.isEmpty)
        let synthesisCalls = await repository.callCount(
            "speech.synthesize:An unmatched reply"
        )
        XCTAssertEqual(synthesisCalls, 0)
    }

    func testUnavailableSpokenRepliesDisableTheToggleAndReportOnce() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            voiceInput: UnavailableVoiceInput(),
            speechOutput: SessionSpeechOutputStub()
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        model.setSpeakRepliesEnabled(true)
        model.updateComposer("Question")
        XCTAssertTrue(model.sendMessage())
        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Reply",
                usage: nil
            )
        )

        await eventually {
            !model.speakRepliesEnabled
                && model.operationError
                    == "Spoken reply unavailable: This Hermes server does not support spoken replies"
        }
    }

    func testTalkPausesForBlockingPromptAndKeepsItActionable() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        voice.emit(.listening(partialText: "private partial"))
        await eventually {
            model.talk?.phase == .listening
        }

        await repository.yield(
            .clarificationRequest(
                sessionID: "live-one",
                requestID: "talk-clarification",
                question: "Which environment?",
                choices: ["Staging", "Production"]
            )
        )

        await eventually {
            model.talk?.phase == .paused
                && model.talkBlockingPrompt?.actionable == true
        }
        XCTAssertEqual(
            model.talk?.message,
            "Talk paused while Hermes waits for your response."
        )
        XCTAssertEqual(
            model.talkBlockingPrompt?.actions.map(\.value),
            ["Staging", "Production"]
        )
        XCTAssertEqual(model.composer, "")
        XCTAssertGreaterThan(voice.cancelCount, 0)
    }

    func testTalkBackgroundPauseRequiresExplicitForegroundResume() async {
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(
            fixture: .androidBrand,
            voiceInput: voice
        )
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        voice.emit(.listening(partialText: "never persisted"))
        await eventually {
            model.talk?.phase == .listening
        }

        model.onAppForegroundChanged(false)

        XCTAssertEqual(model.talk?.phase, .paused)
        XCTAssertEqual(
            model.talk?.message,
            "Talk paused while Nile is in the background."
        )
        XCTAssertFalse(model.isListening)
        XCTAssertEqual(voice.startCount, 1)
        XCTAssertGreaterThan(voice.cancelCount, 0)

        model.onAppForegroundChanged(true)
        XCTAssertEqual(voice.startCount, 1)
        model.resumeTalkMode()
        XCTAssertEqual(voice.startCount, 2)
    }

    func testTalkDefiniteSubmitFailureRemovesOnlyItsOptimisticEntry() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "request rejected",
                retryable: true,
                requestMayHaveSucceeded: false
            )
        )
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice
        )
        await model.load(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )
        model.transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: "existing-user-entry",
                    role: .user,
                    content: "Duplicate"
                )
            )
        )
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        voice.emit(.listening(partialText: ""))
        voice.emit(.finished(text: "Duplicate"))

        await eventually {
            model.talk?.phase == .paused && !model.isSending
        }
        let matchingMessages = model.transcriptEntries.compactMap {
            entry -> TranscriptMessage? in
            guard case let .message(message) = entry,
                  message.role == .user,
                  message.content == "Duplicate" else {
                return nil
            }
            return message
        }
        XCTAssertEqual(matchingMessages.count, 1)
        XCTAssertFalse(matchingMessages[0].id.hasPrefix("talk-user-"))
    }

    func testUsageForwarderPublishesNestedRuntimeObservation() async {
        let model = SessionListModel(fixture: .empty)
        let changed = expectation(description: "Usage observation changed")

        withObservationTracking {
            _ = model.usage
        } onChange: {
            changed.fulfill()
        }

        model.usage = usageFixture(input: 42, contextPercent: 5)

        await fulfillment(of: [changed], timeout: 1)
    }

    func testStatsForwarderPublishesNestedRuntimeObservation() async {
        let model = SessionListModel(fixture: .empty)
        let changed = expectation(description: "Statistics observation changed")

        withObservationTracking {
            _ = model.gatewayStats
        } onChange: {
            changed.fulfill()
        }

        model.gatewayStats = statsFixture(days: 30, sessions: 42)

        await fulfillment(of: [changed], timeout: 1)
    }

    func testUsageLoadsOnOpenRefreshesAfterTurnAndOpensContextSheet() async {
        let openedUsage = usageFixture(
            input: 12_000,
            contextPercent: 62
        )
        let completedUsage = usageFixture(
            input: 15_000,
            contextPercent: 74,
            categories: [
                ContextCategory(
                    id: "conversation",
                    label: "Conversation",
                    tokens: 30_100
                ),
            ]
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            usageResponses: [openedUsage, completedUsage, completedUsage]
        )
        let model = SessionListModel(
            repository: repository,
            usagePollInterval: .zero,
            usageMaxAttempts: 4
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await eventually { model.usage == openedUsage }

        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Done",
                usage: nil
            )
        )
        await eventually { model.usage == completedUsage }

        model.setContextSheetVisible(true)
        await eventually {
            model.isContextSheetVisible
                && model.usage?.categories.first?.label == "Conversation"
        }
        await eventuallyAsync {
            await repository.callCount("session.usage:live-one") == 3
        }
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "session.usage:live-one" }.count,
            3
        )
    }

    func testLateUsageCannotReplaceNewlySelectedSession() async {
        let oldUsage = usageFixture(input: 111, contextPercent: 20)
        let newUsage = usageFixture(input: 222, contextPercent: 30)
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            openedSessions: [
                liveSession(id: "one"),
                liveSession(id: "two"),
            ],
            usageResponses: [oldUsage, newUsage],
            blockFirstUsage: true
        )
        let model = SessionListModel(
            repository: repository,
            usagePollInterval: .zero,
            usageMaxAttempts: 2
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await eventuallyAsync {
            await repository.callCount("session.usage:live-one") == 1
        }
        await model.selectSession(id: "two")
        await eventually { model.usage == newUsage }

        await repository.releaseUsage()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertEqual(model.usage, newUsage)
    }

    func testStatsLoadsSelectedPeriodAndIndependentHeatmap() async {
        let stats30 = statsFixture(days: 30, sessions: 42)
        let stats91 = statsFixture(days: 91, sessions: 91)
        let stats7 = statsFixture(days: 7, sessions: 7)
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            statsFixtures: [
                7: stats7,
                30: stats30,
                91: stats91,
            ]
        )
        let model = SessionListModel(
            repository: repository,
            usageMaxAttempts: 1
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.setStatsSheetVisible(true)
        await eventually {
            model.gatewayStats == stats30
                && model.heatmapDailyStats == stats91.daily
                && !model.isLoadingHeatmap
        }
        model.selectStatsPeriod(7)
        await eventually {
            model.gatewayStats == stats7
                && model.statsPeriodDays == 7
        }

        let calls = (await repository.calls).filter {
            $0.hasPrefix("gateway.stats:")
        }
        XCTAssertEqual(
            calls,
            [
                "gateway.stats:30",
                "gateway.stats:91",
                "gateway.stats:7",
            ]
        )
        model.setStatsSheetVisible(false)
        XCTAssertFalse(model.isStatsSheetVisible)
    }

    func testDelegationEventsPinGroupThenPersistSettledTranscriptHistory()
        async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")]
        )
        let model = SessionListModel(
            repository: repository,
            usageMaxAttempts: 1
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await eventually { !model.isReconcilingDelegations }

        await repository.yield(
            .subagentUpdate(
                sessionID: "live-one",
                kind: .started,
                data: delegationEvent(
                    id: "agent-1",
                    terminal: nil,
                    summary: nil
                )
            )
        )
        await eventually {
            model.pinnedDelegationTurn?.agents.first?.status == .running
        }
        XCTAssertEqual(model.delegationTurns.count, 1)
        XCTAssertEqual(
            model.pinnedDelegationTurn?.agents.first?.childSessionID,
            "child-1"
        )

        await repository.yield(
            .subagentUpdate(
                sessionID: "live-one",
                kind: .completed,
                data: delegationEvent(
                    id: "agent-1",
                    terminal: .completed,
                    summary: "Verified"
                )
            )
        )
        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Parent finished",
                usage: nil
            )
        )
        await eventually {
            model.pinnedDelegationTurnID == nil
                && model.delegationTurns.first?.agents.first?.status
                    == .finished(.completed)
        }
        await eventuallyAsync {
            await repository.callCount(
                "spawn_tree.save:one:1"
            ) == 1
        }
        XCTAssertTrue(model.transcriptEntries.contains { entry in
            guard case .delegation = entry else {
                return false
            }
            return true
        })
        XCTAssertNil(model.delegationControlError)
    }

    func testDelegationInterruptAndOpenChildUseCurrentOwner() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [
                liveSession(id: "one"),
                liveSession(id: "child-1"),
            ]
        )
        let model = SessionListModel(
            repository: repository,
            usageMaxAttempts: 1
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await eventually { !model.isReconcilingDelegations }
        await repository.yield(
            .subagentUpdate(
                sessionID: "live-one",
                kind: .started,
                data: delegationEvent(
                    id: "agent-1",
                    terminal: nil,
                    summary: nil
                )
            )
        )
        await eventually { model.pinnedDelegationTurn != nil }

        model.interruptDelegatedAgent("agent-1")
        await eventuallyAsync {
            await repository.callCount(
                "subagent.interrupt:agent-1"
            ) == 1
        }
        XCTAssertEqual(
            model.pinnedDelegationTurn?.agents.first?.status,
            .interrupting
        )

        model.openDelegatedChild("child-1")
        await eventually { model.selectedSessionID == "child-1" }
        XCTAssertEqual(model.liveSession?.liveID, "live-child-1")
        XCTAssertTrue(model.sessions.contains { $0.id == "child-1" })
    }

}
