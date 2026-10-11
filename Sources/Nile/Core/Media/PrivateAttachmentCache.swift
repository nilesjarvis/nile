import Foundation

struct CachedAttachment: Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let filename: String
    let mimeType: String
}

protocol AttachmentCaching: Sendable {
    func prepare(_ attachment: DownloadedAttachment) async throws
        -> CachedAttachment
}

protocol AttachmentCacheClearing: Sendable {
    func removeAll() async throws
}

enum AttachmentCacheError: LocalizedError, Equatable, Sendable {
    case attachmentTooLarge
    case storageAccess
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .attachmentTooLarge:
            "Attachment exceeds the private viewer cache limit"
        case .storageAccess:
            "Nile could not prepare the attachment for viewing"
        case .cleanupFailed:
            "Nile could not erase downloaded attachments. Try again."
        }
    }
}

actor PrivateAttachmentCache: AttachmentCaching, AttachmentCacheClearing {
    private let directory: URL
    private let fileManager: FileManager
    private let maximumEntries: Int
    private let maximumBytes: Int64

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        maximumEntries: Int = 12,
        maximumBytes: Int64 = 96 * 1_024 * 1_024
    ) {
        precondition(maximumEntries > 0)
        precondition(maximumBytes > 0)
        self.fileManager = fileManager
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
        let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.directory = directory ?? caches
            .appending(path: "Nile", directoryHint: .isDirectory)
            .appending(
                path: "hermes-attachments",
                directoryHint: .isDirectory
            )
    }

    func prepare(
        _ attachment: DownloadedAttachment
    ) throws -> CachedAttachment {
        try Task.checkCancellation()
        guard Int64(attachment.bytes.count) <= maximumBytes else {
            throw AttachmentCacheError.attachmentTooLarge
        }
        do {
            try ensureDirectory()
            try prune(reserving: Int64(attachment.bytes.count))
            let id = UUID()
            let entry = directory.appending(
                path: "open-\(id.uuidString)",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: entry,
                withIntermediateDirectories: false,
                attributes: [
                    .protectionKey:
                        FileProtectionType
                        .completeUntilFirstUserAuthentication,
                ]
            )
            var entryValues = URLResourceValues()
            entryValues.isExcludedFromBackup = true
            var protectedEntry = entry
            try protectedEntry.setResourceValues(entryValues)

            let safeName = Self.safeFilename(attachment.filename)
            let file = entry.appending(
                path: safeName,
                directoryHint: .notDirectory
            )
            do {
                try attachment.bytes.write(
                    to: file,
                    options: [
                        .atomic,
                        .completeFileProtectionUntilFirstUserAuthentication,
                    ]
                )
                var fileValues = URLResourceValues()
                fileValues.isExcludedFromBackup = true
                var protectedFile = file
                try protectedFile.setResourceValues(fileValues)
            } catch {
                try? fileManager.removeItem(at: entry)
                throw error
            }
            return CachedAttachment(
                id: id,
                url: file,
                filename: safeName,
                mimeType: attachment.mimeType.isBlank
                    ? "application/octet-stream"
                    : attachment.mimeType
            )
        } catch let error as AttachmentCacheError {
            throw error
        } catch {
            throw AttachmentCacheError.storageAccess
        }
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw AttachmentCacheError.cleanupFailed
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        try fileManager.setAttributes(
            [
                .protectionKey:
                    FileProtectionType.completeUntilFirstUserAuthentication,
            ],
            ofItemAtPath: directory.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedDirectory = directory
        try protectedDirectory.setResourceValues(values)
    }

    private func prune(reserving incomingBytes: Int64) throws {
        var entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
            ],
            options: [.skipsHiddenFiles]
        ).map { url in
            CacheEntry(
                url: url,
                modified: (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast,
                bytes: recursiveSize(url)
            )
        }.sorted { $0.modified < $1.modified }
        var currentBytes = entries.reduce(Int64(0)) { $0 + $1.bytes }
        while !entries.isEmpty,
              entries.count + 1 > maximumEntries
                || currentBytes > maximumBytes - incomingBytes {
            let oldest = entries.removeFirst()
            try fileManager.removeItem(at: oldest.url)
            currentBytes = max(0, currentBytes - oldest.bytes)
        }
        guard entries.count + 1 <= maximumEntries,
              currentBytes <= maximumBytes - incomingBytes else {
            throw AttachmentCacheError.storageAccess
        }
    }

    private func recursiveSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .fileSizeKey]
        )
        if values?.isDirectory == true {
            return (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
            ))?.reduce(Int64(0)) {
                $0 + recursiveSize($1)
            } ?? 0
        }
        return Int64(values?.fileSize ?? 0)
    }

    private static func safeFilename(_ filename: String) -> String {
        let leaf = filename.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").last.map(String.init) ?? "attachment"
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._ -")
        )
        let sanitized = leaf.unicodeScalars.map {
            allowed.contains($0) ? String($0) : "_"
        }.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !sanitized.isBlank else {
            return "attachment"
        }
        let maximumLength = 120
        guard sanitized.count > maximumLength else {
            return sanitized
        }
        let pathExtension = (sanitized as NSString).pathExtension
        if !pathExtension.isBlank {
            let suffix = ".\(pathExtension)"
            let availableStemLength = maximumLength - suffix.count
            if availableStemLength > 0 {
                let stem = (sanitized as NSString).deletingPathExtension
                let shortenedStem = String(stem.prefix(availableStemLength))
                    .trimmingCharacters(
                        in: CharacterSet(charactersIn: ". ")
                    )
                if !shortenedStem.isBlank {
                    return shortenedStem + suffix
                }
            }
        }
        return String(sanitized.prefix(maximumLength))
    }
}

private struct CacheEntry {
    let url: URL
    let modified: Date
    let bytes: Int64
}
