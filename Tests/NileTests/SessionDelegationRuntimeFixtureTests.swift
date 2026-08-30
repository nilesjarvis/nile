import XCTest
@testable import Nile

@MainActor
final class SessionDelegationRuntimeFixtureTests: XCTestCase {
    func testEventFixturesUseProductionProjectionPath() {
        let owner = DelegationOwner(
            gatewayID: "fixture-gateway",
            storedSessionID: "fixture-session"
        )
        for settled in [false, true] {
            let runtime = SessionDelegationRuntime(repository: nil)
            runtime.installFixture(
                .make(settled: settled),
                owner: owner,
                liveSessionID: "fixture-live"
            )
            let transcript = runtime.project(
                gatewayID: owner.gatewayID,
                storedSessionID: owner.storedSessionID,
                transcript: []
            )

            XCTAssertEqual(runtime.turns.count, 1)
            XCTAssertEqual(runtime.pinnedTurnID == nil, settled)
            XCTAssertEqual(transcript.count, 1)
        }
    }

    func testPresentationFixtureInstallsExactProjection() {
        let runtime = SessionDelegationRuntime(repository: nil)

        let transcript = runtime.installPresentationFixture(.androidVisual)

        XCTAssertEqual(runtime.turns.count, 1)
        XCTAssertEqual(runtime.turns.first?.agents.count, 3)
        XCTAssertEqual(runtime.pinnedTurnID, "delegation-turn")
        XCTAssertEqual(transcript.count, 1)
    }
}
