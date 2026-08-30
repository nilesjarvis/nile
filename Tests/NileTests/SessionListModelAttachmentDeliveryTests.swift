import Observation
import XCTest
@testable import Nile

@MainActor
extension SessionListModelTests {
    func testPhotoDraftIsProtectedBeforeItBecomesVisible() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.attachImageData(imageFixtureData())
        await eventually {
            model.pendingAttachments.count == 1 && !model.isAttaching
        }

        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.drafts.count, 1)
        XCTAssertEqual(
            snapshot.drafts.first?.attachments,
            model.pendingAttachments
        )
        XCTAssertTrue(snapshot.markers.isEmpty)
    }

    func testPhotoDraftStorageFailureNeverPublishesUnprotectedBytes() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let attachmentStore = AttachmentDraftStoreStub(
            failsDraftUpdates: true
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.attachImageData(imageFixtureData())
        await eventually { !model.isAttaching }

        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertEqual(
            model.operationError,
            "Could not save that photo draft. Add the photo again."
        )
        let snapshot = await attachmentStore.snapshot()
        XCTAssertTrue(snapshot.drafts.isEmpty)
        XCTAssertTrue(snapshot.markers.isEmpty)
    }

    func testLatePhotoDraftWriteRemainsScopedToOriginalSession() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ]
        )
        let attachmentStore = AttachmentDraftStoreStub(
            blockedDraftUpdateNumbers: [1]
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")

        model.attachImageData(imageFixtureData())
        await eventuallyAsync {
            await attachmentStore.draftUpdateCallCount == 1
        }
        await model.selectSession(id: "two")
        await attachmentStore.releaseDraftUpdate(1)
        await eventuallyAsync {
            await attachmentStore.completedDraftUpdateCount == 1
        }

        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        await model.selectSession(id: "one")
        XCTAssertEqual(model.pendingAttachments.count, 1)
    }

    func testLatePhotoRemovalCannotClearDestinationSessionState() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ]
        )
        let attachmentStore = AttachmentDraftStoreStub(
            blockedDraftUpdateNumbers: [2]
        )
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }
        let attachmentID = model.pendingAttachments[0].id

        model.removeAttachment(id: attachmentID)
        await eventuallyAsync {
            await attachmentStore.draftUpdateCallCount == 2
        }
        await model.selectSession(id: "two")
        await attachmentStore.releaseDraftUpdate(2)
        await eventuallyAsync {
            await attachmentStore.completedDraftUpdateCount == 2
        }

        XCTAssertEqual(model.selectedSessionID, "two")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        await model.selectSession(id: "one")
        XCTAssertTrue(model.pendingAttachments.isEmpty)
    }

    func testPhotoUploadWaitsForMessageStartBeforeRetiringRecoveryMarker() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")]
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }
        model.updateComposer("Inspect this")

        XCTAssertTrue(model.sendMessage())
        await eventuallyAsync {
            let calls = await repository.calls
            let snapshot = await attachmentStore.snapshot()
            return calls.contains {
                $0.hasPrefix("image.attach_bytes:live-one")
            } && calls.contains("prompt.submit:live-one:Inspect this")
                && snapshot.markers.first?.stage == .promptPending
        }
        XCTAssertTrue(model.pendingAttachments.isEmpty)
        XCTAssertTrue(
            model.transcriptEntries.contains { entry in
                guard case let .message(message) = entry else {
                    return false
                }
                return message.role == .user
                    && message.content == "Inspect this"
                    && message.images.count == 1
            }
        )

        await repository.yield(.messageStart(sessionID: "live-one"))
        await eventuallyAsync {
            await attachmentStore.snapshot().markers.isEmpty
        }
    }

    func testDefiniteUploadRejectionRestoresExactTextAndPhoto() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            attachError: HermesError(
                "image rejected",
                code: 4009,
                retryable: false
            )
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }
        model.updateComposer("Retry me")

        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.pendingAttachments.count == 1
                && model.composer == "Retry me"
                && model.operationError == "image rejected"
        }
        XCTAssertNotNil(model.liveSession)
        let snapshot = await attachmentStore.snapshot()
        XCTAssertTrue(snapshot.markers.isEmpty)
        let calls = await repository.calls
        XCTAssertFalse(calls.contains { $0.hasPrefix("image.detach:") })
    }

    func testDefinitePromptRejectionDetachesLeaseThenRestoresDraft() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "prompt rejected",
                code: 4009,
                retryable: false
            )
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }
        model.updateComposer("Retry me")

        XCTAssertTrue(model.sendMessage())
        await eventuallyAsync {
            let calls = await repository.calls
            return model.pendingAttachments.count == 1
                && model.composer == "Retry me"
                && calls.contains(
                    "image.detach:live-one:/tmp/hermes/photo.jpg"
                )
        }
        let snapshot = await attachmentStore.snapshot()
        XCTAssertTrue(snapshot.markers.isEmpty)
    }

    func testDetachFalseQuarantinesInsteadOfClaimingPhotoWasReleased() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "prompt rejected",
                code: 4009,
                retryable: false
            ),
            detachResult: false
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }

        XCTAssertTrue(model.sendMessage())
        await eventually { model.liveSession == nil && !model.isSending }

        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.first?.stage, .quarantineOnly)
        XCTAssertTrue(snapshot.drafts.first?.attachments.isEmpty == true)
        XCTAssertEqual(
            model.operationError,
            "Hermes may still be handling the interrupted photo. Nile is keeping this conversation closed until Hermes safely releases it; use a new session in the meantime."
        )
    }

    func testMissingRuntimeDuringDetachSafelyRestoresPhotoDraft() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "prompt rejected",
                code: 4009,
                retryable: false
            ),
            detachError: HermesError(
                "session not found",
                code: 4001,
                retryable: false
            )
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }

        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.pendingAttachments.count == 1 && !model.isSending
        }

        XCTAssertNotNil(model.liveSession)
        let snapshot = await attachmentStore.snapshot()
        XCTAssertTrue(snapshot.markers.isEmpty)
        XCTAssertEqual(snapshot.drafts.first?.attachments.count, 1)
    }

    func testUnknownPromptErrorQuarantinesWithoutDetachingLease() async {
        let repository = SessionRepositoryStub(
            sessions: [session(id: "one", source: "niles")],
            submitError: HermesError(
                "unknown prompt failure",
                code: 4999,
                retryable: false
            )
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }

        XCTAssertTrue(model.sendMessage())
        await eventually { model.liveSession == nil && !model.isSending }

        let calls = await repository.calls
        XCTAssertFalse(calls.contains { $0.hasPrefix("image.detach:") })
        let snapshot = await attachmentStore.snapshot()
        XCTAssertEqual(snapshot.markers.first?.stage, .quarantineOnly)
    }

    func testUncertainUploadQuarantinesOnlyItsOwner() async {
        let repository = SessionRepositoryStub(
            sessions: [
                session(id: "one", source: "niles"),
                session(id: "two", source: "niles"),
            ],
            attachError: HermesError(
                "connection lost",
                retryable: true,
                isConnectionFailure: true
            )
        )
        let attachmentStore = AttachmentDraftStoreStub()
        let model = SessionListModel(
            repository: repository,
            attachmentDraftStore: attachmentStore
        )
        await model.load(gatewayID: "gateway-1", preferredSessionID: "one")
        model.attachImageData(imageFixtureData())
        await eventually { model.pendingAttachments.count == 1 }

        XCTAssertTrue(model.sendMessage())
        await eventually {
            model.liveSession == nil
                && model.operationError?.contains(
                    "Hermes may still be handling the interrupted photo"
                ) == true
        }
        let quarantined = await attachmentStore.snapshot()
        XCTAssertEqual(quarantined.markers.first?.stage, .quarantineOnly)

        await model.selectSession(id: "two")
        XCTAssertEqual(model.liveSession?.liveID, "live-two")
        model.updateComposer("Independent owner")
        XCTAssertTrue(model.composerCanSend)
    }

}
