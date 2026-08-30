import Foundation
import XCTest
@testable import Nile

final class GatewayConnectionFailurePolicyTests: XCTestCase {
    func testHTTPFailuresRetainAuthenticationAndRetrySemantics() {
        let cases: [(
            status: Int,
            phrase: String,
            authRejected: Bool,
            retryable: Bool
        )] = [
            (401, "HTTP 401", true, false),
            (403, "Host policy", false, false),
            (404, "not found", false, false),
            (408, "temporarily refused", false, true),
            (418, "HTTP 418", false, false),
            (302, "redirected", false, false),
            (500, "Gateway connection failed", false, true),
        ]

        for item in cases {
            let classification = GatewayConnectionFailurePolicy.classify(
                GatewayWebSocketFailure(
                    "upgrade failed",
                    httpStatusCode: item.status
                )
            )

            XCTAssertTrue(
                classification.message.contains(item.phrase),
                "Expected status \(item.status) to contain \(item.phrase)"
            )
            XCTAssertEqual(
                classification.authRejected,
                item.authRejected,
                "Unexpected authentication classification for \(item.status)"
            )
            XCTAssertEqual(
                classification.retryable,
                item.retryable,
                "Unexpected retry classification for \(item.status)"
            )
        }
    }

    func testCloseFailuresRetainPolicySemanticsAndRedactReasons() {
        let secret = "never-emit-this-token"
        let rejected = GatewayConnectionFailurePolicy.classify(
            GatewayWebSocketFailure(
                "closed",
                closeCode: 4_401,
                closeReason: "expired?token=\(secret)&next=safe"
            )
        )
        XCTAssertTrue(rejected.authRejected)
        XCTAssertFalse(rejected.retryable)
        XCTAssertTrue(rejected.message.contains("4401"))
        XCTAssertTrue(rejected.message.contains("token=<redacted>"))
        XCTAssertFalse(rejected.message.contains(secret))

        for (code, phrase, retryable) in [
            (4_403, "access policy", false),
            (1_002, "protocol error", false),
            (1_008, "policy violation", false),
            (1_000, "connection closed", true),
        ] {
            let classification = GatewayConnectionFailurePolicy.classify(
                GatewayWebSocketFailure(
                    "closed",
                    closeCode: code,
                    closeReason: "reason"
                )
            )
            XCTAssertFalse(classification.authRejected)
            XCTAssertEqual(classification.retryable, retryable)
            XCTAssertTrue(classification.message.contains(phrase))
        }
    }

    func testGenericFailureIsRedactedAndConnectionScoped() {
        let secret = "never-emit-this-ticket"
        let source = NSError(
            domain: "Gateway",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "request failed?ticket=\(secret)&again=true",
            ]
        )

        let error = GatewayConnectionFailurePolicy.connectionError(for: source)

        XCTAssertTrue(error.isConnectionFailure)
        XCTAssertTrue(error.retryable)
        XCTAssertFalse(error.authRejected)
        XCTAssertTrue(error.message.contains("ticket=<redacted>"))
        XCTAssertFalse(error.message.contains(secret))
    }
}
