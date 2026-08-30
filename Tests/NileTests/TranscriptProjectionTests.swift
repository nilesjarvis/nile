import SwiftUI
import UIKit
import XCTest
@testable import Nile

final class TranscriptProjectionTests: XCTestCase {
    @MainActor
    func testHostingCellTransferCannotBeUndoneByOldCellReuse() {
        let host = UIHostingController(
            rootView: AnyView(Text("Stable row"))
        )
        let first = TranscriptHostingCell(frame: .zero)
        let second = TranscriptHostingCell(frame: .zero)

        first.install(host)
        XCTAssertTrue(host.view.superview === first.contentView)

        second.install(host)
        XCTAssertTrue(host.view.superview === second.contentView)

        first.prepareForReuse()
        XCTAssertTrue(
            host.view.superview === second.contentView,
            "A reused former cell must not remove a host from its new cell."
        )
    }

    func testViewportDiffTargetsOneChangedRowInLargeTranscript() {
        let previous = (0..<400).map { index in
            TranscriptViewportItem(
                id: "message-\(index)",
                content: .row(
                    .entry(
                        .message(
                            TranscriptMessage(
                                id: "message-\(index)",
                                role: .assistant,
                                content: "Settled response \(index)"
                            )
                        )
                    )
                ),
                reduceMotion: true
            )
        }
        var next = previous
        next[399] = TranscriptViewportItem(
            id: "message-399",
            content: .row(
                .entry(
                    .message(
                        TranscriptMessage(
                            id: "message-399",
                            role: .assistant,
                            content: "Settled response 399 plus one delta"
                        )
                    )
                )
            ),
            streaming: true,
            reduceMotion: true
        )

        let changes = TranscriptViewportChangeSet(
            previousItemsByID: Dictionary(
                uniqueKeysWithValues: previous.map { ($0.id, $0) }
            ),
            previousIDs: previous.map(\.id),
            nextItems: next
        )

        XCTAssertFalse(changes.structureChanged)
        XCTAssertTrue(changes.removedIDs.isEmpty)
        XCTAssertEqual(changes.changedIDs, ["message-399"])
        XCTAssertEqual(changes.nextItemsByID.count, 400)
    }

    func testHistoricalProjectionPreservesToolAndImageMetadata() {
        let toolText = "tests passed"
        let toolEntry = HermesMessage(
            role: "tool",
            text: toolText,
            toolName: "terminal",
            toolContext: "./gradlew test"
        ).transcriptEntry(index: 2)
        guard case let .tool(tool) = toolEntry else {
            return XCTFail("Expected a tool")
        }
        XCTAssertEqual(
            tool.id,
            "history-2-tool-\(javaStringHash(toolText))"
        )
        XCTAssertEqual(tool.kind, .terminal)
        XCTAssertEqual(tool.status, "recorded")
        XCTAssertEqual(tool.label, "./gradlew test")

        let userEntry = HermesMessage(
            role: "user",
            text: "Look here\n\n[Image attached at: /private/a.png]"
        ).transcriptEntry(
            index: 3,
            imageCache: ["/private/a.png": "cached-bytes"]
        )
        guard case let .message(user) = userEntry else {
            return XCTFail("Expected a message")
        }
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.content, "Look here")
        XCTAssertEqual(
            user.images,
            [MessageImage(base64: "cached-bytes", label: "a.png")]
        )

        let assistantEntry = HermesMessage(
            role: "assistant",
            text: "caption data:image/jpeg;base64,QUJD"
        ).transcriptEntry(index: 4)
        guard case let .message(assistant) = assistantEntry else {
            return XCTFail("Expected a message")
        }
        XCTAssertEqual(assistant.content, "caption")
        XCTAssertEqual(
            assistant.images,
            [MessageImage(base64: "QUJD", label: "image")]
        )
    }

    func testUserMediaTextRemainsLiteral() {
        let entry = HermesMessage(
            role: "user",
            text: "Explain MEDIA:/home/hermes/images/chart.png"
        ).transcriptEntry(index: 7)
        guard case let .message(message) = entry else {
            return XCTFail("Expected a message")
        }
        XCTAssertEqual(
            message.content,
            "Explain MEDIA:/home/hermes/images/chart.png"
        )
        XCTAssertTrue(message.attachments.isEmpty)
    }

    func testHistoricalTerminalOutcomeAndClarificationTrace() {
        let stoppedEntry = HermesMessage(
            role: "tool",
            text: "partial output",
            toolName: "terminal",
            toolContext: "sleep 30",
            toolOutcome: .interrupted
        ).transcriptEntry(index: 5)
        guard case let .tool(stopped) = stoppedEntry else {
            return XCTFail("Expected a tool")
        }
        XCTAssertEqual(stopped.status, "stopped")
        XCTAssertEqual(stopped.outcome, .interrupted)

        let answeredEntry = HermesMessage(
            role: "tool",
            text: "Decision answered",
            toolName: "clarify",
            toolOutcome: .succeeded
        ).transcriptEntry(index: 6)
        guard case let .message(answered) = answeredEntry else {
            return XCTFail("Expected a message")
        }
        XCTAssertEqual(answered.role, .system)
        XCTAssertEqual(answered.content, "Decision answered")
    }

    func testToolPresentationAndMCPRulesMatchAndroid() {
        XCTAssertEqual(toolKind("terminal"), .terminal)
        XCTAssertEqual(toolKind("execute_code"), .terminal)
        XCTAssertEqual(toolKind("memory"), .memory)
        XCTAssertEqual(toolKind("skill_manage"), .skill)
        XCTAssertEqual(toolKind("http_request"), .tool)

        XCTAssertEqual(defaultToolLabel("terminal"), "Running terminal command")
        XCTAssertEqual(defaultToolLabel("execute_code"), "Running code")
        XCTAssertEqual(defaultToolLabel("skill_manage"), "Updating skill")
        XCTAssertEqual(defaultToolLabel("http_request"), "Http Request")
        XCTAssertEqual(defaultToolLabel("__"), "Tool")

        XCTAssertTrue(isMCPToolName("mcp__github__get_issue"))
        XCTAssertTrue(isMCPToolName("mcp.github.get_issue"))
        XCTAssertFalse(isMCPToolName("mcp_github_get_issue"))
    }

    func testStandingGoalAndDisplayGroupingRules() {
        let objective = "Create a layered SVG scene and verify it renders"
        let historical = HermesMessage(
            role: "user",
            text: "  Create a layered SVG scene   and verify it renders  "
        ).transcriptEntry(index: 1, goalObjective: objective)
        guard case let .message(goalMessage) = historical else {
            return XCTFail("Expected a message")
        }
        XCTAssertTrue(goalMessage.isGoalPrompt)

        let one = TranscriptTool(
            id: "one",
            name: "terminal",
            status: "done",
            content: ""
        )
        let two = TranscriptTool(
            id: "two",
            name: "memory",
            status: "done",
            content: ""
        )
        let rows = [
            TranscriptEntry.tool(one),
            .tool(two),
            .message(
                TranscriptMessage(
                    id: "reply",
                    role: .assistant,
                    content: "done"
                )
            ),
        ].displayRows()
        XCTAssertEqual(rows.map(\.id), ["one", "reply"])
        guard case let .toolGroup(tools) = rows.first else {
            return XCTFail("Expected grouped tools")
        }
        XCTAssertEqual(tools.map(\.id), ["one", "two"])
    }

    func testPresentationProjectsRowsAndViewportSignalsInOnePass() {
        let entries: [TranscriptEntry] = [
            .message(
                TranscriptMessage(
                    id: "user",
                    role: .user,
                    content: "Question"
                )
            ),
            .tool(
                TranscriptTool(
                    id: "clarify-tool",
                    name: "clarify",
                    status: "done",
                    content: "hidden"
                )
            ),
            .tool(
                TranscriptTool(
                    id: "terminal",
                    name: "terminal",
                    status: "done",
                    content: "one"
                )
            ),
            .tool(
                TranscriptTool(
                    id: "memory",
                    name: "memory",
                    status: "done",
                    content: "two"
                )
            ),
            .delegation(
                TranscriptDelegation(
                    id: "pinned-delegation",
                    turnID: "pinned"
                )
            ),
            .blockingPrompt(
                TranscriptBlockingPrompt(
                    id: "prompt",
                    kind: .approval,
                    title: "Approve?"
                )
            ),
            .message(
                TranscriptMessage(
                    id: "assistant",
                    role: .assistant,
                    content: "Streaming"
                )
            ),
        ]

        let presentation = TranscriptPresentation(
            entries: entries,
            isSending: true,
            pinnedDelegationTurnID: "pinned"
        )

        XCTAssertEqual(
            presentation.rows.map(\.id),
            ["user", "terminal", "prompt", "assistant"]
        )
        guard case let .toolGroup(tools) = presentation.rows[1] else {
            return XCTFail("Expected adjacent tools to share one row")
        }
        XCTAssertEqual(tools.map(\.id), ["terminal", "memory"])
        XCTAssertEqual(presentation.lastUserEntryID, "user")
        XCTAssertEqual(presentation.streamingEntryID, "assistant")
        XCTAssertTrue(presentation.hasBlockingPrompt)
    }

    func testPresentationFiltersEmptyAssistantRowsExceptStreamingTail() {
        let entries: [TranscriptEntry] = [
            .message(
                TranscriptMessage(
                    id: "blank",
                    role: .assistant,
                    content: "  "
                )
            ),
            .message(
                TranscriptMessage(
                    id: "null",
                    role: .assistant,
                    content: "NULL"
                )
            ),
            .message(
                TranscriptMessage(
                    id: "image",
                    role: .assistant,
                    content: "",
                    images: [MessageImage(base64: "image", label: "image")]
                )
            ),
            .message(
                TranscriptMessage(
                    id: "user",
                    role: .user,
                    content: "Question"
                )
            ),
            .message(
                TranscriptMessage(
                    id: "tail",
                    role: .assistant,
                    content: ""
                )
            ),
        ]

        let settled = TranscriptPresentation(
            entries: entries,
            isSending: false,
            pinnedDelegationTurnID: nil
        )
        let streaming = TranscriptPresentation(
            entries: entries,
            isSending: true,
            pinnedDelegationTurnID: nil
        )

        XCTAssertEqual(settled.rows.map(\.id), ["image", "user"])
        XCTAssertNil(settled.streamingEntryID)
        XCTAssertEqual(streaming.rows.map(\.id), ["image", "user", "tail"])
        XCTAssertEqual(streaming.streamingEntryID, "tail")
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
