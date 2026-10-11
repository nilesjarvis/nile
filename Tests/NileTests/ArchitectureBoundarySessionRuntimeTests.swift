import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testSessionAttachmentPersistenceRuntimeOwnsProtectedStateMachine() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App",
            isDirectory: true)
        let modelSource = try source(in: appDirectory, named: "SessionListModel.swift")
        let persistenceSource = try source(in: appDirectory,
            named: "SessionAttachmentPersistenceRuntime.swift")
        let transactionSource = try source(in: appDirectory,
            named: "SessionAttachmentPersistenceTransactions.swift")
        let recoverySource = try source(in: appDirectory,
            named: "SessionAttachmentPersistenceRecoveryLifecycle.swift")
        let editSource = try source(in: appDirectory,
            named: "SessionAttachmentRecoveredEditRuntime.swift")

        XCTAssertTrue(modelSource.contains("runtimes.attachmentPersistenceRuntime"))
        for forbidden in [
            "private let attachmentDraftStore", "attachmentDrafts",
            "persistedAttachmentDrafts", "attachmentMarkers",
            "recoveredAttachmentEditGenerations", "lastAttachmentTimestamp",
            "makeAttachmentDraft(", "AttachmentDraftMigrationChange",
        ] {
            XCTAssertFalse(modelSource.contains(forbidden))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count,
            5_800, "Keep protected photo state out of the model")

        XCTAssertTrue(persistenceSource.contains(
            "final class SessionAttachmentPersistenceRuntime"))
        for required in [
            "let store: (any AttachmentDraftStoring)?", "var drafts",
            "var records", "var markers", "var restoredOwners",
            "var quarantinedOwners", "var lastTimestamp",
        ] {
            XCTAssertTrue(persistenceSource.contains(required))
        }
        for required in [
            "extension SessionAttachmentPersistenceRuntime",
            "func migrateRecoveredState(", "func loadRecoverySnapshot(",
            "func persistQuarantineAdvance(",
            "func makeDraft(", "func updateDraft(", "func beginMutation(",
            "func advanceMutation(", "func clearMutation(",
            "func recoverMutation(", "func restore(",
        ] {
            XCTAssertTrue(transactionSource.contains(required))
            XCTAssertFalse(persistenceSource.contains(required))
        }
        XCTAssertTrue(transactionSource.contains("try await store.load()"))
        XCTAssertTrue(transactionSource.contains("try await store.updateDraft("))
        XCTAssertFalse(persistenceSource.contains("try await store."))
        XCTAssertFalse(recoverySource.contains("store."))
        for required in [
            "extension SessionAttachmentPersistenceRuntime",
            "func promoteOrdinaryDraft(", "func migrateRecoveredDraft(",
            "func migrateMarkers(", "func scheduleRecoveredMarkerEdit(",
            "func quarantineTrackedBatches(",
        ] {
            XCTAssertTrue(recoverySource.contains(required))
            XCTAssertFalse(persistenceSource.contains(required))
        }
        for declaration in [
            "let store: (any AttachmentDraftStoring)?", "var drafts",
            "var records", "var markers", "var restoredOwners",
            "var quarantinedOwners", "var lastTimestamp",
        ] {
            XCTAssertEqual(
                [persistenceSource, transactionSource, recoverySource].map {
                    $0.components(separatedBy: declaration).count - 1
                }.reduce(0, +),
                1
            )
        }
        XCTAssertTrue(editSource.contains(
            "final class SessionAttachmentRecoveredEditRuntime"))
        XCTAssertTrue(editSource.contains("private var operations"))
        XCTAssertTrue(editSource.contains("for _ in 0..<3"))
        XCTAssertFalse(editSource.contains("AttachmentDraftStoring"))
        let runtimeSource = persistenceSource + transactionSource
            + recoverySource + editSource
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertFalse(runtimeSource.contains("HermesRepository"))
        let lineCounts = [
            persistenceSource, transactionSource, recoverySource, editSource,
        ].map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(lineCounts, [140, 240, 200, 140]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(lineCounts.reduce(0, +), 660)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy: "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Attachment persistence extraction must retain one event router"
        )
    }

    func testSessionCreationDraftRuntimeOwnsProtectedCreationHandoff()
        throws
    {
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
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionCreationDraftRuntime.swift"
            )
        )

        XCTAssertTrue(
            creationSource.contains(
                "runtimes.creationDraftRuntime"
            )
        )
        XCTAssertFalse(
            modelSource.contains("runtimes.creationDraftRuntime")
        )
        let integrationSource = modelSource + creationSource
        XCTAssertFalse(
            integrationSource.contains("RecoveredSessionCreationDraft")
        )
        XCTAssertFalse(
            integrationSource.contains("captureRecoveredSessionCreationDraft")
        )
        XCTAssertFalse(
            integrationSource.contains(
                "promoteOrdinaryPhotoDraftForSessionCreation"
            )
        )
        XCTAssertFalse(
            integrationSource.contains("migrateRecoveredSessionCreationDraft")
        )
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            1_860,
            "Keep protected creation-draft handoff out of the app model"
        )

        XCTAssertTrue(
            runtimeSource.contains("final class SessionCreationDraftRuntime")
        )
        XCTAssertTrue(runtimeSource.contains("struct Plan"))
        XCTAssertTrue(runtimeSource.contains("func capture("))
        XCTAssertTrue(
            runtimeSource.contains("func promoteOrdinaryPhotoDraft(")
        )
        XCTAssertTrue(runtimeSource.contains("func migrate("))
        XCTAssertTrue(
            runtimeSource.contains(
                "private let composerRuntime: SessionComposerRuntime"
            )
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "private let draftPersistenceRuntime: "
                    + "SessionDraftPersistenceRuntime"
            )
        )
        XCTAssertTrue(
            runtimeSource.contains(
                "private let attachmentPersistenceRuntime:\n"
                    + "        SessionAttachmentPersistenceRuntime"
            )
        )
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertFalse(runtimeSource.contains("HermesRepository"))
        XCTAssertFalse(runtimeSource.contains("repository.events"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Creation-draft must retain one model application boundary"
        )
    }

    func testSessionAttachmentRecoveryRuntimeOwnsRelaunchReconciliation()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let coreSource = try appSource("SessionAttachmentRecoveryRuntime.swift")
        let composerSource = try appSource("SessionAttachmentRecoveryComposer.swift")
        let recoverySources = [coreSource, composerSource]

        XCTAssertTrue(
            try sessionNavigationSource().contains(
                "runtimes.attachmentRecoveryRuntime"
            )
        )
        for marker in ["consolidateRecoveredComposerOwnership",
                       "reconcileStoredAttachmentMutations",
                       "scheduleRecoveredAttachmentComposerEdit",
                       "restoreRecoveredAttachmentMarkers",
                       "mergedRecoveredComposer",
                       "durableHistoryMatchesAttachment"] {
            XCTAssertFalse(modelSource.contains(marker))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 5_350)

        for marker in ["final class SessionAttachmentRecoveryRuntime",
                       "enum UnavailableDraftResolution", "func restore(",
                       "func reconcileStoredMutations(",
                       "func resolveUnavailableDraft(",
                       "private static func durableHistoryMatchesAttachment("] {
            XCTAssertTrue(coreSource.contains(marker))
            XCTAssertFalse(composerSource.contains(marker))
        }
        for marker in ["extension SessionAttachmentRecoveryRuntime",
                       "func scheduleRecoveredComposerEdit(",
                       "func mergeAttachments(", "func consolidateComposerOwnership(",
                       "func restoreRecoveredMarkers(",
                       "private static func mergedRecoveredComposer("] {
            XCTAssertTrue(composerSource.contains(marker))
            XCTAssertFalse(coreSource.contains(marker))
        }
        for dependency in ["let composerRuntime: SessionComposerRuntime",
                           "let draftPersistenceRuntime: SessionDraftPersistenceRuntime",
                           "let attachmentPersistenceRuntime: SessionAttachmentPersistenceRuntime",
                           "private let navigationRuntime: SessionNavigationRuntime"] {
            XCTAssertEqual(recoverySources.map {
                $0.components(separatedBy: dependency).count - 1
            }.reduce(0, +), 1)
        }
        XCTAssertFalse(composerSource.contains("navigationRuntime"))
        XCTAssertFalse(composerSource.contains("private var"))
        XCTAssertFalse(composerSource.contains("Task<"))
        for recoverySource in recoverySources {
            for forbidden in ["HermesStreamEvent", "HermesRepository",
                              "AttachmentDraftStoring", "ComposerDraftStoring"] {
                XCTAssertFalse(recoverySource.contains(forbidden))
            }
        }
        let recoveryLines = recoverySources.map {
            $0.components(separatedBy: .newlines).count
        }
        for (count, cap) in zip(recoveryLines, [280, 175]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(recoveryLines.reduce(0, +), 440)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Attachment recovery must retain one model application boundary"
        )
    }

    func testSessionBlockingPromptRuntimeOwnsSensitiveResponseLifecycle()
        throws
    {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = { try self.source(in: directory, named: $0) }
        let modelSource = try appSource("SessionListModel.swift")
        let bridgeSource = try appSource("SessionListModelBlockingPrompt.swift")
        let eventProjection = try appSource("SessionListModelEventProjection.swift")
        let runtimeSources = try ["SessionBlockingPromptRuntime.swift", "SessionBlockingPromptResponseLifecycle.swift"].map(appSource)
        let runtimeSource = runtimeSources[0]
        let responseSource = runtimeSources[1]

        for marker in ["func respondToBlockingPrompt(", "func syncBlockingPromptUI()"] { XCTAssertTrue(bridgeSource.contains(marker)); XCTAssertFalse(modelSource.contains(marker)); XCTAssertFalse(eventProjection.contains(marker)) }
        XCTAssertTrue(bridgeSource.contains("runtimes.blockingPromptRuntime"))
        for forbidden in ["HermesStreamEvent", "HermesBlockingPromptServing", "BlockingPromptSubmissionLifecycle", "Task<", "SessionRuntimeComposition."] { XCTAssertFalse(bridgeSource.contains(forbidden)) }
        for forbidden in ["private var blockingPrompts: BlockingPromptCoordinator", "BlockingPromptSubmission", "repository.respondToClarification", "repository.respondToApproval", "repository.respondToSudo", "repository.respondToSecret"] { XCTAssertFalse(modelSource.contains(forbidden)) }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 250)
        XCTAssertLessThan(bridgeSource.components(separatedBy: .newlines).count, 70)
        for marker in ["final class SessionBlockingPromptRuntime", "any HermesBlockingPromptServing", "private let coordinator: BlockingPromptCoordinator"] { XCTAssertTrue(runtimeSource.contains(marker)) }
        XCTAssertTrue(runtimeSource.contains("private let responseLifecycle"))
        for marker in ["final class SessionBlockingPromptResponseLifecycle", "private let repository: (any HermesBlockingPromptServing)?", "private let coordinator: BlockingPromptCoordinator", "private var responseTasks", "private var responseGeneration", "private static func dispatch"] { XCTAssertTrue(responseSource.contains(marker)) }
        for marker in ["private var responseTasks", "private var responseGeneration", "private static func dispatch", "respondToSecret"] { XCTAssertFalse(runtimeSource.contains(marker)) }
        XCTAssertFalse(runtimeSource.contains("repository.events"))
        XCTAssertFalse(responseSource.contains("HermesStreamEvent"))
        let runtimeLines = runtimeSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(runtimeLines, [160, 260]).allSatisfy { $0.0 < $0.1 }); XCTAssertLessThan(runtimeLines.reduce(0, +), 410)
        XCTAssertFalse(runtimeSource.contains("for await"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Blocking input must retain one model application boundary"
        )
    }

    func testBlockingPromptCoordinatorKeepsInterpretationAndPolicyBounded()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(at: appDirectory.appendingPathComponent($0))
        }
        let coordinatorSource = try appSource("BlockingPromptCoordinator.swift")
        let submissionSource = try appSource(
            "BlockingPromptSubmissionLifecycle.swift"
        )
        let contractsSource = try appSource("BlockingPromptContracts.swift")
        let eventFactorySource = try appSource("BlockingPromptEventFactory.swift")
        let policySource = try appSource("BlockingPromptPolicy.swift")

        for required in [
            "final class BlockingPromptCoordinator", "var records:",
            "private var storedIDs", "BlockingPromptEventRequest(event)",
            "func bindSession(", "func reconcileStatusPoll(", "func project(",
            "BlockingPromptPolicy.merge(",
        ] { XCTAssertTrue(coordinatorSource.contains(required)) }
        for forbidden in [
            "func beginResponse(", "func submitResponse(",
            "func markSubmittingUncertain(",
            "BlockingPromptPolicy.responseLabel(",
            "ApprovalChoice(rawValue: response)", ".clarificationRequest(",
            "TranscriptBlockingPrompt(", "static func merge(",
        ] { XCTAssertFalse(coordinatorSource.contains(forbidden)) }

        for required in [
            "extension BlockingPromptCoordinator", "func responseTarget(promptID:",
            "func beginResponse(", "func submitResponse(",
            "func markSubmittingUncertain(",
            "private func settleResponseFailure(",
            "BlockingPromptPolicy.responseLabel(",
            "ApprovalChoice(rawValue: response)",
            "private func approvalQueueHead(", "private func updateSubmitting(",
        ] { XCTAssertTrue(submissionSource.contains(required)) }
        for forbidden in [
            "final class BlockingPromptCoordinator", "var records:",
            "struct BlockingPromptRecord", "HermesStreamEvent",
            "BlockingPromptEventRequest", "storedIDs", "static func merge(",
        ] { XCTAssertFalse(submissionSource.contains(forbidden)) }

        for required in [
            "struct BlockingPromptEventRequest", "func makePrompt(",
            ".blockingRequestInvalid(",
        ] { XCTAssertTrue(eventFactorySource.contains(required)) }
        XCTAssertFalse(eventFactorySource.contains("BlockingPromptSubmission"))
        for required in [
            "enum BlockingPromptPolicy", "static func responseLabel(",
            "static func isActionable(", "static func merge(",
        ] { XCTAssertTrue(policySource.contains(required)) }
        for forbidden in ["HermesStreamEvent", "BlockingPromptRecord"] {
            XCTAssertFalse(policySource.contains(forbidden))
        }

        for contract in [
            "struct BlockingPromptResponseTarget: Equatable",
            "struct BlockingPromptSubmission",
            "enum BlockingPromptSubmissionOutcome",
            "struct BlockingPromptStatusPollToken: Equatable",
            "enum BlockingPromptEventResult: Equatable",
        ] {
            XCTAssertTrue(contractsSource.contains(contract))
            XCTAssertFalse(coordinatorSource.contains(contract))
            XCTAssertFalse(submissionSource.contains(contract))
        }

        let lineCounts = [
            coordinatorSource, submissionSource, contractsSource,
            eventFactorySource, policySource,
        ].map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(lineCounts, [300, 285, 50, 160, 120]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            850,
            "Do not hide blocking-prompt growth behind split sources"
        )
    }

    func testSessionTurnRuntimeOwnsTurnCapabilityTasksAndStopFencing()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionTurnRuntime.swift"
            )
        )

        XCTAssertTrue(
            try sessionNavigationSource().contains("runtimes.turnRuntime")
        )
        XCTAssertFalse(modelSource.contains("private struct StopOperation"))
        XCTAssertFalse(modelSource.contains("stopOperationGeneration"))
        XCTAssertFalse(modelSource.contains("activeStopOperation"))
        XCTAssertFalse(modelSource.contains("repository.submitPrompt"))
        XCTAssertFalse(modelSource.contains("repository.steer"))
        XCTAssertFalse(modelSource.contains("repository.interrupt"))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            6_780,
            "Keep turn transport lifecycle out of the app model"
        )

        XCTAssertTrue(runtimeSource.contains("final class SessionTurnRuntime"))
        XCTAssertTrue(runtimeSource.contains("any HermesTurnServing"))
        XCTAssertTrue(runtimeSource.contains("private var tasks"))
        XCTAssertTrue(runtimeSource.contains("lifecycleGeneration"))
        XCTAssertTrue(runtimeSource.contains("stopGeneration"))
        XCTAssertTrue(runtimeSource.contains("activeStopRequest"))
        XCTAssertTrue(runtimeSource.contains("isUncertainMutationFailure"))
        XCTAssertFalse(runtimeSource.contains("func submitPrompt("))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertFalse(runtimeSource.contains("for await"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Turn extraction must retain one model application boundary"
        )
    }

    func testSessionTimelineRuntimeOwnsBoundedOffscreenProjection() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let presentationSource = try sessionTimelinePresentationSource()
        let runtimeSource = try appSource("SessionTimelineRuntime.swift")
        let stateSource = try appSource("SessionTimelineProjectionState.swift")
        let eventSource = try sessionEventApplicationSource()
        let projectionSource = try appSource("SessionListModelEventProjection.swift")

        XCTAssertTrue(
            try sessionGatewaySource().contains("runtimes.timelineRuntime")
        )
        XCTAssertTrue(projectionSource.contains("timelineRuntime.consume("))
        XCTAssertFalse(eventSource.contains("timelineRuntime.consume("))
        for marker in ["extension SessionListModel", "timelineRuntime.capture(",
                       "timelineRuntime.restore(", "timelineRuntime.remove(",
                       "func applyStoredTranscript(", "func applyLiveSessionTranscript(",
                       "func scheduleVisibleSessionReconciliation()"] {
            XCTAssertTrue(presentationSource.contains(marker))
        }
        for marker in ["func applyStoredTranscript(", "func applyLiveSessionTranscript(",
                       "timelineRuntime.capture(", "timelineRuntime.restore(",
                       "LiveSessionTimeline", "liveTimelines",
                       "liveSessionIDsByStoredID", "liveTimelineRecency",
                       "private func updateCachedTool"] {
            XCTAssertFalse(modelSource.contains(marker))
        }
        for marker in ["HermesStreamEvent", "HermesEventStreaming", "repository.events",
                       "SessionRepositoryCapabilityProviding", "SessionRuntimeComposition."] {
            XCTAssertFalse(presentationSource.contains(marker))
        }
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            1_110,
            "Keep timeline presentation out of the core model source"
        )
        XCTAssertLessThan(
            presentationSource.components(separatedBy: .newlines).count,
            250,
            "Keep timeline/transcript presentation independently reviewable"
        )
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count
                + presentationSource.components(separatedBy: .newlines).count,
            1_350,
            "Do not hide core growth behind the timeline source split"
        )

        for marker in ["final class SessionTimelineRuntime", "maximumTimelineCount",
                       "timelinesByLiveID", "liveIDsByStoredID", "private var recency",
                       "func capture(", "func consume(", "func restore(", "evictIfNeeded"] {
            XCTAssertTrue(runtimeSource.contains(marker))
        }
        for marker in ["final class SessionTimelineProjectionState", "observedLiveEvents",
                       "func apply(", "case .messageStart:", "LiveToolEvent(",
                       "coordinator.upsertTool(", "private func replacingRuntimeState("] {
            XCTAssertTrue(stateSource.contains(marker))
        }
        for marker in ["case .messageStart:", "LiveToolEvent(",
                       "coordinator.upsertTool(", "replacingRuntimeState("] {
            XCTAssertFalse(runtimeSource.contains(marker))
        }
        for marker in ["maximumTimelineCount", "timelinesByLiveID",
                       "liveIDsByStoredID", "private var recency", "evictIfNeeded"] {
            XCTAssertFalse(stateSource.contains(marker))
        }
        for source in [runtimeSource, stateSource] {
            for marker in ["HermesRepository", "HermesEventStreaming", "for await"] {
                XCTAssertFalse(source.contains(marker))
            }
        }
        let timelineLines = [runtimeSource, stateSource].map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(timelineLines[0], 175)
        XCTAssertLessThan(timelineLines[1], 275)
        XCTAssertLessThan(timelineLines.reduce(0, +), 440)
        XCTAssertEqual(
            eventSource.components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Timeline extraction must retain one model application boundary"
        )
    }

    func testSessionModelControlRuntimeSeparatesMutationCatalogPinsAndPolicy() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let domainDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/Domain", isDirectory: true)
        let modelSource = try source(in: appDirectory, named: "SessionListModel.swift")
        let names = [
            "SessionModelControlRuntime.swift",
            "SessionModelControlMutationLifecycle.swift",
            "SessionModelControlContracts.swift",
            "ModelControlPolicy.swift",
            "ModelOptionsRuntime.swift",
            "ModelPinRuntime.swift",
        ]
        let sources = try names.map { try source(in: appDirectory, named: $0) }
        let runtimeSource = sources[0]
        let mutationSource = sources[1]
        let contractsSource = sources[2]
        let policySource = sources[3]
        let optionsSource = sources[4]
        let pinsSource = sources[5]
        let runtimeSources = [runtimeSource, mutationSource]
        let repositoryContractsSource = try source(
            in: domainDirectory, named: "HermesModelContracts.swift"
        )

        XCTAssertFalse(modelSource.contains("private var modelOptionsTask"))
        XCTAssertFalse(modelSource.contains("private var sessionControlTask"))
        XCTAssertFalse(modelSource.contains("private var pendingModelSwitch"))
        XCTAssertFalse(modelSource.contains("repository.modelOptions"))
        XCTAssertFalse(modelSource.contains("repository.setSessionModel"))
        XCTAssertFalse(modelSource.contains("repository.setReasoningEffort"))
        for marker in [
            "final class SessionModelControlRuntime", "any HermesModelMutationServing",
            "private let optionsRuntime: ModelOptionsRuntime", "private let pinRuntime: ModelPinRuntime",
            "var controlTask: Task<Void, Never>?", "var controlGeneration: Int64 = 0",
            "var currentSessionOwner: SessionOwner?", "var pendingSwitch: PendingSwitch?",
            "func resetSessionControls()", "private func loadOptions(",
        ] {
            XCTAssertTrue(runtimeSource.contains(marker))
        }
        for marker in [
            "extension SessionModelControlRuntime", "func selectModel(",
            "func setReasoningEffort(", "func confirmModelSwitch(",
            "func dismissSwitchConfirmation(", "private func startModelSwitch(",
            "private func isCurrentControlRequest(", "struct PendingSwitch: Sendable",
            "repository.setSessionModel(", "repository.setReasoningEffort(",
        ] {
            XCTAssertTrue(mutationSource.contains(marker))
            XCTAssertFalse(runtimeSource.contains(marker))
        }
        for declaration in [
            "let repository: (any HermesModelMutationServing)?",
            "var controlTask: Task<Void, Never>?", "var controlGeneration: Int64 = 0",
            "var currentSessionOwner: SessionOwner?", "var pendingSwitch: PendingSwitch?",
        ] {
            XCTAssertEqual(
                runtimeSources.map {
                    $0.components(separatedBy: declaration).count - 1
                }.reduce(0, +),
                1
            )
        }
        XCTAssertFalse(runtimeSource.contains("private var optionsTask"))
        XCTAssertFalse(runtimeSource.contains("private let pinStore"))
        XCTAssertFalse(runtimeSource.contains("private let pinWriteQueue"))
        XCTAssertFalse(runtimeSource.contains("repository.modelOptions"))
        XCTAssertFalse(mutationSource.contains("ModelOptionsRuntime"))
        XCTAssertFalse(mutationSource.contains("ModelPinRuntime"))
        for source in runtimeSources {
            XCTAssertFalse(source.contains("HermesStreamEvent"))
            XCTAssertFalse(source.contains("repository.events"))
        }

        for marker in [
            "final class ModelOptionsRuntime", "any HermesModelOptionsServing",
            "private var task", "private var generation",
            "repository.modelOptions",
        ] {
            XCTAssertTrue(optionsSource.contains(marker))
        }
        XCTAssertFalse(optionsSource.contains("repository.setSessionModel"))
        XCTAssertFalse(optionsSource.contains("ModelPinStoring"))

        for marker in [
            "final class ModelPinRuntime", "any ModelPinStoring",
            "ModelPinWriteQueue", "private var mutationGeneration",
        ] {
            XCTAssertTrue(pinsSource.contains(marker))
        }
        XCTAssertFalse(pinsSource.contains("HermesModelServing"))
        XCTAssertFalse(pinsSource.contains("HermesStreamEvent"))

        for marker in [
            "enum ModelControlPolicy", "static func modelSelection(",
            "static func reasoningSelection(", "static func resolvedPins(",
            "static func mutationFailure(",
        ] {
            XCTAssertTrue(policySource.contains(marker))
        }
        XCTAssertFalse(policySource.contains("Task<"))
        XCTAssertFalse(policySource.contains("ModelPinStoring"))
        XCTAssertFalse(policySource.contains("HermesModelServing"))

        for contract in [
            "struct ModelControlGatewayOwner: Equatable, Sendable", "struct ModelControlSessionOwner: Equatable, Sendable",
            "struct AppliedModelControl: Sendable", "struct ModelSwitchConfirmation: Equatable, Sendable",
            "extension SessionModelControlRuntime",
        ] {
            XCTAssertTrue(contractsSource.contains(contract))
            XCTAssertFalse(runtimeSource.contains(contract))
            if contract != "extension SessionModelControlRuntime" {
                XCTAssertFalse(mutationSource.contains(contract))
            }
        }

        for marker in [
            "protocol HermesModelOptionsServing: Sendable",
            "protocol HermesModelMutationServing: Sendable",
            "protocol HermesModelServing:",
        ] {
            XCTAssertTrue(repositoryContractsSource.contains(marker))
        }

        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(lineCounts[0], 240)
        XCTAssertLessThan(lineCounts[1], 290)
        XCTAssertLessThan(lineCounts[2], 55)
        XCTAssertLessThan(lineCounts[3], 260)
        XCTAssertLessThan(lineCounts[4], 90)
        XCTAssertLessThan(lineCounts[5], 170)
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_090,
            "Do not hide model-control growth behind runtime/policy splits"
        )
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Model control must retain one model application boundary"
        )
    }

    func testSessionPinRuntimeOwnsProtectedPersistenceLifecycle() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let gatewaySource = try sessionGatewaySource()
        let navigationSource = try sessionNavigationSource()
        let runtimeSource = try source(
            at: appDirectory.appendingPathComponent("SessionPinRuntime.swift")
        )

        XCTAssertTrue(
            gatewaySource.contains("runtimes.pinRuntime")
        )
        XCTAssertTrue(
            navigationSource.contains("runtimes.pinRuntime")
        )
        XCTAssertTrue(modelSource.contains("runtimes.pinRuntime"))
        XCTAssertFalse(modelSource.contains("private let sessionPinStore"))
        XCTAssertFalse(modelSource.contains("private let sessionPinWriteQueue"))
        XCTAssertFalse(modelSource.contains("sessionPinWriteQueue.enqueue"))
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            6_450,
            "Keep protected session-pin ownership out of the app model"
        )

        XCTAssertTrue(runtimeSource.contains("final class SessionPinRuntime"))
        XCTAssertTrue(runtimeSource.contains("any SessionPinStoring"))
        XCTAssertTrue(runtimeSource.contains("SessionPinWriteQueue"))
        XCTAssertTrue(runtimeSource.contains("struct GatewayOwner"))
        XCTAssertTrue(runtimeSource.contains("func restorePins("))
        XCTAssertTrue(runtimeSource.contains("func togglePin("))
        XCTAssertFalse(runtimeSource.contains("HermesRepository"))
        XCTAssertFalse(runtimeSource.contains("HermesStreamEvent"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Pin extraction must retain one model application boundary"
        )
    }

    func testSessionNavigationRuntimeOwnsDirectoryAndDisplayLifecycle() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appSource: (String) throws -> String = {
            try self.source(in: appDirectory, named: $0)
        }
        let modelSource = try appSource("SessionListModel.swift")
        let gatewaySource = try sessionGatewaySource()
        let navigationSource = try appSource("SessionListModelNavigation.swift")
        let openingSource = try appSource("SessionListModelSessionOpening.swift")
        let refreshSource = try appSource("SessionListModelRefresh.swift")
        let navigationSources = [navigationSource, openingSource, refreshSource]
        let runtimeCoreSource = try appSource("SessionNavigationRuntime.swift")
        let runtimeTaskSource = try appSource("SessionNavigationTaskLifecycle.swift")
        let contextRuntimeSource = try appSource("SessionGatewayContextRuntime.swift")
        let contextBridgeSource = try appSource("SessionListModelGatewayContext.swift")

        for bridge in [gatewaySource] + navigationSources { XCTAssertTrue(bridge.contains("runtimes.navigationRuntime")) }
        XCTAssertTrue(gatewaySource.contains("func load(gatewayID:"))
        XCTAssertTrue(navigationSource.contains("func selectSession(id:"))
        XCTAssertTrue(navigationSource.contains("openProductionSession("))
        for marker in ["struct SessionOpeningRequest: Sendable", "func openProductionSession(",
                       "switch route", "readStoredSessionSource(", "readStoredSession(",
                       "openSession(", "reconcileStoredMutations("] {
            XCTAssertTrue(openingSource.contains(marker))
            XCTAssertFalse(navigationSource.contains(marker))
        }
        for marker in ["func selectSession(id:", "fixtureMessages(for:", "cancelVoiceForOwnershipChange()",
                       "func togglePin(", "currentNavigationGatewayOwner", "applyActiveStatus(", "overlaySelectedLiveSession("] {
            XCTAssertFalse(openingSource.contains(marker))
        }
        XCTAssertTrue(refreshSource.contains("func startRefreshingIfNeeded()"))
        XCTAssertFalse(navigationSource.contains("func startRefreshingIfNeeded()"))
        XCTAssertFalse(openingSource.contains("func startRefreshingIfNeeded()"))
        XCTAssertFalse(refreshSource.contains("func selectSession(id:"))
        XCTAssertFalse(refreshSource.contains("func openProductionSession("))
        XCTAssertFalse(modelSource.contains("runtimes.navigationRuntime"))
        for marker in ["private var loadedGatewayID", "private var terminalSessionIDs", "private var claimedSessionIDs"] {
            XCTAssertTrue(contextRuntimeSource.contains(marker)); XCTAssertFalse(modelSource.contains(marker))
        }
        for marker in ["var currentGatewayID: String?", "func recordListedSessionOwnership(", "func applyClaimedSession("] {
            XCTAssertTrue(contextBridgeSource.contains(marker)); XCTAssertFalse(modelSource.contains(marker))
        }
        XCTAssertTrue(contextBridgeSource.contains("runtimes.gatewayContextRuntime"))
        XCTAssertFalse(contextRuntimeSource.contains("SessionListModel"))
        XCTAssertFalse(contextBridgeSource.contains("HermesStreamEvent"))
        for bridge in [gatewaySource] + navigationSources {
            XCTAssertFalse(bridge.contains("ownership."))
        }
        for bridgeSource in [modelSource, gatewaySource] + navigationSources {
            for marker in ["private var refreshTask", "liveReconciliationTask", "attachedTurnRefreshTask",
                           "repository.listSessions", "repository.activeSessionStatuses", "repository.readStoredSession",
                           "repository.openSession", "repository.createSession", "repository.liveRuntimeStatus", "HermesStreamEvent"] {
                XCTAssertFalse(bridgeSource.contains(marker))
            }
        }
        for bridgeSource in [gatewaySource] + navigationSources {
            XCTAssertFalse(bridgeSource.contains("SessionRepositoryCapabilityProviding"))
        }
        XCTAssertLessThan(modelSource.components(separatedBy: .newlines).count, 410)
        XCTAssertLessThan(gatewaySource.components(separatedBy: .newlines).count, 240)
        XCTAssertLessThan(contextRuntimeSource.components(separatedBy: .newlines).count, 115)
        XCTAssertLessThan(contextBridgeSource.components(separatedBy: .newlines).count, 90)
        let navigationLines = navigationSources.map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(navigationLines, [285, 190, 125]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(navigationLines.reduce(0, +), 560)

        let runtimeSources = [runtimeCoreSource, runtimeTaskSource]
        for marker in ["final class SessionNavigationRuntime", "any HermesSessionServing", "let repository:", "let refreshTicks:", "var currentGatewayOwner:", "var refreshTask:", "var reconciliationTask:", "var attachedTurnRefreshTask:"] {
            XCTAssertTrue(runtimeCoreSource.contains(marker)); XCTAssertEqual(runtimeSources.filter { $0.contains(marker) }.count, 1)
        }
        for marker in ["func loadDirectory(", "func listSessions(", "func readStoredSessionSource(", "func readStoredSession(", "func openSession(", "func liveRuntimeStatus(", "func createSession("] {
            XCTAssertTrue(runtimeCoreSource.contains(marker)); XCTAssertEqual(runtimeSources.filter { $0.contains(marker) }.count, 1)
        }
        for marker in ["extension SessionNavigationRuntime", "func startRefreshing(", "func reconcileDisplay(", "func refreshCompletedAttachedTurn(", "func cancelAttachedTurnRefresh()", "func cancelDisplayTasks()", "private func refreshOnce(", "func cancelAllTasks()"] {
            XCTAssertTrue(runtimeTaskSource.contains(marker)); XCTAssertEqual(runtimeSources.filter { $0.contains(marker) }.count, 1)
        }
        for marker in ["Task { [weak self]", "func startRefreshing(", "func reconcileDisplay(", "func refreshCompletedAttachedTurn(", "sink.history("] { XCTAssertFalse(runtimeCoreSource.contains(marker)) }
        for marker in ["struct GatewayOwner", "struct DirectorySnapshot", "let repository:", "var refreshTask:", "func loadDirectory(", "func createSession("] { XCTAssertFalse(runtimeTaskSource.contains(marker)) }
        for source in runtimeSources { XCTAssertFalse(source.contains("HermesStreamEvent") || source.contains("repository.events")) }
        let runtimeLines = runtimeSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(runtimeLines, [215, 180]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(runtimeLines.reduce(0, +), 380)
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Navigation extraction must retain one model application boundary"
        )
    }

    func testGatewaySetupKeepsModelAndSurfaceResponsibilitiesBounded() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let appNames = ["GatewaySetupModel.swift", "GatewaySetupModelPresentation.swift", "GatewaySetupDependencies.swift", "GatewaySetupModelDebugFixtures.swift", "GatewaySetupModelConnection.swift", "GatewaySetupModelProfiles.swift", "GatewaySetupModelVoice.swift", "GatewaySetupModelSharingConsent.swift", "GatewaySetupModelFormConnection.swift", "GatewaySetupModelConnectionErrors.swift"]
        let appSources = try appNames.map { try source(in: appDirectory, named: $0) }
        let ownership: [(markers: [String], excluded: [String])] = [
            (["final class GatewaySetupModel", "GatewaySetupDependencies.resolve(", "func connect() async", "private(set) var pendingGatewaySwitch: GatewayProfile?", "func setPendingGatewaySwitch(", "func observeAuthenticationEvents(", "var usesDeterministicFixtureCopy = false"], ["import WebKit", "SecureGatewayProfileStore(", "GatewayAuthenticationService(", "TuiGatewayClient(", "NileDebugFixturePolicy", "--nile-fixture-", "usesDeterministicFixtureCopy = true", "var isChecking: Bool", "var errorMessage: String?", "func updateDashboardURL(", "var showsSessionShell: Bool", "func restoreSavedGateway()", "func completeGatewaySignIn()", "func applyHermesVoice("]),
            (["extension GatewaySetupModel", "var isChecking: Bool", "var errorMessage: String?", "var isConnected: Bool", "var cleartextGatewaysSupported: Bool", "var parsedFormEndpoint: GatewayEndpoint?", "func updateDashboardURL(", "func updateCleartextApproved(", "var showsSessionShell: Bool"], ["Task<", "Task {", "GatewaySetupDependencies.resolve(", "GatewayProfileStoring", "GatewayConnecting", "func connect() async", "func installReconnectRestorer(", "func observeAuthenticationEvents(", "func setPendingGatewaySwitch(", "pendingGatewaySwitch =", "import WebKit"]),
            (["struct GatewaySetupDependencies", "static func resolve(", "SecureGatewayProfileStore()", "GatewayAuthenticationService(", "WebKitGatewayCookieStore()", "TuiGatewayClient(", "HermesVoiceCoordinator("], ["@Observable", "ProbeState", "--nile-fixture-", "func connect() async"]),
            (["#if DEBUG", "extension GatewaySetupModel", "func installDebugFixtures(arguments:", "NileDebugFixturePolicy.arguments(from:", "usesDeterministicFixtureCopy = true", "--nile-fixture-gateway-sign-in", "signInFixtureHTML = \"\"\""], ["GatewayProfileStoring", "GatewayConnecting", "SecureGatewayProfileStore", "Task<", "func connect() async"]),
            (["extension GatewaySetupModel", "func completeGatewaySignIn()", "func handleConnectionLoss(", "func attemptReconnect(", "func handleAuthenticationExpiry("], ["func removeGateway(id:", "func applyHermesVoice("]),
            (["extension GatewaySetupModel", "func restoreSavedGateway()", "func useGateway(id:", "func removeGateway(id:", "func showSettings()"], ["pendingGatewaySwitch =", "func attemptReconnect(", "func applyHermesVoice("]),
            (["extension GatewaySetupModel", "func setHermesVoiceSheetVisible(", "func applyHermesVoice(", "func resetHermesVoice()"], ["func useGateway(id:", "func attemptReconnect("]),
            (["struct GatewaySharingConsentRequest:", "func requireSharingConsent(", "func approveSharingConsent()", "func revokeSharingConsent()"], ["UserDefaults", "import WebKit", "connectionClient.connect("]),
            (["extension GatewaySetupModel", "func connectApprovedForm(to"], ["UserDefaults", "func approveSharingConsent()"]),
            (["extension GatewaySetupModel", "static func isRetryableConnectionFailure(", "static func connectionMessage("], ["connectionClient.connect(", "UserDefaults"]),
        ]
        for (index, boundary) in ownership.enumerated() { boundary.markers.forEach { XCTAssertTrue(appSources[index].contains($0)) }; boundary.excluded.forEach { XCTAssertFalse(appSources[index].contains($0)) } }
        for marker in ownership.flatMap(\.markers) where !["extension GatewaySetupModel", "#if DEBUG"].contains(marker) { XCTAssertEqual(appSources.filter { $0.contains(marker) }.count, 1, "Keep \(marker) in exactly one setup boundary") }
        let lineCounts = appSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lineCounts, [225, 80, 100, 80, 310, 300, 175, 100, 85, 45]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(lineCounts.reduce(0, +), 1_400, "Keep consent, connection, and settings responsibilities bounded")

        let featureDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/Features/Gateway", isDirectory: true)
        let surfaceBoundaries: [(file: String, marker: String, limit: Int)] = [
            ("SettingsView.swift", "struct SettingsView: View", 310),
            ("SettingsCards.swift", "struct SettingsSecurityCard: View", 210),
            ("HermesVoiceEntryView.swift", "struct HermesVoiceEntryView: View", 75),
            ("HermesVoiceSettingsView.swift", "struct HermesVoiceSheetView: View", 175),
            ("HermesVoiceEditorView.swift", "struct HermesVoiceEditorView: View", 260),
            ("HermesVoiceEditorSupport.swift", "struct HermesVoiceLoadingView: View", 85),
            ("HermesVoicePresentation.swift", "enum HermesVoicePresentation", 125),
            ("GatewaySwitchConfirmationDialog.swift", "struct GatewaySwitchConfirmationDialog: View", 110),
            ("GatewayRemovalConfirmationDialog.swift", "struct GatewayRemovalConfirmationDialog: View", 155),
            ("GatewaySignInView.swift", "struct GatewaySignInView: View", 210),
            ("GatewayLoginWebView.swift", "struct GatewayLoginWebView: UIViewRepresentable", 180),
            ("GatewayLoginNavigationPolicy.swift", "struct GatewayLoginNavigationPolicy: Equatable, Sendable", 115),
            ("AddGatewayView.swift", "struct AddGatewayView: View", 235),
            ("GatewayCleartextControls.swift", "struct GatewayCleartextWarning: View", 95),
        ]
        let gatewayFiles = try FileManager.default.contentsOfDirectory(atPath: featureDirectory.path).filter { $0.hasSuffix(".swift") }; XCTAssertEqual(Set(surfaceBoundaries.map(\.file)), Set(gatewayFiles))
        let surfaceSources = try surfaceBoundaries.map { try source(in: featureDirectory, named: $0.file) }
        for (index, boundary) in surfaceBoundaries.enumerated() {
            XCTAssertEqual(surfaceSources.filter { $0.contains(boundary.marker) }.count, 1)
            XCTAssertLessThan(surfaceSources[index].components(separatedBy: .newlines).count, boundary.limit)
        }
        for marker in ["SettingsSecurityCard(", "SettingsGatewayCard(", "GatewayRemovalConfirmationDialog(", "Task {"] { XCTAssertTrue(surfaceSources[0].contains(marker)) }
        for marker in ["struct SettingsSecurityCard: View", "struct SettingsGatewayCard: View", "let isEnabled: Binding<Bool>", "let onUse: (String) -> Void", "let onRemove: (GatewayProfile) -> Void"] { XCTAssertTrue(surfaceSources[1].contains(marker)) }
        for forbidden in ["GatewaySetupModel", "BiometricAppLockModel", "@Bindable", "Task {", "requestGatewayUse(", "setEnabled(", "GatewayRemovalConfirmationDialog"] { XCTAssertFalse(surfaceSources[1].contains(forbidden)) }
        for marker in ["PrivacyInformationView(", "GatewaySharingConsentView(", "model.pendingSharingConsent", "model.approveSharingConsent()"] { XCTAssertTrue(surfaceSources[0].contains(marker)) }
        XCTAssertFalse(surfaceSources[0].contains("sharingConsentStore.accept"))
        XCTAssertLessThan(surfaceSources.prefix(2).map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 515)
        XCTAssertEqual(surfaceSources.filter { $0.contains("struct HermesVoicePreset") }.count, 1)
        XCTAssertTrue(surfaceSources[3].contains("@Bindable var model: GatewaySetupModel"))
        for forbidden in ["GatewaySetupModel", "@Bindable", "setHermesVoiceSheetVisible", "applyHermesVoice"] { XCTAssertFalse(surfaceSources[4].contains(forbidden)) }
        for marker in ["struct HermesVoiceLoadingView: View", "struct HermesVoiceFailureView: View", "struct HermesVoiceNotice: View", "struct HermesVoiceMaterialButtonStyle: ButtonStyle"] { XCTAssertTrue(surfaceSources[5].contains(marker)); XCTAssertFalse(surfaceSources[4].contains(marker)) }
        for forbidden in ["GatewaySetupModel", "@Bindable", "@Binding", "@FocusState", "HermesVoiceConfig", "draftVoice", "onApply"] { XCTAssertFalse(surfaceSources[5].contains(forbidden)) }
        for (index, forbidden) in [(9, ["import WebKit", "struct GatewayLoginNavigationPolicy"]), (10, ["struct GatewaySignInView", "func gatewayOriginKey"]), (11, ["import SwiftUI", "import WebKit", "WKWebView"])] { forbidden.forEach { XCTAssertFalse(surfaceSources[index].contains($0)) } }
        for (source, markers) in [(surfaceSources[12], ["@Bindable var model: GatewaySetupModel", "Task {", "GatewayCleartextWarning(", "GatewayCleartextApproval("]), (surfaceSources[13], ["struct GatewayCleartextApproval: View", "NileComposeText(", "NileAccessibilityID.gatewayCleartextWarning", "NileAccessibilityID.approveCleartext"])] { markers.forEach { XCTAssertTrue(source.contains($0)) } }
        for (source, markers) in [(surfaceSources[12], ["NileMaterialButtonStyle", "materialButtonHeight", "connectButtonRasterBackground", "exactFieldText(", "struct GatewayCleartextWarning", "struct GatewayCleartextApproval"]), (surfaceSources[13], ["GatewaySetupModel", "@Bindable", "Task {", "func connect("])] { markers.forEach { XCTAssertFalse(source.contains($0)) } }
        XCTAssertLessThan(surfaceSources.prefix(9).map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 1_400)
        XCTAssertLessThan(
            surfaceSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 2_170,
            "Keep every gateway surface in one bounded aggregate"
        )

        let testDirectory = repositoryRoot.appendingPathComponent("Tests/NileTests", isDirectory: true)
        let boundaries: [(file: String, tests: Int, limit: Int, markers: [String])] = [
            ("GatewaySetupModelConnectionTests.swift", 6, 175, ["func testSuccessfulReadyHandshakePersistsThenTransitionsAndClearsFormSecret", "func testEditingEndpointRevokesInlineCleartextApproval"]),
            ("GatewaySetupModelFixtureTests.swift", 3, 75, ["func testUsesIOSLoopbackOutsideVisualRegressionFixture", "func testGatewaySignInFixtureSuppressesAutomaticProfileRestoration"]),
            ("GatewaySetupModelSwitchTests.swift", 7, 350, ["func testFailedGatewaySwitchClearsReplacedConnectionState", "func testRemovingPendingGatewaySwitchTargetClearsConfirmation"]),
            ("GatewaySetupModelReconnectTests.swift", 5, 275, ["func testTransientSavedGatewayFailureRetainsProfileAndWaitsOffline", "func testDashboardExpiryFencesSuspendedReconnectBeforeRestoration"]),
            ("GatewaySetupModelProtectionTests.swift", 2, 150, ["func testInvalidAddWhileConnectedKeepsCurrentGatewayLive", "func testRemovingGatewayAlsoErasesItsProtectedLocalState"]),
            ("GatewaySetupModelVoiceTests.swift", 7, 260, ["func testOpeningHermesVoiceLoadsCurrentGlobalConfig", "func testHermesVoicePresentationNormalizesAndGatesDraftApplication"]),
            ("GatewaySetupModelTestSupport.swift", 0, 75, ["func connectedModel", "func waitUntil("]),
            ("GatewaySetupModelVoiceTestDouble.swift", 0, 110, ["actor ModelHermesVoiceService"]),
            ("GatewaySetupModelConnectionTestDoubles.swift", 0, 175, ["actor ModelGatewayClient", "class ModelGatewaySwitchRecorder", "actor ModelSuspendedGatewayClient", "actor ModelGatewayNetwork", "actor ModelReconnectRestoreGate", "actor ModelReconnectRestoreRecorder"]),
            ("GatewaySetupModelStoreTestDoubles.swift", 0, 200, ["actor ModelGatewayStore", "actor ModelComposerDraftStore", "actor GatewayModelPinStore", "actor GatewaySessionPinStore"]),
        ]
        let baseSource = try source(in: testDirectory, named: "GatewaySetupModelTests.swift")
        var splitSources = [baseSource]
        var setupTestNames: [String] = []
        for boundary in boundaries {
            let boundarySource = try source(in: testDirectory, named: boundary.file)
            let names = architectureTestNames(in: boundarySource)
            XCTAssertEqual(names.count, boundary.tests)
            XCTAssertLessThan(boundarySource.components(separatedBy: .newlines).count, boundary.limit)
            boundary.markers.forEach { XCTAssertTrue(boundarySource.contains($0)) }
            setupTestNames.append(contentsOf: names)
            splitSources.append(boundarySource)
        }
        XCTAssertEqual(architectureTestNames(in: baseSource), [])
        XCTAssertLessThan(baseSource.components(separatedBy: .newlines).count, 10)
        XCTAssertEqual(setupTestNames.count, 30)
        XCTAssertEqual(Set(setupTestNames).count, 30)
        for marker in boundaries.flatMap(\.markers) {
            let occurrences = splitSources.map { $0.components(separatedBy: marker).count - 1 }.reduce(0, +)
            XCTAssertEqual(occurrences, 1)
        }
        XCTAssertLessThan(
            splitSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 1_620,
            "Allow explicit post-consent fixture injection while keeping setup tests bounded"
        )
    }

}
