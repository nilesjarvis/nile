import Foundation
import XCTest
@testable import Nile

final class GatewayAuthenticationHTTPPolicyTests: XCTestCase {
    func testTicketAndLogoutRequestsOwnExactBoundedPOSTContracts() throws {
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        let ticketURL = try GatewayAuthenticationHTTPPolicy.ticketURL(
            for: connection
        )
        let ticket = GatewayAuthenticationHTTPPolicy.ticketRequest(
            url: ticketURL,
            cookieHeader: "session=one"
        )

        XCTAssertEqual(
            ticketURL.absoluteString,
            "https://gateway.example/hermes/api/auth/ws-ticket"
        )
        XCTAssertEqual(ticket.httpMethod, "POST")
        XCTAssertEqual(ticket.httpBody, Data())
        XCTAssertEqual(ticket.timeoutInterval, 30)
        XCTAssertEqual(
            ticket.cachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        XCTAssertEqual(ticket.value(forHTTPHeaderField: "Cookie"), "session=one")
        XCTAssertEqual(
            GatewayAuthenticationHTTPPolicy.responseLimit,
            GatewayResponseLimits.controlJSON
        )

        let logoutURL = try XCTUnwrap(
            GatewayAuthenticationHTTPPolicy.logoutURL(for: connection)
        )
        let logout = GatewayAuthenticationHTTPPolicy.controlPOSTRequest(
            url: logoutURL,
            cookieHeader: "session=two",
            timeoutInterval: 5
        )
        XCTAssertEqual(
            logoutURL.absoluteString,
            "https://gateway.example/hermes/auth/logout"
        )
        XCTAssertEqual(logout.httpMethod, "POST")
        XCTAssertEqual(logout.httpBody, Data())
        XCTAssertEqual(logout.timeoutInterval, 5)
        XCTAssertEqual(
            logout.cachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        XCTAssertEqual(logout.value(forHTTPHeaderField: "Cookie"), "session=two")
    }

    func testTicketResponsePreservesNonblankSuccessAndClassifiesHTTPFailures()
        throws
    {
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        XCTAssertEqual(
            try GatewayAuthenticationHTTPPolicy.ticket(
                from: bounded(
                    status: 200,
                    body: #"{"ticket":"  fresh-ticket  "}"#
                ),
                connection: connection
            ),
            "  fresh-ticket  "
        )

        for (status, retryable) in [(400, false), (503, true)] {
            do {
                _ = try GatewayAuthenticationHTTPPolicy.ticket(
                    from: bounded(status: status, body: #"{"error":"no"}"#),
                    connection: connection
                )
                XCTFail("Expected HTTP \(status) to fail")
            } catch let error as HermesError {
                XCTAssertEqual(
                    error.message,
                    "Could not mint a gateway connection ticket (HTTP \(status))"
                )
                XCTAssertEqual(error.retryable, retryable)
                XCTAssertTrue(error.isConnectionFailure)
            }
        }
    }

    func testTicketResponseFailsClosedForUnauthorizedOversizedAndMalformedData()
        throws
    {
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        do {
            _ = try GatewayAuthenticationHTTPPolicy.ticket(
                from: bounded(
                    status: 401,
                    body: #"{"login_url":"/hermes/login"}"#,
                    tooLarge: true
                ),
                connection: connection
            )
            XCTFail("Expected sign-in")
        } catch let error as GatewaySignInRequiredError {
            XCTAssertEqual(
                error.loginURL.absoluteString,
                "https://gateway.example/hermes/login"
            )
        }

        for response in [
            bounded(
                status: 200,
                body: #"{"ticket":"too-large"}"#,
                tooLarge: true
            ),
            bounded(status: 200, body: #"{"ticket":"  "}"#),
            bounded(status: 200, body: #"{"ticket":1}"#),
            bounded(status: 200, body: "[]"),
        ] {
            do {
                _ = try GatewayAuthenticationHTTPPolicy.ticket(
                    from: response,
                    connection: connection
                )
                XCTFail("Expected ticket rejection")
            } catch let error as HermesError {
                XCTAssertFalse(error.retryable)
                XCTAssertTrue(error.isConnectionFailure)
                XCTAssertTrue(
                    error.message == "Gateway returned an oversized connection ticket"
                        || error.message == "Gateway returned an invalid connection ticket"
                )
            }
        }
    }

    private func bounded(
        status: Int,
        body: String,
        tooLarge: Bool = false
    ) -> GatewayBoundedHTTPResponse {
        GatewayBoundedHTTPResponse(
            response: GatewayHTTPResponse(
                data: Data(body.utf8),
                statusCode: status
            ),
            tooLarge: tooLarge
        )
    }
}
