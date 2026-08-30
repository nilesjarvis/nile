import Foundation
import WebKit

protocol GatewayCookieStoring: Sendable {
    func cookieHeader(for url: URL) async throws -> String?
    func saveCookies(from response: GatewayHTTPResponse, for url: URL) async throws
    func clearCookies(
        for endpoint: GatewayEndpoint,
        includeHostWideCookies: Bool
    ) async throws
}

@MainActor
final class WebKitGatewayCookieStore: GatewayCookieStoring, @unchecked Sendable {
    private let store: WKHTTPCookieStore
    private let readiness: Task<Void, Never>

    init(dataStore: WKWebsiteDataStore = .default()) {
        store = dataStore.httpCookieStore
        let primer = WebKitCookieStorePrimer()
        // A cold WebKit data store may not expose persisted cookies until
        // its network process has completed an initial document load.
        readiness = Task { @MainActor in
            await primer.prime(dataStore: dataStore)
        }
    }

    func cookieHeader(for url: URL) async throws -> String? {
        GatewayCookiePolicy.header(from: await allCookies(), for: url)
    }

    func saveCookies(
        from response: GatewayHTTPResponse,
        for url: URL
    ) async throws {
        guard let raw = GatewayCookiePolicy.nonBlank(
            response.header("Set-Cookie")
        ) else {
            return
        }
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": raw],
            for: response.responseURL ?? url
        )
        for cookie in cookies {
            await set(cookie)
        }
    }

    func clearCookies(
        for endpoint: GatewayEndpoint,
        includeHostWideCookies: Bool
    ) async throws {
        let cookies = try GatewayCookiePolicy.cookiesToClear(
            from: await allCookies(),
            for: endpoint,
            includeHostWideCookies: includeHostWideCookies
        )
        for cookie in cookies {
            await delete(cookie)
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await readiness.value
        return await withCheckedContinuation { continuation in
            store.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
    }

    private func set(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func delete(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class WebKitCookieStorePrimer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var webView: WKWebView?

    func prime(dataStore: WKWebsiteDataStore) async {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        finish()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish()
    }

    private func finish() {
        guard let continuation else {
            return
        }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        continuation.resume()
    }
}
