import Foundation

/// One implementation of Nile's protected, backup-excluded atomic-file
/// contract. Domain stores retain ownership of their wire formats, validation,
/// and user-facing errors while sharing the security-sensitive file mechanics.
struct ProtectedFileStorage {
    private let fileURL: URL
    private let fileManager: FileManager
    private let excludesFileFromBackup: Bool

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        excludesFileFromBackup: Bool = false
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.excludesFileFromBackup = excludesFileFromBackup
    }

    static func applicationSupportURL(
        fileName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appending(path: "Nile", directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    func read() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func decode<Value: Decodable>(
        _ type: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value? {
        guard let data = try read() else {
            return nil
        }
        return try decoder.decode(type, from: data)
    }

    func write(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        let protection = FileProtectionType
            .completeUntilFirstUserAuthentication
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        try fileManager.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: directory.path
        )
        try excludeFromBackup(directory)
        try data.write(
            to: fileURL,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication,
            ]
        )
        if excludesFileFromBackup {
            try excludeFromBackup(fileURL)
        }
    }

    func write<Value: Encodable>(
        _ value: Value,
        encoder: JSONEncoder = .protectedPersistence
    ) throws {
        try write(encoder.encode(value))
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }
}

extension JSONEncoder {
    static var protectedPersistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Main-actor FIFO used by protected stores whose UI mutations must retain
/// enqueue order while their actor-backed writes suspend.
@MainActor
final class OrderedPersistenceQueue {
    private var tail: Task<Void, Never>?

    func enqueue(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        let predecessor = tail
        tail = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            await operation()
        }
    }
}
