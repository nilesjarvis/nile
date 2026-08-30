#if DEBUG
@MainActor
extension SessionDelegationRuntime {
    func installFixture(
        _ fixture: SessionDelegationEventFixture,
        owner: DelegationOwner,
        liveSessionID: String
    ) {
        bindLiveSession(owner: owner, liveSessionID: liveSessionID)
        for event in fixture.events {
            handleEvent(
                gatewayID: owner.gatewayID,
                visibleStoredSessionID: owner.storedSessionID,
                visibleLiveSessionID: liveSessionID,
                liveSessionID: liveSessionID,
                kind: event.kind,
                data: event.data,
                onProjection: {}
            )
        }
        if fixture.marksParentCompleted {
            markParentCompleted(
                gatewayID: owner.gatewayID,
                visibleStoredSessionID: owner.storedSessionID,
                visibleLiveSessionID: liveSessionID,
                liveSessionID: liveSessionID,
                onProjection: {}
            )
        }
    }

    func installPresentationFixture(
        _ fixture: SessionDelegationPresentationFixture
    ) -> [TranscriptEntry] {
        turns = fixture.turns
        pinnedTurnID = fixture.pinnedTurnID
        return fixture.transcript
    }
}
#endif
