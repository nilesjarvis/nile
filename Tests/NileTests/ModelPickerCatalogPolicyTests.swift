import XCTest
@testable import Nile

final class ModelPickerCatalogPolicyTests: XCTestCase {
    func testOrderedModelsPreserveCatalogOrderThenAppendSortedUnavailableValues() {
        let provider = makeProvider(
            models: ["beta", "alpha", "beta"],
            unavailable: ["gamma", "alpha", "delta"]
        )

        XCTAssertEqual(
            ModelPickerCatalogPolicy.orderedModels(provider),
            ["beta", "alpha", "delta", "gamma"]
        )
    }

    func testSupportingLabelCombinesCapabilitiesAndPaidPricing() {
        let provider = makeProvider(
            models: ["reasoner"],
            capabilities: [
                "reasoner": ModelCapabilities(
                    fast: true,
                    reasoning: true
                ),
            ],
            pricing: [
                "reasoner": ModelPricing(
                    input: "1",
                    output: "2",
                    cache: "0.5",
                    free: false
                ),
            ]
        )

        XCTAssertEqual(
            ModelPickerCatalogPolicy.supportingLabel(
                provider: provider,
                model: "reasoner"
            ),
            "Fast · Reasoning · in 1 · out 2 · cache 0.5 /M tokens"
        )
    }

    func testSupportingLabelDistinguishesFreeFromMissingMetadata() {
        let provider = makeProvider(
            models: ["free", "unknown"],
            pricing: [
                "free": ModelPricing(
                    input: nil,
                    output: nil,
                    cache: nil,
                    free: true
                ),
                "unknown": ModelPricing(
                    input: " ",
                    output: "\n",
                    cache: nil,
                    free: false
                ),
            ]
        )

        XCTAssertEqual(
            ModelPickerCatalogPolicy.supportingLabel(
                provider: provider,
                model: "free"
            ),
            "free"
        )
        XCTAssertNil(
            ModelPickerCatalogPolicy.supportingLabel(
                provider: provider,
                model: "unknown"
            )
        )
    }

    func testFilteredProvidersNormalizeQueriesAndMatchProviderOrModel() {
        let primary = makeProvider(
            slug: "primary",
            name: "Primary Provider",
            models: ["beta", "alpha"]
        )
        let secondary = makeProvider(
            slug: "secondary",
            name: "Secondary",
            models: ["gamma"]
        )

        let providerMatches = ModelPickerCatalogPolicy.filteredProviders(
            [primary, secondary],
            query: "  PRIMARY PROVIDER\n"
        )
        XCTAssertEqual(providerMatches.map(\.0.slug), ["primary"])
        XCTAssertEqual(providerMatches.map(\.1), [["beta", "alpha"]])

        let modelMatches = ModelPickerCatalogPolicy.filteredProviders(
            [primary, secondary],
            query: "  ALP  "
        )
        XCTAssertEqual(modelMatches.map(\.0.slug), ["primary"])
        XCTAssertEqual(modelMatches.map(\.1), [["alpha"]])
    }

    func testPinnedProvidersAndSortedPinsPreserveDeterministicCatalogOrder() {
        let primary = makeProvider(
            slug: "primary",
            models: ["beta", "alpha"]
        )
        let secondary = makeProvider(
            slug: "secondary",
            models: ["gamma"]
        )
        let pins: Set<ModelPin> = [
            ModelPin(providerSlug: "secondary", modelID: "gamma"),
            ModelPin(providerSlug: "primary", modelID: "alpha"),
            ModelPin(providerSlug: "missing", modelID: "zeta"),
        ]

        let groups = ModelPickerCatalogPolicy.pinnedProviders(
            [primary, secondary],
            pins: pins
        )
        XCTAssertEqual(groups.map(\.0.slug), ["primary", "secondary"])
        XCTAssertEqual(groups.map(\.1), [["alpha"], ["gamma"]])

        XCTAssertEqual(
            ModelPickerCatalogPolicy.sortedPins([
                ModelPin(providerSlug: "beta", modelID: "zeta"),
                ModelPin(providerSlug: nil, modelID: "local"),
                ModelPin(providerSlug: "alpha", modelID: "zeta"),
                ModelPin(providerSlug: "alpha", modelID: "alpha"),
            ]),
            [
                ModelPin(providerSlug: nil, modelID: "local"),
                ModelPin(providerSlug: "alpha", modelID: "alpha"),
                ModelPin(providerSlug: "alpha", modelID: "zeta"),
                ModelPin(providerSlug: "beta", modelID: "zeta"),
            ]
        )
    }

    func testScopeNoticePrioritizesActiveSendThenProviderAvailability() {
        XCTAssertEqual(
            ModelPickerCatalogPolicy.scopeNotice(
                isSending: true,
                hasProviders: false
            ),
            "Wait for this session's current turn to finish before changing model settings."
        )
        XCTAssertEqual(
            ModelPickerCatalogPolicy.scopeNotice(
                isSending: false,
                hasProviders: false
            ),
            "This session keeps its current model."
        )
        XCTAssertEqual(
            ModelPickerCatalogPolicy.scopeNotice(
                isSending: false,
                hasProviders: true
            ),
            "Changes apply only to this session, from the next message."
        )
    }

    private func makeProvider(
        slug: String = "provider",
        name: String? = "Provider",
        models: [String],
        capabilities: [String: ModelCapabilities] = [:],
        pricing: [String: ModelPricing] = [:],
        unavailable: Set<String> = []
    ) -> ModelProvider {
        ModelProvider(
            slug: slug,
            name: name,
            authenticated: true,
            isCurrent: true,
            models: models,
            capabilities: capabilities,
            pricing: pricing,
            unavailableModels: unavailable
        )
    }
}
