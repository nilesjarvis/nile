import Foundation

/// Remote command execution, alias validation, and cancellation state.
///
/// The observable `SessionCommandRuntime` retains the sole stored command
/// capability and supplies it only for an admitted operation. This subordinate
/// owns mutation tasks without adding catalog, completion, or event authority.
@MainActor
final class SessionCommandExecutionLifecycle {
    private var executionTasks: [UUID: Task<Void, Never>] = [:]
    private var activeExecutionIDs: [
        SessionCommandRuntime.ExecutionOwner: UUID
    ] = [:]

    isolated deinit {
        executionTasks.values.forEach { $0.cancel() }
    }

    func isExecuting(
        owner: SessionCommandRuntime.ExecutionOwner
    ) -> Bool {
        activeExecutionIDs[owner] != nil
    }

    @discardableResult
    func start(
        repository: any HermesCommandServing,
        owner: SessionCommandRuntime.ExecutionOwner,
        liveSessionID: String,
        input: String,
        extensionNames: Set<String>,
        blockedNames: Set<String>,
        prepare: @escaping SessionCommandRuntime.Preparation,
        onOutcome: @escaping SessionCommandRuntime.OutcomeHandler
    ) -> Bool {
        guard activeExecutionIDs[owner] == nil else {
            return false
        }
        let operationID = UUID()
        activeExecutionIDs[owner] = operationID
        let task = Task { [weak self] in
            let outcome: SessionCommandRuntime.ExecutionOutcome
            if await prepare() {
                do {
                    try Task.checkCancellation()
                    let execution = try await Self.executeValidatedCommand(
                        repository: repository,
                        liveSessionID: liveSessionID,
                        initialInput: input,
                        extensionNames: extensionNames,
                        blockedNames: blockedNames
                    )
                    try Task.checkCancellation()
                    outcome = .completed(execution)
                } catch is CancellationError {
                    outcome = .cancelled
                } catch let failure as CommandExecutionFailure {
                    outcome = .failed(
                        message: failure.localizedDescription,
                        uncertain: failure.uncertain
                    )
                } catch {
                    outcome = .failed(
                        message: error.localizedDescription,
                        uncertain: Self.isUncertainMutationFailure(error)
                    )
                }
            } else {
                outcome = .preparationFailed
            }
            await onOutcome(outcome)
            self?.finishExecution(id: operationID, owner: owner)
        }
        executionTasks[operationID] = task
        return true
    }

    func cancelAll() {
        executionTasks.values.forEach { $0.cancel() }
        executionTasks = [:]
        activeExecutionIDs = [:]
    }

    private func finishExecution(
        id: UUID,
        owner: SessionCommandRuntime.ExecutionOwner
    ) {
        executionTasks.removeValue(forKey: id)
        if activeExecutionIDs[owner] == id {
            activeExecutionIDs.removeValue(forKey: owner)
        }
    }

    private static func executeValidatedCommand(
        repository: any HermesCommandServing,
        liveSessionID: String,
        initialInput: String,
        extensionNames: Set<String>,
        blockedNames: Set<String>
    ) async throws -> CommandExecution {
        var invocation = initialInput
        var visitedNames: Set<String> = []
        for index in 0..<3 {
            let decision = NileSlashPolicy.decide(
                invocation,
                extensionNames: extensionNames,
                blockedNames: blockedNames
            )
            let route: CommandRoute
            switch decision.surface {
            case .slashExec:
                route = .slashExec
            case .commandDispatch:
                route = .dispatch
            case .blocked:
                throw HermesError(
                    "The alias points to /\(decision.name), which isn't available in Nile. It was not run.",
                    retryable: false
                )
            default:
                throw HermesError(
                    "The alias points to /\(decision.name), which must be used directly in Nile. It was not run.",
                    retryable: false
                )
            }
            guard visitedNames.insert(decision.name).inserted else {
                throw HermesError(
                    "Command alias cycle detected at /\(decision.name)",
                    retryable: false
                )
            }
            let execution: CommandExecution
            do {
                execution = try await repository.executeCommand(
                    liveSessionID: liveSessionID,
                    command: invocation,
                    route: route
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw CommandExecutionFailure(
                    underlying: error,
                    uncertain: commandErrorMayHaveExecuted(
                        route: route,
                        error: error
                    )
                )
            }
            guard case let .alias(target) = execution else {
                return execution
            }
            guard index < 2 else {
                throw HermesError(
                    "Command alias chain is too deep",
                    retryable: false
                )
            }
            invocation = try aliasTargetWithArguments(
                target: target,
                sourceInvocation: invocation
            )
        }
        throw HermesError("Command alias chain is too deep", retryable: false)
    }

    private static func aliasTargetWithArguments(
        target: String,
        sourceInvocation: String
    ) throws -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\n"),
              !trimmed.contains("\r") else {
            throw HermesError(
                "Hermes returned an invalid command alias",
                retryable: false
            )
        }
        let sourceParts = sourceInvocation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "/" })
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let argument = sourceParts.count > 1 ? String(sourceParts[1]) : ""
        let normalizedTarget = "/" + trimmed.drop(while: { $0 == "/" })
        return argument.isBlank
            ? normalizedTarget
            : "\(normalizedTarget) \(argument)"
    }

    private static func commandErrorMayHaveExecuted(
        route: CommandRoute,
        error: any Error
    ) -> Bool {
        if route == .dispatch {
            return true
        }
        guard let hermes = error as? HermesError else {
            return true
        }
        if hermes.isConnectionFailure || hermes.requestMayHaveSucceeded {
            return true
        }
        return ![4001, 4004, 4009, 4018].contains(hermes.code)
    }

    private static func isUncertainMutationFailure(
        _ error: any Error
    ) -> Bool {
        guard let hermes = error as? HermesError else {
            return true
        }
        return hermes.isConnectionFailure || hermes.requestMayHaveSucceeded
    }
}

private struct CommandExecutionFailure: LocalizedError {
    let underlying: any Error
    let uncertain: Bool

    var errorDescription: String? {
        underlying.localizedDescription
    }
}
