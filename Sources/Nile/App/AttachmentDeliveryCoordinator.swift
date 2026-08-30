/// Synchronous correlation owner for attachment uploads and prompt delivery.
///
/// Hermes RPC responses and stream events share a socket but can arrive in
/// either order. This coordinator never treats an `image.attach_bytes` path as
/// consumed until a correlated prompt start is observed. Known unconsumed paths
/// remain explicit leases; ambiguous upload/submit outcomes quarantine only the
/// exact gateway/session/runtime tuple.
struct AttachmentDeliveryCoordinator: Sendable {
    private var batches: [String: OutboundAttachmentBatch] = [:]
    private var dispatchedIDs: Set<String> = []
    private var acceptedIDs: Set<String> = []
    private var awaitingResponseIDs: Set<String> = []
    private var submitStatuses: [String: PromptSubmitStatus] = [:]
    private var bufferedStartIDs: Set<String> = []
    private var bufferedCompletionIDs: Set<String> = []
    private var bufferedErrors: [String: String] = [:]
    private var quarantineState = AttachmentDeliveryQuarantineState()

    mutating func track(_ batch: OutboundAttachmentBatch) {
        batches[batch.id] = batch
    }

    mutating func beginUpload(for batch: OutboundAttachmentBatch) {
        quarantineState.beginUpload(for: batch)
    }

    mutating func recordUploadedPath(
        _ path: String,
        for batch: OutboundAttachmentBatch
    ) -> ServerAttachmentLease {
        quarantineState.recordUploadedPath(path, for: batch)
    }

    mutating func finishDefinitelyRejectedUpload() {
        quarantineState.finishDefinitelyRejectedUpload()
    }

    @discardableResult
    mutating func interruptUpload() -> UncertainAttachmentRuntime? {
        quarantineState.interruptUpload()
    }

    mutating func addPromptUncertainty(for batch: OutboundAttachmentBatch) {
        quarantineState.addPromptUncertainty(for: batch)
    }

    mutating func beginSubmit(batchID: String) {
        guard batches[batchID] != nil else {
            return
        }
        dispatchedIDs.insert(batchID)
        awaitingResponseIDs.insert(batchID)
    }

    mutating func resolveSubmitResponse(
        batch: OutboundAttachmentBatch,
        status: PromptSubmitStatus
    ) -> AttachmentSubmitResolution {
        awaitingResponseIDs.remove(batch.id)
        submitStatuses[batch.id] = status
        let started = bufferedStartIDs.remove(batch.id) != nil
        let completed = bufferedCompletionIDs.remove(batch.id) != nil
        let error = bufferedErrors.removeValue(forKey: batch.id)

        if status == .streaming, started {
            accept(batch)
            return .streamingAccepted(
                turnEndedBeforeResponse: completed || error != nil
            )
        }
        if acceptedIDs.contains(batch.id) {
            return .previouslyAccepted
        }
        guard dispatchedIDs.contains(batch.id) else {
            return .noFollowUp
        }
        if status == .steered {
            return .steered(turnAlreadyCompleted: completed || error != nil)
        }
        if status == .streaming, let error {
            return .preStartError(error)
        }
        if status == .streaming || status == .queued {
            return .awaitStreamingStart
        }
        return .noFollowUp
    }

    mutating func acceptBufferedStart(
        for batch: OutboundAttachmentBatch
    ) -> Bool {
        guard bufferedStartIDs.remove(batch.id) != nil else {
            return false
        }
        awaitingResponseIDs.remove(batch.id)
        accept(batch)
        return true
    }

    mutating func stopAwaitingResponse(batchID: String) {
        awaitingResponseIDs.remove(batchID)
        bufferedErrors.removeValue(forKey: batchID)
    }

    mutating func onMessageStart(
        owner: ComposerDraftOwner,
        liveSessionID: String
    ) -> [OutboundAttachmentBatch] {
        let matching = batches.values.filter {
            $0.owner == owner
                && $0.liveSessionID == liveSessionID
                && dispatchedIDs.contains($0.id)
        }
        var accepted: [OutboundAttachmentBatch] = []
        for batch in matching {
            if awaitingResponseIDs.contains(batch.id) {
                bufferedStartIDs.insert(batch.id)
            } else if submitStatuses[batch.id] == .streaming
                || submitStatuses[batch.id] == .queued {
                accept(batch)
                accepted.append(batch)
            }
        }
        return accepted
    }

    mutating func onAssistantCompleted(liveSessionID: String) {
        for batch in batches.values where batch.liveSessionID == liveSessionID {
            if bufferedStartIDs.contains(batch.id)
                && awaitingResponseIDs.contains(batch.id)
                || submitStatuses[batch.id] == .steered {
                bufferedCompletionIDs.insert(batch.id)
            }
        }
    }

    mutating func onError(
        owner: ComposerDraftOwner,
        liveSessionID: String,
        message: String
    ) -> [OutboundAttachmentBatch] {
        let matching = batches.values.filter {
            $0.owner == owner
                && $0.liveSessionID == liveSessionID
                && dispatchedIDs.contains($0.id)
                && !acceptedIDs.contains($0.id)
        }
        for batch in matching where awaitingResponseIDs.contains(batch.id)
            || submitStatuses[batch.id] == .steered {
            bufferedErrors[batch.id] = message
        }
        return matching.filter {
            !awaitingResponseIDs.contains($0.id)
                && submitStatuses[$0.id] == .streaming
        }
    }

    mutating func accept(_ batch: OutboundAttachmentBatch) {
        acceptedIDs.insert(batch.id)
        dispatchedIDs.remove(batch.id)
        batches.removeValue(forKey: batch.id)
        bufferedErrors.removeValue(forKey: batch.id)
        quarantineState.removeLeases(forMutationID: batch.id)
    }

    mutating func retire(batchID: String) {
        batches.removeValue(forKey: batchID)
        dispatchedIDs.remove(batchID)
        acceptedIDs.remove(batchID)
        awaitingResponseIDs.remove(batchID)
        submitStatuses.removeValue(forKey: batchID)
        bufferedStartIDs.remove(batchID)
        bufferedCompletionIDs.remove(batchID)
        bufferedErrors.removeValue(forKey: batchID)
    }

    func batch(id: String) -> OutboundAttachmentBatch? {
        batches[id]
    }

    func trackedBatches(owner: ComposerDraftOwner? = nil) -> [OutboundAttachmentBatch] {
        batches.values.filter { owner == nil || $0.owner == owner }
    }

    func leases(forMutationID mutationID: String) -> [ServerAttachmentLease] {
        quarantineState.leases(forMutationID: mutationID)
    }

    func hasLease(_ lease: ServerAttachmentLease) -> Bool {
        quarantineState.hasLease(lease)
    }

    @discardableResult
    mutating func removeLease(_ lease: ServerAttachmentLease) -> Bool {
        quarantineState.removeLease(lease)
    }

    func hasUncertainty(owner: ComposerDraftOwner) -> Bool {
        quarantineState.hasUncertainty(owner: owner)
    }

    func uncertainties(owner: ComposerDraftOwner) -> [UncertainAttachmentRuntime] {
        quarantineState.uncertainties(owner: owner)
    }

    mutating func clearUncertainty(mutationID: String) {
        quarantineState.clearUncertainty(mutationID: mutationID)
    }

    func state(batchID: String) -> AttachmentBatchState {
        AttachmentBatchState(
            batch: batches[batchID],
            dispatched: dispatchedIDs.contains(batchID),
            accepted: acceptedIDs.contains(batchID),
            awaitingResponse: awaitingResponseIDs.contains(batchID),
            submitStatus: submitStatuses[batchID],
            bufferedStart: bufferedStartIDs.contains(batchID),
            bufferedCompletion: bufferedCompletionIDs.contains(batchID),
            bufferedError: bufferedErrors[batchID]
        )
    }
}
