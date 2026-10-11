import XCTest
@testable import Nile

@MainActor
final class PrivacyCleanupModelTests: XCTestCase {
    func testClearReservesDisconnectedSetupUntilAllDataIsErased() async {
        let setup = makeSetup()
        let cache = CleanupCache()
        let websiteData = BlockingWebsiteCleaner()
        let cleanup = PrivacyCleanupModel(
            gatewaySetup: setup,
            attachmentCache: cache,
            websiteData: websiteData
        )
        let task = Task { await cleanup.clearLocalCaches() }
        await websiteData.waitUntilStarted()

        XCTAssertTrue(cleanup.isClearing)
        XCTAssertFalse(cleanup.canClearData)
        XCTAssertEqual(setup.state, .checking)
        XCTAssertFalse(cleanup.didClearData)

        await cleanup.clearLocalCaches()
        await websiteData.finish()
        await task.value

        XCTAssertEqual(setup.state, .idle)
        XCTAssertFalse(cleanup.isClearing)
        XCTAssertTrue(cleanup.didClearData)
        XCTAssertNil(cleanup.errorMessage)
        let cacheCalls = await cache.calls
        let websiteCalls = await websiteData.calls
        XCTAssertEqual(cacheCalls, 1)
        XCTAssertEqual(websiteCalls, 1)
    }

    func testClearStillErasesWebsiteDataAfterFileFailureAndAllowsRetry() async {
        let setup = makeSetup()
        let cache = CleanupCache(fails: true)
        let websiteData = ImmediateWebsiteCleaner()
        let cleanup = PrivacyCleanupModel(
            gatewaySetup: setup,
            attachmentCache: cache,
            websiteData: websiteData
        )

        await cleanup.clearLocalCaches()

        XCTAssertFalse(cleanup.didClearData)
        XCTAssertNotNil(cleanup.errorMessage)
        XCTAssertTrue(cleanup.canClearData)
        let firstWebsiteCalls = await websiteData.calls
        XCTAssertEqual(firstWebsiteCalls, 1)

        await cache.allowRemoval()
        await cleanup.clearLocalCaches()

        XCTAssertTrue(cleanup.didClearData)
        XCTAssertNil(cleanup.errorMessage)
        let secondWebsiteCalls = await websiteData.calls
        XCTAssertEqual(secondWebsiteCalls, 2)
    }

    func testConnectedConnectingAndSignInStatesCannotClearData() async {
        let setup = makeSetup()
        let cache = CleanupCache()
        let websiteData = ImmediateWebsiteCleaner()
        let cleanup = PrivacyCleanupModel(
            gatewaySetup: setup,
            attachmentCache: cache,
            websiteData: websiteData
        )
        for state in [GatewaySetupModel.ProbeState.loading, .checking,
                      .reconnecting, .restoring, .connected] {
            setup.state = state
            XCTAssertFalse(cleanup.canClearData)
            await cleanup.clearLocalCaches()
        }
        setup.state = .idle
        setup.gatewaySignInURL = URL(string: "https://example.com/login")
        XCTAssertFalse(cleanup.canClearData)
        await cleanup.clearLocalCaches()

        let cacheCalls = await cache.calls
        let websiteCalls = await websiteData.calls
        XCTAssertEqual(cacheCalls, 0)
        XCTAssertEqual(websiteCalls, 0)
    }

    private func makeSetup() -> GatewaySetupModel {
        let setup = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(),
            connectionClient: ModelGatewayClient(),
            automaticallyRestore: false
        )
        setup.state = .idle
        return setup
    }
}

private actor CleanupCache: AttachmentCacheClearing {
    var calls = 0
    private var fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func removeAll() throws {
        calls += 1
        if fails { throw AttachmentCacheError.cleanupFailed }
    }

    func allowRemoval() { fails = false }
}

private actor ImmediateWebsiteCleaner: GatewayWebsiteDataCleaning {
    var calls = 0
    func removeAll() { calls += 1 }
}

private actor BlockingWebsiteCleaner: GatewayWebsiteDataCleaning {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?

    func removeAll() async {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
