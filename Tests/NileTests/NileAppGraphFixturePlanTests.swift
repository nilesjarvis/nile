import XCTest
@testable import Nile

@MainActor
final class NileAppGraphFixturePlanTests: XCTestCase {
    func testProductionPlanProvidesNoFixtureCollaborators() {
        let plan = NileAppGraphFixturePlan(arguments: ["Nile"])

        XCTAssertFalse(plan.showsSessionFixture)
        XCTAssertFalse(plan.forcesReducedMotionFixture)
        XCTAssertFalse(plan.showsNotificationEducationFixture)
        XCTAssertTrue(plan.automaticallyRestoresGateway)
        XCTAssertNil(plan.sessionFixture)
        XCTAssertNil(plan.makeBiometricAppLockFixture())
        XCTAssertNil(plan.makeGatewayProfileStoreFixture())
        XCTAssertNil(plan.makeGatewayConnectionClientFixture())
        XCTAssertNil(plan.makeGatewaySessionCleanerFixture())
        XCTAssertNil(plan.makeHermesVoiceServiceFixture())
        XCTAssertNil(plan.makeSessionListFixture())
    }

    func testComposerFixtureWinsSessionCatalogPrecedence() {
        let plan = NileAppGraphFixturePlan(
            arguments: [
                "Nile",
                "--nile-fixture-composer-needs-input",
                "--nile-fixture-session-empty",
                "--nile-fixture-usage-context",
            ]
        )

        XCTAssertTrue(plan.showsSessionFixture)
        XCTAssertEqual(plan.sessionFixture, .blockingClarification)
        XCTAssertTrue(plan.showsUsageFixture)
        XCTAssertFalse(plan.automaticallyRestoresGateway)
    }

    func testStreamingAndRecoveryPrecedenceRemainDeterministic() {
        let plan = NileAppGraphFixturePlan(
            arguments: [
                "Nile",
                "--nile-fixture-streaming-empty",
                "--nile-fixture-streaming-partial",
                "--nile-fixture-offline",
                "--nile-fixture-restoring",
            ]
        )

        XCTAssertTrue(plan.showsSessionFixture)
        XCTAssertEqual(plan.recoveryFixturePhase, .offline)
        guard case .empty? = plan.streamingTranscriptFixture else {
            return XCTFail("The first streaming fixture must retain precedence")
        }
    }

    func testSessionFixturePolicyOwnsStreamingRecoveryAndComposerPrecedence() {
        let arguments: Set<String> = [
            "--nile-fixture-streaming-empty",
            "--nile-fixture-streaming-partial",
            "--nile-fixture-offline",
            "--nile-fixture-restoring",
            "--nile-fixture-android-visual-brand",
        ]

        guard case .empty? = NileSessionFixturePolicy.streamingTranscript(
            arguments: arguments
        ) else {
            return XCTFail("Streaming precedence must stay deterministic")
        }
        guard case .partial? = NileSessionFixturePolicy.streamingTranscript(
            arguments: ["--nile-fixture-streaming-partial"]
        ) else {
            return XCTFail("Partial streaming must remain selectable")
        }
        guard case .table? = NileSessionFixturePolicy.streamingTranscript(
            arguments: ["--nile-fixture-markdown-table"]
        ) else {
            return XCTFail("Table streaming must remain selectable")
        }
        XCTAssertNil(
            NileSessionFixturePolicy.streamingTranscript(arguments: [])
        )
        XCTAssertEqual(
            NileSessionFixturePolicy.recoveryPhase(arguments: arguments),
            .offline
        )
        XCTAssertEqual(
            NileSessionFixturePolicy.recoveryPhase(
                arguments: ["--nile-fixture-reconnecting"]
            ),
            .reconnecting
        )
        XCTAssertEqual(
            NileSessionFixturePolicy.recoveryPhase(
                arguments: ["--nile-fixture-restoring"]
            ),
            .restoring
        )
        XCTAssertNil(NileSessionFixturePolicy.recoveryPhase(arguments: []))
        XCTAssertEqual(
            NileSessionFixturePolicy.sessionFixture(
                arguments: arguments,
                composerActivity: .needsInput
            ),
            .blockingClarification
        )
    }

    func testSessionFixturePolicyMapsDedicatedCatalogArgumentsAndFailsClosed() {
        let mappings: [(String, SessionListFixture)] = [
            ("--nile-fixture-session-empty", .empty),
            ("--nile-fixture-session-switching", .androidBrand),
            ("--nile-fixture-session-switching-empty", .androidVisualBrand),
            ("--nile-fixture-android-visual-brand", .androidVisualBrand),
            ("--nile-fixture-android-visual-media", .androidVisualMedia),
            ("--nile-fixture-android-visual-attachments", .androidVisualAttachments),
            ("--nile-fixture-android-visual-transcript-syntax", .androidVisualSyntax),
            ("--nile-fixture-transcript-scroll", .transcriptScroll),
            ("--nile-fixture-android-delegation-mixed", .androidVisualDelegation),
            ("--nile-fixture-usage-context", .androidVisualContext),
            ("--nile-fixture-stats", .androidVisualStats),
            ("--nile-fixture-android-visual-rename", .androidVisualContext),
            ("--nile-fixture-blocking-clarification", .blockingClarification),
            ("--nile-fixture-blocking-approvals", .blockingApprovals),
            ("--nile-fixture-blocking-sudo", .blockingSudo),
            ("--nile-fixture-blocking-secret", .blockingSecret),
            ("--nile-fixture-blocking-invalid", .blockingInvalid),
            ("--nile-fixture-attachments", .attachments),
            ("--nile-fixture-android-visual-model-picker", .androidVisualModelPicker),
            ("--nile-fixture-model-picker", .modelPicker),
            ("--nile-fixture-goal-create", .goalCreation),
            ("--nile-fixture-goal-active", .goalActive),
        ]

        for (argument, expected) in mappings {
            XCTAssertEqual(
                NileSessionFixturePolicy.sessionFixture(
                    arguments: [argument],
                    composerActivity: nil
                ),
                expected,
                argument
            )
        }
        XCTAssertNil(
            NileSessionFixturePolicy.sessionFixture(
                arguments: ["--nile-fixture-unknown"],
                composerActivity: nil
            )
        )
    }

    func testGatewaySwitchBuildsOnlyItsTwoIsolatedProfiles() async throws {
        let plan = NileAppGraphFixturePlan(
            arguments: [
                "Nile",
                "--nile-fixture-android-visual-gateway-switch",
                "--nile-fixture-android-visual-gateway-removal",
            ]
        )

        XCTAssertTrue(plan.confirmsGatewaySwitchFixture)
        XCTAssertFalse(plan.automaticallyRestoresGateway)
        XCTAssertNotNil(plan.makeGatewayConnectionClientFixture())
        XCTAssertNotNil(plan.makeGatewaySessionCleanerFixture())
        let store = try XCTUnwrap(plan.makeGatewayProfileStoreFixture())
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.profiles.map(\.id), ["home", "lab"])
        XCTAssertEqual(snapshot.activeProfile?.id, "home")
    }

    func testGatewayRemovalBuildsOnlyItsProfileAndCleanupCapability()
        async throws
    {
        let plan = NileAppGraphFixturePlan(
            arguments: [
                "Nile",
                "--nile-fixture-android-visual-gateway-removal",
            ]
        )

        XCTAssertFalse(plan.confirmsGatewaySwitchFixture)
        XCTAssertFalse(plan.automaticallyRestoresGateway)
        XCTAssertNil(plan.makeGatewayConnectionClientFixture())
        XCTAssertNotNil(plan.makeGatewaySessionCleanerFixture())
        XCTAssertNil(plan.makeHermesVoiceServiceFixture())
        let store = try XCTUnwrap(plan.makeGatewayProfileStoreFixture())
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.profiles.map(\.id), ["home"])
        XCTAssertEqual(
            snapshot.activeProfile?.normalizedBaseURL,
            "https://hermes.example"
        )
    }

    func testHermesVoiceBuildsOnlyItsVoiceCapability() {
        let plan = NileAppGraphFixturePlan(
            arguments: ["Nile", "--nile-fixture-hermes-voice"]
        )

        XCTAssertFalse(plan.automaticallyRestoresGateway)
        XCTAssertNil(plan.makeGatewayProfileStoreFixture())
        XCTAssertNil(plan.makeGatewayConnectionClientFixture())
        XCTAssertNil(plan.makeGatewaySessionCleanerFixture())
        XCTAssertNotNil(plan.makeHermesVoiceServiceFixture())
    }

    func testPerformanceStressArgumentSelectsOnlySessionFixtureState() {
        let plan = NileAppGraphFixturePlan(
            arguments: ["Nile", "--nile-performance-streaming-stress"]
        )

        XCTAssertTrue(plan.showsStreamingStressFixture)
        XCTAssertTrue(plan.showsSessionFixture)
        XCTAssertNil(plan.sessionFixture)
        XCTAssertFalse(plan.automaticallyRestoresGateway)
    }
}
