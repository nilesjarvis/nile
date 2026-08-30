import SwiftUI

struct HermesVoiceEditorView: View {
    let config: HermesVoiceConfig
    let isLoading: Bool
    let isUpdating: Bool
    let error: String?
    @Binding var draftVoice: String
    @FocusState.Binding var isVoiceFocused: Bool
    let onRetry: () -> Void
    let onApply: (String) -> Void

    private var presets: [HermesVoicePreset] {
        HermesVoicePresentation.presets(config.provider)
    }

    private var controlsEnabled: Bool {
        !isUpdating && !isLoading
    }

    private var trimmedDraft: String {
        HermesVoicePresentation.normalizedVoice(draftVoice)
    }

    private var canApply: Bool {
        HermesVoicePresentation.canApply(
            draftVoice: draftVoice,
            currentVoice: config.voice,
            controlsEnabled: controlsEnabled
        )
    }

    @ViewBuilder
    var body: some View {
        if isLoading {
            HermesVoiceLoadingView(label: "Refreshing voice…")
        }
        if let error {
            HermesVoiceFailureView(message: error, onRetry: onRetry)
        }

        VStack(alignment: .leading, spacing: 5) {
            Text("Provider")
                .font(NileTypography.labelMedium)
                .foregroundStyle(NileColors.muted)
            Text(HermesVoicePresentation.providerLabel(config.provider))
                .font(
                    NileTypography.font(
                        size: 14,
                        weight: .medium,
                        relativeTo: .headline
                    )
                )
                .frame(minHeight: 20, alignment: .leading)
            Text(
                "The provider is managed by Hermes. Nile changes only its voice."
            )
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NileColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.card)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .accessibilityValue("Read only provider")
        .accessibilityIdentifier(
            NileAccessibilityID.hermesVoiceProvider
        )
        .padding(.top, 2.5)

        Text("Current voice · \(config.voice)")
            .font(NileTypography.monospaceBodySmall)
            .foregroundStyle(NileColors.muted)
            .accessibilityIdentifier(
                NileAccessibilityID.hermesVoiceCurrent
            )

        if !presets.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Suggested voices")
                    .font(NileTypography.labelMedium)
                    .foregroundStyle(NileColors.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            presetButton(
                                preset,
                                provider: config.provider,
                                selected: trimmedDraft == preset.voice,
                                enabled: controlsEnabled
                            )
                        }
                    }
                    .frame(height: 48)
                }
                .padding(.top, 1)
            }
            .accessibilityIdentifier(
                NileAccessibilityID.hermesVoicePresets
            )
        }

        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Voice",
                text: Binding(
                    get: { draftVoice },
                    set: { draftVoice = String($0.prefix(128)) }
                )
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isVoiceFocused)
            .disabled(!controlsEnabled)
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(NileColors.panel)
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.small)
                    .stroke(
                        isVoiceFocused
                            ? NileColors.accent
                            : NileColors.border,
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topLeading) {
                Text("Voice")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .padding(.horizontal, 5)
                    .background(NileColors.panel)
                    .offset(x: 10, y: -7)
            }
            .accessibilityIdentifier(
                NileAccessibilityID.hermesVoiceInput
            )

            Text(
                presets.isEmpty
                    ? "Enter the voice identifier supported by this provider."
                    : "Choose a suggestion or enter another supported voice identifier."
            )
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.muted)
            .padding(.leading, 14)
        }
        .padding(.top, 12)

        HermesVoiceNotice(
            text: "This changes the global Hermes voice for every app and client using this gateway.",
            color: NileColors.warning
        )
        .padding(.top, 6)
        .accessibilityIdentifier(
            NileAccessibilityID.hermesVoiceGlobalWarning
        )

        Button {
            isVoiceFocused = false
            onApply(trimmedDraft)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: NileRadii.control)
                    .fill(
                        canApply
                            ? NileColors.accentStrong
                            : Color(hex: 0x3C3C3C)
                    )
                    .frame(height: 40)
                HStack(spacing: 8) {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(NileColors.text)
                    }
                    Text(isUpdating ? "Applying…" : "Apply voice")
                        .font(NileTypography.titleMedium)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(
                canApply
                    ? NileColors.onAccent
                    : Color(hex: 0x858585)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HermesVoiceMaterialButtonStyle())
        .disabled(!canApply)
        .padding(.top, 2)
        .accessibilityIdentifier(NileAccessibilityID.hermesVoiceApply)
    }

    private func presetButton(
        _ preset: HermesVoicePreset,
        provider: String,
        selected: Bool,
        enabled: Bool
    ) -> some View {
        Button {
            draftVoice = preset.voice
        } label: {
            Text(preset.label)
                .font(NileTypography.titleMedium)
                .foregroundStyle(
                    enabled ? NileColors.text : NileColors.muted
                )
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(
                    selected
                        ? NileColors.accentSoft
                        : NileColors.panel
                )
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
                .overlay {
                    RoundedRectangle(cornerRadius: NileRadii.control)
                        .strokeBorder(
                            selected
                                ? NileColors.accentSoft
                                : NileColors.border,
                            lineWidth: 1
                        )
                }
                .frame(height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier(
            NileAccessibilityID.hermesVoicePreset(
                provider: provider,
                voice: preset.voice
            )
        )
    }
}
