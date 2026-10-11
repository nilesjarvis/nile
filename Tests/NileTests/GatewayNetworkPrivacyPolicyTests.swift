import XCTest
import WebKit
@testable import Nile

final class GatewayNetworkPrivacyPolicyTests: XCTestCase {
    func testTransportDoesNotKeepUnmanagedContentCredentialsOrCookies() {
        let configuration = GatewayNetworkPrivacyPolicy.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalCacheData
        )
    }

    @MainActor
    func testWebsiteCleanupErasesCookiesAcrossSignInOrigins() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        for domain in ["gateway.example", "login.example"] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: domain,
                .path: "/",
                .name: "fixture-session",
                .value: "fixture-value",
                .secure: "TRUE",
            ]))
            await store.httpCookieStore.setCookie(cookie)
        }
        let before = await store.httpCookieStore.allCookies()
        XCTAssertEqual(before.count, 2)

        await WebKitGatewayWebsiteDataCleaner(dataStore: store).removeAll()

        let after = await store.httpCookieStore.allCookies()
        XCTAssertTrue(after.isEmpty)
    }
}
