import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testModelOptionsAndSessionControlsUseExactTypedContracts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "model.options": [
                    "model": .string("claude-sonnet"),
                    "provider": .string("anthropic"),
                    "providers": .array([
                        .object([
                            "slug": .string("anthropic"),
                            "name": .string("Anthropic"),
                            "authenticated": .bool(true),
                            "is_current": .bool(true),
                            "models": .array([
                                .string("claude-sonnet"),
                                .string("claude-opus"),
                            ]),
                            "capabilities": .object([
                                "claude-sonnet": .object([
                                    "fast": .bool(true),
                                    "reasoning": .bool(true),
                                ]),
                            ]),
                            "pricing": .object([
                                "claude-sonnet": .object([
                                    "input": .string("$3"),
                                    "output": .string("$15"),
                                    "cache": .null,
                                    "free": .bool(false),
                                ]),
                            ]),
                            "free_tier": .bool(false),
                            "unavailable_models": .array([
                                .string("claude-opus"),
                            ]),
                        ]),
                    ]),
                ],
                "config.set": [
                    "key": .string("model"),
                    "value": .string("claude-sonnet"),
                    "warning": .string(""),
                    "confirm_required": .bool(false),
                    "confirm_message": .string(""),
                ],
            ]
        )
        let models = modelService(rpc: rpc)

        let options = try await models.modelOptions(
            liveSessionID: "live-1",
            refresh: true
        )
        let switched = try await models.setSessionModel(
            liveSessionID: "live-1",
            model: "claude-sonnet",
            provider: "anthropic",
            confirmExpensiveModel: false
        )

        XCTAssertEqual(options.model, "claude-sonnet")
        XCTAssertEqual(options.provider, "anthropic")
        XCTAssertEqual(options.providers[0].unavailableModels, ["claude-opus"])
        XCTAssertEqual(
            options.providers[0].capabilities["claude-sonnet"],
            ModelCapabilities(fast: true, reasoning: true)
        )
        XCTAssertEqual(
            switched,
            .applied(resolvedModel: "claude-sonnet", warning: nil)
        )
        let requests = await rpc.requests
        XCTAssertEqual(
            Array(requests.suffix(2)),
            [
                RPCRequest(
                    method: "model.options",
                    params: [
                        "session_id": .string("live-1"),
                        "refresh": .bool(true),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "config.set",
                    params: [
                        "session_id": .string("live-1"),
                        "key": .string("model"),
                        "value": .string(
                            "claude-sonnet --provider anthropic --session"
                        ),
                        "confirm_expensive_model": .bool(false),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
            ]
        )
    }

    func testReasoningUsesSessionScopeAndStrictAcknowledgement() async throws {
        let rpc = RecordingRPC(
            responses: [
                "config.set": [
                    "key": .string("reasoning"),
                    "value": .string("high"),
                    "scope": .string("session"),
                ],
            ]
        )
        let models = modelService(rpc: rpc)

        let effort = try await models.setReasoningEffort(
            liveSessionID: "live-1",
            effort: "HIGH"
        )

        XCTAssertEqual(effort, "high")
        let requests = await rpc.requests
        XCTAssertEqual(
            requests.last,
            RPCRequest(
                method: "config.set",
                params: [
                    "session_id": .string("live-1"),
                    "key": .string("reasoning"),
                    "value": .string("high"),
                    "scope": .string("session"),
                ],
                timeoutMilliseconds: 30_000,
                allowNullResult: false
            )
        )
    }

    func testLegacyModelSwitchAcknowledgementIsAcceptedAsApplied() async throws {
        let models = modelService(
            rpc: RecordingRPC(
                responses: [
                    "config.set": [
                        "key": .string("model"),
                        "value": .string("claude-sonnet"),
                        "warning": .string("catalog unavailable"),
                    ],
                ]
            )
        )

        let outcome = try await models.setSessionModel(
            liveSessionID: "live-1",
            model: "claude-sonnet",
            provider: "anthropic",
            confirmExpensiveModel: false
        )

        XCTAssertEqual(
            outcome,
            .applied(
                resolvedModel: "claude-sonnet",
                warning: "catalog unavailable"
            )
        )
    }

    func testMalformedModelMutationsAreUncertainAndUnsafeFlagsNeverSend() async {
        let malformed = modelService(
            rpc: RecordingRPC(
                responses: [
                    "config.set": [
                        "key": .string("model"),
                        "value": .string("claude"),
                        "warning": .string(""),
                        "confirm_required": .bool(false),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await malformed.setSessionModel(
                liveSessionID: "live-1",
                model: "claude",
                provider: "anthropic",
                confirmExpensiveModel: false
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
            XCTAssertTrue(
                hermes?.message.contains("Malformed response to config.set model")
                    == true
            )
        }

        let scopedWithoutConfirmation = modelService(
            rpc: RecordingRPC(
                responses: [
                    "config.set": [
                        "key": .string("model"),
                        "value": .string("claude"),
                        "warning": .string(""),
                        "scope": .string("session"),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await scopedWithoutConfirmation.setSessionModel(
                liveSessionID: "live-1",
                model: "claude",
                provider: "anthropic",
                confirmExpensiveModel: false
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
            XCTAssertTrue(
                hermes?.message.contains(
                    "confirmation metadata was missing from a scoped response"
                ) == true
            )
        }

        let rpc = RecordingRPC(responses: [:])
        let unsafe = modelService(rpc: rpc)
        await XCTAssertThrowsErrorAsync(
            try await unsafe.setSessionModel(
                liveSessionID: "live-1",
                model: "claude --global",
                provider: "anthropic",
                confirmExpensiveModel: false
            )
        )
        let requests = await rpc.requests
        XCTAssertTrue(requests.isEmpty)
    }

}
