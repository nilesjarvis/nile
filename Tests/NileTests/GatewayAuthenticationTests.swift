import Foundation
import WebKit
import XCTest
@testable import Nile

final class GatewayAuthenticationTests: XCTestCase, @unchecked Sendable {
    func testGatedConnectionMintsFreshSingleUseTicketForEverySocket() async throws {
        let status = GatewayStatusClient(
            transport: AuthFixedTransport(
                GatewayHTTPResponse(
                    data: Data(#"{"auth_required":true}"#.utf8),
                    statusCode: 200
                )
            )
        )
        let transport = AuthSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(#"{"ticket":"ticket-one"}"#.utf8),
                    statusCode: 200
                ),
                GatewayHTTPResponse(
                    data: Data(#"{"ticket":"ticket-two"}"#.utf8),
                    statusCode: 200
                ),
            ]
        )
        let cookies = AuthMemoryCookies(header: "hermes_session_at=access")
        let service = GatewayAuthenticationService(
            statusClient: status,
            transport: transport,
            cookieStore: cookies
        )
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: "must-not-be-used"
        )

        let first = try await service.makeWebSocketRequest(for: connection)
        let second = try await service.makeWebSocketRequest(for: connection)

        XCTAssertEqual(
            first.url?.absoluteString,
            "wss://gateway.example/hermes/api/ws?ticket=ticket-one"
        )
        XCTAssertEqual(
            second.url?.absoluteString,
            "wss://gateway.example/hermes/api/ws?ticket=ticket-two"
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests.allSatisfy {
                $0.url?.absoluteString
                    == "https://gateway.example/hermes/api/auth/ws-ticket"
                    && $0.httpMethod == "POST"
                    && $0.value(forHTTPHeaderField: "Cookie")
                        == "hermes_session_at=access"
                    && $0.value(
                        forHTTPHeaderField: "X-Hermes-Session-Token"
                    ) == nil
            }
        )
    }

    func testTicketMintRejectsOversizedControlResponse() async throws {
        let transport = AuthBoundedTransport(
            response: GatewayHTTPResponse(
                data: Data(#"{"ticket":"oversized"}"#.utf8),
                statusCode: 200
            ),
            tooLarge: true
        )
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: AuthMemoryCookies(
                header: "hermes_session_at=access"
            )
        )

        do {
            _ = try await service.makeWebSocketRequest(
                for: try GatewayConnection(
                    baseURL: "https://gateway.example/hermes",
                    token: ""
                )
            )
            XCTFail("Expected oversized ticket data to be rejected")
        } catch let error as HermesError {
            XCTAssertEqual(
                error.message,
                "Gateway returned an oversized connection ticket"
            )
            XCTAssertFalse(error.retryable)
            XCTAssertTrue(error.isConnectionFailure)
        }
        let maximumBytes = await transport.maximumBytes
        XCTAssertEqual(
            maximumBytes,
            [GatewayResponseLimits.controlJSON]
        )
    }

    func testExternalCleartextGatedConnectionRejectsDeniedPermissionBeforeTicket()
        async throws
    {
        let status = GatewayStatusClient(
            transport: AuthFixedTransport(
                GatewayHTTPResponse(
                    data: Data(#"{"auth_required":true}"#.utf8),
                    statusCode: 200
                )
            )
        )
        let transport = AuthSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(#"{"ticket":"cleartext-ticket"}"#.utf8),
                    statusCode: 200
                ),
            ]
        )
        let service = GatewayAuthenticationService(
            statusClient: status,
            transport: transport,
            cookieStore: AuthMemoryCookies(
                header: "hermes_session_at=access"
            )
        )
        let connection = try GatewayConnection(
            baseURL: "http://gateway.example:9119/hermes",
            token: "",
            cleartextPermission: .denied
        )

        do {
            _ = try await service.makeWebSocketRequest(for: connection)
            XCTFail("Denied cleartext permission must fail before ticket minting")
        } catch let error as HermesError {
            XCTAssertTrue(error.message.contains("Approve this unencrypted"))
            XCTAssertFalse(error.retryable)
            XCTAssertTrue(error.isConnectionFailure)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancelledTicketPersistsRotationThenReleasesGateForFreshRetry() async throws {
        let transport = AuthControlledTransport()
        let cookies = AuthMemoryCookies(header: "hermes_session_rt=before")
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: cookies
        )
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        let cancelled = Task {
            try await service.makeWebSocketRequest(for: connection)
        }
        await transport.waitForRequestCount(1)

        cancelled.cancel()
        await transport.completeNext(
            GatewayHTTPResponse(
                data: Data(#"{"ticket":"obsolete"}"#.utf8),
                statusCode: 200,
                headers: [
                    "Set-Cookie":
                        "hermes_session_rt=rotated; HttpOnly; Path=/hermes",
                ]
            )
        )

        do {
            _ = try await cancelled.value
            XCTFail("Cancellation must win after cookie rotation is saved")
        } catch is CancellationError {
            // Expected.
        }
        let savedAfterCancellation = await cookies.savedURLs
        XCTAssertEqual(
            savedAfterCancellation,
            ["https://gateway.example/hermes/api/auth/ws-ticket"]
        )

        let retry = Task {
            try await service.makeWebSocketRequest(for: connection)
        }
        await transport.waitForRequestCount(2)
        await transport.completeNext(
            GatewayHTTPResponse(
                data: Data(#"{"ticket":"fresh"}"#.utf8),
                statusCode: 200
            )
        )
        let retryRequest = try await retry.value
        XCTAssertEqual(
            retryRequest.url?.absoluteString,
            "wss://gateway.example/hermes/api/ws?ticket=fresh"
        )
    }

    func testTicketUnauthorizedUsesOnlyExactSafeAdvertisedLogin() async throws {
        for advertised in [
            "/hermes/login?return=%2Fhermes",
            "https://attacker.example/hermes/login",
        ] {
            let service = GatewayAuthenticationService(
                statusClient: gatedStatusClient(),
                transport: AuthSequenceTransport(
                    responses: [
                        GatewayHTTPResponse(
                            data: Data(
                                #"{"login_url":"\#(advertised)"}"#.utf8
                            ),
                            statusCode: 401
                        ),
                    ]
                ),
                cookieStore: AuthMemoryCookies(
                    header: "hermes_session_at=access"
                )
            )
            do {
                _ = try await service.makeWebSocketRequest(
                    for: try GatewayConnection(
                        baseURL: "https://gateway.example/hermes",
                        token: ""
                    )
                )
                XCTFail("Expected sign-in")
            } catch let error as GatewaySignInRequiredError {
                XCTAssertEqual(
                    error.loginURL.absoluteString,
                    advertised.hasPrefix("/hermes")
                        ? "https://gateway.example/hermes/login?return=%2Fhermes"
                        : "https://gateway.example/hermes/login"
                )
            }
        }
    }

    func testGatedCookieScopeRejectsOverlappingSameHostBeforeTicketMint() async throws {
        let transport = AuthSequenceTransport(responses: [])
        let existing = try GatewayProfile(
            id: "gateway-existing",
            name: "Existing gateway",
            baseURL: "https://shared.example/team",
            token: ""
        )
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: AuthMemoryCookies(header: "cookie=value"),
            savedProfiles: { [existing] }
        )

        do {
            _ = try await service.makeWebSocketRequest(
                for: try GatewayConnection(
                    baseURL: "https://shared.example/team/child",
                    token: ""
                )
            )
            XCTFail("Expected scope rejection")
        } catch let error as GatewayCookieScopeConflictError {
            XCTAssertEqual(error.conflictingProfileName, "Existing gateway")
        }
        let rejectedRequests = await transport.requests
        XCTAssertTrue(rejectedRequests.isEmpty)
        XCTAssertTrue(
            GatewayCookiePolicy.scopesOverlap(
                existing.endpoint,
                try GatewayEndpoint.parse(
                    "http://shared.example:9000/team/child"
                )
            )
        )
        XCTAssertFalse(
            GatewayCookiePolicy.scopesOverlap(
                existing.endpoint,
                try GatewayEndpoint.parse(
                    "https://other.example/team/child"
                )
            )
        )
    }

    func testDashboardTransportAttachesCookiesOnlyInsideSavedGatewayScope() async throws {
        let profile = try GatewayProfile(
            id: "gateway-one",
            name: "One",
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        let transport = AuthSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data("{}".utf8),
                    statusCode: 200,
                    headers: ["Set-Cookie": "hermes_session_at=rotated"]
                ),
                GatewayHTTPResponse(
                    data: Data("external".utf8),
                    statusCode: 200
                ),
            ]
        )
        let cookies = AuthMemoryCookies(header: "hermes_session_at=access")
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: cookies,
            savedProfiles: { [profile] }
        )

        _ = try await service.data(
            for: URLRequest(
                url: URL(
                    string: "https://gateway.example/hermes/api/sessions"
                )!
            )
        )
        _ = try await service.data(
            for: URLRequest(
                url: URL(string: "https://cdn.example/file")!
            )
        )

        let requests = await transport.requests
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Cookie"),
            "hermes_session_at=access"
        )
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        let saves = await cookies.savedURLs
        XCTAssertEqual(
            saves,
            ["https://gateway.example/hermes/api/sessions"]
        )
    }

    func testManagedGatedUnauthorizedResponsesPublishSafeExpiryEvents() async throws {
        let profile = try GatewayProfile(
            id: "gateway-one",
            name: "One",
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        let transport = AuthSequenceTransport(
            responses: [
                GatewayHTTPResponse(
                    data: Data(
                        #"{"login_url":"/hermes/login?return=%2Fhermes"}"#.utf8
                    ),
                    statusCode: 401
                ),
                GatewayHTTPResponse(
                    data: Data(
                        #"{"login_url":"https://attacker.example/login"}"#.utf8
                    ),
                    statusCode: 401
                ),
            ]
        )
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: AuthMemoryCookies(
                header: "hermes_session_at=expired"
            ),
            savedProfiles: { [profile] }
        )
        let collected = Task {
            var events: [GatewayAuthenticationEvent] = []
            for await event in service.authenticationEvents {
                events.append(event)
                if events.count == 2 {
                    return events
                }
            }
            return events
        }

        let request = URLRequest(
            url: URL(
                string: "https://gateway.example/hermes/api/sessions"
            )!
        )
        _ = try await service.data(for: request)
        _ = try await service.data(for: request, maximumBytes: 1_024)

        let expiryEvents = await collected.value
        XCTAssertEqual(
            expiryEvents,
            [
                GatewayAuthenticationEvent(
                    profileID: profile.id,
                    loginURL: URL(
                        string:
                            "https://gateway.example/hermes/login?return=%2Fhermes"
                    )!
                ),
                GatewayAuthenticationEvent(
                    profileID: profile.id,
                    loginURL: URL(
                        string: "https://gateway.example/hermes/login"
                    )!
                ),
            ]
        )
    }

    func testRemovalLogsOutOnlyAtHostScopeThenAlwaysClearsSelectedPaths() async throws {
        let profile = try GatewayProfile(
            id: "gateway-one",
            name: "One",
            baseURL: "https://gateway.example/hermes",
            token: ""
        )
        let transport = AuthSequenceTransport(
            responses: [
                GatewayHTTPResponse(data: Data(), statusCode: 204),
            ]
        )
        let cookies = AuthMemoryCookies(header: "hermes_session_rt=refresh")
        let service = GatewayAuthenticationService(
            statusClient: gatedStatusClient(),
            transport: transport,
            cookieStore: cookies,
            savedProfiles: { [profile] }
        )

        try await service.clearSession(
            for: profile.connection,
            includeHostWideCookies: true
        )

        let requests = await transport.requests
        XCTAssertEqual(
            requests.single?.url?.absoluteString,
            "https://gateway.example/hermes/auth/logout"
        )
        XCTAssertEqual(
            requests.single?.value(forHTTPHeaderField: "Cookie"),
            "hermes_session_rt=refresh"
        )
        let clears = await cookies.clearCalls
        XCTAssertEqual(
            clears,
            [.init(baseURL: profile.normalizedBaseURL, hostWide: true)]
        )
    }

    func testNavigationPolicyRequiresApprovalForExternalHTTPSAndBlocksEscapes() {
        let policy = GatewayLoginNavigationPolicy(
            gatewayLoginURL: URL(
                string: "https://gateway.example/hermes/login"
            )!
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(
                    string: "https://gateway.example/hermes/auth/login"
                )!,
                approvedExternalOrigins: []
            ),
            .allow
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "https://gateway.example/admin")!,
                approvedExternalOrigins: ["https://gateway.example:443"]
            ),
            .block(
                "Blocked navigation outside this gateway's configured path"
            )
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "https://accounts.example/login")!,
                approvedExternalOrigins: []
            ),
            .approveExternal
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "https://accounts.example/login")!,
                approvedExternalOrigins: ["https://accounts.example:443"]
            ),
            .allow
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(string: "http://accounts.example/login")!,
                approvedExternalOrigins: ["http://accounts.example:80"]
            ),
            .block(
                "Blocked an unencrypted or unsupported external sign-in page"
            )
        )
    }

    func testNavigationPolicyRejectsCredentialedAndMalformedOrigins() {
        let policy = GatewayLoginNavigationPolicy(
            gatewayLoginURL: URL(
                string: "https://gateway.example/hermes/login"
            )!
        )
        for target in [
            URL(string: "https://user:pass@accounts.example/login")!,
            URL(string: "data:text/html,sign-in")!,
        ] {
            XCTAssertEqual(
                policy.decision(
                    for: target,
                    approvedExternalOrigins: []
                ),
                .block("Blocked an invalid sign-in navigation")
            )
        }
        XCTAssertEqual(
            gatewayOriginKey(
                URL(string: "HTTPS://Gateway.Example/login")!
            ),
            "https://gateway.example:443"
        )
        XCTAssertEqual(
            gatewayDisplayOrigin(
                URL(string: "https://gateway.example:8443/login")!
            ),
            "https://gateway.example:8443"
        )
    }

    @MainActor
    func testWebKitCookieBridgePrimesExistingHttpOnlyCookiesAndFiltersHTTPSVariantsByScope() async throws {
        let websiteStore = WKWebsiteDataStore.nonPersistent()
        let webCookies = websiteStore.httpCookieStore
        for (name, path) in [
            ("hermes_session_at", "/"),
            ("__Host-hermes_session_at", "/"),
            ("__Secure-hermes_session_at", "/hermes"),
        ] {
            let cookie = try XCTUnwrap(
                HTTPCookie(
                    properties: [
                        .name: name,
                        .value: name,
                        .domain: "gateway.example",
                        .path: path,
                        .secure: "TRUE",
                        HTTPCookiePropertyKey("HttpOnly"): "TRUE",
                    ]
                )
            )
            await withCheckedContinuation { continuation in
                webCookies.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
        let store = WebKitGatewayCookieStore(dataStore: websiteStore)

        let root = try await store.cookieHeader(
            for: URL(
                string: "https://gateway.example/api/auth/ws-ticket"
            )!
        )
        XCTAssertTrue(root?.contains("hermes_session_at=") == true)
        XCTAssertTrue(root?.contains("__Host-hermes_session_at=") == true)
        XCTAssertFalse(root?.contains("__Secure-hermes_session_at=") == true)

        let prefix = try await store.cookieHeader(
            for: URL(
                string:
                    "https://gateway.example/hermes/api/auth/ws-ticket"
            )!
        )
        XCTAssertTrue(prefix?.contains("hermes_session_at=") == true)
        XCTAssertFalse(prefix?.contains("__Host-hermes_session_at=") == true)
        XCTAssertTrue(prefix?.contains("__Secure-hermes_session_at=") == true)
    }

    @MainActor
    func testSetupRetainsPendingAttemptAndPersistsOnlyAfterTicketRetrySucceeds() async throws {
        let login = URL(
            string: "https://gateway.example/hermes/login"
        )!
        let client = SignInSequenceClient(
            outcomes: [
                .failure(GatewaySignInRequiredError(loginURL: login)),
                .success(()),
            ]
        )
        let store = AuthProfileStore()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: client,
            automaticallyRestore: false
        )
        model.gatewayName = "Secure gateway"
        model.dashboardURL = "https://gateway.example/hermes"

        await model.connect()
        XCTAssertEqual(model.gatewaySignInURL, login)
        XCTAssertFalse(model.isConnected)
        let beforeSignInConnections = await store.savedConnections
        XCTAssertTrue(beforeSignInConnections.isEmpty)

        await model.completeGatewaySignIn()
        XCTAssertNil(model.gatewaySignInURL)
        XCTAssertTrue(model.isConnected)
        let savedConnections = await store.savedConnections
        let connectCount = await client.connectCount
        XCTAssertEqual(
            savedConnections.single?.token,
            ""
        )
        XCTAssertEqual(connectCount, 2)
    }

    @MainActor
    func testSetupClearsCorrectCookieScopeBeforeCommittingRemoval() async throws {
        let root = try GatewayProfile(
            id: "gateway-root",
            name: "Root",
            baseURL: "https://shared.example",
            token: ""
        )
        let prefix = try GatewayProfile(
            id: "gateway-prefix",
            name: "Prefix",
            baseURL: "https://shared.example/team",
            token: ""
        )
        let store = AuthProfileStore(
            profiles: [root, prefix],
            activeID: root.id
        )
        let cleaner = AuthSessionCleaner()
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: store,
            connectionClient: SignInSequenceClient(outcomes: []),
            sessionCleaner: cleaner,
            automaticallyRestore: false
        )
        model.savedGateways = [root, prefix]
        model.activeGatewayID = root.id
        model.connectedProfile = root
        model.state = .connected

        await model.removeGateway(id: prefix.id)

        let calls = await cleaner.calls
        XCTAssertEqual(
            calls,
            [.init(baseURL: prefix.normalizedBaseURL, hostWide: false)]
        )
        let snapshot = await store.load()
        XCTAssertEqual(snapshot.profiles, [root])
    }

    private func gatedStatusClient() -> GatewayStatusClient {
        GatewayStatusClient(
            transport: AuthFixedTransport(
                GatewayHTTPResponse(
                    data: Data(#"{"auth_required":true}"#.utf8),
                    statusCode: 200
                )
            )
        )
    }
}

private actor AuthFixedTransport: GatewayHTTPTransport {
    let response: GatewayHTTPResponse

    init(_ response: GatewayHTTPResponse) {
        self.response = response
    }

    func data(for request: URLRequest) -> GatewayHTTPResponse {
        response
    }
}

private actor AuthBoundedTransport: GatewayHTTPTransport {
    let response: GatewayHTTPResponse
    let tooLarge: Bool
    private(set) var maximumBytes: [Int64] = []

    init(response: GatewayHTTPResponse, tooLarge: Bool) {
        self.response = response
        self.tooLarge = tooLarge
    }

    func data(for request: URLRequest) throws -> GatewayHTTPResponse {
        throw AuthTestError()
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

private actor AuthSequenceTransport: GatewayHTTPTransport {
    private var responses: [GatewayHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [GatewayHTTPResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) throws -> GatewayHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw AuthTestError()
        }
        return responses.removeFirst()
    }
}

private actor AuthControlledTransport: GatewayHTTPTransport {
    private var requests: [URLRequest] = []
    private var requestWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private var responseWaiters: [
        CheckedContinuation<GatewayHTTPResponse, Never>
    ] = []

    func data(for request: URLRequest) async -> GatewayHTTPResponse {
        requests.append(request)
        let ready = requestWaiters.filter { requests.count >= $0.count }
        requestWaiters.removeAll { requests.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
        return await withCheckedContinuation { continuation in
            responseWaiters.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func completeNext(_ response: GatewayHTTPResponse) {
        responseWaiters.removeFirst().resume(returning: response)
    }
}

private actor AuthMemoryCookies: GatewayCookieStoring {
    struct ClearCall: Equatable, Sendable {
        let baseURL: String
        let hostWide: Bool
    }

    private let header: String?
    private(set) var savedURLs: [String] = []
    private(set) var clearCalls: [ClearCall] = []

    init(header: String?) {
        self.header = header
    }

    func cookieHeader(for url: URL) -> String? {
        header
    }

    func saveCookies(
        from response: GatewayHTTPResponse,
        for url: URL
    ) {
        savedURLs.append(url.absoluteString)
    }

    func clearCookies(
        for endpoint: GatewayEndpoint,
        includeHostWideCookies: Bool
    ) {
        clearCalls.append(
            ClearCall(
                baseURL: endpoint.baseURL,
                hostWide: includeHostWideCookies
            )
        )
    }
}

private actor SignInSequenceClient: GatewayConnecting {
    private var outcomes: [Result<Void, any Error>]
    private(set) var connectCount = 0

    init(outcomes: [Result<Void, any Error>]) {
        self.outcomes = outcomes
    }

    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) throws {
        connectCount += 1
        guard !outcomes.isEmpty else {
            return
        }
        try outcomes.removeFirst().get()
    }

    func close() {}
}

private actor AuthProfileStore: GatewayProfileStoring {
    private var profiles: [GatewayProfile]
    private var activeID: String?
    private(set) var savedConnections: [GatewayConnection] = []

    init(
        profiles: [GatewayProfile] = [],
        activeID: String? = nil
    ) {
        self.profiles = profiles
        self.activeID = activeID
    }

    func load() -> GatewayProfileSnapshot {
        GatewayProfileSnapshot(
            profiles: profiles,
            activeProfile: activeID.flatMap { id in
                profiles.first { $0.id == id }
            }
        )
    }

    func save(
        connection: GatewayConnection,
        name: String?
    ) throws -> GatewayProfile {
        savedConnections.append(connection)
        let profile = try GatewayProfile(
            id: "gateway-auth",
            name: name ?? "Gateway",
            baseURL: connection.baseURL,
            token: connection.token,
            cleartextPermission: connection.cleartextPermission
        )
        profiles = [profile]
        activeID = profile.id
        return profile
    }

    func selectGateway(id: String) {
        activeID = id
    }

    func removeGateway(id: String) {
        profiles.removeAll { $0.id == id }
    }

    func saveLastSessionID(
        gatewayID: String,
        storedSessionID: String
    ) {}
}

private struct AuthTestError: Error {}

private actor AuthSessionCleaner: GatewaySessionCleaning {
    struct Call: Equatable, Sendable {
        let baseURL: String
        let hostWide: Bool
    }

    private(set) var calls: [Call] = []

    func clearSession(
        for connection: GatewayConnection,
        includeHostWideCookies: Bool
    ) {
        calls.append(
            Call(
                baseURL: connection.baseURL,
                hostWide: includeHostWideCookies
            )
        )
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
