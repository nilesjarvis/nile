import XCTest
@testable import Nile

@MainActor
final class SharingConsentSessionTeardownTests: XCTestCase {
    func testWithdrawalSynchronouslyStopsVoiceAndRequiresSessionReopen() async {
        let repository = makeRepository()
        let voice = SessionVoiceInputStub()
        let speech = SessionSpeechOutputStub()
        let model = SessionListModel(
            repository: repository,
            voiceInput: voice,
            speechOutput: speech
        )
        await model.load(gatewayID: "gateway", preferredSessionID: "one")
        model.onAppForegroundChanged(true)
        model.updateComposer("Keep this unsent draft")
        model.startVoiceInput()
        XCTAssertEqual(voice.startCount, 1)
        let initialCancels = voice.cancelCount
        let initialStops = speech.stopCount

        model.stopForSharingConsentWithdrawal()

        XCTAssertGreaterThan(voice.cancelCount, initialCancels)
        XCTAssertGreaterThan(speech.stopCount, initialStops)
        XCTAssertFalse(model.runtimes.voiceInputRuntime.eventsAreEnabled)
        XCTAssertNil(model.liveSession)
        XCTAssertFalse(model.isSending)
        XCTAssertFalse(model.isOpeningSession)
        XCTAssertFalse(model.composerCanSend)
        XCTAssertEqual(model.composer, "Keep this unsent draft")
        XCTAssertEqual(model.connectionPhase, .failed)

        await model.load(gatewayID: "gateway", preferredSessionID: "one")

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.liveSession?.liveID, "live-one")
        XCTAssertEqual(model.composer, "Keep this unsent draft")
        let reopened = await repository.callCount("session.resume:one")
        XCTAssertEqual(reopened, 2)
    }

    func testWithdrawalEndsTalkBeforeViewDisappears() async {
        let repository = makeRepository()
        let voice = SessionVoiceInputStub()
        let model = SessionListModel(repository: repository, voiceInput: voice)
        await model.load(gatewayID: "gateway", preferredSessionID: "one")
        model.onAppForegroundChanged(true)
        model.startTalkMode()
        XCTAssertTrue(model.runtimes.talkRuntime.isActive)

        model.stopForSharingConsentWithdrawal()

        XCTAssertFalse(model.runtimes.talkRuntime.isActive)
        XCTAssertNil(model.talk)
        XCTAssertFalse(model.runtimes.voiceInputRuntime.eventsAreEnabled)
    }

    private func makeRepository() -> SessionRepositoryStub {
        SessionRepositoryStub(sessions: [
            HermesSession(
                id: "one", title: "One", preview: nil, source: "niles",
                messageCount: 0, startedAt: nil, lastMessageAt: nil
            ),
        ])
    }
}
