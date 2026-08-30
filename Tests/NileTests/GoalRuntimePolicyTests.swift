import XCTest
@testable import Nile

final class GoalRuntimePolicyTests: XCTestCase {
    func testStartAdmissionNormalizesInputAndPreservesBudget() {
        XCTAssertEqual(
            GoalRuntimePolicy.startAdmission(
                objective: "  Ship\n  the   release  ",
                maxTurns: 12,
                availability: .available,
                context: context(),
                currentGoal: nil
            ),
            .allowed(
                GoalStartAdmission(
                    objective: "Ship the release",
                    maxTurns: 12
                )
            )
        )
    }

    func testStartAdmissionKeepsSafetyChecksAndExactMessages() {
        XCTAssertEqual(
            GoalRuntimePolicy.startAdmission(
                objective: "Ship",
                maxTurns: nil,
                availability: .unavailable,
                context: context(isSending: true),
                currentGoal: nil
            ),
            .rejected(
                "Standing goals are unavailable on this Hermes profile."
            )
        )
        XCTAssertEqual(
            GoalRuntimePolicy.startAdmission(
                objective: "Ship",
                maxTurns: 101,
                availability: .available,
                context: context(),
                currentGoal: nil
            ),
            .rejected("Choose a turn budget between 1 and 100.")
        )
        XCTAssertEqual(
            GoalRuntimePolicy.startAdmission(
                objective: "Replace",
                maxTurns: nil,
                availability: .available,
                context: context(),
                currentGoal: goal(phase: .active)
            ),
            .rejected(
                "Pause and clear the current goal before replacing it."
            )
        )
    }

    func testResumeAndContinuationAdmissionStayDistinct() {
        XCTAssertEqual(
            GoalRuntimePolicy.resumeError(
                context: context(isUpdatingSessionControls: true),
                isMutating: false
            ),
            "Wait for the session setting to finish before resuming."
        )
        XCTAssertEqual(
            GoalRuntimePolicy.continuationDecision(
                context: context(isSending: true),
                isMutating: false
            ),
            .ignored
        )
        XCTAssertEqual(
            GoalRuntimePolicy.continuationDecision(
                context: context(hasPendingAttachments: true),
                isMutating: false
            ),
            .rejected(
                "Send or remove the queued photo before continuing the goal."
            )
        )
    }

    func testCompletionAndProgressReductionPreserveTurnCorrelation() {
        let active = goal(phase: .active, turnsUsed: 2, maxTurns: 3)
        let completion = GoalRuntimePolicy.assistantCompletion(
            goal: active,
            isFinalizing: true
        )
        XCTAssertEqual(completion.goal?.phase, .checking)
        XCTAssertEqual(completion.goal?.turnsUsed, 3)
        XCTAssertTrue(completion.shouldRefreshStatus)

        let streamingFinal = GoalRuntimePolicy.progress(
            goal: active,
            update: GoalProgressUpdate(
                phase: .finished,
                turnsUsed: 3,
                reason: "verified"
            ),
            isSending: true,
            isFinalizing: false
        )
        XCTAssertEqual(streamingFinal.goal.phase, .active)
        XCTAssertEqual(streamingFinal.goal.lastReason, "verified")
        XCTAssertTrue(streamingFinal.isFinalizing)
        XCTAssertFalse(streamingFinal.shouldRefreshStatus)

        let settledFinal = GoalRuntimePolicy.progress(
            goal: active,
            update: GoalProgressUpdate(
                phase: .finished,
                turnsUsed: 3
            ),
            isSending: false,
            isFinalizing: false
        )
        XCTAssertEqual(settledFinal.goal.phase, .checking)
        XCTAssertTrue(settledFinal.shouldRefreshStatus)
    }

    func testStatusReductionAndFailureClassificationFailClosed() {
        let active = goal(phase: .active)
        let paused = goal(phase: .paused)
        XCTAssertEqual(
            GoalRuntimePolicy.reconcileStatus(
                authoritative: paused,
                currentGoal: active,
                isFinalizing: true,
                isSessionSending: true
            ),
            GoalStatusReduction(goal: active, isFinalizing: false)
        )
        let checking = GoalRuntimePolicy.reconcileStatus(
            authoritative: active,
            currentGoal: nil,
            isFinalizing: true,
            isSessionSending: false
        )
        XCTAssertEqual(checking.goal?.phase, .checking)
        XCTAssertTrue(checking.isFinalizing)

        XCTAssertFalse(
            GoalRuntimePolicy.isUncertainMutationFailure(
                HermesError("rejected")
            )
        )
        XCTAssertTrue(
            GoalRuntimePolicy.isUncertainMutationFailure(
                HermesError("lost", isConnectionFailure: true)
            )
        )
        XCTAssertTrue(
            GoalRuntimePolicy.isUncertainMutationFailure(
                CocoaError(.fileReadUnknown)
            )
        )
    }

    private func context(
        isUpdatingSessionControls: Bool = false,
        isSending: Bool = false,
        isStopping: Bool = false,
        hasPendingAttachments: Bool = false,
        isAttaching: Bool = false
    ) -> GoalActionContext {
        GoalActionContext(
            owner: nil,
            isUpdatingSessionControls: isUpdatingSessionControls,
            isSending: isSending,
            isStopping: isStopping,
            hasPendingAttachments: hasPendingAttachments,
            isAttaching: isAttaching
        )
    }

    private func goal(
        phase: GoalPhase,
        turnsUsed: Int = 1,
        maxTurns: Int = 5
    ) -> HermesGoal {
        HermesGoal(
            objective: "Ship safely",
            phase: phase,
            turnsUsed: turnsUsed,
            maxTurns: maxTurns
        )
    }
}
