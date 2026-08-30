import Foundation

struct PendingAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let filename: String
    let data: Data
    let fileExtension: String

    init(
        id: String = "local-image-\(UUID().uuidString)",
        filename: String,
        data: Data,
        fileExtension: String = ".jpg"
    ) {
        self.id = id
        self.filename = filename
        self.data = data
        self.fileExtension = fileExtension
    }

    var base64: String {
        data.base64EncodedString()
    }
}

struct PersistedAttachmentDraft: Codable, Equatable, Sendable {
    let gatewayID: String
    let storedSessionID: String
    let revision: Int64
    let attachments: [PendingAttachment]
    let updatedAtMilliseconds: Int64

    var owner: ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }
}

enum AttachmentMutationStage: String, Codable, Equatable, Sendable {
    case uploadPending
    case promptPending
    case draftRecovered
    case quarantineOnly
}

/// Durable authority written before Hermes can mutate a runtime's image queue.
///
/// The marker deliberately keeps the complete local draft until delivery is
/// proven. Server paths are not persisted: a path response can race process
/// death, so only runtime disappearance or durable user-history evidence is
/// strong enough to release an uncertain marker after restoration.
struct AttachmentMutationMarker: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let gatewayID: String
    let storedSessionID: String
    let liveSessionID: String
    let input: String
    let attachments: [PendingAttachment]
    let userEntryID: String
    let userMessagesBefore: Int
    let stage: AttachmentMutationStage

    var owner: ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
    }

    func advancing(to stage: AttachmentMutationStage) -> Self {
        Self(
            id: id,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID,
            input: input,
            attachments: attachments,
            userEntryID: userEntryID,
            userMessagesBefore: userMessagesBefore,
            stage: stage
        )
    }

    func retargeting(
        storedSessionID: String,
        liveSessionID: String,
        input: String,
        attachments: [PendingAttachment]
    ) -> Self {
        Self(
            id: id,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID,
            input: input,
            attachments: attachments,
            userEntryID: userEntryID,
            userMessagesBefore: userMessagesBefore,
            stage: stage
        )
    }
}

struct AttachmentRecoverySnapshot: Equatable, Sendable {
    let drafts: [PersistedAttachmentDraft]
    let markers: [AttachmentMutationMarker]
}

struct AttachmentMutationMigration: Equatable, Sendable {
    let expected: AttachmentMutationMarker
    let replacement: AttachmentMutationMarker
}

struct AttachmentDraftMigrationChange: Equatable, Sendable {
    let owner: ComposerDraftOwner
    let expected: PersistedAttachmentDraft?
    let replacement: PersistedAttachmentDraft
}

protocol AttachmentDraftStoring: Sendable {
    func load() async throws -> AttachmentRecoverySnapshot

    func updateDraft(_ draft: PersistedAttachmentDraft) async throws -> Bool

    /// Atomically hands ordinary photo-draft ownership to a mutation marker.
    func beginMutation(
        _ marker: AttachmentMutationMarker,
        replacingMarkerIDs: Set<String>,
        expectedDraft: PersistedAttachmentDraft?,
        tombstone: PersistedAttachmentDraft
    ) async throws -> Bool

    func advanceMutation(
        from expected: AttachmentMutationMarker,
        to replacement: AttachmentMutationMarker
    ) async throws -> Bool

    /// Atomically restores a failed mutation to ordinary photo-draft ownership.
    func recoverMutation(
        _ expected: AttachmentMutationMarker,
        as draft: PersistedAttachmentDraft
    ) async throws -> Bool

    /// Retargets recovered mutation authority and its ordinary photo records in
    /// one protected-file CAS. The commit guard prevents an obsolete display
    /// request from publishing into a gateway that is no longer visible.
    func migrateRecoveredDraft(
        mutations: [AttachmentMutationMigration],
        draftChanges: [AttachmentDraftMigrationChange],
        commitGuard: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> Bool

    func clearMutation(_ expected: AttachmentMutationMarker) async throws -> Bool
    func removeGateway(id: String) async throws
}

enum AttachmentDraftStoreError: LocalizedError, Equatable, Sendable {
    case malformedData
    case unsupportedVersion(Int)
    case invalidRecord
    case attachmentTooLarge
    case storageAccess

    var errorDescription: String? {
        switch self {
        case .malformedData:
            "Saved photo drafts are damaged."
        case let .unsupportedVersion(version):
            "Saved photo drafts use unsupported version \(version)."
        case .invalidRecord:
            "A saved photo draft is invalid."
        case .attachmentTooLarge:
            "A saved photo exceeds Nile's protected draft limit."
        case .storageAccess:
            "Nile could not access protected photo drafts."
        }
    }
}
