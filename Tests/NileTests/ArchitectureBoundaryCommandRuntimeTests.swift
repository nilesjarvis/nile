import XCTest

extension ArchitectureBoundaryTests {
    func testSessionCommandRuntimeOwnsCapabilityAndAsyncLifecycle() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: directory, named: $0) }
        let model = try appSource("SessionListModel.swift")
        let runtime = try appSource("SessionCommandRuntime.swift")
        let execution = try appSource("SessionCommandExecutionLifecycle.swift")

        XCTAssertTrue(try sessionGatewaySource().contains("runtimes.commandRuntime"))
        XCTAssertTrue(try sessionNavigationSource().contains("runtimes.commandRuntime"))
        for marker in ["slashCompletionTask", "commandExtensionNames",
                       "executeValidatedCommand", "aliasTargetWithArguments"] {
            XCTAssertFalse(model.contains(marker))
        }
        for marker in ["final class SessionCommandRuntime", "@Observable",
                       "private let repository: (any HermesCommandServing)?",
                       "func refreshCompletions", "completionTask",
                       "func startExecution", "executionLifecycle.start("] {
            XCTAssertTrue(runtime.contains(marker))
        }
        for marker in ["final class SessionCommandExecutionLifecycle",
                       "private var executionTasks", "private var activeExecutionIDs",
                       "func cancelAll()", "private func finishExecution(",
                       "private static func executeValidatedCommand(",
                       "private static func aliasTargetWithArguments(",
                       "requestMayHaveSucceeded", "CommandExecutionFailure"] {
            XCTAssertTrue(execution.contains(marker))
            XCTAssertFalse(runtime.contains(marker))
        }
        for forbidden in ["@Observable", "var catalog", "completionTask",
                          "private let repository", "HermesStreamEvent"] {
            XCTAssertFalse(execution.contains(forbidden))
        }
        XCTAssertFalse(runtime.contains("HermesStreamEvent"))
        XCTAssertLessThan(model.components(separatedBy: .newlines).count, 350)
        let lines = [runtime, execution].map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(lines[0], 200)
        XCTAssertLessThan(lines[1], 240)
        XCTAssertLessThan(lines.reduce(0, +), 420)
    }
}
