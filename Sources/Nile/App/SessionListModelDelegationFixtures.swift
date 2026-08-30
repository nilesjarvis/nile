#if DEBUG
@MainActor
extension SessionListModel {
    func installDelegationFixture(settled: Bool) {
        guard !hasSessionRepository,
              let gatewayID = currentGatewayID,
              let selectedSessionID,
              let liveSessionID = liveSession?.liveID else {
            return
        }
        runtimes.delegationRuntime.installFixture(
            .make(settled: settled),
            owner: DelegationOwner(
                gatewayID: gatewayID,
                storedSessionID: selectedSessionID
            ),
            liveSessionID: liveSessionID
        )
        syncDelegationUI()
    }

    func installAndroidVisualDelegationFixture() {
        guard !hasSessionRepository, liveSession != nil else {
            return
        }
        transcriptEntries = runtimes.delegationRuntime
            .installPresentationFixture(.androidVisual)
        isSending = true
    }
}
#endif
