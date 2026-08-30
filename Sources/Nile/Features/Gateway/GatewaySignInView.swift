import SwiftUI

struct GatewaySignInView: View {
    let loginURL: URL
    let fixtureHTML: String?
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var loading = true
    @State private var pageLoaded = false
    @State private var pageError: String?
    @State private var visibleOrigin: String
    @State private var approvedExternalOrigins: Set<String> = []
    @State private var pendingExternalURL: URL?
    @State private var reloadGeneration = 0

    init(
        loginURL: URL,
        fixtureHTML: String? = nil,
        onContinue: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.loginURL = loginURL
        self.fixtureHTML = fixtureHTML
        self.onContinue = onContinue
        self.onCancel = onCancel
        _visibleOrigin = State(initialValue: gatewayDisplayOrigin(loginURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in to Hermes")
                    .font(NileTypography.titleLarge)
                    .accessibilityIdentifier(NileAccessibilityID.gatewaySignIn)
                Text(
                    "Complete the gateway sign-in, then continue to mint "
                        + "a one-time connection ticket."
                )
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                Text("Page: \(visibleOrigin)")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(
                        visibleOrigin.hasPrefix("https://")
                            ? NileColors.accent
                            : NileColors.warning
                    )
                if loginURL.scheme?.lowercased() != "https" {
                    Text(
                        "Unencrypted sign-in: dashboard credentials and "
                            + "session cookies can be read or changed by this network."
                    )
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.warning)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GatewayLoginWebView(
                loginURL: loginURL,
                fixtureHTML: fixtureHTML,
                approvedExternalOrigins: approvedExternalOrigins,
                reloadGeneration: reloadGeneration,
                onState: apply,
                onExternalNavigation: { target in
                    pendingExternalURL = target
                    loading = false
                }
            )
            .accessibilityIdentifier(NileAccessibilityID.gatewaySignInWebView)

            if let pageError {
                Text(pageError)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier(
                        NileAccessibilityID.gatewaySignInError
                    )
            }

            HStack(spacing: 10) {
                Spacer()
                if loading {
                    ProgressView()
                        .tint(NileColors.accent)
                        .padding(.trailing, 4)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(NileTextButtonStyle())
                    .accessibilityIdentifier(
                        NileAccessibilityID.gatewaySignInCancel
                    )
                if pageError != nil {
                    Button("Retry") {
                        pageError = nil
                        pageLoaded = false
                        loading = true
                        reloadGeneration += 1
                    }
                    .buttonStyle(NileTextButtonStyle())
                    .accessibilityIdentifier(
                        NileAccessibilityID.gatewaySignInRetry
                    )
                }
                Button("Continue", action: onContinue)
                    .buttonStyle(NileTextButtonStyle(prominent: true))
                    .disabled(
                        !pageLoaded
                            || loading
                            || pageError != nil
                            || pendingExternalURL != nil
                    )
                    .accessibilityIdentifier(
                        NileAccessibilityID.gatewaySignInContinue
                    )
            }
            .padding(16)
        }
        .background(NileColors.background)
        .foregroundStyle(NileColors.text)
        .interactiveDismissDisabled()
        .alert(
            "Continue to external sign-in?",
            isPresented: Binding(
                get: { pendingExternalURL != nil },
                set: {
                    if !$0 {
                        pendingExternalURL = nil
                    }
                }
            )
        ) {
            Button("Stay here", role: .cancel) {
                pendingExternalURL = nil
            }
            Button("Continue") {
                guard let target = pendingExternalURL,
                      let origin = gatewayOriginKey(target)
                else {
                    pendingExternalURL = nil
                    return
                }
                approvedExternalOrigins.insert(origin)
                pendingExternalURL = nil
                reloadGeneration += 1
            }
            .accessibilityIdentifier(
                NileAccessibilityID.gatewaySignInApproveExternal
            )
        } message: {
            Text(
                "Hermes wants to open "
                    + gatewayDisplayOrigin(pendingExternalURL ?? loginURL)
                    + ". Only continue if this is the identity provider you expect."
            )
        }
    }

    private func apply(_ state: GatewayLoginPageState) {
        switch state {
        case let .started(url):
            loading = true
            pageLoaded = false
            pageError = nil
            visibleOrigin = gatewayDisplayOrigin(url)
        case let .finished(url):
            loading = false
            pageLoaded = pageError == nil
            visibleOrigin = gatewayDisplayOrigin(url)
        case let .failed(message):
            loading = false
            pageLoaded = false
            pageError = message
        }
    }
}
