import XCTest
@testable import Nile

@MainActor
final class SessionMediaRuntimeTests: XCTestCase {
    func testOpenUsesFullBoundAndPrivateCache() async {
        let downloaded = mediaDownload(
            path: "/tmp/report.pdf",
            filename: "report.pdf",
            mimeType: "application/pdf"
        )
        let repository = ImmediateMediaRepository(downloads: [downloaded])
        let cache = ImmediateMediaCache()
        let runtime = SessionMediaRuntime(
            repository: repository,
            cache: cache
        )
        let owner = mediaOwner()
        let errors = MediaErrorCapture()

        runtime.open(
            path: downloaded.path,
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onError: { errors.values.append($0) }
        )

        await eventually { runtime.openedAttachment != nil }
        let calls = await repository.calls
        let prepared = await cache.prepared
        XCTAssertEqual(
            calls,
            ["\(downloaded.path):\(SessionMediaRuntime.viewerMaximumBytes)"]
        )
        XCTAssertEqual(prepared, [downloaded])
        XCTAssertEqual(runtime.openedAttachment?.filename, "report.pdf")
        XCTAssertFalse(runtime.isOpeningAttachment)
        XCTAssertEqual(errors.values.count, 1)
        XCTAssertNil(errors.values[0])
    }

    func testResetPreventsLateOpenFromReplacingNewViewer() async {
        let repository = ImmediateMediaRepository(
            downloads: [
                mediaDownload(path: "/tmp/old.pdf", filename: "old.pdf"),
                mediaDownload(path: "/tmp/new.pdf", filename: "new.pdf"),
            ]
        )
        let cache = BlockingFirstMediaCache()
        let runtime = SessionMediaRuntime(
            repository: repository,
            cache: cache
        )
        let ownerOne = mediaOwner(displayGeneration: 1)
        let ownerTwo = mediaOwner(displayGeneration: 2)
        let currentOwner = MediaOwnerCapture(ownerOne)

        runtime.open(
            path: "/tmp/old.pdf",
            owner: ownerOne,
            isCurrentOwner: { $0 == currentOwner.value },
            onError: { _ in }
        )
        await eventuallyAsync { await cache.callCount == 1 }

        currentOwner.value = ownerTwo
        runtime.reset()
        runtime.open(
            path: "/tmp/new.pdf",
            owner: ownerTwo,
            isCurrentOwner: { $0 == currentOwner.value },
            onError: { _ in }
        )
        await eventually {
            runtime.openedAttachment?.filename == "prepared-2-new.pdf"
        }

        await cache.releaseFirst()
        await eventuallyAsync { await cache.completedCount == 2 }
        XCTAssertEqual(
            runtime.openedAttachment?.filename,
            "prepared-2-new.pdf"
        )
        XCTAssertFalse(runtime.isOpeningAttachment)
    }

    func testPreviewUsesSmallBoundAndPublishesImageUpdate() async {
        let downloaded = mediaDownload(
            path: "/tmp/result.png",
            filename: "result.png",
            mimeType: "image/png",
            bytes: Data("image".utf8)
        )
        let repository = ImmediateMediaRepository(downloads: [downloaded])
        let runtime = SessionMediaRuntime(
            repository: repository,
            cache: ImmediateMediaCache()
        )
        let owner = mediaOwner()
        let updates = MediaPreviewCapture()
        let transcript = mediaTranscript(paths: [downloaded.path])

        _ = runtime.reconcilePreviews(
            in: transcript,
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onPreview: { updates.values.append($0) },
            onNeedsReconcile: {}
        )

        await eventually { updates.values.count == 1 }
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            ["\(downloaded.path):\(SessionMediaRuntime.previewMaximumBytes)"]
        )
        XCTAssertEqual(updates.values[0].owner, owner)
        XCTAssertEqual(updates.values[0].messageID, "message-0")
        XCTAssertEqual(updates.values[0].attachmentIndex, 0)
        XCTAssertEqual(
            updates.values[0].attachment.previewBase64,
            downloaded.bytes.base64EncodedString()
        )
        XCTAssertEqual(updates.values[0].attachment.mimeType, "image/png")
    }

    func testResetSuppressesLatePreviewUpdate() async {
        let repository = BlockingMediaRepository(
            download: mediaDownload(
                path: "/tmp/result.png",
                filename: "result.png",
                mimeType: "image/png"
            )
        )
        let runtime = SessionMediaRuntime(
            repository: repository,
            cache: ImmediateMediaCache()
        )
        let owner = mediaOwner()
        let updates = MediaPreviewCapture()
        let reconciliations = MediaReconcileCapture()

        _ = runtime.reconcilePreviews(
            in: mediaTranscript(paths: ["/tmp/result.png"]),
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onPreview: { updates.values.append($0) },
            onNeedsReconcile: { reconciliations.count += 1 }
        )
        await eventuallyAsync { await repository.started }

        runtime.reset()
        await repository.release()
        await Task.yield()

        XCTAssertTrue(updates.values.isEmpty)
        XCTAssertEqual(reconciliations.count, 0)
    }

    func testPreviewHydrationStartsAtMostTwoDownloads() async {
        let repository = ConcurrentBlockingMediaRepository()
        let runtime = SessionMediaRuntime(
            repository: repository,
            cache: ImmediateMediaCache()
        )
        let owner = mediaOwner()

        _ = runtime.reconcilePreviews(
            in: mediaTranscript(
                paths: [
                    "/tmp/one.png",
                    "/tmp/two.png",
                    "/tmp/three.png",
                ]
            ),
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onPreview: { _ in },
            onNeedsReconcile: {}
        )

        await eventuallyAsync { await repository.startedCount == 2 }
        let maximumActive = await repository.maximumActiveCount
        XCTAssertEqual(
            maximumActive,
            SessionMediaRuntime.concurrentPreviewCount
        )
        runtime.reset()
        await repository.releaseAll()
        await eventuallyAsync { await repository.activeCount == 0 }
    }

    func testPreviewProjectionRetainsOnlyLatestEightImages() {
        let downloads = (0..<9).map {
            mediaDownload(
                path: "/tmp/image-\($0).png",
                filename: "image-\($0).png",
                mimeType: "image/png"
            )
        }
        let runtime = SessionMediaRuntime(
            repository: ImmediateMediaRepository(downloads: downloads),
            cache: ImmediateMediaCache()
        )
        let owner = mediaOwner()
        let transcript = mediaTranscript(
            paths: downloads.map(\.path),
            preview: "retained"
        )

        let projected = runtime.reconcilePreviews(
            in: transcript,
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onPreview: { _ in },
            onNeedsReconcile: {}
        )
        let previews = projected.compactMap { entry -> String? in
            guard case let .message(message) = entry else {
                return nil
            }
            return message.attachments.first?.previewBase64
        }

        XCTAssertEqual(previews.count, 8)
        guard case let .message(first) = projected[0] else {
            return XCTFail("Expected a message entry")
        }
        XCTAssertNil(first.attachments[0].previewBase64)
    }

    private func mediaOwner(
        displayGeneration: Int = 1
    ) -> SessionMediaRuntime.Owner {
        SessionMediaRuntime.Owner(
            gatewayGeneration: 1,
            displayGeneration: displayGeneration,
            gatewayID: "gateway-one",
            storedSessionID: "session-one"
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class MediaErrorCapture {
    var values: [String?] = []
}

@MainActor
private final class MediaPreviewCapture {
    var values: [SessionMediaRuntime.PreviewUpdate] = []
}

@MainActor
private final class MediaReconcileCapture {
    var count = 0
}

@MainActor
private final class MediaOwnerCapture {
    var value: SessionMediaRuntime.Owner

    init(_ value: SessionMediaRuntime.Owner) {
        self.value = value
    }
}

private actor ImmediateMediaRepository: HermesAttachmentReading {
    private var downloads: [String: DownloadedAttachment]
    private(set) var calls: [String] = []

    init(downloads: [DownloadedAttachment]) {
        self.downloads = Dictionary(
            uniqueKeysWithValues: downloads.map { ($0.path, $0) }
        )
    }

    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) throws -> DownloadedAttachment {
        calls.append("\(path):\(maxBytes)")
        guard let download = downloads[path] else {
            throw HermesError("Missing media fixture", retryable: false)
        }
        return download
    }
}

private actor BlockingMediaRepository: HermesAttachmentReading {
    private let download: DownloadedAttachment
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    init(download: DownloadedAttachment) {
        self.download = download
    }

    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async -> DownloadedAttachment {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return download
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ConcurrentBlockingMediaRepository: HermesAttachmentReading {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var startedCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0

    func downloadAttachment(
        path: String,
        maxBytes: Int64
    ) async -> DownloadedAttachment {
        startedCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        activeCount -= 1
        return mediaDownload(
            path: path,
            filename: URL(filePath: path).lastPathComponent,
            mimeType: "image/png"
        )
    }

    func releaseAll() {
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor ImmediateMediaCache: AttachmentCaching {
    private(set) var prepared: [DownloadedAttachment] = []

    func prepare(_ attachment: DownloadedAttachment) -> CachedAttachment {
        prepared.append(attachment)
        return mediaCachedAttachment(filename: attachment.filename)
    }
}

private actor BlockingFirstMediaCache: AttachmentCaching {
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    private(set) var completedCount = 0

    func prepare(
        _ attachment: DownloadedAttachment
    ) async -> CachedAttachment {
        callCount += 1
        let index = callCount
        if index == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        completedCount += 1
        return mediaCachedAttachment(
            filename: "prepared-\(index)-\(attachment.filename)"
        )
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private func mediaDownload(
    path: String,
    filename: String,
    mimeType: String = "application/pdf",
    bytes: Data = Data("payload".utf8)
) -> DownloadedAttachment {
    DownloadedAttachment(
        path: path,
        filename: filename,
        mimeType: mimeType,
        bytes: bytes
    )
}

private func mediaCachedAttachment(filename: String) -> CachedAttachment {
    CachedAttachment(
        id: UUID(),
        url: FileManager.default.temporaryDirectory.appending(path: filename),
        filename: filename,
        mimeType: "application/octet-stream"
    )
}

private func mediaTranscript(
    paths: [String],
    preview: String? = nil
) -> [TranscriptEntry] {
    paths.enumerated().map { index, path in
        .message(
            TranscriptMessage(
                id: "message-\(index)",
                role: .assistant,
                content: "",
                attachments: [
                    MessageAttachment(
                        path: path,
                        filename: URL(filePath: path).lastPathComponent,
                        kind: .image,
                        previewBase64: preview,
                        mimeType: "image/png"
                    ),
                ]
            )
        )
    }
}
