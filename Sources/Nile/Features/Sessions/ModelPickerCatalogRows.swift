import SwiftUI

extension ModelPickerCatalogView {
    func modelRow(
        provider: ModelProvider,
        modelID: String,
        shortcut: Bool = false,
        optionID: String,
        pinID: String,
        supportingText: String? = nil
    ) -> some View {
        let selected = model.liveSession?.info.model == modelID
            && model.resolvedCurrentModelProviderSlug == provider.slug
        let unavailable = provider.unavailableModels.contains(modelID)
        let pinned = model.isModelPinned(
            provider: provider.slug,
            model: modelID
        )
        let detail = supportingText ?? (
            unavailable
                ? provider.freeTier == true
                    ? "Requires this provider's paid tier"
                    : "Unavailable for this provider account"
                : ModelPickerCatalogPolicy.supportingLabel(
                    provider: provider,
                    model: modelID
                )
        )
        return HStack(spacing: 0) {
            Button {
                model.selectModel(modelID, provider: provider.slug)
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName: selected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(
                        selected ? NileColors.accent : Color.clear
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        ModelPickerText(
                            modelID,
                            style: NileTypography.monospaceBodyMediumStyle,
                            color:
                                unavailable
                                    ? NileColors.warning
                                    : selected
                                        ? NileColors.accent
                                        : controlsEnabled
                                            ? NileColors.text
                                            : NileColors.muted,
                            background:
                                selected
                                    ? NileColors.panelAlt
                                    : NileColors.panel,
                            fillsWidth: true
                        )
                        if let detail {
                            ModelPickerText(
                                detail,
                                style: NileTypography.materialLabelSmallStyle,
                                color:
                                    unavailable
                                        ? NileColors.warning
                                        : NileColors.muted,
                                background:
                                    selected
                                        ? NileColors.panelAlt
                                        : NileColors.panel,
                                fillsWidth: true
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controlsEnabled || unavailable)
            .accessibilityValue(
                shortcut && selected
                    ? "Current model"
                    : selected
                        ? "Selected"
                        : ""
            )
            .accessibilityIdentifier(optionID)

            modelPinButton(
                pinned: pinned,
                provider: provider.slug,
                modelID: modelID,
                providerLabel: provider.name ?? provider.slug,
                section: shortcut
                    ? "pinned shortcuts"
                    : "provider catalog",
                identifier: pinID
            )
        }
        .frame(minHeight: 54)
        .background(selected ? NileColors.panelAlt : NileColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func unresolvedPinRow(_ pin: ModelPin) -> some View {
        let providerLabel = pin.providerSlug ?? "Unknown provider"
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("  \(pin.modelID)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(NileColors.warning)
                Text("\(providerLabel) · No longer available")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.warning)
                    .lineLimit(1)
                    .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.leading, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                NileAccessibilityID.pinnedModelOption(
                    provider: pin.providerSlug,
                    model: pin.modelID
                )
            )
            modelPinButton(
                pinned: true,
                provider: pin.providerSlug,
                modelID: pin.modelID,
                providerLabel: providerLabel,
                section: "pinned shortcuts",
                identifier: NileAccessibilityID.pinnedModelPinAction(
                    provider: pin.providerSlug,
                    model: pin.modelID
                )
            )
        }
        .background(NileColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func modelPinButton(
        pinned: Bool,
        provider: String?,
        modelID: String,
        providerLabel: String,
        section: String,
        identifier: String
    ) -> some View {
        Button {
            model.toggleModelPin(provider: provider, model: modelID)
        } label: {
            Group {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        pinned
                            ? NileColors.accent
                            : NileColors.muted.opacity(0.7)
                    )
            }
                .frame(width: 20, height: 20)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .disabled(!model.canModifyModelPins)
        .accessibilityLabel(
            "\(pinned ? "Unpin" : "Pin") \(modelID) from \(providerLabel) in \(section)"
        )
        .accessibilityValue(pinned ? "Pinned" : "Not pinned")
        .accessibilityIdentifier(identifier)
    }
}
