import SwiftUI

struct HermesVoiceSheetView: View {
    @Bindable var model: GatewaySetupModel
    @State private var draftVoice = ""
    @FocusState private var isVoiceFocused: Bool

    private var config: HermesVoiceConfig? {
        model.hermesVoiceConfig
    }

    private var configIdentity: String {
        guard let config else {
            return ""
        }
        return "\(config.provider.count):\(config.provider)|\(config.voice.count):\(config.voice)"
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    bodyContent
                    HStack {
                        Spacer()
                        Button("Close") {
                            isVoiceFocused = false
                            model.setHermesVoiceSheetVisible(false)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            model.isUpdatingHermesVoice
                                ? NileColors.muted
                                : NileColors.accent
                        )
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        // Keep the Android-aligned 40-point layout slot while
                        // exposing a full iOS accessibility target.
                        .padding(.vertical, -4)
                        .padding(.top, 4)
                        .disabled(model.isUpdatingHermesVoice)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    NileAccessibilityID.hermesVoiceContent
                )
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: 603)
        .background(NileColors.background)
        .foregroundStyle(NileColors.text)
        .font(NileTypography.bodyLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NileAccessibilityID.hermesVoiceSheet)
        .interactiveDismissDisabled(model.isUpdatingHermesVoice)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(NileRadii.sheet)
        .presentationBackground(NileColors.background)
        .presentationDetents([.height(603)])
        .onChange(of: configIdentity, initial: true) {
            guard let config else {
                return
            }
            draftVoice = config.voice
        }
    }

    private var dragHandle: some View {
        Button {
            isVoiceFocused = false
            model.setHermesVoiceSheetVisible(false)
        } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay {
                    Capsule()
                        .fill(NileColors.border)
                        .frame(width: 40, height: 4)
                }
        }
        .buttonStyle(.plain)
        // Preserve the 32-point visual slot while retaining the 48-point
        // semantic hit area around the centered handle.
        .padding(.vertical, -8)
        .disabled(model.isUpdatingHermesVoice)
        .accessibilityLabel("Close voice settings")
        .accessibilityIdentifier(
            NileAccessibilityID.hermesVoiceDragHandle
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hermes voice")
                .font(
                    NileTypography.font(
                        size: 20,
                        weight: .semibold,
                        relativeTo: .title3
                    )
                )
            Text("Choose how Hermes sounds when Nile speaks a reply.")
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if config == nil, model.isLoadingHermesVoice {
            HermesVoiceLoadingView(label: "Loading Hermes voice…")
        } else if let config {
            HermesVoiceEditorView(
                config: config,
                isLoading: model.isLoadingHermesVoice,
                isUpdating: model.isUpdatingHermesVoice,
                error: model.hermesVoiceError,
                draftVoice: $draftVoice,
                isVoiceFocused: $isVoiceFocused,
                onRetry: { model.refreshHermesVoice() },
                onApply: { voice in
                    model.applyHermesVoice(
                        expectedProvider: config.provider,
                        voice: voice
                    )
                }
            )
        } else if let error = model.hermesVoiceError {
            HermesVoiceFailureView(
                message: error,
                onRetry: { model.refreshHermesVoice() }
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice settings have not loaded yet.")
                    .font(NileTypography.bodyMedium)
                    .foregroundStyle(NileColors.muted)
                Button("Load voice settings") {
                    model.refreshHermesVoice()
                }
                .buttonStyle(NileTextButtonStyle())
                .accessibilityIdentifier(
                    NileAccessibilityID.hermesVoiceRetry
                )
            }
        }
    }
}
