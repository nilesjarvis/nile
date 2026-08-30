import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testArchitectureBoundaryCoverageHasFeatureOwnedSources() throws {
        let testsDirectory = repositoryRoot.appendingPathComponent(
            "Tests/NileTests",
            isDirectory: true
        )
        let boundaries: [(file: String, markers: [String])] = [
            ("ArchitectureBoundaryCompositionTests.swift", ["testNileAppGraphSeparatesProductionFixtureAndRouteResponsibilities", "testAccessibilityIDsHaveFeatureOwnedSources", "testSessionRuntimeCompositionOwnsProductionAndFixtureWiring"]),
            ("ArchitectureBoundarySessionBridgeTests.swift", ["testSessionListPresentationAdaptersHaveBoundedSource", "testSessionEventRuntimeOwnsTheOnlyHermesStreamAndDeltaCadence"]),
            ("ArchitectureBoundaryFeatureSurfaceTests.swift", ["testSessionFixturesHaveCapabilityOwnedSourceBoundaries", "testGoalSurfaceSeparatesPersistentCardFromModalSheet", "testTalkModeSurfaceSeparatesOrchestrationControlsAndPolicy", "testDelegationCoordinatorAndSurfaceHaveBoundedResponsibilities"]),
            ("ArchitectureBoundaryCapabilityRuntimeTests.swift", ["testSessionGoalRuntimeSeparatesMutationStatusPolicyAndContracts", "testSlashCommandPolicySeparatesDispatchSafetyFromCatalogDiscovery", "testSessionComposerRuntimeOwnsDraftRecoveryProjection", "testSessionClaimAndRenameRuntimesOwnIndependentLifecycles"]),
            ("ArchitectureBoundaryCommandRuntimeTests.swift", ["testSessionCommandRuntimeOwnsCapabilityAndAsyncLifecycle"]),
            ("ArchitectureBoundarySessionRuntimeTests.swift", ["testSessionAttachmentPersistenceRuntimeOwnsProtectedStateMachine", "testGatewaySetupKeepsModelAndSurfaceResponsibilitiesBounded"]),
            ("ArchitectureBoundaryGatewayClientTests.swift", ["testGatewayWebSocketClientKeepsStateAndPoliciesBounded", "testGatewayDashboardOwnsBoundedTransportAndSecurityPolicies"]),
            ("ArchitectureBoundaryGatewayServiceTests.swift", ["testGatewayDelegationServiceOwnsCapabilityTransport", "testGatewayRepositoryTestsHaveCapabilityOwnedSources", "testGatewayCommandGoalServicesAndSpeechCodecOwnCapabilityValidation"]),
            ("ArchitectureBoundaryPersistenceTests.swift", ["testUsageStatsHasBoundedUIAndProjectionSources", "testProtectedPersistenceMechanicsAndWriteOrderingHaveOneBoundary"]),
        ]

        let baseSource = try source(
            at: testsDirectory.appendingPathComponent(
                "ArchitectureBoundaryTests.swift"
            )
        )
        XCTAssertEqual(
            architectureTestNames(in: baseSource),
            ["testArchitectureBoundaryCoverageHasFeatureOwnedSources"]
        )

        var featureTestNames: [String] = []
        var aggregateLines = baseSource.components(
            separatedBy: .newlines
        ).count
        for boundary in boundaries {
            let boundarySource = try source(
                at: testsDirectory.appendingPathComponent(boundary.file)
            )
            XCTAssertTrue(
                boundarySource.contains("extension ArchitectureBoundaryTests")
            )
            for marker in boundary.markers {
                XCTAssertTrue(
                    boundarySource.contains("func \(marker)"),
                    "Keep \(marker) in \(boundary.file)"
                )
            }

            let lineCount = boundarySource.components(
                separatedBy: .newlines
            ).count
            XCTAssertLessThan(
                lineCount,
                1_000,
                "Keep \(boundary.file) independently reviewable"
            )
            aggregateLines += lineCount
            featureTestNames.append(
                contentsOf: architectureTestNames(in: boundarySource)
            )
        }

        XCTAssertEqual(
            featureTestNames.count, 62,
            "Preserve every pre-split architecture contract"
        )
        XCTAssertEqual(
            Set(featureTestNames).count, 62,
            "Architecture contract names must have one source owner"
        )
        XCTAssertLessThan(
            aggregateLines,
            5_450,
            "Do not hide architecture-test growth behind the source split"
        )
    }

    var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func sessionEventApplicationSource() throws -> String {
        try [
            "SessionListModelEvents.swift", "SessionListModelEventSettlement.swift",
            "SessionListModelVisibleEventProjection.swift", "SessionListModelConnectionLossProjection.swift",
        ].map {
            try source(
                at: repositoryRoot.appendingPathComponent(
                    "Sources/Nile/App/\($0)"
                )
            )
        }.joined(separator: "\n")
    }

    func sessionTimelinePresentationSource() throws -> String {
        try source(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Nile/App/SessionListModelTimeline.swift"
            )
        )
    }

    func sessionGatewaySource() throws -> String {
        try source(
            at: repositoryRoot.appendingPathComponent(
                "Sources/Nile/App/SessionListModelGateway.swift"
            )
        )
    }

    func sessionNavigationSource() throws -> String {
        try [
            "SessionListModelNavigation.swift",
            "SessionListModelSessionOpening.swift",
            "SessionListModelRefresh.swift",
        ].map {
            try source(
                at: repositoryRoot.appendingPathComponent(
                    "Sources/Nile/App/\($0)"
                )
            )
        }.joined(separator: "\n")
    }

    func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func source(in directory: URL, named file: String) throws -> String {
        try source(at: directory.appendingPathComponent(file))
    }

    func architectureTestNames(in source: String) -> [String] {
        source.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard
                line.hasPrefix("func test"),
                let openingParenthesis = line.firstIndex(of: "(")
            else {
                return nil
            }
            let nameStart = line.index(line.startIndex, offsetBy: 5)
            return String(line[nameStart..<openingParenthesis])
        }
    }
}
