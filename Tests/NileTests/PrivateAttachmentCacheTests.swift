import XCTest
@testable import Nile

final class PrivateAttachmentCacheTests: XCTestCase {
    func testWritesSanitizedProtectedBackupExcludedFile() async throws {
        let fixture = try TemporaryAttachmentCache()
        let cache = PrivateAttachmentCache(directory: fixture.directory)
        let cached = try await cache.prepare(
            DownloadedAttachment(
                path: "/tmp/source",
                filename: "../../unsafe:\0name.txt",
                mimeType: "text/plain",
                bytes: Data("private".utf8)
            )
        )

        XCTAssertEqual(cached.filename, "unsafe__name.txt")
        XCTAssertEqual(try Data(contentsOf: cached.url), Data("private".utf8))
        XCTAssertEqual(
            try cached.url.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: cached.url.path
        )
#if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(
                protection,
                .completeUntilFirstUserAuthentication
            )
        }
#else
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
#endif
    }

    func testPrunesOldestEntryByCountAndBytes() async throws {
        let fixture = try TemporaryAttachmentCache()
        let cache = PrivateAttachmentCache(
            directory: fixture.directory,
            maximumEntries: 2,
            maximumBytes: 8
        )
        let first = try await cache.prepare(download("one", bytes: 3))
        let second = try await cache.prepare(download("two", bytes: 3))
        let third = try await cache.prepare(download("three", bytes: 3))

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.url.deletingLastPathComponent().path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.url.path))
    }

    func testLongFilenameKeepsExtensionForSystemPreview() async throws {
        let fixture = try TemporaryAttachmentCache()
        let cache = PrivateAttachmentCache(directory: fixture.directory)
        let cached = try await cache.prepare(
            DownloadedAttachment(
                path: "/reports/final",
                filename: String(repeating: "quarterly-report-", count: 12)
                    + ".pdf",
                mimeType: "application/pdf",
                bytes: Data("%PDF".utf8)
            )
        )

        XCTAssertLessThanOrEqual(cached.filename.count, 120)
        XCTAssertTrue(cached.filename.hasSuffix(".pdf"))
        XCTAssertEqual(cached.url.pathExtension, "pdf")
        XCTAssertEqual(try Data(contentsOf: cached.url), Data("%PDF".utf8))
    }

    func testRejectsFileLargerThanEntirePrivateCache() async {
        let fixture = try! TemporaryAttachmentCache()
        let cache = PrivateAttachmentCache(
            directory: fixture.directory,
            maximumBytes: 4
        )
        do {
            _ = try await cache.prepare(download("large", bytes: 5))
            XCTFail("Expected bounded private cache rejection")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Attachment exceeds the private viewer cache limit"
            )
        }
    }

    private func download(
        _ name: String,
        bytes: Int
    ) -> DownloadedAttachment {
        DownloadedAttachment(
            path: "/tmp/\(name)",
            filename: "\(name).bin",
            mimeType: "application/octet-stream",
            bytes: Data(repeating: 1, count: bytes)
        )
    }
}

private final class TemporaryAttachmentCache: @unchecked Sendable {
    let root: URL
    let directory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "nile-private-cache-test-\(UUID())",
            directoryHint: .isDirectory
        )
        directory = root.appending(
            path: "attachments",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
