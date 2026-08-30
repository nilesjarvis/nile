import SwiftUI

struct GatewayRemovalConfirmationDialog: View {
    let profile: GatewayProfile
    let message: String
    let error: String?
    let isRemoving: Bool
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isRemoving else {
                        return
                    }
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 0) {
                Text("Remove \(profile.displayName)?")
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
                    text: primaryMessage,
                    style: NileTypography.bodyLargeStyle,
                    color: UIColor(NileColors.prose),
                    backgroundColor: UIColor(NileColors.panel),
                    fillsWidth: true
                )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)

                if let activeGatewayWarning {
                    NileComposeText(
                        text: activeGatewayWarning,
                        style: NileTypography.bodySmallStyle,
                        color: UIColor(NileColors.warning),
                        backgroundColor: UIColor(NileColors.panel),
                        fillsWidth: true
                    )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                if let error {
                    Text(error)
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                HStack(spacing: 8) {
                    Button("Cancel", action: onDismiss)
                        .buttonStyle(.plain)
                        .font(
                            NileTypography.font(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(NileColors.text)
                        .frame(width: 108)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                        .disabled(isRemoving)
                        .accessibilityIdentifier(
                            NileAccessibilityID.cancelRemoveGateway
                        )

                    Button(action: onConfirm) {
                        HStack(spacing: 8) {
                            if isRemoving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(NileColors.onAccent)
                            }
                            Text(
                                isRemoving
                                    ? "Removing…"
                                    : "Remove gateway"
                            )
                        }
                        .font(
                            NileTypography.font(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(NileColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(NileColors.error)
                        .clipShape(
                            RoundedRectangle(cornerRadius: NileRadii.control)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 156)
                    .frame(minHeight: 48)
                    .disabled(isRemoving)
                    .accessibilityIdentifier(
                        NileAccessibilityID.confirmRemoveGateway
                    )
                }
                .padding(.top, 22)
            }
            .padding(24)
            .frame(
                maxWidth: 320,
                minHeight: 281,
                alignment: .topLeading
            )
            .nileGlass(cornerRadius: NileRadii.window)
            .padding(.horizontal, 24)
        }
    }

    private var primaryMessage: String {
        message.components(separatedBy: " Nile will disconnect").first
            ?? message
    }

    private var activeGatewayWarning: String? {
        guard let range = message.range(
            of: "Nile will disconnect"
        ) else {
            return nil
        }
        return String(message[range.lowerBound...])
    }
}
