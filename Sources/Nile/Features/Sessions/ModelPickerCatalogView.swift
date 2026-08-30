import SwiftUI

/// Search, provider expansion, pinning, and model selection for the session
/// model picker. The parent overlay owns only sheet-level status and reasoning
/// controls; catalog-local interaction state stays here.
struct ModelPickerCatalogView: View {
    @Bindable var model: SessionListModel
    let controlsEnabled: Bool
    @Binding var searchIsFocused: Bool

    @State private var query = ""
    @State private var expandedProviders: Set<String> = []
    @State private var collapsedProviders: Set<String> = []
    @FocusState private var catalogSearchIsFocused: Bool

    private var filteredProviders: [(ModelProvider, [String])] {
        ModelPickerCatalogPolicy.filteredProviders(model.selectableModelProviders, query: query)
    }

    private var normalizedQuery: String {
        ModelPickerCatalogPolicy.normalizedQuery(query)
    }

    private var pinnedCatalogGroups: [(ModelProvider, [String])] {
        ModelPickerCatalogPolicy.pinnedProviders(model.selectableModelProviders, pins: model.resolvedPinnedModels)
    }

    private var sortedUnresolvedPins: [ModelPin] {
        ModelPickerCatalogPolicy.sortedPins(model.unresolvedPinnedModels)
    }

    private var providerExpansionSeed: [String] {
        [
            model.liveSession?.info.model ?? "",
            model.resolvedCurrentModelProviderSlug ?? "",
        ] + model.selectableModelProviders.map(\.slug)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelPickerText(
                "Models",
                style: NileTypography.bodyMediumSemiboldStyle,
                color: NileColors.text,
                background: NileColors.background
            )
            .padding(.top, 10)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NileColors.muted)
                TextField("Search models", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(NileColors.text)
                    .tint(NileColors.accent)
                    .focused($catalogSearchIsFocused)
                    .accessibilityLabel("Search models")
                    .accessibilityIdentifier(NileAccessibilityID.modelSearch)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(NileColors.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear model search")
                }
            }
                .padding(.horizontal, 10)
                .frame(minHeight: 40)
                .nileGlass(cornerRadius: NileRadii.small, tint: NileColors.inset)
                .disabled(model.isUpdatingSessionControls)

            if let currentModel = model.liveSession?.info.model {
                VStack(alignment: .leading, spacing: 2) {
                    ModelPickerText(
                        "Current model",
                        style: NileTypography.bodySmallStyle,
                        color: NileColors.muted,
                        background: NileColors.surfaceRaised
                    )
                    ModelPickerText(
                        currentModel,
                        style: NileTypography.monospaceBodyMediumStyle,
                        color: NileColors.accent,
                        background: NileColors.surfaceRaised
                    )
                    if let provider = model.liveSession?.info.provider {
                        ModelPickerText(
                            provider,
                            style: NileTypography.bodySmallStyle,
                            color: NileColors.muted,
                            background: NileColors.surfaceRaised
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nilePanel()
            }

            if normalizedQuery.isEmpty,
               !pinnedCatalogGroups.isEmpty
                || !sortedUnresolvedPins.isEmpty {
                Label(
                    "Pinned (\(model.resolvedPinnedModels.count + sortedUnresolvedPins.count))",
                    systemImage: "pin.fill"
                )
                    .font(.headline)
                    .foregroundStyle(NileColors.text)
                    .padding(.top, 8)

                ForEach(pinnedCatalogGroups, id: \.0.slug) {
                    provider, models in
                    ForEach(models, id: \.self) { modelID in
                        modelRow(
                            provider: provider,
                            modelID: modelID,
                            shortcut: true,
                            optionID: NileAccessibilityID
                                .pinnedModelOption(
                                    provider: provider.slug,
                                    model: modelID
                                ),
                            pinID: NileAccessibilityID
                                .pinnedModelPinAction(
                                    provider: provider.slug,
                                    model: modelID
                                ),
                            supportingText:
                                provider.name ?? provider.slug
                        )
                    }
                }

                ForEach(
                    sortedUnresolvedPins,
                    id: \.self
                ) { pin in
                    unresolvedPinRow(pin)
                }
            }

            if filteredProviders.isEmpty,
               !model.isLoadingModelOptions,
               model.modelOptionsError == nil {
                ModelPickerText(
                    normalizedQuery.isEmpty
                        ? "No authenticated model providers are available on this gateway."
                        : "No models match “\(normalizedQuery)”.",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    background: NileColors.background,
                    fillsWidth: true
                )
                .padding(.vertical, 10)
            }

            ForEach(filteredProviders, id: \.0.slug) { provider, models in
                providerSection(provider: provider, models: models)
            }

            ModelPickerText(
                scopeNotice,
                style: NileTypography.bodySmallStyle,
                color: NileColors.muted,
                background: NileColors.panelAlt,
                fillsWidth: true
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NileColors.panelAlt)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
        }
        .onChange(of: providerExpansionSeed) {
            expandedProviders.removeAll()
            collapsedProviders.removeAll()
        }
        .onChange(of: catalogSearchIsFocused) {
            searchIsFocused = catalogSearchIsFocused
        }
    }

    private var scopeNotice: String {
        ModelPickerCatalogPolicy.scopeNotice(
            isSending: model.isSending,
            hasProviders: !model.selectableModelProviders.isEmpty
        )
    }

    private func providerSection(
        provider: ModelProvider,
        models: [String]
    ) -> some View {
        let expanded = !normalizedQuery.isEmpty
            || expandedProviders.contains(provider.slug)
            || (
                provider.slug == model.resolvedCurrentModelProviderSlug
                    && !collapsedProviders.contains(provider.slug)
            )
        return VStack(spacing: 8) {
            Button {
                if expanded {
                    expandedProviders.remove(provider.slug)
                    collapsedProviders.insert(provider.slug)
                } else {
                    expandedProviders.insert(provider.slug)
                    collapsedProviders.remove(provider.slug)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(
                        systemName: expanded
                            ? "chevron.down"
                            : "chevron.right"
                    )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            provider.slug
                                == model.resolvedCurrentModelProviderSlug
                                ? NileColors.accent
                                : NileColors.muted
                        )
                        .frame(width: 14)
                    ModelPickerText(
                        "\(provider.name ?? provider.slug) (\(models.count))\(provider.freeTier == true ? " · free tier" : "")",
                        style: NileTypography.bodyMediumStyle,
                        color:
                            provider.slug
                                == model.resolvedCurrentModelProviderSlug
                                ? NileColors.accent
                                : NileColors.text,
                        background: NileColors.background,
                        fillsWidth: true
                    )
                }
                .foregroundStyle(
                        provider.slug
                            == model.resolvedCurrentModelProviderSlug
                            ? NileColors.accent
                            : NileColors.text
                )
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controlsEnabled)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(
                NileAccessibilityID.modelProvider(provider.slug)
            )

            if expanded {
                ForEach(models, id: \.self) { modelID in
                    modelRow(
                        provider: provider,
                        modelID: modelID,
                        optionID: NileAccessibilityID.modelOption(
                            provider: provider.slug,
                            model: modelID
                        ),
                        pinID: NileAccessibilityID.modelPinAction(
                            provider: provider.slug,
                            model: modelID
                        )
                    )
                }
            }
        }
    }

}
