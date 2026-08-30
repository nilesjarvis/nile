import XCTest
@testable import Nile

final class DomainModelsTests: XCTestCase {
    func testLiveSessionRequiresRunningAndAnActiveStatus() {
        let info = SessionInfo(model: nil, provider: nil)

        for status in [nil, "working", "waiting", "starting"] {
            let session = LiveSession(
                liveID: "live-1",
                storedID: "stored-1",
                info: info,
                messages: [],
                running: true,
                status: status,
                inflight: nil
            )
            XCTAssertTrue(session.turnInFlight, "Expected active status \(status ?? "nil")")
        }

        XCTAssertFalse(
            LiveSession(
                liveID: "live-1",
                storedID: nil,
                info: info,
                messages: [],
                running: true,
                status: "idle",
                inflight: nil
            ).turnInFlight
        )
        XCTAssertFalse(
            LiveSession(
                liveID: "live-1",
                storedID: nil,
                info: info,
                messages: [],
                running: false,
                status: "working",
                inflight: nil
            ).turnInFlight
        )
    }

    func testGoalLoopAliveMatchesAndroidPhases() {
        for phase in [GoalPhase.active, .checking, .waiting] {
            XCTAssertTrue(goal(phase).isLoopAlive)
        }
        XCTAssertFalse(goal(.paused).isLoopAlive)
        XCTAssertFalse(goal(.finished).isLoopAlive)
    }

    func testRecordedTokenTotalsExcludeCacheAndReasoning() {
        let totals = GatewayStatsTotals(
            inputTokens: 120,
            outputTokens: 30,
            cacheReadTokens: 1_000,
            reasoningTokens: 50,
            sessions: 2,
            apiCalls: 4,
            estimatedCostUSD: 0.5,
            actualCostUSD: 0.4
        )
        XCTAssertEqual(totals.recordedTokens, 150)
    }

    func testWireEnumsMatchPinnedHermesContract() {
        XCTAssertEqual(ApprovalChoice.allCases.map(\.rawValue), [
            "once",
            "session",
            "always",
            "deny",
        ])
        XCTAssertEqual(reasoningEffortOptions, [
            "none",
            "minimal",
            "low",
            "medium",
            "high",
            "xhigh",
            "max",
        ])
    }

    func testConnectionLostIsTheOnlySessionlessStreamEvent() {
        let event = HermesStreamEvent.connectionLost(
            message: "dropped",
            authRejected: false,
            retryable: true
        )
        XCTAssertEqual(event.sessionID, "")
        XCTAssertEqual(
            HermesStreamEvent.messageStart(sessionID: "live-1").sessionID,
            "live-1"
        )
    }

    func testRepositoryCapabilitiesRemainNarrowAndFailClosed() async {
        let service = UnavailableHermesCapabilities()
        let operations: [(message: String, call: () async throws -> Void)] = [
            (
                "Attachment downloads are unavailable for this repository",
                { _ = try await service.downloadAttachment(path: "x", maxBytes: 1) }
            ),
            (
                "Speech transcription is unavailable for this repository",
                {
                    _ = try await service.transcribeSpeech(
                        audio: RecordedAudio(mimeType: "audio/wav", bytes: Data())
                    )
                }
            ),
            (
                "Hermes voice settings are unavailable for this repository",
                { _ = try await service.getHermesVoiceConfig() }
            ),
            (
                "Slash commands are unavailable for this repository",
                { _ = try await service.commandsCatalog() }
            ),
            (
                "Model controls are unavailable for this repository",
                { _ = try await service.modelOptions() }
            ),
            (
                "Standing goals are unavailable for this repository",
                { _ = try await service.goalStatus(liveSessionID: "live") }
            ),
            (
                "Session usage is unavailable for this repository",
                { _ = try await service.sessionUsage(liveSessionID: "live") }
            ),
            (
                "Delegated-agent status is unavailable for this repository",
                { _ = try await service.delegationStatus() }
            ),
        ]

        for operation in operations {
            do {
                try await operation.call()
                XCTFail("Unavailable capability unexpectedly succeeded")
            } catch let error as HermesError {
                XCTAssertEqual(error.message, operation.message)
                XCTAssertFalse(error.retryable)
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    private func goal(_ phase: GoalPhase) -> HermesGoal {
        HermesGoal(
            objective: "Finish",
            phase: phase,
            turnsUsed: 1,
            maxTurns: 10,
            lastReason: nil,
            pausedReason: nil
        )
    }
}

private struct UnavailableHermesCapabilities:
    HermesAttachmentServing,
    HermesSpeechServing,
    HermesVoiceServing,
    HermesCommandServing,
    HermesModelServing,
    HermesGoalServing,
    HermesUsageServing,
    HermesDelegationServing
{}
