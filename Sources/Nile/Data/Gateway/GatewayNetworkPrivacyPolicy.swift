import Foundation

enum GatewayNetworkPrivacyPolicy {
    /// Gateway content and authentication live only in the explicitly managed
    /// stores. Foundation must not retain a second response or credential copy.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}
