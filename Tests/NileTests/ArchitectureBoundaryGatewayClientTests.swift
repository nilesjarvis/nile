import Foundation
import XCTest

extension ArchitectureBoundaryTests {
    func testGatewayWebSocketClientKeepsStateAndPoliciesBounded() throws {
        let gatewayDirectory = repositoryRoot.appendingPathComponent("Sources/Nile/Data/Gateway", isDirectory: true)
        let names = [
            "TuiGatewayClient.swift",
            "TuiGatewayClientReceiveLifecycle.swift",
            "TuiGatewayClientRequestLifecycle.swift",
            "TuiGatewayClientContracts.swift",
            "GatewayConnectionFailurePolicy.swift",
            "GatewayAsyncPrimitives.swift",
        ]
        let sources = try names.map { try source(in: gatewayDirectory, named: $0) }
        let clientSource = sources[0]
        let receiveSource = sources[1]
        let requestSource = sources[2]
        let contractsSource = sources[3]
        let failurePolicySource = sources[4]
        let asyncSource = sources[5]
        let implementationSources = [clientSource, receiveSource, requestSource]

        for marker in [
            "actor TuiGatewayClient",
            "var currentAttempt: ConnectionAttempt?",
            "struct ConnectionAttempt",
            "private func establish(",
            "func yieldSignal(",
            "GatewayConnectionFailurePolicy.connectionError(for: error)",
        ] {
            XCTAssertTrue(clientSource.contains(marker))
        }
        for forbidden in ["func receiveLoop(", "func request(", "struct TerminalEffects"] {
            XCTAssertFalse(clientSource.contains(forbidden))
        }

        for marker in [
            "extension TuiGatewayClient",
            "func receiveLoop(",
            "private func handleLine(",
            "private func protocolViolation(",
            "func terminalEffects(",
            "func terminateAfterRequestSendFailure(",
            "struct TerminalEffects",
            "enum SocketAction",
            "GatewayConnectionFailurePolicy.classify(error)",
        ] {
            XCTAssertTrue(receiveSource.contains(marker))
        }
        for forbidden in ["actor TuiGatewayClient", "var currentAttempt:", "func request(", "rawSignalContinuation"] {
            XCTAssertFalse(receiveSource.contains(forbidden))
        }

        for marker in [
            "extension TuiGatewayClient",
            "func request(",
            "func handleResponse(",
            "private func removePending(",
            "private func allocateRequestID(",
            "struct PendingCall",
            "frameCodec.encodeRequest(",
            "frameCodec.decodeResponse(",
            "GatewayDeadline.run(",
            "throw await terminateAfterRequestSendFailure(",
        ] {
            XCTAssertTrue(requestSource.contains(marker))
        }
        for forbidden in [
            "actor TuiGatewayClient",
            "terminalEffects(",
            "receiveLoop(",
            "rawSignalContinuation",
            "requestFactory",
        ] {
            XCTAssertFalse(requestSource.contains(forbidden))
        }
        XCTAssertEqual(
            implementationSources.filter { $0.contains("var currentAttempt:") }.count,
            1,
            "Keep one connection-attempt state owner"
        )
        XCTAssertEqual(
            implementationSources.filter { $0.contains("struct PendingCall") }.count,
            1,
            "Keep pending request records in the request lifecycle"
        )
        for marker in [
            "actor TuiGatewayClient",
            "func receiveLoop(",
            "struct TerminalEffects",
            "rawSignalContinuation",
        ] {
            XCTAssertEqual(
                implementationSources.filter { $0.contains(marker) }.count,
                1,
                "Keep one transport owner for \(marker)"
            )
        }
        for source in implementationSources {
            XCTAssertFalse(source.contains("private func classifyHTTP("))
            XCTAssertFalse(source.contains("private func classifyClose("))
            XCTAssertFalse(source.contains("sanitizeCredential"))
            XCTAssertFalse(source.contains("withThrowingTaskGroup"))
            XCTAssertFalse(source.contains("AsyncThrowingStream"))
        }

        let contractDeclarations = [
            "struct GatewayFailure: Equatable, Sendable",
            "enum GatewaySignal: Equatable, Sendable",
            "struct GatewaySignalSequence: AsyncSequence, Sendable",
            "protocol GatewayConnecting: Sendable",
        ]
        for declaration in contractDeclarations {
            XCTAssertTrue(contractsSource.contains(declaration))
            XCTAssertFalse(implementationSources.contains { $0.contains(declaration) })
        }
        XCTAssertTrue(contractsSource.contains("@Sendable (Int64) async -> Bool"))
        XCTAssertTrue(contractsSource.contains("acceptsGeneration(signal.generation)"))
        XCTAssertFalse(contractsSource.contains("TuiGatewayClient"))
        XCTAssertTrue(clientSource.contains("private func acceptsSignal(from generation:"))
        XCTAssertFalse(contractsSource.contains("var currentAttempt"))
        XCTAssertFalse(contractsSource.contains("terminalEffects("))

        for marker in [
            "enum GatewayConnectionFailurePolicy",
            "struct GatewayFailureClassification",
            "static func connectionError(",
            "static func classify(",
            "case 4_401:",
            "case 4_403:",
            "case 1_002, 1_003, 1_007:",
            "prefix(160)",
            "$1<redacted>",
        ] {
            XCTAssertTrue(failurePolicySource.contains(marker))
        }
        XCTAssertFalse(failurePolicySource.contains("actor TuiGatewayClient"))
        XCTAssertFalse(failurePolicySource.contains("currentAttempt"))
        XCTAssertFalse(failurePolicySource.contains("GatewayOneShot"))

        for marker in [
            "struct GatewayDeadlineExceeded",
            "enum GatewayDeadline",
            "struct GatewayOneShot",
            "withThrowingTaskGroup",
            "bufferingNewest(1)",
        ] {
            XCTAssertTrue(asyncSource.contains(marker))
        }
        XCTAssertFalse(asyncSource.contains("GatewayWebSocket"))
        XCTAssertFalse(asyncSource.contains("GatewayConnection"))
        XCTAssertFalse(asyncSource.contains("token"))
        XCTAssertFalse(asyncSource.contains("ticket"))

        XCTAssertEqual(
            [clientSource, receiveSource, requestSource, failurePolicySource, asyncSource].map {
                $0.components(separatedBy: "sanitizeCredential").count - 1
            }.reduce(0, +),
            3,
            "Keep credential redaction implementation and its two calls together"
        )
        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        for (lineCount, limit) in zip(lineCounts, [275, 275, 155, 75, 175, 70]) {
            XCTAssertLessThan(lineCount, limit)
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            975,
            "Do not hide WebSocket client growth behind lifecycle or policy splits"
        )
    }

    func testGatewayAuthenticationSeparatesActorCookieIOAndPolicy() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Data/Gateway", isDirectory: true)
        let gatewaySource: (String) throws -> String = { try self.source(in: directory, named: $0) }
        let contractsSource = try gatewaySource("GatewayAuthenticationContracts.swift")
        let authenticationSource = try gatewaySource("GatewayAuthentication.swift")
        let httpPolicySource = try gatewaySource("GatewayAuthenticationHTTPPolicy.swift")
        let rotationSource = try gatewaySource("GatewayCookieRotationGate.swift")
        let storeSource = try gatewaySource("GatewayCookieStore.swift")
        let policySource = try gatewaySource("GatewayCookiePolicy.swift")
        let sources = [contractsSource, authenticationSource, httpPolicySource,
                       rotationSource, storeSource, policySource]

        for marker in ["protocol GatewaySessionCleaning:", "struct GatewayCookieScopeConflictError:", "struct GatewayAuthenticationEvent:"] { XCTAssertTrue(contractsSource.contains(marker)); XCTAssertFalse(authenticationSource.contains(marker)) }
        for forbidden in ["actor ", "GatewayHTTPTransport", "GatewayCookieStoring", "GatewayCookiePolicy", "URLRequest", "import WebKit", "HTTPCookie", "Task<"] { XCTAssertFalse(contractsSource.contains(forbidden)) }

        for marker in ["actor GatewayAuthenticationService:", "private let statusClient:",
                       "private let transport: any GatewayHTTPTransport", "private let cookieStore:",
                       "private let cookieRotation = GatewayCookieRotationGate()", "private func mintTicket(",
                       "private func validateCookieScope(", "private func publishAuthenticationExpiry(",
                       "private func bestEffortLogout(", "GatewayAuthenticationHTTPPolicy.ticket("] {
            XCTAssertTrue(authenticationSource.contains(marker))
            XCTAssertFalse(contractsSource.contains(marker))
            XCTAssertFalse(rotationSource.contains(marker))
        }
        for forbidden in ["JSONSerialization", "request.httpMethod = \"POST\"",
                          "request.httpBody = Data()", "reloadIgnoringLocalAndRemoteCacheData",
                          "GatewayResponseLimits.controlJSON"] {
            XCTAssertFalse(authenticationSource.contains(forbidden))
        }
        for marker in ["enum GatewayAuthenticationHTTPPolicy",
                       "static let responseLimit = GatewayResponseLimits.controlJSON",
                       "static func ticketURL(", "static func ticketRequest(",
                       "static func logoutURL(", "static func controlPOSTRequest(",
                       "static func ticket(", "JSONSerialization.jsonObject(",
                       "GatewayDashboardResponsePolicy.safeLoginURL(",
                       "GatewayCookiePolicy.nonBlank("] {
            XCTAssertTrue(httpPolicySource.contains(marker))
            XCTAssertFalse(contractsSource.contains(marker))
            XCTAssertFalse(rotationSource.contains(marker))
        }
        for forbidden in ["actor ", "await ", "Task<", "GatewayHTTPTransport",
                          "GatewayCookieStoring", "savedProfiles", "AsyncStream"] {
            XCTAssertFalse(httpPolicySource.contains(forbidden))
        }
        for marker in ["actor GatewayCookieRotationGate", "private var locked", "private var waiters:",
                       "private struct Waiter", "func withCancellationShield", "func withInterruptibleRotation",
                       "private func acquire(", "private func release(", "private func cancelWaiter("] {
            XCTAssertTrue(rotationSource.contains(marker))
            XCTAssertFalse(authenticationSource.contains(marker))
        }
        for forbidden in ["GatewayHTTPTransport", "GatewayCookieStoring", "GatewayProfile",
                          "GatewayAuthenticationEvent", "URLRequest", "import WebKit", "HTTPCookie"] {
            XCTAssertFalse(rotationSource.contains(forbidden))
        }
        for marker in ["import WebKit", "protocol GatewayCookieStoring", "final class WebKitGatewayCookieStore",
                       "private let store: WKHTTPCookieStore", "private let readiness: Task<Void, Never>",
                       "final class WebKitCookieStorePrimer", "webView.loadHTMLString(\"\", baseURL: nil)",
                       "GatewayCookiePolicy.header(",
                       "GatewayCookiePolicy.cookiesToClear(", "GatewayCookiePolicy.nonBlank("] {
            XCTAssertTrue(storeSource.contains(marker))
        }
        for forbidden in ["savedProfiles", "mintTicket", "private var locked", "sessionCookieNames"] {
            XCTAssertFalse(storeSource.contains(forbidden))
        }
        for marker in ["enum GatewayCookiePolicy", "static func scopesOverlap(", "static func contains(",
                       "static func header(", "static func cookiesToClear(", "static func nonBlank(",
                       "private static let sessionCookieNames", "private static let hostCookieNames",
                       "private static let secureCookieNames", "components.user == nil",
                       "components.password == nil"] {
            XCTAssertTrue(policySource.contains(marker))
        }
        for forbidden in ["import WebKit", "actor ", "await ", "savedProfiles", "GatewayHTTPTransport"] {
            XCTAssertFalse(policySource.contains(forbidden))
        }
        for source in [contractsSource, authenticationSource, httpPolicySource,
                       rotationSource, policySource] {
            XCTAssertFalse(source.contains("WKHTTPCookieStore"))
            XCTAssertFalse(source.contains("protocol GatewayCookieStoring"))
        }
        let lineCounts = sources.map { $0.components(separatedBy: .newlines).count }
        for (count, cap) in zip(lineCounts, [35, 255, 110, 105, 145, 205]) { XCTAssertLessThan(count, cap) }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            785,
            "Keep authentication I/O, HTTP policy, rotation, cookie storage, and cookie policy bounded"
        )
    }

    func testGatewayEventProjectionKeepsOneRouterAndBoundedPayloadProjectors()
        throws
    {
        let gatewayDirectory = repositoryRoot.appendingPathComponent(
            "Sources/Nile/Data/Gateway",
            isDirectory: true
        )
        let coreSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayEventProjector.swift"
            )
        )
        let blockingSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayBlockingEventProjector.swift"
            )
        )
        let statusSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewayStatusEventProjector.swift"
            )
        )
        let subagentSource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "GatewaySubagentEventProjector.swift"
            )
        )
        let repositorySource = try source(
            at: gatewayDirectory.appendingPathComponent(
                "TuiGatewayRepository.swift"
            )
        )

        XCTAssertTrue(coreSource.contains("struct GatewayEventProjector"))
        XCTAssertTrue(
            coreSource.contains(
                "private let blocking = GatewayBlockingEventProjector()"
            )
        )
        XCTAssertTrue(
            coreSource.contains(
                "private let status = GatewayStatusEventProjector()"
            )
        )
        XCTAssertTrue(
            coreSource.contains(
                "private let subagents = GatewaySubagentEventProjector()"
            )
        )
        XCTAssertTrue(coreSource.contains("return blocking.project(frame)"))
        XCTAssertTrue(coreSource.contains("return status.project(frame)"))
        XCTAssertTrue(coreSource.contains("return subagents.project(frame)"))
        XCTAssertTrue(coreSource.contains("GatewaySessionCodec()"))
        XCTAssertTrue(coreSource.contains("private func positiveDouble("))
        XCTAssertTrue(coreSource.contains("private func todoItems("))
        XCTAssertFalse(coreSource.contains("preAPICompressionTokenEstimate("))
        XCTAssertFalse(coreSource.contains("parseGoalProgressUpdate("))
        XCTAssertFalse(coreSource.contains("NSRegularExpression"))
        XCTAssertFalse(coreSource.contains("InvalidBlockingPayload"))
        XCTAssertFalse(coreSource.contains("requiredBlockingString"))
        XCTAssertFalse(coreSource.contains("subagentEventData"))
        XCTAssertFalse(coreSource.contains("subagentTerminalStatus"))

        XCTAssertTrue(
            blockingSource.contains("struct GatewayBlockingEventProjector")
        )
        XCTAssertTrue(blockingSource.contains("case \"clarify.request\":"))
        XCTAssertTrue(blockingSource.contains("case \"approval.request\":"))
        XCTAssertTrue(blockingSource.contains("case \"sudo.request\":"))
        XCTAssertTrue(blockingSource.contains("case \"secret.request\":"))
        XCTAssertTrue(blockingSource.contains(".blockingRequestInvalid("))
        XCTAssertTrue(blockingSource.contains("InvalidBlockingPayload"))
        XCTAssertTrue(blockingSource.contains("private func requiredString("))
        XCTAssertTrue(blockingSource.contains("private func secretMetadata("))
        XCTAssertFalse(blockingSource.contains("SubagentEventData"))
        XCTAssertFalse(blockingSource.contains("GatewaySessionCodec"))
        XCTAssertFalse(blockingSource.contains("parseGoalProgressUpdate"))

        XCTAssertTrue(
            statusSource.contains("struct GatewayStatusEventProjector")
        )
        XCTAssertTrue(statusSource.contains("func project("))
        XCTAssertTrue(statusSource.contains(".goalUpdate("))
        XCTAssertTrue(statusSource.contains(".compactionStarted("))
        XCTAssertTrue(statusSource.contains(".statusUpdate("))
        XCTAssertTrue(
            statusSource.contains("private func parseGoalProgressUpdate(")
        )
        XCTAssertTrue(
            statusSource.contains("private func preAPICompressionTokenEstimate(")
        )
        XCTAssertTrue(statusSource.contains("NSRegularExpression"))
        XCTAssertFalse(statusSource.contains("InvalidBlockingPayload"))
        XCTAssertFalse(statusSource.contains("SubagentEventData"))
        XCTAssertFalse(statusSource.contains("GatewaySessionCodec"))
        XCTAssertFalse(statusSource.contains("TodoItem("))

        XCTAssertTrue(
            subagentSource.contains("struct GatewaySubagentEventProjector")
        )
        XCTAssertTrue(subagentSource.contains("SubagentEventData("))
        XCTAssertTrue(subagentSource.contains("Double(Int32.max)"))
        XCTAssertTrue(subagentSource.contains("strippingANSI()"))
        XCTAssertTrue(subagentSource.contains("explicitError ?? inferredError"))
        XCTAssertTrue(subagentSource.contains("private func terminalStatus("))
        XCTAssertFalse(subagentSource.contains("InvalidBlockingPayload"))
        XCTAssertFalse(subagentSource.contains("SecretRequestMetadata"))
        XCTAssertFalse(subagentSource.contains("GatewaySessionCodec"))
        XCTAssertFalse(subagentSource.contains("parseGoalProgressUpdate"))

        XCTAssertTrue(
            repositorySource.contains("let projector = GatewayEventProjector()")
        )
        XCTAssertTrue(repositorySource.contains("projector.project(frame)"))
        XCTAssertFalse(
            repositorySource.contains("GatewayBlockingEventProjector")
        )
        XCTAssertFalse(
            repositorySource.contains("GatewaySubagentEventProjector")
        )
        XCTAssertFalse(
            repositorySource.contains("GatewayStatusEventProjector")
        )
        XCTAssertEqual(
            repositorySource.components(
                separatedBy: "GatewayEventProjector()"
            ).count - 1,
            1,
            "Keep one repository-facing ordered event router"
        )

        let projectorSources = [
            coreSource,
            statusSource,
            blockingSource,
            subagentSource,
        ]
        for declaration in [
            "private func parseGoalProgressUpdate(",
            "private func preAPICompressionTokenEstimate(",
        ] {
            XCTAssertEqual(
                projectorSources.filter { $0.contains(declaration) }.count,
                1
            )
        }
        let lineCounts = projectorSources.map {
            $0.components(separatedBy: .newlines).count
        }
        for (count, cap) in zip(lineCounts, [155, 155, 180, 165]) {
            XCTAssertLessThan(count, cap)
        }
        XCTAssertLessThan(
            lineCounts.reduce(0, +),
            620,
            "Do not hide event projection growth behind payload source splits"
        )
    }

    func testGatewayDashboardOwnsBoundedTransportAndSecurityPolicies() throws {
        let directory = repositoryRoot.appendingPathComponent("Sources/Nile/Data/Gateway", isDirectory: true)
        let contracts = try source(in: directory, named: "GatewayDashboardContracts.swift")
        let core = try source(in: directory, named: "GatewayDashboardClient.swift")
        let responsePolicy = try source(in: directory, named: "GatewayDashboardResponsePolicy.swift")
        let download = try source(in: directory, named: "GatewayDashboardDownload.swift")
        let policy = try source(in: directory, named: "GatewayDashboardDownloadPolicy.swift")
        let origin = try source(in: directory, named: "GatewayURLOriginPolicy.swift")
        for marker in ["protocol GatewayDashboardReading: Sendable", "extension GatewayDashboardReading", "Dashboard queries are unavailable", "Attachment downloads are unavailable", "Dashboard mutations are unavailable"] {
            XCTAssertTrue(contracts.contains(marker)); XCTAssertFalse(core.contains(marker))
        }
        for marker in ["struct GatewayDashboardClient: GatewayDashboardReading", "let transport: any GatewayHTTPTransport", "private func jsonRequest(", "query.sorted", "transport.data(", "X-Hermes-Session-Token"] {
            XCTAssertTrue(core.contains(marker)); XCTAssertFalse(contracts.contains(marker))
        }
        for forbidden in ["static func safeLoginURL(", "static func errorDetail(", "GatewayURLOriginPolicy.sameOrigin"] { XCTAssertFalse(core.contains(forbidden)) }
        for marker in ["enum GatewayDashboardResponsePolicy", "static func safeLoginURL(", "static func errorDetail(", "static func isRetryableHTTPStatus(", "isSafeLoginCandidate(", "GatewayURLOriginPolicy.sameOrigin"] { XCTAssertTrue(responsePolicy.contains(marker)) }
        for forbidden in ["URLRequest", "transport.data(", "X-Hermes-Session-Token", "connection.token", "func download("] { XCTAssertFalse(responsePolicy.contains(forbidden)) }
        for marker in ["extension GatewayDashboardClient", "func download(", "redirectCount < 5", "authenticated = false", "transport.data(", "X-Hermes-Session-Token", "GatewayURLOriginPolicy.sameOrigin", "GatewayDashboardResponsePolicy"] {
            XCTAssertTrue(download.contains(marker))
        }
        for marker in ["enum GatewayDashboardDownloadPolicy", "static func source(", "static func validateExternalMediaURL(", "static func validateRedirect(", "static func safeFilename(", "private static func managedSource(", "private static let filenamePattern"] {
            XCTAssertTrue(policy.contains(marker)); XCTAssertFalse(download.contains(marker))
        }
        for forbidden in ["URLRequest", "transport.data(", "X-Hermes-Session-Token", "connection.token", "func download(", "static func safeLoginURL("] {
            XCTAssertFalse(policy.contains(forbidden))
        }
        for marker in ["enum GatewayURLOriginPolicy", "static func sameOrigin(", "static func effectivePort("] { XCTAssertTrue(origin.contains(marker)) }
        for forbidden in ["HermesError", "GatewayConnection", "URLRequest", "token", "filename"] { XCTAssertFalse(origin.contains(forbidden)) }
        let implementation = [core, responsePolicy, download, policy, origin]
        for declaration in ["static func safeLoginURL(", "static func errorDetail(", "static func isRetryableHTTPStatus("] {
            XCTAssertEqual(implementation.filter { $0.contains(declaration) }.count, 1)
        }
        XCTAssertEqual(implementation.map { $0.components(separatedBy: "static func effectivePort(").count - 1 }.reduce(0, +), 1)
        let sources = [contracts] + implementation
        XCTAssertTrue(zip(sources, [100, 220, 100, 140, 255, 45]).allSatisfy { $0.0.components(separatedBy: .newlines).count < $0.1 })
        XCTAssertLessThan(sources.map { $0.components(separatedBy: .newlines).count }.reduce(0, +), 790)
    }

}
