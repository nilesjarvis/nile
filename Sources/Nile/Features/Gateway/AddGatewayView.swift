import SwiftUI

struct AddGatewayView: View {
    @Bindable var model: GatewaySetupModel
    let onCancel: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case url
        case token
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Gateway")
                    .font(.headline)
                    .accessibilityIdentifier(NileAccessibilityID.addGateway)
                Spacer()
                Button {
                    focusedField = nil
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }

            gatewayField
            dashboardURLField
            legacyTokenField

            if formEndpointIsCleartext {
                GatewayCleartextWarning(
                    isSupported: model.cleartextGatewaysSupported,
                    usesDeterministicFixtureCopy:
                        model.usesDeterministicFixtureCopy
                )
                .padding(.top, 1)
                if model.cleartextGatewaysSupported {
                    GatewayCleartextApproval(
                        isApproved: model.cleartextApproved
                    ) {
                        model.updateCleartextApproved(
                            !model.cleartextApproved
                        )
                    }
                }
            }

            statusMessage
            connectButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nilePanel(cornerRadius: NileRadii.card)
    }

    private var gatewayField: some View {
        TextField("Name (optional)", text: $model.gatewayName)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .url
            }
            .font(NileTypography.bodyLarge)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(NileColors.panelAlt)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.control)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }
        .accessibilityIdentifier(NileAccessibilityID.gatewayName)
    }

    private var dashboardURLField: some View {
        TextField(
            "Dashboard URL",
            text: Binding(
                get: { model.dashboardURL },
                set: { model.updateDashboardURL($0) }
            )
        )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .focused($focusedField, equals: .url)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .token
            }
            .font(NileTypography.bodyLarge)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(NileColors.panelAlt)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.control)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }
            .accessibilityIdentifier(NileAccessibilityID.gatewayURL)
    }

    private var legacyTokenField: some View {
        outlinedField(
            helper: "Leave blank for gateways that use dashboard sign-in"
        ) {
            SecureField(
                "Legacy session token",
                text: $model.legacyToken
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .token)
            .submitLabel(.done)
            .onSubmit {
                focusedField = nil
                guard formCanSubmit else {
                    return
                }
                Task {
                    await model.connect()
                }
            }
            .font(NileTypography.bodyLarge)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(NileColors.panelAlt)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.control)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }
            .accessibilityIdentifier(NileAccessibilityID.gatewayToken)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = model.errorMessage {
            Text(error)
                .nileTextStyle(NileTypography.bodySmallStyle)
                .foregroundStyle(NileColors.error)
                .accessibilityIdentifier(NileAccessibilityID.gatewayError)
        } else if model.state == .connected {
            Text("Gateway connected.")
                .nileTextStyle(NileTypography.bodySmallStyle)
                .foregroundStyle(NileColors.complete)
                .accessibilityIdentifier(NileAccessibilityID.gatewayStatus)
        }
    }

    private var connectButton: some View {
        Button {
            focusedField = nil
            Task {
                await model.connect()
            }
        } label: {
            HStack(spacing: 8) {
                if model.isChecking {
                    ProgressView()
                        .tint(NileColors.onAccent)
                }
                Text(
                    model.isChecking
                        ? "Checking…"
                        : connectButtonTitle
                )
                .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
        }
        .nileGlassButton(prominent: true)
        .disabled(!formCanSubmit)
        .accessibilityIdentifier(NileAccessibilityID.connectGateway)
    }

    private var formEndpointIsCleartext: Bool {
        model.parsedFormEndpoint?.isCleartext == true
    }

    private var formCanSubmit: Bool {
        guard !model.isChecking else {
            return false
        }
        guard formEndpointIsCleartext else {
            return true
        }
        return model.cleartextGatewaysSupported
            && model.cleartextApproved
    }

    private var connectButtonTitle: String {
        if model.isConnected {
            return formEndpointIsCleartext
                ? "Add and switch insecurely"
                : "Add and switch"
        }
        return formEndpointIsCleartext
            ? "Connect insecurely"
            : "Connect"
    }

    private func outlinedField<Content: View>(
        helper: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            if let helper {
                Text(helper)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}
