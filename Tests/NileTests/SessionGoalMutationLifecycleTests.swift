import XCTest
@testable import Nile

@MainActor
final class SessionGoalMutationLifecycleTests: XCTestCase {
    func testReplacementCancelsPriorTaskAndFencesBothGenerations() async {
        let lifecycle = SessionGoalMutationLifecycle()
        let firstStarted = expectation(description: "First task started")
        let firstCancelled = expectation(description: "First task cancelled")

        let first = lifecycle.start(lifecycle: 9) { _ in
            firstStarted.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                firstCancelled.fulfill()
            } catch {
                XCTFail("Unexpected task failure: \(error)")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        let replacementFinished = expectation(
            description: "Replacement task finished"
        )
        let replacement = lifecycle.start(lifecycle: 9) { _ in
            replacementFinished.fulfill()
        }
        await fulfillment(
            of: [firstCancelled, replacementFinished],
            timeout: 1
        )

        XCTAssertFalse(lifecycle.isCurrent(first, lifecycle: 9))
        XCTAssertTrue(lifecycle.isCurrent(replacement, lifecycle: 9))
        XCTAssertFalse(lifecycle.isCurrent(replacement, lifecycle: 10))

        lifecycle.reset()
        XCTAssertFalse(lifecycle.isCurrent(replacement, lifecycle: 9))
    }
}
