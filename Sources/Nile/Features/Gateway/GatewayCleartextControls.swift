import SwiftUI

struct GatewayCleartextWarning: View {
    let isSupported: Bool
    let usesAndroidVisualParityCopy: Bool

    var body: some View {
        NileComposeText(
            text: message,
            style: NileTypography.bodySmallStyle,
            color: UIColor(
                isSupported ? NileColors.warning : NileColors.error
            ),
            backgroundColor: UIColor(NileColors.panelAlt),
            fillsWidth: true
        )
            .padding(10)
            .offset(y: -1.0 / 3.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: NileRadii.small)
                    .fill(NileColors.panelAlt)
            }
            .accessibilityIdentifier(
                NileAccessibilityID.gatewayCleartextWarning
            )
    }

    private var message: String {
        if isSupported {
            let localRuntime = usesAndroidVisualParityCopy
                ? "emulator"
                : "simulator"
            return "Unencrypted connection: anyone on this network may be able "
                + "to read your token, prompts, responses, approvals, and "
                + "commands. Use only a trusted \(localRuntime), LAN, or VPN."
        }
        return "This build requires HTTPS. Use an HTTPS endpoint, or install "
            + "the local build for trusted simulator or LAN HTTP."
    }
}

struct GatewayCleartextApproval: View {
    let isApproved: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(
                    systemName: isApproved
                        ? "checkmark.square.fill"
                        : "square"
                )
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    isApproved ? NileColors.accent : NileColors.muted
                )
                Text(
                    "Allow unencrypted connection on this trusted network"
                )
                .font(.subheadline)
                .foregroundStyle(NileColors.text)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "I trust this local network and allow an unencrypted connection"
        )
        .accessibilityValue(isApproved ? "Approved" : "Not approved")
        .accessibilityAddTraits(isApproved ? .isSelected : [])
        .accessibilityIdentifier(NileAccessibilityID.approveCleartext)
    }
}
