struct SlashCompletion: Equatable, Sendable {
    let text: String
    let display: String
    let meta: String
}

struct SlashCompletions: Equatable, Sendable {
    let items: [SlashCompletion]
    let replaceFrom: Int
}

struct CommandInfo: Equatable, Sendable {
    let name: String
    let description: String
}

struct CommandCategory: Equatable, Sendable {
    let name: String
    let commands: [CommandInfo]
}

struct CommandCatalog: Equatable, Sendable {
    let categories: [CommandCategory]
    let skillCommands: [CommandInfo]
}

enum CommandExecution: Equatable, Sendable {
    case output(String)
    case submitPrompt(message: String, notice: String?)
    case prefillComposer(message: String, notice: String?)
    case alias(target: String)
}

enum CommandRoute: String, Codable, Sendable {
    case slashExec
    case dispatch
}

protocol HermesCommandServing: Sendable {
    func commandsCatalog() async throws -> CommandCatalog
    func completeSlash(text: String) async throws -> SlashCompletions
    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution
}

extension HermesCommandServing {
    func executeCommand(
        liveSessionID: String,
        command: String
    ) async throws -> CommandExecution {
        try await executeCommand(
            liveSessionID: liveSessionID,
            command: command,
            route: .slashExec
        )
    }

    func commandsCatalog() async throws -> CommandCatalog {
        throw HermesError(
            "Slash commands are unavailable for this repository",
            retryable: false
        )
    }

    func completeSlash(text: String) async throws -> SlashCompletions {
        throw HermesError(
            "Slash commands are unavailable for this repository",
            retryable: false
        )
    }

    func executeCommand(
        liveSessionID: String,
        command: String,
        route: CommandRoute
    ) async throws -> CommandExecution {
        throw HermesError(
            "Slash commands are unavailable for this repository",
            retryable: false
        )
    }
}
