import Foundation

struct CuratedNileCommandCatalog: Equatable, Sendable {
    let catalog: CommandCatalog
    let extensionNames: Set<String>
    let blockedNames: Set<String>
}

enum NileSlashCatalogPolicy {
    private static let discoveryHiddenNames: Set<String> = [
        "reset", "compose", "fork", "compact", "snap", "bg", "btw",
        "tasks", "learning", "memory-graph", "q", "set-home",
        "codex_runtime", "sb", "ts", "generate-pet", "suggest", "bp",
        "reload_mcp", "reload_skills", "gateway", "v", "exit", "detail",
        "scroll", "switch", "session", "commands",
    ]

    private static let curatedDescriptions = [
        "new": "Start a new chat",
        "model": "Choose a model to use",
        "help": "See available commands and what they do",
        "goal": "Set or control a simple standing goal",
        "learn": "Learn a reusable skill from this chat or a description",
        "plan": "Create a plan from this chat or a description",
        "subgoal": "List, add, remove, or clear standing-goal criteria",
    ]

    static func curateCatalog(
        _ catalog: CommandCatalog
    ) -> CuratedNileCommandCatalog {
        let skillNames = Set(
            catalog.skillCommands.map {
                NileSlashPolicy.normalizeName($0.name)
            }
        )
        let userNames = Set(
            catalog.categories
                .filter {
                    $0.name.caseInsensitiveCompare("User commands")
                        == .orderedSame
                }
                .flatMap(\.commands)
                .map { NileSlashPolicy.normalizeName($0.name) }
        )
        let blockedNames = Set(
            skillNames.union(userNames).filter {
                !NileSlashPolicy.isReservedNativeName($0)
            }
        )
        let extensionNames: Set<String> = []

        func visible(_ info: CommandInfo) -> Bool {
            let name = NileSlashPolicy.normalizeName(info.name)
            return NileSlashPolicy.decide(
                info.name,
                extensionNames: extensionNames,
                blockedNames: blockedNames
            ).surface != .blocked && !discoveryHiddenNames.contains(name)
        }

        func curated(_ info: CommandInfo) -> CommandInfo {
            CommandInfo(
                name: info.name,
                description:
                    curatedDescriptions[NileSlashPolicy.normalizeName(info.name)]
                    ?? info.description
            )
        }

        let categories = catalog.categories.compactMap { category in
            let isUserCategory =
                category.name.caseInsensitiveCompare("User commands")
                == .orderedSame
            let commands = category.commands.compactMap { info -> CommandInfo? in
                if isUserCategory,
                   NileSlashPolicy.isKnownHermesName(info.name) {
                    return nil
                }
                return visible(info) ? curated(info) : nil
            }
            return commands.isEmpty
                ? nil
                : CommandCategory(name: category.name, commands: commands)
        }
        let skills = catalog.skillCommands.compactMap { info -> CommandInfo? in
            guard !NileSlashPolicy.isKnownHermesName(info.name),
                  visible(info) else {
                return nil
            }
            return curated(info)
        }
        return CuratedNileCommandCatalog(
            catalog: CommandCatalog(
                categories: categories,
                skillCommands: skills
            ),
            extensionNames: extensionNames,
            blockedNames: blockedNames
        )
    }

    static func filterCompletions(
        query: String,
        completions: SlashCompletions,
        extensionNames: Set<String>,
        blockedNames: Set<String> = []
    ) -> SlashCompletions {
        let items: [SlashCompletion]
        if completions.replaceFrom > 1 {
            let replaceFrom = min(max(completions.replaceFrom, 0), query.count)
            let prefix = String(query.prefix(replaceFrom))
            items = completions.items.filter { item in
                let candidate = prefix + item.text
                return candidate.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).caseInsensitiveCompare("/subgoal remove") == .orderedSame
                    || NileSlashPolicy.decide(
                        candidate,
                        extensionNames: extensionNames,
                        blockedNames: blockedNames
                    ).surface != .blocked
            }
        } else {
            items = completions.items.filter { item in
                let candidate = item.display.hasPrefix("/")
                    ? item.display
                    : item.text
                let name = NileSlashPolicy.normalizeName(candidate)
                return NileSlashPolicy.decide(
                    "/\(name)",
                    extensionNames: extensionNames,
                    blockedNames: blockedNames
                ).surface != .blocked
                    && !discoveryHiddenNames.contains(name)
            }
        }
        return SlashCompletions(
            items: items,
            replaceFrom: completions.replaceFrom
        )
    }
}
