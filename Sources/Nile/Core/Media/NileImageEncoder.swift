import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

private final class TranscriptImageCacheEntry: NSObject {
    let image: UIImage?

    init(image: UIImage?) {
        self.image = image
    }
}

final class TranscriptImageCache: @unchecked Sendable {
    static let shared = TranscriptImageCache()

    private let cache = NSCache<NSString, TranscriptImageCacheEntry>()
    private let lock = NSLock()
    private var unlockedDecodeCount = 0

    init(countLimit: Int = 24, totalCostLimit: Int = 48 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    var decodeCount: Int {
        lock.withLock { unlockedDecodeCount }
    }

    func image(forBase64 base64: String) -> UIImage? {
        let key = base64 as NSString
        if let entry = cache.object(forKey: key) {
            return entry.image
        }
        let image = Data(base64Encoded: base64).flatMap(UIImage.init(data:))
        lock.withLock { unlockedDecodeCount &+= 1 }
        let cost = image?.cgImage.map {
            $0.bytesPerRow * $0.height
        } ?? min(base64.utf8.count, 64 * 1_024)
        cache.setObject(
            TranscriptImageCacheEntry(image: image),
            forKey: key,
            cost: cost
        )
        return image
    }
}

enum NileImageEncoder {
    static let maximumEdge = 1_568
    static let jpegQuality = 0.85

    /// Matches Android's upload preparation: orient, downscale, and encode JPEG.
    static func encode(_ sourceData: Data) -> PendingAttachment? {
        guard let source = CGImageSourceCreateWithData(
            sourceData as CFData,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [
                kCGImageDestinationLossyCompressionQuality: jpegQuality,
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        let jpeg = output as Data
        guard !jpeg.isEmpty,
              jpeg.count <= ProtectedAttachmentDraftStore
                .maximumAttachmentBytes else {
            return nil
        }
        return PendingAttachment(
            filename: "photo_\(jpeg.count).jpg",
            data: jpeg,
            fileExtension: ".jpg"
        )
    }
}
