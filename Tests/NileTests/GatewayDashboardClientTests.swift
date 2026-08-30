import Foundation
import XCTest
@testable import Nile

final class GatewayDashboardClientTests: XCTestCase {
    func testGetUsesProxyPrefixEncodedSegmentsAndLegacyToken() async throws {
        let transport = DashboardRecordingTransport(
            response: GatewayHTTPResponse(
                data: Data(#"{"messages":[]}"#.utf8),
                statusCode: 200
            )
        )
        let client = GatewayDashboardClient(transport: transport)
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: "dashboard-token"
        )

        let result = try await client.getJSON(
            connection: connection,
            pathSegments: ["sessions", "session/id", "messages"]
        )

        XCTAssertEqual(result, ["messages": .array([])])
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gateway.example/hermes/api/sessions/session%2Fid/messages"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertEqual(
            request.cachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Hermes-Session-Token"),
            "dashboard-token"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testBlankTokenIsNotSent() async throws {
        let transport = DashboardRecordingTransport(
            response: GatewayHTTPResponse(data: Data("{}".utf8), statusCode: 200)
        )
        let client = GatewayDashboardClient(transport: transport)

        _ = try await client.getJSON(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example",
                token: " \n"
            ),
            pathSegments: ["sessions", "one"]
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(
            request.value(forHTTPHeaderField: "X-Hermes-Session-Token")
        )
    }

    func testQueryUsesTheSharedAuthenticatedRequestPipeline() async throws {
        let transport = DashboardRecordingTransport(
            response: GatewayHTTPResponse(data: Data("{}".utf8), statusCode: 200)
        )
        let client = GatewayDashboardClient(transport: transport)

        _ = try await client.getJSON(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example/hermes",
                token: "query-token"
            ),
            pathSegments: ["stats"],
            query: ["z": "hello world", "days": "7"]
        )

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gateway.example/hermes/api/stats?days=7&z=hello%20world"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Hermes-Session-Token"),
            "query-token"
        )
    }

    func testUnauthorizedRequiresDashboardSignInAtProxyLogin() async {
        let client = GatewayDashboardClient(
            transport: DashboardRecordingTransport(
                response: GatewayHTTPResponse(data: Data(), statusCode: 401)
            )
        )

        await XCTAssertThrowsDashboardError(
            try await client.getJSON(
                connection: GatewayConnection(
                    endpoint: try GatewayEndpoint.parse(
                        "https://gateway.example/hermes"
                    ),
                    token: "expired"
                ),
                pathSegments: ["sessions", "one"]
            )
        ) { error in
            XCTAssertEqual(
                (error as? GatewaySignInRequiredError)?.loginURL.absoluteString,
                "https://gateway.example/hermes/login"
            )
            XCTAssertEqual(
                error.localizedDescription,
                "Your Hermes dashboard session has expired or requires sign-in"
            )
        }
    }

    func testUnauthorizedAcceptsOnlyExactSameOriginAdvertisedLogin() async {
        for advertised in [
            "login?return=%2Fhermes",
            "/hermes/login?return=%2Fhermes",
            "https://gateway.example:443/hermes/login?return=%2Fhermes",
        ] {
            let client = GatewayDashboardClient(
                transport: DashboardRecordingTransport(
                    response: GatewayHTTPResponse(
                        data: Data(
                            #"{"login_url":"\#(advertised)"}"#.utf8
                        ),
                        statusCode: 401
                    )
                )
            )

            await XCTAssertThrowsDashboardError(
                try await client.getJSON(
                    connection: try GatewayConnection(
                        baseURL: "https://gateway.example/hermes",
                        token: "expired"
                    ),
                    pathSegments: ["sessions", "one"]
                )
            ) { error in
                XCTAssertEqual(
                    (error as? GatewaySignInRequiredError)?
                        .loginURL.absoluteString,
                    "https://gateway.example/hermes/login?return=%2Fhermes"
                )
            }
        }

        for advertised in [
            "https://attacker.example/hermes/login",
            "https://user@gateway.example/hermes/login",
            "https://gateway.example/other/login",
            "https://gateway.example/hermes/login#fragment",
        ] {
            let client = GatewayDashboardClient(
                transport: DashboardRecordingTransport(
                    response: GatewayHTTPResponse(
                        data: Data(
                            #"{"login_url":"\#(advertised)"}"#.utf8
                        ),
                        statusCode: 401
                    )
                )
            )

            await XCTAssertThrowsDashboardError(
                try await client.getJSON(
                    connection: try GatewayConnection(
                        baseURL: "https://gateway.example/hermes",
                        token: "expired"
                    ),
                    pathSegments: ["sessions", "one"]
                )
            ) { error in
                XCTAssertEqual(
                    (error as? GatewaySignInRequiredError)?
                        .loginURL.absoluteString,
                    "https://gateway.example/hermes/login"
                )
            }
        }
    }

    func testOriginPolicyNormalizesOnlyMatchingDefaultPorts() throws {
        let https = try XCTUnwrap(URL(string: "https://gateway.example/path"))
        let explicitHTTPS = try XCTUnwrap(
            URL(string: "https://gateway.example:443/other")
        )
        let http = try XCTUnwrap(URL(string: "http://gateway.example/path"))
        let explicitHTTP = try XCTUnwrap(
            URL(string: "http://gateway.example:80/other")
        )
        let customPort = try XCTUnwrap(
            URL(string: "https://gateway.example:444/path")
        )

        XCTAssertTrue(GatewayURLOriginPolicy.sameOrigin(https, explicitHTTPS))
        XCTAssertTrue(GatewayURLOriginPolicy.sameOrigin(http, explicitHTTP))
        XCTAssertFalse(GatewayURLOriginPolicy.sameOrigin(https, http))
        XCTAssertFalse(GatewayURLOriginPolicy.sameOrigin(https, customPort))
    }

    func testHTTPRetryClassificationUsesExpectedPolicy() async {
        for status in [408, 425, 429, 500, 503] {
            await assertHTTPFailure(status: status, retryable: true)
        }
        for status in [400, 403, 404, 422] {
            await assertHTTPFailure(status: status, retryable: false)
        }
    }

    func testSuccessfulBodyMustBeJSONObject() async {
        for body in ["[]", "null", #""text""#, "not-json"] {
            let client = GatewayDashboardClient(
                transport: DashboardRecordingTransport(
                    response: GatewayHTTPResponse(
                        data: Data(body.utf8),
                        statusCode: 200
                    )
                )
            )
            await XCTAssertThrowsDashboardError(
                try await client.getJSON(
                    connection: try GatewayConnection(
                        baseURL: "https://gateway.example",
                        token: "token"
                    ),
                    pathSegments: ["sessions", "one"]
                )
            ) { error in
                let hermes = error as? HermesError
                XCTAssertEqual(
                    hermes?.message,
                    "Gateway returned invalid dashboard data"
                )
                XCTAssertEqual(hermes?.retryable, false)
            }
        }
    }

    func testOrdinaryDashboardReadsUseBoundedTransport() async {
        let transport = DashboardBoundedSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(#"{"messages":[]}"#.utf8),
                    statusCode: 200
                ),
            ],
            tooLarge: true
        )
        let client = GatewayDashboardClient(transport: transport)

        await XCTAssertThrowsDashboardError(
            try await client.getJSON(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                pathSegments: ["sessions", "one", "messages"]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Gateway returned too much dashboard data"
            )
        }
        let calls = await transport.calls
        XCTAssertEqual(
            calls.map(\.maximumBytes),
            [GatewayResponseLimits.dashboardJSON]
        )
    }

    func testVoiceJSONRequestsUseExactAuthenticatedProxyContracts() async throws {
        let transport = DashboardBoundedSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(
                        #"{"provider":"edge","voice":"en-US-AriaNeural"}"#.utf8
                    ),
                    statusCode: 200
                ),
                GatewayHTTPResponse(
                    data: Data(
                        #"{"provider":"edge","voice":"en-US-GuyNeural"}"#.utf8
                    ),
                    statusCode: 200
                ),
            ]
        )
        let client = GatewayDashboardClient(transport: transport)
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: "voice-token"
        )

        _ = try await client.getJSONWithErrorDetail(
            connection: connection,
            pathSegments: ["niles", "tts-config"],
            maximumBytes: 1_024
        )
        _ = try await client.sendJSON(
            connection: connection,
            method: "put",
            pathSegments: ["niles", "tts-config"],
            body: [
                "provider": .string("edge"),
                "voice": .string("en-US-GuyNeural"),
            ],
            maximumBytes: 2_048
        )

        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.maximumBytes), [1_024, 2_048])
        XCTAssertEqual(calls[0].request.httpMethod, "GET")
        XCTAssertNil(calls[0].request.httpBody)
        XCTAssertEqual(
            calls[0].request.url?.absoluteString,
            "https://gateway.example/hermes/api/niles/tts-config"
        )
        XCTAssertEqual(calls[1].request.httpMethod, "PUT")
        XCTAssertEqual(
            calls[1].request.value(
                forHTTPHeaderField: "Content-Type"
            ),
            "application/json"
        )
        XCTAssertEqual(
            calls[1].request.value(
                forHTTPHeaderField: "X-Hermes-Session-Token"
            ),
            "voice-token"
        )
        let body = try XCTUnwrap(calls[1].request.httpBody)
        XCTAssertEqual(
            try JSONValue(
                any: JSONSerialization.jsonObject(with: body)
            ).objectValue,
            [
                "provider": .string("edge"),
                "voice": .string("en-US-GuyNeural"),
            ]
        )
        XCTAssertNil(
            calls[1].request.value(forHTTPHeaderField: "Cookie")
        )
    }

    func testVoiceJSONRequestsPreserveSafeErrorDetailAndBounds() async {
        for payload in [
            #"{"detail":" Choose a supported Edge voice. "}"#,
            #"{"error":"provider unavailable"}"#,
        ] {
            let client = GatewayDashboardClient(
                transport: DashboardBoundedSequenceTransport(
                    responses: [
                        GatewayHTTPResponse(
                            data: Data(payload.utf8),
                            statusCode: 422
                        ),
                    ]
                )
            )
            await XCTAssertThrowsDashboardError(
                try await client.sendJSON(
                    connection: try GatewayConnection(
                        baseURL: "https://gateway.example/hermes",
                        token: "token"
                    ),
                    method: "PUT",
                    pathSegments: ["niles", "tts-config"],
                    body: [:],
                    maximumBytes: 1_024
                )
            ) { error in
                XCTAssertTrue(
                    error.localizedDescription.hasPrefix(
                        "Could not write dashboard data (HTTP 422): "
                    )
                )
                XCTAssertEqual((error as? HermesError)?.retryable, false)
            }
        }

        let oversized = GatewayDashboardClient(
            transport: DashboardBoundedSequenceTransport(
                responses: [
                    GatewayHTTPResponse(
                        data: Data("{}".utf8),
                        statusCode: 200
                    ),
                ],
                tooLarge: true
            )
        )
        await XCTAssertThrowsDashboardError(
            try await oversized.getJSONWithErrorDetail(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                pathSegments: ["niles", "tts-config"],
                maximumBytes: 1
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Gateway returned too much dashboard data"
            )
        }
        await XCTAssertThrowsDashboardError(
            try await oversized.sendJSON(
                connection: try! GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                method: "DELETE",
                pathSegments: ["niles", "tts-config"],
                body: [:],
                maximumBytes: 1
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Dashboard JSON method is not supported"
            )
        }
    }

    func testManagedAttachmentDownloadEncodesPathAndAuthenticates() async throws {
        let transport = DashboardSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data("payload".utf8),
                    statusCode: 200,
                    headers: [
                        "Content-Disposition":
                            #"attachment; filename="wrong.txt"; filename*=UTF-8''report%20final%2B.txt"#,
                        "Content-Type": "text/plain; charset=utf-8",
                    ]
                ),
            ]
        )
        let client = GatewayDashboardClient(transport: transport)
        let downloaded = try await client.download(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example/hermes",
                token: "dashboard-token"
            ),
            path: "/tmp/report final.txt",
            maximumBytes: 1_024
        )

        XCTAssertEqual(downloaded.filename, "report final+.txt")
        XCTAssertEqual(downloaded.mimeType, "text/plain")
        XCTAssertEqual(downloaded.bytes, Data("payload".utf8))
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gateway.example/hermes/api/files/download?path=/tmp/report%20final.txt"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Hermes-Session-Token"),
            "dashboard-token"
        )
    }

    func testCrossOriginRedirectDropsCredentialAndRejectsDowngrade() async throws {
        let transport = DashboardSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(),
                    statusCode: 302,
                    headers: [
                        "Location": "https://cdn.example/photo.jpg",
                    ]
                ),
                GatewayHTTPResponse(
                    data: Data("jpeg".utf8),
                    statusCode: 200,
                    headers: ["Content-Type": "image/jpeg"]
                ),
            ]
        )
        let client = GatewayDashboardClient(transport: transport)
        _ = try await client.download(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example/hermes",
                token: "private-token"
            ),
            path: "/tmp/photo.jpg",
            maximumBytes: 100
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].value(
                forHTTPHeaderField: "X-Hermes-Session-Token"
            ),
            "private-token"
        )
        XCTAssertNil(
            requests[1].value(
                forHTTPHeaderField: "X-Hermes-Session-Token"
            )
        )

        let downgradeClient = GatewayDashboardClient(
            transport: DashboardSequenceTransport(
                responses: [
                    GatewayHTTPResponse(
                        data: Data(),
                        statusCode: 302,
                        headers: [
                            "Location": "http://cdn.example/photo.jpg",
                        ]
                    ),
                ]
            )
        )
        await XCTAssertThrowsDashboardError(
            try await downgradeClient.download(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                path: "/tmp/photo.jpg",
                maximumBytes: 100
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Attachment redirect cannot downgrade HTTPS"
            )
        }
    }

    func testExternalHTTPAndOversizedDownloadsFailClosed() async {
        let client = GatewayDashboardClient(
            transport: DashboardSequenceTransport(responses: [])
        )
        await XCTAssertThrowsDashboardError(
            try await client.download(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                path: "http://attacker.example/file",
                maximumBytes: 100
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Attachment URL is invalid or unsafe"
            )
        }

        let oversized = GatewayDashboardClient(
            transport: DashboardSequenceTransport(
                responses: [
                    GatewayHTTPResponse(
                        data: Data(repeating: 1, count: 101),
                        statusCode: 200
                    ),
                ]
            )
        )
        await XCTAssertThrowsDashboardError(
            try await oversized.download(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                path: "/tmp/file",
                maximumBytes: 100
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Attachment is too large to download safely"
            )
        }
    }

    private func assertHTTPFailure(status: Int, retryable: Bool) async {
        let client = GatewayDashboardClient(
            transport: DashboardRecordingTransport(
                response: GatewayHTTPResponse(data: Data(), statusCode: status)
            )
        )
        await XCTAssertThrowsDashboardError(
            try await client.getJSON(
                connection: try GatewayConnection(
                    baseURL: "https://gateway.example",
                    token: "token"
                ),
                pathSegments: ["sessions", "one"]
            )
        ) { error in
            let hermes = error as? HermesError
            XCTAssertEqual(
                hermes?.message,
                "Could not read dashboard data (HTTP \(status))"
            )
            XCTAssertEqual(hermes?.retryable, retryable)
        }
    }
}

private actor DashboardSequenceTransport: GatewayHTTPTransport {
    private var responses: [GatewayHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [GatewayHTTPResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw HermesError("Missing test response", retryable: false)
        }
        return responses.removeFirst()
    }
}

private actor DashboardRecordingTransport: GatewayHTTPTransport {
    private let response: GatewayHTTPResponse
    private(set) var requests: [URLRequest] = []

    init(response: GatewayHTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        requests.append(request)
        return response
    }
}

private struct DashboardBoundedCall: Sendable {
    let request: URLRequest
    let maximumBytes: Int64
}

private actor DashboardBoundedSequenceTransport: GatewayHTTPTransport {
    private var responses: [GatewayHTTPResponse]
    private let tooLarge: Bool
    private(set) var calls: [DashboardBoundedCall] = []

    init(
        responses: [GatewayHTTPResponse],
        tooLarge: Bool = false
    ) {
        self.responses = responses
        self.tooLarge = tooLarge
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        let bounded = try await data(for: request, maximumBytes: .max)
        return bounded.response
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) async throws -> GatewayBoundedHTTPResponse {
        calls.append(
            DashboardBoundedCall(
                request: request,
                maximumBytes: maximumBytes
            )
        )
        guard !responses.isEmpty else {
            throw HermesError("Missing test response", retryable: false)
        }
        return GatewayBoundedHTTPResponse(
            response: responses.removeFirst(),
            tooLarge: tooLarge
        )
    }
}

private func XCTAssertThrowsDashboardError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        handler(error)
    }
}
