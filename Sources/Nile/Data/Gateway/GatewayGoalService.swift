import Foundation

/// Owns standing-goal compatibility checks, configuration, and mutations.
struct GatewayGoalService: HermesGoalServing, Sendable {
    private let rpc: any GatewayRPCRequesting
    private let commands: any HermesCommandServing

    init(
        rpc: any GatewayRPCRequesting,
        commands: any HermesCommandServing
    ) {
        self.rpc = rpc
        self.commands = commands
    }

    func goalStatus(liveSessionID: String) async throws -> HermesGoal? {
        try await ensureGoalCompatibilityTarget()
        return try await readVerifiedGoalStatus(
            liveSessionID: liveSessionID
        )
    }

    func setGoal(
        liveSessionID: String,
        objective: String,
        maxTurns: Int?
    ) async throws -> GoalStart {
        let normalized = objective.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty,
              normalized.count <= 2_000,
              !normalized.contains("\n"),
              !normalized.contains("\r") else {
            throw HermesError(
                "A goal must be one line between 1 and 2,000 characters",
                retryable: false
            )
        }
        try await ensureGoalCompatibilityTarget()
        if let maxTurns {
            try await configureGoalTurnBudget(maxTurns)
        }
        let result = try await commands.executeCommand(
            liveSessionID: liveSessionID,
            command: "goal \(normalized)",
            route: .dispatch
        )
        guard case let .submitPrompt(message, notice) = result,
              message == normalized else {
            throw malformedGoalResponse(
                method: "goal.set",
                mutationMayHaveSucceeded: true
            )
        }
        let resolvedNotice = notice ?? ""
        return GoalStart(
            goal: try parseGoalSetNotice(
                resolvedNotice,
                expectedObjective: normalized
            ),
            kickoffPrompt: message,
            notice: resolvedNotice
        )
    }

    func pauseGoal(liveSessionID: String) async throws -> HermesGoal? {
        try await ensureGoalCompatibilityTarget()
        let result = try await commands.executeCommand(
            liveSessionID: liveSessionID,
            command: "goal pause",
            route: .dispatch
        )
        guard case let .output(output) = result,
              output.hasPrefix("⏸ Goal paused:")
                || output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == "No goal set." else {
            throw malformedGoalResponse(
                method: "goal.pause",
                mutationMayHaveSucceeded: true
            )
        }
        return try await readVerifiedGoalStatus(
            liveSessionID: liveSessionID
        )
    }

    func resumeGoal(liveSessionID: String) async throws -> HermesGoal? {
        try await ensureGoalCompatibilityTarget()
        let result = try await commands.executeCommand(
            liveSessionID: liveSessionID,
            command: "goal resume",
            route: .dispatch
        )
        guard case let .output(output) = result,
              output.hasPrefix("▶ Goal resumed:")
                || output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) == "No goal to resume." else {
            throw malformedGoalResponse(
                method: "goal.resume",
                mutationMayHaveSucceeded: true
            )
        }
        return try await readVerifiedGoalStatus(
            liveSessionID: liveSessionID
        )
    }

    func clearGoal(liveSessionID: String) async throws {
        try await ensureGoalCompatibilityTarget()
        let result = try await commands.executeCommand(
            liveSessionID: liveSessionID,
            command: "goal clear",
            route: .dispatch
        )
        guard case let .output(output) = result,
              ["✓ Goal cleared.", "No active goal."].contains(
                  output.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  )
              ) else {
            throw malformedGoalResponse(
                method: "goal.clear",
                mutationMayHaveSucceeded: true
            )
        }
    }

    private func configureGoalTurnBudget(_ maxTurns: Int) async throws {
        guard (1...100).contains(maxTurns) else {
            throw HermesError(
                "A goal turn budget must be between 1 and 100",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "cli.exec",
            params: [
                "argv": .array([
                    .string("config"),
                    .string("set"),
                    .string("goals.max_turns"),
                    .string(String(maxTurns)),
                ]),
                "timeout": .number(30),
            ],
            timeoutMilliseconds: 60_000,
            allowNullResult: false
        )
        try Self.requireGoalTurnBudgetConfigured(result)
    }

    private func readVerifiedGoalStatus(
        liveSessionID: String
    ) async throws -> HermesGoal? {
        let result = try await commands.executeCommand(
            liveSessionID: liveSessionID,
            command: "goal status",
            route: .dispatch
        )
        guard case let .output(output) = result else {
            throw malformedGoalResponse(
                method: "goal.status",
                mutationMayHaveSucceeded: false
            )
        }
        return try parseGoalStatusOutput(output)
    }

    private func ensureGoalCompatibilityTarget() async throws {
        let catalog = try await commands.commandsCatalog()
        let userCommands = catalog.categories
            .filter {
                $0.name.caseInsensitiveCompare("User commands")
                    == .orderedSame
            }
            .flatMap(\.commands)
        let shadowsGoal = (userCommands + catalog.skillCommands).contains {
            $0.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).drop(while: { $0 == "/" })
                .caseInsensitiveCompare("goal") == .orderedSame
        }
        guard !shadowsGoal else {
            throw HermesError(
                "This Hermes profile shadows /goal, so Nile cannot control it safely",
                retryable: false
            )
        }
        let result = try await rpc.request(
            method: "command.resolve",
            params: ["name": .string("goal")],
            timeoutMilliseconds: 30_000,
            allowNullResult: false
        )
        guard result.string("canonical")
            .caseInsensitiveCompare("goal") == .orderedSame else {
            throw HermesError(
                "This Hermes gateway does not expose the built-in goal command",
                retryable: false
            )
        }
    }

    private static func requireGoalTurnBudgetConfigured(
        _ result: JSONValue.Object
    ) throws {
        guard case let .bool(blocked)? = result["blocked"] else {
            throw GatewayMutationCodec.malformedResult(
                method: "cli.exec goal budget",
                detail: "blocked was missing or not true or false"
            )
        }
        guard case let .number(codeNumber)? = result["code"],
              codeNumber.isFinite,
              codeNumber.rounded(.towardZero) == codeNumber,
              codeNumber >= Double(Int.min),
              codeNumber <= Double(Int.max) else {
            throw GatewayMutationCodec.malformedResult(
                method: "cli.exec goal budget",
                detail: "code was missing or not an integer"
            )
        }
        guard let output = result["output"]?.stringValue else {
            throw GatewayMutationCodec.malformedResult(
                method: "cli.exec goal budget",
                detail: "output was missing or not a string"
            )
        }
        if blocked {
            throw HermesError(
                "Hermes does not allow changing the goal turn budget from this gateway",
                retryable: false
            )
        }
        guard Int(codeNumber) == 0 else {
            throw HermesError(
                output.isBlank
                    ? "Hermes could not save the goal turn budget"
                    : output,
                retryable: false
            )
        }
    }
}
