import SwiftUI

/// Notification permission education presented above the active app surface.
///
/// Permission state and persistence remain owned by `NotificationEducationModel`.
struct NotificationEducationView: View {
    @Bindable var model: NotificationEducationModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.64)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.dismiss()
                }

            VStack(alignment: .leading, spacing: 16) {
                Text("Stay in the loop")
                    .font(NileTypography.titleLarge)
                    .foregroundStyle(NileColors.text)

                Text(
                    "Get notified when a long-running session finishes or needs a decision."
                )
                .font(NileTypography.bodyLarge)
                .foregroundStyle(NileColors.muted)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Not now") {
                        model.dismiss()
                    }
                    .buttonStyle(NotificationEducationButtonStyle())
                    .accessibilityIdentifier(
                        NileAccessibilityID.notificationEducationDismiss
                    )

                    Button("Enable notifications") {
                        model.enableNotifications()
                    }
                    .buttonStyle(NotificationEducationButtonStyle())
                    .accessibilityIdentifier(
                        NileAccessibilityID.notificationEducationEnable
                    )
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .nileGlass(cornerRadius: NileRadii.window)
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                NileAccessibilityID.notificationEducation
            )
        }
        .zIndex(100)
    }
}

private struct NotificationEducationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NileColors.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
