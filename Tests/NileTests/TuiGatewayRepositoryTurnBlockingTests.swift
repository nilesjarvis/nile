import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testPromptSteerAndInterruptMutationContracts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "prompt.submit": ["status": .string("queued")],
                "session.steer": ["status": .string("queued")],
                "session.interrupt": [:],
            ]
        )
        let repository = repository(rpc: rpc)
        let turns = repository.sessionCapabilities.turns

        let promptStatus = try await turns.submitPrompt(
            liveSessionID: "live-1",
            text: "hello"
        )
        let steered = try await turns.steer(
            liveSessionID: "live-1",
            text: "change"
        )
        XCTAssertEqual(promptStatus, .queued)
        XCTAssertTrue(steered)
        try await turns.interrupt(liveSessionID: "live-1")

        let requests = await rpc.requests
        XCTAssertTrue(requests[0].allowNullResult)
        XCTAssertFalse(requests[1].allowNullResult)
        XCTAssertTrue(requests[2].allowNullResult)
    }

    func testTalkCapabilityComposesPromptAndRuntimeStatusServices() async throws {
        let rpc = RecordingRPC(
            responses: [
                "session.active_list": [
                    "sessions": .array([
                        .object([
                            "id": .string("live-1"),
                            "status": .string("idle"),
                        ]),
                    ]),
                ],
                "prompt.submit": ["status": .string("streaming")],
            ]
        )
        let repository = repository(rpc: rpc)
        let talk = repository.sessionCapabilities.talk

        let status = try await talk.liveRuntimeStatus(
            liveSessionID: "live-1"
        )
        let prompt = try await talk.submitPrompt(
            liveSessionID: "live-1",
            text: "continue"
        )

        XCTAssertEqual(status, "idle")
        XCTAssertEqual(prompt, .streaming)
        let requests = await rpc.requests
        XCTAssertEqual(
            requests.map(\.method),
            ["session.active_list", "prompt.submit"]
        )
    }

    func testUnknownPromptStatusReportsThatMutationMayHaveSucceeded() async {
        let rpc = RecordingRPC(
            responses: ["prompt.submit": ["status": .string("future")]]
        )
        let repository = repository(rpc: rpc)
        let turns = repository.sessionCapabilities.turns

        await XCTAssertThrowsErrorAsync(
            try await turns.submitPrompt(
                liveSessionID: "live-1",
                text: "hello"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(hermes?.message, "prompt.submit returned an unknown status")
            XCTAssertEqual(hermes?.retryable, false)
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
        }
    }

    func testBlockingResponsesUseExactTypedWireContracts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "clarify.respond": ["status": .string("ok")],
                "sudo.respond": ["status": .string("ok")],
                "secret.respond": ["status": .string("ok")],
                "approval.respond": ["resolved": .number(1)],
            ]
        )
        let blockingPrompts = blockingPromptService(rpc: rpc)

        try await blockingPrompts.respondToClarification(
            requestID: "clarify-1",
            answer: "Staging"
        )
        try await blockingPrompts.respondToSudo(
            requestID: "sudo-1",
            password: "fixture-response"
        )
        try await blockingPrompts.respondToSecret(
            requestID: "secret-1",
            value: "fixture-response"
        )
        let approvalResolved = try await blockingPrompts.respondToApproval(
            liveSessionID: "live-1",
            choice: .session
        )
        XCTAssertTrue(approvalResolved)

        let requests = await rpc.requests
        XCTAssertEqual(
            requests,
            [
                RPCRequest(
                    method: "clarify.respond",
                    params: [
                        "request_id": .string("clarify-1"),
                        "answer": .string("Staging"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "sudo.respond",
                    params: [
                        "request_id": .string("sudo-1"),
                        "password": .string("fixture-response"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "secret.respond",
                    params: [
                        "request_id": .string("secret-1"),
                        "value": .string("fixture-response"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "approval.respond",
                    params: [
                        "session_id": .string("live-1"),
                        "choice": .string("session"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
            ]
        )
    }

    func testMalformedBlockingMutationResultsFailClosedAsUncertain() async {
        let blockingPrompts = blockingPromptService(
            rpc: RecordingRPC(
                responses: [
                    "clarify.respond": ["status": .string("future")],
                    "approval.respond": ["resolved": .number(2)],
                ]
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await blockingPrompts.respondToClarification(
                requestID: "clarify-1",
                answer: "Staging"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Malformed response to clarify.respond: status was not ok"
            )
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
        }
        await XCTAssertThrowsErrorAsync(
            try await blockingPrompts.respondToApproval(
                liveSessionID: "live-1",
                choice: .once
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Malformed response to approval.respond: resolved was not 0 or 1"
            )
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
        }
    }

}
