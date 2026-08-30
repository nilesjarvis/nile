import SwiftUI

extension ModelPickerOverlay {
    var reasoningControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelPickerText(
                "Reasoning effort",
                style: NileTypography.bodyMediumSemiboldStyle,
                color: NileColors.text,
                background: NileColors.background
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            Rectangle().fill(NileColors.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Menu {
                    ForEach(reasoningEffortOptions, id: \.self) { effort in
                        Button(
                            Self.reasoningLabel(effort)
                        ) {
                            model.setReasoningEffort(effort)
                        }
                        .accessibilityIdentifier(
                            NileAccessibilityID.reasoningOption(effort)
                        )
                    }
                } label: {
                    HStack {
                        ModelPickerText(
                            Self.reasoningLabel(
                                model.liveSession?.info.reasoningEffort
                                    ?? "default"
                            ),
                            style: NileTypography.bodyMediumStyle,
                            color: reasoningSelectorEnabled
                                ? NileColors.text
                                : NileColors.muted,
                            background: reasoningSelectorBackground
                        )
                        Spacer()
                        if !model.currentModelSupportsReasoning {
                            ModelPickerText(
                                "Unsupported",
                                style: NileTypography.bodySmallStyle,
                                color: NileColors.warning,
                                background: reasoningSelectorBackground
                            )
                            .padding(.leading, 8)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NileColors.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .disabled(!reasoningSelectorEnabled)
                .nileGlass(cornerRadius: NileRadii.small, tint: NileColors.inset)
                .accessibilityIdentifier(
                    NileAccessibilityID.reasoningSelector
                )

                ModelPickerText(
                    reasoningFootnote,
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    background: NileColors.panelAlt,
                    fillsWidth: true
                )
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NileColors.inset)
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
            }
            .padding(10)
        }
        .nilePanel()
    }

    private var reasoningSelectorEnabled: Bool {
        controlsEnabled
            && model.currentModelSupportsReasoning
            && model.liveSession?.info
                .reasoningEffortSessionScopeSupported == true
    }

    private var reasoningSelectorBackground: Color {
        reasoningSelectorEnabled ? NileColors.panelAlt : NileColors.panel
    }

    private var reasoningFootnote: String {
        if model.liveSession?.info.reasoningEffortSessionScopeSupported != true {
            return "Update Hermes to enable safe per-session reasoning changes."
        }
        if !model.currentModelSupportsReasoning {
            return "\(model.liveSession?.info.model ?? "This model") does not advertise reasoning support."
        }
        return "Changes apply only to this session, from the next message."
    }

    private static func reasoningLabel(_ effort: String) -> String {
        let normalized = effort
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "none" ? "off" : normalized
    }
}
