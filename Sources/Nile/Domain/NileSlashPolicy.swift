import Foundation

enum NileSlashSurface: Equatable, Sendable {
    case nativeNew
    case nativeModel
    case nativeHelp
    case nativeGoal
    case nativeReasoning
    case slashExec
    case commandDispatch
    case blocked
}

struct NileSlashDecision: Equatable, Sendable {
    let name: String
    let surface: NileSlashSurface
    var message: String?
    var argument: String?
}

enum NileSlashPolicy {
    private static let nativeNew: Set<String> = ["new", "reset"]
    private static let nativeModel: Set<String> = ["model"]
    private static let nativeHelp: Set<String> = ["help", "commands"]
    private static let nativeNames =
        nativeNew.union(nativeModel).union(nativeHelp)
            .union(["goal", "reasoning"])

    private static let knownHermesNames: Set<String> = [
        "agents", "approve", "background", "billing", "blueprint", "branch",
        "browser", "bundles", "busy", "clear", "codex-runtime", "commands",
        "compress", "config", "copy", "credits", "cron", "curator", "debug",
        "deny", "fast", "footer", "goal", "handoff", "hatch", "help",
        "history", "image", "indicator", "insights", "journey", "kanban",
        "learn", "memory", "moa", "model", "new", "paste", "personality",
        "pet", "platform", "platforms", "plugins", "profile", "prompt",
        "queue", "quit", "reasoning", "redraw", "reload", "reload-mcp",
        "reload-skills", "restart", "resume", "retry", "rollback", "save",
        "sessions", "sethome", "skills", "skin", "snapshot", "start",
        "status", "statusbar", "steer", "stop", "subgoal", "suggestions",
        "timestamps", "title", "tools", "toolsets", "topic", "undo",
        "update", "usage", "verbose", "version", "voice", "whoami", "yolo",
        "reset", "compose", "fork", "compact", "snap", "bg", "btw",
        "tasks", "learning", "memory-graph", "q", "set-home",
        "codex_runtime", "sb", "ts", "generate-pet", "suggest", "bp",
        "reload_mcp", "reload_skills", "gateway", "v", "exit", "details",
        "detail", "logs", "mouse", "scroll", "switch", "session", "plan",
    ]

    static func decide(
        _ command: String,
        extensionNames: Set<String> = [],
        blockedNames: Set<String> = []
    ) -> NileSlashDecision {
        let parsed = parse(command)
        let name = parsed.name
        let argument = parsed.argument
        guard !name.isEmpty else {
            return NileSlashDecision(
                name: name,
                surface: .blocked,
                message: "Enter a slash command."
            )
        }
        if command.contains("\n") || command.contains("\r") {
            return blocked(
                name,
                "Slash commands must fit on one line. Your draft was kept."
            )
        }
        let normalizedBlockedNames = Set(blockedNames.map(normalizeName))
        if normalizedBlockedNames.contains(name),
           !nativeNames.contains(name) {
            return blocked(
                name,
                "/\(name) is supplied by this Hermes profile, but the pinned mobile protocol can't prove whether dispatch will run a skill, plugin, alias, or host command. Run it from a Hermes terminal. Your draft was kept."
            )
        }
        if nativeNew.contains(name) {
            return argument.isEmpty
                ? NileSlashDecision(name: name, surface: .nativeNew)
                : blocked(
                    name,
                    "That option isn't supported yet. Type /new without arguments, then rename the chat from the session list. Your draft was kept."
                )
        }
        if nativeModel.contains(name) {
            return argument.isEmpty
                ? NileSlashDecision(name: name, surface: .nativeModel)
                : blocked(
                    name,
                    "Use the model picker to switch models. Your draft was kept."
                )
        }
        if name == "reasoning" {
            guard !argument.isEmpty else {
                return blocked(
                    name,
                    "Specify an effort level: /reasoning <none|minimal|low|medium|high|xhigh|max>. Your draft was kept."
                )
            }
            let normalized = argument.lowercased()
            return reasoningEffortOptions.contains(normalized)
                ? NileSlashDecision(
                    name: name,
                    surface: .nativeReasoning,
                    argument: normalized
                )
                : blocked(
                    name,
                    "Unknown reasoning effort \"\(normalized)\". Valid levels: none, minimal, low, medium, high, xhigh, max. Your draft was kept."
                )
        }
        if nativeHelp.contains(name) {
            return argument.isEmpty
                ? NileSlashDecision(name: name, surface: .nativeHelp)
                : blocked(
                    name,
                    "/\(name) doesn't take arguments in Nile. Your draft was kept."
                )
        }
        if name == "goal" {
            return argument.isEmpty
                ? NileSlashDecision(name: name, surface: .nativeGoal)
                : blocked(
                    name,
                    "Open Nile’ Goal sheet and choose a quick start or review the objective there. Your draft was kept."
                )
        }
        if name == "subgoal" {
            return decideSubgoal(name: name, argument: argument)
        }

        let normalizedExtensions = Set(extensionNames.map(normalizeName))
        switch name {
        case "undo", "retry", "rollback":
            return blocked(
                name,
                "/\(name) can rewrite conversation or filesystem history without mobile confirmation. Run it from Hermes in a terminal. Your draft was kept."
            )
        case "compact":
            return blocked(
                name,
                "/compact is a TUI display command that Hermes interprets as context compression here. Run /compress from a Hermes terminal if that is what you want. Your draft was kept."
            )
        case "compress":
            return blocked(
                name,
                "/compress changes Hermes' stored conversation identity, which this mobile protocol can't safely follow. Run it from a Hermes terminal. Your draft was kept."
            )
        case "queue", "q":
            return blocked(
                name,
                "/queue isn't supported in Nile yet. Wait for the turn to finish, then send the message. Your draft was kept."
            )
        case "steer":
            return blocked(
                name,
                "Send plain text while Hermes is working to steer the turn; /steer isn't used in Nile. Your draft was kept."
            )
        case "resume", "sessions", "switch", "session":
            return blocked(
                name,
                "Use the session list to switch chats. Your draft was kept."
            )
        case "update":
            return blocked(
                name,
                "Update Hermes from Settings. Your draft was kept."
            )
        case "learn":
            return blocked(
                name,
                "/learn can't be resolved atomically on the pinned mobile protocol; a profile command can shadow it after discovery. Run it from a Hermes terminal. Your draft was kept."
            )
        case "plan":
            return blocked(
                name,
                "/plan can't be resolved safely on the pinned mobile protocol because a profile plugin can shadow the bundled skill. Run it from a Hermes terminal. Your draft was kept."
            )
        case "debug":
            return blocked(
                name,
                "/debug can upload system details and logs. Run it from Hermes after reviewing its upload options. Your draft was kept."
            )
        default:
            if knownHermesNames.contains(name) {
                return blocked(
                    name,
                    "/\(name) isn't available in Nile. Your draft was kept."
                )
            }
            if normalizedExtensions.contains(name) {
                return blocked(
                    name,
                    "/\(name) can't be resolved safely as a profile command on the pinned mobile protocol. Run it from a Hermes terminal. Your draft was kept."
                )
            }
            return blocked(
                name,
                "Nile couldn't verify /\(name) as a skill or user command. Your draft was kept."
            )
        }
    }

    private static func decideSubgoal(
        name: String,
        argument: String
    ) -> NileSlashDecision {
        guard !argument.isEmpty else {
            return NileSlashDecision(name: name, surface: .slashExec)
        }
        let words = argument.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.first?.lowercased() {
        case "clear":
            return words.count == 1
                ? NileSlashDecision(name: name, surface: .slashExec)
                : blocked(
                    name,
                    "Use /subgoal clear without extra text. Your draft was kept."
                )
        case "remove":
            let index = words.count == 2 ? Int(words[1]) : nil
            return index.map { $0 > 0 } == true
                ? NileSlashDecision(name: name, surface: .slashExec)
                : blocked(
                    name,
                    "Use /subgoal remove with one positive number. Your draft was kept."
                )
        default:
            return NileSlashDecision(name: name, surface: .slashExec)
        }
    }

    private static func blocked(
        _ name: String,
        _ message: String
    ) -> NileSlashDecision {
        NileSlashDecision(
            name: name,
            surface: .blocked,
            message: message
        )
    }

    private static func parse(
        _ command: String
    ) -> (name: String, argument: String) {
        let stripped = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "/" })
        let parts = stripped.split(
            maxSplits: 1,
            whereSeparator: \.isWhitespace
        )
        return (
            normalizeName(parts.first.map(String.init) ?? ""),
            parts.count > 1
                ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
        )
    }

    static func isReservedNativeName(_ command: String) -> Bool {
        nativeNames.contains(normalizeName(command))
    }

    static func isKnownHermesName(_ command: String) -> Bool {
        knownHermesNames.contains(normalizeName(command))
    }

    static func normalizeName(_ command: String) -> String {
        let stripped = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "/" })
        return stripped.split(
            maxSplits: 1,
            whereSeparator: \.isWhitespace
        ).first.map(String.init)?.lowercased() ?? ""
    }
}
