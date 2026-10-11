import XCTest
@testable import Nile

@MainActor
final class SessionMediaPrivacyTests: XCTestCase {
    func testChangedGatewayOwnerPreventsDownloadedFileFromReachingCache() async {
        let repository = PrivacyMediaRepository()
        let cache = PrivacyMediaCache()
        let runtime = SessionMediaRuntime(repository: repository, cache: cache)
        let owner = SessionMediaRuntime.Owner(
            gatewayGeneration: 1,
            displayGeneration: 1,
            gatewayID: "gateway",
            storedSessionID: "session"
        )
        let currentOwner = CurrentPrivacyMediaOwner()
        runtime.open(
            path: "/tmp/private.txt",
            owner: owner,
            isCurrentOwner: { _ in currentOwner.isCurrent },
            onError: { _ in }
        )
        await repository.waitUntilStarted()
        currentOwner.isCurrent = false
        await repository.release()

        for _ in 0..<200 where runtime.isOpeningAttachment {
            await Task.yield()
        }
        XCTAssertFalse(runtime.isOpeningAttachment)
        XCTAssertNil(runtime.openedAttachment)
        let calls = await cache.calls
        XCTAssertEqual(calls, 0)
    }
}

@MainActor
private final class CurrentPrivacyMediaOwner {
    var isCurrent = true
}

private actor PrivacyMediaRepository: HermesAttachmentReading {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?

    func downloadAttachment(path: String, maxBytes: Int64) async -> DownloadedAttachment {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
        return DownloadedAttachment(
            path: path,
            filename: "private.txt",
            mimeType: "text/plain",
            bytes: Data("private".utf8)
        )
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor PrivacyMediaCache: AttachmentCaching {
    var calls = 0

    func prepare(_ attachment: DownloadedAttachment) -> CachedAttachment {
        calls += 1
        return CachedAttachment(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/fixture-only.txt"),
            filename: attachment.filename,
            mimeType: attachment.mimeType
        )
    }
}
