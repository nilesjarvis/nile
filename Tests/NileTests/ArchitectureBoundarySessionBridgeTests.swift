import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testSessionListPresentationAdaptersHaveBoundedSource() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: directory, named: $0) }
        let model = try appSource("SessionListModel.swift")
        let forwarding = try appSource("SessionListModelPresentation.swift")
        let workspace = try appSource("SessionListModelWorkspacePresentation.swift")
        for marker in ["var modelOptions: ModelOptions?", "var goal: HermesGoal?", "var assistantDeltaPublicationCount: Int"] {
            XCTAssertTrue(forwarding.contains(marker)); XCTAssertFalse(model.contains(marker)); XCTAssertFalse(workspace.contains(marker))
        }
        for marker in ["var errorMessage: String?", "var transcriptScrollOwner: TranscriptScrollOwner?", "var showsComposer: Bool", "var displayedSessions: [HermesSession]", "enum SessionRuntimePresentation", "extension HermesSession"] {
            XCTAssertTrue(workspace.contains(marker)); XCTAssertFalse(model.contains(marker)); XCTAssertFalse(forwarding.contains(marker))
        }
        for source in [forwarding, workspace] {
            for forbidden in ["HermesStreamEvent", "HermesRepository", "SessionRepositoryCapabilityProviding", "SessionRuntimeComposition.production", "SessionRuntimeComposition.fixture"] { XCTAssertFalse(source.contains(forbidden)) }
        }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Presentation extraction must retain one event application boundary"
        )
        let lines = [model, forwarding, workspace].map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lines, [250, 135, 190]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(lines.reduce(0, +), 550, "Do not hide model growth behind presentation splits")
    }

    func testSessionVoiceBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let voiceSource = try appSource("SessionListModelVoice.swift")
        let talkSource = try appSource("SessionListModelTalk.swift")

        XCTAssertTrue(voiceSource.contains("extension SessionListModel"))
        XCTAssertTrue(talkSource.contains("extension SessionListModel"))
        let voiceAdapters = [
            "var composerPlaceholder: String", "func startVoiceInput()",
            "func stopVoiceInput()", "func setSpeakRepliesEnabled(",
            "func onAppForegroundChanged(", "func onSessionSurfaceHidden()",
            "func cancelVoiceForOwnershipChange()", "func speakCompletedReply(",
        ]
        let talkAdapters = [
            "var talkBlockingPrompt: TranscriptBlockingPrompt?",
            "func beginRoutingVoiceEvents()", "func startTalkMode()",
            "func pauseTalkMode()", "func resumeTalkMode()",
            "func interruptTalkSpeech()", "func endTalkMode()",
            "private func captureTalkOwner()", "private func canTalkListen(",
            "func talkEnvironmentProvider()", "func talkErrorHandler()",
            "private func applyTalkSubmission(",
            "private func applyTalkSubmissionFailure(",
        ]
        for (owner, other, adapters) in [
            (voiceSource, talkSource, voiceAdapters),
            (talkSource, voiceSource, talkAdapters),
        ] {
            for adapter in adapters {
                XCTAssertTrue(owner.contains(adapter))
                XCTAssertFalse(other.contains(adapter))
                XCTAssertFalse(modelSource.contains(adapter))
            }
        }
        for marker in ["runtimes.speechRuntime.playStandardReply(",
                       "runtimes.voiceInputRuntime.startDraft("] {
            XCTAssertTrue(voiceSource.contains(marker))
            XCTAssertFalse(talkSource.contains(marker))
        }
        for marker in ["runtimes.voiceInputRuntime.beginRouting(",
                       "runtimes.talkRuntime.consumeVoiceEvent(",
                       "SessionTalkRuntime.Submission"] {
            XCTAssertTrue(talkSource.contains(marker))
            XCTAssertFalse(voiceSource.contains(marker))
        }
        for candidate in [voiceSource, talkSource] {
            for forbidden in ["HermesStreamEvent",
                              "SessionRepositoryCapabilityProviding",
                              "SessionRuntimeComposition."] {
                XCTAssertFalse(candidate.contains(forbidden))
            }
        }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Voice split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let bridgeLines = [voiceSource, talkSource].map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(modelLines, 350)
        XCTAssertLessThan(bridgeLines[0], 145)
        XCTAssertLessThan(bridgeLines[1], 235)
        XCTAssertLessThan(bridgeLines.reduce(0, +), 365)
        XCTAssertLessThan(
            modelLines + bridgeLines.reduce(0, +),
            700,
            "Do not hide model growth behind the voice source split"
        )
    }

    func testSessionCommandBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let commandSource = try appSource("SessionListModelCommands.swift")
        let settlementSource = try appSource(
            "SessionListModelCommandSettlement.swift"
        )

        XCTAssertTrue(commandSource.contains("extension SessionListModel"))
        let commandMarkers = [
            "func applySlashCompletion(",
            "func pickCatalogCommand(",
            "func refreshSlashCompletions(",
            "func runSlashCommand(",
            "private func performNativeSlashAction(",
            "private func claimSlashDraft(",
            "runtimes.commandRuntime.startExecution(",
            "runtimes.draftLifecycleRuntime.captureClaim(",
        ]
        let settlementMarkers = [
            "struct SlashCommandSettlement: Sendable",
            "func settleSlashCommandOutcome(",
            "switch outcome",
            "func restoreCommandDraft(",
            "private func deliverCommandOutput(",
            "func updateCommandEntry(",
        ]
        for marker in commandMarkers {
            XCTAssertTrue(commandSource.contains(marker))
            XCTAssertFalse(settlementSource.contains(marker))
        }
        for marker in settlementMarkers {
            XCTAssertTrue(settlementSource.contains(marker))
            XCTAssertFalse(commandSource.contains(marker))
        }
        for marker in commandMarkers + settlementMarkers {
            XCTAssertFalse(modelSource.contains(marker))
        }
        for candidate in [commandSource, settlementSource] {
            for forbidden in ["HermesStreamEvent", "HermesEventStreaming",
                              "SessionRepositoryCapabilityProviding",
                              "SessionRuntimeComposition."] {
                XCTAssertFalse(candidate.contains(forbidden))
            }
        }
        for forbidden in ["decision(for:", "startExecution(", "captureClaim(",
                          "claimSlashDraft(", "outboundTasks"] {
            XCTAssertFalse(settlementSource.contains(forbidden))
        }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Command split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let commandLines = [commandSource, settlementSource].map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(modelLines, 425)
        XCTAssertLessThan(commandLines[0], 275)
        XCTAssertLessThan(commandLines[1], 225)
        XCTAssertLessThan(commandLines.reduce(0, +), 500)
        XCTAssertLessThan(modelLines + commandLines.reduce(0, +), 900)
    }

    func testSessionModelControlBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let controlSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelModelControl.swift"
            )
        )

        XCTAssertTrue(controlSource.contains("extension SessionListModel"))
        for adapter in [
            "var selectableModelProviders: [ModelProvider]",
            "var currentModelSupportsReasoning: Bool",
            "var canModifyModelPins: Bool",
            "var resolvedPinnedModels: Set<ModelPin>",
            "var unresolvedPinnedModels: Set<ModelPin>",
            "func isModelPinned(",
            "var resolvedCurrentModelProviderSlug: String?",
            "func setModelPickerVisible(",
            "func refreshModelOptions()",
            "func prepareCompactModelMenu()",
            "func selectModel(",
            "func setReasoningEffort(",
            "func confirmModelSwitch()",
            "func dismissModelSwitchConfirmation()",
            "var canConfirmModelSwitch: Bool",
            "func toggleModelPin(",
            "private func captureSessionControlOwner(",
            "private func applyModelControl(",
            "private func updateLiveSessionInfo(",
        ] {
            XCTAssertTrue(
                controlSource.contains(adapter),
                "Model-control bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
        }
        XCTAssertTrue(controlSource.contains("runtimes.modelControlRuntime"))
        XCTAssertFalse(controlSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            controlSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(controlSource.contains("SessionRuntimeComposition."))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Model-control split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let controlLines = controlSource.components(
            separatedBy: .newlines
        ).count
        XCTAssertLessThan(
            modelLines,
            3_850,
            "Keep model-control integration out of the core model source"
        )
        XCTAssertLessThan(
            controlLines,
            240,
            "Keep the model-facing control bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + controlLines,
            4_030,
            "Do not hide model growth behind the control source split"
        )
    }

    func testSessionGoalBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let goalSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelGoal.swift"
            )
        )

        XCTAssertTrue(goalSource.contains("extension SessionListModel"))
        for adapter in [
            "func setGoalSheetVisible(",
            "func startGoal(",
            "func pauseGoal()",
            "func resumeGoal()",
            "func continueGoal()",
            "func clearGoal()",
            "private func submitGoalPrompt(",
            "private func settleGoalPromptFailure(",
            "private func goalActionContext()",
            "func captureGoalOwner()",
            "private func isCurrentGoalOwner(",
        ] {
            XCTAssertTrue(
                goalSource.contains(adapter),
                "Standing-goal bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
        }
        XCTAssertTrue(goalSource.contains("runtimes.goalRuntime"))
        XCTAssertTrue(goalSource.contains("runtimes.turnRuntime.sendPrompt"))
        XCTAssertFalse(goalSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            goalSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(goalSource.contains("SessionRuntimeComposition."))
        let navigationSource = try sessionNavigationSource()
        XCTAssertTrue(navigationSource.contains("func syncGoalState("))
        XCTAssertFalse(modelSource.contains("func syncGoalState("))
        let eventSource = try sessionEventApplicationSource()
        let projectionSource = try source(
            in: appDirectory,
            named: "SessionListModelEventProjection.swift"
        )
        XCTAssertTrue(projectionSource.contains("func handleGoalUpdate("))
        XCTAssertTrue(projectionSource.contains("func markStandingGoalPrompts("))
        XCTAssertFalse(eventSource.contains("func handleGoalUpdate("))
        XCTAssertFalse(goalSource.contains("func syncGoalState("))
        XCTAssertFalse(goalSource.contains("func handleGoalUpdate("))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Goal bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let goalLines = goalSource.components(separatedBy: .newlines).count
        XCTAssertLessThan(
            modelLines,
            3_650,
            "Keep standing-goal integration out of the core model source"
        )
        XCTAssertLessThan(
            goalLines,
            210,
            "Keep the model-facing goal bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + goalLines,
            3_820,
            "Do not hide model growth behind the goal source split"
        )
    }

    func testSessionMediaBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let presentationSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelPresentation.swift"
            )
        )
        let mediaSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelMedia.swift"
            )
        )

        XCTAssertTrue(mediaSource.contains("extension SessionListModel"))
        for adapter in [
            "var openedAttachment: CachedAttachment?",
            "var isOpeningAttachment: Bool",
            "func openAttachment(",
            "func dismissOpenedAttachment()",
            "private func captureMediaOwner()",
            "private func isCurrentMediaOwner(",
            "private func mediaOwnerValidator()",
            "func hydrateVisibleMediaAttachments()",
            "private func applyMediaPreview(",
        ] {
            XCTAssertTrue(
                mediaSource.contains(adapter),
                "Displayed-media bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
            XCTAssertFalse(
                presentationSource.contains(adapter),
                "Keep \(adapter) out of the general presentation source"
            )
        }
        XCTAssertTrue(mediaSource.contains("runtimes.mediaRuntime"))
        XCTAssertTrue(
            try sessionTimelinePresentationSource().contains(
                "hydrateVisibleMediaAttachments()"
            )
        )
        XCTAssertFalse(mediaSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            mediaSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(mediaSource.contains("SessionRuntimeComposition."))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Media bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let presentationLines = presentationSource.components(
            separatedBy: .newlines
        ).count
        let mediaLines = mediaSource.components(separatedBy: .newlines).count
        XCTAssertLessThan(
            modelLines,
            3_560,
            "Keep displayed-media integration out of the core model source"
        )
        XCTAssertLessThan(
            presentationLines,
            335,
            "Keep feature media state out of general presentation forwarding"
        )
        XCTAssertLessThan(
            mediaLines,
            110,
            "Keep the model-facing media bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + presentationLines + mediaLines,
            3_970,
            "Do not hide model growth behind the media source split"
        )
    }

    func testSessionComposerBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let composerSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelComposer.swift"
            )
        )

        XCTAssertTrue(composerSource.contains("extension SessionListModel"))
        for adapter in [
            "var composerIsBlocked: Bool",
            "var composerCanSend: Bool",
            "func updateComposer(",
            "func sendMessage(",
            "func flushDrafts()",
            "func applyDraftClaimRetirement(",
            "func draftFailureHandler()",
            "func currentDraftOwner()",
            "func transcriptIsVisible(",
            "func composerIsVisible(",
            "func restoreComposerPresentation()",
        ] {
            XCTAssertTrue(
                composerSource.contains(adapter),
                "Composer bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
        }
        for runtime in [
            "runtimes.composerRuntime",
            "runtimes.draftLifecycleRuntime",
            "runtimes.attachmentRecoveryRuntime",
        ] {
            XCTAssertTrue(composerSource.contains(runtime))
        }
        XCTAssertFalse(composerSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            composerSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(composerSource.contains("SessionRuntimeComposition."))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Composer bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let composerLines = composerSource.components(
            separatedBy: .newlines
        ).count
        XCTAssertLessThan(
            modelLines,
            2_100,
            "Keep composer integration out of the core model source"
        )
        XCTAssertLessThan(
            composerLines,
            270,
            "Keep the model-facing composer bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + composerLines,
            2_350,
            "Do not hide model growth behind the composer source split"
        )
    }

    func testSessionTurnBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let composerSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelComposer.swift"
            )
        )
        let turnSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelTurn.swift"
            )
        )
        let settlementSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelTurnSettlement.swift"
            )
        )

        XCTAssertTrue(turnSource.contains("extension SessionListModel"))
        XCTAssertTrue(settlementSource.contains("extension SessionListModel"))
        let admissionAdapters = [
            "func stopActiveRun()",
            "func submitPrompt(",
            "func queueSteer(",
            "func beginBackgroundTurn(",
            "func stopBackgroundTurn(",
        ]
        let settlementAdapters = [
            "func settlePromptFailure(",
            "func settleSteerFailure(",
            "func settleStop(",
            "func settleSuccessfulStop(",
        ]
        for adapter in admissionAdapters {
            XCTAssertTrue(
                turnSource.contains(adapter),
                "Turn admission must own \(adapter)"
            )
            XCTAssertFalse(settlementSource.contains(adapter))
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
        }
        for adapter in settlementAdapters {
            XCTAssertTrue(
                settlementSource.contains(adapter),
                "Turn settlement must own \(adapter)"
            )
            XCTAssertFalse(turnSource.contains(adapter))
            XCTAssertFalse(modelSource.contains(adapter))
        }
        for marker in [
            "runtimes.turnRuntime.stop(",
            "runtimes.turnRuntime.sendPrompt(",
            "runtimes.turnRuntime.sendSteer(",
        ] {
            XCTAssertTrue(turnSource.contains(marker))
            XCTAssertFalse(settlementSource.contains(marker))
        }
        for marker in [
            "runtimes.draftLifecycleRuntime.recover(",
            "runtimes.talkRuntime.handleStopSucceeded(",
            "runtimes.blockingPromptRuntime.finalizeRuntime(",
        ] {
            XCTAssertTrue(settlementSource.contains(marker))
            XCTAssertFalse(turnSource.contains(marker))
        }
        XCTAssertTrue(composerSource.contains("submitPrompt("))
        XCTAssertTrue(composerSource.contains("queueSteer("))
        for candidate in [turnSource, settlementSource] {
            XCTAssertFalse(candidate.contains("HermesStreamEvent"))
            XCTAssertFalse(
                candidate.contains("SessionRepositoryCapabilityProviding")
            )
            XCTAssertFalse(candidate.contains("SessionRuntimeComposition."))
        }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Turn bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let composerLines = composerSource.components(
            separatedBy: .newlines
        ).count
        let turnLines = [turnSource, settlementSource].map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(modelLines, 350)
        XCTAssertLessThan(composerLines, 260)
        XCTAssertLessThan(turnLines[0], 235)
        XCTAssertLessThan(turnLines[1], 150)
        XCTAssertLessThan(
            turnLines.reduce(0, +),
            365,
            "Do not hide turn growth behind the admission/settlement split"
        )
        XCTAssertLessThan(
            modelLines + composerLines + turnLines.reduce(0, +),
            975,
            "Do not hide model growth behind the composer/turn source split"
        )
    }

    func testSessionCreationBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let creationSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelCreation.swift"
            )
        )

        XCTAssertTrue(creationSource.contains("extension SessionListModel"))
        for adapter in [
            "var canCreateSession: Bool",
            "var hasDraftWithoutOpenSession: Bool",
            "func createSession() async",
            "private func createFixtureSession()",
        ] {
            XCTAssertTrue(
                creationSource.contains(adapter),
                "Session-creation bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
        }
        for runtime in [
            "runtimes.navigationRuntime",
            "runtimes.creationDraftRuntime",
            "runtimes.draftLifecycleRuntime",
            "runtimes.renameRuntime",
            "runtimes.goalRuntime",
        ] {
            XCTAssertTrue(creationSource.contains(runtime))
        }
        XCTAssertTrue(
            creationSource.contains("recordListedSessionOwnership(")
        )
        XCTAssertTrue(
            creationSource.contains("applyLiveSessionTranscript(")
        )
        XCTAssertTrue(
            creationSource.contains("overlaySelectedLiveSession(")
        )
        XCTAssertTrue(creationSource.contains("syncGoalState("))
        XCTAssertFalse(modelSource.contains("private var ownership"))
        XCTAssertFalse(modelSource.contains("recordListedSessionOwnership("))
        XCTAssertFalse(creationSource.contains("ownership."))
        XCTAssertFalse(creationSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            creationSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(creationSource.contains("SessionRuntimeComposition."))
        XCTAssertFalse(creationSource.contains("for await"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Creation bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let creationLines = creationSource.components(
            separatedBy: .newlines
        ).count
        XCTAssertLessThan(
            modelLines,
            1_860,
            "Keep session-creation integration out of the core model source"
        )
        XCTAssertLessThan(
            creationLines,
            270,
            "Keep the model-facing creation bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + creationLines,
            2_120,
            "Do not hide model growth behind the creation source split"
        )
    }

    func testSessionLifecycleRuntimeOwnsAppAndBackgroundTurnState() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: directory, named: $0) }
        let model = try appSource("SessionListModel.swift")
        let bridge = try appSource("SessionListModelLifecycle.swift")
        let composition = try appSource("SessionRuntimeComposition.swift")
        let runtime = try appSource("SessionLifecycleRuntime.swift")
        let adapters = ["func installConnectionLossHandler(", "func installBackgroundTurnStartedHandler(", "func stopBackgroundTurnsOutsideGateway(", "func hasBackgroundTurnsOutsideGateway(", "func setConnectionRecoveryPhase("]
        for marker in adapters { XCTAssertTrue(bridge.contains(marker)); XCTAssertFalse(model.contains(marker)) }
        for forbidden in ["HermesStreamEvent", "HermesRepository", "Task<", "SessionRuntimeComposition.production", "SessionRuntimeComposition.fixture"] { XCTAssertFalse(bridge.contains(forbidden)) }
        for forbidden in ["private var appIsForeground", "private var appHasEnteredBackground", "private var connectionLossHandler", "private var backgroundTurnStartedHandler", "runtimes.backgroundTurns", "BackgroundTurnTarget(", "enum SessionConnectionPhase", "struct GatewayConnectionLossNotice"] { XCTAssertFalse(model.contains(forbidden)) }
        for marker in ["let lifecycleRuntime: SessionLifecycleRuntime", "SessionLifecycleRuntime("] { XCTAssertTrue(composition.contains(marker)) }
        XCTAssertFalse(composition.contains("let backgroundTurns: BackgroundTurnCoordinator"))
        for marker in ["final class SessionLifecycleRuntime", "enum SessionConnectionPhase", "struct GatewayConnectionLossNotice", "private let backgroundTurns: BackgroundTurnCoordinator", "private var hasEnteredBackground", "private var connectionLossHandler", "private var backgroundTurnStartedHandler", "func setForeground(", "func startTurn(", "func notifyConnectionLoss(", "func reconcileStatuses("] { XCTAssertTrue(runtime.contains(marker)) }
        XCTAssertFalse(runtime.contains("HermesStreamEvent")); XCTAssertFalse(runtime.contains("HermesRepository"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Lifecycle extraction must retain one event application boundary"
        )
        let lines = [model, bridge, runtime].map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lines, [250, 50, 170]).allSatisfy { $0.0 < $0.1 })
    }

    func testSessionEventRuntimeOwnsTheOnlyHermesStreamAndDeltaCadence() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let names = [
            "SessionListModel.swift",
            "SessionListModelEvents.swift",
            "SessionListModelEventSettlement.swift",
            "SessionListModelVisibleEventProjection.swift", "SessionListModelConnectionLossProjection.swift",
            "SessionListModelEventProjection.swift",
            "SessionEventRuntime.swift",
            "LiveTranscriptCoordinator.swift",
            "LiveTranscriptToolProjection.swift",
            "TranscriptImagePayloadCache.swift",
            "SessionListModelBlockingPrompt.swift",
        ]
        let sources = try names.map { try source(in: appDirectory, named: $0) }
        let modelSource = sources[0]
        let applicationSource = sources[1]
        let settlementSource = sources[2]
        let visibleSource = sources[3]; let connectionLossSource = sources[4]
        let projectionSource = sources[5]
        let runtimeSource = sources[6]
        let transcriptSource = sources[7]
        let toolSource = sources[8]
        let cacheSource = sources[9]
        let blockingSource = sources[10]
        let eventSources = [applicationSource, settlementSource, visibleSource, connectionLossSource, projectionSource]
        let timelineSource = try sessionTimelinePresentationSource()
        let gatewaySource = try sessionGatewaySource()
        let navigationSource = try sessionNavigationSource()

        XCTAssertTrue(modelSource.contains("let runtimes: SessionRuntimeComposition"))
        for forbidden in ["HermesEventStreaming", "repository.events", "private var eventTask",
                          "private var assistantDeltaFlushTask", "private var assistantDeltaCoalescer", "HermesStreamEvent"] {
            XCTAssertFalse(modelSource.contains(forbidden))
        }
        for marker in ["extension SessionListModel", "runtimes.eventRuntime.beginRouting(",
                       "private func consume(_ event: HermesStreamEvent)"] {
            XCTAssertTrue(applicationSource.contains(marker))
        }
        let orderedStages = [
            "applyDelegationLifecycle(event)", "settleTurnLifecycle(event)",
            "consumeBlockingPromptEvent(event)", "settleTerminalResources(event)",
            "applyVisibleEvent(event)",
        ]
        let stageOffsets = orderedStages.compactMap { applicationSource.range(of: $0)?.lowerBound }
        XCTAssertEqual(stageOffsets.count, orderedStages.count)
        for pair in zip(stageOffsets, stageOffsets.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
        for marker in [
            "func applyDelegationLifecycle(", "func settleTurnLifecycle(",
            "func consumeBlockingPromptEvent(", "func settleTerminalResources(",
            "private func settleRejectedAttachmentBatches(",
        ] {
            XCTAssertTrue(settlementSource.contains(marker))
            XCTAssertFalse(applicationSource.contains(marker))
        }
        for marker in [
            "func applyVisibleEvent(", "private func applyVisibleAssistantCompletion(",
            "private func applyVisibleError(",
            "private func settleAcceptedAttachmentBatches(",
        ] {
            XCTAssertTrue(visibleSource.contains(marker))
        }
        XCTAssertTrue(connectionLossSource.contains("func applyVisibleConnectionLoss(")); XCTAssertFalse(visibleSource.contains("func applyVisibleConnectionLoss("))
        for marker in ["cacheVisibleLiveTimeline()", "quarantineTrackedAttachmentBatches()", "markSubmittingUncertain(", "finalizeGateway(", "notifyConnectionLoss("] { XCTAssertTrue(connectionLossSource.contains(marker)); XCTAssertEqual(eventSources.filter { $0.contains(marker) }.count, 1) }
        for marker in [
            "func handleGoalUpdate(",
            "func applyAssistantDelta(",
            "func consumeCachedLiveEvent(",
            "func refreshCompletedAttachedTurn(",
            "func applyToolEvent(",
        ] {
            XCTAssertTrue(projectionSource.contains(marker))
            XCTAssertFalse(applicationSource.contains(marker))
        }
        XCTAssertTrue(blockingSource.contains("func syncBlockingPromptUI()")); XCTAssertTrue(blockingSource.contains("runtimes.blockingPromptRuntime.project(")); XCTAssertFalse(eventSources.contains { $0.contains("func syncBlockingPromptUI()") })
        for source in eventSources {
            if source != applicationSource {
                XCTAssertFalse(source.contains("beginRoutingEventsIfNeeded"))
                XCTAssertFalse(source.contains("private func consume("))
            }
            XCTAssertFalse(source.contains("HermesEventStreaming"))
            XCTAssertFalse(source.contains("repository.events"))
            XCTAssertFalse(source.contains("SessionRepositoryCapabilityProviding"))
            XCTAssertFalse(source.contains("SessionRuntimeComposition."))
        }
        XCTAssertEqual(
            eventSources.map {
                $0.components(
                    separatedBy: "private func consume(_ event: HermesStreamEvent)"
                ).count - 1
            }.reduce(0, +),
            1,
            "The model must retain one ordered event-application boundary"
        )
        let eventLineCounts = eventSources.map {
            $0.components(separatedBy: .newlines).count
        }
        for (count, cap) in zip(eventLineCounts, [60, 140, 250, 85, 115]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(eventLineCounts.reduce(0, +), 610)
        let modelLines = modelSource.components(separatedBy: .newlines).count
        XCTAssertLessThan(modelLines, 1_110)
        XCTAssertLessThan(
            modelLines + eventLineCounts.reduce(0, +)
                + timelineSource.components(separatedBy: .newlines).count
                + gatewaySource.components(separatedBy: .newlines).count
                + navigationSource.components(separatedBy: .newlines).count,
            2_050,
            "Do not hide model growth behind orchestration source splits"
        )

        for marker in [
            "final class SessionEventRuntime",
            "private let repository: (any HermesEventStreaming)?",
            "for await event in repository.events",
            "private var eventTask",
            "private var assistantDeltaFlushTask",
            "AssistantDeltaEventCoalescer",
            "private func route(_ event:",
            "func flushPendingAssistantDelta()",
        ] {
            XCTAssertTrue(runtimeSource.contains(marker))
        }
        XCTAssertLessThan(runtimeSource.components(separatedBy: .newlines).count, 200)
        XCTAssertFalse(transcriptSource.contains("AssistantDeltaEventCoalescer"))
        for marker in ["private let toolProjector: LiveTranscriptToolProjector", "toolProjector.startsNewTool(", "toolProjector.upsert("] { XCTAssertTrue(transcriptSource.contains(marker)) }
        for marker in ["struct LiveToolEvent: Equatable, Sendable", "struct LiveTranscriptProjection: Equatable, Sendable", "struct LiveTranscriptToolProjector", "func startsNewTool(", "func upsert(", "private func toolID(for event:", "toolKind(event.name)", "defaultToolLabel(event.name)", "startedAtMilliseconds:"] { XCTAssertTrue(toolSource.contains(marker)); XCTAssertFalse(transcriptSource.contains(marker)) }
        for forbidden in ["LiveTranscriptCoordinator", "activeAssistantID", "parseMessageContent", "TranscriptImagePayloadCache", "Task<", "Hermes"] { XCTAssertFalse(toolSource.contains(forbidden)) }
        for marker in ["private var imageCache: TranscriptImagePayloadCache", "func rememberImage(path:", "func cachedImages()", "func clearCachedImages()"] {
            XCTAssertTrue(transcriptSource.contains(marker))
        }
        for marker in ["struct TranscriptImagePayloadCache: Sendable", "private var imagesByPath", "private var pathsByRecency", "private var base64CharacterCount", "mutating func remember(path:", "private mutating func evictOldestImagesIfNeeded()"] {
            XCTAssertTrue(cacheSource.contains(marker)); XCTAssertFalse(transcriptSource.contains(marker))
        }
        for forbidden in ["TranscriptEntry", "LiveToolEvent", "import Foundation", "Task<", "Hermes"] { XCTAssertFalse(cacheSource.contains(forbidden)) }
        let transcriptLineCounts = [transcriptSource, toolSource, cacheSource].map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(transcriptLineCounts, [290, 110, 65]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(transcriptLineCounts.reduce(0, +), 435, "Do not hide live transcript projection growth behind collaborator splits")
    }

}
