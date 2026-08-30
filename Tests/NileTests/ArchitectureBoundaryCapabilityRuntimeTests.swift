import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testSessionGoalRuntimeSeparatesMutationStatusPolicyAndContracts() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let domainDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/Domain", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(at: appDirectory.appendingPathComponent($0))
        }
        let modelSource = try appSource("SessionListModel.swift")
        let runtimeSource = try appSource("SessionGoalRuntime.swift")
        let mutationSource = try appSource("SessionGoalMutations.swift")
        let mutationLifecycleSource = try appSource("SessionGoalMutationLifecycle.swift")
        let contractsSource = try appSource("SessionGoalContracts.swift")
        let policySource = try appSource("GoalRuntimePolicy.swift")
        let statusSource = try appSource("GoalStatusRuntime.swift")
        let repositoryContractsSource = try source(
            at: domainDirectory.appendingPathComponent("GoalModels.swift")
        )

        for forbidden in ["goalTask", "goalGeneration", "GoalOwner",
                          "repository.goalStatus", "repository.setGoal"] {
            XCTAssertFalse(modelSource.contains(forbidden))
        }
        for required in ["final class SessionGoalRuntime", "any HermesGoalServing",
                         "let status: GoalStatusRuntime", "let mutationLifecycle",
                         "func synchronize(owner:", "func handleProgressUpdate(",
                         "private func refreshAfterCompletion("] {
            XCTAssertTrue(runtimeSource.contains(required))
        }
        for forbidden in ["func start(", "repository.setGoal",
                          "repository.pauseGoal", "repository.resumeGoal",
                          "repository.clearGoal", "private func beginMutation(",
                          "MutationToken", "isCurrentMutation(", "Task<",
                          "HermesStreamEvent"] {
            XCTAssertFalse(runtimeSource.contains(forbidden))
        }
        for required in ["extension SessionGoalRuntime", "func start(",
                         "func pause(", "func resume(", "func clear(",
                         "repository.setGoal", "repository.pauseGoal",
                         "repository.resumeGoal", "repository.clearGoal",
                         "beginMutation(owner:"] {
            XCTAssertTrue(mutationSource.contains(required))
        }
        for forbidden in ["@Observable", "final class SessionGoalRuntime",
                          "func synchronize(owner:", "struct Token:",
                          "private var task:", "HermesStreamEvent"] {
            XCTAssertFalse(mutationSource.contains(forbidden))
        }
        for required in ["final class SessionGoalMutationLifecycle", "struct Token: Equatable, Sendable", "private var task: Task<Void, Never>?", "private var generation: Int64", "func start(", "func reset()", "extension SessionGoalRuntime", "func beginMutation(", "func settleMutation(", "func finishMutation(", "func settleMutationFailure(", "func isCurrentMutation("] {
            XCTAssertTrue(mutationLifecycleSource.contains(required))
        }
        for forbidden in ["@Observable", "final class SessionGoalRuntime", "repository.setGoal", "repository.pauseGoal", "repository.resumeGoal", "repository.clearGoal", "HermesStreamEvent"] {
            XCTAssertFalse(mutationLifecycleSource.contains(forbidden))
        }
        for marker in ["private var task: Task<Void, Never>?", "private var generation: Int64", "struct Token:"] {
            XCTAssertEqual([runtimeSource, mutationSource, mutationLifecycleSource].filter { $0.contains(marker) }.count, 1)
        }
        for required in ["final class GoalStatusRuntime",
                         "any HermesGoalStatusServing", "private var task",
                         "private var generation", "repository.goalStatus"] {
            XCTAssertTrue(statusSource.contains(required))
        }
        for forbidden in ["repository.setGoal", "repository.pauseGoal",
                          "HermesStreamEvent"] {
            XCTAssertFalse(statusSource.contains(forbidden))
        }
        for required in ["enum GoalRuntimePolicy", "static func startAdmission(",
                         "static func progress(", "static func reconcileStatus("] {
            XCTAssertTrue(policySource.contains(required))
        }
        for forbidden in ["Task<", "HermesGoalServing", "HermesStreamEvent"] {
            XCTAssertFalse(policySource.contains(forbidden))
        }

        for contract in [
            "enum GoalAvailability: Equatable, Sendable",
            "struct GoalRuntimeOwner: Equatable, Sendable",
            "struct GoalActionContext: Sendable",
            "struct GoalSynchronization: Sendable",
            "extension SessionGoalRuntime",
        ] {
            XCTAssertTrue(contractsSource.contains(contract))
            XCTAssertFalse(runtimeSource.contains(contract))
        }

        for contract in ["protocol HermesGoalStatusServing: Sendable",
                         "protocol HermesGoalServing: HermesGoalStatusServing"] {
            XCTAssertTrue(repositoryContractsSource.contains(contract))
        }

        let lineCounts = [
            runtimeSource,
            mutationSource,
            mutationLifecycleSource,
            contractsSource,
            policySource,
            statusSource,
        ].map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(lineCounts, [290, 260, 140, 55, 280, 125]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_070,
            "Do not hide goal-runtime growth behind policy/status helpers"
        )
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Goal extraction must not introduce another stream-event router"
        )
    }

    func testSessionUsageRuntimeOwnsItsAsyncLifecycleWithoutEventRouting() throws {
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
        let usageSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionListModelUsage.swift"
            )
        )
        let runtimeSource = try source(in: appDirectory, named: "SessionUsageRuntime.swift")
        let statsRuntimeSource = try source(in: appDirectory, named: "GatewayStatsRuntime.swift")
        let contextSource = try source(at: appDirectory.appendingPathComponent("SessionListModelGatewayContext.swift"))

        XCTAssertTrue(usageSource.contains("extension SessionListModel"))
        for adapter in [
            "static var statsPeriodOptions: [Int]",
            "var usage: SessionUsage?",
            "var isContextSheetVisible: Bool",
            "var isStatsSheetVisible: Bool",
            "var statsPeriodDays: Int",
            "var gatewayStats: GatewayStats?",
            "var heatmapDailyStats: [DailyGatewayStats]?",
            "var statsReferenceDate: Date?",
            "var isLoadingStats: Bool",
            "var isLoadingHeatmap: Bool",
            "var statsError: String?",
            "func setContextSheetVisible(",
            "func setStatsSheetVisible(",
            "func selectStatsPeriod(",
            "func refreshStats()",
            "func refreshUsage()",
            "private func captureUsageOwner()",
            "private func captureGatewayStatsOwner()",
            "func resetSessionUsage()",
            "func resetGatewayStats()",
        ] {
            XCTAssertTrue(
                usageSource.contains(adapter),
                "Usage bridge must own \(adapter)"
            )
            XCTAssertFalse(
                modelSource.contains(adapter),
                "Keep \(adapter) out of the core model source"
            )
            XCTAssertFalse(
                presentationSource.contains(adapter),
                "Keep \(adapter) out of general presentation forwarding"
            )
        }
        XCTAssertTrue(["runtimes.usageRuntime", "runtimes.gatewayStatsRuntime"].allSatisfy(usageSource.contains))
        let gatewaySource = try sessionGatewaySource()
        let navigationSource = try sessionNavigationSource()
        XCTAssertTrue(contextSource.contains("refreshUsage()"))
        XCTAssertTrue(navigationSource.contains("refreshUsage()"))
        XCTAssertTrue(navigationSource.contains("resetSessionUsage()"))
        XCTAssertTrue(gatewaySource.contains("resetSessionUsage()"))
        XCTAssertTrue(gatewaySource.contains("resetGatewayStats()"))
        XCTAssertFalse(usageSource.contains("loadedGatewayID"))
        XCTAssertFalse(usageSource.contains("HermesStreamEvent"))
        XCTAssertFalse(
            usageSource.contains("SessionRepositoryCapabilityProviding")
        )
        XCTAssertFalse(usageSource.contains("SessionRuntimeComposition."))
        for marker in ["private var usageTask", "private var statsTask"] { XCTAssertFalse(modelSource.contains(marker)) }
        for marker in ["final class SessionUsageRuntime", "private var usageTask", "repository.sessionUsage"] { XCTAssertTrue(runtimeSource.contains(marker)) }
        for marker in ["private var statsTask", "gatewayStats(", "GatewayOwner", "statsPeriodOptions", "HermesStreamEvent"] { XCTAssertFalse(runtimeSource.contains(marker)) }
        for marker in ["final class GatewayStatsRuntime", "private var task", "func setSheetVisible", "func selectPeriod", "repository.gatewayStats"] { XCTAssertTrue(statsRuntimeSource.contains(marker)) }
        for marker in ["sessionUsage(", "usagePollInterval", "SessionOwner", "HermesStreamEvent"] { XCTAssertFalse(statsRuntimeSource.contains(marker)) }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "SessionListModel must retain one ordered application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let presentationLines = presentationSource.components(
            separatedBy: .newlines
        ).count
        let usageLines = usageSource.components(separatedBy: .newlines).count
        let telemetryLines = [runtimeSource, statsRuntimeSource].map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(telemetryLines, [145, 215]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(telemetryLines.reduce(0, +), 350)
        XCTAssertLessThan(
            modelLines,
            3_310,
            "Keep usage and statistics integration out of the core model"
        )
        XCTAssertLessThan(
            presentationLines,
            265,
            "Keep telemetry state out of general presentation forwarding"
        )
        XCTAssertLessThan(
            usageLines,
            145,
            "Keep the model-facing usage bridge independently reviewable"
        )
        XCTAssertLessThan(
            modelLines + presentationLines + usageLines,
            3_700,
            "Do not hide model growth behind the usage source split"
        )
    }

    func testSlashCommandPolicySeparatesDispatchSafetyFromCatalogDiscovery() throws {
        let directory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Domain", isDirectory: true
        )
        let dispatch = try source(in: directory, named: "NileSlashPolicy.swift")
        let catalog = try source(in: directory, named: "NileSlashCatalogPolicy.swift")
        let runtime = try source(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Nile/App/SessionCommandRuntime.swift"
            )
        )
        for marker in ["enum NileSlashSurface", "struct NileSlashDecision", "enum NileSlashPolicy", "static func decide(", "knownHermesNames", "func isReservedNativeName("] {
            XCTAssertTrue(dispatch.contains(marker)); XCTAssertFalse(catalog.contains(marker))
        }
        for marker in ["struct CuratedNileCommandCatalog", "enum NileSlashCatalogPolicy", "static func curateCatalog(", "static func filterCompletions(", "discoveryHiddenNames", "curatedDescriptions"] {
            XCTAssertTrue(catalog.contains(marker)); XCTAssertFalse(dispatch.contains(marker))
        }
        for forbidden in ["HermesCommandServing", "HermesStreamEvent", "Task<", "executeCommand("] {
            XCTAssertFalse(dispatch.contains(forbidden)); XCTAssertFalse(catalog.contains(forbidden))
        }
        XCTAssertTrue(runtime.contains("NileSlashCatalogPolicy.curateCatalog"))
        XCTAssertTrue(runtime.contains("NileSlashCatalogPolicy.filterCompletions"))
        XCTAssertTrue(runtime.contains("NileSlashPolicy.decide"))
        let lines = [dispatch, catalog].map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lines, [300, 155]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(lines.reduce(0, +), 440)
    }

    func testSessionSpeechRuntimeOwnsCapabilityAndPlaybackLifecycle() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionSpeechRuntime.swift"
            )
        )

        XCTAssertTrue(
            try sessionNavigationSource().contains("runtimes.speechRuntime")
        )
        XCTAssertFalse(modelSource.contains("private let speechOutput"))
        XCTAssertFalse(modelSource.contains("spokenReplyTask"))
        XCTAssertFalse(modelSource.contains("spokenReplyGeneration"))
        XCTAssertFalse(modelSource.contains("repository.synthesizeSpeech"))
        XCTAssertFalse(modelSource.contains("chunkTextForSpeech"))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            7_600,
            "Keep speech capability tasks out of the app model"
        )
        XCTAssertTrue(
            runtimeSource.contains("final class SessionSpeechRuntime")
        )
        XCTAssertTrue(
            runtimeSource.contains("any HermesSpeechSynthesisServing")
        )
        XCTAssertFalse(runtimeSource.contains("HermesTranscriptionServing"))
        XCTAssertTrue(runtimeSource.contains("private let output"))
        XCTAssertTrue(runtimeSource.contains("private var playbackTask"))
        XCTAssertTrue(runtimeSource.contains("private var playbackGeneration"))
        XCTAssertTrue(runtimeSource.contains("func playStandardReply"))
        XCTAssertTrue(runtimeSource.contains("func playTalkReply"))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Speech extraction must retain one model application boundary"
        )
    }

    func testSessionVoiceInputRuntimeOwnsCapabilityAndEventLifecycle() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionVoiceInputRuntime.swift"
            )
        )
        let talkSource = try source(
            at: appDirectory.appendingPathComponent("SessionTalkRuntime.swift")
        )

        XCTAssertTrue(modelSource.contains("runtimes.voiceInputRuntime"))
        XCTAssertFalse(modelSource.contains("private let voice:"))
        XCTAssertFalse(modelSource.contains("voiceEventTask"))
        XCTAssertFalse(modelSource.contains("draftIsListening"))
        XCTAssertFalse(modelSource.contains("draftIsTranscribing"))
        XCTAssertFalse(modelSource.contains("repository.transcribeSpeech"))
        XCTAssertFalse(modelSource.contains("HermesEventStreaming"))
        XCTAssertFalse(modelSource.contains("repository.events"))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            6_450,
            "Keep voice-input capability and task state out of the app model"
        )

        XCTAssertTrue(
            runtimeSource.contains("final class SessionVoiceInputRuntime")
        )
        XCTAssertTrue(
            runtimeSource.contains("any HermesTranscriptionServing")
        )
        XCTAssertFalse(
            runtimeSource.contains("HermesSpeechSynthesisServing")
        )
        XCTAssertTrue(runtimeSource.contains("private let coordinator"))
        XCTAssertTrue(runtimeSource.contains("private var eventTask"))
        XCTAssertTrue(runtimeSource.contains("func beginRouting"))
        XCTAssertTrue(runtimeSource.contains("isDraftListening"))
        XCTAssertTrue(runtimeSource.contains("isDraftTranscribing"))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertTrue(
            talkSource.contains("let voice: SessionVoiceInputRuntime")
        )
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Voice extraction must retain one ordered Hermes event router"
        )
    }

    func testSessionTalkRuntimeOwnsTalkTasksTokensAndCapability() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let names = ["SessionTalkRuntime.swift", "SessionTalkResponseLifecycle.swift", "SessionTalkRelistenLifecycle.swift", "SessionTalkContracts.swift", "TalkSubmissionRuntime.swift", "TalkSubmissionPolicy.swift"]
        let sources = try names.map { try source(in: appDirectory, named: $0) }
        let runtimeSource = sources[0]
        let responseSource = sources[1]
        let relistenSource = sources[2]
        let contractsSource = sources[3]
        let submissionSource = sources[4]
        let policySource = sources[5]
        let modelSource = try source(in: appDirectory, named: "SessionListModel.swift")
        let applicationSource = try sessionEventApplicationSource()
        let coordinatorSources = try ["TalkModeCoordinator.swift", "TalkModeContracts.swift"].map { try source(in: appDirectory, named: $0) }
        for marker in ["enum TalkPhase", "struct TalkUIState", "struct TalkOwner", "final class TalkModeToken", "final class TalkTurnToken", "final class TalkRelistenToken", "enum TalkRecognitionDecision", "enum TalkRelistenDecision"] { XCTAssertEqual(coordinatorSources.filter { $0.contains(marker) }.count, 1); XCTAssertTrue(coordinatorSources[1].contains(marker)) }
        for marker in ["@MainActor", "final class TalkModeCoordinator", "private var generation", "private var activeMode", "private var activeTurn", "private var pendingRelisten", "func finishRecognition(", "func claimRelisten("] { XCTAssertTrue(coordinatorSources[0].contains(marker)); XCTAssertFalse(coordinatorSources[1].contains(marker)) }
        for forbidden in ["Task<", "HermesTalkServing", "SessionTalkRuntime"] { XCTAssertFalse(coordinatorSources[1].contains(forbidden)) }
        for (source, limit) in zip(coordinatorSources, [325, 110]) { XCTAssertLessThan(source.components(separatedBy: .newlines).count, limit) }
        XCTAssertLessThan(coordinatorSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 420)

        XCTAssertTrue(applicationSource.contains("runtimes.talkRuntime"))
        for forbidden in ["private var talkMode", "acknowledgedTalkTurn", "unacknowledgedTalkTurn", "uncorrelatedTalkTerminal", "talkResumeAfterStop", "talkRelistenTask", "private func submitTalkTurn", "private func scheduleTalkRelisten"] {
            XCTAssertFalse(modelSource.contains(forbidden))
        }
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            7_200,
            "Keep Talk orchestration and request races out of the app model"
        )
        for marker in ["final class SessionTalkRuntime", "any HermesTalkServing", "let relisten: SessionTalkRelistenRuntime", "let submission: TalkSubmissionRuntime", "var resumeAfterStop", "func consumeVoiceEvent("] {
            XCTAssertTrue(runtimeSource.contains(marker))
        }
        for marker in ["extension SessionTalkRuntime", "func handleAssistantCompleted(", "func handleError(", "func handleStopSucceeded(", "speech.playTalkReply("] {
            XCTAssertTrue(responseSource.contains(marker))
        }
        for marker in ["final class SessionTalkRelistenRuntime", "private var task: Task<Void, Never>?", "private var generation: Int64", "func replace(", "func scheduleRelisten(", "func pauseAndScheduleResume(", "func cancelRelisten("] { XCTAssertTrue(relistenSource.contains(marker)) }
        XCTAssertFalse(runtimeSource.contains("func handleAssistantCompleted("))
        XCTAssertFalse(runtimeSource.contains("relistenTask") || responseSource.contains("func scheduleRelisten("))
        XCTAssertFalse(responseSource.contains("final class SessionTalkRuntime"))
        for forbidden in ["private var submissionTask", "private var acknowledgedTurn", "repository?.submitPrompt", "repository?.liveRuntimeStatus", "HermesStreamEvent"] {
            XCTAssertFalse(runtimeSource.contains(forbidden))
            XCTAssertFalse(responseSource.contains(forbidden))
            XCTAssertFalse(relistenSource.contains(forbidden))
        }

        for marker in ["final class TalkSubmissionRuntime", "any HermesTalkServing", "private var task", "private var generation", "private var acknowledgedTurn", "private var unacknowledgedTurn", "private var uncorrelatedTerminal", "repository?.submitPrompt", "repository?.liveRuntimeStatus"] {
            XCTAssertTrue(submissionSource.contains(marker))
        }
        for forbidden in ["TalkModeCoordinator", "SessionSpeechRuntime", "SessionVoiceInputRuntime", "HermesStreamEvent"] {
            XCTAssertFalse(submissionSource.contains(forbidden))
        }

        for marker in ["enum TalkSubmissionPolicy", "static func canSubmit(", "static func settlement(", "static func failure("] {
            XCTAssertTrue(policySource.contains(marker))
        }
        XCTAssertFalse(policySource.contains("Task<"))
        XCTAssertFalse(policySource.contains("HermesStreamEvent"))

        for contract in [
            "struct TalkRuntimeEnvironment: Equatable, Sendable",
            "struct TalkSubmission: Equatable, Sendable",
            "struct TalkSubmissionFailure: Equatable, Sendable",
            "typealias TalkEnvironmentProvider",
            "extension SessionTalkRuntime",
        ] {
            XCTAssertTrue(contractsSource.contains(contract))
            XCTAssertFalse(runtimeSource.contains(contract))
        }
        XCTAssertTrue(contractsSource.contains("extension SessionTalkRuntime"))

        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        for (lineCount, limit) in zip(lineCounts, [290, 240, 140, 50, 220, 100]) {
            XCTAssertLessThan(lineCount, limit)
        }
        XCTAssertLessThan(lineCounts.reduce(0, +), 950, "Do not hide Talk orchestration growth behind lifecycle helpers")
        XCTAssertEqual(
            applicationSource.components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Talk extraction must retain one model application boundary"
        )
    }

    func testSessionClaimAndRenameRuntimesOwnIndependentLifecycles() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let names = [
            "SessionListModel.swift", "SessionListModelPresentation.swift",
            "SessionListModelClaim.swift", "SessionListModelRename.swift",
            "SessionListModelGatewayContext.swift", "SessionClaimRuntime.swift",
            "SessionRenameRuntime.swift",
        ]
        let sources = try names.map { try source(in: directory, named: $0) }
        let model = sources[0], presentation = sources[1]
        let claimBridge = sources[2], renameBridge = sources[3]
        let context = sources[4], claim = sources[5], rename = sources[6]
        let claimAdapters = [
            "var isClaimDialogVisible: Bool", "var isClaimingSession: Bool",
            "func setClaimDialogVisible(", "func claimCurrentSession() async",
            "private func captureClaimOwner(", "private func isCurrentClaimOwner(",
            "private func claimOwnerValidator()",
        ]
        let renameAdapters = [
            "var isRenameDialogVisible: Bool", "var isRenamingSession: Bool",
            "var renameSessionError: String?", "var canShowRenameSession: Bool",
            "func setRenameDialogVisible(", "func renameCurrentSession(",
            "private func applyRenamedSession(",
            "private func captureRenameOwner()", "private func isCurrentRenameOwner(",
            "private func renameOwnerValidator()",
        ]

        func assertAdapters(
            _ adapters: [String], ownedBy owner: String,
            excludedFrom excludedSources: [String]
        ) {
            for adapter in adapters {
                XCTAssertTrue(owner.contains(adapter))
                excludedSources.forEach { XCTAssertFalse($0.contains(adapter)) }
            }
        }
        assertAdapters(claimAdapters, ownedBy: claimBridge, excludedFrom: [model, presentation, renameBridge])
        assertAdapters(renameAdapters, ownedBy: renameBridge, excludedFrom: [model, presentation, claimBridge])
        XCTAssertTrue(claimBridge.contains("runtimes.claimRuntime"))
        XCTAssertTrue(claimBridge.contains("applyClaimedSession("))
        XCTAssertTrue(renameBridge.contains("runtimes.renameRuntime"))
        XCTAssertTrue(context.contains("func applyClaimedSession("))
        XCTAssertFalse(model.contains("func applyClaimedSession("))
        for bridge in [claimBridge, renameBridge] {
            for forbidden in [
                "HermesStreamEvent", "SessionRepositoryCapabilityProviding",
                "SessionRuntimeComposition.", "applyLiveSessionTranscript",
                "refreshUsage()",
            ] {
                XCTAssertFalse(bridge.contains(forbidden))
            }
        }
        for forbidden in [
            "SessionManagementRuntime", "SessionListModelManagement",
            "private var statusTask", "private var claimGeneration",
            "private var renameTask", "private var renameGeneration",
            "repository.liveSessionStatus", "repository.renameSession",
        ] {
            XCTAssertFalse(model.contains(forbidden))
        }
        for removed in ["SessionManagementRuntime.swift", "SessionListModelManagement.swift"] {
            let path = directory.appendingPathComponent(removed).path
            XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        }

        for marker in [
            "final class SessionClaimRuntime", "any HermesSessionClaimServing",
            "private var statusTask", "private var statusGeneration",
            "private var claimGeneration", "let displayGeneration", "func claim(",
        ] {
            XCTAssertTrue(claim.contains(marker))
            XCTAssertFalse(rename.contains(marker))
        }
        for marker in [
            "final class SessionRenameRuntime", "any HermesSessionRenaming",
            "private var task", "private var generation",
            "let liveSessionID", "func rename(",
        ] {
            XCTAssertTrue(rename.contains(marker))
            XCTAssertFalse(claim.contains(marker))
        }
        for forbidden in [
            "renameSession(", "isRenaming", "HermesSessionRenaming",
            "HermesStreamEvent",
        ] {
            XCTAssertFalse(claim.contains(forbidden))
        }
        for forbidden in [
            "openSession(", "liveSessionStatus(", "isClaiming",
            "HermesSessionClaimServing", "HermesStreamEvent",
        ] {
            XCTAssertFalse(rename.contains(forbidden))
        }
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy: "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1
        )

        let lines = sources.map { $0.components(separatedBy: .newlines).count }
        let caps = [350, 260, 145, 115, 90, 190, 150]
        for (count, cap) in zip(lines, caps) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(
            lines[2] + lines[3], 250,
            "Keep Claim and Rename model bridges independently bounded"
        )
        XCTAssertLessThan(
            lines[5] + lines[6], 330,
            "Do not hide lifecycle growth behind capability splits"
        )
        XCTAssertLessThan(
            lines.prefix(4).reduce(0, +), 850,
            "Keep Claim and Rename integration out of the core model"
        )
    }

    func testSessionMediaRuntimeOwnsViewerAndPreviewAsyncLifecycle() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: appDirectory, named: $0) }
        let modelSource = try appSource("SessionListModel.swift")
        let coreSource = try appSource("SessionMediaRuntime.swift")
        let previewSource = try appSource("SessionMediaPreviewRuntime.swift")
        let mediaSources = [coreSource, previewSource]

        XCTAssertTrue(try sessionNavigationSource().contains("runtimes.mediaRuntime"))
        for marker in ["private let attachmentCache", "private var mediaPreviewTasks", "private var failedMediaPreviewKeys",
                       "private var openingAttachmentOperationID", "repository.downloadAttachment"] {
            XCTAssertFalse(modelSource.contains(marker))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 425)
        for marker in ["final class SessionMediaRuntime", "func open(", "func cancelOpening(", "private func finishOpening("] {
            XCTAssertTrue(coreSource.contains(marker))
            XCTAssertFalse(previewSource.contains(marker))
        }
        for marker in ["extension SessionMediaRuntime", "func reconcilePreviews(", "private func startPreview(",
                       "private func finishPreview(", "func resetPreviews(", "private func prunePreviews("] {
            XCTAssertTrue(previewSource.contains(marker))
            XCTAssertFalse(coreSource.contains(marker))
        }
        for authority in ["let repository: (any HermesAttachmentReading)?",
                          "private let cache: any AttachmentCaching", "private var openingTask:",
                          "private var openingGeneration:", "var previewOperations:",
                          "var failedPreviewKeys:", "struct PreviewOperation"] {
            XCTAssertEqual(mediaSources.map {
                $0.components(separatedBy: authority).count - 1
            }.reduce(0, +), 1)
            XCTAssertTrue(coreSource.contains(authority))
        }
        for mediaSource in mediaSources {
            XCTAssertFalse(mediaSource.contains("any HermesAttachmentServing"))
            XCTAssertFalse(mediaSource.contains("HermesStreamEvent"))
        }
        XCTAssertFalse(previewSource.contains("HermesAttachmentReading"))
        XCTAssertFalse(previewSource.contains("AttachmentCaching"))
        let mediaLines = mediaSources.map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(mediaLines, [180, 255]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(mediaLines.reduce(0, +), 420)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Media extraction must retain one model application boundary"
        )
    }

    func testSessionAttachmentRuntimeOwnsMutationCapabilityAndLifecycle() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: appDirectory, named: $0) }
        let modelSource = try appSource("SessionListModel.swift")
        let coreSource = try appSource("SessionAttachmentRuntime.swift")
        let deliverySource = try appSource("SessionAttachmentDelivery.swift")
        let runtimeSources = [coreSource, deliverySource]
        let deliveryStateSources = try ["AttachmentDeliveryCoordinator.swift", "AttachmentDeliveryContracts.swift", "AttachmentDeliveryQuarantineState.swift"].map(appSource)
        let coordinatorSource = deliveryStateSources[0], contractsSource = deliveryStateSources[1], quarantineSource = deliveryStateSources[2]
        for marker in ["struct OutboundAttachmentBatch: Equatable, Sendable, Identifiable", "struct ServerAttachmentLease: Hashable, Sendable", "enum AttachmentUncertainty: String, Equatable, Sendable", "struct UncertainAttachmentRuntime: Hashable, Sendable", "enum AttachmentSubmitResolution: Equatable, Sendable", "struct AttachmentBatchState: Equatable, Sendable"] { XCTAssertTrue(contractsSource.contains(marker)); XCTAssertEqual(deliveryStateSources.filter { $0.contains(marker) }.count, 1) }
        for marker in ["struct AttachmentDeliveryQuarantineState: Sendable", "private var leases", "private var mutationIDsByLease", "private var uploadInFlight", "private var uncertainties"] { XCTAssertTrue(quarantineSource.contains(marker)); XCTAssertEqual(deliveryStateSources.filter { $0.contains(marker) }.count, 1) }
        for forbidden in ["PromptSubmitStatus", "private var batches", "SessionAttachmentRuntime", "Task<", "Hermes", "repository"] { XCTAssertFalse(quarantineSource.contains(forbidden)) }
        for removedAuthority in ["private var leases", "mutationIDsByLease", "uploadInFlight", "private var uncertainties"] { XCTAssertFalse(coordinatorSource.contains(removedAuthority)) }; XCTAssertTrue(coordinatorSource.contains("private var quarantineState")); XCTAssertFalse(contractsSource.contains("private var")); XCTAssertFalse(contractsSource.contains("mutating func"))
        let deliveryStateLines = deliveryStateSources.map { $0.components(separatedBy: .newlines).count }; XCTAssertTrue(zip(deliveryStateLines, [240, 60, 110]).allSatisfy { $0.0 < $0.1 }); XCTAssertLessThan(deliveryStateLines.reduce(0, +), 380)

        XCTAssertTrue(try sessionGatewaySource().contains("runtimes.attachmentRuntime"))
        XCTAssertTrue(modelSource.contains("runtimes.eventRuntime"))
        for forbidden in ["private var attachmentDelivery", "attachmentStartTasks",
                          "repository?.", "repository.attachImage",
                          "repository.detachImage", "turnRuntime.submitPrompt"] {
            XCTAssertFalse(modelSource.contains(forbidden))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 6_300)

        for marker in ["final class SessionAttachmentRuntime",
                       "func onMessageStart(", "func detachKnownLeases(",
                       "func quarantineTrackedBatches(", "func reset()"] {
            XCTAssertTrue(coreSource.contains(marker))
            XCTAssertFalse(deliverySource.contains(marker))
        }
        for marker in ["extension SessionAttachmentRuntime", "func startDelivery(",
                       "private func scheduleStartConfirmation(",
                       "private func isCurrentDelivery(",
                       "private static func isUncertainUploadFailure(",
                       "private static func promptMayHaveExecuted("] {
            XCTAssertTrue(deliverySource.contains(marker))
            XCTAssertFalse(coreSource.contains(marker))
        }
        for authority in ["let attachments: (any HermesAttachmentMutating)?",
                          "let prompts: (any HermesPromptServing)?",
                          "let disconnector: (any HermesDisconnectServing)?",
                          "var coordinator = AttachmentDeliveryCoordinator()",
                          "var deliveryTasks:", "var startConfirmationTasks:",
                          "var lifecycleGeneration:"] {
            XCTAssertEqual(runtimeSources.map {
                $0.components(separatedBy: authority).count - 1
            }.reduce(0, +), 1)
            XCTAssertTrue(coreSource.contains(authority))
        }
        for runtimeSource in runtimeSources {
            for forbidden in ["any HermesAttachmentReading", "any HermesTurnServing",
                              "any HermesConnectionServing", "any HermesRepository",
                              "HermesStreamEvent", "for await"] {
                XCTAssertFalse(runtimeSource.contains(forbidden))
            }
        }
        let runtimeLines = runtimeSources.map { $0.components(separatedBy: .newlines).count }; for (count, cap) in zip(runtimeLines, [175, 290]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(runtimeLines.reduce(0, +), 470)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Attachment extraction must retain one model application boundary"
        )
    }

    func testSessionAttachmentBridgeHasBoundedFeatureSource() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let names = [
            "SessionListModel.swift",
            "SessionListModelAttachments.swift",
            "SessionListModelAttachmentSettlement.swift",
        ]
        let sources = try names.map { try source(in: appDirectory, named: $0) }
        let modelSource = sources[0]
        let intakeSource = sources[1]
        let settlementSource = sources[2]
        let bridgeSources = [intakeSource, settlementSource]
        let intakeAdapters = [
            "var isCurrentAttachmentOwnerQuarantined: Bool",
            "func attachImageData(",
            "func removeAttachment(",
            "func submitAttachmentPrompt(",
        ]
        let settlementAdapters = [
            "func restoreAttachmentBeforeMutation(",
            "func settleAcceptedAttachmentBatch(",
            "func settleFailedAttachmentBatch(",
            "func quarantineTrackedAttachmentBatches()",
            "func restorePersistedAttachmentState(",
            "func presentUnavailableRecoveredDraft(",
        ]

        for source in bridgeSources {
            XCTAssertTrue(source.contains("extension SessionListModel"))
        }
        for adapter in intakeAdapters {
            XCTAssertTrue(intakeSource.contains(adapter))
            XCTAssertFalse(settlementSource.contains(adapter))
            XCTAssertFalse(modelSource.contains(adapter))
        }
        for adapter in settlementAdapters {
            XCTAssertTrue(settlementSource.contains(adapter))
            XCTAssertFalse(intakeSource.contains(adapter))
            XCTAssertFalse(modelSource.contains(adapter))
        }
        XCTAssertTrue(intakeSource.contains("runtimes.attachmentRuntime"))
        XCTAssertTrue(intakeSource.contains("runtimes.attachmentPersistenceRuntime"))
        XCTAssertFalse(intakeSource.contains("runtimes.attachmentRecoveryRuntime"))
        for marker in [
            "runtimes.attachmentRuntime",
            "runtimes.attachmentPersistenceRuntime",
            "runtimes.attachmentRecoveryRuntime",
        ] {
            XCTAssertTrue(settlementSource.contains(marker))
        }
        XCTAssertFalse(settlementSource.contains("outboundTasks"))
        XCTAssertFalse(settlementSource.contains("startDelivery("))
        let applicationSource = try sessionEventApplicationSource()
        for callback in [
            "settleFailedAttachmentBatch(",
            "settleAcceptedAttachmentBatch(",
            "quarantineTrackedAttachmentBatches()",
        ] {
            XCTAssertTrue(applicationSource.contains(callback))
        }
        for source in bridgeSources {
            XCTAssertFalse(source.contains("HermesStreamEvent"))
            XCTAssertFalse(source.contains("SessionRepositoryCapabilityProviding"))
            XCTAssertFalse(source.contains("SessionRuntimeComposition."))
        }
        XCTAssertEqual(
            applicationSource.components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Attachment bridge split must retain one event application boundary"
        )

        let modelLines = modelSource.components(separatedBy: .newlines).count
        let bridgeLines = bridgeSources.map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(modelLines, 425)
        XCTAssertLessThan(bridgeLines[0], 310)
        XCTAssertLessThan(bridgeLines[1], 200)
        XCTAssertLessThan(bridgeLines.reduce(0, +), 500)
        XCTAssertLessThan(modelLines + bridgeLines.reduce(0, +), 900)
    }

    func testSessionDraftPersistenceRuntimeOwnsProtectedWriteLifecycle()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let coreSource = try appSource("SessionDraftPersistenceRuntime.swift")
        let writeSource = try appSource("SessionDraftPersistenceWrites.swift")
        let persistenceSources = [coreSource, writeSource]

        for marker in ["private let draftPersistenceRuntime", "private let draftStore",
                       "persistedComposerDrafts", "draftWriteOperations",
                       "lastDraftTimestamp", "makeComposerDraft(",
                       "ComposerDraftMigrationChange"] {
            XCTAssertFalse(modelSource.contains(marker))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 6_100)
        for marker in ["final class SessionDraftPersistenceRuntime", "func restore(",
                       "func flushClaim(", "func retireClaim(", "func migrateRecoveredDraft(",
                       "func retireStoredDraft(", "func makeRecord("] {
            XCTAssertTrue(coreSource.contains(marker))
            XCTAssertFalse(writeSource.contains(marker))
        }
        for marker in ["extension SessionDraftPersistenceRuntime", "func storeText(",
                       "func flushAll(", "func persistRecovered(", "private func scheduleWrite(",
                       "private func finishWrite("] {
            XCTAssertTrue(writeSource.contains(marker))
            XCTAssertFalse(coreSource.contains(marker))
        }
        for authority in ["struct WriteOperation", "let store: (any ComposerDraftStoring)?",
                          "let nowMilliseconds:", "var records:", "var writeOperations:",
                          "var lastTimestamp:"] {
            XCTAssertEqual(persistenceSources.map {
                $0.components(separatedBy: authority).count - 1
            }.reduce(0, +), 1)
            XCTAssertTrue(coreSource.contains(authority))
        }
        for persistenceSource in persistenceSources {
            XCTAssertFalse(persistenceSource.contains("HermesStreamEvent"))
            XCTAssertFalse(persistenceSource.contains("HermesRepository"))
        }
        let persistenceLines = persistenceSources.map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(persistenceLines, [260, 135]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(persistenceLines.reduce(0, +), 390)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Draft persistence must retain one model application boundary"
        )
    }

    func testSessionDraftLifecycleRuntimeOwnsRecoveryComposition() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionDraftLifecycleRuntime.swift"
            )
        )

        XCTAssertTrue(
            try sessionGatewaySource().contains("runtimes.draftLifecycleRuntime")
        )
        XCTAssertFalse(
            modelSource.contains("private let draftPersistenceRuntime")
        )
        XCTAssertFalse(modelSource.contains("capturePersistenceClaim"))
        XCTAssertFalse(modelSource.contains("flushDraftClaim"))
        XCTAssertFalse(modelSource.contains("persistRecoveredDraft"))
        XCTAssertFalse(modelSource.contains("composerRuntime.recover("))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            5_270,
            "Keep ordinary protected-draft composition out of the app model"
        )

        XCTAssertTrue(
            runtimeSource.contains("final class SessionDraftLifecycleRuntime")
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "private let composerRuntime: SessionComposerRuntime"
            )
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "private let persistenceRuntime: "
                    + "SessionDraftPersistenceRuntime"
            )
        )
        XCTAssertTrue(runtimeSource.contains("func captureClaim("))
        XCTAssertTrue(runtimeSource.contains("func flushClaim("))
        XCTAssertTrue(runtimeSource.contains("func retireClaim("))
        XCTAssertTrue(runtimeSource.contains("func restore("))
        XCTAssertTrue(runtimeSource.contains("func recover("))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertFalse(runtimeSource.contains("HermesRepository"))
        XCTAssertFalse(runtimeSource.contains("ComposerDraftStoring"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Draft lifecycle must retain one model application boundary"
        )
    }

    func testSessionComposerRuntimeOwnsDraftRecoveryProjection() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionComposerRuntime.swift"
            )
        )

        XCTAssertTrue(
            modelSource.contains(
                "runtimes.composerRuntime"
            )
        )
        XCTAssertFalse(modelSource.contains("private var composerDrafts"))
        XCTAssertFalse(modelSource.contains("private var restoredDraftOwners"))
        XCTAssertFalse(modelSource.contains("DraftRecoveryCoordinator"))
        XCTAssertFalse(modelSource.contains("DraftRecoveryToken"))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            5_750,
            "Keep draft projection and recovery ordering out of the model"
        )

        XCTAssertTrue(
            runtimeSource.contains("final class SessionComposerRuntime")
        )
        XCTAssertTrue(runtimeSource.contains("private var drafts"))
        XCTAssertTrue(runtimeSource.contains("private var restoredOwners"))
        XCTAssertTrue(runtimeSource.contains("private var orderedRecoveries"))
        XCTAssertTrue(runtimeSource.contains("private var steerNotices"))
        XCTAssertTrue(runtimeSource.contains("private var operationNotices"))
        XCTAssertTrue(runtimeSource.contains("func recover("))
        XCTAssertTrue(runtimeSource.contains("func migrate("))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertFalse(runtimeSource.contains("HermesRepository"))
        XCTAssertFalse(runtimeSource.contains("ComposerDraftStoring"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Composer extraction must retain one model application boundary"
        )
    }

}
