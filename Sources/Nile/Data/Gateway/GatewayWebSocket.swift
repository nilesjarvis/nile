import Foundation

protocol GatewayRequestFactory: Sendable {
    func makeRequest(for connection: GatewayConnection) async throws -> URLRequest
}

struct LegacyGatewayRequestFactory: GatewayRequestFactory {
    func makeRequest(for connection: GatewayConnection) async throws -> URLRequest {
        URLRequest(url: try connection.webSocketURL())
    }
}

struct GatewayAuthenticationRequestFactory: GatewayRequestFactory {
    private let statusClient: GatewayStatusClient?
    private let authenticator: GatewayAuthenticationService?

    init(statusClient: GatewayStatusClient = GatewayStatusClient()) {
        self.statusClient = statusClient
        authenticator = nil
    }

    init(authenticator: GatewayAuthenticationService) {
        statusClient = nil
        self.authenticator = authenticator
    }

    func makeRequest(for connection: GatewayConnection) async throws -> URLRequest {
        if let authenticator {
            return try await authenticator.makeWebSocketRequest(
                for: connection
            )
        }
        guard let statusClient else {
            throw GatewayProbeError.invalidResponse
        }
        switch try await statusClient.probe(connection.endpoint) {
        case .legacy:
            guard !connection.token.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw GatewayTokenRequiredError()
            }
            return URLRequest(url: try connection.webSocketURL())
        case .gated:
            throw GatewaySignInRequiredError(
                loginURL: try connection.endpoint.apiURL(pathSegments: ["login"])
            )
        }
    }
}

struct GatewayTokenRequiredError: LocalizedError, Equatable, Sendable {
    var errorDescription: String? {
        "This local gateway requires its dashboard session token."
    }
}

struct GatewaySignInRequiredError: LocalizedError, Equatable, Sendable {
    let loginURL: URL
    let message: String

    init(
        loginURL: URL,
        message: String = "This gateway requires dashboard sign-in."
    ) {
        self.loginURL = loginURL
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

enum GatewayWebSocketMessage: Equatable, Sendable {
    case text(String)
    case data(Data)
}

protocol GatewayWebSocket: AnyObject, Sendable {
    func start() async throws
    func send(text: String) async throws
    func receive() async throws -> GatewayWebSocketMessage
    func close(code: Int, reason: String?) async
    func cancel() async
}

protocol GatewayWebSocketFactory: Sendable {
    func makeWebSocket(for request: URLRequest) async throws -> any GatewayWebSocket
}

struct GatewayWebSocketFailure: LocalizedError, Sendable {
    let message: String
    let httpStatusCode: Int?
    let closeCode: Int?
    let closeReason: String?

    init(
        _ message: String,
        httpStatusCode: Int? = nil,
        closeCode: Int? = nil,
        closeReason: String? = nil
    ) {
        self.message = message
        self.httpStatusCode = httpStatusCode
        self.closeCode = closeCode
        self.closeReason = closeReason
    }

    var errorDescription: String? { message }
}

final class URLSessionGatewayWebSocketFactory: GatewayWebSocketFactory, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init() {
        configuration = GatewayNetworkPrivacyPolicy.configuration()
    }

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    func makeWebSocket(for request: URLRequest) async throws -> any GatewayWebSocket {
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: request)
        return URLSessionGatewayWebSocket(session: session, task: task)
    }
}

private final class URLSessionGatewayWebSocket: GatewayWebSocket, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(session: URLSession, task: URLSessionWebSocketTask) {
        self.session = session
        self.task = task
    }

    func start() async throws {
        task.resume()
    }

    func send(text: String) async throws {
        do {
            try await task.send(.string(text))
        } catch {
            throw failure(from: error)
        }
    }

    func receive() async throws -> GatewayWebSocketMessage {
        do {
            switch try await task.receive() {
            case let .string(text):
                return .text(text)
            case let .data(data):
                return .data(data)
            @unknown default:
                throw GatewayWebSocketFailure("Gateway returned an unsupported WebSocket message")
            }
        } catch let error as GatewayWebSocketFailure {
            throw error
        } catch {
            throw failure(from: error)
        }
    }

    func close(code: Int, reason: String?) async {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task.cancel(
            with: closeCode,
            reason: reason?.data(using: .utf8)
        )
        session.finishTasksAndInvalidate()
    }

    func cancel() async {
        task.cancel()
        session.invalidateAndCancel()
    }

    private func failure(from error: any Error) -> GatewayWebSocketFailure {
        let responseCode = (task.response as? HTTPURLResponse)?.statusCode
        let closeCode: Int?
        if task.closeCode == .invalid {
            closeCode = nil
        } else {
            closeCode = task.closeCode.rawValue
        }
        let closeReason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
        return GatewayWebSocketFailure(
            error.localizedDescription,
            httpStatusCode: responseCode,
            closeCode: closeCode,
            closeReason: closeReason
        )
    }
}
