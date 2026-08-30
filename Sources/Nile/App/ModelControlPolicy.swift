import Foundation

struct ModelSelectionAdmission: Equatable, Sendable {
    let model: String
    let provider: String
}

enum ModelSelectionDecision: Equatable, Sendable {
    case apply(ModelSelectionAdmission)
    case unchanged
    case rejected(String)
}

enum ReasoningSelectionDecision: Equatable, Sendable {
    case apply(String)
    case unchanged
    case rejected(String)
}

enum ModelPinAdmissionDecision: Equatable, Sendable {
    case allowed(ModelPin)
    case rejected(String)
}

struct ModelMutationFailure: Equatable, Sendable {
    let isUncertain: Bool
    let message: String
}

enum ModelControlPolicy {
    static func selectableProviders(
        from options: ModelOptions?
    ) -> [ModelProvider] {
        options?.providers.filter {
            $0.authenticated && !$0.models.isEmpty
        } ?? []
    }

    static func modelSelection(
        model: String,
        provider: String,
        currentInfo: SessionInfo,
        selectableProviders: [ModelProvider]
    ) -> ModelSelectionDecision {
        guard let selectedProvider = selectableProviders.first(
            where: { $0.slug == provider }
        ),
        selectedProvider.models.contains(model),
        !selectedProvider.unavailableModels.contains(model) else {
            return .rejected(
                "That model is not available for this gateway. Refresh the model list and try again."
            )
        }
        guard currentInfo.model != model
                || currentInfo.provider != provider else {
            return .unchanged
        }
        return .apply(
            ModelSelectionAdmission(model: model, provider: provider)
        )
    }

    static func reasoningSelection(
        effort: String,
        currentEffort: String?
    ) -> ReasoningSelectionDecision {
        let normalized = effort
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard reasoningEffortOptions.contains(normalized) else {
            return .rejected("That reasoning effort is not supported.")
        }
        guard currentEffort?.lowercased() != normalized else {
            return .unchanged
        }
        return .apply(normalized)
    }

    static func appliedModelNotice(
        resolvedModel: String,
        warning: String?
    ) -> String {
        [
            "switched this session to \(resolvedModel)",
            warning?.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        .compactMap { value in
            value.flatMap { $0.isBlank ? nil : $0 }
        }
        .joined(separator: "\n")
    }

    static func mutationFailure(_ error: any Error) -> ModelMutationFailure {
        let uncertain: Bool
        if let hermes = error as? HermesError {
            uncertain = hermes.isConnectionFailure
                || hermes.requestMayHaveSucceeded
        } else {
            uncertain = true
        }
        return ModelMutationFailure(
            isUncertain: uncertain,
            message: uncertain
                ? "Hermes may have changed this session's model, but Nile did not receive a valid confirmation. Reopen the model picker to verify before retrying."
                : error.localizedDescription
        )
    }

    static func reasoningNotice(_ effort: String) -> String {
        let normalized = effort
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let display = normalized == "none" ? "off" : normalized
        return "set this session's reasoning effort to \(display)"
    }

    static func pinAdmission(
        provider: String?,
        model: String
    ) -> ModelPinAdmissionDecision {
        let normalizedProvider = provider?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedModel = model.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedModel.isEmpty,
              normalizedModel == model,
              !normalizedModel.contains("\n"),
              !normalizedModel.contains("\r"),
              normalizedProvider == provider,
              normalizedProvider?.isEmpty != true,
              normalizedProvider?.contains("\n") != true,
              normalizedProvider?.contains("\r") != true else {
            return .rejected("That model pin is invalid.")
        }
        return .allowed(
            ModelPin(
                providerSlug: normalizedProvider,
                modelID: normalizedModel
            )
        )
    }

    static func resolvedPins(
        _ pins: Set<ModelPin>,
        selectableProviders: [ModelProvider]
    ) -> Set<ModelPin> {
        Set(
            pins.compactMap {
                resolvePin($0, selectableProviders: selectableProviders)
            }
        )
    }

    static func unresolvedPins(
        _ pins: Set<ModelPin>,
        selectableProviders: [ModelProvider]
    ) -> Set<ModelPin> {
        pins.filter {
            resolvePin($0, selectableProviders: selectableProviders) == nil
        }
    }

    static func isPinned(
        provider: String,
        model: String,
        pins: Set<ModelPin>,
        selectableProviders: [ModelProvider]
    ) -> Bool {
        if pins.contains(ModelPin(providerSlug: provider, modelID: model)) {
            return true
        }
        let legacy = ModelPin(providerSlug: nil, modelID: model)
        guard pins.contains(legacy) else {
            return false
        }
        return uniqueProviderSlug(
            for: model,
            selectableProviders: selectableProviders
        ) == provider
    }

    static func resolvedCurrentProvider(
        info: SessionInfo?,
        selectableProviders: [ModelProvider]
    ) -> ModelProvider? {
        if let provider = info?.provider {
            return selectableProviders.first { $0.slug == provider }
        }
        guard let model = info?.model else {
            return nil
        }
        let matches = providers(
            containing: model,
            selectableProviders: selectableProviders
        )
        return matches.count == 1 ? matches[0] : nil
    }

    private static func resolvePin(
        _ pin: ModelPin,
        selectableProviders: [ModelProvider]
    ) -> ModelPin? {
        let matches = providers(
            containing: pin.modelID,
            selectableProviders: selectableProviders
        )
        guard let provider = pin.providerSlug else {
            guard matches.count == 1 else {
                return nil
            }
            return ModelPin(
                providerSlug: matches[0].slug,
                modelID: pin.modelID
            )
        }
        return matches.contains(where: { $0.slug == provider }) ? pin : nil
    }

    private static func uniqueProviderSlug(
        for model: String,
        selectableProviders: [ModelProvider]
    ) -> String? {
        let matches = providers(
            containing: model,
            selectableProviders: selectableProviders
        )
        return matches.count == 1 ? matches[0].slug : nil
    }

    private static func providers(
        containing model: String,
        selectableProviders: [ModelProvider]
    ) -> [ModelProvider] {
        selectableProviders.filter {
            $0.models.contains(model) || $0.unavailableModels.contains(model)
        }
    }
}
