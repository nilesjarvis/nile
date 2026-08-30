import Foundation

actor GatewayAuthenticationService:
    GatewayHTTPTransport,
    GatewaySessionCleaning
{
    typealias SavedProfiles = @Sendable () async throws -> [GatewayProfile]

    private let statusClient: GatewayStatusClient
    private let transport: any GatewayHTTPTransport
    private let cookieStore: any GatewayCookieStoring
    private let savedProfiles: SavedProfiles
    private let cookieRotation = GatewayCookieRotationGate()
    private let authenticationEventContinuation:
        AsyncStream<GatewayAuthenticationEvent>.Continuation
    nonisolated let authenticationEvents:
        AsyncStream<GatewayAuthenticationEvent>

    init(
        statusClient: GatewayStatusClient = GatewayStatusClient(),
        transport: any GatewayHTTPTransport = URLSessionGatewayHTTPTransport(),
        cookieStore: any GatewayCookieStoring,
        savedProfiles: @escaping SavedProfiles = { [] }
    ) {
        let eventChannel = AsyncStream<GatewayAuthenticationEvent>
            .makeStream()
        self.statusClient = statusClient
        self.transport = transport
        self.cookieStore = cookieStore
        self.savedProfiles = savedProfiles
        authenticationEvents = eventChannel.stream
        authenticationEventContinuation = eventChannel.continuation
    }

    func makeWebSocketRequest(
        for connection: GatewayConnection
    ) async throws -> URLRequest {
        switch try await statusClient.probe(connection.endpoint) {
        case .legacy:
            guard GatewayCookiePolicy.nonBlank(connection.token) != nil else {
                throw GatewayTokenRequiredError()
            }
            return URLRequest(url: try connection.webSocketURL())
        case .gated:
            if connection.endpoint.isCleartext,
               !connection.cleartextPermission.allowsCleartext {
                throw HermesError(
                    "Approve this unencrypted gateway before entering dashboard sign-in credentials",
                    retryable: false,
                    isConnectionFailure: true
                )
            }
            try await validateCookieScope(connection)
            let ticket = try await cookieRotation.withCancellationShield {
                try await self.mintTicket(connection)
            }
            return URLRequest(
                url: try connection.webSocketURL(
                    credentialName: "ticket",
                    credential: ticket
                )
            )
        }
    }

    func data(for request: URLRequest) async throws -> GatewayHTTPResponse {
        try await cookieRotation.withCancellationShield {
            var authenticated = request
            try await self.addManagedCookies(to: &authenticated)
            let response = try await self.transport.data(for: authenticated)
            if let url = authenticated.url,
               let profile = try await self.managedProfile(for: url) {
                try await self.cookieStore.saveCookies(
                    from: response,
                    for: url
                )
                await self.publishAuthenticationExpiry(
                    response,
                    profile: profile
                )
            }
            return response
        }
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int64
    ) async throws -> GatewayBoundedHTTPResponse {
        try await cookieRotation.withInterruptibleRotation {
            var authenticated = request
            try await self.addManagedCookies(to: &authenticated)
            let bounded = try await self.transport.data(
                for: authenticated,
                maximumBytes: maximumBytes
            )
            if let url = authenticated.url,
               let profile = try await self.managedProfile(for: url) {
                try await self.cookieStore.saveCookies(
                    from: bounded.response,
                    for: url
                )
                await self.publishAuthenticationExpiry(
                    bounded.response,
                    profile: profile
                )
            }
            return bounded
        }
    }

    func clearSession(
        for connection: GatewayConnection,
        includeHostWideCookies: Bool
    ) async throws {
        let cookieRotation = cookieRotation
        let cleanup = Task.detached {
            try await cookieRotation.withCancellationShield {
                if includeHostWideCookies {
                    await self.bestEffortLogout(connection)
                }
                try await self.cookieStore.clearCookies(
                    for: connection.endpoint,
                    includeHostWideCookies: includeHostWideCookies
                )
            }
        }
        try await cleanup.value
    }

    private func mintTicket(
        _ connection: GatewayConnection
    ) async throws -> String {
        let url = try GatewayAuthenticationHTTPPolicy.ticketURL(
            for: connection
        )
        let request = GatewayAuthenticationHTTPPolicy.ticketRequest(
            url: url,
            cookieHeader: try await cookieStore.cookieHeader(for: url)
        )
        let bounded = try await transport.data(
            for: request,
            maximumBytes: GatewayAuthenticationHTTPPolicy.responseLimit
        )
        let response = bounded.response
        try await cookieStore.saveCookies(from: response, for: url)
        return try GatewayAuthenticationHTTPPolicy.ticket(
            from: bounded,
            connection: connection
        )
    }

    private func validateCookieScope(
        _ connection: GatewayConnection
    ) async throws {
        let conflict = try await savedProfiles().first { profile in
            profile.normalizedBaseURL != connection.normalizedBaseURL
                && GatewayCookiePolicy.scopesOverlap(
                    profile.endpoint,
                    connection.endpoint
                )
        }
        if let conflict {
            throw GatewayCookieScopeConflictError(
                conflictingProfileName: conflict.displayName
            )
        }
    }

    private func addManagedCookies(
        to request: inout URLRequest
    ) async throws {
        guard let url = request.url,
              try await isManagedGatewayURL(url),
              let cookie = try await cookieStore.cookieHeader(for: url)
        else {
            return
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
    }

    private func isManagedGatewayURL(_ url: URL) async throws -> Bool {
        try await managedProfile(for: url) != nil
    }

    private func managedProfile(
        for url: URL
    ) async throws -> GatewayProfile? {
        try await savedProfiles().first { profile in
            GatewayCookiePolicy.contains(url, in: profile.endpoint)
        }
    }

    private func publishAuthenticationExpiry(
        _ response: GatewayHTTPResponse,
        profile: GatewayProfile
    ) {
        guard response.statusCode == 401, profile.token.isBlank,
              let loginURL = try? GatewayDashboardResponsePolicy.safeLoginURL(
                  connection: profile.connection,
                  responseData: response.data
              )
        else {
            return
        }
        authenticationEventContinuation.yield(
            GatewayAuthenticationEvent(
                profileID: profile.id,
                loginURL: loginURL
            )
        )
    }

    private func bestEffortLogout(_ connection: GatewayConnection) async {
        guard let url = GatewayAuthenticationHTTPPolicy.logoutURL(
            for: connection
        ), let cookie = try? await cookieStore.cookieHeader(for: url)
        else {
            return
        }
        let request = GatewayAuthenticationHTTPPolicy.controlPOSTRequest(
            url: url,
            cookieHeader: cookie,
            timeoutInterval: 5
        )
        if let bounded = try? await transport.data(
            for: request,
            maximumBytes: GatewayAuthenticationHTTPPolicy.responseLimit
        ) {
            try? await cookieStore.saveCookies(
                from: bounded.response,
                for: url
            )
        }
    }

}
