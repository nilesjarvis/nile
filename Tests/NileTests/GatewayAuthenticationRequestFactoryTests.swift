import Foundation
import XCTest
@testable import Nile

final class GatewayAuthenticationRequestFactoryTests: XCTestCase, @unchecked Sendable {
    func testPreStatusGatewayUsesEncodedReusableToken() async throws {
        let transport = AuthenticationHTTPTransport(
            GatewayHTTPResponse(data: Data(), statusCode: 404)
        )
        let factory = GatewayAuthenticationRequestFactory(
            statusClient: GatewayStatusClient(transport: transport)
        )
        let token = "one&two #%"
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: token
        )

        let request = try await factory.makeRequest(for: connection)

        XCTAssertEqual(
            request.url?.absoluteString,
            "wss://gateway.example/hermes/api/ws?token=one%26two%20%23%25"
        )
        let requestURLs = await transport.requestURLs
        XCTAssertEqual(
            requestURLs,
            ["https://gateway.example/hermes/api/status"]
        )
    }

    func testLegacyGatewayRejectsBlankTokenBeforeSocketCreation() async throws {
        let factory = GatewayAuthenticationRequestFactory(
            statusClient: GatewayStatusClient(
                transport: AuthenticationHTTPTransport(
                    GatewayHTTPResponse(
                        data: Data(#"{"auth_required":false}"#.utf8),
                        statusCode: 200
                    )
                )
            )
        )

        do {
            _ = try await factory.makeRequest(
                for: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: " \n "
                )
            )
            XCTFail("Expected a missing-token rejection")
        } catch {
            XCTAssertTrue(error is GatewayTokenRequiredError)
        }
    }

    func testPreStatusGatewayRejectsBlankTokenBeforeSocketCreation() async throws {
        let factory = GatewayAuthenticationRequestFactory(
            statusClient: GatewayStatusClient(
                transport: AuthenticationHTTPTransport(
                    GatewayHTTPResponse(data: Data(), statusCode: 404)
                )
            )
        )

        do {
            _ = try await factory.makeRequest(
                for: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: " \n "
                )
            )
            XCTFail("Expected a missing-token rejection")
        } catch {
            XCTAssertTrue(error is GatewayTokenRequiredError)
        }
    }

    func testGatedGatewayNeverFallsBackToReusableToken() async throws {
        let transport = AuthenticationHTTPTransport(
            GatewayHTTPResponse(
                data: Data(#"{"auth_required":true}"#.utf8),
                statusCode: 200
            )
        )
        let factory = GatewayAuthenticationRequestFactory(
            statusClient: GatewayStatusClient(transport: transport)
        )

        do {
            _ = try await factory.makeRequest(
                for: try GatewayConnection(
                    baseURL: "https://gateway.example/prefix",
                    token: "must-not-be-used"
                )
            )
            XCTFail("Expected dashboard sign-in")
        } catch let error as GatewaySignInRequiredError {
            XCTAssertEqual(
                error.loginURL.absoluteString,
                "https://gateway.example/prefix/login"
            )
        }
    }

    func testClientPreservesSignInAndTokenRequiredOutcomesFromCredentialDiscovery() async throws {
        for expected in [
            ExpectedPreparationError.signIn,
            ExpectedPreparationError.token,
        ] {
            let requestFactory = ThrowingAuthenticationRequestFactory(expected: expected)
            let socketFactory = RejectingAuthenticationSocketFactory()
            let client = TuiGatewayClient(
                webSocketFactory: socketFactory,
                requestFactory: requestFactory
            )

            do {
                try await client.connect(
                    try GatewayConnection(
                        baseURL: "https://gateway.example",
                        token: "secret"
                    ),
                    timeoutMilliseconds: 1_000
                )
                XCTFail("Expected credential discovery to stop the connection")
            } catch {
                switch expected {
                case .signIn:
                    XCTAssertTrue(error is GatewaySignInRequiredError)
                case .token:
                    XCTAssertTrue(error is GatewayTokenRequiredError)
                }
            }
            let requests = await socketFactory.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }
}

private actor AuthenticationHTTPTransport: GatewayHTTPTransport {
    private let response: GatewayHTTPResponse
    private(set) var requestURLs: [String] = []

    init(_ response: GatewayHTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) -> GatewayHTTPResponse {
        requestURLs.append(request.url?.absoluteString ?? "")
        return response
    }
}

private enum ExpectedPreparationError: Sendable {
    case signIn
    case token
}

private struct ThrowingAuthenticationRequestFactory: GatewayRequestFactory {
    let expected: ExpectedPreparationError

    func makeRequest(for connection: GatewayConnection) throws -> URLRequest {
        switch expected {
        case .signIn:
            throw GatewaySignInRequiredError(
                loginURL: URL(string: "https://gateway.example/login")!
            )
        case .token:
            throw GatewayTokenRequiredError()
        }
    }
}

private actor RejectingAuthenticationSocketFactory: GatewayWebSocketFactory {
    private(set) var requests: [URLRequest] = []

    func makeWebSocket(for request: URLRequest) throws -> any GatewayWebSocket {
        requests.append(request)
        throw GatewayWebSocketFailure("Socket creation must not run")
    }
}
