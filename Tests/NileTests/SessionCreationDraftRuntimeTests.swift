import Foundation
import XCTest
@testable import Nile

@MainActor
final class SessionCreationDraftRuntimeTests: XCTestCase {
    func testCapturePreservesRecoveredMarkerAuthority() async throws {
        let owner = makeOwner()
        let attachment = makeAttachment()
        let marker = makeMarker(owner: owner, attachment: attachment)
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            )
        )
        let runtime = makeRuntime(attachmentStore: attachmentStore)
        _ = try await runtime.attachments.restore(
            gatewayID: owner.gatewayID
        )

        let plan = try XCTUnwrap(
            runtime.creation.capture(
                owner: owner,
                composer: "Recovered prompt",
                attachments: [attachment]
            )
        )

        XCTAssertEqual(plan.sourceOwner, owner)
        XCTAssertEqual(plan.composer, "Recovered prompt")
        XCTAssertEqual(plan.attachments, [attachment])
        XCTAssertEqual(plan.markers, [marker])
        XCTAssertTrue(plan.recoveredFromInterruptedMutation)
        XCTAssertFalse(plan.requiresPhotoPromotion)
    }

    func testOrdinaryPhotoPromotionCreatesRecoveredAuthority() async throws {
        let owner = makeOwner()
        let attachment = makeAttachment()
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: owner.gatewayID,
                        storedSessionID: owner.storedSessionID,
                        revision: 1,
                        attachments: [attachment],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: []
            )
        )
        let runtime = makeRuntime(attachmentStore: attachmentStore)
        _ = try await runtime.attachments.restore(
            gatewayID: owner.gatewayID
        )
        let ordinary = try XCTUnwrap(
            runtime.creation.capture(
                owner: owner,
                composer: "Ordinary prompt",
                attachments: [attachment]
            )
        )

        let promotion = await runtime.creation.promoteOrdinaryPhotoDraft(
            ordinary
        )
        let promoted = try XCTUnwrap(promotion)

        XCTAssertEqual(promoted.markers.count, 1)
        XCTAssertEqual(promoted.markers.first?.stage, .draftRecovered)
        XCTAssertEqual(promoted.markers.first?.owner, owner)
        XCTAssertEqual(promoted.markers.first?.input, "Ordinary prompt")
        XCTAssertEqual(promoted.markers.first?.attachments, [attachment])
        XCTAssertFalse(promoted.recoveredFromInterruptedMutation)
        XCTAssertFalse(promoted.requiresPhotoPromotion)
    }

    func testMigrationMovesProtectedAuthorityAndComposerProjection()
        async throws
    {
        let source = makeOwner(storedSessionID: "missing")
        let target = makeOwner(storedSessionID: "created")
        let attachment = makeAttachment()
        let marker = makeMarker(owner: source, attachment: attachment)
        let composerStore = ComposerDraftStoreStub(
            records: [
                PersistedComposerDraft(
                    gatewayID: source.gatewayID,
                    storedSessionID: source.storedSessionID,
                    revision: 1,
                    text: "Recovered prompt",
                    updatedAtMilliseconds: 1
                ),
            ]
        )
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            )
        )
        let runtime = makeRuntime(
            composerStore: composerStore,
            attachmentStore: attachmentStore
        )
        _ = try await runtime.drafts.restore(gatewayID: source.gatewayID)
        _ = try await runtime.attachments.restore(
            gatewayID: source.gatewayID
        )
        runtime.composer.seed(
            owner: source,
            text: "Recovered prompt",
            restored: true
        )
        let plan = try XCTUnwrap(
            runtime.creation.capture(
                owner: source,
                composer: "Recovered prompt",
                attachments: [attachment]
            )
        )

        let migrated = await runtime.creation.migrate(
            plan,
            to: makeLiveSession(storedID: target.storedSessionID),
            commitGuard: { true }
        )

        XCTAssertTrue(migrated)
        XCTAssertEqual(runtime.composer.text(for: source), "")
        XCTAssertEqual(
            runtime.composer.text(for: target),
            "Recovered prompt"
        )
        let sourceText = await composerStore.record(
            gatewayID: source.gatewayID,
            storedSessionID: source.storedSessionID
        )
        let targetText = await composerStore.record(
            gatewayID: target.gatewayID,
            storedSessionID: target.storedSessionID
        )
        XCTAssertEqual(sourceText?.text, "")
        XCTAssertEqual(targetText?.text, "")
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.first?.storedSessionID, "created")
        XCTAssertEqual(snapshot.markers.first?.liveSessionID, "live-created")
        XCTAssertEqual(snapshot.markers.first?.input, "Recovered prompt")
    }

    func testMigrationRejectsStaleCommitBeforeMovingAttachmentAuthority()
        async throws
    {
        let source = makeOwner(storedSessionID: "missing")
        let attachment = makeAttachment()
        let marker = makeMarker(owner: source, attachment: attachment)
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            )
        )
        let runtime = makeRuntime(attachmentStore: attachmentStore)
        _ = try await runtime.attachments.restore(
            gatewayID: source.gatewayID
        )
        runtime.composer.seed(owner: source, text: "Keep this")
        let plan = try XCTUnwrap(
            runtime.creation.capture(
                owner: source,
                composer: "Keep this",
                attachments: [attachment]
            )
        )

        let migrated = await runtime.creation.migrate(
            plan,
            to: makeLiveSession(storedID: "created"),
            commitGuard: { false }
        )

        XCTAssertFalse(migrated)
        XCTAssertEqual(runtime.composer.text(for: source), "Keep this")
        XCTAssertEqual(runtime.composer.text(for: makeOwner(
            storedSessionID: "created"
        )), "")
        let snapshot = await attachmentStore.snapshot()
        let migrationCallCount = await attachmentStore.migrationCallCount
        XCTAssertEqual(snapshot.markers, [marker])
        XCTAssertEqual(migrationCallCount, 0)
    }

    private func makeRuntime(
        composerStore: ComposerDraftStoreStub = ComposerDraftStoreStub(),
        attachmentStore: AttachmentDraftStoreStub = AttachmentDraftStoreStub()
    ) -> (
        creation: SessionCreationDraftRuntime,
        composer: SessionComposerRuntime,
        drafts: SessionDraftPersistenceRuntime,
        attachments: SessionAttachmentPersistenceRuntime
    ) {
        let composer = SessionComposerRuntime()
        let drafts = SessionDraftPersistenceRuntime(store: composerStore)
        let attachments = SessionAttachmentPersistenceRuntime(
            store: attachmentStore
        )
        return (
            SessionCreationDraftRuntime(
                composerRuntime: composer,
                draftPersistenceRuntime: drafts,
                attachmentPersistenceRuntime: attachments
            ),
            composer,
            drafts,
            attachments
        )
    }

    private func makeOwner(
        storedSessionID: String = "missing"
    ) -> ComposerDraftOwner {
        ComposerDraftOwner(
            gatewayID: "gateway",
            storedSessionID: storedSessionID
        )
    }

    private func makeAttachment() -> PendingAttachment {
        PendingAttachment(
            id: "photo",
            filename: "photo.jpg",
            data: Data("photo".utf8)
        )
    }

    private func makeMarker(
        owner: ComposerDraftOwner,
        attachment: PendingAttachment
    ) -> AttachmentMutationMarker {
        AttachmentMutationMarker(
            id: "marker",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "dead-live",
            input: "Recovered prompt",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .draftRecovered
        )
    }

    private func makeLiveSession(storedID: String) -> LiveSession {
        LiveSession(
            liveID: "live-\(storedID)",
            storedID: storedID,
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
    }
}
