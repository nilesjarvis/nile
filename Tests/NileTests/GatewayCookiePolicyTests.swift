import Foundation
import XCTest
@testable import Nile

final class GatewayCookiePolicyTests: XCTestCase {
    func testScopeContainmentRejectsOriginAndPathConfusion() throws {
        let endpoint = try GatewayEndpoint.parse(
            "https://gateway.example/hermes"
        )

        for value in [
            "https://gateway.example/hermes",
            "https://gateway.example:443/hermes/api/sessions",
            "https://gateway.example/hermes/team",
        ] {
            XCTAssertTrue(
                GatewayCookiePolicy.contains(
                    try XCTUnwrap(URL(string: value)),
                    in: endpoint
                ),
                "Expected managed URL: \(value)"
            )
        }
        for value in [
            "http://gateway.example/hermes",
            "https://gateway.example:444/hermes",
            "https://gateway.example/hermes-other",
            "https://other.example/hermes",
            "https://attacker@gateway.example/hermes",
        ] {
            XCTAssertFalse(
                GatewayCookiePolicy.contains(
                    try XCTUnwrap(URL(string: value)),
                    in: endpoint
                ),
                "Expected unmanaged URL: \(value)"
            )
        }

        XCTAssertTrue(
            GatewayCookiePolicy.scopesOverlap(
                endpoint,
                try GatewayEndpoint.parse(
                    "http://gateway.example:9000/hermes/child"
                )
            )
        )
        XCTAssertFalse(
            GatewayCookiePolicy.scopesOverlap(
                endpoint,
                try GatewayEndpoint.parse(
                    "https://other.example/hermes/child"
                )
            )
        )
    }

    func testHeaderFiltersDomainExpiryTransportAndCookieVariants() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cookies = try [
            cookie(name: "hermes_session_at", path: "/"),
            cookie(name: "__Host-hermes_session_at", path: "/"),
            cookie(name: "__Secure-hermes_session_at", path: "/hermes"),
            cookie(
                name: "expired",
                path: "/",
                expires: now.addingTimeInterval(-1)
            ),
            cookie(name: "foreign", path: "/", domain: "other.example"),
        ]

        let root = GatewayCookiePolicy.header(
            from: cookies,
            for: try XCTUnwrap(
                URL(
                    string: "https://gateway.example/api/auth/ws-ticket"
                )
            ),
            now: now
        )
        XCTAssertTrue(root?.contains("hermes_session_at=") == true)
        XCTAssertTrue(root?.contains("__Host-hermes_session_at=") == true)
        XCTAssertFalse(root?.contains("__Secure-hermes_session_at=") == true)
        XCTAssertFalse(root?.contains("expired=") == true)
        XCTAssertFalse(root?.contains("foreign=") == true)

        let prefix = GatewayCookiePolicy.header(
            from: cookies,
            for: try XCTUnwrap(
                URL(
                    string:
                        "https://gateway.example/hermes/api/auth/ws-ticket"
                )
            ),
            now: now
        )
        XCTAssertTrue(prefix?.contains("hermes_session_at=") == true)
        XCTAssertFalse(prefix?.contains("__Host-hermes_session_at=") == true)
        XCTAssertTrue(prefix?.contains("__Secure-hermes_session_at=") == true)

        XCTAssertNil(
            GatewayCookiePolicy.header(
                from: [try cookie(name: "secure", path: "/")],
                for: try XCTUnwrap(
                    URL(string: "http://gateway.example/api/value")
                ),
                now: now
            )
        )
    }

    func testCleanupSelectsOnlyEligibleSessionNamesDomainsAndPaths() throws {
        let endpoint = try GatewayEndpoint.parse(
            "https://gateway.example/hermes"
        )
        let cookies = try [
            cookie(name: "hermes_session_at", path: "/"),
            cookie(name: "__Host-hermes_session_at", path: "/"),
            cookie(name: "hermes_session_rt", path: "/hermes"),
            cookie(name: "__Secure-hermes_session_rt", path: "/hermes/"),
            cookie(name: "unrelated", path: "/hermes"),
            cookie(
                name: "hermes_session_at",
                path: "/hermes",
                domain: "other.example"
            ),
        ]

        let scoped = try GatewayCookiePolicy.cookiesToClear(
            from: cookies,
            for: endpoint,
            includeHostWideCookies: false
        )
        XCTAssertEqual(
            Set(scoped.map { "\($0.name)@\($0.path)" }),
            [
                "hermes_session_rt@/hermes",
                "__Secure-hermes_session_rt@/hermes/",
            ]
        )

        let hostWide = try GatewayCookiePolicy.cookiesToClear(
            from: cookies,
            for: endpoint,
            includeHostWideCookies: true
        )
        XCTAssertEqual(
            Set(hostWide.map { "\($0.name)@\($0.path)" }),
            [
                "hermes_session_at@/",
                "__Host-hermes_session_at@/",
                "hermes_session_rt@/hermes",
                "__Secure-hermes_session_rt@/hermes/",
            ]
        )
    }

    private func cookie(
        name: String,
        path: String,
        domain: String = "gateway.example",
        expires: Date? = nil
    ) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: name,
            .domain: domain,
            .path: path,
            .secure: "TRUE",
        ]
        if let expires {
            properties[.expires] = expires
        }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }
}
