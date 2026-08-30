import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testProcessRecoveryRestoresWhenOldRuntimeIsGone() async {
        let owner = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        let attachment = PendingAttachment(
            id: "recovered",
            filename: "recovered.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Recovered text",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .uploadPending
        )
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: owner.gatewayID,
                        storedSessionID: owner.storedSessionID,
                        revision: 1,
                        attachments: [],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: [marker]
            )
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertEqual(model.composer, "Recovered text")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(model.liveSession?.liveID, "live-one")
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.first?.stage, .draftRecovered)
        XCTAssertTrue(
            snapshot.drafts.first?.attachments.isEmpty == true
        )
    }

    func testRecoveredComposerConsolidatesEditsIntoMarkerAuthority()
        async {
        let owner = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        let attachment = PendingAttachment(
            id: "recovered",
            filename: "recovered.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Recovered prompt",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
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
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            )
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let model = SessionListModel(
            repository: repository,
            draftStore: composerStore,
            attachmentDraftStore: attachmentStore
        )

        await model.load(
            gatewayID: owner.gatewayID,
            preferredSessionID: owner.storedSessionID
        )

        XCTAssertEqual(
            model.composer,
            "Recovered prompt\n\nNewer draft"
        )
        var snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(
            snapshot.markers.first?.input,
            "Recovered prompt\n\nNewer draft"
        )
        var composerRecord = await composerStore.record(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        XCTAssertEqual(composerRecord?.text, "")

        model.updateComposer("Edited recovered draft")
        await eventuallyAsync {
            let edited = await attachmentStore.snapshot()
            return edited.markers.first?.input
                == "Edited recovered draft"
        }
        snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(
            snapshot.markers.first?.input,
            "Edited recovered draft"
        )
        composerRecord = await composerStore.record(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID
        )
        XCTAssertEqual(composerRecord?.text, "")

        let relaunched = SessionListModel(
            repository: SessionRepositoryStub(
                sessions: [session(id: "one", source: "niles")]
            ),
            draftStore: composerStore,
            attachmentDraftStore: attachmentStore
        )
        await relaunched.load(
            gatewayID: owner.gatewayID,
            preferredSessionID: owner.storedSessionID
        )
        XCTAssertEqual(relaunched.composer, "Edited recovered draft")
        XCTAssertEqual(relaunched.pendingAttachments, [attachment])
    }

    func testMissingRecoveredSessionMovesPromptAndPhotoToCreatedOwner()
        async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let attachment = PendingAttachment(
            id: "recovered",
            filename: "recovered.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: source.gatewayID,
            storedSessionID: source.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Describe this photo",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .promptPending
        )
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: source.gatewayID,
                        storedSessionID: source.storedSessionID,
                        revision: 1,
                        attachments: [],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: [marker]
            )
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )

        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )

        XCTAssertEqual(model.selectedSessionID, "missing")
        XCTAssertNil(model.liveSession)
        XCTAssertEqual(model.composer, "Describe this photo")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertTrue(model.hasDraftWithoutOpenSession)
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.markers.first?.stage, .draftRecovered)

        await model.createSession()

        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.liveSession?.liveID, "live-new")
        XCTAssertEqual(model.composer, "Describe this photo")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.markers.first?.storedSessionID, "new")
        XCTAssertEqual(snapshot.markers.first?.liveSessionID, "live-new")
        XCTAssertEqual(snapshot.markers.first?.stage, .draftRecovered)
        XCTAssertEqual(
            snapshot.drafts.first {
                $0.storedSessionID == "missing"
            }?.attachments,
            []
        )
        XCTAssertEqual(
            snapshot.drafts.first {
                $0.storedSessionID == "new"
            }?.attachments,
            []
        )

        let relaunched = SessionListModel(
            repository: SessionRepositoryStub(
                sessions: [session(id: "new", source: "niles")]
            ),
            attachmentDraftStore: store
        )
        await relaunched.load(
            gatewayID: source.gatewayID,
            preferredSessionID: "new"
        )
        XCTAssertEqual(relaunched.selectedSessionID, "new")
        XCTAssertEqual(relaunched.liveSession?.liveID, "live-new")
        XCTAssertEqual(relaunched.composer, "Describe this photo")
        XCTAssertEqual(relaunched.pendingAttachments, [attachment])
    }

    func testMissingOrdinaryTextDraftMovesToCreatedOwner() async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let composerStore = ComposerDraftStoreStub(
            records: [
                PersistedComposerDraft(
                    gatewayID: source.gatewayID,
                    storedSessionID: source.storedSessionID,
                    revision: 1,
                    text: "Keep this text",
                    updatedAtMilliseconds: 1
                ),
            ]
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            draftStore: composerStore
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )
        XCTAssertEqual(model.selectedSessionID, "missing")
        XCTAssertEqual(model.composer, "Keep this text")
        XCTAssertTrue(model.hasDraftWithoutOpenSession)

        await model.createSession()

        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.composer, "Keep this text")
        let sourceRecord = await composerStore.record(
            gatewayID: source.gatewayID,
            storedSessionID: source.storedSessionID
        )
        let targetRecord = await composerStore.record(
            gatewayID: source.gatewayID,
            storedSessionID: "new"
        )
        XCTAssertEqual(sourceRecord?.text, "")
        XCTAssertEqual(targetRecord?.text, "Keep this text")
    }

    func testMissingOrdinaryPhotoDraftIsPromotedBeforeRemoteCreate()
        async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let attachment = PendingAttachment(
            id: "ordinary-photo",
            filename: "ordinary.jpg",
            data: imageFixtureData()
        )
        let composerStore = ComposerDraftStoreStub(
            records: [
                PersistedComposerDraft(
                    gatewayID: source.gatewayID,
                    storedSessionID: source.storedSessionID,
                    revision: 1,
                    text: "Move both",
                    updatedAtMilliseconds: 1
                ),
            ]
        )
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: source.gatewayID,
                        storedSessionID: source.storedSessionID,
                        revision: 1,
                        attachments: [attachment],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: []
            )
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            draftStore: composerStore,
            attachmentDraftStore: attachmentStore
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )
        XCTAssertEqual(model.composer, "Move both")
        XCTAssertEqual(model.pendingAttachments, [attachment])

        await model.createSession()

        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.composer, "Move both")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.count, 1)
        XCTAssertEqual(snapshot.markers.first?.storedSessionID, "new")
        XCTAssertEqual(snapshot.markers.first?.liveSessionID, "live-new")
        XCTAssertEqual(snapshot.markers.first?.input, "Move both")
        XCTAssertEqual(snapshot.markers.first?.attachments, [attachment])
        let calls = await repository.calls
        XCTAssertEqual(
            calls.filter { $0 == "session.create" }.count,
            1
        )
    }

    func testOrdinaryPhotoPromotionFailureStopsBeforeRemoteCreate()
        async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let attachment = PendingAttachment(
            id: "ordinary-photo",
            filename: "ordinary.jpg",
            data: imageFixtureData()
        )
        let attachmentStore = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: source.gatewayID,
                        storedSessionID: source.storedSessionID,
                        revision: 1,
                        attachments: [attachment],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: []
            ),
            mutationBeginReturnsFalse: true
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )

        await model.createSession()

        let createCalls = await repository.callCount("session.create")
        XCTAssertEqual(createCalls, 0)
        XCTAssertEqual(model.selectedSessionID, "missing")
        XCTAssertNil(model.liveSession)
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertEqual(
            model.operationError,
            "Nile could not safely save this draft, so no session was created."
        )
    }

    func testRecoveredSessionMigrationFailureKeepsPlaceholderAuthority()
        async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let attachment = PendingAttachment(
            id: "recovered",
            filename: "recovered.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: source.gatewayID,
            storedSessionID: source.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Keep this",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .draftRecovered
        )
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            ),
            migrationReturnsFalse: true
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )

        await model.createSession()

        XCTAssertEqual(model.selectedSessionID, "missing")
        XCTAssertNil(model.liveSession)
        XCTAssertEqual(model.composer, "Keep this")
        XCTAssertEqual(model.pendingAttachments, [attachment])
        XCTAssertFalse(model.isOpeningSession)
        XCTAssertFalse(model.isAttachmentDraftLocked)
        XCTAssertEqual(
            model.operationError,
            "Could not safely move the recovered photo draft. Try creating the session again."
        )
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.markers, [marker])
    }

    func testGatewayChangeRejectsStaleRecoveredMigrationCommit() async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let attachment = PendingAttachment(
            id: "recovered",
            filename: "recovered.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: source.gatewayID,
            storedSessionID: source.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Keep gateway one",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .draftRecovered
        )
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            ),
            blocksMigration: true
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )

        let create = Task {
            await model.createSession()
        }
        await eventuallyAsync {
            await store.migrationCallCount == 1
        }
        await model.load(
            gatewayID: "gateway-2",
            preferredSessionID: nil
        )
        await store.releaseMigration()
        await create.value

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.markers, [marker])
        XCTAssertEqual(model.selectedSessionID, "new")
        XCTAssertEqual(model.liveSession?.liveID, "live-new")
    }

    func testMultiMarkerRecoveredSessionMovesMergedDraftAsOneCAS() async {
        let source = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "missing"
        )
        let firstPhoto = PendingAttachment(
            id: "photo-a",
            filename: "a.jpg",
            data: imageFixtureData()
        )
        let secondPhoto = PendingAttachment(
            id: "photo-b",
            filename: "b.jpg",
            data: imageFixtureData()
        )
        func marker(
            id: String,
            input: String,
            attachment: PendingAttachment
        ) -> AttachmentMutationMarker {
            AttachmentMutationMarker(
                id: id,
                gatewayID: source.gatewayID,
                storedSessionID: source.storedSessionID,
                liveSessionID: "dead-runtime",
                input: input,
                attachments: [attachment],
                userEntryID: "user-\(id)",
                userMessagesBefore: 0,
                stage: .draftRecovered
            )
        }
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [
                    marker(
                        id: "a-marker",
                        input: "Prompt A",
                        attachment: firstPhoto
                    ),
                    marker(
                        id: "b-marker",
                        input: "Prompt B",
                        attachment: secondPhoto
                    ),
                ]
            )
        )
        let repository = SessionRepositoryStub(sessions: [])
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )
        await model.load(
            gatewayID: source.gatewayID,
            preferredSessionID: source.storedSessionID
        )
        XCTAssertEqual(model.composer, "Prompt B\n\nPrompt A")
        XCTAssertEqual(
            model.pendingAttachments,
            [firstPhoto, secondPhoto]
        )

        await model.createSession()

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.markers.count, 2)
        XCTAssertTrue(
            snapshot.markers.allSatisfy {
                $0.storedSessionID == "new"
                    && $0.liveSessionID == "live-new"
                    && $0.input == "Prompt B\n\nPrompt A"
            }
        )
        XCTAssertEqual(model.composer, "Prompt B\n\nPrompt A")
        XCTAssertEqual(
            model.pendingAttachments,
            [firstPhoto, secondPhoto]
        )
    }

    func testProcessRecoveryUsesDurableHistoryAsAcceptanceProof() async {
        let owner = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        let attachment = PendingAttachment(
            id: "accepted",
            filename: "accepted.jpg",
            data: imageFixtureData()
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "dead-runtime",
            input: "Accepted prompt",
            attachments: [attachment],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .promptPending
        )
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [
                    PersistedAttachmentDraft(
                        gatewayID: owner.gatewayID,
                        storedSessionID: owner.storedSessionID,
                        revision: 1,
                        attachments: [],
                        updatedAtMilliseconds: 1
                    ),
                ],
                markers: [marker]
            )
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            histories: [
                "one": [
                    HermesMessage(
                        role: "user",
                        text: "[image]\n\nAccepted prompt"
                    ),
                ],
            ]
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertEqual(model.liveSession?.liveID, "live-one")
        let snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.markers.isEmpty)
        XCTAssertTrue(snapshot.drafts.first?.attachments.isEmpty == true)
    }

    func testLiveUncertainRuntimeStaysClosedAndIsNeverResumed() async {
        let owner = ComposerDraftOwner(
            gatewayID: "gateway-1",
            storedSessionID: "one"
        )
        let marker = AttachmentMutationMarker(
            id: "mutation",
            gatewayID: owner.gatewayID,
            storedSessionID: owner.storedSessionID,
            liveSessionID: "uncertain-runtime",
            input: "Maybe sent",
            attachments: [
                PendingAttachment(
                    id: "photo",
                    filename: "photo.jpg",
                    data: imageFixtureData()
                ),
            ],
            userEntryID: "user-entry",
            userMessagesBefore: 0,
            stage: .quarantineOnly
        )
        let store = AttachmentDraftStoreStub(
            snapshot: AttachmentRecoverySnapshot(
                drafts: [],
                markers: [marker]
            )
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            runtimeStatuses: ["uncertain-runtime": "working"]
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: store
        )

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        XCTAssertNil(model.liveSession)
        XCTAssertEqual(
            model.operationError,
            "Hermes may still be handling the interrupted photo. Nile is keeping this conversation closed until Hermes safely releases it; use a new session in the meantime."
        )
        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains("runtime.status:uncertain-runtime")
        )
        XCTAssertFalse(calls.contains("session.resume:one"))
    }

    func testTranscriptImagePreviewHydratesWithTwoMegabyteBound() async {
        let imageBytes = imageFixtureData()
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            openedSessions: [
                LiveSession(
                    liveID: "live-one",
                    storedID: "one",
                    info: SessionInfo(model: nil, provider: nil),
                    messages: [
                        HermesMessage(
                            role: "assistant",
                            text: "Preview\n\nMEDIA:/tmp/result.png"
                        ),
                    ],
                    running: false,
                    status: "idle",
                    inflight: nil
                ),
            ],
            downloadedAttachment: DownloadedAttachment(
                path: "/tmp/result.png",
                filename: "result.png",
                mimeType: "image/png",
                bytes: imageBytes
            )
        )
        let model = SessionListModel(repository: repository)

        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        await eventually {
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.attachments.first?.previewBase64
                    == imageBytes.base64EncodedString()
            }
        }
        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains(
                "attachment.download:/tmp/result.png:2097152"
            )
        )
    }

    func testOpenAttachmentUsesFullBoundAndPrivateCache() async {
        let downloaded = DownloadedAttachment(
            path: "/tmp/report.pdf",
            filename: "report.pdf",
            mimeType: "application/pdf",
            bytes: Data("pdf".utf8)
        )
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            downloadedAttachment: downloaded
        )
        let cache = AttachmentCacheStub()
        let model = SessionListModel(
            repository: repository,
            attachmentCache: cache
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.openAttachment(path: downloaded.path)
        await eventually {
            model.openedAttachment?.filename == "report.pdf"
                && !model.isOpeningAttachment
        }

        let prepared = await cache.prepared
        XCTAssertEqual(prepared, [downloaded])
        let calls = await repository.calls
        XCTAssertTrue(
            calls.contains(
                "attachment.download:/tmp/report.pdf:33554432"
            )
        )
        model.dismissOpenedAttachment()
        XCTAssertNil(model.openedAttachment)
    }

    func testLateAttachmentOpenCannotReplaceNewSessionViewerState() async {
        let downloaded = DownloadedAttachment(
            path: "/tmp/report.pdf",
            filename: "report.pdf",
            mimeType: "application/pdf",
            bytes: Data("pdf".utf8)
        )
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            downloadedAttachment: downloaded
        )
        let cache = BlockingFirstAttachmentCacheStub()
        let model = SessionListModel(
            repository: repository,
            attachmentCache: cache
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.openAttachment(path: "/tmp/old.pdf")
        await eventuallyAsync { await cache.callCount == 1 }

        await model.selectSession(id: "two")
        model.openAttachment(path: "/tmp/new.pdf")
        await eventually {
            model.openedAttachment?.filename == "prepared-2-report.pdf"
                && !model.isOpeningAttachment
        }

        await cache.releaseFirst()
        await eventuallyAsync { await cache.completedCount == 2 }
        XCTAssertEqual(
            model.openedAttachment?.filename,
            "prepared-2-report.pdf"
        )
        XCTAssertNil(model.operationError)
        XCTAssertFalse(model.isOpeningAttachment)
    }

}
