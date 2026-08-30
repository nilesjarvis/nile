import XCTest
@testable import Nile

final class NileSlashCatalogPolicyTests: XCTestCase {
    func testDiscoveredProfileCommandsAreBlockedAndRemovedFromCatalog() {
        let catalog = CommandCatalog(
            categories: [
                CommandCategory(
                    name: "Core",
                    commands: [
                        CommandInfo(name: "/new", description: "old"),
                        CommandInfo(name: "/model", description: "old"),
                        CommandInfo(name: "/subgoal", description: "old"),
                        CommandInfo(name: "/undo", description: "unsafe"),
                    ]
                ),
                CommandCategory(
                    name: "User commands",
                    commands: [
                        CommandInfo(name: "/deploy", description: "custom"),
                        CommandInfo(name: "/goal", description: "shadow"),
                    ]
                ),
            ],
            skillCommands: [
                CommandInfo(name: "/review", description: "skill"),
                CommandInfo(name: "/status", description: "collision"),
            ]
        )

        let curated = NileSlashCatalogPolicy.curateCatalog(catalog)

        XCTAssertEqual(curated.extensionNames, [])
        XCTAssertEqual(
            curated.blockedNames,
            ["deploy", "review", "status"]
        )
        XCTAssertEqual(
            curated.catalog.categories.flatMap(\.commands).map(\.name),
            ["/new", "/model", "/subgoal"]
        )
        XCTAssertEqual(curated.catalog.skillCommands, [])
        XCTAssertEqual(
            curated.catalog.categories[0].commands[0].description,
            "Start a new chat"
        )
        XCTAssertEqual(
            NileSlashPolicy.decide(
                "/deploy",
                blockedNames: curated.blockedNames
            ).surface,
            .blocked
        )
    }

    func testCompletionFilteringPreservesOnlySafeRootAndSubgoalRows() {
        let root = NileSlashCatalogPolicy.filterCompletions(
            query: "/",
            completions: SlashCompletions(
                items: [
                    SlashCompletion(
                        text: "model",
                        display: "/model",
                        meta: "model"
                    ),
                    SlashCompletion(
                        text: "undo",
                        display: "/undo",
                        meta: "unsafe"
                    ),
                    SlashCompletion(
                        text: "deploy",
                        display: "/deploy",
                        meta: "custom"
                    ),
                ],
                replaceFrom: 1
            ),
            extensionNames: [],
            blockedNames: ["deploy"]
        )
        XCTAssertEqual(root.items.map(\.display), ["/model"])

        let nested = NileSlashCatalogPolicy.filterCompletions(
            query: "/subgoal r",
            completions: SlashCompletions(
                items: [
                    SlashCompletion(
                        text: "remove",
                        display: "remove",
                        meta: "Remove"
                    ),
                    SlashCompletion(
                        text: "clear now",
                        display: "clear now",
                        meta: "Invalid"
                    ),
                ],
                replaceFrom: 9
            ),
            extensionNames: []
        )
        XCTAssertEqual(nested.items.map(\.text), ["remove"])
    }
}
