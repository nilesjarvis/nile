struct AttachmentDeliveryQuarantineState: Sendable {
    private var leases: Set<ServerAttachmentLease> = []
    private var mutationIDsByLease: [ServerAttachmentLease: String] = [:]
    private var uploadInFlight: UncertainAttachmentRuntime?
    private var uncertainties: Set<UncertainAttachmentRuntime> = []

    mutating func beginUpload(for batch: OutboundAttachmentBatch) {
        uploadInFlight = UncertainAttachmentRuntime(
            mutationID: batch.id,
            owner: batch.owner,
            liveSessionID: batch.liveSessionID,
            kind: .uploadPath
        )
    }

    mutating func recordUploadedPath(
        _ path: String,
        for batch: OutboundAttachmentBatch
    ) -> ServerAttachmentLease {
        let lease = ServerAttachmentLease(
            owner: batch.owner,
            liveSessionID: batch.liveSessionID,
            path: path
        )
        leases.insert(lease)
        mutationIDsByLease[lease] = batch.id
        uploadInFlight = nil
        return lease
    }

    mutating func finishDefinitelyRejectedUpload() {
        uploadInFlight = nil
    }

    @discardableResult
    mutating func interruptUpload() -> UncertainAttachmentRuntime? {
        guard let uploadInFlight else {
            return nil
        }
        uncertainties.insert(uploadInFlight)
        self.uploadInFlight = nil
        return uploadInFlight
    }

    mutating func addPromptUncertainty(for batch: OutboundAttachmentBatch) {
        uncertainties.insert(
            UncertainAttachmentRuntime(
                mutationID: batch.id,
                owner: batch.owner,
                liveSessionID: batch.liveSessionID,
                kind: .promptOutcome
            )
        )
    }

    func leases(forMutationID mutationID: String) -> [ServerAttachmentLease] {
        leases.filter { mutationIDsByLease[$0] == mutationID }
    }

    func hasLease(_ lease: ServerAttachmentLease) -> Bool {
        leases.contains(lease)
    }

    @discardableResult
    mutating func removeLease(_ lease: ServerAttachmentLease) -> Bool {
        mutationIDsByLease.removeValue(forKey: lease)
        return leases.remove(lease) != nil
    }

    mutating func removeLeases(forMutationID mutationID: String) {
        let owned = leases.filter { mutationIDsByLease[$0] == mutationID }
        for lease in owned {
            _ = removeLease(lease)
        }
    }

    func hasUncertainty(owner: ComposerDraftOwner) -> Bool {
        uncertainties.contains { $0.owner == owner }
    }

    func uncertainties(
        owner: ComposerDraftOwner
    ) -> [UncertainAttachmentRuntime] {
        uncertainties.filter { $0.owner == owner }
    }

    mutating func clearUncertainty(mutationID: String) {
        uncertainties = Set(
            uncertainties.filter { $0.mutationID != mutationID }
        )
    }
}
