import XCTest
@testable import Nile

final class PrivateAttachmentCacheCleanupTests: XCTestCase {
    func testClearErasesDownloadedFilesAndAllowsFreshDownloads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "nile-cache-cleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PrivateAttachmentCache(directory: directory)
        try await cache.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        let first = try await cache.prepare(download())
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.path))
        try await cache.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        let next = try await cache.prepare(download())
        XCTAssertEqual(try Data(contentsOf: next.url), Data("private".utf8))
        XCTAssertNotEqual(first.url, next.url)
    }

    func testCanceledDownloadCannotRepopulateClearedCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "nile-canceled-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PrivateAttachmentCache(directory: directory)
        let gate = CachePreparationGate()
        let attachment = download()
        let preparation = Task {
            await gate.wait()
            return try await cache.prepare(attachment)
        }
        await gate.waitUntilStarted()
        preparation.cancel()
        try await cache.removeAll()
        await gate.release()

        do {
            _ = try await preparation.value
            XCTFail("Canceled attachment must not be persisted")
        } catch is CancellationError {
            // Cancellation remains distinguishable from a storage failure.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func download() -> DownloadedAttachment {
        DownloadedAttachment(
            path: "/tmp/private.txt",
            filename: "private.txt",
            mimeType: "text/plain",
            bytes: Data("private".utf8)
        )
    }
}

private actor CachePreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
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
