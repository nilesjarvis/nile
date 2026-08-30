import XCTest
@testable import Nile

@MainActor
final class SessionEventRuntimeTests: XCTestCase {
    func testVisibleDeltaFlushesLosslesslyBeforeNextOrderedEvent() async {
        let repository = SessionRepositoryStub(sessions: [])
        let runtime = SessionEventRuntime(
            repository: repository,
            assistantDeltaPublicationInterval: .seconds(60)
        )
        var deliveries: [Delivery] = []
        let receivedTool = expectation(description: "received ordered tool")

        runtime.beginRouting(
            visibleSessionID: { "live-one" },
            onOrderedEvent: { event in
                deliveries.append(.ordered(event))
                receivedTool.fulfill()
            },
            onVisibleAssistantDelta: { event in
                deliveries.append(.visibleDelta(event))
                return true
            },
            onHiddenAssistantDelta: { event in
                deliveries.append(.hiddenDelta(event))
            }
        )

        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "hello ")
        )
        await repository.yield(
            .assistantDelta(sessionID: "live-one", text: "there")
        )
        let tool = HermesStreamEvent.toolStart(
            sessionID: "live-one",
            toolID: "tool-one",
            name: "terminal",
            detail: nil,
            context: "Run tests",
            generating: false
        )
        await repository.yield(tool)

        await fulfillment(of: [receivedTool], timeout: 1)
        XCTAssertEqual(deliveries, [
            .visibleDelta(
                .assistantDelta(
                    sessionID: "live-one",
                    text: "hello there"
                )
            ),
            .ordered(tool),
        ])
        XCTAssertEqual(runtime.assistantDeltaPublicationCount, 1)
    }

    func testHiddenDeltaBypassesVisibleCadenceAndPublicationCount() async {
        let repository = SessionRepositoryStub(sessions: [])
        let runtime = SessionEventRuntime(
            repository: repository,
            assistantDeltaPublicationInterval: .seconds(60)
        )
        var deliveries: [Delivery] = []
        let receivedHiddenDelta = expectation(
            description: "received hidden delta"
        )

        runtime.beginRouting(
            visibleSessionID: { "live-one" },
            onOrderedEvent: { event in
                deliveries.append(.ordered(event))
            },
            onVisibleAssistantDelta: { event in
                deliveries.append(.visibleDelta(event))
                return true
            },
            onHiddenAssistantDelta: { event in
                deliveries.append(.hiddenDelta(event))
                receivedHiddenDelta.fulfill()
            }
        )

        let delta = HermesStreamEvent.assistantDelta(
            sessionID: "live-two",
            text: "background"
        )
        await repository.yield(delta)

        await fulfillment(of: [receivedHiddenDelta], timeout: 1)
        XCTAssertEqual(deliveries, [.hiddenDelta(delta)])
        XCTAssertEqual(runtime.assistantDeltaPublicationCount, 0)
    }

    private enum Delivery: Equatable {
        case ordered(HermesStreamEvent)
        case visibleDelta(HermesStreamEvent)
        case hiddenDelta(HermesStreamEvent)
    }
}
