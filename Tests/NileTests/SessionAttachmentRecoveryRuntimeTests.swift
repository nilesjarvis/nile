import Foundation
import XCTest
@testable import Nile

@MainActor
final class SessionAttachmentRecoveryRuntimeTests: XCTestCase {
    func testRestoreConsolidatesOrdinaryTextIntoRecoveredMarkerAuthority()
        async throws
    {
        let owner = makeOwner()
        let attachment = makeAttachment()
        let marker = makeMarker(
            owner: owner,
            attachment: attachment,
            input: "Recovered prompt",
            stage: .draftRecovered
        )
        let composerStore = ComposerDraftStoreStub(
            records: [
                PersistedComposerDraft(
                    gatewayID: owner.gatewayID,
                    storedSessionID: owner.storedSessionID,
                    revision: 1,
                    text: "Newer draft",
                    updatedAtMilliseconds: 1
                ),
            ]
        )
        let attachmentStore = makeAttachmentStore(markers: [marker])
        let harness = makeHarness(
            composerStore: composerStore,
            attachmentStore: attachmentStore
        )
        _ = try await harness.drafts.restore(gatewayID: owner.gatewayID)

        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )

        XCTAssertEqual(
            harness.composer.text(for: owner),
            "Recovered prompt\n\nNewer draft"
        )
        XCTAssertEqual(harness.attachments.draft(for: owner), [attachment])
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(
            snapshot.markers.first?.input,
            "Recovered prompt\n\nNewer draft"
        )
        let composerRecord = await composerStore.record(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        XCTAssertEqual(composerRecord?.text, "")
    }

    func testReconcileUsesDurableHistoryAsAcceptanceProof() async throws {
        let owner = makeOwner()
        let attachment = makeAttachment()
        let marker = makeMarker(
            owner: owner,
            attachment: attachment,
            input: "Accepted prompt",
            stage: .promptPending
        )
        let attachmentStore = makeAttachmentStore(markers: [marker])
        let repository = SessionRepositoryStub(
            sessions: [],
            histories: [
                owner.storedSessionID: [
                    HermesMessage(
                        role: "user",
                        text: "[image]\n\nAccepted prompt"
                    ),
                ],
            ]
        )
        let harness = makeHarness(
            attachmentStore: attachmentStore,
            repository: repository
        )
        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )

        let remainsClosed = try await harness.recovery
            .reconcileStoredMutations(
                owner: owner,
                navigationOwner: harness.navigationOwner
            )

        XCTAssertFalse(remainsClosed)
        XCTAssertFalse(harness.attachments.isQuarantined(owner: owner))
        let snapshot = await attachmentStore.snapshot()
        XCTAssertTrue(snapshot.markers.isEmpty)
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            ["runtime.status:dead-runtime", "history:session"]
        )
    }

    func testReconcileKeepsOwnerClosedWhileOldRuntimeExists() async throws {
        let owner = makeOwner()
        let marker = makeMarker(
            owner: owner,
            attachment: makeAttachment(),
            stage: .quarantineOnly
        )
        let attachmentStore = makeAttachmentStore(markers: [marker])
        let repository = SessionRepositoryStub(
            sessions: [],
            runtimeStatuses: ["dead-runtime": "working"]
        )
        let harness = makeHarness(
            attachmentStore: attachmentStore,
            repository: repository
        )
        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )

        let remainsClosed = try await harness.recovery
            .reconcileStoredMutations(
                owner: owner,
                navigationOwner: harness.navigationOwner
            )

        XCTAssertTrue(remainsClosed)
        XCTAssertTrue(harness.attachments.isQuarantined(owner: owner))
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers, [marker])
    }

    func testUnavailableDraftAdvancesDeadMutationAndReturnsPresentation()
        async throws
    {
        let owner = makeOwner(storedSessionID: "missing")
        let attachment = makeAttachment()
        let marker = makeMarker(
            owner: owner,
            attachment: attachment,
            input: "Recover me",
            stage: .uploadPending
        )
        let attachmentStore = makeAttachmentStore(markers: [marker])
        let harness = makeHarness(attachmentStore: attachmentStore)
        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )

        let resolution = await harness.recovery.resolveUnavailableDraft(
            preferredSessionID: owner.storedSessionID,
            gatewayID: owner.gatewayID,
            navigationOwner: harness.navigationOwner,
            commitGuard: { true }
        )

        guard case let .recovered(presentation) = resolution else {
            return XCTFail("Expected a recovered missing-owner draft")
        }
        XCTAssertEqual(presentation.owner, owner)
        XCTAssertEqual(presentation.composer, "Recover me")
        XCTAssertEqual(presentation.attachments, [attachment])
        XCTAssertFalse(harness.attachments.isQuarantined(owner: owner))
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.first?.stage, .draftRecovered)
    }

    func testUnavailableDraftRejectsStaleGenerationBeforeMarkerAdvance()
        async throws
    {
        let owner = makeOwner(storedSessionID: "missing")
        let marker = makeMarker(
            owner: owner,
            attachment: makeAttachment(),
            stage: .uploadPending
        )
        let attachmentStore = makeAttachmentStore(markers: [marker])
        let harness = makeHarness(attachmentStore: attachmentStore)
        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )

        let resolution = await harness.recovery.resolveUnavailableDraft(
            preferredSessionID: owner.storedSessionID,
            gatewayID: owner.gatewayID,
            navigationOwner: harness.navigationOwner,
            commitGuard: { false }
        )

        XCTAssertEqual(resolution, .stale)
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers, [marker])
    }

    func testRecoveredEditFailureRollsProjectionBackToDurableMarker()
        async throws
    {
        let owner = makeOwner()
        let marker = makeMarker(
            owner: owner,
            attachment: makeAttachment(),
            input: "Durable prompt",
            stage: .draftRecovered
        )
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            ),
            migrationReturnsFalse: true
        )
        let harness = makeHarness(attachmentStore: attachmentStore)
        try await harness.recovery.restore(
            gatewayID: owner.gatewayID,
            commitGuard: { true }
        )
        harness.composer.update(owner: owner, text: "Unsaved edit")
        var failure: SessionAttachmentRecoveryRuntime.RecoveredEditFailure?

        harness.recovery.scheduleRecoveredComposerEdit(
            owner: owner,
            markers: [marker],
            text: "Unsaved edit",
            onFailure: { failure = $0 }
        )

        await eventually { failure != nil }
        XCTAssertEqual(
            failure,
            SessionAttachmentRecoveryRuntime.RecoveredEditFailure(
                owner: owner,
                attemptedText: "Unsaved edit",
                fallbackText: "Durable prompt"
            )
        )
        XCTAssertEqual(harness.composer.text(for: owner), "Durable prompt")
    }

    private struct Harness {
        let recovery: SessionAttachmentRecoveryRuntime
        let composer: SessionComposerRuntime
        let drafts: SessionDraftPersistenceRuntime
        let attachments: SessionAttachmentPersistenceRuntime
        let navigationOwner: SessionNavigationRuntime.GatewayOwner
    }

    private func makeHarness(
        composerStore: ComposerDraftStoreStub = ComposerDraftStoreStub(),
        attachmentStore: AttachmentDraftStoreStub = AttachmentDraftStoreStub(),
        repository: SessionRepositoryStub = SessionRepositoryStub(sessions: [])
    ) -> Harness {
        let composer = SessionComposerRuntime()
        let drafts = SessionDraftPersistenceRuntime(store: composerStore)
        let attachments = SessionAttachmentPersistenceRuntime(
            store: attachmentStore
        )
        let navigation = SessionNavigationRuntime(repository: repository)
        let navigationOwner = SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: 1,
            gatewayID: "gateway"
        )
        navigation.resetGateway(owner: navigationOwner)
        return Harness(
            recovery: SessionAttachmentRecoveryRuntime(
                composerRuntime: composer,
                draftPersistenceRuntime: drafts,
                attachmentPersistenceRuntime: attachments,
                navigationRuntime: navigation
            ),
            composer: composer,
            drafts: drafts,
            attachments: attachments,
            navigationOwner: navigationOwner
        )
    }

    private func makeOwner(
        storedSessionID: String = "session"
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
        attachment: PendingAttachment,
        input: String = "Prompt",
        stage: AttachmentMutationStage
    ) -> AttachmentMutationMarker {
        AttachmentMutationMarker(
            id: "marker",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "dead-runtime",
            input: input,
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: stage
        )
    }

    private func makeAttachmentStore(
        markers: [AttachmentMutationMarker]
    ) -> AttachmentDraftStoreStub {
        AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: markers
            )
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor @Sendable () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}
