import XCTest
@testable import Nile

final class GatewaySessionCodecTests: XCTestCase {
    private let codec = GatewaySessionCodec()
    private let storedCodec = GatewayStoredSessionCodec()

    func testSessionListUsesAndroidTimestampFallbacksAndStrictIDs() throws {
        let sessions = try codec.decodeSessionList([
            "sessions": .array([
                .object([
                    "id": .string("stored-1"),
                    "title": .string("First"),
                    "preview": .string("hello"),
                    "source": .string("niles"),
                    "message_count": .number(3),
                    "started_at": .number(1_700_000_000_000),
                    "updated_at": .number(1_700_000_100),
                ]),
                .object([
                    "id": .string("stored-2"),
                    "message_count": .string("7"),
                    "last_activity_at": .number(1_700_000_200),
                ]),
            ]),
        ])

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].id, "stored-1")
        XCTAssertEqual(sessions[0].startedAt, 1_700_000_000)
        XCTAssertEqual(sessions[0].lastMessageAt, 1_700_000_100)
        XCTAssertEqual(sessions[1].messageCount, 7)
        XCTAssertEqual(sessions[1].lastMessageAt, 1_700_000_200)

        XCTAssertThrowsError(
            try codec.decodeSessionList([
                "sessions": .array([.object(["id": .string(" ")])]),
            ])
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to session.list: id was missing or blank"
            )
        }
    }

    func testRequiredArraysRejectMissingArraysAndNonObjectRows() {
        XCTAssertThrowsError(try codec.decodeSessionList([:])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to session.list: sessions was missing or not an array"
            )
        }
        XCTAssertThrowsError(
            try codec.decodeSessionList(["sessions": .array([.string("bad")])])
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to session.list: sessions[0] was not an object"
            )
        }
    }

    func testLiveSessionFiltersPrivateGoalRowsAndProjectsModelMarker() throws {
        let marker = Self.modelMarker("openai/gpt-5")
        let session = codec.decodeLiveSession(
            [
                "session_id": .string("live-1"),
                "stored_session_id": .null,
                "info": .object([
                    "model": .string("gpt-5"),
                    "provider": .string("openai"),
                    "reasoning_effort": .string("high"),
                    "reasoning_effort_session_scope": .bool(true),
                    "lazy": .bool(true),
                ]),
                "messages": .array([
                    .object(["role": .string("assistant"), "text": .string("hello")]),
                    .object(["role": .string("assistant"), "text": .string(" ")]),
                    .object([
                        "role": .string("user"),
                        "text": .string("[Continuing toward your standing goal]\nGoal: ship"),
                    ]),
                    .object(["role": .string("user"), "text": .string(marker)]),
                    .object([
                        "role": .string("tool"),
                        "name": .string("terminal"),
                        "context": .string("swift test"),
                    ]),
                ]),
                "running": .bool(true),
                "status": .string("working"),
                "inflight": .object([
                    "user": .string("[Continuing toward your standing goal]\nGoal: ship"),
                    "assistant": .string("still working"),
                ]),
            ],
            fallbackStoredID: "stored-fallback"
        )

        XCTAssertEqual(session.liveID, "live-1")
        XCTAssertEqual(session.storedID, "stored-fallback")
        XCTAssertEqual(
            session.info,
            SessionInfo(
                model: "gpt-5",
                provider: "openai",
                reasoningEffort: "high",
                reasoningEffortSessionScopeSupported: true,
                isLazy: true
            )
        )
        XCTAssertEqual(
            session.messages,
            [
                HermesMessage(role: "assistant", text: "hello"),
                HermesMessage(role: "system", text: "model changed to openai/gpt-5"),
                HermesMessage(
                    role: "tool",
                    text: "swift test",
                    toolName: "terminal",
                    toolContext: "swift test"
                ),
            ]
        )
        XCTAssertTrue(session.turnInFlight)
        XCTAssertEqual(session.inflight, InflightTurn(user: "", assistant: "still working"))
        XCTAssertNoThrow(try codec.requireLiveID(session, method: "session.resume"))
    }

    func testLiveSessionRequiresNonblankRuntimeID() {
        let session = codec.decodeLiveSession([:], fallbackStoredID: nil)
        XCTAssertThrowsError(try codec.requireLiveID(session, method: "session.create")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Malformed response to session.create: session_id was missing or blank"
            )
        }
    }

    func testStoredHistoryFlattensContentAndPairsToolCallsWithResults() throws {
        let messages = try storedCodec.decodeMessages([
            "messages": .array([
                .object([
                    "role": .string("assistant"),
                    "content": .null,
                    "tool_calls": .array([
                        .object([
                            "id": .string("call-1"),
                            "function": .object([
                                "name": .string("terminal"),
                                "arguments": .string(#"{"command":"ls -la"}"#),
                            ]),
                        ]),
                    ]),
                ]),
                .object([
                    "role": .string("tool"),
                    "tool_call_id": .string("call-1"),
                    "content": .string(
                        #"{"output":"\u001B[31mfile.txt\u001B[0m","exit_code":0}"#
                    ),
                ]),
                .object([
                    "role": .string("user"),
                    "content": .array([
                        .object(["type": .string("input_text"), "text": .string("Look")]),
                        .object(["type": .string("input_image")]),
                        .object(["type": .string("input_audio")]),
                    ]),
                ]),
                .object(["role": .string("assistant"), "content": .string(" null ")]),
                .object([
                    "role": .string("user"),
                    "content": .string("[Continuing toward your standing goal]\nGoal: ship"),
                ]),
                .object([
                    "role": .string("user"),
                    "content": .string(Self.modelMarker("anthropic/claude")),
                ]),
                .object([
                    "role": .string("tool"),
                    "content": .string("plain result"),
                ]),
            ]),
        ])

        XCTAssertEqual(
            messages,
            [
                HermesMessage(
                    role: "tool",
                    text: "file.txt",
                    toolName: "terminal",
                    toolContext: "ls -la",
                    toolOutcome: .succeeded
                ),
                HermesMessage(role: "user", text: "Look\n[screenshot]\n[audio]"),
                HermesMessage(
                    role: "system",
                    text: "model changed to anthropic/claude"
                ),
                HermesMessage(role: "tool", text: "plain result", toolName: "tool"),
            ]
        )
    }

    func testStoredToolResultDetectsInterruptAndClarificationEnvelope() throws {
        let messages = try storedCodec.decodeMessages([
            "messages": .array([
                .object([
                    "role": .string("tool"),
                    "tool_name": .string("terminal"),
                    "content": .string(
                        #"{"output":"partial\n[Command interrupted]","exit_code":130}"#
                    ),
                ]),
                .object([
                    "role": .string("tool"),
                    "tool_name": .string("clarify"),
                    "content": .string(#"{"user_response":"yes"}"#),
                ]),
            ]),
        ])

        XCTAssertEqual(messages[0].text, "partial")
        XCTAssertEqual(messages[0].toolOutcome, .interrupted)
        XCTAssertEqual(messages[1].text, "Decision answered")
        XCTAssertEqual(messages[1].toolOutcome, .succeeded)
    }

    func testStoredAndRuntimeStatusDecodingHaveDifferentStrictness() throws {
        let result: JSONValue.Object = [
            "sessions": .array([
                .object([
                    "id": .string("live-1"),
                    "session_key": .string("stored-1"),
                    "status": .string("working"),
                ]),
                .object([
                    "id": .string("live-2"),
                    "session_key": .string(""),
                    "status": .string("idle"),
                ]),
            ]),
        ]

        XCTAssertEqual(
            try codec.decodeStoredStatuses(result),
            ["stored-1": "working"]
        )
        XCTAssertEqual(
            try codec.decodeRuntimeStatuses(result),
            ["live-1": "working", "live-2": "idle"]
        )

        XCTAssertThrowsError(
            try codec.decodeRuntimeStatuses([
                "sessions": .array([
                    .object(["id": .string(" "), "status": .string("idle")]),
                ]),
            ])
        )
    }

    private static func modelMarker(_ identity: String) -> String {
        "[System: The active model for this chat has changed to \(identity). From this point forward, use this runtime metadata when answering questions about what model/provider is active.]"
    }
}
