import XCTest
@testable import Nile

extension TuiGatewayRepositoryTests {
    func testAttachmentRPCsUseExactHermesContracts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "image.attach_bytes": [
                    "path": .string("/tmp/hermes/photo.jpg"),
                    "filename": .string("server-photo.jpg"),
                ],
                "image.detach": ["detached": .bool(true)],
            ]
        )
        let repository = repository(rpc: rpc)
        let attachments = repository.sessionCapabilities.attachmentMutating

        let attached = try await attachments.attachImage(
            liveSessionID: "live-1",
            base64: "anBlZw==",
            fileExtension: ".jpg",
            filename: "photo.jpg"
        )
        let detached = try await attachments.detachImage(
            liveSessionID: "live-1",
            path: attached.path
        )

        XCTAssertEqual(
            attached,
            AttachedImage(
                path: "/tmp/hermes/photo.jpg",
                filename: "server-photo.jpg"
            )
        )
        XCTAssertTrue(detached)
        let requests = await rpc.requests
        XCTAssertEqual(
            requests,
            [
                RPCRequest(
                    method: "image.attach_bytes",
                    params: [
                        "session_id": .string("live-1"),
                        "content_base64": .string("anBlZw=="),
                        "ext": .string(".jpg"),
                        "filename": .string("photo.jpg"),
                    ],
                    timeoutMilliseconds: 60_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "image.detach",
                    params: [
                        "session_id": .string("live-1"),
                        "path": .string("/tmp/hermes/photo.jpg"),
                    ],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: true
                ),
            ]
        )
    }

    func testMalformedDetachIsUncertainBecauseServerMayHaveRemovedPath() async {
        let repository = repository(
            rpc: RecordingRPC(
                responses: ["image.detach": ["detached": .string("yes")]]
            )
        )
        let attachments = repository.sessionCapabilities.attachmentMutating

        await XCTAssertThrowsErrorAsync(
            try await attachments.detachImage(
                liveSessionID: "live-1",
                path: "/tmp/photo.jpg"
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "image.detach result was missing detached"
            )
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
        }
    }

    func testCommandDiscoveryCompletionAndExecutionUseExactContracts() async throws {
        let rpc = RecordingRPC(
            responses: [
                "commands.catalog": [
                    "categories": .array([
                        .object([
                            "name": .string("Core"),
                            "pairs": .array([
                                .array([
                                    .string("/model"),
                                    .string("Choose model"),
                                ]),
                            ]),
                        ]),
                    ]),
                    "pairs": .array([
                        .array([
                            .string("/model"),
                            .string("Choose model"),
                        ]),
                        .array([
                            .string("/review"),
                            .string("Review skill"),
                        ]),
                    ]),
                    "skill_count": .number(1),
                    "warning": .string(""),
                ],
                "complete.slash": [
                    "items": .array([
                        .object([
                            "text": .string("/model"),
                            "display": .string("/model"),
                            "meta": .string("Choose model"),
                        ]),
                    ]),
                    "replace_from": .number(1),
                ],
                "slash.exec": [
                    "type": .string("exec"),
                    "output": .string("Subgoal added"),
                ],
                "command.dispatch": [
                    "type": .string("skill"),
                    "name": .string("review"),
                    "message": .string("Review this"),
                    "notice": .string("Prepared"),
                ],
            ]
        )
        let commands = commandService(rpc: rpc)

        let catalog = try await commands.commandsCatalog()
        let completions = try await commands.completeSlash(text: "/mo")
        let slash = try await commands.executeCommand(
            liveSessionID: "live-1",
            command: "/subgoal release must pass",
            route: .slashExec
        )
        let dispatch = try await commands.executeCommand(
            liveSessionID: "live-1",
            command: "/review now",
            route: .dispatch
        )

        XCTAssertEqual(catalog.categories[0].commands.map(\.name), ["/model"])
        XCTAssertEqual(catalog.skillCommands.map(\.name), ["/review"])
        XCTAssertEqual(completions.items.map(\.text), ["model"])
        XCTAssertEqual(completions.replaceFrom, 1)
        XCTAssertEqual(slash, .output("Subgoal added"))
        XCTAssertEqual(
            dispatch,
            .submitPrompt(
                message: "Review this",
                notice: "⚡ loading skill: review\nPrepared"
            )
        )
        let requests = await rpc.requests
        XCTAssertEqual(
            Array(requests.suffix(4)),
            [
                RPCRequest(
                    method: "commands.catalog",
                    params: [:],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "complete.slash",
                    params: ["text": .string("/mo")],
                    timeoutMilliseconds: 30_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "slash.exec",
                    params: [
                        "session_id": .string("live-1"),
                        "command": .string("subgoal release must pass"),
                    ],
                    timeoutMilliseconds: 60_000,
                    allowNullResult: false
                ),
                RPCRequest(
                    method: "command.dispatch",
                    params: [
                        "session_id": .string("live-1"),
                        "name": .string("review"),
                        "arg": .string("now"),
                    ],
                    timeoutMilliseconds: 60_000,
                    allowNullResult: false
                ),
            ]
        )
    }

    func testIncompleteDiscoveryAndMalformedCommandResultsFailClosed() async {
        let discovery = commandService(
            rpc: RecordingRPC(
                responses: [
                    "commands.catalog": [
                        "categories": .array([]),
                        "pairs": .array([]),
                        "skill_count": .number(0),
                        "warning": .string("skill discovery unavailable"),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await discovery.commandsCatalog()
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("discovery was incomplete")
            )
        }

        let malformed = commandService(
            rpc: RecordingRPC(
                responses: [
                    "slash.exec": [
                        "type": .string("send"),
                        "message": .number(42),
                    ],
                ]
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await malformed.executeCommand(
                liveSessionID: "live-1",
                command: "/subgoal ship",
                route: .slashExec
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertTrue(
                hermes?.message.contains("Malformed response to slash.exec")
                    == true
            )
            XCTAssertEqual(hermes?.requestMayHaveSucceeded, true)
            XCTAssertEqual(hermes?.retryable, false)
        }
    }

}
