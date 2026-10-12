import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testNileAppGraphSeparatesProductionFixtureAndRouteResponsibilities()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let graphSource = try source(in: appDirectory, named: "NileAppGraph.swift")
        let fixtureSource = try source(in: appDirectory, named: "NileAppGraphFixtures.swift")
        let collaboratorSource = try source(in: appDirectory, named: "NileAppGraphFixtureCollaborators.swift")
        let planSource = try source(in: appDirectory, named: "NileAppGraphFixturePlan.swift")
        let sessionPolicySource = try source(in: appDirectory, named: "NileSessionFixturePolicy.swift")
        let assemblySource = try source(in: appDirectory, named: "NileAppGraphFixtureAssembly.swift")
        let installerSource = try source(in: appDirectory, named: "NileAppGraphFixtureInstaller.swift")
        let routePolicySource = try source(in: appDirectory, named: "TurnNotificationRoutePolicy.swift")
        let appSurfaceSources = try ["NileApp.swift", "BiometricAppLockOverlay.swift", "NotificationEducationView.swift"].map { try source(in: appDirectory, named: $0) }
        let appLockSources = try ["BiometricAppLock.swift", "BiometricAppLockContracts.swift", "BiometricAppLockStore.swift", "LocalBiometricAuthenticator.swift"].map { try source(in: appDirectory, named: $0) }
        let notificationDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/Core/Notifications", isDirectory: true)
        let notificationSources = try [
            "TurnNotificationRouting.swift",
            "TurnNotificationController.swift",
            "NotificationEducation.swift",
            "NileAppDelegate.swift",
        ].map { try source(in: notificationDirectory, named: $0) }

        for marker in ["let fixturePlan =", "NileAppGraphFixturePlan(arguments:", "NileAppGraphFixtureInstaller.install(", "TuiGatewayRepository("] { XCTAssertTrue(graphSource.contains(marker)) }
        XCTAssertEqual(graphSource.components(separatedBy: "TuiGatewayRepository(").count - 1, 1)
        for marker in ["--nile-fixture-", "NileDebugFixturePolicy", "SessionListFixture?", "StreamingTranscriptFixture", "GatewayVisualFixtureProfileStore", "TalkFixtureVoiceInput", "gatewayStatsReferenceDate", "streamingStressFragments", "enum TurnNotificationGatewayDecision", "struct TurnNotificationRoutePolicy"] { XCTAssertFalse(graphSource.contains(marker)) }

        XCTAssertTrue(fixtureSource.contains("enum NileAppGraphFixtures {"))
        XCTAssertTrue(collaboratorSource.contains("extension NileAppGraphFixtures {"))
        for source in [fixtureSource, collaboratorSource, planSource, sessionPolicySource, assemblySource, installerSource] {
            XCTAssertTrue(source.contains("#if DEBUG || NILE_LOCAL_RELEASE"))
        }
        XCTAssertTrue(planSource.contains("#else\nstruct NileAppGraphFixturePlan"))
        XCTAssertTrue(assemblySource.contains("#else\nextension NileAppGraphFixturePlan"))
        XCTAssertTrue(installerSource.contains("#else\n@MainActor\nenum NileAppGraphFixtureInstaller"))
        let fixtureBoundaries = [fixtureSource, collaboratorSource]
        for (declaration, owner) in [
            ("enum StreamingTranscriptFixture {", fixtureSource),
            ("enum ComposerActivityFixture {", fixtureSource),
            ("static func gatewayStats(", fixtureSource),
            ("actor GatewayVisualFixtureProfileStore", collaboratorSource),
            ("class TalkFixtureVoiceInput", collaboratorSource),
            ("actor HermesVoiceFixtureService", collaboratorSource),
        ] {
            XCTAssertTrue(owner.contains(declaration))
            XCTAssertEqual(fixtureBoundaries.filter { $0.contains(declaration) }.count, 1)
        }

        XCTAssertTrue(planSource.contains("struct NileAppGraphFixturePlan {"))
        XCTAssertTrue(planSource.contains("enum GatewayVisualFixture: Equatable {"))
        XCTAssertTrue(planSource.contains("NileDebugFixturePolicy.arguments(from:"))
        XCTAssertTrue(planSource.contains("--nile-performance-streaming-stress"))
        for marker in [
            "static func streamingTranscript(",
            "static func recoveryPhase(",
            "static func sessionFixture(",
        ] {
            XCTAssertTrue(sessionPolicySource.contains(marker))
            XCTAssertEqual(
                [planSource, sessionPolicySource]
                    .filter { $0.contains(marker) }.count,
                1
            )
        }
        for marker in [
            "NileSessionFixturePolicy.streamingTranscript(",
            "NileSessionFixturePolicy.recoveryPhase(",
            "NileSessionFixturePolicy.sessionFixture(",
        ] {
            XCTAssertTrue(planSource.contains(marker))
        }
        for forbidden in [
            "NileDebugFixturePolicy", "GatewayProfile(",
            "SessionListModel(", "TuiGatewayRepository(",
            "GatewayAuthenticationService(",
        ] {
            XCTAssertFalse(sessionPolicySource.contains(forbidden))
        }
        for movedArgument in [
            "--nile-fixture-blocking-clarification",
            "--nile-fixture-blocking-secret",
            "--nile-fixture-visual-model-picker",
            "--nile-fixture-goal-active",
        ] {
            XCTAssertFalse(planSource.contains(movedArgument))
            XCTAssertTrue(sessionPolicySource.contains(movedArgument))
        }
        let assemblyMethods = [
            "makeBiometricAppLockFixture()", "makeGatewayProfileStoreFixture()",
            "makeGatewayConnectionClientFixture()", "makeGatewaySessionCleanerFixture()",
            "makeHermesVoiceServiceFixture()", "configureGatewaySetupFixture(",
            "makeSessionListFixture()",
        ]
        for method in assemblyMethods {
            XCTAssertFalse(planSource.contains(method))
            XCTAssertTrue(assemblySource.contains(method))
            let owners = [planSource, assemblySource].filter { $0.contains(method) }.count
            XCTAssertEqual(owners, 1, "Keep \(method) in the fixture assembly boundary")
        }
        XCTAssertTrue(assemblySource.contains("extension NileAppGraphFixturePlan {"))
        for forbidden in ["GatewayProfile(", "SessionListModel("] { XCTAssertFalse(planSource.contains(forbidden)) }
        for forbidden in ["--nile-fixture-", "NileDebugFixturePolicy"] { XCTAssertFalse(assemblySource.contains(forbidden)) }
        for source in [planSource, assemblySource] {
            XCTAssertFalse(source.contains("TuiGatewayRepository("))
            XCTAssertFalse(source.contains("GatewayAuthenticationService("))
        }

        XCTAssertTrue(installerSource.contains("enum NileAppGraphFixtureInstaller"))
        XCTAssertTrue(installerSource.contains("installStatistics("))
        XCTAssertTrue(installerSource.contains("installStreamingTranscript("))
        XCTAssertTrue(installerSource.contains("installStreamingStress("))
        XCTAssertTrue(installerSource.contains("installActivePlan("))
        XCTAssertFalse(installerSource.contains("TuiGatewayRepository("))
        XCTAssertFalse(installerSource.contains("GatewaySetupModel("))

        XCTAssertTrue(routePolicySource.contains("enum TurnNotificationGatewayDecision: Equatable"))
        XCTAssertTrue(routePolicySource.contains("struct TurnNotificationRoutePolicy"))
        XCTAssertTrue(routePolicySource.contains("static func initialGatewayDecision("))
        XCTAssertTrue(routePolicySource.contains("static func sessionDecision("))
        XCTAssertFalse(routePolicySource.contains("NileAppGraphFixtures"))

        let lineCounts = [graphSource, fixtureSource, collaboratorSource, planSource,
                          assemblySource, installerSource, routePolicySource,
                          sessionPolicySource]
            .map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(
            lineCounts[0],
            250,
            "Keep fixture policy, state installation, and route policy out of app wiring"
        )
        XCTAssertLessThan(
            lineCounts[1],
            250,
            "Keep deterministic fixture states independently reviewable"
        )
        XCTAssertLessThan(lineCounts[2], 200)
        XCTAssertLessThan(lineCounts[3], 210)
        XCTAssertLessThan(lineCounts[4], 200)
        XCTAssertLessThan(lineCounts[5], 260)
        XCTAssertLessThan(lineCounts[6], 100)
        XCTAssertLessThan(lineCounts[7], 110)
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_450,
            "Do not hide app-graph growth across its dedicated boundaries"
        )

        let notificationDeclarations = [
            ["struct TurnNotificationRoute:", "final class TurnNotificationRouteCenter"],
            ["protocol BackgroundExecutionOperating:", "final class IOSTurnBackgroundController"],
            ["protocol NotificationPermissionManaging:", "final class NotificationEducationModel"],
            ["final class NileAppDelegate:"],
        ]
        for (notificationSource, declarations) in zip(notificationSources, notificationDeclarations) {
            for declaration in declarations {
                XCTAssertTrue(notificationSource.contains(declaration))
                XCTAssertEqual(
                    notificationSources.filter { $0.contains(declaration) }.count,
                    1,
                    "Keep \(declaration) in one notification boundary"
                )
            }
        }
        XCTAssertFalse(notificationSources[0].contains("import UserNotifications"))
        XCTAssertFalse(notificationSources[1].contains("NotificationEducationModel"))
        XCTAssertFalse(notificationSources[2].contains("IOSTurnBackgroundController"))
        XCTAssertFalse(notificationSources[3].contains("NotificationPermissionManaging"))
        let notificationLines = notificationSources.map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertTrue(zip(notificationLines, [80, 180, 150, 70]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(notificationLines.reduce(0, +), 430)

        let rootSource = appSurfaceSources[0], lockSource = appSurfaceSources[1], educationSource = appSurfaceSources[2]
        for (source, markers) in [(rootSource, ["@main", "private struct GatewayRootView: View", "BiometricAppLockWindowBridge(model:", "NotificationEducationView(", "private struct NileLoadingView: View"]), (lockSource, ["struct BiometricAppLockWindowBridge: UIViewRepresentable", "private struct BiometricAppLockView: View", "UIWindow.Level.alert.rawValue + 1", "accessibilityViewIsModal = true", "overlayWindow.makeKeyAndVisible()"]), (educationSource, ["struct NotificationEducationView: View", "NotificationEducationButtonStyle", "model.enableNotifications()"])] {
            for marker in markers { XCTAssertTrue(source.contains(marker)) }
        }
        for declaration in ["struct BiometricAppLockWindowBridge:", "struct NotificationEducationView:", "struct NileLoadingView:"] {
            XCTAssertEqual(appSurfaceSources.filter { $0.contains(declaration) }.count, 1)
        }
        XCTAssertFalse(lockSource.contains("NileAppGraph") || lockSource.contains("NotificationEducationModel"))
        XCTAssertFalse(educationSource.contains("NileAppGraph") || educationSource.contains("BiometricAppLockModel"))
        let appSurfaceLines = appSurfaceSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(appSurfaceLines, [190, 225, 85]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(appSurfaceLines.reduce(0, +), 480)
        let lockBoundaries: [(markers: [String], excluded: [String])] = [
            (["final class BiometricAppLockModel", "@ObservationIgnored private var backgroundGeneration", "func appDidEnterBackground()", "func unlock() async"], ["LAContext", "LAError", "private let defaults:", "defaults.bool(", "import LocalAuthentication"]),
            (["enum NileBiometryKind", "struct NileBiometricCapability", "enum NileBiometricAuthenticationFailure", "protocol BiometricAppLockStoring", "protocol BiometricAuthenticating"], ["@Observable", "LAContext", "UserDefaults"]),
            (["final class UserDefaultsBiometricAppLockStore", "security.biometric_app_lock.enabled.v1"], ["@Observable", "LAContext", "LocalAuthentication"]),
            (["final class LocalBiometricAuthenticator", "import LocalAuthentication", "LAContext()", "NileBiometricAuthenticationFailure"], ["@Observable", "UserDefaults", "BiometricAppLockModel"]),
        ]
        for (source, boundary) in zip(appLockSources, lockBoundaries) { boundary.markers.forEach { XCTAssertTrue(source.contains($0)) }; boundary.excluded.forEach { XCTAssertFalse(source.contains($0)) } }
        for declaration in ["final class BiometricAppLockModel", "enum NileBiometryKind", "final class UserDefaultsBiometricAppLockStore", "final class LocalBiometricAuthenticator"] { XCTAssertEqual(appLockSources.filter { $0.contains(declaration) }.count, 1) }
        let appLockLines = appLockSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(appLockLines, [200, 80, 35, 110]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(appLockLines.reduce(0, +), 390)
    }

    func testAccessibilityIDsHaveFeatureOwnedSources() throws {
        let directory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/App", isDirectory: true
        )
        let base = try source(in: directory, named: "NileAccessibilityID.swift")
        let boundaries: [(file: String, markers: [String], limit: Int)] = [
            ("NileAccessibilityIDAppGateway.swift", ["static let addGateway =", "static let biometricLock =", "static func hermesVoicePreset(", "private static func stableVoiceKey("], 95),
            ("NileAccessibilityIDComposer.swift", ["static let composer =", "static let talkSurface =", "static let attachmentStrip =", "static func statsPeriod("], 60),
            ("NileAccessibilityIDDelegation.swift", ["static let delegationOverview =", "static func delegationAgentRow(", "static func delegationStop("], 40),
            ("NileAccessibilityIDGoalPrompt.swift", ["static let goalButton =", "static let blockingPrompt =", "static func blockingPrompt(", "static func goalBudget("], 40),
            ("NileAccessibilityIDModel.swift", ["static let commandPalette =", "static let modelPicker =", "static func composerModelOption(", "private static func modelPinKey("], 90),
            ("NileAccessibilityIDSession.swift", ["static let sessionShell =", "static let renameSession =", "static func sessionPill(", "static func sessionPin("], 60),
            ("NileAccessibilityIDTranscript.swift", ["static let transcript =", "static let sessionLaunchpad =", "static func markdownTableCell(", "static func messageAttachment("], 55),
        ]
        let sources = try boundaries.map { try source(in: directory, named: $0.file) }

        XCTAssertEqual(base.trimmingCharacters(in: .whitespacesAndNewlines), "enum NileAccessibilityID {}")
        XCTAssertFalse(base.contains("static let") || base.contains("static func"))
        for (index, boundary) in boundaries.enumerated() {
            XCTAssertEqual(sources[index].components(separatedBy: "extension NileAccessibilityID").count - 1, 1)
            boundary.markers.forEach { marker in
                XCTAssertTrue(sources[index].contains(marker))
                XCTAssertEqual(sources.filter { $0.contains(marker) }.count, 1)
            }
            XCTAssertLessThan(sources[index].components(separatedBy: .newlines).count, boundary.limit)
        }
        let inventory = sources.joined(separator: "\n")
        XCTAssertEqual(inventory.components(separatedBy: "\n    static let ").count - 1, 153)
        XCTAssertEqual(inventory.components(separatedBy: "\n    static func ").count - 1, 34)
        XCTAssertEqual(inventory.components(separatedBy: "\n    private static func ").count - 1, 2)
        XCTAssertEqual(inventory.components(separatedBy: "\"niles.").count - 1, 187)
        XCTAssertEqual(inventory.components(separatedBy: "private static func stableVoiceKey(").count - 1, 1)
        XCTAssertEqual(inventory.components(separatedBy: "private static func modelPinKey(").count - 1, 1)
        XCTAssertLessThan(sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 370)
    }

    func testDomainContractsHaveFeatureOwnedSources() throws {
        let domainDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Domain",
            isDirectory: true
        )
        let contracts: [(name: String, declarations: [String])] = [
            ("GatewayContracts.swift", ["struct GatewayProfile:", "struct HermesError:", "protocol HermesConnectionServing:"]),
            ("HermesSessionContracts.swift", ["struct HermesSession:", "protocol HermesSessionClaimServing:", "protocol HermesSessionRenaming:", "protocol HermesSessionServing:", "protocol HermesBlockingPromptServing:"]),
            ("HermesEventContracts.swift", ["enum HermesStreamEvent:", "protocol HermesEventStreaming:"]),
            ("HermesModelContracts.swift", ["struct ModelOptions:", "protocol HermesModelOptionsServing:", "protocol HermesModelMutationServing:"]),
            ("HermesUsageContracts.swift", ["struct SessionUsage:", "struct GatewayStats:", "protocol HermesSessionUsageServing:", "protocol HermesGatewayStatsServing:", "protocol HermesUsageServing:"]),
            ("HermesMediaContracts.swift", ["struct DownloadedAttachment:", "protocol HermesAttachmentReading:", "protocol HermesSpeechServing:"]),
            ("HermesDelegationContracts.swift", ["struct DelegationStatus:", "protocol HermesDelegationServing:"]),
            ("HermesCommandContracts.swift", ["struct CommandCatalog:", "protocol HermesCommandServing:"]),
            ("GoalModels.swift", ["struct HermesGoal:", "protocol HermesGoalStatusServing:", "protocol HermesGoalServing:"]),
        ]
        let sources = try contracts.map {
            try source(at: domainDirectory.appendingPathComponent($0.name))
        }
        let endpointBoundaries: [(name: String, markers: [String], excluded: [String], cap: Int)] = [
            (
                "GatewayEndpoint.swift",
                ["struct GatewayEndpoint:", "struct GatewayEndpointError:", "func apiURL(", "func webSocketURL(", "percentEncodeQueryValue("],
                ["URLComponents", "validateProxyPrefix", "CleartextPermission", "struct GatewayConnection:"],
                105
            ),
            (
                "GatewayEndpointParser.swift",
                ["enum GatewayEndpointParser", "static func parse(", "URLComponents", "validateProxyPrefix(", "validatePort("],
                ["CleartextPermission", "struct GatewayConnection:", "percentEncodeQueryValue("],
                190
            ),
            (
                "GatewayConnection.swift",
                ["enum CleartextPermission:", "struct GatewayConnection:", "cleartextPermission.allowsCleartext"],
                ["URLComponents", "validateProxyPrefix(", "percentEncodeQueryValue("],
                85
            ),
        ]
        let endpointSources = try endpointBoundaries.map {
            try source(in: domainDirectory, named: $0.name)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: domainDirectory
                    .appendingPathComponent("Models.swift").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: domainDirectory
                    .appendingPathComponent("HermesRepository.swift").path
            )
        )
        for (index, contract) in contracts.enumerated() {
            for declaration in contract.declarations {
                XCTAssertTrue(
                    sources[index].contains(declaration),
                    "Keep \(declaration) in \(contract.name)"
                )
                XCTAssertEqual(
                    sources.filter { $0.contains(declaration) }.count,
                    1,
                    "Keep \(declaration) under one domain owner"
                )
            }
        }
        let lineCounts = sources.map {
            $0.components(separatedBy: .newlines).count
        }
        XCTAssertTrue(
            lineCounts.allSatisfy { $0 < 220 },
            "Keep each domain capability inventory independently reviewable"
        )
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_300,
            "Do not hide domain growth behind contract source splits"
        )
        XCTAssertFalse(
            sources.joined(separator: "\n").contains(
                "protocol HermesRepository:"
            )
        )
        for (index, boundary) in endpointBoundaries.enumerated() {
            boundary.markers.forEach { XCTAssertTrue(endpointSources[index].contains($0)) }
            boundary.excluded.forEach { XCTAssertFalse(endpointSources[index].contains($0)) }
            XCTAssertLessThan(endpointSources[index].components(separatedBy: .newlines).count, boundary.cap)
        }
        for declaration in ["struct GatewayEndpoint:", "enum GatewayEndpointParser", "enum CleartextPermission:", "struct GatewayConnection:"] {
            XCTAssertEqual(endpointSources.filter { $0.contains(declaration) }.count, 1)
        }
        XCTAssertLessThan(
            endpointSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +),
            350
        )
    }

    func testDesignSystemHasFeatureOwnedSourcesAndNoDeadRenderer() throws {
        let designDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Core/Design",
            isDirectory: true
        )
        let boundaries: [(
            name: String, declarations: [String], limit: Int
        )] = [
            (
                "NileDesignTokens.swift",
                ["enum NileColors {", "enum NileRadii {", "enum NileMotion {", "enum NileTactilePressFeedback {", "struct NileTactileButtonStyle:"], 150
            ),
            (
                "NileTypography.swift",
                ["enum NileTypography {", "static let bodyLargeStyle", "static let brandStyle", "static func font("], 200
            ),
            (
                "NileTypographyMetrics.swift",
                ["extension NileTypography {", "struct TextStyle {", "func scaledUIFont(", "extension DynamicTypeSize {"], 140
            ),
            (
                "NileDesignModifiers.swift",
                ["struct NilePanelModifier:", "struct NileGlassModifier:", "struct NileGlassButtonModifier:", "struct NileGlassIconButtonModifier:", "struct NileTextStyleModifier:"], 225
            ),
            (
                "NileComposeText.swift",
                ["struct NileComposeText:", "struct NileMeasuredComposeText:"], 115
            ),
            (
                "NileTextMeasurement.swift",
                ["enum NileTextMeasurement {", "static func height(", "static func lineCount(", "static func letterSpacingPixels("], 145
            ),
            (
                "NileMarkdown.swift",
                ["struct NileMarkdownText: View", "struct MarkdownBlockView: View", "struct MarkdownCodeBlock: View"], 225
            ),
            ("NileMarkdownContracts.swift", ["enum MarkdownTableAlignment:", "struct MarkdownTableColumn:", "enum MarkdownBlock:"], 35),
            ("NileMarkdownBlockCache.swift", ["private final class MarkdownBlockBox:", "final class MarkdownBlockCache:", "func blocks("], 55),
            ("NileMarkdownParser.swift", ["func parseMarkdownBlocks(", "private func markdownTableAlignments(", "private func markdownTableCells("], 275),
            (
                "NileMarkdownInline.swift",
                ["struct MarkdownListRow: View", "struct MarkdownTextStyleModifier: ViewModifier", "func styledInlineMarkdown("], 110
            ),
            (
                "NileMarkdownTable.swift",
                ["enum MarkdownTablePresentation:", "struct MarkdownTable: View", "struct MarkdownTableCell: View"], 325
            ),
            (
                "NileMaterialIcon.swift",
                ["struct NileMaterialIcon: View", "enum Kind {", "private var symbolName: String"], 60
            ),
        ]
        let sources = try boundaries.map {
            try source(at: designDirectory.appendingPathComponent($0.name))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: designDirectory
                    .appendingPathComponent("NileDesign.swift").path
            )
        )
        for (index, boundary) in boundaries.enumerated() {
            for declaration in boundary.declarations {
                XCTAssertTrue(
                    sources[index].contains(declaration),
                    "Keep \(declaration) in \(boundary.name)"
                )
                XCTAssertEqual(
                    sources.filter { $0.contains(declaration) }.count,
                    1,
                    "Keep \(declaration) under one design-system owner"
                )
            }
        }

        XCTAssertFalse(sources.joined(separator: "\n").contains("NileTextLabel"))
        XCTAssertFalse(sources.joined(separator: "\n").contains("var nileRGBA:"))
        XCTAssertEqual(
            sources.filter { $0.contains("import NileTextRenderer") }.count,
            1,
            "Only live text measurement should import the renderer"
        )
        for forbidden in ["import UIKit", "struct TextStyle", "func scaledUIFont(", "extension DynamicTypeSize"] { XCTAssertFalse(sources[1].contains(forbidden)) }
        for forbidden in ["static let bodyLargeStyle", "static let brandStyle", "static func font(", "import NileTextRenderer"] { XCTAssertFalse(sources[2].contains(forbidden)) }
        XCTAssertTrue(sources[5].contains("import NileTextRenderer"))
        XCTAssertFalse(sources[6].contains("func parseMarkdownBlocks("))
        XCTAssertFalse(sources[6].contains("struct MarkdownTable: View"))
        XCTAssertFalse(sources[7].contains("func parseMarkdownBlocks("))
        XCTAssertFalse(sources[7].contains("NSCache"))
        XCTAssertTrue(sources[8].contains("parseMarkdownBlocks(content"))
        for forbidden in ["NSRegularExpression", "func markdownTableCells("] { XCTAssertFalse(sources[8].contains(forbidden)) }
        for forbidden in ["final class MarkdownBlockCache", "NSCache<", "NSLock"] { XCTAssertFalse(sources[9].contains(forbidden)) }
        for index in [7, 8, 9] { XCTAssertFalse(sources[index].contains(": View")) }
        for removedPath in ["private var path: Path", "private static var", "Path {", "CGPoint(", "CGRect("] { XCTAssertFalse(sources[12].contains(removedPath)) }
        XCTAssertEqual(sources[12].components(separatedBy: "case .").count - 1, 9)

        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        for (index, count) in lineCounts.enumerated() {
            XCTAssertLessThan(
                count,
                boundaries[index].limit,
                "Keep \(boundaries[index].name) independently reviewable"
            )
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_825,
            "Do not hide design-system growth behind source splits"
        )
    }

    func testSessionRepositoryCompositionUsesExplicitCapabilityBundle() throws {
        let sourceDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile",
            isDirectory: true
        )
        let modelSource = try source(
            at: sourceDirectory.appendingPathComponent(
                "App/SessionListModel.swift"
            )
        )
        let contractSource = try source(
            at: sourceDirectory.appendingPathComponent(
                "Domain/HermesSessionContracts.swift"
            )
        )
        let capabilitiesSource = try source(
            at: sourceDirectory.appendingPathComponent(
                "Domain/SessionRepositoryCapabilities.swift"
            )
        )
        let compositionSource = try source(
            at: sourceDirectory.appendingPathComponent(
                "App/SessionRuntimeComposition.swift"
            )
        )
        let gatewaySource = try source(
            at: sourceDirectory.appendingPathComponent(
                "Data/Gateway/TuiGatewayRepository.swift"
            )
        )

        XCTAssertFalse(contractSource.contains("protocol HermesRepository:"))
        XCTAssertTrue(
            modelSource.contains(
                "repository capabilityProvider:\n"
                    + "            any SessionRepositoryCapabilityProviding"
            )
        )
        XCTAssertTrue(
            modelSource.contains(
                "SessionRuntimeComposition.production("
            )
        )
        XCTAssertFalse(
            modelSource.contains(
                "let capabilities = capabilityProvider.sessionCapabilities"
            )
        )
        XCTAssertTrue(
            compositionSource.contains(
                "let capabilities = capabilityProvider.sessionCapabilities"
            )
        )
        XCTAssertFalse(modelSource.contains("any HermesRepository"))
        XCTAssertTrue(
            capabilitiesSource.contains(
                "struct SessionRepositoryCapabilities: Sendable"
            )
        )
        XCTAssertTrue(
            capabilitiesSource.contains(
                "protocol SessionRepositoryCapabilityProviding: Sendable"
            )
        )
        for marker in ["let sessions: any HermesSessionServing", "let sessionClaim: any HermesSessionClaimServing", "let sessionRenaming: any HermesSessionRenaming", "let turns: any HermesTurnServing", "let blockingPrompts: any HermesBlockingPromptServing", "let sessionUsage: any HermesSessionUsageServing", "let gatewayStatistics: any HermesGatewayStatsServing"] { XCTAssertTrue(capabilitiesSource.contains(marker)) }
        XCTAssertFalse(capabilitiesSource.contains("sessionControl") || capabilitiesSource.contains("HermesSessionControlServing"))
        XCTAssertFalse(capabilitiesSource.contains("let usage: any HermesUsageServing"))
        XCTAssertFalse(
            capabilitiesSource.contains("HermesConnectionServing")
        )
        XCTAssertFalse(capabilitiesSource.contains("HermesVoiceServing"))
        XCTAssertTrue(
            gatewaySource.contains("SessionRepositoryCapabilityProviding")
        )
        for marker in ["sessionClaim: sessions", "sessionRenaming: sessions", "delegation: delegation", "commands: commands", "goals: goals", "sessionUsage: usage", "gatewayStatistics: usage"] { XCTAssertTrue(gatewaySource.contains(marker)) }
        XCTAssertFalse(
            gatewaySource.contains(
                "SessionRepositoryCapabilities(unified: self)"
            )
        )
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Capability composition must retain one model application boundary"
        )
    }

    func testSessionRuntimeCompositionOwnsProductionAndFixtureWiring()
        throws
    {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let compositionSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionRuntimeComposition.swift"
            )
        )

        XCTAssertTrue(
            modelSource.contains("SessionRuntimeComposition.production(")
        )
        XCTAssertTrue(
            modelSource.contains("SessionRuntimeComposition.fixture(")
        )
        XCTAssertTrue(
            modelSource.contains(
                "@ObservationIgnored let runtimes: "
                    + "SessionRuntimeComposition"
            )
        )
        XCTAssertFalse(modelSource.contains("private let eventRuntime"))
        XCTAssertFalse(modelSource.contains("private let navigationRuntime"))
        XCTAssertFalse(modelSource.contains("private let turnRuntime"))
        XCTAssertFalse(modelSource.contains("runtimeComposition."))
        XCTAssertFalse(
            modelSource.contains(
                "let capabilities = capabilityProvider.sessionCapabilities"
            )
        )
        for constructor in [
            "SessionGatewayContextRuntime(", "SessionLifecycleRuntime(",
            "SessionEventRuntime(",
            "SessionNavigationRuntime(",
            "SessionTurnRuntime(",
            "SessionTalkRuntime(",
            "SessionClaimRuntime(", "SessionRenameRuntime(",
            "SessionAttachmentRuntime(",
            "SessionDraftLifecycleRuntime(",
            "SessionBlockingPromptRuntime(",
        ] {
            XCTAssertFalse(
                modelSource.contains(constructor),
                "Keep \(constructor) construction out of the app model"
            )
            XCTAssertTrue(compositionSource.contains(constructor))
        }
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            4_800,
            "Keep feature-runtime construction out of the app model"
        )

        XCTAssertTrue(
            compositionSource.contains(
                "struct SessionRuntimeComposition"
            )
        )
        for capability in [
            "events",
            "sessions",
            "sessionClaim", "sessionRenaming",
            "turns",
            "talk",
            "delegation",
            "blockingPrompts",
            "models",
            "sessionUsage",
            "gatewayStatistics",
            "attachmentReading",
            "attachmentMutating",
            "prompts",
            "disconnect",
            "transcription",
            "speechSynthesis",
            "commands",
            "goals",
        ] {
            XCTAssertTrue(
                compositionSource.contains("capabilities.\(capability)"),
                "Composition must narrow the \(capability) capability"
            )
        }
        XCTAssertTrue(
            compositionSource.contains("voice: voiceInputRuntime")
        )
        XCTAssertTrue(
            compositionSource.contains("speech: speechRuntime")
        )
        XCTAssertTrue(
            compositionSource.contains("composerRuntime: composerRuntime")
        )
        XCTAssertTrue(
            compositionSource.contains(
                "persistenceRuntime: draftPersistenceRuntime"
            )
        )
        XCTAssertTrue(
            compositionSource.contains("navigationRuntime: navigationRuntime")
        )
        XCTAssertLessThan(
            compositionSource.components(separatedBy: .newlines).count,
            250,
            "Keep session runtime construction independently reviewable"
        )
    }

}
