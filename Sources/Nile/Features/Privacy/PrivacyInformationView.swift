import SwiftUI

struct PrivacyInformationView: View {
    @Bindable var gateway: GatewaySetupModel
    let cleanup: PrivacyCleanupModel?
    @State private var confirmsWithdrawal = false

    var body: some View {
        Form {
            Section("Where your data goes") {
                Text("Nile connects to the Hermes gateway you choose. Messages, selected photos, recorded microphone audio, and text for spoken replies are sent to that gateway when you use those features.")
                Text("Your gateway can forward this data to its configured AI, transcription, speech, and tool providers. The gateway operator chooses those providers and controls their retention and use of your data. Ask the operator which providers are enabled and review their privacy policies before sharing personal information.")
                Text("Nile does not operate an AI service and includes no advertising or analytics SDKs. AI responses can be inaccurate; review responses and proposed actions before relying on them.")
            }
            Section("On this iPhone") {
                Text("Saved gateway credentials use the device Keychain. Gateway settings, unsent text and photo drafts, and pins use protected local files excluded from backup. Downloaded previews use a protected, size-limited cache. Dashboard sign-in uses cookies and website storage in Nile's browser.")
                Text("Camera, photo selection, microphone, notifications, and biometric locking are optional. You can change system permissions in iOS Settings. Text chat works without camera or microphone access.")
            }
            Section("Your choices") {
                Button("Withdraw AI sharing consent", role: .destructive) {
                    confirmsWithdrawal = true
                }
                .disabled(gateway.isChecking)
                .accessibilityIdentifier(NileAccessibilityID.privacyWithdraw)
                Text("Withdrawal disconnects Nile and asks for permission again before connecting to any gateway. It does not recall data already sent or stop work already running on Hermes.")
                Text("To delete a saved gateway, open Settings → Gateway → Gateway actions → Remove. This removes its saved credentials, sign-in cookies, drafts, and pins from Nile. To delete conversations or a server account, use Hermes or contact your gateway operator; removing a gateway from Nile does not delete server data.")
            }
            if let cleanup {
                PrivacyCleanupControls(model: cleanup)
            }
            Section("About Nile") {
                if let url = PrivacyLinks.privacyPolicyURL {
                    Link("Privacy Policy", destination: url)
                        .accessibilityIdentifier(NileAccessibilityID.privacyPolicy)
                }
                if let url = PrivacyLinks.supportURL {
                    Link("Contact Support", destination: url)
                        .accessibilityIdentifier(NileAccessibilityID.privacySupport)
                }
                NavigationLink("Software Notices") {
                    SoftwareNoticesView()
                }
                .accessibilityIdentifier(NileAccessibilityID.softwareNotices)
            }
        }
        .font(NileTypography.bodyMedium)
        .foregroundStyle(NileColors.text)
        .scrollContentBackground(.hidden)
        .background(NileColors.background)
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier(NileAccessibilityID.privacyInformation)
        .alert("Withdraw sharing consent?", isPresented: $confirmsWithdrawal) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect and Withdraw", role: .destructive) {
                Task { await gateway.revokeSharingConsent() }
            }
            .accessibilityIdentifier(NileAccessibilityID.privacyWithdrawConfirm)
        } message: {
            Text("Nile will disconnect. Saved gateways and drafts remain on this iPhone, and data already sent remains subject to your gateway and provider policies.")
        }
    }
}

private struct PrivacyCleanupControls: View {
    @Bindable var model: PrivacyCleanupModel
    @State private var confirmsCleanup = false

    var body: some View {
        Section("Downloaded files and browser data") {
            Button("Clear Downloads and Website Data", role: .destructive) {
                confirmsCleanup = true
            }
            .disabled(!model.canClearData)
            .accessibilityIdentifier(NileAccessibilityID.privacyClear)
            Text("Clears all downloaded previews and Nile's browser cookies, caches, and website storage, including identity-provider sign-ins. Saved gateway tokens and unsent drafts remain. Withdraw sharing consent first if Nile is connected.")
            if model.isClearing {
                ProgressView("Clearing local data…")
            } else if let error = model.errorMessage {
                Text(error).foregroundStyle(NileColors.error)
            } else if model.didClearData {
                Text("Downloads and website data cleared.")
                    .accessibilityIdentifier(NileAccessibilityID.privacyCleared)
            }
        }
        .alert("Clear downloads and website data?", isPresented: $confirmsCleanup) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Data", role: .destructive) {
                Task { await model.clearLocalCaches() }
            }
            .accessibilityIdentifier(NileAccessibilityID.privacyClearConfirm)
        } message: {
            Text("This signs out all websites in Nile and removes downloaded previews. Server conversations, saved gateway tokens, and unsent drafts are kept.")
        }
    }
}
