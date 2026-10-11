import XCTest
@testable import Nile

final class PrivacyLinksTests: XCTestCase {
    func testPublishingLinksRejectMissingInsecureAndPlaceholderDestinations() {
        let invalid: [Any?] = [
            nil, 42, "", "http://nileapp.org/privacy", "https://example.com/privacy",
            "https://hermes.example", "https://user:password@nileapp.org/privacy",
            "https://LOCALHOST/privacy", "https://192.168.1.1/privacy", "https://[::1]/",
            "https://policy.example.com", "https://nile.test", "https://nile.local",
            "https://nileapp.org/privacy?token=secret", "https://$(POLICY_HOST)/privacy",
        ]
        for value in invalid {
            XCTAssertNil(PrivacyLinks.httpsURL(value))
        }
        XCTAssertEqual(PrivacyLinks.httpsURL("https://nileapp.org/privacy")?.absoluteString,
            "https://nileapp.org/privacy")
    }
}
