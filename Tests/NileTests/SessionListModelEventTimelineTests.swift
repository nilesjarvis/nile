import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testOrderedEventsDriveAttentionBusyAndConnectionState() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        var lossNotices: [GatewayConnectionLossNotice] = []
        model.installConnectionLossHandler {
            lossNotices.append($0)
        }

        await repository.yield(
            .clarificationRequest(
                sessionID: "live-one",
                requestID: "request-1",
                question: "Continue?",
                choices: nil
            )
        )
        await eventually {
            model.sessionsNeedingInput == ["one"]
        }

        await repository.yield(.messageStart(sessionID: "live-one"))
        await eventually {
            model.activeStatuses["one"] == "working"
                && model.sessionsNeedingInput == ["one"]
        }

        await repository.yield(
            .assistantCompleted(sessionID: "live-one", text: "done", usage: nil)
        )
        await eventually {
            model.activeStatuses["one"] == nil
                && model.sessionsNeedingInput.isEmpty
        }

        let retainedTranscript = model.transcriptEntries
        await repository.yield(
            .connectionLost(
                message: "connection lost",
                authRejected: false,
                retryable: true
            )
        )
        await eventually {
            model.state == .failed("connection lost")
        }
        XCTAssertEqual(model.connectionPhase, .reconnecting)
        XCTAssertFalse(model.showsComposer)
        XCTAssertEqual(model.transcriptEntries, retainedTranscript)
        XCTAssertEqual(
            lossNotices,
            [
                GatewayConnectionLossNotice(
                    message: "connection lost",
                    retryable: true
                ),
            ]
        )
    }

    func testOrderedEventsProjectChronologicalTranscriptAndToolMetadata() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await repository.yield(.messageStart(sessionID: "live-one"))
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "before tool")
        )
        await repository.yield(
            .toolStart(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                detail: nil,
                context: "Running `swift test`",
                generating: false
            )
        )
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "after ")
        )
        await repository.yield(
            .toolComplete(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                result: "all passed",
                outcome: .succeeded,
                summary: "Ran the test suite",
                durationSeconds: 1.2,
                todos: nil,
                inlineDiff: nil
            )
        )
        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "after tool",
                usage: nil
            )
        )

        await eventually {
            model.transcriptEntries.count == 3 && !model.isSending
        }
        XCTAssertEqual(model.transcriptEntries.map(\.id).count, 3)
        guard case let .message(before) = model.transcriptEntries[0],
              case let .tool(tool) = model.transcriptEntries[1],
              case let .message(after) = model.transcriptEntries[2] else {
            return XCTFail("Expected assistant, tool, assistant ordering")
        }
        XCTAssertEqual(before.content, "before tool")
        XCTAssertEqual(tool.label, "Running `swift test`")
        XCTAssertEqual(tool.content, "all passed")
        XCTAssertEqual(tool.summary, "Ran the test suite")
        XCTAssertEqual(tool.durationSeconds, 1.2)
        XCTAssertEqual(after.content, "after tool")
    }

    func testBurstyDeltasPublishOneLosslessTranscriptBatchBeforeTool() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            assistantDeltaPublicationInterval: .seconds(60)
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await repository.yield(.messageStart(sessionID: "live-one"))

        let fragments = (0..<120).map { "fragment-\($0);" }
        for fragment in fragments {
            await repository.yield(
                .assistantDelta(sessionID: "live-one", text: fragment)
            )
        }
        await repository.yield(
            .toolStart(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                detail: nil,
                context: "Run tests",
                generating: false
            )
        )

        await eventually {
            model.transcriptEntries.contains { entry in
                guard case let .tool(tool) = entry else {
                    return false
                }
                return tool.id == "tool-terminal-1"
            }
        }
        XCTAssertEqual(model.assistantDeltaPublicationCount, 1)
        XCTAssertEqual(
            model.transcriptEntries.compactMap { entry -> String? in
                guard case let .message(message) = entry,
                      message.role == .assistant else {
                    return nil
                }
                return message.content
            },
            [fragments.joined()]
        )
    }

    func testHiddenSessionKeepsObservedTimelineAndRestoresItMidTurn() async {
        let idleOne = liveSession(id: "one")
        let idleTwo = liveSession(id: "two")
        let resumedOne = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: idleOne.info,
            messages: [],
            running: true,
            status: "working",
            inflight: InflightTurn(
                user: "Investigate",
                assistant: "Before toolInterim updateAfter tool"
            )
        )
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            openedSessions: [idleOne, idleTwo, resumedOne]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await repository.yield(.messageStart(sessionID: "live-one"))
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "Before tool")
        )
        await eventually {
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.content == "Before tool"
            }
        }

        await model.selectSession(id: "two")
        await repository.yield(
            .toolStart(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                detail: "swift test",
                context: "Running tests",
                generating: false
            )
        )
        await repository.yield(
            .toolComplete(
                sessionID: "live-one",
                toolID: "terminal-1",
                name: "terminal",
                result: "passed",
                outcome: .succeeded,
                summary: "Tests passed",
                durationSeconds: 2,
                todos: [TodoItem(content: "Ship", status: "in_progress")],
                inlineDiff: nil
            )
        )
        await repository.yield(
            .assistantInterim(
                sessionID: "live-one",
                text: "Interim update"
            )
        )
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "After tool")
        )
        await eventually {
            model.activeStatuses["one"] == "working"
        }

        await model.selectSession(id: "one")

        await eventually {
            model.transcriptEntries.compactMap { entry in
                guard case let .message(message) = entry,
                      message.role == .assistant else {
                    return nil
                }
                return message.content
            } == ["Before tool", "Interim update", "After tool"]
        }
        XCTAssertTrue(model.isSending)
        XCTAssertEqual(model.activeTodos?.map(\.content), ["Ship"])
        XCTAssertEqual(model.transcriptEntries.compactMap { entry in
            guard case let .message(message) = entry,
                  message.role == .assistant else {
                return nil
            }
            return message.content
        }, ["Before tool", "Interim update", "After tool"])
        XCTAssertEqual(model.transcriptEntries.compactMap { entry in
            guard case let .tool(tool) = entry else {
                return nil
            }
            return tool.content
        }, ["passed"])
        let resumeCalls = await repository.callCount("session.resume:one")
        XCTAssertEqual(resumeCalls, 2)
    }

    func testAttachedTurnCompletionReopensAuthoritativeHistory() async {
        let initial = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [
                HermesMessage(role: "user", text: "earlier"),
            ],
            running: true,
            status: "working",
            inflight: InflightTurn(
                user: "deploy the fix",
                assistant: "Working on it"
            )
        )
        let completed = LiveSession(
            liveID: "live-one",
            storedID: "one",
            info: SessionInfo(model: nil, provider: nil),
            messages: [
                HermesMessage(role: "user", text: "earlier"),
                HermesMessage(role: "user", text: "deploy the fix"),
                HermesMessage(
                    role: "tool",
                    text: "./deploy.sh",
                    toolName: "terminal"
                ),
                HermesMessage(
                    role: "assistant",
                    text: "Working on it — nearly done. Deployed."
                ),
            ],
            running: false,
            status: "idle",
            inflight: nil
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [initial, completed]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertTrue(model.isSending)
        XCTAssertTrue(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.content == "catching up with a running turn — tool detail appears when it finishes"
            }
        )
        await repository.yield(
            .assistantDelta(
                sessionID: "live-one",
                text: " — nearly done."
            )
        )
        await repository.yield(
            .assistantCompleted(
                sessionID: "live-one",
                text: "Working on it — nearly done. Deployed.",
                usage: nil
            )
        )

        await eventuallyAsync {
            await repository.callCount("session.resume:one") == 2
                && model.transcriptEntries.contains {
                    guard case .tool = $0 else {
                        return false
                    }
                    return true
                }
        }
        XCTAssertFalse(model.isSending)
        XCTAssertFalse(
            model.transcriptEntries.contains {
                guard case let .message(message) = $0 else {
                    return false
                }
                return message.content == "catching up with a running turn — tool detail appears when it finishes"
            }
        )
        XCTAssertEqual(
            model.transcriptEntries.compactMap { entry in
                guard case let .message(message) = entry,
                      message.role == .assistant else {
                    return nil
                }
                return message.content
            },
            ["Working on it — nearly done. Deployed."]
        )
    }

    func testFixtureProjectsShowcaseTranscriptAndStableToolGroup() {
        let model = SessionListModel(fixture: .showcase)

        XCTAssertEqual(model.transcriptEntries.count, 5)
        let rows = model.transcriptEntries.displayRows()
        XCTAssertEqual(rows.count, 4)
        guard case let .toolGroup(tools) = rows[2] else {
            return XCTFail("Expected the two fixture actions to group")
        }
        XCTAssertEqual(tools.map(\.name), ["terminal", "skill_view"])
    }

    func testVisualRegressionBrandFixtureRetainsProjectionPayload() {
        let entries = SessionListModel(fixture: .visualRegressionBrand)
            .transcriptEntries

        XCTAssertEqual(
            entries.map(\.id),
            ["user-1", "assistant-1", "tool-1", "assistant-2"]
        )
        guard case let .tool(tool) = entries[2] else {
            return XCTFail("Expected the retained fixture tool")
        }
        XCTAssertEqual(tool.summary, "Build passed in 18s")
    }

    func testVisualRegressionMediaFixtureRetainsEmbeddedPreview() {
        let entries = SessionListModel(fixture: .visualRegressionMedia)
            .transcriptEntries

        XCTAssertEqual(entries.map(\.id), ["media-user", "media-assistant"])
        guard case let .message(message) = entries[1],
              let attachment = message.attachments.first else {
            return XCTFail("Expected the retained fixture image")
        }
        XCTAssertEqual(message.content, "NILE-CLI-FIXTURE-OK")
        XCTAssertEqual(attachment.path, "/tmp/hermes/images/niles-test-media.png")
        XCTAssertTrue(attachment.previewBase64?.hasPrefix("iVBORw0KGgoAAA") == true)
    }

}
