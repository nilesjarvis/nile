import SwiftUI

struct HermesVoiceEntryView: View {
    let config: HermesVoiceConfig?
    let enabled: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NileColors.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice")
                        .font(NileTypography.bodyLarge.weight(.semibold))
                        .foregroundStyle(
                            enabled ? NileColors.text : NileColors.muted
                        )
                    Text(subtitle)
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NileColors.faint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(NileAccessibilityID.hermesVoiceEntry)
    }

    private var subtitle: String {
        guard let config else {
            return "Spoken replies"
        }
        return "\(HermesVoicePresentation.providerLabel(config.provider)) · \(config.voice)"
    }
}
