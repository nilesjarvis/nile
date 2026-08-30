import XCTest
@testable import Nile

final class ModelControlPolicyTests: XCTestCase {
    func testSelectableProvidersRequireAuthenticationAndModels() {
        let options = ModelOptions(
            model: nil,
            provider: nil,
            providers: [
                provider(slug: "ready", models: ["model"]),
                provider(slug: "signed-out", authenticated: false),
                provider(slug: "empty"),
            ]
        )

        XCTAssertEqual(
            ModelControlPolicy.selectableProviders(from: options).map(\.slug),
            ["ready"]
        )
    }

    func testModelAndReasoningAdmissionPreserveExactOutcomes() {
        let providers = [provider(slug: "openai", models: ["gpt-5"])]
        let current = SessionInfo(
            model: "gpt-5",
            provider: "openai",
            reasoningEffort: "high"
        )

        XCTAssertEqual(
            ModelControlPolicy.modelSelection(
                model: "gpt-5",
                provider: "openai",
                currentInfo: current,
                selectableProviders: providers
            ),
            .unchanged
        )
        XCTAssertEqual(
            ModelControlPolicy.modelSelection(
                model: "missing",
                provider: "openai",
                currentInfo: current,
                selectableProviders: providers
            ),
            .rejected(
                "That model is not available for this gateway. Refresh the model list and try again."
            )
        )
        XCTAssertEqual(
            ModelControlPolicy.reasoningSelection(
                effort: " MAX ",
                currentEffort: "high"
            ),
            .apply("max")
        )
        XCTAssertEqual(
            ModelControlPolicy.reasoningSelection(
                effort: "turbo",
                currentEffort: nil
            ),
            .rejected("That reasoning effort is not supported.")
        )
    }

    func testNoticesNormalizeWarningsAndReasoningDisplay() {
        XCTAssertEqual(
            ModelControlPolicy.appliedModelNotice(
                resolvedModel: "gpt-5",
                warning: "  expensive  "
            ),
            "switched this session to gpt-5\nexpensive"
        )
        XCTAssertEqual(
            ModelControlPolicy.appliedModelNotice(
                resolvedModel: "gpt-5",
                warning: "  "
            ),
            "switched this session to gpt-5"
        )
        XCTAssertEqual(ModelControlPolicy.reasoningNotice(" NONE "),
                       "set this session's reasoning effort to off")
    }

    func testMutationFailureKeepsDefiniteAndUncertainPathsDistinct() {
        XCTAssertEqual(
            ModelControlPolicy.mutationFailure(HermesError("rejected")),
            ModelMutationFailure(isUncertain: false, message: "rejected")
        )
        let uncertain = ModelControlPolicy.mutationFailure(
            HermesError("lost", isConnectionFailure: true)
        )
        XCTAssertTrue(uncertain.isUncertain)
        XCTAssertTrue(uncertain.message.contains("may have changed"))
        XCTAssertTrue(
            ModelControlPolicy.mutationFailure(
                CocoaError(.fileReadUnknown)
            ).isUncertain
        )
    }

    func testPinAndProviderResolutionFailClosedWhenLegacyIsAmbiguous() {
        let providers = [
            provider(slug: "one", models: ["shared", "unique"]),
            provider(slug: "two", models: ["shared"]),
        ]
        let legacyShared = ModelPin(providerSlug: nil, modelID: "shared")
        let legacyUnique = ModelPin(providerSlug: nil, modelID: "unique")

        XCTAssertEqual(
            ModelControlPolicy.resolvedPins(
                [legacyShared, legacyUnique],
                selectableProviders: providers
            ),
            [ModelPin(providerSlug: "one", modelID: "unique")]
        )
        XCTAssertEqual(
            ModelControlPolicy.unresolvedPins(
                [legacyShared, legacyUnique],
                selectableProviders: providers
            ),
            [legacyShared]
        )
        XCTAssertFalse(
            ModelControlPolicy.isPinned(
                provider: "one",
                model: "shared",
                pins: [legacyShared],
                selectableProviders: providers
            )
        )
        XCTAssertEqual(
            ModelControlPolicy.pinAdmission(
                provider: " one ",
                model: "unique"
            ),
            .rejected("That model pin is invalid.")
        )
    }

    private func provider(
        slug: String,
        authenticated: Bool = true,
        models: [String] = []
    ) -> ModelProvider {
        ModelProvider(
            slug: slug,
            name: slug,
            authenticated: authenticated,
            isCurrent: false,
            models: models
        )
    }
}
