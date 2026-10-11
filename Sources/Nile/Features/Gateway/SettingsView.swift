import SwiftUI
struct SettingsView: View {
    @Bindable var model: GatewaySetupModel
    @Bindable var appLock: BiometricAppLockModel
    var privacyCleanup: PrivacyCleanupModel? = nil
    @State private var pendingRemoval: GatewayProfile?
    @State private var isRemovingGateway = false
    @State private var isGatewayFormExpanded = false
    var body: some View {
        NavigationStack {
            ZStack {
                NileColors.background.ignoresSafeArea()
                if isFirstRun { onboardingContent } else { settingsContent }
            }
        }
        .overlay { confirmationDialogs }
        .foregroundStyle(NileColors.text)
        .font(NileTypography.bodyLarge)
        .interactiveDismissDisabled(isConnectedMutationBusy)
        .onAppear {
            appLock.refreshCapability()
            if model.errorMessage != nil { isGatewayFormExpanded = true }
        }
        .onChange(of: model.errorMessage) { _, error in
            if error != nil { isGatewayFormExpanded = true }
        }
        .onChange(of: model.savedGateways.map(\.id)) { _, ids in
            guard let pendingRemoval, !ids.contains(pendingRemoval.id) else { return }
            self.pendingRemoval = nil
            isRemovingGateway = false
        }
        .alert("Allow unencrypted gateway?", isPresented: $model.showCleartextConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Allow") { Task { await model.approveCleartextAndConnect() } }
                .accessibilityIdentifier(NileAccessibilityID.approveCleartext)
        } message: {
            Text("Plain HTTP/WS exposes the dashboard session on the network. Use it only on a trusted simulator, LAN, or VPN.")
        }
        .sheet(
            isPresented: Binding(
                get: { model.isHermesVoiceSheetVisible },
                set: { model.setHermesVoiceSheetVisible($0) }
            )
        ) { HermesVoiceSheetView(model: model) }
        .sheet(item: Binding(
            get: { model.pendingSharingConsent },
            set: { if $0 == nil { model.cancelSharingConsent() } }
        )) { request in
            GatewaySharingConsentView(
                request: request,
                onApprove: { Task { await model.approveSharingConsent() } },
                onCancel: model.cancelSharingConsent
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(model.connectedProfile == nil ? .hidden : .visible)
        .presentationCornerRadius(NileRadii.window)
        .presentationBackground(NileColors.background)
    }
    private var isFirstRun: Bool {
        model.savedGateways.isEmpty && model.connectedProfile == nil
    }
    private var isConnectedMutationBusy: Bool {
        model.connectedProfile != nil
            && (model.isChecking || model.isUpdatingHermesVoice || isRemovingGateway)
    }
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hermesSettingsGroup
                securityCard
                privacyLink
            }
            .padding(.horizontal, 16)
            .padding(.top, 12).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(NileAccessibilityID.settings)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings").font(.headline)
            }
            if model.connectedProfile != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.dismissSettings() }
                        .disabled(isConnectedMutationBusy)
                }
            }
        }
    }
    private var hermesSettingsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Hermes")
            VStack(spacing: 0) {
                NavigationLink { gatewayManagementContent } label: {
                    SettingsGatewaySummaryRow(
                        profile: activeProfile,
                        savedCount: model.savedGateways.count,
                        isConnected: model.isConnected,
                        isChecking: model.isChecking
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(NileAccessibilityID.gatewayManagement)
                if model.isConnected {
                    Divider().overlay(NileColors.border)
                    HermesVoiceEntryView(
                        config: model.hermesVoiceConfig,
                        enabled: !model.isChecking && !model.isUpdatingHermesVoice
                    ) { model.setHermesVoiceSheetVisible(true) }
                }
            }
            .nilePanel()
        }
    }
    private var gatewayManagementContent: some View {
        ZStack {
            NileColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    SettingsGatewayCard(
                        profiles: model.savedGateways,
                        activeGatewayID: model.activeGatewayID,
                        isConnected: model.isConnected,
                        isChecking: model.isChecking,
                        showsAddAction: !isGatewayFormExpanded,
                        onUse: { id in Task { await model.requestGatewayUse(id: id) } },
                        onRemove: { pendingRemoval = $0 },
                        onAdd: { isGatewayFormExpanded = true }
                    )
                    if isGatewayFormExpanded {
                        AddGatewayView(model: model) { isGatewayFormExpanded = false }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier(NileAccessibilityID.gatewayList)
        }
        .navigationTitle("Gateways")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var onboardingContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    NileMark().frame(width: 54, height: 54)
                    Text("Connect Nile to Hermes")
                        .font(
                            NileTypography.font(
                                size: 28,
                                weight: .semibold,
                                relativeTo: .largeTitle
                            )
                        )
                    Text("Nile requires access to a compatible Hermes gateway. Enter the HTTPS address provided by your gateway operator to get started.")
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(NileColors.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                if isGatewayFormExpanded {
                    AddGatewayView(model: model) { isGatewayFormExpanded = false }
                } else {
                    addGatewayButton
                }
                NavigationLink { securityDetail } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                        Text("App security").font(NileTypography.bodyMedium.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(NileColors.muted)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nilePanel()
                privacyLink
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier(NileAccessibilityID.settings)
        .toolbar(.hidden, for: .navigationBar)
    }
    private var securityDetail: some View {
        ZStack {
            NileColors.background.ignoresSafeArea()
            ScrollView { securityCard.padding(16) }
        }
        .navigationTitle("App Security")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
    private var securityCard: some View {
        SettingsSecurityCard(
            isEnabled: Binding(
                get: { appLock.isEnabled },
                set: { enabled in Task { await appLock.setEnabled(enabled) } }
            ),
            canEnable: appLock.canEnable,
            isAuthenticating: appLock.isAuthenticating,
            biometryName: appLock.biometryName,
            errorMessage: appLock.errorMessage,
            unavailableMessage: appLock.capability.unavailableMessage
        )
    }
    private var privacyLink: some View {
        NavigationLink {
            PrivacyInformationView(gateway: model, cleanup: privacyCleanup)
        } label: {
            Label("Privacy & Data", systemImage: "hand.raised")
                .font(NileTypography.bodyMedium.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .nilePanel()
        .accessibilityIdentifier(NileAccessibilityID.privacyEntry)
    }
    private var activeProfile: GatewayProfile? {
        model.savedGateways.first { $0.id == model.activeGatewayID }
            ?? model.connectedProfile
    }
    private var addGatewayButton: some View {
        Button { isGatewayFormExpanded = true } label: {
            Label("Add Gateway", systemImage: "plus")
                .font(NileTypography.bodyLarge.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .nileGlassButton(prominent: true)
        .disabled(model.isChecking)
        .accessibilityIdentifier(NileAccessibilityID.addGateway)
    }
    @ViewBuilder private var confirmationDialogs: some View {
        if let pendingRemoval {
            GatewayRemovalConfirmationDialog(
                profile: pendingRemoval,
                message: removalConfirmationMessage,
                error: model.errorMessage,
                isRemoving: isRemovingGateway,
                onDismiss: {
                    guard !isRemovingGateway else { return }
                    self.pendingRemoval = nil
                },
                onConfirm: confirmPendingRemoval
            )
            .zIndex(10)
        }
        if let profile = model.pendingGatewaySwitch {
            GatewaySwitchConfirmationDialog(
                profile: profile,
                onDismiss: model.dismissGatewaySwitchConfirmation,
                onConfirm: { Task { await model.confirmGatewaySwitch() } }
            )
            .zIndex(10)
        }
    }
    private func confirmPendingRemoval() {
        guard let profile = pendingRemoval, !isRemovingGateway, !model.isChecking else { return }
        isRemovingGateway = true
        Task {
            await model.removeGateway(id: profile.id)
            isRemovingGateway = false
            if !model.savedGateways.contains(where: { $0.id == profile.id }) {
                pendingRemoval = nil
            }
        }
    }
    private var removalConfirmationMessage: String {
        guard let profile = pendingRemoval else { return "" }
        var message = "Nile will delete this gateway's saved credentials, sign-in session, and local text and photo drafts. Conversations remain on Hermes."
        if profile.id == model.activeGatewayID {
            message += model.savedGateways.count > 1
                ? " Nile will disconnect and switch to the next saved gateway. Any Hermes turn already running may continue without Nile following it."
                : " Nile will disconnect. Any Hermes turn already running may continue without Nile following it."
        }
        return message
    }
}
#Preview {
    SettingsView(model: GatewaySetupModel(), appLock: BiometricAppLockModel())
        .preferredColorScheme(.dark)
}
