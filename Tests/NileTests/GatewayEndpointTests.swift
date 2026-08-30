import Foundation
import XCTest
@testable import Nile

final class GatewayEndpointTests: XCTestCase {
    func testCanonicalizesHTTPEndpointsAndPreservesCleanProxyPrefix() throws {
        XCTAssertEqual(
            try GatewayEndpoint.parse("  HTTPS://Example.COM:443/hermes/  ").baseURL,
            "https://example.com/hermes"
        )
        XCTAssertEqual(
            try GatewayEndpoint.parse("http://[::1]:9119/proxy/hermes").baseURL,
            "http://[::1]:9119/proxy/hermes"
        )
        XCTAssertFalse(try GatewayEndpoint.parse("https://example.com").isCleartext)
        XCTAssertTrue(try GatewayEndpoint.parse("http://example.com").isCleartext)
    }

    func testWebSocketURLAppendsToProxyPrefixAndEncodesTokenAsOneQueryValue() throws {
        let connection = try GatewayConnection(
            baseURL: "https://example.com/hermes",
            token: "a&b#c%d+e ?"
        )

        XCTAssertEqual(
            try connection.webSocketURL().absoluteString,
            "wss://example.com/hermes/api/ws?token=a%26b%23c%25d%2Be%20%3F"
        )
    }

    func testCleartextWebSocketURLRequiresProfilePermission() throws {
        let denied = try GatewayConnection(
            baseURL: "http://gateway.local:9119",
            token: "token"
        )
        XCTAssertThrowsError(try denied.webSocketURL())

        let approved = try GatewayConnection(
            baseURL: "http://gateway.local:9119",
            token: "token",
            cleartextPermission: .approved
        )
        XCTAssertEqual(
            try approved.webSocketURL().absoluteString,
            "ws://gateway.local:9119/api/ws?token=token"
        )
    }

    func testAPIURLPercentEncodesEveryDynamicPathSegment() throws {
        let endpoint = try GatewayEndpoint.parse("https://example.com/hermes")

        XCTAssertEqual(
            try endpoint.apiURL(
                pathSegments: ["api", "sessions", "terminal/id + ?", "messages"]
            ).absoluteString,
            "https://example.com/hermes/api/sessions/terminal%2Fid%20%2B%20%3F/messages"
        )
        XCTAssertThrowsError(
            try endpoint.apiURL(pathSegments: ["api", "", "sessions"])
        )
    }

    func testRejectsOriginConfusingOrAmbiguousInput() {
        let rejected = [
            "gateway.local:9119",
            "ftp://gateway.local",
            "https://user:pass@gateway.local",
            "https://gateway.local/hermes?target=other",
            "https://gateway.local/hermes#fragment",
            #"https://gateway.local/hermes\child"#,
            "https://gateway.local/hermes/%5c/child",
            "https://gateway.local/hermes/../child",
            "https://gateway.local/hermes/%2e%2e/child",
            "https://gateway.local/hermes//child",
            "https://gateway.local/hermes%2fchild",
            "https://gateway.local:",
            "https://gateway.local:not-a-port",
            "https://gateway.local:0",
            "https://gateway.local:99999",
        ]

        for value in rejected {
            XCTAssertThrowsError(
                try GatewayEndpoint.parse(value),
                "Expected rejection for \(value)"
            )
        }
    }

    func testLegacyParserOnlyMigratesMissingSchemeAndRedundantTrailingSlashes() throws {
        XCTAssertEqual(
            try GatewayEndpoint.parseLegacy(" gateway.local:9119/hermes/// ").baseURL,
            "http://gateway.local:9119/hermes"
        )
        XCTAssertThrowsError(try GatewayEndpoint.parse("gateway.local:9119/hermes"))
        XCTAssertThrowsError(try GatewayEndpoint.parseLegacy("ftp://gateway.local"))
    }
}
