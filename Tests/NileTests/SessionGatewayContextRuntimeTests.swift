import XCTest
@testable import Nile

@MainActor
final class SessionGatewayContextRuntimeTests: XCTestCase {
    func testProductionAndFixtureGatewayIdentityRemainDistinct() {
        let production = SessionGatewayContextRuntime(
            hasSessionRepository: true
        )
        let fixture = SessionGatewayContextRuntime(
            hasSessionRepository: false
        )

        XCTAssertNil(production.currentGatewayID)
        XCTAssertNil(production.productionGatewayID)
        XCTAssertEqual(fixture.currentGatewayID, "fixture")
        XCTAssertNil(fixture.productionGatewayID)

        production.setLoadedGatewayID("gateway")
        XCTAssertEqual(production.currentGatewayID, "gateway")
        XCTAssertEqual(production.productionGatewayID, "gateway")
    }

    func testListedTerminalSessionRoutesToDurableHistory() {
        let runtime = context()
        let terminal = session(id: "one", source: "cli")

        runtime.recordListedSessions([terminal])

        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "one",
                listedSession: terminal
            ),
            .terminalHistory
        )
    }

    func testRememberedTerminalOwnershipSurvivesPartialListPage() {
        let runtime = context()
        runtime.recordListedSessions([session(id: "one", source: "tui")])
        runtime.recordListedSessions([])

        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "one",
                listedSession: nil
            ),
            .terminalHistory
        )
    }

    func testNonterminalSourceRoutesLiveAndMissingSourceRequiresLookup() {
        let runtime = context()

        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "one",
                listedSession: session(id: "one", source: "niles")
            ),
            .live
        )
        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "two",
                listedSession: session(id: "two", source: " ")
            ),
            .needsSourceLookup
        )
    }

    func testClaimOverridesLaterTerminalListUntilGatewayChanges() {
        let runtime = context()
        let terminal = session(id: "one", source: "terminal")
        runtime.recordListedSessions([terminal])
        runtime.recordClaim(
            storedSessionID: "one",
            resumedStoredSessionID: "resumed"
        )
        runtime.recordListedSessions([terminal])

        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "one",
                listedSession: terminal
            ),
            .live
        )
        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "resumed",
                listedSession: nil
            ),
            .live
        )

        runtime.clearGateway()
        XCTAssertEqual(
            runtime.displayRoute(
                storedSessionID: "one",
                listedSession: terminal
            ),
            .terminalHistory
        )
    }

    func testExplicitSourceLookupCanRecordTerminalProvenance() {
        let runtime = context()
        runtime.recordTerminalSession(storedSessionID: "one")

        XCTAssertTrue(
            runtime.isReadOnlySession(
                storedSessionID: "one",
                sessions: []
            )
        )
    }

    private func context() -> SessionGatewayContextRuntime {
        SessionGatewayContextRuntime(hasSessionRepository: true)
    }

    private func session(id: String, source: String) -> HermesSession {
        HermesSession(
            id: id,
            title: nil,
            preview: nil,
            source: source,
            messageCount: 0,
            startedAt: nil,
            lastMessageAt: nil
        )
    }
}
