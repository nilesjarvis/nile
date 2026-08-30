import Foundation

enum ModelPickerCatalogPolicy {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func filteredProviders(
        _ providers: [ModelProvider], query: String
    ) -> [(ModelProvider, [String])] {
        let normalized = normalizedQuery(query).lowercased()
        return providers.compactMap { provider in
            let allModels = orderedModels(provider)
            let providerMatches = !normalized.isEmpty
                && [provider.name, provider.slug].compactMap { $0 }
                    .contains { $0.lowercased().contains(normalized) }
            let models = normalized.isEmpty || providerMatches
                ? allModels
                : allModels.filter { $0.lowercased().contains(normalized) }
            return models.isEmpty ? nil : (provider, models)
        }
    }

    static func pinnedProviders(
        _ providers: [ModelProvider], pins: Set<ModelPin>
    ) -> [(ModelProvider, [String])] {
        providers.compactMap { provider in
            let models = orderedModels(provider).filter {
                pins.contains(ModelPin(providerSlug: provider.slug, modelID: $0))
            }
            return models.isEmpty ? nil : (provider, models)
        }
    }

    static func sortedPins(_ pins: Set<ModelPin>) -> [ModelPin] {
        pins.sorted {
            ($0.providerSlug ?? "", $0.modelID)
                < ($1.providerSlug ?? "", $1.modelID)
        }
    }

    static func scopeNotice(isSending: Bool, hasProviders: Bool) -> String {
        if isSending {
            return "Wait for this session's current turn to finish before changing model settings."
        }
        return hasProviders
            ? "Changes apply only to this session, from the next message."
            : "This session keeps its current model."
    }

    static func orderedModels(_ provider: ModelProvider) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for model in provider.models
            + provider.unavailableModels.sorted() where seen.insert(model).inserted {
            result.append(model)
        }
        return result
    }

    static func supportingLabel(
        provider: ModelProvider, model: String
    ) -> String? {
        var parts: [String] = []
        if provider.capabilities[model]?.fast == true {
            parts.append("Fast")
        }
        if provider.capabilities[model]?.reasoning == true {
            parts.append("Reasoning")
        }
        if let pricing = pricingLabel(provider: provider, model: model) {
            parts.append(pricing)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func pricingLabel(
        provider: ModelProvider, model: String
    ) -> String? {
        guard let pricing = provider.pricing[model] else { return nil }
        if pricing.free {
            return "free"
        }
        let parts = [
            pricing.input.flatMap {
                $0.isBlank ? nil : "in \($0)"
            },
            pricing.output.flatMap {
                $0.isBlank ? nil : "out \($0)"
            },
            pricing.cache.flatMap {
                $0.isBlank ? nil : "cache \($0)"
            },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " /M tokens"
    }
}
