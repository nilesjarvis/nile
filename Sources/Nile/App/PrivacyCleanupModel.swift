import Foundation
import Observation

@MainActor
@Observable
final class PrivacyCleanupModel {
    private(set) var isClearing = false
    private(set) var errorMessage: String?
    private(set) var didClearData = false
    private let gatewaySetup: GatewaySetupModel
    private let attachmentCache: any AttachmentCacheClearing
    private let websiteData: any GatewayWebsiteDataCleaning
    private let onBegin: @MainActor () -> Void

    init(
        gatewaySetup: GatewaySetupModel,
        attachmentCache: any AttachmentCacheClearing,
        websiteData: any GatewayWebsiteDataCleaning =
            WebKitGatewayWebsiteDataCleaner(),
        onBegin: @escaping @MainActor () -> Void = {}
    ) {
        self.gatewaySetup = gatewaySetup
        self.attachmentCache = attachmentCache
        self.websiteData = websiteData
        self.onBegin = onBegin
    }

    var canClearData: Bool {
        guard !isClearing,
              gatewaySetup.connectedProfile == nil,
              gatewaySetup.gatewaySignInURL == nil else {
            return false
        }
        switch gatewaySetup.state {
        case .idle, .offline, .failed:
            return true
        case .loading, .checking, .reconnecting, .restoring, .connected:
            return false
        }
    }

    func clearLocalCaches() async {
        guard canClearData else {
            return
        }
        let previousState = gatewaySetup.state
        // Reserve the setup operation while WebKit removes data so another
        // connection cannot restore a cookie before cleanup has completed.
        gatewaySetup.state = .checking
        gatewaySetup.reconnectCoordinator.cancel()
        isClearing = true
        errorMessage = nil
        didClearData = false
        onBegin()
        defer {
            if gatewaySetup.state == .checking {
                gatewaySetup.state = previousState
            }
            isClearing = false
        }
        do {
            try await attachmentCache.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        await websiteData.removeAll()
        URLCache.shared.removeAllCachedResponses()
        didClearData = errorMessage == nil
    }
}
