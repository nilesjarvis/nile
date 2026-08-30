import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testSlashCatalogCompletionAndSubgoalCommandStaySourceScoped() async {
        let catalog = CommandCatalog(
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
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            commandCatalog: catalog,
            slashCompletions: SlashCompletions(
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
            ),
            commandExecution: .output("Subgoal added")
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(
            model.commandCatalog?.categories.flatMap(\.commands).map(\.name),
            ["/subgoal"]
        )
        model.updateComposer("/sub")
        await eventually {
            model.slashCompletions.map(\.display) == ["/subgoal"]
        }
        model.applySlashCompletion("subgoal")
        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.transcriptEntries.contains { entry in
                guard case let .command(command) = entry else {
                    return false
                }
                return command.command == "/subgoal"
                    && command.output == "Subgoal added"
                    && command.status == .done
            }
        }
        XCTAssertEqual(model.composer, "")
        let calls = await repository.calls
        XCTAssertTrue(calls.contains("complete.slash:/sub"))
        XCTAssertTrue(calls.contains("slash.exec:live-one:/subgoal"))
        XCTAssertFalse(
            calls.contains(where: { $0.contains("prompt.submit") })
        )
    }

    func testBlockedSlashKeepsDraftAndNeverCallsRemoteCommand() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            commandCatalog: CommandCatalog(
                categories: [
                    CommandCategory(
                        name: "Core",
                        commands: [
                            CommandInfo(name: "/undo", description: "Unsafe"),
                        ]
                    ),
                ],
                skillCommands: []
            ),
            commandExecution: .output("must not run")
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("/undo")
        XCTAssertFalse(model.sendMessage())

        XCTAssertEqual(model.composer, "/undo")
        XCTAssertTrue(
            model.operationError?.contains("draft was kept") == true
        )
        let calls = await repository.calls
        XCTAssertFalse(
            calls.contains(where: {
                $0.hasPrefix("slash.exec:")
                    || $0.hasPrefix("command.dispatch:")
            })
        )
    }

    func testDefiniteSlashRejectionRestoresDraftWithoutUncertainWarning() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            commandCatalog: CommandCatalog(
                categories: [
                    CommandCategory(
                        name: "Core",
                        commands: [
                            CommandInfo(
                                name: "/subgoal",
                                description: "Manage criteria"
                            ),
                        ]
                    ),
                ],
                skillCommands: []
            ),
            commandExecutionError: HermesError(
                "use command.dispatch",
                code: 4018,
                retryable: false
            )
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("/subgoal ship")
        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.composer == "/subgoal ship"
                && model.transcriptEntries.contains { entry in
                    guard case let .command(command) = entry else {
                        return false
                    }
                    return command.status == .error
                }
        }

        XCTAssertTrue(
            model.operationError?.contains("wasn't completed") == true
        )
        XCTAssertFalse(
            model.operationError?.contains("could not confirm") == true
        )
    }

    func testUnknownSlashFailureRestoresDraftWithDuplicateRiskWarning() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            commandCatalog: CommandCatalog(
                categories: [
                    CommandCategory(
                        name: "Core",
                        commands: [
                            CommandInfo(
                                name: "/subgoal",
                                description: "Manage criteria"
                            ),
                        ]
                    ),
                ],
                skillCommands: []
            ),
            commandExecutionError: HermesError(
                "future rejection",
                code: 4999,
                retryable: false
            )
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("/subgoal ship")
        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.composer == "/subgoal ship"
                && model.operationError?.contains("could not confirm") == true
        }
    }

    func testModelPickerLoadsOptionsForCurrentLiveSession() async {
        let options = modelOptionsFixture()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            modelOptions: options
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.setModelPickerVisible(true)

        await eventually {
            model.modelOptions == options
                && !model.isLoadingModelOptions
        }
        XCTAssertTrue(model.isModelPickerVisible)
        XCTAssertNil(model.modelOptionsError)
        let calls = await repository.calls
        XCTAssertTrue(calls.contains("model.options:live-one:false"))
    }

    func testModelPickerFixtureRetainsInMemoryPinAndSwitchSemantics() {
        let model = SessionListModel(fixture: .modelPicker)
        let pin = ModelPin(
            providerSlug: "openai",
            modelID: "gpt-5-mini"
        )

        model.toggleModelPin(
            provider: pin.providerSlug,
            model: pin.modelID
        )
        model.selectModel("gemini-3-flash", provider: "google")

        XCTAssertTrue(model.pinnedModels.contains(pin))
        XCTAssertTrue(model.isUpdatingSessionControls)
        XCTAssertNil(model.operationError)
    }

    func testCompactModelMenuLoadsOptionsWithoutOpeningFullPicker() async {
        let options = modelOptionsFixture()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            modelOptions: options
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.prepareCompactModelMenu()
        model.prepareCompactModelMenu()

        await eventually {
            model.modelOptions == options
                && !model.isLoadingModelOptions
        }
        XCTAssertFalse(model.isModelPickerVisible)
        XCTAssertNil(model.modelOptionsError)
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "model.options:live-one:false" }.count,
            1
        )
    }

    func testAppliedModelSwitchUpdatesOnlyCurrentSessionAndAddsNotice() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            modelOptions: modelOptionsFixture(),
            modelSwitchOutcomes: [
                .applied(
                    resolvedModel: "claude-sonnet-4",
                    warning: "Higher usage cost"
                ),
            ]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setModelPickerVisible(true)
        await eventually { model.modelOptions != nil }

        model.selectModel("claude-sonnet-4", provider: "anthropic")

        await eventually {
            model.liveSession?.info.model == "claude-sonnet-4"
                && !model.isUpdatingSessionControls
        }
        XCTAssertEqual(model.liveSession?.info.provider, "anthropic")
        XCTAssertFalse(model.isModelPickerVisible)
        XCTAssertTrue(
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.role == .system
                    && message.content.contains(
                        "switched this session to claude-sonnet-4"
                    )
                    && message.content.contains("Higher usage cost")
            }
        )
        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains(
                "config.set.model:live-one:anthropic:claude-sonnet-4:false"
            )
        )
    }

    func testExpensiveModelRequiresExplicitConfirmationBeforeApplying() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            modelOptions: modelOptionsFixture(),
            modelSwitchOutcomes: [
                .confirmationRequired(
                    resolvedModel: "claude-sonnet-4",
                    message: "This model costs more."
                ),
                .applied(
                    resolvedModel: "claude-sonnet-4",
                    warning: nil
                ),
            ]
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setModelPickerVisible(true)
        await eventually { model.modelOptions != nil }

        model.selectModel("claude-sonnet-4", provider: "anthropic")
        await eventually {
            model.modelSwitchConfirmation?.message
                == "This model costs more."
        }

        XCTAssertEqual(model.liveSession?.info.model, "claude-haiku")
        model.confirmModelSwitch()
        await eventually {
            model.liveSession?.info.model == "claude-sonnet-4"
                && model.modelSwitchConfirmation == nil
        }

        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains(
                "config.set.model:live-one:anthropic:claude-sonnet-4:false"
            )
        )
        XCTAssertTrue(
            calls.contains(
                "config.set.model:live-one:anthropic:claude-sonnet-4:true"
            )
        )
    }

    func testLateModelSwitchCannotMutateNewlySelectedSession() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            openedSessions: [
                liveSession(id: "one"),
                liveSession(
                    id: "two",
                    model: "session-two-model",
                    provider: "local"
                ),
            ],
            modelOptions: modelOptionsFixture(),
            modelSwitchOutcomes: [
                .applied(
                    resolvedModel: "claude-sonnet-4",
                    warning: nil
                ),
            ],
            blockModelSwitch: true
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setModelPickerVisible(true)
        await eventually { model.modelOptions != nil }
        model.selectModel("claude-sonnet-4", provider: "anthropic")
        await eventuallyAsync {
            await repository.calls.contains(
                "config.set.model:live-one:anthropic:claude-sonnet-4:false"
            )
        }

        await model.selectSession(id: "two")
        await repository.releaseModelSwitch()
        await eventually { !model.isOpeningSession }

        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertEqual(model.liveSession?.info.model, "session-two-model")
        XCTAssertFalse(
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.content.contains("claude-sonnet-4")
            }
        )
    }

    func testUncertainModelMutationClosesPickerAndRequiresVerification() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            modelOptions: modelOptionsFixture(),
            modelSwitchError: HermesError(
                "Connection lost",
                retryable: true,
                isConnectionFailure: true,
                requestMayHaveSucceeded: true
            )
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setModelPickerVisible(true)
        await eventually { model.modelOptions != nil }

        model.selectModel("claude-sonnet-4", provider: "anthropic")

        await eventually {
            model.operationError?.contains("may have changed") == true
                && !model.isUpdatingSessionControls
        }
        XCTAssertFalse(model.isModelPickerVisible)
        XCTAssertEqual(model.liveSession?.info.model, "claude-haiku")
    }

    func testNativeReasoningCommandUsesSessionScopeAndClearsDraft() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [liveSession(id: "one")],
            reasoningEffort: "high"
        )
        let model = SessionListModel(repository: repository)
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.updateComposer("/reasoning high")
        XCTAssertTrue(model.sendMessage())

        await eventually {
            model.liveSession?.info.reasoningEffort == "high"
                && model.composer.isEmpty
        }
        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains("config.set.reasoning:live-one:high")
        )
        XCTAssertTrue(model.transcriptEntries.contains { entry in
            guard case let .message(message) = entry else {
                return false
            }
            return message.content
                == "set this session's reasoning effort to high"
        })
        XCTAssertFalse(
            calls.contains(where: {
                $0.hasPrefix("slash.exec:")
                    || $0.hasPrefix("command.dispatch:")
            })
        )
    }

    func testModelPinsRestoreResolveLegacyAndPersistProviderToggle() async {
        let legacy = ModelPin(providerSlug: nil, modelID: "shared")
        let stale = ModelPin(
            providerSlug: "retired",
            modelID: "retired-model"
        )
        let pinStore = SessionModelPinStoreStub(
            pinsByGateway: ["gateway-1": [legacy, stale]]
        )
        let options = ModelOptions(
            model: "shared",
            provider: "anthropic",
            providers: [
                ModelProvider(
                    slug: "anthropic",
                    name: "Anthropic",
                    authenticated: true,
                    isCurrent: true,
                    models: ["shared"]
                ),
            ]
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [
                liveSession(
                    id: "one",
                    model: "shared",
                    provider: "anthropic"
                ),
            ],
            modelOptions: options
        )
        let model = SessionListModel(
            repository: repository,
            modelPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.setModelPickerVisible(true)
        await eventually { model.modelOptions == options }

        XCTAssertEqual(
            model.resolvedPinnedModels,
            [
                ModelPin(
                    providerSlug: "anthropic",
                    modelID: "shared"
                ),
            ]
        )
        XCTAssertEqual(model.unresolvedPinnedModels, [stale])
        XCTAssertTrue(
            model.isModelPinned(provider: "anthropic", model: "shared")
        )

        model.toggleModelPin(provider: "anthropic", model: "shared")
        await eventuallyAsync {
            await pinStore.pins(gatewayID: "gateway-1") == [stale]
        }
        await eventually { model.pinnedModels == [stale] }
        let calls = await pinStore.calls
        XCTAssertTrue(
            calls.contains(
                "toggle:gateway-1:anthropic:shared"
            )
        )
    }

    func testRapidModelPinTogglesPersistAndPublishInTapOrder() async {
        let pinStore = SessionModelPinStoreStub()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            modelPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        await eventually {
            model.pinnedModelsGatewayID == "gateway-1"
        }

        let first = ModelPin(
            providerSlug: "google",
            modelID: "gemini-3-flash"
        )
        let second = ModelPin(
            providerSlug: "openai",
            modelID: "gpt-5-mini"
        )
        model.toggleModelPin(
            provider: first.providerSlug,
            model: first.modelID
        )
        model.toggleModelPin(
            provider: second.providerSlug,
            model: second.modelID
        )

        await eventually { model.pinnedModels == [first, second] }
        await eventuallyAsync {
            await pinStore.pins(gatewayID: "gateway-1") == [first, second]
        }

        model.toggleModelPin(
            provider: first.providerSlug,
            model: first.modelID
        )
        model.toggleModelPin(
            provider: first.providerSlug,
            model: first.modelID
        )

        await eventuallyAsync {
            await pinStore.calls.suffix(4) == [
                "toggle:gateway-1:google:gemini-3-flash",
                "toggle:gateway-1:openai:gpt-5-mini",
                "toggle:gateway-1:google:gemini-3-flash",
                "toggle:gateway-1:google:gemini-3-flash",
            ]
        }
        await eventually { model.pinnedModels == [first, second] }
        let persisted = await pinStore.pins(gatewayID: "gateway-1")
        XCTAssertEqual(
            persisted,
            [first, second]
        )
    }

    func testLateModelPinWriteCannotReplaceAnotherGatewayPins() async {
        let secondPin = ModelPin(
            providerSlug: "openai",
            modelID: "gateway-two-model"
        )
        let pinStore = SessionModelPinStoreStub(
            pinsByGateway: ["gateway-2": [secondPin]],
            blockToggle: true
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            modelPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.toggleModelPin(provider: "google", model: "late-model")
        await eventuallyAsync { await pinStore.isToggleWaiting }

        let gatewayLoad = Task { @MainActor in
            await model.load(
                gatewayID: "gateway-2",
                preferredSessionID: "one"
            )
        }
        await Task.yield()
        await pinStore.releaseToggle()
        await gatewayLoad.value
        await eventually {
            model.pinnedModelsGatewayID == "gateway-2"
                && model.pinnedModels == [secondPin]
        }

        XCTAssertEqual(model.pinnedModelsGatewayID, "gateway-2")
        XCTAssertEqual(model.pinnedModels, [secondPin])
    }

    func testModelPinsRemainWritableAfterSameGatewayReconnect() async {
        let pinStore = SessionModelPinStoreStub()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            modelPinStore: pinStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await repository.yield(
            .connectionLost(
                message: "connection lost",
                authRejected: false,
                retryable: true
            )
        )
        await eventually { model.state == .failed("connection lost") }
        await model.retry(
            gatewayID: "gateway-1",
            preferredSessionID: "one"
        )

        let pin = ModelPin(
            providerSlug: "openai",
            modelID: "gpt-5-mini"
        )
        model.toggleModelPin(
            provider: pin.providerSlug,
            model: pin.modelID
        )

        await eventuallyAsync {
            await pinStore.pins(gatewayID: "gateway-1") == [pin]
        }
        XCTAssertEqual(model.pinnedModels, [pin])
        XCTAssertNil(model.operationError)
    }

}
