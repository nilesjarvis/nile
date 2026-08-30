import XCTest
@testable import Nile

@MainActor
final class SessionAttachmentRuntimeTests: XCTestCase {
    func testPreparationFailureDoesNotReachTransport() async {
        let repository = AttachmentRuntimeRepository()
        let runtime = makeRuntime(repository: repository)
        let probe = AttachmentRuntimeProbe()

        XCTAssertTrue(
            runtime.startDelivery(
                batch: makeBatch(),
                marker: makeMarker(),
                prepare: { .rejected(message: "not durable") },
                preparePrompt: { _, _ in
                    XCTFail("Prompt preparation must not run")
                    return false
                },
                didUpload: { _, _ in XCTFail("Nothing should upload") },
                onOutcome: { probe.outcomes.append($0) },
                onStartTimeout: { _, _ in XCTFail("No timeout expected") }
            )
        )

        await eventually { probe.outcomes.count == 1 }
        guard case let .preparationFailed(message) = probe.outcomes[0] else {
            return XCTFail("Expected preparation failure")
        }
        XCTAssertEqual(message, "not durable")
        let calls = await repository.calls
        XCTAssertEqual(calls, [])
    }

    func testStartBeforePromptResponseAcceptsExactlyOnce() async {
        let repository = AttachmentRuntimeRepository(blockPrompt: true)
        let runtime = makeRuntime(repository: repository)
        let probe = AttachmentRuntimeProbe()
        let batch = makeBatch()

        XCTAssertTrue(
            runtime.startDelivery(
                batch: batch,
                marker: makeMarker(),
                prepare: { .ready },
                preparePrompt: { current, pending in
                    probe.promptTransitions.append((current, pending))
                    return true
                },
                didUpload: { attachment, attached in
                    probe.uploads.append((attachment, attached))
                },
                onOutcome: { probe.outcomes.append($0) },
                onStartTimeout: { _, _ in XCTFail("No timeout expected") }
            )
        )
        await eventuallyAsync { await repository.promptStarted }

        XCTAssertTrue(
            runtime.onMessageStart(
                owner: batch.owner,
                liveSessionID: batch.liveSessionID
            ).isEmpty
        )
        await repository.releasePrompt()
        await eventually { probe.outcomes.count == 1 }

        guard case let .accepted(accepted, marker) = probe.outcomes[0] else {
            return XCTFail("Expected accepted delivery")
        }
        XCTAssertEqual(accepted, batch)
        XCTAssertEqual(marker.stage, .promptPending)
        XCTAssertEqual(probe.uploads.count, 1)
        XCTAssertEqual(probe.promptTransitions.count, 1)
        XCTAssertTrue(
            runtime.onMessageStart(
                owner: batch.owner,
                liveSessionID: batch.liveSessionID
            ).isEmpty
        )
        let calls = await repository.calls
        XCTAssertEqual(
            calls,
            [
                .attach(
                    liveSessionID: batch.liveSessionID,
                    filename: "photo.jpg"
                ),
                .prompt(
                    liveSessionID: batch.liveSessionID,
                    text: batch.input
                ),
            ]
        )
    }

    func testUploadFailureClassificationFailsClosed() async {
        let definite = AttachmentRuntimeRepository(
            attachResult: .failure(
                HermesError("rejected", code: 4004, retryable: false)
            )
        )
        let definiteRuntime = makeRuntime(repository: definite)
        let definiteProbe = AttachmentRuntimeProbe()
        _ = definiteRuntime.startDelivery(
            batch: makeBatch(id: "definite"),
            marker: makeMarker(id: "definite"),
            prepare: { .ready },
            preparePrompt: { _, _ in true },
            didUpload: { _, _ in },
            onOutcome: { definiteProbe.outcomes.append($0) },
            onStartTimeout: { _, _ in }
        )
        await eventually { definiteProbe.outcomes.count == 1 }
        assertFailure(
            definiteProbe.outcomes[0],
            message: "rejected",
            uncertain: false,
            stage: .uploadPending
        )

        let uncertain = AttachmentRuntimeRepository(
            attachResult: .failure(
                HermesError(
                    "connection dropped",
                    retryable: true,
                    isConnectionFailure: true
                )
            )
        )
        let uncertainRuntime = makeRuntime(repository: uncertain)
        let uncertainProbe = AttachmentRuntimeProbe()
        _ = uncertainRuntime.startDelivery(
            batch: makeBatch(id: "uncertain"),
            marker: makeMarker(id: "uncertain"),
            prepare: { .ready },
            preparePrompt: { _, _ in true },
            didUpload: { _, _ in },
            onOutcome: { uncertainProbe.outcomes.append($0) },
            onStartTimeout: { _, _ in }
        )
        await eventually { uncertainProbe.outcomes.count == 1 }
        assertFailure(
            uncertainProbe.outcomes[0],
            message: "connection dropped",
            uncertain: true,
            stage: .uploadPending
        )
    }

    func testMissingStartTimesOutAndDisconnectsTransport() async {
        let repository = AttachmentRuntimeRepository(promptResult: .success(.queued))
        let runtime = makeRuntime(
            repository: repository,
            startConfirmationDelay: .milliseconds(1)
        )
        let probe = AttachmentRuntimeProbe()
        let batch = makeBatch()

        _ = runtime.startDelivery(
            batch: batch,
            marker: makeMarker(),
            prepare: { .ready },
            preparePrompt: { _, _ in true },
            didUpload: { _, _ in },
            onOutcome: { probe.outcomes.append($0) },
            onStartTimeout: { batch, marker in
                probe.timeouts.append((batch, marker))
            }
        )

        await eventuallyAsync { await repository.disconnectCount == 1 }
        XCTAssertTrue(probe.outcomes.isEmpty)
        XCTAssertEqual(probe.timeouts.count, 1)
        XCTAssertEqual(probe.timeouts[0].0, batch)
        XCTAssertEqual(probe.timeouts[0].1.stage, .promptPending)
    }

    func testKnownLeaseCleanupUsesAttachmentCapability() async {
        let repository = AttachmentRuntimeRepository(promptResult: .success(.queued))
        let runtime = makeRuntime(
            repository: repository,
            startConfirmationDelay: .seconds(60)
        )
        let batch = makeBatch()

        _ = runtime.startDelivery(
            batch: batch,
            marker: makeMarker(),
            prepare: { .ready },
            preparePrompt: { _, _ in true },
            didUpload: { _, _ in },
            onOutcome: { _ in },
            onStartTimeout: { _, _ in }
        )
        await eventuallyAsync { await repository.promptCallCount == 1 }

        let detached = await runtime.detachKnownLeases(for: batch)
        let calls = await repository.calls
        XCTAssertTrue(detached)
        XCTAssertEqual(
            calls.last,
            .detach(
                liveSessionID: batch.liveSessionID,
                path: "/runtime/photo.jpg"
            )
        )
        runtime.reset()
    }

    func testResetCancelsBlockedUploadWithoutPublishingOutcome() async {
        let repository = AttachmentRuntimeRepository(blockAttach: true)
        let runtime = makeRuntime(repository: repository)
        let probe = AttachmentRuntimeProbe()

        _ = runtime.startDelivery(
            batch: makeBatch(),
            marker: makeMarker(),
            prepare: { .ready },
            preparePrompt: { _, _ in true },
            didUpload: { _, _ in probe.uploadCount += 1 },
            onOutcome: { probe.outcomes.append($0) },
            onStartTimeout: { _, _ in }
        )
        await eventuallyAsync { await repository.attachStarted }

        runtime.reset()
        await repository.releaseAttach()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(probe.uploadCount, 0)
        XCTAssertTrue(probe.outcomes.isEmpty)
    }

    private func makeRuntime(
        repository: AttachmentRuntimeRepository,
        startConfirmationDelay: Duration = .seconds(35)
    ) -> SessionAttachmentRuntime {
        SessionAttachmentRuntime(
            attachments: repository,
            prompts: repository,
            disconnector: repository,
            startConfirmationDelay: startConfirmationDelay
        )
    }

    private func makeBatch(
        id: String = "mutation"
    ) -> OutboundAttachmentBatch {
        OutboundAttachmentBatch(
            id: id,
            owner: ComposerDraftOwner(
                gatewayID: "gateway",
                storedSessionID: "stored"
            ),
            liveSessionID: "live",
            input: "describe",
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

    private func makeMarker(
        id: String = "mutation"
    ) -> AttachmentMutationMarker {
        let batch = makeBatch(id: id)
        return AttachmentMutationMarker(
            id: batch.id,
            gatewayID: batch.owner.gatewayID,
            storedSessionID: batch.owner.storedSessionID,
            liveSessionID: batch.liveSessionID,
            input: batch.input,
            attachments: batch.attachments,
            userEntryID: batch.userEntryID,
            userMessagesBefore: batch.userMessagesBefore,
            stage: .uploadPending
        )
    }

    private func assertFailure(
        _ outcome: SessionAttachmentRuntime.DeliveryOutcome,
        message: String,
        uncertain: Bool,
        stage: AttachmentMutationStage
    ) {
        guard case let .failed(_, marker, actualMessage, actualUncertain) =
            outcome else {
            return XCTFail("Expected failed delivery")
        }
        XCTAssertEqual(actualMessage, message)
        XCTAssertEqual(actualUncertain, uncertain)
        XCTAssertEqual(marker.stage, stage)
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class AttachmentRuntimeProbe {
    var outcomes: [SessionAttachmentRuntime.DeliveryOutcome] = []
    var uploads: [(PendingAttachment, AttachedImage)] = []
    var promptTransitions: [
        (AttachmentMutationMarker, AttachmentMutationMarker)
    ] = []
    var timeouts: [(OutboundAttachmentBatch, AttachmentMutationMarker)] = []
    var uploadCount = 0
}

private actor AttachmentRuntimeRepository:
    HermesAttachmentMutating,
    HermesPromptServing,
    HermesDisconnectServing
{
    enum Call: Equatable, Sendable {
        case attach(liveSessionID: String, filename: String)
        case prompt(liveSessionID: String, text: String)
        case detach(liveSessionID: String, path: String)
        case disconnect
    }

    private let attachResult: Result<AttachedImage, HermesError>
    private let promptResult: Result<PromptSubmitStatus, HermesError>
    private let detachResult: Result<Bool, HermesError>
    private let blockAttach: Bool
    private let blockPrompt: Bool
    private var attachContinuation: CheckedContinuation<Void, Never>?
    private var promptContinuation: CheckedContinuation<Void, Never>?
    private(set) var calls: [Call] = []
    private(set) var attachStarted = false
    private(set) var promptStarted = false

    init(
        attachResult: Result<AttachedImage, HermesError> = .success(
            AttachedImage(path: "/runtime/photo.jpg", filename: "photo.jpg")
        ),
        promptResult: Result<PromptSubmitStatus, HermesError> =
            .success(.streaming),
        detachResult: Result<Bool, HermesError> = .success(true),
        blockAttach: Bool = false,
        blockPrompt: Bool = false
    ) {
        self.attachResult = attachResult
        self.promptResult = promptResult
        self.detachResult = detachResult
        self.blockAttach = blockAttach
        self.blockPrompt = blockPrompt
    }

    var disconnectCount: Int {
        calls.filter { $0 == .disconnect }.count
    }

    var promptCallCount: Int {
        calls.filter {
            if case .prompt = $0 { true } else { false }
        }.count
    }

    func disconnect() async {
        calls.append(.disconnect)
    }

    func attachImage(
        liveSessionID: String,
        base64: String,
        fileExtension: String,
        filename: String
    ) async throws -> AttachedImage {
        calls.append(.attach(liveSessionID: liveSessionID, filename: filename))
        attachStarted = true
        if blockAttach {
            await withCheckedContinuation { continuation in
                attachContinuation = continuation
            }
        }
        return try attachResult.get()
    }

    func detachImage(
        liveSessionID: String,
        path: String
    ) async throws -> Bool {
        calls.append(.detach(liveSessionID: liveSessionID, path: path))
        return try detachResult.get()
    }

    func submitPrompt(
        liveSessionID: String,
        text: String
    ) async throws -> PromptSubmitStatus {
        calls.append(.prompt(liveSessionID: liveSessionID, text: text))
        promptStarted = true
        if blockPrompt {
            await withCheckedContinuation { continuation in
                promptContinuation = continuation
            }
        }
        return try promptResult.get()
    }

    func releaseAttach() {
        attachContinuation?.resume()
        attachContinuation = nil
    }

    func releasePrompt() {
        promptContinuation?.resume()
        promptContinuation = nil
    }
}
