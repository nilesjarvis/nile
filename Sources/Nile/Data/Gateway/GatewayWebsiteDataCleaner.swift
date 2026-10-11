import WebKit

protocol GatewayWebsiteDataCleaning: Sendable {
    func removeAll() async
}

/// WebKit data cannot safely be assigned to one proxy-path profile, and a
/// dashboard may use a separate sign-in origin. Clearing it is an explicit
/// all-websites action, distinct from scoped gateway-cookie removal.
@MainActor
final class WebKitGatewayWebsiteDataCleaner: GatewayWebsiteDataCleaning {
    private let dataStore: WKWebsiteDataStore

    init(dataStore: WKWebsiteDataStore = .default()) {
        self.dataStore = dataStore
    }

    func removeAll() async {
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}
