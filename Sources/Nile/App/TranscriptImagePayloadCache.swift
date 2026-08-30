struct TranscriptImagePayloadCache: Sendable {
    private let maximumEntryCount: Int
    private let maximumBase64CharacterCount: Int
    private var imagesByPath: [String: String] = [:]
    private var pathsByRecency: [String] = []
    private var base64CharacterCount = 0

    init(
        maximumEntryCount: Int = 8,
        maximumBase64CharacterCount: Int = 8 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = max(0, maximumEntryCount)
        self.maximumBase64CharacterCount = max(
            0,
            maximumBase64CharacterCount
        )
    }

    var images: [String: String] {
        imagesByPath
    }

    mutating func remember(path: String, base64: String) {
        if let previous = imagesByPath.removeValue(forKey: path) {
            base64CharacterCount -= previous.count
            pathsByRecency.removeAll { $0 == path }
        }
        guard base64.count <= maximumBase64CharacterCount else {
            return
        }
        imagesByPath[path] = base64
        pathsByRecency.append(path)
        base64CharacterCount += base64.count
        evictOldestImagesIfNeeded()
    }

    mutating func removeAll() {
        imagesByPath.removeAll()
        pathsByRecency.removeAll()
        base64CharacterCount = 0
    }

    private mutating func evictOldestImagesIfNeeded() {
        while !pathsByRecency.isEmpty,
              pathsByRecency.count > maximumEntryCount
                || base64CharacterCount > maximumBase64CharacterCount {
            let oldestPath = pathsByRecency.removeFirst()
            if let removed = imagesByPath.removeValue(forKey: oldestPath) {
                base64CharacterCount -= removed.count
            }
        }
    }
}
