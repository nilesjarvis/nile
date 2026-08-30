import Foundation
@testable import Nile

actor AttachmentCacheStub: AttachmentCaching {
    private(set) var prepared: [DownloadedAttachment] = []

    func prepare(
        _ attachment: DownloadedAttachment
    ) -> CachedAttachment {
        prepared.append(attachment)
        return CachedAttachment(
            id: UUID(),
            url: FileManager.default.temporaryDirectory.appending(
                path: attachment.filename
            ),
            filename: attachment.filename,
            mimeType: attachment.mimeType
        )
    }
}

actor BlockingFirstAttachmentCacheStub: AttachmentCaching {
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
        let filename = "prepared-\(index)-\(attachment.filename)"
        return CachedAttachment(
            id: UUID(),
            url: FileManager.default.temporaryDirectory.appending(
                path: filename
            ),
            filename: filename,
            mimeType: attachment.mimeType
        )
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
