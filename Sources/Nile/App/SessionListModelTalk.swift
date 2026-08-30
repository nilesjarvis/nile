import Foundation

/// Model-facing Talk owner gating, voice routing, and submission projection.
///
/// `SessionTalkRuntime` retains mutable mode/turn state, recognition, transport,
/// response, speech, and relisten lifecycles. This extension binds that authority
/// to the displayed session without adding a repository or event-stream path.
@MainActor
extension SessionListModel {
    var talkBlockingPrompt: TranscriptBlockingPrompt? {
        transcriptEntries.reversed().compactMap {
            entry -> TranscriptBlockingPrompt? in
            guard case let .blockingPrompt(prompt) = entry,
                  prompt.status == .pending else {
                return nil
            }
            return prompt
        }.first
    }

    func beginRoutingVoiceEvents() {
        runtimes.voiceInputRuntime.beginRouting(
            consumeTalkEvent: { [weak self] event in
                guard let self else {
                    return true
                }
                return runtimes.talkRuntime.consumeVoiceEvent(
                    event,
                    environmentProvider: talkEnvironmentProvider(),
                    onSubmissionStarted: talkSubmissionStartedHandler(),
                    onSubmissionFailed: talkSubmissionFailedHandler(),
                    onError: talkErrorHandler()
                )
            },
            onComposerChanged: { [weak self] composer in
                self?.updateComposer(composer)
            },
            onError: { [weak self] message in
                self?.operationError = message
            }
        )
    }

    func startTalkMode() {
        runtimes.talkRuntime.start(
            voiceInputAvailable: voiceInputAvailable,
            environment: talkEnvironment(),
            otherVoiceActivity: runtimes.voiceInputRuntime.eventsAreEnabled
                || runtimes.voiceInputRuntime.isDraftListening
                || runtimes.voiceInputRuntime.isDraftTranscribing,
            onError: talkErrorHandler()
        )
    }

    func pauseTalkMode() {
        runtimes.talkRuntime.pause()
    }

    func resumeTalkMode() {
        runtimes.talkRuntime.resume(
            environmentProvider: talkEnvironmentProvider(),
            onError: talkErrorHandler()
        )
    }

    func interruptTalkSpeech() {
        runtimes.talkRuntime.interruptSpeech(
            remoteTurnActive: isSending,
            environmentProvider: talkEnvironmentProvider(),
            onStopRequested: { [weak self] in
                self?.stopActiveRun()
            }
        )
    }

    func endTalkMode() {
        runtimes.talkRuntime.end()
    }

    private func captureTalkOwner() -> TalkOwner? {
        guard let gatewayID = currentGatewayID,
              let selectedSessionID,
              let liveSession,
              liveSession.storedID == nil
                || liveSession.storedID == selectedSessionID else {
            return nil
        }
        return TalkOwner(
            connectionGeneration: Int64(gatewayGeneration),
            gatewayID: gatewayID,
            gatewayKey: gatewayID,
            selectedSessionID: selectedSessionID,
            transcriptSessionID: selectedSessionID,
            liveSessionID: liveSession.liveID
        )
    }

    private func canTalkListen(_ owner: TalkOwner) -> Bool {
        guard runtimes.lifecycleRuntime.isForeground,
              state == .loaded,
              captureTalkOwner() == owner,
              showsComposer,
              !isReadOnlySession,
              !isOpeningSession,
              !isAttaching,
              !isAttachmentDraftLocked,
              !isOpeningAttachment,
              !isSending,
              !isStopping,
              !composerIsBlocked,
              !isUpdatingSessionControls,
              composer.isBlank,
              pendingAttachments.isEmpty,
              !isCurrentAttachmentOwnerQuarantined else {
            return false
        }
        let status = activeStatuses[owner.selectedSessionID]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return status.map {
            !SessionClaimRuntime.busyStatuses.contains($0)
        } ?? true
    }

    private func talkEnvironment() -> SessionTalkRuntime.Environment {
        let owner = captureTalkOwner()
        return SessionTalkRuntime.Environment(
            owner: owner,
            canListen: owner.map(canTalkListen) ?? false,
            isForeground: runtimes.lifecycleRuntime.isForeground
        )
    }

    func talkEnvironmentProvider()
        -> SessionTalkRuntime.EnvironmentProvider {
        { [weak self] in
            self?.talkEnvironment() ?? SessionTalkRuntime.Environment(
                owner: nil,
                canListen: false,
                isForeground: false
            )
        }
    }

    func talkErrorHandler() -> SessionTalkRuntime.ErrorHandler {
        { [weak self] message in
            self?.operationError = message
        }
    }

    private func talkSubmissionStartedHandler()
        -> SessionTalkRuntime.SubmissionHandler {
        { [weak self] submission in
            self?.applyTalkSubmission(submission)
        }
    }

    private func talkSubmissionFailedHandler()
        -> SessionTalkRuntime.SubmissionFailureHandler {
        { [weak self] failure in
            self?.applyTalkSubmissionFailure(failure)
        }
    }

    private func applyTalkSubmission(
        _ submission: SessionTalkRuntime.Submission
    ) {
        let owner = submission.owner
        liveTranscript.beginTurn()
        transcriptEntries.append(
            .message(
                TranscriptMessage(
                    id: submission.entryID,
                    role: .user,
                    content: submission.text
                )
            )
        )
        isSending = true
        turnStartedAt = Date()
        activeTodos = nil
        activeStatuses[owner.selectedSessionID] = "working"
        beginBackgroundTurn(
            gatewayID: owner.gatewayID,
            storedSessionID: owner.selectedSessionID,
            liveSessionID: owner.liveSessionID
        )
    }

    private func applyTalkSubmissionFailure(
        _ failure: SessionTalkRuntime.SubmissionFailure
    ) {
        let owner = failure.owner
        if !failure.uncertain {
            stopBackgroundTurn(
                gatewayID: owner.gatewayID,
                liveSessionID: owner.liveSessionID
            )
        }
        guard captureTalkOwner() == owner else {
            return
        }
        if !failure.uncertain {
            if let entryID = failure.entryID {
                transcriptEntries.removeAll { entry in
                    guard case let .message(message) = entry else {
                        return false
                    }
                    return message.id == entryID
                }
            }
            isSending = false
            turnStartedAt = nil
            activeStatuses.removeValue(forKey: owner.selectedSessionID)
        }
        operationError = failure.message
    }
}
