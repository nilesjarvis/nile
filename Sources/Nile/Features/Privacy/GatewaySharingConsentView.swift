import SwiftUI

struct GatewaySharingConsentView: View {
    let request: GatewaySharingConsentRequest
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Share data with this gateway?")
                        .font(NileTypography.font(size: 26, weight: .semibold, relativeTo: .title))
                    Text(request.endpoint.baseURL)
                        .font(NileTypography.bodyMedium.weight(.semibold))
                        .textSelection(.enabled)
                        .accessibilityIdentifier(NileAccessibilityID.sharingDestination)
                    Text("Nile will connect and send the messages, selected photos, microphone recordings, and text for spoken replies you choose to use to this Hermes gateway.")
                    Text("The gateway may share these with its configured third-party AI, speech, and tool providers. Its operator chooses those providers and their data retention policies. Ask the operator which providers receive your data and review their policies before continuing.")
                    Text("Only continue if you trust this gateway and its providers. You can withdraw permission in Privacy & Data. Withdrawal does not delete data already sent.")
                    Text("AI responses may be inaccurate. Review answers and actions before relying on them.")
                        .foregroundStyle(NileColors.muted)
                    Button(action: onApprove) {
                        Text("Allow Sharing and Connect")
                            .font(NileTypography.bodyLarge.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .nileGlassButton(prominent: true)
                    .accessibilityIdentifier(NileAccessibilityID.sharingApprove)
                    Button(action: onCancel) {
                        Text("Not Now")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(NileAccessibilityID.sharingCancel)
                }
                .padding(20)
            }
            .font(NileTypography.bodyMedium)
            .foregroundStyle(NileColors.text)
            .background(NileColors.background)
            .navigationTitle("Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(NileAccessibilityID.sharingConsent)
        }
        .interactiveDismissDisabled()
    }
}
