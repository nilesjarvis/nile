import SwiftUI

struct SecureBlockingPromptOverlay: View {
    let prompt: TranscriptBlockingPrompt
    let onDismiss: () -> Void
    let onSubmit: (String) -> Void
    @State private var value = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    value = ""
                    onDismiss()
                }
            VStack(alignment: .leading, spacing: 12) {
                Text(prompt.title)
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.text)
                Text(
                    prompt.kind == .sudo
                        ? "Enter the administrator password. Nile does not save it."
                        : "Enter the requested secret. Nile does not save it."
                )
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                SecureField(
                    prompt.kind == .sudo ? "Password" : "Secret",
                    text: $value
                )
                .textContentType(.password)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.text)
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(NileColors.panelAlt)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NileColors.border, lineWidth: 1)
                }
                .accessibilityLabel("Secure response")
                .accessibilityIdentifier(
                    NileAccessibilityID.blockingPromptSecureEntry
                )
                .privacySensitive()
                HStack {
                    Button("Cancel") {
                        value = ""
                        onDismiss()
                    }
                    .frame(minWidth: 48, minHeight: 48)
                    Spacer()
                    Button("Continue") {
                        let response = value
                        value = ""
                        onSubmit(response)
                    }
                    .disabled(value.isEmpty)
                    .frame(minWidth: 48, minHeight: 48)
                    .accessibilityIdentifier(
                        NileAccessibilityID.blockingPromptSecureSubmit
                    )
                }
                .font(NileTypography.bodyMedium.weight(.semibold))
                .foregroundStyle(NileColors.text)
            }
            .padding(20)
            .background(NileColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.card)
                    .stroke(NileColors.border, lineWidth: 1)
            }
            .padding(.horizontal, 24)
            .privacySensitive()
        }
    }
}

struct PermanentApprovalOverlay: View {
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 12) {
                Text("Always allow matching commands?")
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.text)
                Text(
                    "Hermes will also allow future commands that match this approval pattern. Only continue if you trust those matching commands."
                )
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
                HStack {
                    Button("Go back", action: onDismiss)
                        .frame(minWidth: 48, minHeight: 48)
                    Spacer()
                    Button("Always allow", action: onConfirm)
                        .frame(minWidth: 48, minHeight: 48)
                        .accessibilityIdentifier(
                            NileAccessibilityID.blockingPromptAlwaysConfirm
                        )
                }
                .font(NileTypography.bodyMedium.weight(.semibold))
                .foregroundStyle(NileColors.text)
            }
            .padding(20)
            .background(NileColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.card)
                    .stroke(NileColors.border, lineWidth: 1)
            }
            .padding(.horizontal, 24)
        }
    }
}
