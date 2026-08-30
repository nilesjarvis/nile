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

    init(store: WKHTTPCookieStore = WKWebsiteDataStore.default().httpCookieStore) {
        self.store = store
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
        await withCheckedContinuation { continuation in
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
