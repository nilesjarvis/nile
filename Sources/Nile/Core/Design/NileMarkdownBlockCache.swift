import Foundation

private final class MarkdownBlockBox: NSObject {
    let blocks: [MarkdownBlock]

    init(_ blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

final class MarkdownBlockCache: @unchecked Sendable {
    static let shared = MarkdownBlockCache()

    private let cache = NSCache<NSString, MarkdownBlockBox>()
    private let lock = NSLock()
    private var unlockedParseCount = 0

    init(countLimit: Int = 128, totalCostLimit: Int = 4 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    var parseCount: Int {
        lock.withLock { unlockedParseCount }
    }

    func blocks(for content: String, streaming: Bool) -> [MarkdownBlock] {
        if !streaming, let cached = cache.object(forKey: content as NSString) {
            return cached.blocks
        }
        let blocks = parseMarkdownBlocks(content, streaming: streaming)
        lock.withLock { unlockedParseCount &+= 1 }
        if !streaming {
            cache.setObject(
                MarkdownBlockBox(blocks),
                forKey: content as NSString,
                cost: content.utf8.count
            )
        }
        return blocks
    }
}
