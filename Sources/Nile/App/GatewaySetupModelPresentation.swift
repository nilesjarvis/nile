import Foundation

/// Synchronous form mutation and root-surface projection for gateway setup.
/// This boundary owns no dependency construction, capability, task, or
/// connection lifecycle.
@MainActor
extension GatewaySetupModel {
    var isChecking: Bool {
        state == .checking
    }

    var errorMessage: String? {
        if let operationError {
            return operationError
        }
        guard case let .failed(message) = state else {
            return nil
        }
        return message
    }

    var isConnected: Bool {
        state == .connected && connectedProfile != nil
    }

    var connectionStatusText: String {
        switch state {
        case .loading, .checking: "Connecting…"
        case .offline: "Waiting for network…"
        case .reconnecting: "Reconnecting…"
        case .restoring: "Restoring session…"
        case .connected: "Connected"
        case .failed: "Connection failed"
        case .idle: "Manage"
        }
    }

    var cleartextGatewaysSupported: Bool {
#if NILE_CLEARTEXT_GATEWAYS_SUPPORTED
        true
#else
        false
#endif
    }

    var parsedFormEndpoint: GatewayEndpoint? {
        try? GatewayEndpoint.parse(dashboardURL)
    }

    func updateDashboardURL(_ value: String) {
        guard dashboardURL != value else {
            return
        }
        dashboardURL = value
        cleartextApproved = false
        showCleartextConfirmation = false
        operationError = nil
    }

    func updateCleartextApproved(_ approved: Bool) {
        cleartextApproved = approved
        showCleartextConfirmation = false
        operationError = nil
    }

    var showsSessionShell: Bool {
        guard connectedProfile != nil, !isSettingsVisible else {
            return false
        }
        return switch state {
        case .connected, .offline, .reconnecting, .restoring:
            true
        case .loading, .idle, .checking, .failed:
            false
        }
    }
}
