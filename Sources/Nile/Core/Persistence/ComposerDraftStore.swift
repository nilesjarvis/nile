import Foundation

struct ComposerDraftOwner: Hashable, Sendable {
    let gatewayID: String
    let storedSessionID: String
}

struct PersistedComposerDraft: Codable, Equatable, Sendable {
    let gatewayID: String
    let storedSessionID: String
    let revision: Int64
    let text: String
    let updatedAtMilliseconds: Int64

    var owner: ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }
}

struct ComposerDraftMigrationChange: Equatable, Sendable {
    let owner: ComposerDraftOwner
    let expected: PersistedComposerDraft?
    let replacement: PersistedComposerDraft
}

protocol ComposerDraftStoring: Sendable {
    func load() async throws -> [PersistedComposerDraft]

    /// Applies a newer revision, or the exact same revision idempotently.
    /// A stale or conflicting revision returns false without changing storage.
    func update(_ draft: PersistedComposerDraft) async throws -> Bool

    /// Applies every exact-owner comparison and replacement in one protected
    /// file commit. This is used when a recovered draft changes session owner.
    func migrate(
        _ changes: [ComposerDraftMigrationChange]
    ) async throws -> Bool

    func removeGateway(id: String) async throws
}

enum ComposerDraftStoreError: LocalizedError, Equatable, Sendable {
    case malformedData
    case unsupportedVersion(Int)
    case invalidRecord
    case storageAccess

    var errorDescription: String? {
        switch self {
        case .malformedData:
            "Saved composer drafts are damaged."
        case let .unsupportedVersion(version):
            "Saved composer drafts use unsupported version \(version)."
        case .invalidRecord:
            "A saved composer draft is invalid."
        case .storageAccess:
            "Nile could not access protected composer drafts."
        }
    }
}

actor ProtectedComposerDraftStore: ComposerDraftStoring {
    private let storage: ProtectedFileStorage
    private var removedGatewayIDs: Set<String> = []

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        storage = ProtectedFileStorage(
            fileURL: fileURL ?? ProtectedFileStorage.applicationSupportURL(
                fileName: "composer-drafts-v1.json",
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    func load() throws -> [PersistedComposerDraft] {
        try loadEnvelope().drafts
    }

    func update(_ draft: PersistedComposerDraft) throws -> Bool {
        try Self.validate(draft)
        guard !removedGatewayIDs.contains(draft.gatewayID) else {
            return false
        }
        var envelope = try loadEnvelope()
        if let index = envelope.drafts.firstIndex(where: {
            $0.gatewayID == draft.gatewayID
                && $0.storedSessionID == draft.storedSessionID
        }) {
            let current = envelope.drafts[index]
            if current.revision > draft.revision {
                return false
            }
            if current.revision == draft.revision {
                return current == draft
            }
            envelope.drafts[index] = draft
        } else {
            envelope.drafts.append(draft)
        }
        try write(envelope)
        return true
    }

    func migrate(_ changes: [ComposerDraftMigrationChange]) throws -> Bool {
        guard !changes.isEmpty else {
            return true
        }
        var owners: Set<ComposerDraftOwner> = []
        for change in changes {
            guard owners.insert(change.owner).inserted,
                  change.replacement.owner == change.owner else {
                throw ComposerDraftStoreError.invalidRecord
            }
            try Self.validate(change.replacement)
            if let expected = change.expected {
                guard expected.owner == change.owner else {
                    throw ComposerDraftStoreError.invalidRecord
                }
                try Self.validate(expected)
            }
            guard !removedGatewayIDs.contains(change.owner.gatewayID) else {
                return false
            }
        }
        guard Set(changes.map(\.owner.gatewayID)).count == 1 else {
            throw ComposerDraftStoreError.invalidRecord
        }

        var envelope = try loadEnvelope()
        for change in changes {
            let current = envelope.drafts.first {
                $0.owner == change.owner
            }
            guard current == change.expected else {
                return false
            }
        }
        for change in changes {
            if let index = envelope.drafts.firstIndex(where: {
                $0.owner == change.owner
            }) {
                envelope.drafts[index] = change.replacement
            } else {
                envelope.drafts.append(change.replacement)
            }
        }
        try write(envelope)
        return true
    }

    func removeGateway(id: String) throws {
        removedGatewayIDs.insert(id)
        var envelope = try loadEnvelope()
        let originalCount = envelope.drafts.count
        envelope.drafts.removeAll { $0.gatewayID == id }
        guard envelope.drafts.count != originalCount else {
            return
        }
        if envelope.drafts.isEmpty {
            try removeFile()
        } else {
            try write(envelope)
        }
    }

    private func loadEnvelope() throws -> ComposerDraftEnvelope {
        let envelope: ComposerDraftEnvelope
        do {
            guard let stored = try storage.decode(
                ComposerDraftEnvelope.self
            ) else {
                return ComposerDraftEnvelope()
            }
            envelope = stored
        } catch is DecodingError {
            throw ComposerDraftStoreError.malformedData
        } catch {
            throw ComposerDraftStoreError.storageAccess
        }
        guard envelope.version == ComposerDraftEnvelope.currentVersion else {
            throw ComposerDraftStoreError.unsupportedVersion(envelope.version)
        }
        do {
            try Self.validate(envelope.drafts)
        } catch let error as ComposerDraftStoreError {
            throw error
        } catch {
            throw ComposerDraftStoreError.malformedData
        }
        return envelope
    }

    private func write(_ envelope: ComposerDraftEnvelope) throws {
        do {
            try storage.write(envelope)
        } catch {
            throw ComposerDraftStoreError.storageAccess
        }
    }

    private func removeFile() throws {
        do {
            try storage.remove()
        } catch {
            throw ComposerDraftStoreError.storageAccess
        }
    }

    private static func validate(_ drafts: [PersistedComposerDraft]) throws {
        var owners: Set<ComposerDraftOwner> = []
        for draft in drafts {
            try validate(draft)
            guard owners.insert(draft.owner).inserted else {
                throw ComposerDraftStoreError.malformedData
            }
        }
    }

    private static func validate(_ draft: PersistedComposerDraft) throws {
        guard !draft.gatewayID
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                  .isEmpty,
              !draft.storedSessionID
                  .trimmingCharacters(in: .whitespacesAndNewlines)
                  .isEmpty,
              draft.revision > 0,
              draft.updatedAtMilliseconds >= 0 else {
            throw ComposerDraftStoreError.invalidRecord
        }
    }
}

private struct ComposerDraftEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var drafts: [PersistedComposerDraft]

    init(
        version: Int = Self.currentVersion,
        drafts: [PersistedComposerDraft] = []
    ) {
        self.version = version
        self.drafts = drafts
    }
}
