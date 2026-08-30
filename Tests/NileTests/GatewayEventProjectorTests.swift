import XCTest
@testable import Nile

final class GatewayEventProjectorTests: XCTestCase {
    private let projector = GatewayEventProjector()

    func testMessageChannelsKeepThinkingReplacementSeparateFromReasoningAppend() {
        XCTAssertEqual(
            project("message.start"),
            .messageStart(sessionID: "live-1")
        )
        XCTAssertEqual(
            project("message.delta", ["text": .string("hi")]),
            .assistantDelta(sessionID: "live-1", text: "hi")
        )
        XCTAssertEqual(
            project("message.interim", ["text": .string("checking")]),
            .assistantInterim(sessionID: "live-1", text: "checking")
        )
        XCTAssertNil(project("message.interim", ["text": .string(" ")]))
        XCTAssertEqual(
            project("thinking.delta", ["text": .string("searching")]),
            .thinkingStatus(sessionID: "live-1", text: "searching")
        )
        XCTAssertEqual(
            project("reasoning.delta", ["text": .string("because")]),
            .thinkingDelta(sessionID: "live-1", text: "because")
        )
        XCTAssertEqual(
            project(
                "message.complete",
                [
                    "text": .string(" null "),
                    "usage": .object(["input": .number(7), "output": .number(2)]),
                ]
            ),
            .assistantCompleted(
                sessionID: "live-1",
                text: "",
                usage: UsageSummary(inputTokens: 7, outputTokens: 2)
            )
        )
    }

    func testToolProjectionDecodesOutcomeTodosDiffAndPositiveDuration() {
        XCTAssertEqual(
            project(
                "tool.generating",
                [
                    "tool_id": .string("tool-1"),
                    "name": .string(""),
                    "preview": .string("draft"),
                    "context": .string("ctx"),
                ]
            ),
            .toolStart(
                sessionID: "live-1",
                toolID: "tool-1",
                name: "tool",
                detail: "draft",
                context: "ctx",
                generating: true
            )
        )

        XCTAssertEqual(
            project(
                "tool.complete",
                [
                    "tool_id": .string("tool-1"),
                    "name": .string("terminal"),
                    "result_text": .string(#"{"output":"done","exit_code":0}"#),
                    "summary": .string("ran"),
                    "duration_s": .number(1.25),
                    "todos": .array([
                        .string("ignored"),
                        .object(["content": .string("ship"), "status": .string("")]),
                    ]),
                    "inline_diff": .string("\u{001B}[31m-old\u{001B}[0m"),
                ]
            ),
            .toolComplete(
                sessionID: "live-1",
                toolID: "tool-1",
                name: "terminal",
                result: "done",
                outcome: .succeeded,
                summary: "ran",
                durationSeconds: 1.25,
                todos: [TodoItem(content: "ship", status: "pending")],
                inlineDiff: "-old"
            )
        )
    }

    func testBlockingRequestsAreStrictAndMalformedPayloadsRemainVisible() {
        XCTAssertEqual(
            project(
                "clarify.request",
                [
                    "request_id": .string("request-1"),
                    "question": .string("Continue?"),
                    "choices": .array([.string("yes"), .string("no")]),
                ]
            ),
            .clarificationRequest(
                sessionID: "live-1",
                requestID: "request-1",
                question: "Continue?",
                choices: ["yes", "no"]
            )
        )

        XCTAssertEqual(
            project(
                "approval.request",
                [
                    "command": .string("git status"),
                    "description": .string(""),
                ]
            ),
            .approvalRequest(
                sessionID: "live-1",
                command: "git status",
                description: "",
                allowPermanent: true
            )
        )

        XCTAssertEqual(
            project("clarify.request", ["question": .string("Continue?")]),
            .blockingRequestInvalid(
                sessionID: "live-1",
                requestType: "clarify.request",
                message: "Malformed clarify.request: request_id was missing or not text"
            )
        )
        XCTAssertEqual(
            projector.project(
                GatewayEventFrame(
                    type: "sudo.request",
                    sessionID: "live-1",
                    payload: nil
                )
            ),
            .blockingRequestInvalid(
                sessionID: "live-1",
                requestType: "sudo.request",
                message: "Malformed sudo.request: request_id was missing or not text"
            )
        )
    }

    func testSecretMetadataRejectsWrongTypesInsteadOfEnablingInput() {
        XCTAssertEqual(
            project(
                "secret.request",
                [
                    "request_id": .string("secret-1"),
                    "env_var": .string("TOKEN"),
                    "prompt": .string("Token"),
                    "metadata": .object([
                        "skill_name": .string("deploy"),
                        "help": .string("Open settings"),
                        "required_for": .string("publish"),
                    ]),
                ]
            ),
            .secretRequest(
                sessionID: "live-1",
                requestID: "secret-1",
                envVar: "TOKEN",
                prompt: "Token",
                metadata: SecretRequestMetadata(
                    skillName: "deploy",
                    help: "Open settings",
                    requiredFor: "publish"
                )
            )
        )
        XCTAssertEqual(
            project(
                "secret.request",
                [
                    "request_id": .string("secret-1"),
                    "env_var": .string("TOKEN"),
                    "prompt": .string("Token"),
                    "metadata": .array([]),
                ]
            ),
            .blockingRequestInvalid(
                sessionID: "live-1",
                requestType: "secret.request",
                message: "Malformed secret.request: metadata was not an object"
            )
        )
    }

    func testStatusProjectionRecognizesGoalAndBothCompactionForms() {
        XCTAssertEqual(
            project(
                "status.update",
                [
                    "kind": .string("goal"),
                    "text": .string("↻ Continuing toward goal (2/9): run tests"),
                ]
            ),
            .goalUpdate(
                sessionID: "live-1",
                text: "↻ Continuing toward goal (2/9): run tests",
                update: GoalProgressUpdate(
                    phase: .active,
                    turnsUsed: 2,
                    maxTurns: 9,
                    reason: "run tests"
                )
            )
        )
        XCTAssertEqual(
            project(
                "status.update",
                ["text": .string("Pre-API compression: ~12,345 tokens")]
            ),
            .compactionStarted(sessionID: "live-1", estimatedTokens: 12_345)
        )
        XCTAssertEqual(
            project(
                "status.update",
                ["kind": .string("compacting"), "text": .string("working")]
            ),
            .compactionStarted(sessionID: "live-1", estimatedTokens: nil)
        )
    }

    func testStatusProjectionPreservesTerminalPausedAndGenericGoalUpdates() {
        XCTAssertEqual(
            project(
                "status.update",
                [
                    "kind": .string("goal"),
                    "text": .string("✓ Goal achieved: shipped"),
                ]
            ),
            .goalUpdate(
                sessionID: "live-1",
                text: "✓ Goal achieved: shipped",
                update: GoalProgressUpdate(
                    phase: .finished,
                    turnsUsed: nil,
                    maxTurns: nil,
                    reason: "shipped"
                )
            )
        )
        XCTAssertEqual(
            project(
                "status.update",
                [
                    "kind": .string("goal"),
                    "text": .string("⏳ Goal parked: waiting for operator"),
                ]
            ),
            .goalUpdate(
                sessionID: "live-1",
                text: "⏳ Goal parked: waiting for operator",
                update: GoalProgressUpdate(
                    phase: .waiting,
                    turnsUsed: nil,
                    maxTurns: nil,
                    reason: "waiting for operator"
                )
            )
        )
        XCTAssertEqual(
            project(
                "status.update",
                [
                    "kind": .string("goal"),
                    "text": .string("⏸ Goal paused (4/9 turns) — review needed"),
                ]
            ),
            .goalUpdate(
                sessionID: "live-1",
                text: "⏸ Goal paused (4/9 turns) — review needed",
                update: GoalProgressUpdate(
                    phase: .paused,
                    turnsUsed: 4,
                    maxTurns: 9,
                    reason: "review needed"
                )
            )
        )
        XCTAssertEqual(
            project("status.update", ["text": .string("Waiting for tools")]),
            .statusUpdate(sessionID: "live-1", text: "Waiting for tools")
        )
    }

    func testSessionInfoReviewAndErrorFallbackProjection() {
        XCTAssertEqual(
            project(
                "session.info",
                [
                    "model": .string("gpt-5"),
                    "provider": .string("openai"),
                    "reasoning_effort_session_scope": .bool(true),
                ]
            ),
            .sessionInfoUpdate(
                sessionID: "live-1",
                info: SessionInfo(
                    model: "gpt-5",
                    provider: "openai",
                    reasoningEffortSessionScopeSupported: true
                )
            )
        )
        XCTAssertEqual(
            project("review.summary", ["text": .string("reviewed")]),
            .statusUpdate(sessionID: "live-1", text: "reviewed")
        )
        XCTAssertEqual(
            project("error"),
            .error(sessionID: "live-1", message: "Gateway error")
        )
    }

    func testSubagentProjectionRequiresIdentityFieldsAndCleansTerminalData() {
        XCTAssertNil(
            project(
                "subagent.start",
                ["goal": .string("work"), "task_count": .number(1)]
            )
        )

        XCTAssertEqual(
            project(
                "subagent.complete",
                [
                    "goal": .string("ship"),
                    "task_count": .number(2),
                    "task_index": .number(1),
                    "subagent_id": .string("agent-1"),
                    "status": .string("complete"),
                    "toolsets": .array([
                        .string("\u{001B}[31mterminal\u{001B}[0m"),
                        .number(1),
                    ]),
                    "duration_seconds": .number(3.5),
                    "output_tail": .array([
                        .object([
                            "tool": .string("terminal"),
                            "status": .string("failed"),
                            "preview": .string("oops"),
                        ]),
                    ]),
                ]
            ),
            .subagentUpdate(
                sessionID: "live-1",
                kind: .completed,
                data: SubagentEventData(
                    goal: "ship",
                    taskCount: 2,
                    taskIndex: 1,
                    subagentID: "agent-1",
                    parentID: nil,
                    childSessionID: nil,
                    depth: nil,
                    model: nil,
                    toolCount: nil,
                    toolsets: ["terminal"],
                    text: nil,
                    toolName: nil,
                    toolPreview: nil,
                    terminalStatus: .completed,
                    rawTerminalStatus: "complete",
                    summary: nil,
                    durationSeconds: 3.5,
                    inputTokens: nil,
                    outputTokens: nil,
                    reasoningTokens: nil,
                    apiCalls: nil,
                    filesRead: [],
                    filesWritten: [],
                    outputTail: [
                        SubagentOutput(
                            tool: "terminal",
                            preview: "oops",
                            isError: true,
                            status: "failed"
                        ),
                    ]
                )
            )
        )
    }

    func testUnknownProjectorEventIsIgnored() {
        XCTAssertNil(project("future.event"))
    }

    private func project(
        _ type: String,
        _ payload: JSONValue.Object = [:]
    ) -> HermesStreamEvent? {
        projector.project(
            GatewayEventFrame(
                type: type,
                sessionID: "live-1",
                payload: payload
            )
        )
    }
}
