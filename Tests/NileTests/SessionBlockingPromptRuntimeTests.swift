import XCTest
@testable import Nile

@MainActor
final class SessionBlockingPromptRuntimeTests: XCTestCase {
    func testDispatchesEveryTypedResponseThroughNarrowCapability() async {
        let repository = BlockingPromptRepositoryStub()
        let runtime = SessionBlockingPromptRuntime(repository: repository)
        let probe = BlockingPromptRuntimeProbe()

        _ = runtime.handleEvent(
            .clarificationRequest(
                sessionID: "live",
                requestID: "clarify",
                question: "Which environment?",
                choices: ["Staging"]
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        XCTAssertTrue(
            respond(
                runtime,
                kind: .clarification,
                value: "Staging",
                probe: probe
            )
        )
        await waitUntil { await repository.callCount == 1 }

        _ = runtime.handleEvent(
            .approvalRequest(
                sessionID: "live",
                command: "./deploy",
                description: "Deploy",
                allowPermanent: true
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        XCTAssertTrue(
            respond(
                runtime,
                kind: .approval,
                value: ApprovalChoice.always.rawValue,
                probe: probe
            )
        )
        await waitUntil { await repository.callCount == 2 }

        _ = runtime.handleEvent(
            .sudoRequest(sessionID: "live", requestID: "sudo"),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        XCTAssertTrue(
            respond(
                runtime,
                kind: .sudo,
                value: "sudo-password",
                probe: probe
            )
        )
        await waitUntil { await repository.callCount == 3 }

        let secret = "secret-value-never-retain"
        _ = runtime.handleEvent(
            .secretRequest(
                sessionID: "live",
                requestID: "secret",
                envVar: "DEPLOY_TOKEN",
                prompt: "Enter token",
                metadata: nil
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )
        XCTAssertTrue(
            respond(
                runtime,
                kind: .secret,
                value: secret,
                probe: probe
            )
        )
        await waitUntil { await repository.callCount == 4 }
        await waitUntil { probe.changeCount >= 8 }

        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            [
                .clarification(requestID: "clarify", answer: "Staging"),
                .approval(liveSessionID: "live", choice: .always),
                .sudo(requestID: "sudo", password: "sudo-password"),
                .secret(requestID: "secret", value: secret),
            ]
        )
        XCTAssertTrue(probe.errors.isEmpty)
        XCTAssertFalse(
            String(describing: projection(runtime)).contains(secret),
            "Sensitive responses must not enter runtime presentation state"
        )
    }

    func testDefiniteFailureRestoresRetryAndReportsOnlyCurrentOwner() async {
        let repository = BlockingPromptRepositoryStub(
            failure: HermesError("definitely rejected", retryable: false)
        )
        let runtime = SessionBlockingPromptRuntime(repository: repository)
        let probe = BlockingPromptRuntimeProbe()
        _ = runtime.handleEvent(
            .clarificationRequest(
                sessionID: "live",
                requestID: "retry",
                question: "Retry?",
                choices: nil
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "stored"
        )

        XCTAssertTrue(
            respond(
                runtime,
                kind: .clarification,
                value: "answer",
                probe: probe
            )
        )
        await waitUntil { probe.changeCount >= 2 }

        XCTAssertEqual(probe.errors, ["definitely rejected"])
        let prompt = prompts(runtime).first
        XCTAssertEqual(prompt?.status, .pending)
        XCTAssertTrue(prompt?.actionable == true)
    }

    func testStaleOwnerCannotBeginResponse() async {
        let repository = BlockingPromptRepositoryStub(
            failure: HermesError("old owner failed", retryable: false)
        )
        let runtime = SessionBlockingPromptRuntime(repository: repository)
        let probe = BlockingPromptRuntimeProbe()
        _ = runtime.handleEvent(
            .clarificationRequest(
                sessionID: "old-live",
                requestID: "old",
                question: "Old?",
                choices: nil
            ),
            gatewayID: "gateway",
            fallbackStoredSessionID: "old-stored"
        )

        guard let promptID = prompts(
            runtime,
            liveSessionID: "old-live",
            storedSessionID: "old-stored"
        ).first?.id else {
            return XCTFail("Expected prompt")
        }
        XCTAssertTrue(
            runtime.respond(
                promptID: promptID,
                response: "answer",
                isCurrentTarget: { _ in false },
                onChanged: { probe.changeCount += 1 },
                onError: { _, error in
                    probe.errors.append(error.localizedDescription)
                }
            ) == false,
            "A stale owner must not begin a response"
        )
        let callCount = await repository.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(probe.errors.isEmpty)
        XCTAssertEqual(
            prompts(
                runtime,
                liveSessionID: "old-live",
                storedSessionID: "old-stored"
            ).first?.status,
            .pending
        )
    }

    func testResetCancelsResponseWithoutPublishingIntoReplacementGateway()
        async
    {
        let repository = BlockingPromptRepositoryStub(blocks: true)
        let runtime = SessionBlockingPromptRuntime(repository: repository)
        let probe = BlockingPromptRuntimeProbe()
        _ = runtime.handleEvent(
            .secretRequest(
                sessionID: "old-live",
                requestID: "old-secret",
                envVar: "TOKEN",
                prompt: "Old secret",
                metadata: nil
            ),
            gatewayID: "old-gateway",
            fallbackStoredSessionID: "old-stored"
        )
        guard let oldID = prompts(
            runtime,
            gatewayID: "old-gateway",
            liveSessionID: "old-live",
            storedSessionID: "old-stored"
        ).first?.id else {
            return XCTFail("Expected old prompt")
        }
        XCTAssertTrue(
            runtime.respond(
                promptID: oldID,
                response: "ephemeral-secret",
                isCurrentTarget: { _ in true },
                onChanged: { probe.changeCount += 1 },
                onError: { _, error in
                    probe.errors.append(error.localizedDescription)
                }
            )
        )
        await waitUntil { await repository.callCount == 1 }
        XCTAssertEqual(probe.changeCount, 1)

        runtime.reset()
        _ = runtime.handleEvent(
            .clarificationRequest(
                sessionID: "new-live",
                requestID: "new",
                question: "New?",
                choices: nil
            ),
            gatewayID: "new-gateway",
            fallbackStoredSessionID: "new-stored"
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(probe.changeCount, 1)
        XCTAssertTrue(probe.errors.isEmpty)
        let replacement = prompts(
            runtime,
            gatewayID: "new-gateway",
            liveSessionID: "new-live",
            storedSessionID: "new-stored"
        ).first
        XCTAssertEqual(replacement?.status, .pending)
        XCTAssertTrue(replacement?.actionable == true)
    }

    private func respond(
        _ runtime: SessionBlockingPromptRuntime,
        kind: BlockingPromptKind,
        value: String,
        probe: BlockingPromptRuntimeProbe
    ) -> Bool {
        guard let promptID = prompts(runtime).first(where: {
            $0.kind == kind && $0.status == .pending
        })?.id else {
            return false
        }
        return runtime.respond(
            promptID: promptID,
            response: value,
            isCurrentTarget: { target in
                target == BlockingPromptResponseTarget(
                    gatewayID: "gateway",
                    liveSessionID: "live",
                    storedSessionID: "stored"
                )
            },
            onChanged: { probe.changeCount += 1 },
            onError: { _, error in
                probe.errors.append(error.localizedDescription)
            }
        )
    }

    private func prompts(
        _ runtime: SessionBlockingPromptRuntime,
        gatewayID: String = "gateway",
        liveSessionID: String = "live",
        storedSessionID: String = "stored"
    ) -> [TranscriptBlockingPrompt] {
        projection(
            runtime,
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            storedSessionID: storedSessionID
        ).transcript.compactMap { entry in
            guard case let .blockingPrompt(prompt) = entry else {
                return nil
            }
            return prompt
        }
    }

    private func projection(
        _ runtime: SessionBlockingPromptRuntime,
        gatewayID: String = "gateway",
        liveSessionID: String = "live",
        storedSessionID: String = "stored"
    ) -> (
        transcript: [TranscriptEntry],
        sessionsNeedingInput: Set<String>
    ) {
        runtime.project(
            gatewayID: gatewayID,
            liveSessionID: liveSessionID,
            storedSessionID: storedSessionID,
            transcript: []
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class BlockingPromptRuntimeProbe {
    var changeCount = 0
    var errors: [String] = []
}

private actor BlockingPromptRepositoryStub: HermesBlockingPromptServing {
    enum Call: Equatable {
        case clarification(requestID: String, answer: String)
        case approval(liveSessionID: String, choice: ApprovalChoice)
        case sudo(requestID: String, password: String)
        case secret(requestID: String, value: String)
    }

    private(set) var calls: [Call] = []
    private let failure: HermesError?
    private let blocks: Bool

    init(failure: HermesError? = nil, blocks: Bool = false) {
        self.failure = failure
        self.blocks = blocks
    }

    var callCount: Int { calls.count }

    func respondToClarification(
        requestID: String,
        answer: String
    ) async throws {
        try await record(.clarification(requestID: requestID, answer: answer))
    }

    func respondToSudo(
        requestID: String,
        password: String
    ) async throws {
        try await record(.sudo(requestID: requestID, password: password))
    }

    func respondToSecret(
        requestID: String,
        value: String
    ) async throws {
        try await record(.secret(requestID: requestID, value: value))
    }

    func respondToApproval(
        liveSessionID: String,
        choice: ApprovalChoice
    ) async throws -> Bool {
        try await record(
            .approval(liveSessionID: liveSessionID, choice: choice)
        )
        return true
    }

    private func record(_ call: Call) async throws {
        calls.append(call)
        if blocks {
            try await Task.sleep(for: .seconds(30))
        }
        if let failure {
            throw failure
        }
    }
}
