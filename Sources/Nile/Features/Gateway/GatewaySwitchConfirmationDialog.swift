import SwiftUI

struct GatewaySwitchConfirmationDialog: View {
    let profile: GatewayProfile
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    private let warning =
        "A Hermes turn is still running on the current gateway. "
        + "It may continue after you switch, but Nile will no longer follow it."

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("Switch to \(profile.displayName)?")
                    .font(
                        NileTypography.font(
                            size: 24,
                            weight: .regular,
                            relativeTo: .title2
                        )
                    )
                    .foregroundStyle(NileColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                NileComposeText(
                    text: warning,
                    style: NileTypography.bodyLargeStyle,
                    color: UIColor(NileColors.warning),
                    backgroundColor: UIColor(NileColors.panel),
                    fillsWidth: true
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)

                HStack(spacing: 8) {
                    Button("Stay here", action: onDismiss)
                        .buttonStyle(.plain)
                        .font(
                            NileTypography.font(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(NileColors.text)
                        .frame(width: 84)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier(
                            NileAccessibilityID.dismissGatewaySwitch
                        )

                    Button(action: onConfirm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: NileRadii.control)
                                .fill(NileColors.accentStrong)
                                .frame(height: 40)
                            Text("Switch gateway")
                                .font(
                                    NileTypography.font(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(NileColors.onAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 148)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier(
                        NileAccessibilityID.confirmGatewaySwitch
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 24)
            }
            .padding(24)
            .frame(
                maxWidth: 320,
                minHeight: 224,
                alignment: .topLeading
            )
            .nileGlass(cornerRadius: NileRadii.window)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.gatewaySwitchDialog)
        }
    }
}
