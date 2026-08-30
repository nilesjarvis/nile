import XCTest
@testable import Nile

@MainActor
final class SessionCommandRuntimeTests: XCTestCase {
    func testRuntimeOwnsCatalogCompletionAndAliasValidation() async {
        let repository = CommandRuntimeRepository()
        let runtime = SessionCommandRuntime(
            repository: repository,
            completionDebounce: .zero
        )

        runtime.applyCatalog(await runtime.fetchCatalog())

        XCTAssertEqual(
            runtime.catalog?.categories.flatMap(\.commands).map(\.name),
            ["/subgoal"]
        )
        XCTAssertEqual(
            runtime.decision(for: "/undo").surface,
            .blocked
        )

        runtime.refreshCompletions(
            query: "/sub",
            owner: SessionCommandRuntime.CompletionOwner(
                gatewayGeneration: 3,
                gatewayID: "gateway-1"
            )
        )
        await eventually {
            runtime.completions.map(\.display) == ["/subgoal"]
        }
        XCTAssertEqual(runtime.replaceFrom, 1)

        let recorder = CommandOutcomeRecorder()
        let owner = SessionCommandRuntime.ExecutionOwner(
            gatewayID: "gateway-1",
            storedSessionID: "stored-1"
        )
        XCTAssertTrue(
            runtime.startExecution(
                owner: owner,
                liveSessionID: "live-1",
                input: "/subgoal ship",
                prepare: { true },
                onOutcome: { recorder.outcome = $0 }
            )
        )
        await eventually { recorder.outcome != nil }

        XCTAssertEqual(
            recorder.outcome,
            .failed(
                message:
                    "The alias points to /learn, which isn't available in Nile. It was not run.",
                uncertain: false
            )
        )
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            [
                "commands.catalog",
                "complete.slash:/sub",
                "slashExec:live-1:/subgoal ship",
            ]
        )
        await eventually { !runtime.isExecuting(owner: owner) }
    }

    func testGatewayResetCancelsActiveExecutionAsUncertain() async {
        let repository = BlockingCommandRuntimeRepository()
        let runtime = SessionCommandRuntime(repository: repository)
        let recorder = CommandOutcomeRecorder()
        let owner = SessionCommandRuntime.ExecutionOwner(
            gatewayID: "gateway-1",
            storedSessionID: "stored-1"
        )
        var started = repository.executionStarted.makeAsyncIterator()

        XCTAssertTrue(
            runtime.startExecution(
                owner: owner,
                liveSessionID: "live-1",
                input: "/subgoal ship",
                prepare: { true },
                onOutcome: { recorder.outcome = $0 }
            )
        )
        _ = await started.next()

        runtime.resetGateway()

        await eventually { recorder.outcome == .cancelled }
        XCTAssertFalse(runtime.isExecuting(owner: owner))
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            try? await clock.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class CommandOutcomeRecorder {
    var outcome: SessionCommandRuntime.ExecutionOutcome?
}

private actor CommandRuntimeRepository: HermesCommandServing {
    private(set) var calls: [String] = []

    func commandsCatalog() async throws -> CommandCatalog {
        calls.append("commands.catalog")
        return CommandCatalog(
            categories: [
                CommandCategory(
                    name: "Core",
                    commands: [
                        CommandInfo(
                            name: "/subgoal",
                            description: "Manage criteria"
                        ),
                        CommandInfo(name: "/undo", description: "Unsafe"),
                    ]
                ),
            ],
            skillCommands: []
        )
    }

    func completeSlash(text: String) async throws -> SlashCompletions {
        calls.append("complete.slash:\(text)")
        return SlashCompletions(
            items: [
                SlashCompletion(
                    text: "subgoal",
                    display: "/subgoal",
                    meta: "Manage criteria"
                ),
                SlashCompletion(
                    text: "undo",
                    display: "/undo",
                    meta: "Unsafe"
                ),
            ],
            replaceFrom: 1
        )
    }

    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution {
        calls.append("\(route.rawValue):\(liveSessionID):\(command)")
        if command.hasPrefix("/subgoal") {
            return .alias(target: "learn")
        }
        return .output("criterion added")
    }
}

private actor BlockingCommandRuntimeRepository: HermesCommandServing {
    nonisolated let executionStarted: AsyncStream<Void>
    private let executionStartedContinuation: AsyncStream<Void>.Continuation

    init() {
        let pair = AsyncStream<Void>.makeStream()
        executionStarted = pair.stream
        executionStartedContinuation = pair.continuation
    }

    func commandsCatalog() async throws -> CommandCatalog {
        throw HermesError("Not used", retryable: false)
    }

    func completeSlash(text: String) async throws -> SlashCompletions {
        throw HermesError("Not used", retryable: false)
    }

    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution {
        executionStartedContinuation.yield()
        try await Task.sleep(for: .seconds(60))
        return .output("must not complete")
    }
}
