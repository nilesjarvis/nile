import SwiftUI

struct HermesVoiceLoadingView: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(NileColors.accent)
            Text(label)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(NileAccessibilityID.hermesVoiceLoading)
    }
}

struct HermesVoiceFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HermesVoiceNotice(text: message, color: NileColors.error)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(
                    NileAccessibilityID.hermesVoiceError
                )
            Button("Retry", action: onRetry)
                .buttonStyle(NileTextButtonStyle())
                .accessibilityIdentifier(
                    NileAccessibilityID.hermesVoiceRetry
                )
        }
    }
}

struct HermesVoiceNotice: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(NileTypography.bodySmall)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NileColors.panelAlt)
            .clipShape(
                RoundedRectangle(cornerRadius: NileRadii.small)
            )
    }
}

struct HermesVoiceMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                }
            }
    }
}
