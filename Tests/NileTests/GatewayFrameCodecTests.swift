import XCTest
@testable import Nile

final class GatewayFrameCodecTests: XCTestCase {
    private let codec = GatewayFrameCodec()

    func testRequestEncodingPreservesExactJSONRPCFieldsAndNewlineFraming() throws {
        let encoded = try codec.encodeRequest(
            id: 7,
            method: "session.resume",
            params: ["stored_session_id": .string("session-1")]
        )

        XCTAssertTrue(encoded.hasSuffix("\n"))
        XCTAssertEqual(encoded.filter { $0 == "\n" }.count, 1)
        let object = try parseObject(encoded)
        XCTAssertEqual(object.count, 4)
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual((object["id"] as? NSNumber)?.int64Value, 7)
        XCTAssertEqual(object["method"] as? String, "session.resume")
        XCTAssertEqual(
            (object["params"] as? [String: Any])?["stored_session_id"] as? String,
            "session-1"
        )
    }

    func testTopLevelDispatchRejectsInvalidShapesAndIgnoresFutureNotifications() throws {
        assertInboundInvalid("not json", "message was not valid JSON")
        assertInboundInvalid("{}", "message was not a response or notification")
        assertInboundInvalid(
            try json([
                "jsonrpc": "1.0",
                "method": "future.notice",
            ]),
            "notification did not declare JSON-RPC 2.0"
        )

        XCTAssertEqual(
            codec.decodeInbound(
                try json([
                    "jsonrpc": "2.0",
                    "method": "future.notice",
                    "params": ["future shape"],
                ])
            ),
            .ignored
        )

        let response = codec.decodeInbound(
            try json([
                "jsonrpc": "2.0",
                "id": 9,
                "method": "future.request",
            ])
        )
        guard case let .response(id, _) = response else {
            return XCTFail("Expected response precedence")
        }
        XCTAssertEqual(id, 9)
        assertDecodedInvalid(
            codec.decodeResponse(response, allowNullResult: false),
            "response also contained a method"
        )
    }

    func testReadyEventRequiresStrictEnvelopeButNoSessionID() throws {
        XCTAssertEqual(
            codec.decodeInbound(try eventEnvelope(type: "gateway.ready")),
            .ready
        )
        assertInboundInvalid(
            try eventEnvelope(type: "gateway.ready", jsonrpc: "1.0"),
            "event did not declare JSON-RPC 2.0"
        )
        assertInboundInvalid(
            try eventEnvelope(type: "gateway.ready", extra: ["id": 1]),
            "event contained response fields"
        )
        assertInboundInvalid(
            try json(["jsonrpc": "2.0", "method": "event"]),
            "event params were missing or not an object"
        )
        assertInboundInvalid(
            try eventEnvelope(type: " "),
            "event type was missing or blank"
        )
        assertInboundInvalid(
            try eventEnvelope(type: "gateway.ready", payload: []),
            "event payload was not an object"
        )
    }

    func testKnownSessionEventKeepsTypeSessionAndObjectPayload() throws {
        let decoded = codec.decodeInbound(
            try eventEnvelope(
                type: "message.delta",
                sessionID: "live-1",
                payload: ["text": "hello"]
            )
        )
        guard case let .event(frame) = decoded else {
            return XCTFail("Expected event")
        }
        XCTAssertEqual(frame.type, "message.delta")
        XCTAssertEqual(frame.sessionID, "live-1")
        XCTAssertEqual(frame.payload?["text"], .string("hello"))

        let interim = codec.decodeInbound(
            try eventEnvelope(
                type: "message.interim",
                sessionID: "live-1",
                payload: ["text": "checking"]
            )
        )
        guard case let .event(interimFrame) = interim else {
            return XCTFail("Expected interim event")
        }
        XCTAssertEqual(interimFrame.type, "message.interim")
        XCTAssertEqual(interimFrame.payload?["text"], .string("checking"))

        assertInboundInvalid(
            try eventEnvelope(
                type: "message.delta",
                sessionID: "",
                payload: [:]
            ),
            "message.delta event had no session id"
        )
        assertInboundInvalid(
            try eventEnvelope(
                type: "message.delta",
                sessionID: "live-1",
                payload: "bad"
            ),
            "event payload was not an object"
        )
    }

    func testMalformedBlockingPayloadFailsClosedWithoutInvalidatingEnvelope() throws {
        for type in ["clarify.request", "approval.request", "sudo.request", "secret.request"] {
            let decoded = codec.decodeInbound(
                try eventEnvelope(
                    type: type,
                    sessionID: "live-1",
                    payload: ["bad"]
                )
            )
            guard case let .event(frame) = decoded else {
                return XCTFail("Expected blocking event for \(type)")
            }
            XCTAssertNil(frame.payload)
        }
    }

    func testUnknownEventTypeIsIgnoredBeforePayloadAndSessionValidation() throws {
        XCTAssertEqual(
            codec.decodeInbound(
                try eventEnvelope(type: "future.global", payload: ["future payload"])
            ),
            .ignored
        )
    }

    func testResponseIDMustBePositiveIntegralNumber() throws {
        for id: Any in [1, 7, 3.0] {
            let decoded = codec.decodeInbound(
                try json([
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [String: Any](),
                ])
            )
            guard case let .response(value, _) = decoded else {
                return XCTFail("Expected response for \(id)")
            }
            XCTAssertEqual(value, Int64((id as! NSNumber).doubleValue))
        }

        for id: Any in [0, -1, 1.5, "1", NSNull()] {
            assertInboundInvalid(
                try json([
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [String: Any](),
                ]),
                "response id was not a positive integer"
            )
        }
    }

    func testResponseResultRequiresObjectUnlessNullExplicitlyAllowed() throws {
        let objectResponse = try responseEnvelope(result: ["accepted": true])
        XCTAssertEqual(
            codec.decodeResponse(objectResponse, allowNullResult: false),
            .result(["accepted": .bool(true)])
        )

        let nullResponse = try responseEnvelope(result: NSNull())
        assertDecodedInvalid(
            codec.decodeResponse(nullResponse, allowNullResult: false),
            "result was not an object"
        )
        XCTAssertEqual(
            codec.decodeResponse(nullResponse, allowNullResult: true),
            .result([:])
        )

        let scalarResponse = try responseEnvelope(result: "scalar")
        assertDecodedInvalid(
            codec.decodeResponse(scalarResponse, allowNullResult: false),
            "result was not an object"
        )
    }

    func testResponseRequiresVersionAndExactlyOneResultOrError() throws {
        let wrongVersion = codec.decodeInbound(
            try json([
                "jsonrpc": "1.0",
                "id": 1,
                "result": [String: Any](),
            ])
        )
        assertDecodedInvalid(
            codec.decodeResponse(wrongVersion, allowNullResult: false),
            "jsonrpc was not 2.0"
        )

        let neither = codec.decodeInbound(
            try json(["jsonrpc": "2.0", "id": 1])
        )
        assertDecodedInvalid(
            codec.decodeResponse(neither, allowNullResult: false),
            "exactly one of result or error is required"
        )

        let both = codec.decodeInbound(
            try json([
                "jsonrpc": "2.0",
                "id": 1,
                "result": [String: Any](),
                "error": ["code": 1, "message": "bad"],
            ])
        )
        assertDecodedInvalid(
            codec.decodeResponse(both, allowNullResult: false),
            "exactly one of result or error is required"
        )
    }

    func testResponseErrorRequiresIntegralIntCodeAndNonblankMessage() throws {
        let valid = try responseEnvelope(
            error: ["code": -32_000, "message": "Rejected"]
        )
        XCTAssertEqual(
            codec.decodeResponse(valid, allowNullResult: false),
            .error(code: -32_000, message: "Rejected")
        )

        let badShape = try responseEnvelope(error: "bad")
        assertDecodedInvalid(
            codec.decodeResponse(badShape, allowNullResult: false),
            "error was not an object"
        )

        for code: Any in [1.5, Int64(Int32.max) + 1, "1"] {
            let response = try responseEnvelope(
                error: ["code": code, "message": "bad"]
            )
            assertDecodedInvalid(
                codec.decodeResponse(response, allowNullResult: false),
                "error code was not an integer"
            )
        }

        for message in ["", "   "] {
            let response = try responseEnvelope(
                error: ["code": 1, "message": message]
            )
            assertDecodedInvalid(
                codec.decodeResponse(response, allowNullResult: false),
                "error message was missing or blank"
            )
        }
    }

    private func eventEnvelope(
        type: String,
        sessionID: String? = nil,
        payload: Any? = nil,
        jsonrpc: String = "2.0",
        extra: [String: Any] = [:]
    ) throws -> String {
        var params: [String: Any] = ["type": type]
        if let sessionID {
            params["session_id"] = sessionID
        }
        if let payload {
            params["payload"] = payload
        }
        var envelope: [String: Any] = [
            "jsonrpc": jsonrpc,
            "method": "event",
            "params": params,
        ]
        for (key, value) in extra {
            envelope[key] = value
        }
        return try json(envelope)
    }

    private func responseEnvelope(
        result: Any? = nil,
        error: Any? = nil
    ) throws -> GatewayInboundFrame {
        var envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
        ]
        if let result {
            envelope["result"] = result
        }
        if let error {
            envelope["error"] = error
        }
        return codec.decodeInbound(try json(envelope))
    }

    private func assertInboundInvalid(
        _ json: String,
        _ reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            codec.decodeInbound(json),
            .invalid(reason: reason),
            file: file,
            line: line
        )
    }

    private func assertDecodedInvalid(
        _ response: GatewayDecodedResponse,
        _ reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            response,
            .invalid(reason: reason),
            file: file,
            line: line
        )
    }

    private func parseObject(_ value: String) throws -> [String: Any] {
        let data = try XCTUnwrap(value.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func json(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
