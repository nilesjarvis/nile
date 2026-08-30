import SwiftUI

/// Fail-closed confirmation surface for costly session-model changes.
struct ModelSwitchConfirmationOverlay: View {
    let confirmation: ModelSwitchConfirmation
    let updating: Bool
    let canConfirm: Bool
    let error: String?
    let onDismissError: () -> Void
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    if !updating {
                        onDismiss()
                    }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Switch to \(confirmation.model)?")
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.text)
                if updating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(NileColors.accent)
                        Text("Applying model settings…")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        NileAccessibilityID.modelSwitchProgress
                    )
                }
                if let error {
                    Button(action: onDismissError) {
                        Text("\(error) — tap to dismiss")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.error)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 48,
                                maxHeight: 96,
                                alignment: .leading
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(error). Dismiss error")
                    .accessibilityIdentifier(
                        NileAccessibilityID.sessionControlError
                    )
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(confirmation.message)
                            .font(NileTypography.bodyMedium)
                            .foregroundStyle(NileColors.prose)
                        Text("Provider: \(confirmation.provider)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(NileColors.muted)
                        Text("This changes only this session.")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                        if !canConfirm, !updating {
                            Text(
                                "Wait for the current turn to finish before confirming."
                            )
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.warning)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                .accessibilityIdentifier(
                    NileAccessibilityID.modelConfirmationBody
                )
                HStack {
                    Button("Cancel", action: onDismiss)
                        .disabled(updating)
                    Spacer()
                    Button(
                        updating
                            ? "Switching…"
                            : canConfirm
                                ? "Switch model"
                                : "Wait for turn",
                        action: onConfirm
                    )
                        .buttonStyle(NileTextButtonStyle(prominent: true))
                        .disabled(!canConfirm)
                        .accessibilityIdentifier(
                            NileAccessibilityID.confirmModelSwitch
                        )
                }
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.window))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.window)
                    .stroke(NileColors.border, lineWidth: 1)
            }
            .padding(24)
        }
        .accessibilityIdentifier(NileAccessibilityID.modelConfirmation)
    }
}
