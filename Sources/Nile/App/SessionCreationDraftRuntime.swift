import Foundation

/// Owns the protected draft handoff performed when a missing session is
/// replaced by a newly created Hermes session.
///
/// The runtime composes the existing text, attachment, and in-memory composer
/// capabilities into one fail-closed transaction. It does not create sessions,
/// publish UI state, or consume stream events; `SessionListModel` retains those
/// responsibilities and supplies the request-generation commit fence.
@MainActor
final class SessionCreationDraftRuntime {
    typealias CommitGuard = @MainActor @Sendable () -> Bool

    struct Plan: Equatable, Sendable {
        let sourceOwner: ComposerDraftOwner
        let composer: String
        let attachments: [PendingAttachment]
        let markers: [AttachmentMutationMarker]
        let recoveredFromInterruptedMutation: Bool

        var requiresPhotoPromotion: Bool {
            markers.isEmpty && !attachments.isEmpty
        }
    }

    private let composerRuntime: SessionComposerRuntime
    private let draftPersistenceRuntime: SessionDraftPersistenceRuntime
    private let attachmentPersistenceRuntime:
        SessionAttachmentPersistenceRuntime

    init(
        composerRuntime: SessionComposerRuntime,
        draftPersistenceRuntime: SessionDraftPersistenceRuntime,
        attachmentPersistenceRuntime: SessionAttachmentPersistenceRuntime
    ) {
        self.composerRuntime = composerRuntime
        self.draftPersistenceRuntime = draftPersistenceRuntime
        self.attachmentPersistenceRuntime = attachmentPersistenceRuntime
    }

    func capture(
        owner: ComposerDraftOwner,
        composer: String,
        attachments: [PendingAttachment]
    ) -> Plan? {
        let markers = attachmentPersistenceRuntime.markers(
            for: owner,
            stage: .draftRecovered
        )
        guard !markers.isEmpty
                || !composer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                || !attachments.isEmpty else {
            return nil
        }
        return Plan(
            sourceOwner: owner,
            composer: composer,
            attachments: attachments,
            markers: markers,
            recoveredFromInterruptedMutation: !markers.isEmpty
        )
    }

    /// Gives an ordinary photo draft durable mutation-marker authority before
    /// the remote create call. Returning `nil` means no session may be created.
    func promoteOrdinaryPhotoDraft(_ plan: Plan) async -> Plan? {
        guard plan.requiresPhotoPromotion else {
            return plan
        }
        let marker = AttachmentMutationMarker(
            id: "recovered-create-\(UUID().uuidString)",
            gatewayID: plan.sourceOwner.gatewayID,
            storedSessionID: plan.sourceOwner.storedSessionID,
            liveSessionID: "unavailable-\(UUID().uuidString)",
            input: plan.composer,
            attachments: plan.attachments,
            userEntryID: "recovered-user-\(UUID().uuidString)",
            userMessagesBefore: 0,
            stage: .uploadPending
        )
        guard await attachmentPersistenceRuntime.promoteOrdinaryDraft(
            marker: marker,
            attachments: plan.attachments
        ) else {
            return nil
        }
        let promotedMarkers = attachmentPersistenceRuntime.markers(
            for: plan.sourceOwner,
            stage: .draftRecovered
        )
        guard !promotedMarkers.isEmpty else {
            return nil
        }
        return Plan(
            sourceOwner: plan.sourceOwner,
            composer: plan.composer,
            attachments: plan.attachments,
            markers: promotedMarkers,
            recoveredFromInterruptedMutation:
                plan.recoveredFromInterruptedMutation
        )
    }

    /// Moves protected text, recovered markers, and ordinary attachment records
    /// to the created owner. In-memory composer ownership advances only after
    /// both protected stores accept their exact-CAS updates.
    func migrate(
        _ plan: Plan,
        to created: LiveSession,
        commitGuard: @escaping CommitGuard
    ) async -> Bool {
        guard let storedSessionID = created.storedID else {
            return false
        }
        let targetOwner = ComposerDraftOwner(
            gatewayID: plan.sourceOwner.gatewayID,
            storedSessionID: storedSessionID
        )
        guard targetOwner != plan.sourceOwner else {
            return false
        }

        let snapshotAttachments = Dictionary(
            uniqueKeysWithValues: plan.attachments.map { ($0.id, $0) }
        )
        var migrations: [AttachmentMutationMigration] = []
        for marker in plan.markers {
            guard attachmentPersistenceRuntime.containsMarker(marker) else {
                return false
            }
            var recovered: [PendingAttachment] = []
            for attachment in marker.attachments {
                guard let snapshot = snapshotAttachments[attachment.id] else {
                    return false
                }
                recovered.append(snapshot)
            }
            migrations.append(
                AttachmentMutationMigration(
                    expected: marker,
                    replacement: marker.retargeting(
                        storedSessionID: storedSessionID,
                        liveSessionID: created.liveID,
                        input: plan.composer,
                        attachments: recovered
                    )
                )
            )
        }

        let movedComposer = await draftPersistenceRuntime
            .migrateRecoveredDraft(
                from: plan.sourceOwner,
                to: targetOwner,
                // Recovered markers remain authoritative for their prompt. A
                // text-only ordinary draft has no marker and moves directly in
                // this exact-owner protected-file CAS.
                targetText: plan.markers.isEmpty ? plan.composer : ""
            )
        guard movedComposer, commitGuard() else {
            return false
        }

        let markerAttachmentIDs = Set(
            plan.markers.flatMap { $0.attachments.map(\.id) }
        )
        let ordinaryAttachments = plan.attachments.filter {
            !markerAttachmentIDs.contains($0.id)
        }
        let movedAttachments = await attachmentPersistenceRuntime
            .migrateRecoveredDraft(
                mutations: migrations,
                from: plan.sourceOwner,
                to: targetOwner,
                ordinaryAttachments: ordinaryAttachments,
                visibleAttachments: plan.attachments,
                commitGuard: commitGuard
            )
        guard movedAttachments, commitGuard() else {
            return false
        }

        composerRuntime.migrate(
            from: plan.sourceOwner,
            to: targetOwner,
            text: plan.composer
        )
        return true
    }
}
