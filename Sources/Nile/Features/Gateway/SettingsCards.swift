import SwiftUI

struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(NileTypography.labelMedium)
            .tracking(0.7)
            .foregroundStyle(NileColors.muted)
            .padding(.leading, 4)
    }
}

/// Model-free app-security presentation with one narrow binding.
struct SettingsSecurityCard: View {
    let isEnabled: Binding<Bool>
    let canEnable: Bool
    let isAuthenticating: Bool
    let biometryName: String
    let errorMessage: String?
    let unavailableMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Security")
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: isEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Require \(biometryName)")
                            .font(NileTypography.bodyLarge.weight(.semibold))
                        Text("Lock Nile when it opens or returns from the background.")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(NileColors.accentStrong)
                .disabled(isAuthenticating || (!isEnabled.wrappedValue && !canEnable))
                .padding(14)
                .accessibilityIdentifier(NileAccessibilityID.biometricLockToggle)

                if let statusMessage {
                    Divider().overlay(NileColors.border)
                    HStack(spacing: 8) {
                        if isAuthenticating {
                            ProgressView().controlSize(.small).tint(NileColors.accent)
                        }
                        Text(statusMessage)
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(statusColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .nilePanel()
        }
    }

    private var statusMessage: String? {
        if isAuthenticating { return "Confirm with \(biometryName)…" }
        if let errorMessage { return errorMessage }
        return canEnable ? nil : unavailableMessage
    }

    private var statusColor: Color {
        errorMessage == nil ? NileColors.muted : NileColors.error
    }
}

struct SettingsGatewaySummaryRow: View {
    let profile: GatewayProfile?
    let savedCount: Int
    let isConnected: Bool
    let isChecking: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(NileColors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("Gateway").font(NileTypography.bodyLarge.weight(.semibold))
                Text(profile?.displayName ?? "\(savedCount) saved")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(isChecking ? "Connecting" : (isConnected ? "Connected" : "Manage"))
                .font(NileTypography.bodySmall)
                .foregroundStyle(isConnected ? NileColors.complete : NileColors.muted)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NileColors.faint)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

/// Model-free saved-gateway list; mutations remain in `SettingsView`.
struct SettingsGatewayCard: View {
    let profiles: [GatewayProfile]
    let activeGatewayID: String?
    let isConnected: Bool
    let isChecking: Bool
    let showsAddAction: Bool
    let onUse: (String) -> Void
    let onRemove: (GatewayProfile) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: "Saved gateways")
            VStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { Divider().overlay(NileColors.border) }
                    gatewayRow(profile)
                }
                if showsAddAction {
                    if !profiles.isEmpty { Divider().overlay(NileColors.border) }
                    Button(action: onAdd) {
                        Label("Add Gateway", systemImage: "plus")
                            .font(NileTypography.bodyLarge.weight(.semibold))
                            .foregroundStyle(NileColors.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecking)
                    .accessibilityIdentifier(NileAccessibilityID.addGateway)
                }
            }
            .nilePanel()
            if profiles.contains(where: { $0.endpoint.isCleartext }) {
                Text("Unencrypted gateways expose traffic and credentials. Use HTTPS whenever possible.")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.warning)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gatewayRow(_ profile: GatewayProfile) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(NileTypography.bodyLarge.weight(.semibold))
                        .lineLimit(1)
                    if profile.endpoint.isCleartext {
                        Text("UNENCRYPTED")
                            .font(NileTypography.labelMedium)
                            .foregroundStyle(NileColors.warning)
                    }
                }
                Text(profile.normalizedBaseURL)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if profile.id == activeGatewayID, isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(NileColors.complete)
                    .accessibilityLabel("Connected")
            } else {
                Button(profile.id == activeGatewayID ? "Retry" : "Use") {
                    onUse(profile.id)
                }
                .buttonStyle(NileTextButtonStyle())
                .disabled(isChecking)
            }
            Menu {
                Button("Remove", role: .destructive) { onRemove(profile) }
                    .accessibilityIdentifier(NileAccessibilityID.removeGateway)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(NileColors.muted)
            .accessibilityLabel("Gateway actions")
            .accessibilityIdentifier(NileAccessibilityID.gatewayActions)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }
}
