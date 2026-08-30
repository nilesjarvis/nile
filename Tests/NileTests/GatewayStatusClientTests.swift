import Foundation
import XCTest
@testable import Nile

final class GatewayStatusClientTests: XCTestCase, @unchecked Sendable {
    func testProbeUsesExactProxyPrefixedStatusRequest() async throws {
        let transport = RecordingHTTPTransport(
            response: GatewayHTTPResponse(
                data: Data(#"{"status":"ok","auth_required":false}"#.utf8),
                statusCode: 200
            )
        )
        let client = GatewayStatusClient(transport: transport)

        let mode = try await client.probe(
            try GatewayEndpoint.parse("https://gateway.example/hermes")
        )
        XCTAssertEqual(mode, .legacy)

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/hermes/api/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testProbeUses404CompatibilityAndRequiresBooleanAuthMode() async throws {
        let endpoint = try GatewayEndpoint.parse("https://gateway.example")
        let missing = GatewayStatusClient(
            transport: RecordingHTTPTransport(
                response: GatewayHTTPResponse(data: Data(), statusCode: 404)
            )
        )
        let missingMode = try await missing.probe(endpoint)
        XCTAssertEqual(missingMode, .legacy)

        let gated = GatewayStatusClient(
            transport: RecordingHTTPTransport(
                response: GatewayHTTPResponse(
                    data: Data(#"{"auth_required":true}"#.utf8),
                    statusCode: 200
                )
            )
        )
        let gatedMode = try await gated.probe(endpoint)
        XCTAssertEqual(gatedMode, .gated)

        let cases: [(GatewayHTTPResponse, GatewayProbeError)] = [
            (
                GatewayHTTPResponse(data: Data(#"{"error":"no"}"#.utf8), statusCode: 403),
                .httpStatus(403)
            ),
            (
                GatewayHTTPResponse(data: Data(#"{"status":"ok"}"#.utf8), statusCode: 200),
                .invalidResponse
            ),
            (
                GatewayHTTPResponse(data: Data(#"{"auth_required":1}"#.utf8), statusCode: 200),
                .invalidResponse
            ),
            (
                GatewayHTTPResponse(data: Data("[]".utf8), statusCode: 200),
                .invalidResponse
            ),
            (
                GatewayHTTPResponse(data: Data("{}".utf8), statusCode: 200),
                .invalidResponse
            ),
            (
                GatewayHTTPResponse(data: Data("not-json".utf8), statusCode: 200),
                .invalidResponse
            ),
        ]

        for (response, expected) in cases {
            let client = GatewayStatusClient(
                transport: RecordingHTTPTransport(response: response)
            )
            do {
                _ = try await client.probe(endpoint)
                XCTFail("Expected probe to fail")
            } catch let error as GatewayProbeError {
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testPresentationMapsNetworkFailuresWithoutLeakingInternals() {
        XCTAssertEqual(
            GatewayProbePresentation.message(for: URLError(.timedOut)),
            "The gateway did not respond in time."
        )
        XCTAssertEqual(
            GatewayProbePresentation.message(for: URLError(.cannotFindHost)),
            "Nile could not reach that gateway."
        )
        XCTAssertEqual(
            GatewayProbePresentation.message(for: URLError(.serverCertificateUntrusted)),
            "Nile could not establish a trusted connection."
        )
        XCTAssertEqual(
            GatewayProbePresentation.message(for: URLError(.badServerResponse)),
            "Nile could not check that gateway."
        )
    }

    func testProbeBoundsUntrustedStatusPayloadBeforeDecoding() async throws {
        let transport = StatusBoundedTransport(
            response: GatewayHTTPResponse(
                data: Data(#"{"auth_required":false}"#.utf8),
                statusCode: 200
            ),
            tooLarge: true
        )
        let client = GatewayStatusClient(transport: transport)

        do {
            _ = try await client.probe(
                try GatewayEndpoint.parse("https://gateway.example")
            )
            XCTFail("Expected oversized status data to be rejected")
        } catch let error as GatewayProbeError {
            XCTAssertEqual(error, .invalidResponse)
        }
        let maximumBytes = await transport.maximumBytes
        XCTAssertEqual(
            maximumBytes,
            [GatewayResponseLimits.controlJSON]
        )
    }
}

private actor RecordingHTTPTransport: GatewayHTTPTransport {
    let response: GatewayHTTPResponse
    private(set) var requests: [URLRequest] = []

    init(response: GatewayHTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        requests.append(request)
        return response
    }
}

private actor StatusBoundedTransport: GatewayHTTPTransport {
    let response: GatewayHTTPResponse
    let tooLarge: Bool
    private(set) var maximumBytes: [Int64] = []

    init(response: GatewayHTTPResponse, tooLarge: Bool) {
        self.response = response
        self.tooLarge = tooLarge
    }

    func data(for request: URLRequest) throws -> GatewayHTTPResponse {
        throw GatewayProbeError.invalidResponse
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) -> GatewayBoundedHTTPResponse {
        self.maximumBytes.append(maximumBytes)
        return GatewayBoundedHTTPResponse(
            response: response,
            tooLarge: tooLarge
        )
    }
}
