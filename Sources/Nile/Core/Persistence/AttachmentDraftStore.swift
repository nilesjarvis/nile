import Foundation

/// Owns the protected attachment file, envelope invariants, and gateway-removal
/// fence. Exact draft and mutation transactions execute in a same-actor
/// extension without introducing another storage or state authority.
actor ProtectedAttachmentDraftStore: AttachmentDraftStoring {
    static let maximumAttachmentBytes = 25 * 1_024 * 1_024

    private let storage: ProtectedFileStorage
    private var removedGatewayIDs: Set<String> = []

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        storage = ProtectedFileStorage(
            fileURL: fileURL ?? ProtectedFileStorage.applicationSupportURL(
                fileName: "attachment-drafts-v1.json",
                fileManager: fileManager
            ),
            fileManager: fileManager,
            excludesFileFromBackup: true
        )
    }

    func permitsGateway(_ gatewayID: String) -> Bool {
        !removedGatewayIDs.contains(gatewayID)
    }

    func retireGatewayID(_ gatewayID: String) {
        removedGatewayIDs.insert(gatewayID)
    }

    func loadEnvelope() throws -> AttachmentDraftEnvelope {
        let envelope: AttachmentDraftEnvelope
        do {
            guard let stored = try storage.decode(
                AttachmentDraftEnvelope.self
            ) else {
                return AttachmentDraftEnvelope()
            }
            envelope = stored
        } catch is DecodingError {
            throw AttachmentDraftStoreError.malformedData
        } catch {
            throw AttachmentDraftStoreError.storageAccess
        }
        guard envelope.version == AttachmentDraftEnvelope.currentVersion else {
            throw AttachmentDraftStoreError.unsupportedVersion(envelope.version)
        }
        try Self.validate(envelope)
        return envelope
    }

    func writeOrRemove(_ envelope: AttachmentDraftEnvelope) throws {
        if envelope.drafts.isEmpty && envelope.markers.isEmpty {
            try removeFile()
        } else {
            try write(envelope)
        }
    }

    func write(_ envelope: AttachmentDraftEnvelope) throws {
        do {
            try storage.write(envelope)
        } catch {
            throw AttachmentDraftStoreError.storageAccess
        }
    }

    private func removeFile() throws {
        do {
            try storage.remove()
        } catch {
            throw AttachmentDraftStoreError.storageAccess
        }
    }

    static func apply(
        _ draft: PersistedAttachmentDraft,
        to drafts: inout [PersistedAttachmentDraft]
    ) -> Bool {
        if let index = drafts.firstIndex(where: { $0.owner == draft.owner }) {
            let current = drafts[index]
            if current.revision > draft.revision {
                return false
            }
            if current.revision == draft.revision {
                return current == draft
            }
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
        return true
    }

    static func validate(_ envelope: AttachmentDraftEnvelope) throws {
        var owners: Set<ComposerDraftOwner> = []
        for draft in envelope.drafts {
            try validate(draft)
            guard owners.insert(draft.owner).inserted else {
                throw AttachmentDraftStoreError.malformedData
            }
        }
        var markerIDs: Set<String> = []
        for marker in envelope.markers {
            try validate(marker)
            guard markerIDs.insert(marker.id).inserted else {
                throw AttachmentDraftStoreError.malformedData
            }
        }
    }

    static func validate(_ draft: PersistedAttachmentDraft) throws {
        guard !draft.gatewayID.isBlank,
              !draft.storedSessionID.isBlank,
              draft.revision > 0,
              draft.updatedAtMilliseconds >= 0 else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        try validate(draft.attachments)
    }

    static func validate(_ marker: AttachmentMutationMarker) throws {
        guard !marker.id.isBlank,
              !marker.gatewayID.isBlank,
              !marker.storedSessionID.isBlank,
              !marker.liveSessionID.isBlank,
              !marker.userEntryID.isBlank,
              marker.userMessagesBefore >= 0,
              !marker.attachments.isEmpty else {
            throw AttachmentDraftStoreError.invalidRecord
        }
        try validate(marker.attachments)
    }

    static func validate(_ attachments: [PendingAttachment]) throws {
        var ids: Set<String> = []
        for attachment in attachments {
            guard !attachment.id.isBlank,
                  !attachment.filename.isBlank,
                  !attachment.data.isEmpty,
                  attachment.fileExtension.hasPrefix("."),
                  !attachment.fileExtension.isBlank,
                  ids.insert(attachment.id).inserted else {
                throw AttachmentDraftStoreError.invalidRecord
            }
            guard attachment.data.count <= maximumAttachmentBytes else {
                throw AttachmentDraftStoreError.attachmentTooLarge
            }
        }
    }
}

struct AttachmentDraftEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var drafts: [PersistedAttachmentDraft]
    var markers: [AttachmentMutationMarker]

    init(
        version: Int = Self.currentVersion,
        drafts: [PersistedAttachmentDraft] = [],
        markers: [AttachmentMutationMarker] = []
    ) {
        self.version = version
        self.drafts = drafts
        self.markers = markers
    }
}
