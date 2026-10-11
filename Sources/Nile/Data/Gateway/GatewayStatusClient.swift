import Foundation

enum GatewayResponseLimits {
    static let controlJSON: Int64 = 64 * 1_024
    static let dashboardJSON: Int64 = 32 * 1_024 * 1_024
}

struct GatewayHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]
    let responseURL: URL?

    init(
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:],
        responseURL: URL? = nil
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.responseURL = responseURL
    }

    func header(_ name: String) -> String? {
        headers.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

struct GatewayBoundedHTTPResponse: Sendable {
    let response: GatewayHTTPResponse
    let tooLarge: Bool
}

protocol GatewayHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> GatewayHTTPResponse
    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) async throws -> GatewayBoundedHTTPResponse
}

extension GatewayHTTPTransport {
    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) async throws -> GatewayBoundedHTTPResponse {
        let response = try await data(for: request)
        return GatewayBoundedHTTPResponse(
            response: response,
            tooLarge: Int64(response.data.count) > maximumBytes
        )
    }
}

struct URLSessionGatewayHTTPTransport: GatewayHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = GatewayNetworkPrivacyPolicy.configuration()
        session = URLSession(
            configuration: configuration,
            delegate: GatewayNoRedirectDelegate.shared,
            delegateQueue: nil
        )
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        let (data, response) = try await session.data(for: request)
        return try Self.response(data: data, response: response)
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) async throws -> GatewayBoundedHTTPResponse {
        guard maximumBytes > 0 else {
            throw HermesError(
                "Attachment download limit must be positive",
                retryable: false
            )
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayProbeError.invalidResponse
        }
        if let contentLength = httpResponse.value(
            forHTTPHeaderField: "Content-Length"
        ).flatMap(Int64.init), contentLength > maximumBytes {
            return GatewayBoundedHTTPResponse(
                response: try Self.response(data: Data(), response: response),
                tooLarge: true
            )
        }
        var data = Data()
        data.reserveCapacity(
            Int(min(maximumBytes, max(0, httpResponse.expectedContentLength)))
        )
        for try await byte in bytes {
            if Int64(data.count) >= maximumBytes {
                return GatewayBoundedHTTPResponse(
                    response: try Self.response(
                        data: data,
                        response: response
                    ),
                    tooLarge: true
                )
            }
            data.append(byte)
        }
        return GatewayBoundedHTTPResponse(
            response: try Self.response(data: data, response: response),
            tooLarge: false
        )
    }

    private static func response(
        data: Data,
        response: URLResponse
    ) throws -> GatewayHTTPResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayProbeError.invalidResponse
        }
        let headers = httpResponse.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, pair in
            result[String(describing: pair.key)] = String(
                describing: pair.value
            )
        }
        return GatewayHTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            headers: headers,
            responseURL: httpResponse.url
        )
    }
}

private final class GatewayNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let shared = GatewayNoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct GatewayStatusClient: Sendable {
    private let transport: any GatewayHTTPTransport

    init(transport: any GatewayHTTPTransport = URLSessionGatewayHTTPTransport()) {
        self.transport = transport
    }

    func probe(_ endpoint: GatewayEndpoint) async throws -> GatewayAuthenticationMode {
        let url = try endpoint.apiURL(pathSegments: ["api", "status"])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let bounded = try await transport.data(
            for: request,
            maximumBytes: GatewayResponseLimits.controlJSON
        )
        let response = bounded.response
        if response.statusCode == 404 {
            return .legacy
        }
        guard (200...299).contains(response.statusCode) else {
            throw GatewayProbeError.httpStatus(response.statusCode)
        }
        guard !bounded.tooLarge else {
            throw GatewayProbeError.invalidResponse
        }
        do {
            let status = try JSONDecoder().decode(
                GatewayStatusEnvelope.self,
                from: response.data
            )
            return status.authRequired ? .gated : .legacy
        } catch {
            throw GatewayProbeError.invalidResponse
        }
    }
}

enum GatewayAuthenticationMode: Equatable, Sendable {
    case legacy
    case gated
}

private struct GatewayStatusEnvelope: Decodable {
    let authRequired: Bool

    private enum CodingKeys: String, CodingKey {
        case authRequired = "auth_required"
    }
}

enum GatewayProbeError: LocalizedError, Equatable, Sendable {
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .httpStatus(status):
            "The gateway returned HTTP \(status)."
        case .invalidResponse:
            "The server did not return a valid Hermes status response."
        }
    }
}

enum GatewayProbePresentation {
    static func message(for error: any Error) -> String {
        if let probeError = error as? GatewayProbeError {
            return probeError.localizedDescription
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The gateway did not respond in time."
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Nile could not reach that gateway."
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "Nile could not establish a trusted connection."
            default:
                return "Nile could not check that gateway."
            }
        }
        return "Nile could not check that gateway."
    }
}
