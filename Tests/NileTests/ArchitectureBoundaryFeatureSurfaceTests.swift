import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testSessionFixturesHaveCapabilityOwnedSourceBoundaries() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(
            at: appDirectory.appendingPathComponent("SessionListModel.swift")
        )
        let catalogSource = try source(
            at: appDirectory.appendingPathComponent("SessionListFixture.swift")
        )
        let controlSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionControlFixture.swift"
            )
        )
        let transcriptSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionTranscriptFixture.swift"
            )
        )
        let presentationSource = try source(
            at: appDirectory.appendingPathComponent(
                "SessionTranscriptPresentationFixture.swift"
            )
        )
        let fixtureSources = [
            catalogSource, controlSource, transcriptSource, presentationSource,
        ]

        XCTAssertFalse(modelSource.contains("enum SessionListFixture"))
        XCTAssertFalse(modelSource.contains("iVBORw0KGgoAAA"))
        XCTAssertTrue(modelSource.contains("#if DEBUG || NILE_LOCAL_RELEASE\n    init(\n        fixture: SessionListFixture"))
        XCTAssertTrue(catalogSource.contains("enum SessionListFixture"))
        XCTAssertTrue(catalogSource.contains("case androidVisualBrand"))
        XCTAssertFalse(catalogSource.contains("var blockingEvents"))
        XCTAssertFalse(catalogSource.contains("var transcriptEntries"))
        XCTAssertFalse(catalogSource.contains("var modelPickerOptions"))
        XCTAssertFalse(catalogSource.contains("iVBORw0KGgoAAA"))
        XCTAssertTrue(controlSource.contains("var blockingEvents"))
        XCTAssertTrue(controlSource.contains("var modelPickerOptions"))
        XCTAssertTrue(controlSource.contains("var pendingAttachments"))
        XCTAssertFalse(controlSource.contains("var liveSessions"))
        XCTAssertTrue(transcriptSource.contains("var liveSessions"))
        XCTAssertTrue(transcriptSource.contains("var storedMessages"))
        XCTAssertFalse(transcriptSource.contains("var blockingEvents"))
        XCTAssertFalse(transcriptSource.contains("var transcriptEntries"))
        XCTAssertFalse(transcriptSource.contains("iVBORw0KGgoAAA"))
        XCTAssertTrue(presentationSource.contains("var transcriptEntries"))
        XCTAssertTrue(presentationSource.contains("iVBORw0KGgoAAA"))
        for marker in ["var liveSessions", "var storedMessages", "HermesMessage"] {
            XCTAssertFalse(presentationSource.contains(marker))
        }
        XCTAssertEqual(fixtureSources.filter { $0.contains("var transcriptEntries") }.count, 1)
        XCTAssertEqual(fixtureSources.filter { $0.contains("iVBORw0KGgoAAA") }.count, 1)
        for source in fixtureSources {
            XCTAssertTrue(source.hasPrefix("#if DEBUG || NILE_LOCAL_RELEASE"))
        }
        let lineCounts = fixtureSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lineCounts, [270, 285, 255, 110]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            875,
            "Keep the build-gated session fixture catalog bounded"
        )
        XCTAssertLessThan(
            modelSource.components(separatedBy: .newlines).count,
            350,
            "Keep fixture catalogs and future feature runtimes out of the app model"
        )
    }

    func testSessionListModelTestsHaveBoundedFeatureAndSupportSources()
        throws
    {
        let testDirectory = repositoryRoot
            .appendingPathComponent("Tests/NileTests", isDirectory: true)
        let boundaries: [(
            file: String, markers: [String], lineLimit: Int
        )] = [
            ("SessionListModelCreationTests.swift",
             ["testEmptyFixtureOffersAndCreatesANewSession", "testMissingPreferredSessionFallsBackToFirstListedSession"], 400),
            ("SessionListModelManagementPinGoalTests.swift",
             ["testRenameSessionTrimsUpdatesSelectedTitleAndClosesDialog", "testGoalResumeSubmitsObjectiveThroughModelTurnBoundary"], 575),
            ("SessionListModelNavigationTests.swift",
             ["testTerminalSelectionNeverResumesOrClaimsWritableRuntime", "testConnectionLossFencesInFlightSourceLookup"], 450),
            ("SessionListModelEventTimelineTests.swift",
             ["testOrderedEventsDriveAttentionBusyAndConnectionState", "testFixtureProjectsAndroidTranscriptAndStableToolGroup"], 450),
            ("SessionListModelTurnDraftTests.swift",
             ["testPromptSendOptimisticallyClearsDraftAndStreamsToCompletion", "testNewDraftTypedDuringSendSurvivesOldDraftRetirement"], 500),
            ("SessionListModelBlockingPromptTests.swift",
             ["testClarificationProjectsAChoiceAndRetainsOnlyItsSafeLabel", "testBackgroundRuntimeCompletionFinalizesItsParkedPrompt"], 425),
            ("SessionListModelVoiceUsageDelegationTests.swift",
             ["testVoiceInputPreservesExistingDraftAndPublishesCapturePhases", "testDelegationInterruptAndOpenChildUseCurrentOwner"], 750),
            ("SessionListModelBackgroundLifecycleTests.swift",
             ["testAcceptedTurnTracksExactOwnerAndCompletesFromStream", "testForegroundReconcilesSelectedTurnWithAuthoritativeCompletion"], 400),
            ("SessionListModelAttachmentDeliveryTests.swift",
             ["testPhotoDraftIsProtectedBeforeItBecomesVisible", "testUncertainUploadQuarantinesOnlyItsOwner"], 400),
            ("SessionListModelAttachmentRecoveryTests.swift",
             ["testProcessRecoveryRestoresWhenOldRuntimeIsGone", "testLateAttachmentOpenCannotReplaceNewSessionViewerState"], 900),
            ("SessionListModelCommandModelTests.swift",
             ["testSlashCatalogCompletionAndSubgoalCommandStaySourceScoped", "testModelPinsRemainWritableAfterSameGatewayReconnect"], 700),
        ]
        let doubleBoundaries: [(
            file: String, declarations: [String], lineLimit: Int
        )] = [
            ("SessionListModelAudioTestDoubles.swift",
             ["final class SessionVoiceInputStub", "final class SessionSpeechOutputStub"], 100),
            ("SessionListModelPinStoreTestDoubles.swift",
             ["actor SessionModelPinStoreStub", "actor SessionPinStoreStub"], 175),
            ("SessionListModelProtectedStoreTestDoubles.swift",
             ["actor ComposerDraftStoreStub", "actor AttachmentDraftStoreStub"], 300),
            ("SessionListModelAttachmentCacheTestDoubles.swift",
             ["actor AttachmentCacheStub", "actor BlockingFirstAttachmentCacheStub"], 100),
            ("SessionListModelRepositoryTestDouble.swift", ["actor SessionRepositoryStub"], 800),
        ]

        let baseSource = try source(
            at: testDirectory.appendingPathComponent(
                "SessionListModelTests.swift"
            )
        )
        let supportSource = try source(
            at: testDirectory.appendingPathComponent(
                "SessionListModelTestSupport.swift"
            )
        )

        XCTAssertTrue(baseSource.contains("final class SessionListModelTests"))
        XCTAssertFalse(baseSource.contains("    func test"))
        XCTAssertTrue(supportSource.contains("extension SessionListModelTests"))
        XCTAssertTrue(supportSource.contains("func session("))
        XCTAssertTrue(supportSource.contains("func eventuallyAsync("))
        XCTAssertTrue(supportSource.contains("func imageFixtureData("))
        XCTAssertFalse(supportSource.contains("    func test"))

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: testDirectory.appendingPathComponent(
                    "SessionListModelTestDoubles.swift"
                ).path
            ),
            "Do not restore the mixed test-double catch-all"
        )

        var doublesAggregateLines = 0
        var doublesCombinedSource = ""
        for boundary in doubleBoundaries {
            let boundarySource = try source(
                at: testDirectory.appendingPathComponent(boundary.file)
            )
            XCTAssertFalse(boundarySource.contains("    func test"))
            for declaration in boundary.declarations {
                XCTAssertTrue(
                    boundarySource.contains(declaration),
                    "Keep \(declaration) in \(boundary.file)"
                )
            }
            XCTAssertLessThan(
                boundarySource.components(separatedBy: .newlines).count,
                boundary.lineLimit,
                "Keep \(boundary.file) independently reviewable"
            )
            doublesAggregateLines += boundarySource.components(
                separatedBy: .newlines
            ).count
            doublesCombinedSource += boundarySource
        }

        let doubleDeclarations = doubleBoundaries.flatMap(\.declarations)
        for declaration in doubleDeclarations {
            XCTAssertEqual(
                doublesCombinedSource.components(
                    separatedBy: declaration
                ).count - 1,
                1,
                "Each model test double needs one capability source owner"
            )
        }
        XCTAssertLessThan(
            doublesAggregateLines,
            1_275,
            "Do not hide test-double growth behind capability boundaries"
        )

        var featureTestNames: [String] = []
        var aggregateLines = baseSource.components(
            separatedBy: .newlines
        ).count + supportSource.components(separatedBy: .newlines).count
        for boundary in boundaries {
            let boundarySource = try source(
                at: testDirectory.appendingPathComponent(boundary.file)
            )
            XCTAssertTrue(
                boundarySource.contains("extension SessionListModelTests")
            )
            for declaration in doubleDeclarations {
                XCTAssertFalse(boundarySource.contains(declaration))
            }
            for marker in boundary.markers {
                XCTAssertTrue(
                    boundarySource.contains("func \(marker)"),
                    "Keep \(marker) in \(boundary.file)"
                )
            }
            XCTAssertLessThan(
                boundarySource.components(separatedBy: .newlines).count,
                boundary.lineLimit,
                "Keep \(boundary.file) independently reviewable"
            )
            aggregateLines += boundarySource.components(
                separatedBy: .newlines
            ).count
            featureTestNames.append(
                contentsOf: architectureTestNames(in: boundarySource)
            )
        }

        XCTAssertEqual(
            featureTestNames.count,
            137,
            "Keep every model regression discoverable across the split"
        )
        XCTAssertEqual(
            Set(featureTestNames).count,
            137,
            "Each model regression must have one feature source owner"
        )
        XCTAssertLessThan(
            aggregateLines,
            5_650,
            "Do not hide model-test growth behind feature source boundaries"
        )
    }

    func testTranscriptSurfaceHasBoundedSourceResponsibilities() throws {
        let appDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let contractSource = try source(in: appDirectory, named: "TranscriptModels.swift")
        let presentationSource = try source(in: appDirectory, named: "TranscriptPresentation.swift")
        for marker in ["enum TranscriptRole", "struct TranscriptMessage", "struct TranscriptTool", "struct TranscriptBlockingPrompt", "enum TranscriptEntry"] {
            XCTAssertTrue(contractSource.contains(marker)); XCTAssertFalse(presentationSource.contains(marker))
        }
        for marker in ["enum TranscriptDisplayRow", "struct TranscriptPresentation", "func displayRows()", "func visibleTranscriptEntries("] {
            XCTAssertTrue(presentationSource.contains(marker)); XCTAssertFalse(contractSource.contains(marker))
        }
        for source in [contractSource, presentationSource] { XCTAssertFalse(source.contains("import SwiftUI")); XCTAssertFalse(source.contains("import UIKit")) }
        let appLineCounts = [contractSource, presentationSource].map { $0.components(separatedBy: .newlines).count }
        XCTAssertLessThan(appLineCounts[0], 270); XCTAssertLessThan(appLineCounts[1], 140)
        XCTAssertLessThan(appLineCounts.reduce(0, +), 390)
        let parsingNames = ["TranscriptParsing.swift", "TranscriptMessageParser.swift", "TranscriptMediaMarkerParser.swift", "TranscriptRegex.swift"]
        let parsingSources = try parsingNames.map { try source(in: appDirectory, named: $0) }
        let parsingMarkers = [
            ["struct ParsedMessageContent", "func parseMessageContent(", "TranscriptMessageParser.parse("],
            ["enum TranscriptMessageParser", "static func parse(", "private static func messageAttachment("],
            ["struct TranscriptMediaMarker", "enum TranscriptMediaMarkerParser", "maskProtectedExamples(", "maskJSONExamples(", "supportedExtensions"],
            ["enum TranscriptRegex", "static func matches(", "static func masking(", "static func removing("],
        ]
        for (index, markers) in parsingMarkers.enumerated() { for marker in markers { XCTAssertTrue(parsingSources[index].contains(marker)); XCTAssertEqual(parsingSources.filter { $0.contains(marker) }.count, 1) } }
        for forbidden in ["import SwiftUI", "import UIKit", "Hermes", "Task<", "repository"] { parsingSources.forEach { XCTAssertFalse($0.contains(forbidden)) } }
        let parsingLineCounts = parsingSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(parsingLineCounts, [30, 135, 170, 125]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(parsingLineCounts.reduce(0, +), 420)
        let transcriptDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/Features/Transcript", isDirectory: true)
        let boundaries: [(file: String, markers: [String], excluded: [String], limit: Int)] = [
            ("BlockingPromptView.swift", ["struct BlockingPromptRow: View"], ["struct ClarificationPromptActions", "struct BlockingPromptStatusView", "struct PromptActionButton", "struct SecureBlockingPromptOverlay: View", "struct PermanentApprovalOverlay: View", "final class TranscriptViewportController"], 240),
            ("BlockingPromptActions.swift", ["struct ClarificationPromptActions: View", "struct BlockingPromptStatusView: View", "struct PromptActionButton: View", "private struct BlockingPromptButtonStyle"], ["struct BlockingPromptRow: View", "struct SecureBlockingPromptOverlay: View", "struct PermanentApprovalOverlay: View", "final class TranscriptViewportController"], 250),
            ("BlockingPromptOverlays.swift", ["struct SecureBlockingPromptOverlay: View", "struct PermanentApprovalOverlay: View", ".privacySensitive()"], ["struct BlockingPromptRow: View", "struct PromptActionButton", "final class TranscriptViewportController"], 150),
            ("TranscriptView.swift", ["struct TranscriptView: View"], ["final class TranscriptViewportController", "struct MessageRow", "struct ToolActivityGroup"], 300),
            ("TranscriptViewport.swift", ["struct TranscriptViewportItem:", "struct TranscriptViewportChangeSet:", "struct TranscriptViewportActions", "struct TranscriptViewport:"], ["final class TranscriptViewportController", "final class TranscriptHostingCell", "struct MessageRow", "struct ToolActivityGroup"], 125),
            ("TranscriptViewportController.swift", ["final class TranscriptViewportController", "private let positionRuntime = TranscriptViewportPositionRuntime()", "private let rowHost = TranscriptViewportRowHost()", "positionRuntime.update(", "private func updateViewportAccessibility("], ["UICollectionViewDelegate", "private weak var scrollState", "private var owner", "PendingPosition", "viewportResizeState", "viewportGeometry", "recordUserPosition", "UICollectionViewCompositionalLayout", "UICollectionViewDiffableDataSource", "UIHostingController<AnyView>", "TranscriptViewportRowFactory", "struct MessageRow", "struct ToolActivityGroup"], 115),
            ("TranscriptViewportPositionRuntime.swift", ["final class TranscriptViewportPositionRuntime: NSObject", "UICollectionViewDelegate", "private weak var scrollState", "private var owner", "private var settlementState", "func scrollViewWillBeginDragging(", "private func settleAfterLayout(", "private func recordUserPosition(", "private var viewportGeometry: TranscriptViewportGeometry"], ["TranscriptViewportRowHost", "TranscriptViewportChangeSet(", "UIHostingController", "TranscriptViewportRowFactory", "OSSignposter", "updateViewportAccessibility", "struct MessageRow", "struct ToolActivityGroup", "private var viewportResizeState"], 300),
            ("TranscriptViewportSettlementState.swift", ["enum TranscriptViewportSettlementAction: Equatable, Sendable", "struct TranscriptViewportSettlementState: Sendable", "private var pendingPosition", "mutating func nextAction(", "mutating func desiredTopInset("], ["UIKit", "UICollectionView", "TranscriptScrollCoordinator", "DispatchQueue", "UIView", "final class TranscriptViewportPositionRuntime"], 180),
            ("TranscriptViewportCollectionView.swift", ["@MainActor enum TranscriptViewportCollectionLayout", "private static let contentTopPadding", "static func makeLayout()", "static func makeCollectionView()", "collectionView.alwaysBounceVertical = true", "UICollectionViewCompositionalLayout", "final class TranscriptLayoutObservingCollectionView", "rootView.addSubview(self)", "override func layoutSubviews()"], ["TranscriptViewportController", "TranscriptViewportPositionRuntime", "TranscriptScrollCoordinator", "TranscriptViewportRowHost", "NileAccessibilityID", "UICollectionViewDelegate"], 80),
            ("TranscriptViewportPositionPolicy.swift", ["struct TranscriptViewportGeometry: Equatable, Sendable", "struct TranscriptViewportResizeState: Equatable, Sendable", "mutating func observe("], ["final class TranscriptViewportController", "TranscriptViewportPositionRuntime", "UIKit", "TranscriptScrollCoordinator", "TranscriptViewportRowHost"], 80),
            ("TranscriptViewportRowHost.swift", ["final class TranscriptViewportRowHost", "UICollectionViewDiffableDataSource", "TranscriptViewportChangeSet(", "TranscriptHostingCell.self", "TranscriptViewportRowFactory.make(", "parent.addChild(host)"], ["final class TranscriptViewportController", "TranscriptViewportPositionRuntime", "TranscriptScrollCoordinator", "TranscriptScrollOwner", "contentOffset", "recordUserScroll"], 190),
            ("TranscriptViewportRowFactory.swift", ["enum TranscriptViewportRowFactory", "static func make(", "switch item.content"], ["UIViewController", "UICollectionView", "TranscriptScrollCoordinator", "TranscriptProjection"], 80),
            ("TranscriptHostingCell.swift", ["final class TranscriptHostingCell", "func install(_ host:", "func uninstall(_ host:"], ["final class TranscriptViewportController", "struct TranscriptViewportChangeSet:", "struct MessageRow", "struct ToolActivityGroup"], 90),
            ("SessionLaunchpad.swift", ["struct SessionLaunchpadQuickStart", "var launchpadQuickStarts", "struct SessionLaunchpad: View"], ["struct TranscriptRow", "struct MessageRow", "struct ToolActivityGroup"], 175),
            ("TranscriptCommandRows.swift", ["struct CommandRow: View"], ["struct MessageRow: View", "struct SystemNoticeRow: View"], 110),
            ("TranscriptMessageRows.swift", ["struct TranscriptRow", "struct MessageRow", "struct AssistantMessageRow", "struct UserMessageBubble"], ["struct MessageImageView", "struct MessageAttachmentCard", "struct SessionLaunchpadQuickStart", "struct CommandRow: View", "struct SystemNoticeRow: View", "final class TranscriptViewportController", "struct ToolActivityGroup"], 250),
            ("TranscriptMediaRows.swift", ["struct MessageImageView", "struct MessageAttachmentCard", "TranscriptImageCache.shared.image"], ["struct TranscriptRow", "struct MessageRow", "struct AssistantMessageRow", "struct UserMessageBubble", "UIPasteboard", "NileMarkdownText", "BlockingPromptRow", "ToolRow"], 130),
            ("TranscriptNoticeRows.swift", ["struct SystemNoticeRow: View", "struct StandingGoalPromptRow: View"], ["struct CommandRow: View", "struct MessageRow: View"], 110),
            ("TranscriptToolActivityRows.swift", ["struct ToolActivityGroup", "struct ToolActivityRipple", "private struct ToolActivityWave"], ["struct ToolRow", "struct DefaultToolCard", "struct DiffToolCard", "struct TodoToolCard", "struct ElbowDetail"], 210),
            ("TranscriptToolRows.swift", ["struct ToolRow", "private struct DefaultToolCard", "private struct ToolHeader"], ["struct ToolActivityGroup", "struct ToolActivityRipple", "struct DiffToolCard", "struct TodoToolCard", "struct ElbowDetail"], 230),
            ("TranscriptDiffToolRow.swift", ["struct DiffToolCard", "private extension Array where Element == String"], ["struct ToolActivityGroup", "struct TodoToolCard", "struct ActiveTodoPlan", "struct ElbowDetail"], 150),
            ("TranscriptTodoRows.swift", ["struct TodoToolCard", "struct ActiveTodoPlan", "struct TodoChecklist"], ["struct ToolActivityGroup", "struct DiffToolCard", "struct ElbowDetail"], 150),
            ("TranscriptToolRowSupport.swift", ["struct ElbowDetail<", "struct StatusDot", "func statusColor(", "func formatToolDuration(", "extension String", "\nextension Array {"], ["struct ToolActivityGroup", "struct ToolRow", "struct DiffToolCard", "struct TodoToolCard", "struct ActiveTodoPlan"], 100),
        ]
        let sources = try boundaries.map {
            try source(in: transcriptDirectory, named: $0.file)
        }
        for (index, boundary) in boundaries.enumerated() {
            for marker in boundary.markers {
                XCTAssertTrue(sources[index].contains(marker), "Keep \(marker) in \(boundary.file)")
                XCTAssertEqual(sources.filter { $0.contains(marker) }.count, 1)
            }
            boundary.excluded.forEach { XCTAssertFalse(sources[index].contains($0)) }
            XCTAssertLessThan(
                sources[index].components(separatedBy: .newlines).count,
                boundary.limit,
                "Keep \(boundary.file) independently reviewable"
            )
        }
        XCTAssertEqual(sources.filter { $0.contains("TranscriptViewportPositionRuntime") }.count, 2)
        XCTAssertLessThan(
            sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +),
            3_290,
            "Do not hide transcript-surface growth behind source splits"
        )
    }

    func testModelPickerHasBoundedComponentSourcesAndNoDeadGlyphs() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Features/Sessions", isDirectory: true)
        let sources = try ["ModelPickerView.swift", "ModelPickerReasoningControl.swift", "ModelPickerCatalogView.swift", "ModelPickerCatalogRows.swift", "ModelPickerCatalogPolicy.swift", "ModelPickerCatalogComponents.swift", "ModelSwitchConfirmationView.swift"].map { try source(in: directory, named: $0) }
        let overlay = sources[0], reasoning = sources[1], catalog = sources[2], rows = sources[3], policy = sources[4], components = sources[5], confirmation = sources[6]
        let boundaries: [(source: String, markers: [String], excluded: [String], cap: Int)] = [
            (overlay, ["struct ModelPickerOverlay: View", "var controlsEnabled: Bool", "ModelPickerCatalogView("], ["Reasoning effort", "private static func reasoningLabel(", "struct ModelSwitchConfirmationOverlay"], 250),
            (reasoning, ["extension ModelPickerOverlay", "var reasoningControl: some View", "private var reasoningSelectorEnabled", "model.setReasoningEffort("], ["@State", "@Bindable", "SessionListModel", "ModelPickerCatalogView(", "isLoadingModelOptions"], 125),
            (catalog, ["struct ModelPickerCatalogView: View", "private var filteredProviders", "private var normalizedQuery", "private var pinnedCatalogGroups", "private var sortedUnresolvedPins", "private func providerSection(", "@State private var query"], ["func modelRow(", "func unresolvedPinRow(", "private func modelPinButton(", "private var reasoningControl", "static func filteredProviders(", "static func pinnedProviders(", "static func sortedPins(", "static func scopeNotice(", "Wait for this session's current turn", "struct ModelPickerText: View"], 290),
            (rows, ["extension ModelPickerCatalogView", "func modelRow(", "func unresolvedPinRow(", "private func modelPinButton(", "model.selectModel(", "model.toggleModelPin("], ["struct ModelPickerCatalogView: View", "@State", "private var filteredProviders", "private func providerSection("], 200),
            (policy, ["enum ModelPickerCatalogPolicy", "static func normalizedQuery(", "static func filteredProviders(", "static func pinnedProviders(", "static func sortedPins(", "static func scopeNotice(", "static func orderedModels(", "static func supportingLabel(", "private static func pricingLabel("], ["import SwiftUI", "@State", "@Binding", "@FocusState", "SessionListModel", "toggleModelPin"], 105),
            (components, ["struct ModelPickerText: View", "NileComposeText("], ["SessionListModel", "ModelProvider"], 50),
            (confirmation, ["struct ModelSwitchConfirmationOverlay: View", "if !canConfirm, !updating"], ["private func providerSection(", "static func orderedModels("], 140),
        ]
        for boundary in boundaries {
            for marker in boundary.markers {
                XCTAssertTrue(boundary.source.contains(marker))
                XCTAssertEqual(sources.filter { $0.contains(marker) }.count, 1)
            }
            boundary.excluded.forEach { XCTAssertFalse(boundary.source.contains($0)) }
            XCTAssertLessThan(
                boundary.source.components(separatedBy: .newlines).count,
                boundary.cap,
                "Keep each model-picker responsibility independently reviewable"
            )
        }

        let combined = sources.joined()
        for removedGlyph in [
            "NileCloseGlyph", "NileArrowDropDownGlyph",
            "NileProviderDisclosureGlyph", "NileFilledPushPinGlyph",
            "NileOutlinedPushPinGlyph", "pushPinPath(in",
        ] {
            XCTAssertFalse(combined.contains(removedGlyph))
        }
        XCTAssertLessThan(
            sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +),
            1_050,
            "Do not hide model-picker or removed-glyph debt behind source splits"
        )
    }

    func testGoalSurfaceSeparatesPersistentCardFromModalSheet() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Features/Sessions", isDirectory: true)
        let sources = try ["GoalView.swift", "GoalSheetCreation.swift", "GoalSheetDetails.swift", "GoalStatusCard.swift", "GoalPresentationPolicy.swift"].map { try source(in: directory, named: $0) }
        let sheet = sources[0], creation = sources[1], details = sources[2], card = sources[3], policy = sources[4]
        XCTAssertTrue(sheet.contains("struct GoalSheet: View") && !sheet.contains("var goalCreation") && !sheet.contains("func goalDetails(") && sources.filter { $0.contains("var goalCreation") }.count == 1 && sources.filter { $0.contains("@State var objective") }.count == 1)
        for (source, markers) in [(creation, ["extension GoalSheet", "var goalCreation", "private func budgetButton(", "goalQuickStarts", "model.startGoal("]), (details, ["extension GoalSheet", "func goalDetails(", "private func primaryGoalButton(", "GoalPresentationPolicy.statusSummary("]), (card, ["struct GoalStatusCard: View", "struct NileGoalGlyph: Shape", "GoalPresentationPolicy.statusSummary("]), (policy, ["enum GoalPresentationPolicy", "static func statusSummary(", "static func statusColor("])] {
            for marker in markers { XCTAssertTrue(source.contains(marker)) }
        }
        XCTAssertFalse(creation.contains("@State") || creation.contains("@Bindable") || creation.contains("SessionListModel") || details.contains("@State") || details.contains("@Bindable") || policy.contains("SessionListModel") || policy.contains(": View"))
        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(lineCounts, [100, 250, 210, 140, 45]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(lineCounts.reduce(0, +), 700)
    }

    func testTalkModeSurfaceSeparatesOrchestrationControlsAndPolicy() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Features/Sessions", isDirectory: true)
        let sources = try ["TalkModeView.swift", "TalkModeControls.swift", "TalkPresentation.swift"].map { try source(in: directory, named: $0) }
        for (source, boundary) in zip(sources, [(["struct TalkModeView: View", "TalkPresentation("], 275), (["struct TalkOrb: View", "struct TalkControl: View"], 140), (["struct TalkPresentation: Equatable, Sendable", "enum PrimaryAction: Equatable, Sendable"], 100)]) { for marker in boundary.0 { XCTAssertTrue(source.contains(marker)); XCTAssertEqual(sources.filter { $0.contains(marker) }.count, 1) }; XCTAssertLessThan(source.components(separatedBy: .newlines).count, boundary.1) }
        XCTAssertFalse(sources[0].contains("struct TalkOrb") || sources[0].contains("enum PrimaryAction") || sources[1].contains("SessionListModel") || sources[2].contains("import SwiftUI") || sources[2].contains("SessionListModel"))
        XCTAssertLessThan(sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 500)
    }

    func testSessionDelegationRuntimeOwnsCapabilityAndAsyncLifecycle() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let modelSource = try source(in: appDirectory, named: "SessionListModel.swift")
        let presentationSource = try source(in: appDirectory, named: "SessionListModelPresentation.swift")
        let delegationSource = try source(in: appDirectory, named: "SessionListModelDelegation.swift")
        let delegationFixtureSource = try source(in: appDirectory, named: "SessionListModelDelegationFixtures.swift")
        let runtimeCoreSource = try source(in: appDirectory, named: "SessionDelegationRuntime.swift")
        let runtimeLifecycleSource = try source(in: appDirectory, named: "SessionDelegationAsyncLifecycle.swift")
        let runtimeFixtureSource = try source(in: appDirectory, named: "SessionDelegationRuntimeFixtures.swift")
        let fixtureSource = try source(in: appDirectory, named: "SessionDelegationFixture.swift")
        let fixtureInstallerSource = try source(in: appDirectory, named: "NileAppGraphFixtureInstaller.swift")
        let fixtureTestSource = try source(in: repositoryRoot.appendingPathComponent("Tests/NileTests", isDirectory: true), named: "SessionDelegationRuntimeFixtureTests.swift")

        XCTAssertTrue(delegationSource.contains("extension SessionListModel"))
        for adapter in [
            "var delegationTurns: [DelegationTurnUI]",
            "var pinnedDelegationTurnID: String?",
            "var isReconcilingDelegations: Bool",
            "var delegationControlError: String?",
            "var pinnedDelegationTurn: DelegationTurnUI?",
            "var delegationControlsEnabled: Bool",
            "func interruptDelegatedAgent(",
            "func openDelegatedChild(",
            "func handleDelegationEvent(",
            "func markDelegationParentCompleted(",
            "func ensureDelegationSnapshotsLoaded(",
            "func reconcileDelegations()",
            "func syncDelegationUI()",
            "func clearDelegationState()",
        ] {
            XCTAssertTrue(delegationSource.contains(adapter), "Delegation bridge must own \(adapter)")
            XCTAssertFalse(modelSource.contains(adapter), "Keep \(adapter) out of the core model source")
            XCTAssertFalse(presentationSource.contains(adapter), "Keep \(adapter) out of general presentation forwarding")
        }
        XCTAssertTrue(delegationSource.contains("runtimes.delegationRuntime"))
        let applicationSource = try sessionEventApplicationSource()
        XCTAssertTrue(applicationSource.contains("handleDelegationEvent("))
        XCTAssertTrue(applicationSource.contains("markDelegationParentCompleted("))
        XCTAssertTrue(try sessionNavigationSource().contains("syncDelegationUI()"))
        XCTAssertFalse(delegationSource.contains("HermesStreamEvent"))
        XCTAssertFalse(delegationSource.contains("SessionRepositoryCapabilityProviding"))
        XCTAssertFalse(delegationSource.contains("SessionRuntimeComposition."))
        for marker in ["private var delegationTasks", "private var delegations", "repository.delegationStatus", "repository.interruptSubagent", "repository.saveDelegationSnapshot"] { XCTAssertFalse(modelSource.contains(marker)) }

        let runtimeSources = [runtimeCoreSource, runtimeLifecycleSource]
        for marker in ["final class SessionDelegationRuntime", "any HermesDelegationServing", "let repository:", "var coordinator", "var tasks:", "var lifecycleGeneration", "var activeGatewayID"] {
            XCTAssertTrue(runtimeCoreSource.contains(marker)); XCTAssertEqual(runtimeSources.filter { $0.contains(marker) }.count, 1)
        }
        for marker in ["extension SessionDelegationRuntime", "func interrupt(", "func loadSnapshots(", "func reconcile(", "func persist(", "repository.interruptSubagent(", "repository.listDelegationSnapshots(", "repository.delegationStatus()", "repository.saveDelegationSnapshot("] {
            XCTAssertTrue(runtimeLifecycleSource.contains(marker)); XCTAssertEqual(runtimeSources.filter { $0.contains(marker) }.count, 1)
        }
        for marker in ["repository.interruptSubagent(", "repository.listDelegationSnapshots(", "repository.delegationStatus()", "repository.saveDelegationSnapshot(", "tasks[taskID]"] { XCTAssertFalse(runtimeCoreSource.contains(marker)) }
        for marker in ["@Observable", "var turns:", "let repository:", "var coordinator", "var tasks:", "func handleEvent(", "func markParentCompleted("] { XCTAssertFalse(runtimeLifecycleSource.contains(marker)) }
        for source in runtimeSources { XCTAssertFalse(source.contains("HermesStreamEvent") || source.contains("SessionDelegationEventFixture") || source.contains("func installFixture(")) }
        for (source, markers) in [
            (runtimeFixtureSource, ["#if DEBUG", "extension SessionDelegationRuntime", "func installFixture(", "func installPresentationFixture(", "handleEvent(", "markParentCompleted("]),
            (delegationFixtureSource, ["#if DEBUG", "extension SessionListModel", "func installDelegationFixture(", "func installAndroidVisualDelegationFixture()", "runtimes.delegationRuntime.installFixture("]),
        ] {
            markers.forEach { XCTAssertTrue(source.contains($0)) }
        }
        XCTAssertFalse(delegationSource.contains("func installDelegationFixture("))
        XCTAssertFalse(runtimeFixtureSource.contains("any HermesDelegationServing"))
        XCTAssertFalse(delegationFixtureSource.contains("HermesStreamEvent"))
        XCTAssertTrue(fixtureSource.hasPrefix("#if DEBUG"))
        XCTAssertTrue(fixtureInstallerSource.contains("#if DEBUG\n        if plan.showsDelegationActiveFixture"))
        XCTAssertEqual(architectureTestNames(in: fixtureTestSource), ["testEventFixturesUseProductionProjectionPath", "testPresentationFixtureInstallsExactProjection"])
        XCTAssertLessThan(fixtureTestSource.components(separatedBy: .newlines).count, 50)
        XCTAssertFalse(runtimeSources.contains { $0.contains("fixture-agent-one") })
        XCTAssertTrue(fixtureSource.contains("fixture-agent-one"))
        XCTAssertTrue(fixtureSource.contains("androidVisual"))
        XCTAssertEqual(
            try sessionEventApplicationSource().components(
                separatedBy:
                    "private func consume(_ event: HermesStreamEvent)"
            ).count - 1,
            1,
            "Delegation extraction must retain one model application boundary"
        )

        let boundedSources = [modelSource, presentationSource, delegationSource, delegationFixtureSource, runtimeCoreSource, runtimeLifecycleSource, runtimeFixtureSource, fixtureSource]
        let lineCounts = boundedSources.map { $0.components(separatedBy: .newlines).count }
        XCTAssertTrue(zip(lineCounts, [340, 250, 170, 50, 145, 265, 60, 220]).allSatisfy { $0.0 < $0.1 })
        XCTAssertLessThan(lineCounts.reduce(0, +), 1_400, "Do not hide delegation growth behind Debug-only source splits")
    }

    func testDelegationCoordinatorAndSurfaceHaveBoundedResponsibilities() throws {
        let appDirectory = repositoryRoot
            .appendingPathComponent("Sources/Nile/App", isDirectory: true)
        let names = ["DelegationCoordinator.swift", "DelegationInterruptLifecycle.swift", "DelegationSnapshotLifecycle.swift", "DelegationAgentReducer.swift", "DelegationPresentation.swift"]
        let sources = try names.map { try source(in: appDirectory, named: $0) }
        let coordinatorSource = sources[0]
        let interruptSource = sources[1]
        let lifecycleSource = sources[2]
        let reducerSource = sources[3]
        let presentationSource = sources[4]

        for marker in ["final class DelegationCoordinator", "var turnsByOwner", "private var liveOwners", "let interruptLifecycle", "func applyEvent(", "DelegationAgentReducer.merge("] {
            XCTAssertTrue(coordinatorSource.contains(marker))
        }
        for marker in ["final class DelegationInterruptLifecycle", "private var active:", "private var sequence:", "func begin(", "func applyResult(", "func applyFailure(", "extension DelegationCoordinator", "func beginInterrupt("] {
            XCTAssertTrue(interruptSource.contains(marker))
        }
        for marker in ["extension DelegationCoordinator", "func beginSnapshotLoad(", "func applyReconciliation(", "func claimPersistence(", "func trimSettledHistory(", "DelegationAgentReducer.snapshot("] {
            XCTAssertTrue(lifecycleSource.contains(marker))
        }
        XCTAssertEqual(sources.filter { $0.contains("var turnsByOwner:") }.count, 1)
        XCTAssertEqual(sources.filter { $0.contains("private var active: [String: Int64]") }.count, 1)
        XCTAssertFalse(coordinatorSource.contains("func applyReconciliation("))
        XCTAssertFalse(coordinatorSource.contains("func beginInterrupt("))
        XCTAssertFalse(interruptSource.contains("func applyEvent("))
        XCTAssertFalse(lifecycleSource.contains("func applyEvent("))
        XCTAssertFalse(lifecycleSource.contains("final class DelegationCoordinator"))

        for marker in ["enum DelegationAgentReducer {", "struct State {", "static func fallbackKey(", "static func make(", "static func merge(", "static func ui(", "static func snapshot(", "static func eventData(", "static func absoluteToolCount("] {
            XCTAssertTrue(reducerSource.contains(marker))
        }
        for forbidden in ["turnsByOwner", "interruptLifecycle", "reconcileGeneration", "nowEpochSeconds"] {
            XCTAssertFalse(reducerSource.contains(forbidden))
        }

        for contract in [
            "let retainedSettledDelegationTurns = 3",
            "struct DelegationOwner: Hashable, Sendable",
            "enum DelegatedAgentStatus: Equatable, Sendable",
            "struct DelegatedAgentUI: Equatable, Sendable, Identifiable",
            "struct DelegationTurnUI: Equatable, Sendable, Identifiable",
            "struct DelegationProjection: Equatable, Sendable",
            "struct DelegationInterruptRequest: Equatable, Sendable",
        ] {
            XCTAssertTrue(presentationSource.contains(contract), "Presentation must own \(contract)")
            XCTAssertFalse(sources.dropLast().contains { $0.contains(contract) }, "Keep \(contract) out of coordination")
        }
        XCTAssertFalse(presentationSource.contains("SubagentEventData("))
        XCTAssertFalse(presentationSource.contains("DelegationSnapshotAgent("))

        let lineCounts = sources
            .map { $0.components(separatedBy: .newlines).count }
        for (lineCount, limit) in zip(lineCounts, [310, 150, 200, 290, 100]) {
            XCTAssertLessThan(lineCount, limit)
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            1_000,
            "Do not hide delegation coordinator growth behind lifecycle sources"
        )

        let sessionsDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Features/Sessions", isDirectory: true
        )
        let surfaceBoundaries: [(file: String, markers: [String], limit: Int)] = [
            ("DelegationView.swift", ["struct DelegatedActivityOverview", "struct DelegationTranscriptGroup", "private struct DelegationGroup"], 175),
            ("DelegatedAgentRow.swift", ["struct DelegatedAgentRow"], 125),
            ("DelegatedAgentDetail.swift", ["struct DelegatedAgentDetail", "struct DetailLine"], 225),
            ("DelegationViewSupport.swift", ["struct DelegationSupportingText", "struct DelegationDuration", "struct DelegationStatusDot", "extension DelegatedAgentStatus", "func delegationText("], 180),
        ]
        let surfaceSources = try surfaceBoundaries.map {
            try source(in: sessionsDirectory, named: $0.file)
        }
        for (index, boundary) in surfaceBoundaries.enumerated() {
            boundary.markers.forEach { marker in
                XCTAssertEqual(surfaceSources.filter { $0.contains(marker) }.count, 1)
            }
            XCTAssertLessThan(surfaceSources[index].components(separatedBy: .newlines).count, boundary.limit)
        }
        XCTAssertLessThan(
            surfaceSources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 675,
            "Keep delegation orchestration, rows, details, and support bounded"
        )
    }

}
