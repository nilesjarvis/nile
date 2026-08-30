import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testGatewayDelegationServiceOwnsCapabilityTransport() throws {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let sources = try [
            "TuiGatewayRepository.swift",
            "GatewayDelegationService.swift",
            "GatewayDelegationStatusCodec.swift",
            "GatewayDelegationSnapshotDecoding.swift",
            "GatewayDelegationSnapshotEncoding.swift",
            "GatewayDelegationCodec.swift",
            "GatewayRPCRequesting.swift",
        ].map { try source(at: gatewayDirectory.appendingPathComponent($0)) }
        let repositorySource = sources[0]
        let serviceSource = sources[1]
        let codecSources = Array(sources[2...5])
        let statusCodecSource = codecSources[0]
        let snapshotDecoderSource = codecSources[1]
        let snapshotEncoderSource = codecSources[2]
        let primitiveCodecSource = codecSources[3]
        let rpcSource = sources[6]

        XCTAssertTrue([
            "private let delegation: GatewayDelegationService",
            "delegation: delegation",
        ].allSatisfy(repositorySource.contains))
        XCTAssertFalse([
            "protocol GatewayRPCRequesting", "HermesDelegationServing,",
            "func delegationStatus(", "func interruptSubagent(",
            "func saveDelegationSnapshot(", "func listDelegationSnapshots(",
            "func loadDelegationSnapshot(",
        ].contains(where: repositorySource.contains))
        XCTAssertLessThan(
            repositorySource.components(separatedBy: .newlines).count,
            1_100
        )

        XCTAssertTrue([
            "struct GatewayDelegationService: HermesDelegationServing",
            "any GatewayRPCRequesting", "func delegationStatus(",
            "func interruptSubagent(", "func saveDelegationSnapshot(",
            "func listDelegationSnapshots(", "func loadDelegationSnapshot(",
            "GatewayMutationCodec", "decodeDelegationStatus(",
            "decodeDelegationSnapshotInfos(", "decodeDelegationSnapshot(",
            "encodeDelegationSnapshotAgents(",
        ].allSatisfy(serviceSource.contains))
        XCTAssertLessThan(
            serviceSource.components(separatedBy: .newlines).count,
            200
        )

        for declaration in [
            "func decodeDelegationStatus(",
            "func decodeDelegationSnapshotInfos(",
            "func decodeDelegationSnapshot(",
            "func encodeDelegationSnapshotAgents(",
            "func delegationCleanString(",
            "func delegationRequireNonNegativeInt(",
        ] {
            XCTAssertEqual(codecSources.filter { $0.contains(declaration) }.count, 1)
        }
        XCTAssertTrue([
            statusCodecSource.contains("DelegationStatus("),
            !statusCodecSource.contains("DelegationSnapshot"),
            !statusCodecSource.contains("spawn_tree."),
            snapshotDecoderSource.contains("DelegationSnapshotInfo("),
            snapshotDecoderSource.contains("DelegationSnapshot("),
            !snapshotDecoderSource.contains("encodeDelegationSnapshotAgents("),
            !snapshotDecoderSource.contains("spawn_tree.save"),
            snapshotEncoderSource.contains("encodeDelegationSnapshotAgents("),
            snapshotEncoderSource.contains("delegationTerminalWireValue("),
            !snapshotEncoderSource.contains("decodeDelegationSnapshot"),
            !snapshotEncoderSource.contains("spawn_tree.load"),
            !snapshotEncoderSource.contains("spawn_tree.list"),
            primitiveCodecSource.contains("func delegationMalformed("),
            primitiveCodecSource.contains("func delegationPutString("),
            !primitiveCodecSource.contains("ActiveSubagent"),
            !primitiveCodecSource.contains("DelegationSnapshot"),
        ].allSatisfy { $0 })
        let codecLineCounts = codecSources.map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertTrue(
            zip(codecLineCounts, [60, 175, 150, 250])
                .allSatisfy { $0.0 < $0.1 }
        )
        XCTAssertLessThan(codecLineCounts.reduce(0, +), 590)

        XCTAssertTrue(rpcSource.contains("protocol GatewayRPCRequesting"))
        XCTAssertTrue(
            rpcSource.contains(
                "extension TuiGatewayClient: GatewayRPCRequesting"
            )
        )
    }

    func testGatewayModelUsageAndBlockingServicesOwnCapabilityTransport()
        throws
    {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let repositorySource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "TuiGatewayRepository.swift"
            )
        )
        let modelCodecSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayModelCodec.swift"
            )
        )
        let modelArgumentPolicySource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayModelArgumentPolicy.swift"
            )
        )
        let mutationCodecSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayMutationCodec.swift"
            )
        )
        let modelServiceSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayModelService.swift"
            )
        )
        let usageServiceSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayUsageService.swift"
            )
        )
        let blockingServiceSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayBlockingPromptService.swift"
            )
        )
        let connectionStateSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayConnectionState.swift"
            )
        )

        XCTAssertTrue(
            repositorySource.contains(
                "private let models: GatewayModelService"
            )
        )
        XCTAssertTrue(
            repositorySource.contains(
                "private let usage: GatewayUsageService"
            )
        )
        XCTAssertTrue(
            repositorySource.contains(
                "private let blockingPrompts: GatewayBlockingPromptService"
            )
        )
        XCTAssertTrue(repositorySource.contains("models: models"))
        XCTAssertTrue(["sessionUsage: usage", "gatewayStatistics: usage"].allSatisfy(repositorySource.contains))
        XCTAssertTrue(
            repositorySource.contains("blockingPrompts: blockingPrompts")
        )
        XCTAssertFalse(repositorySource.contains("HermesModelServing,"))
        XCTAssertFalse(repositorySource.contains("HermesUsageServing,"))
        XCTAssertFalse(
            repositorySource.contains("HermesBlockingPromptServing,")
        )
        XCTAssertFalse(repositorySource.contains("func modelOptions("))
        XCTAssertFalse(repositorySource.contains("func setSessionModel("))
        XCTAssertFalse(repositorySource.contains("func setReasoningEffort("))
        XCTAssertFalse(repositorySource.contains("func sessionUsage("))
        XCTAssertFalse(repositorySource.contains("func gatewayStats("))
        XCTAssertFalse(
            repositorySource.contains("func respondToClarification(")
        )
        XCTAssertFalse(repositorySource.contains("func respondToSudo("))
        XCTAssertFalse(repositorySource.contains("func respondToSecret("))
        XCTAssertFalse(repositorySource.contains("func respondToApproval("))
        XCTAssertFalse(repositorySource.contains("actor GatewayConnectionState"))
        XCTAssertFalse(repositorySource.contains("func decodeModelOptions"))
        XCTAssertFalse(repositorySource.contains("func decodeModelPricing"))
        XCTAssertFalse(repositorySource.contains("func requireSafeModelName"))
        XCTAssertLessThan(
            repositorySource.components(separatedBy: .newlines).count,
            550,
            "Keep independent capability transport out of the repository"
        )

        XCTAssertTrue(
            modelServiceSource.contains(
                "struct GatewayModelService: HermesModelServing"
            )
        )
        XCTAssertTrue(modelServiceSource.contains("GatewayModelCodec()"))
        XCTAssertTrue(modelServiceSource.contains("any GatewayRPCRequesting"))
        XCTAssertTrue(modelServiceSource.contains("func modelOptions("))
        XCTAssertTrue(modelServiceSource.contains("func setSessionModel("))
        XCTAssertTrue(modelServiceSource.contains("func setReasoningEffort("))
        XCTAssertTrue(modelServiceSource.contains("GatewayModelArgumentPolicy.requireSafeModelName"))
        XCTAssertLessThan(
            modelServiceSource.components(separatedBy: .newlines).count,
            115,
            "Keep model transport independently reviewable"
        )

        XCTAssertTrue(
            usageServiceSource.contains(
                "struct GatewayUsageService: HermesUsageServing"
            )
        )
        XCTAssertTrue(usageServiceSource.contains("GatewayConnectionState"))
        XCTAssertTrue(usageServiceSource.contains("any GatewayRPCRequesting"))
        XCTAssertTrue(usageServiceSource.contains("func sessionUsage("))
        XCTAssertTrue(usageServiceSource.contains("func gatewayStats("))
        XCTAssertTrue(usageServiceSource.contains("decodeSessionUsage"))
        XCTAssertTrue(usageServiceSource.contains("decodeGatewayStats"))
        XCTAssertLessThan(
            usageServiceSource.components(separatedBy: .newlines).count,
            75,
            "Keep usage transport independently reviewable"
        )

        XCTAssertTrue(
            blockingServiceSource.contains(
                "struct GatewayBlockingPromptService: HermesBlockingPromptServing"
            )
        )
        XCTAssertTrue(
            blockingServiceSource.contains("requestMayHaveSucceeded: true")
        )
        XCTAssertTrue(blockingServiceSource.contains("func respondToClarification("))
        XCTAssertTrue(blockingServiceSource.contains("func respondToSudo("))
        XCTAssertTrue(blockingServiceSource.contains("func respondToSecret("))
        XCTAssertTrue(blockingServiceSource.contains("func respondToApproval("))
        XCTAssertLessThan(
            blockingServiceSource.components(separatedBy: .newlines).count,
            130,
            "Keep sensitive response transport independently reviewable"
        )

        XCTAssertTrue(
            connectionStateSource.contains("actor GatewayConnectionState")
        )
        XCTAssertTrue(connectionStateSource.contains("func requireActive()"))
        XCTAssertTrue(
            connectionStateSource.contains("isConnectionFailure: true")
        )
        XCTAssertLessThan(
            connectionStateSource.components(separatedBy: .newlines).count,
            40,
            "Keep the shared active-connection primitive minimal"
        )

        XCTAssertTrue(modelCodecSource.contains("struct GatewayModelCodec"))
        XCTAssertTrue(modelCodecSource.contains("func decodeOptions"))
        XCTAssertTrue(modelCodecSource.contains("func decodeSwitchOutcome"))
        XCTAssertFalse(modelCodecSource.contains("func requireSafeModelName"))
        XCTAssertFalse(modelCodecSource.contains("CharacterSet."))
        XCTAssertTrue(
            modelCodecSource.contains("GatewayMutationCodec.requireLiteral")
        )
        XCTAssertFalse(modelCodecSource.contains("func malformedResult"))
        for marker in ["enum GatewayModelArgumentPolicy", "static func requireSafeModelName", "static func requireSafeProviderIdentifier", "private static func containsUnsafeModelFlag"] { XCTAssertTrue(modelArgumentPolicySource.contains(marker)) }
        for forbidden in ["JSONValue", "GatewayMutationCodec", "GatewayRPCRequesting", "ModelOptions"] { XCTAssertFalse(modelArgumentPolicySource.contains(forbidden)) }
        XCTAssertLessThan(modelCodecSource.components(separatedBy: .newlines).count, 275)
        XCTAssertLessThan(modelArgumentPolicySource.components(separatedBy: .newlines).count, 65)
        XCTAssertLessThan([modelCodecSource, modelArgumentPolicySource].map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 330)
        XCTAssertTrue(
            mutationCodecSource.contains("enum GatewayMutationCodec")
        )
        XCTAssertTrue(mutationCodecSource.contains("static func requireLiteral"))
        XCTAssertTrue(mutationCodecSource.contains("static func requireString"))
        XCTAssertTrue(mutationCodecSource.contains("static func requireBool"))
        XCTAssertTrue(mutationCodecSource.contains("static func malformedResult"))
    }

    func testGatewaySessionTurnAndTalkServicesOwnCapabilityTransport() throws {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let repositorySource = try source(in: gatewayDirectory, named: "TuiGatewayRepository.swift")
        let sessionSource = try source(in: gatewayDirectory, named: "GatewaySessionService.swift")
        let sessionCodecSources = try [
            "GatewaySessionCodec.swift", "GatewayStoredSessionCodec.swift",
            "GatewaySessionMessagePolicy.swift",
        ].map { try source(at: gatewayDirectory.appendingPathComponent($0)) }
        let sessionCodecSource = sessionCodecSources[0]
        let storedSessionCodecSource = sessionCodecSources[1]
        let sessionMessagePolicySource = sessionCodecSources[2]
        let turnSource = try source(in: gatewayDirectory, named: "GatewayTurnService.swift")
        let talkSource = try source(in: gatewayDirectory, named: "GatewayTalkService.swift")
        let contractSource = try source(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Nile/Domain/HermesSessionContracts.swift"
            )
        )

        XCTAssertTrue([
            "protocol HermesLiveRuntimeStatusServing: Sendable",
            "HermesLiveRuntimeStatusServing,\n    Sendable\n{",
        ].allSatisfy(contractSource.contains))

        XCTAssertTrue([
            "private let sessions: GatewaySessionService",
            "private let turns: GatewayTurnService",
            "private let talk: GatewayTalkService", "sessions: sessions",
            "sessionClaim: sessions", "sessionRenaming: sessions",
            "turns: turns", "talk: talk",
            "prompts: turns", "HermesConnectionServing,", "GatewayConnecting,",
            "Self.projectedEvents(",
        ].allSatisfy(repositorySource.contains))
        XCTAssertFalse([
            "HermesSessionServing,", "HermesTurnServing,", "HermesTalkServing,",
            "private let rpc:", "private let dashboard:", "GatewaySessionCodec()",
            "GatewayStoredSessionCodec()", "func listSessions(",
            "func readStoredSession(", "func openSession(",
            "func liveRuntimeStatus(", "func createSession(",
            "func submitPrompt(", "func steer(", "func interrupt(",
        ].contains(where: repositorySource.contains))

        XCTAssertTrue([
            "struct GatewaySessionService: HermesSessionServing",
            "any GatewayRPCRequesting", "GatewayConnectionState",
            "any GatewayDashboardReading",
            "private let sessionCodec = GatewaySessionCodec()",
            "private let storedSessionCodec = GatewayStoredSessionCodec()",
            "func listSessions(", "func readStoredSessionSource(",
            "func readStoredSession(", "func openSession(",
            "func liveSessionStatus(", "func liveRuntimeStatus(",
            "func createSession(", "func renameSession(",
        ].allSatisfy(sessionSource.contains))
        XCTAssertFalse([
            "func submitPrompt(", "GatewayEventProjector",
        ].contains(where: sessionSource.contains))

        XCTAssertTrue([
            "struct GatewaySessionCodec: Sendable", "func decodeSessionList(",
            "func decodeLiveSession(", "func decodeStoredStatuses(",
            "func decodeRuntimeStatuses(", "func decodeSessionInfo(",
        ].allSatisfy(sessionCodecSource.contains))
        XCTAssertFalse([
            "func decodeMessages(", "StoredToolCall", "JSONSerialization",
        ].contains(where: sessionCodecSource.contains))
        XCTAssertTrue([
            "struct GatewayStoredSessionCodec: Sendable", "func decodeMessages(",
            "StoredToolCall", "func messageText(", "JSONSerialization",
        ].allSatisfy(storedSessionCodecSource.contains))
        XCTAssertFalse([
            "func decodeLiveSession(", "func decodeSessionList(",
            "func decodeRuntimeStatuses(", "func decodeSessionInfo(",
        ].contains(where: storedSessionCodecSource.contains))
        XCTAssertTrue([
            "enum GatewaySessionMessagePolicy",
            "static func isPrivateGoalContinuation(",
            "static func modelSwitchNotice(",
        ].allSatisfy(sessionMessagePolicySource.contains))
        XCTAssertFalse([
            "JSONValue", "HermesMessage", "StoredToolCall",
        ].contains(where: sessionMessagePolicySource.contains))
        for declaration in [
            "func decodeLiveSession(", "func decodeMessages(",
            "static func modelSwitchNotice(",
        ] {
            XCTAssertEqual(
                sessionCodecSources.filter { $0.contains(declaration) }.count,
                1
            )
        }

        XCTAssertTrue([
            "struct GatewayTurnService: HermesTurnServing",
            "any GatewayRPCRequesting", "func submitPrompt(", "func steer(",
            "func interrupt(", "requestMayHaveSucceeded: true",
        ].allSatisfy(turnSource.contains))
        XCTAssertFalse([
            "GatewayConnectionState", "GatewayDashboardReading",
            "GatewayEventProjector",
        ].contains(where: turnSource.contains))

        XCTAssertTrue([
            "struct GatewayTalkService: HermesTalkServing",
            "any HermesPromptServing", "any HermesLiveRuntimeStatusServing",
            "func submitPrompt(", "func liveRuntimeStatus(",
        ].allSatisfy(talkSource.contains))
        XCTAssertFalse([
            "GatewayRPCRequesting", "GatewayConnectionState",
            "GatewayEventProjector",
        ].contains(where: talkSource.contains))

        let lineCounts = [
            repositorySource,
            sessionSource,
            turnSource,
            talkSource,
        ].map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(lineCounts[0], 210)
        XCTAssertLessThan(lineCounts[1], 145)
        XCTAssertLessThan(lineCounts[2], 75)
        XCTAssertLessThan(lineCounts[3], 40)
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            460,
            "Do not hide connection/event repository growth behind services"
        )
        let codecLineCounts = sessionCodecSources.map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertTrue(zip(codecLineCounts, [150, 175, 50]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(codecLineCounts.reduce(0, +), 350)
    }

    func testGatewayAttachmentSpeechAndVoiceServicesOwnCapabilityTransport()
        throws
    {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let repositorySource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "TuiGatewayRepository.swift"
            )
        )
        let attachmentSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayAttachmentService.swift"
            )
        )
        let speechSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewaySpeechService.swift"
            )
        )
        let graphSource = try source(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Nile/App/NileAppGraph.swift"
            )
        )

        XCTAssertTrue(
            repositorySource.contains(
                "private let attachments: GatewayAttachmentService"
            )
        )
        XCTAssertTrue(
            repositorySource.contains(
                "private let speech: GatewaySpeechService"
            )
        )
        XCTAssertTrue(
            repositorySource.contains("attachmentReading: attachments")
        )
        XCTAssertTrue(
            repositorySource.contains("attachmentMutating: attachments")
        )
        XCTAssertTrue(repositorySource.contains("transcription: speech"))
        XCTAssertTrue(repositorySource.contains("speechSynthesis: speech"))
        XCTAssertTrue(
            repositorySource.contains(
                "var voiceService: any HermesVoiceServing"
            )
        )
        XCTAssertTrue(repositorySource.contains("private init<Signals>("))
        XCTAssertEqual(
            repositorySource.components(
                separatedBy: "let connectionState = GatewayConnectionState()"
            ).count - 1,
            1,
            "Construct shared connection state once in the designated initializer"
        )
        XCTAssertFalse(repositorySource.contains("HermesAttachmentServing,"))
        XCTAssertFalse(repositorySource.contains("HermesSpeechServing,"))
        XCTAssertFalse(repositorySource.contains("HermesVoiceServing,"))
        XCTAssertFalse(repositorySource.contains("func attachImage("))
        XCTAssertFalse(repositorySource.contains("func detachImage("))
        XCTAssertFalse(repositorySource.contains("func downloadAttachment("))
        XCTAssertFalse(repositorySource.contains("func synthesizeSpeech("))
        XCTAssertFalse(repositorySource.contains("func transcribeSpeech("))
        XCTAssertFalse(repositorySource.contains("func getHermesVoiceConfig("))
        XCTAssertFalse(repositorySource.contains("func setHermesVoice("))

        XCTAssertTrue(
            attachmentSource.contains(
                "struct GatewayAttachmentService: HermesAttachmentServing"
            )
        )
        XCTAssertTrue(attachmentSource.contains("any GatewayRPCRequesting"))
        XCTAssertTrue(
            attachmentSource.contains("GatewayConnectionState")
        )
        XCTAssertTrue(
            attachmentSource.contains("any GatewayDashboardReading")
        )
        XCTAssertTrue(attachmentSource.contains("func attachImage("))
        XCTAssertTrue(attachmentSource.contains("func detachImage("))
        XCTAssertTrue(attachmentSource.contains("func downloadAttachment("))
        XCTAssertTrue(
            attachmentSource.contains("requestMayHaveSucceeded: true")
        )
        XCTAssertFalse(attachmentSource.contains("func submitPrompt("))
        XCTAssertFalse(attachmentSource.contains("GatewayEventProjector"))
        XCTAssertFalse(attachmentSource.contains("GatewaySpeechCodec"))

        XCTAssertTrue(
            speechSource.contains("struct GatewaySpeechService:")
        )
        XCTAssertTrue(speechSource.contains("HermesSpeechServing,"))
        XCTAssertTrue(speechSource.contains("HermesVoiceServing,"))
        XCTAssertTrue(
            speechSource.contains("private let codec = GatewaySpeechCodec()")
        )
        XCTAssertTrue(speechSource.contains("GatewayConnectionState"))
        XCTAssertTrue(speechSource.contains("any GatewayDashboardReading"))
        XCTAssertTrue(speechSource.contains("func synthesizeSpeech("))
        XCTAssertTrue(speechSource.contains("func transcribeSpeech("))
        XCTAssertTrue(speechSource.contains("func getHermesVoiceConfig("))
        XCTAssertTrue(speechSource.contains("func setHermesVoice("))
        XCTAssertTrue(speechSource.contains("SpeechSynthesisUnavailableError"))
        XCTAssertTrue(
            speechSource.contains("SpeechTranscriptionUnavailableError")
        )
        XCTAssertFalse(speechSource.contains("GatewayRPCRequesting"))
        XCTAssertFalse(speechSource.contains("func attachImage("))
        XCTAssertFalse(speechSource.contains("GatewayEventProjector"))

        XCTAssertTrue(graphSource.contains("?? repository.voiceService"))

        let lineCounts = [repositorySource, attachmentSource, speechSource].map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertLessThan(lineCounts[0], 210)
        XCTAssertLessThan(lineCounts[1], 115)
        XCTAssertLessThan(lineCounts[2], 140)
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            450,
            "Do not hide repository growth behind capability service splits"
        )
    }

    func testGatewayCommandGoalServicesAndSpeechCodecOwnCapabilityValidation()
        throws
    {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let repositorySource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "TuiGatewayRepository.swift"
            )
        )
        let commandCodecSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayCommandCodec.swift"
            )
        )
        let commandServiceSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayCommandService.swift"
            )
        )
        let goalServiceSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayGoalService.swift"
            )
        )
        let speechCodecSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewaySpeechCodec.swift"
            )
        )

        XCTAssertTrue(
            repositorySource.contains(
                "private let commands: GatewayCommandService"
            )
        )
        XCTAssertTrue(
            repositorySource.contains("private let goals: GatewayGoalService")
        )
        XCTAssertFalse(repositorySource.contains("HermesCommandServing,"))
        XCTAssertFalse(repositorySource.contains("HermesGoalServing,"))
        XCTAssertFalse(repositorySource.contains("func commandsCatalog("))
        XCTAssertFalse(repositorySource.contains("func completeSlash("))
        XCTAssertFalse(repositorySource.contains("func executeCommand("))
        XCTAssertFalse(repositorySource.contains("func goalStatus("))
        XCTAssertFalse(repositorySource.contains("func setGoal("))
        XCTAssertFalse(repositorySource.contains("func pauseGoal("))
        XCTAssertFalse(repositorySource.contains("func resumeGoal("))
        XCTAssertFalse(repositorySource.contains("func clearGoal("))
        XCTAssertFalse(
            repositorySource.contains("private let speech = GatewaySpeechCodec()")
        )
        XCTAssertFalse(repositorySource.contains("func decodeCommandExecution"))
        XCTAssertFalse(repositorySource.contains("func decodeCommandPairs"))
        XCTAssertFalse(repositorySource.contains("func decodeSynthesizedSpeech"))
        XCTAssertFalse(repositorySource.contains("func requireVoiceMutationValue"))
        XCTAssertLessThan(
            repositorySource.components(separatedBy: .newlines).count,
            800,
            "Keep capability RPC implementations out of the transport repository"
        )

        XCTAssertTrue(
            commandServiceSource.contains(
                "struct GatewayCommandService: HermesCommandServing"
            )
        )
        XCTAssertTrue(
            commandServiceSource.contains("private let codec = GatewayCommandCodec()")
        )
        XCTAssertTrue(commandServiceSource.contains("any GatewayRPCRequesting"))
        XCTAssertTrue(commandServiceSource.contains("func commandsCatalog("))
        XCTAssertTrue(commandServiceSource.contains("func completeSlash("))
        XCTAssertTrue(commandServiceSource.contains("func executeCommand("))
        XCTAssertLessThan(
            commandServiceSource.components(separatedBy: .newlines).count,
            100,
            "Keep command transport independently reviewable"
        )

        XCTAssertTrue(
            goalServiceSource.contains(
                "struct GatewayGoalService: HermesGoalServing"
            )
        )
        XCTAssertTrue(
            goalServiceSource.contains(
                "private let commands: any HermesCommandServing"
            )
        )
        XCTAssertTrue(goalServiceSource.contains("func goalStatus("))
        XCTAssertTrue(goalServiceSource.contains("func setGoal("))
        XCTAssertTrue(goalServiceSource.contains("func pauseGoal("))
        XCTAssertTrue(goalServiceSource.contains("func resumeGoal("))
        XCTAssertTrue(goalServiceSource.contains("func clearGoal("))
        XCTAssertTrue(
            goalServiceSource.contains(
                "This Hermes profile shadows /goal"
            )
        )
        XCTAssertTrue(goalServiceSource.contains("GatewayMutationCodec"))
        XCTAssertTrue(goalServiceSource.contains("parseGoalSetNotice"))
        XCTAssertTrue(goalServiceSource.contains("parseGoalStatusOutput"))
        XCTAssertLessThan(
            goalServiceSource.components(separatedBy: .newlines).count,
            270,
            "Keep goal transport and its safety policy independently reviewable"
        )

        XCTAssertTrue(commandCodecSource.contains("struct GatewayCommandCodec"))
        XCTAssertTrue(commandCodecSource.contains("func decodeCatalog"))
        XCTAssertTrue(commandCodecSource.contains("func decodeCompletions"))
        XCTAssertTrue(commandCodecSource.contains("func decodeExecution"))
        XCTAssertTrue(
            commandCodecSource.contains("requestMayHaveSucceeded: true")
        )
        XCTAssertFalse(commandCodecSource.contains("rpc.request"))
        XCTAssertTrue(speechCodecSource.contains("struct GatewaySpeechCodec"))
        XCTAssertTrue(speechCodecSource.contains("func transcriptionMIMEType"))
        XCTAssertTrue(speechCodecSource.contains("func decodeSynthesis"))
        XCTAssertTrue(speechCodecSource.contains("func decodeTranscription"))
        XCTAssertTrue(speechCodecSource.contains("func decodeVoiceConfig"))
        XCTAssertFalse(speechCodecSource.contains("GatewayDashboardReading"))
    }

    func testGatewayRepositoryTestsHaveCapabilityOwnedSources() throws {
        let directory = repositoryRoot.appendingPathComponent("Tests/NileTests", isDirectory: true)
        let boundaries: [(file: String, count: Int, limit: Int, markers: [String])] = [
            ("TuiGatewayRepositorySessionHistoryTests.swift", 7, 300,
             ["testSessionOperationsUseExactMethodsParametersAndTimeouts",
              "testStoredReadsUseActiveConnectionExactPathsAndStrictCodec"]),
            ("TuiGatewayRepositoryTurnBlockingTests.swift", 5, 225,
             ["testPromptSteerAndInterruptMutationContracts",
              "testMalformedBlockingMutationResultsFailClosedAsUncertain"]),
            ("TuiGatewayRepositoryAttachmentCommandTests.swift", 4, 275,
             ["testAttachmentRPCsUseExactHermesContracts",
              "testIncompleteDiscoveryAndMalformedCommandResultsFailClosed"]),
            ("TuiGatewayRepositoryModelTests.swift", 4, 275,
             ["testModelOptionsAndSessionControlsUseExactTypedContracts",
              "testMalformedModelMutationsAreUncertainAndUnsafeFlagsNeverSend"]),
            ("TuiGatewayRepositorySpeechVoiceTests.swift", 4, 350,
             ["testSpeechAndVoiceConfigurationUseExactDashboardContracts",
              "testVoiceConfigurationRequiresStrictNonBlankStrings"]),
            ("TuiGatewayRepositoryGoalUsageTests.swift", 5, 250,
             ["testGoalSetUsesCollisionFenceBudgetAndStrictDispatch",
              "testGatewayStatsUsesAuthenticatedExactDashboardQuery"]),
            ("TuiGatewayRepositoryEventDelegationTests.swift", 4, 400,
             ["testEventStreamPreservesSignalOrderAndProjectsTerminalFailureLast",
              "testDelegationProtocolRejectsMalformedStatusAndSnapshotRows"]),
        ]
        let base = try source(at: directory.appendingPathComponent("TuiGatewayRepositoryTests.swift"))
        let support = try source(at: directory.appendingPathComponent("TuiGatewayRepositoryTestSupport.swift"))
        var sources = [base, support]
        var testNames: [String] = []
        for boundary in boundaries {
            let boundarySource = try source(at: directory.appendingPathComponent(boundary.file))
            let names = architectureTestNames(in: boundarySource)
            XCTAssertEqual(names.count, boundary.count)
            XCTAssertLessThan(boundarySource.components(separatedBy: .newlines).count, boundary.limit)
            boundary.markers.forEach { XCTAssertTrue(names.contains($0)) }
            testNames.append(contentsOf: names)
            sources.append(boundarySource)
        }
        XCTAssertEqual(architectureTestNames(in: base), [])
        XCTAssertEqual(architectureTestNames(in: support), [])
        XCTAssertLessThan(base.components(separatedBy: .newlines).count, 10)
        XCTAssertLessThan(support.components(separatedBy: .newlines).count, 300)
        XCTAssertEqual(testNames.count, 33)
        XCTAssertEqual(Set(testNames).count, 33)
        XCTAssertLessThan(sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 2_150)

        let declarations = ["struct RPCRequest", "actor RecordingRPC",
                            "struct DashboardRequest", "actor RecordingDashboard",
                            "struct QueryDashboardRequest", "actor QueryRecordingDashboard",
                            "struct VoiceDashboardCall", "actor RecordingVoiceDashboard",
                            "actor NoopConnectionClient", "func XCTAssertThrowsErrorAsync"]
        for declaration in declarations {
            XCTAssertTrue(support.contains(declaration))
            XCTAssertEqual(sources.map {
                $0.components(separatedBy: declaration).count - 1
            }.reduce(0, +), 1)
        }
    }

}
