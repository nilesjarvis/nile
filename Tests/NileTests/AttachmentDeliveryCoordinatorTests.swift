import XCTest
@testable import Nile

final class AttachmentDeliveryCoordinatorTests: XCTestCase {
    func testStartBeforeSubmitResponseBuffersThenAcceptsExactlyOnce() {
        var coordinator = AttachmentDeliveryCoordinator()
        let batch = makeBatch()
        coordinator.track(batch)
        coordinator.beginUpload(for: batch)
        let lease = coordinator.recordUploadedPath(
            "/tmp/photo.jpg",
            for: batch
        )
        coordinator.beginSubmit(batchID: batch.id)

        XCTAssertTrue(
            coordinator.onMessageStart(
                owner: batch.owner,
                liveSessionID: batch.liveSessionID
            ).isEmpty
        )
        XCTAssertTrue(coordinator.state(batchID: batch.id).bufferedStart)

        XCTAssertEqual(
            coordinator.resolveSubmitResponse(
                batch: batch,
                status: .streaming
            ),
            .streamingAccepted(turnEndedBeforeResponse: false)
        )
        XCTAssertFalse(coordinator.hasLease(lease))
        XCTAssertNil(coordinator.state(batchID: batch.id).batch)
    }

    func testStreamingResponseWaitsForCorrelatedStart() {
        var coordinator = AttachmentDeliveryCoordinator()
        let batch = makeBatch()
        coordinator.track(batch)
        coordinator.beginSubmit(batchID: batch.id)

        XCTAssertEqual(
            coordinator.resolveSubmitResponse(
                batch: batch,
                status: .streaming
            ),
            .awaitStreamingStart
        )
        XCTAssertEqual(
            coordinator.onMessageStart(
                owner: batch.owner,
                liveSessionID: batch.liveSessionID
            ),
            [batch]
        )
        XCTAssertNil(coordinator.state(batchID: batch.id).batch)
    }

    func testWrongOwnerAndReplacementRuntimeCannotConsumeLease() {
        var coordinator = AttachmentDeliveryCoordinator()
        let batch = makeBatch()
        coordinator.track(batch)
        coordinator.beginSubmit(batchID: batch.id)
        _ = coordinator.resolveSubmitResponse(
            batch: batch,
            status: .streaming
        )

        XCTAssertTrue(
            coordinator.onMessageStart(
                owner: ComposerDraftOwner(
                    gatewayID: "other",
                    storedSessionID: "session"
                ),
                liveSessionID: batch.liveSessionID
            ).isEmpty
        )
        XCTAssertTrue(
            coordinator.onMessageStart(
                owner: batch.owner,
                liveSessionID: "replacement-runtime"
            ).isEmpty
        )
        XCTAssertNotNil(coordinator.state(batchID: batch.id).batch)
    }

    func testQuarantineStateScopesLeaseAndUncertainMutationLifecycles() {
        var state = AttachmentDeliveryQuarantineState()
        let batch = makeBatch()
        state.beginUpload(for: batch)
        let lease = state.recordUploadedPath("/tmp/photo.jpg", for: batch)

        XCTAssertTrue(state.hasLease(lease))
        XCTAssertEqual(state.leases(forMutationID: batch.id), [lease])
        state.beginUpload(for: batch)

        XCTAssertEqual(
            state.interruptUpload()?.kind,
            .uploadPath
        )
        state.addPromptUncertainty(for: batch)
        XCTAssertEqual(
            Set(state.uncertainties(owner: batch.owner).map(\.kind)),
            [.uploadPath, .promptOutcome]
        )
        XCTAssertFalse(
            state.hasUncertainty(
                owner: ComposerDraftOwner(
                    gatewayID: "gateway",
                    storedSessionID: "other"
                )
            )
        )

        XCTAssertTrue(state.removeLease(lease))
        XCTAssertFalse(state.hasLease(lease))
        state.clearUncertainty(mutationID: batch.id)
        XCTAssertFalse(state.hasUncertainty(owner: batch.owner))
    }

    func testSteeredResponseNeverClaimsPhotoDelivery() {
        var coordinator = AttachmentDeliveryCoordinator()
        let batch = makeBatch()
        coordinator.track(batch)
        coordinator.beginSubmit(batchID: batch.id)

        XCTAssertEqual(
            coordinator.resolveSubmitResponse(
                batch: batch,
                status: .steered
            ),
            .steered(turnAlreadyCompleted: false)
        )
        XCTAssertNotNil(coordinator.state(batchID: batch.id).batch)
    }

    private func makeBatch() -> OutboundAttachmentBatch {
        OutboundAttachmentBatch(
            id: "mutation",
            owner: ComposerDraftOwner(
                gatewayID: "gateway",
                storedSessionID: "session"
            ),
            liveSessionID: "live-session",
            input: "inspect",
            attachments: [
                PendingAttachment(
                    id: "photo",
                    filename: "photo.jpg",
                    data: Data("jpeg".utf8)
                ),
            ],
            userEntryID: "user-entry",
            userMessagesBefore: 1
        )
    }
}
