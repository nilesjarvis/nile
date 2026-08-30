import Foundation

/// Session-creation admission, protected draft handoff, and displayed-session
/// settlement.
///
/// SessionNavigationRuntime owns the create/list requests and
/// SessionCreationDraftRuntime owns protected draft migration. This bridge
/// applies their immutable outcomes without repository or Hermes event-stream
/// access; the core retains ownership coordination and ordered event routing.
@MainActor
extension SessionListModel {
    var canCreateSession: Bool {
        (hasSessionRepository || fixtureAllowsSessionCreation)
            && state == .loaded
            && connectionPhase == .online
            && !isOpeningSession
            && !isGoalMutating
    }

    var hasDraftWithoutOpenSession: Bool {
        liveSession == nil
            && !isReadOnlySession
            && (
                !composer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    || !pendingAttachments.isEmpty
            )
    }

    func createSession() async {
        guard hasSessionRepository || fixtureAllowsSessionCreation,
              state == .loaded,
              connectionPhase == .online,
              !isOpeningSession else {
            return
        }
        guard !isUpdatingSessionControls else {
            operationError =
                "Wait for the model setting to finish before creating a session."
            return
        }
        guard !isGoalMutating else {
            operationError =
                "Wait for the goal update to finish before creating a session."
            return
        }
        guard !isAttaching else {
            operationError =
                "Wait for the photo to finish before creating a session."
            return
        }
        guard hasSessionRepository else {
            guard fixtureAllowsSessionCreation else {
                return
            }
            createFixtureSession()
            return
        }
        runtimes.renameRuntime.reset()
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        endTalkMode()
        resetSessionUsage()
        let outgoingDraftOwner = currentDraftOwner()
        let outgoingDraftClaim = outgoingDraftOwner.flatMap {
            runtimes.draftLifecycleRuntime.record(for: $0)
        }
        var recoveredCreationDraft =
            liveSession == nil
                ? outgoingDraftOwner.flatMap {
                    runtimes.creationDraftRuntime.capture(
                        owner: $0,
                        composer: composer,
                        attachments: pendingAttachments
                    )
                }
                : nil
        let displayToken = beginSessionDisplayRequest()
        let requestGatewayGeneration = gatewayGeneration
        guard let gatewayID = currentGatewayID else {
            return
        }
        let navigationOwner = SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: requestGatewayGeneration,
            gatewayID: gatewayID
        )
        isOpeningSession = true
        isAttachmentDraftLocked = recoveredCreationDraft != nil
        operationError = nil
        if let outgoingDraftOwner,
           !(await runtimes.draftLifecycleRuntime.flushClaim(
               owner: outgoingDraftOwner,
               claim: outgoingDraftClaim
           )) {
            guard displayToken == displayGeneration,
                  requestGatewayGeneration == gatewayGeneration else {
                return
            }
            isOpeningSession = false
            isAttachmentDraftLocked = false
            operationError =
                "Nile could not save this draft before creating a session."
            return
        }
        guard displayToken == displayGeneration,
              requestGatewayGeneration == gatewayGeneration else {
            return
        }
        if let draft = recoveredCreationDraft,
           draft.requiresPhotoPromotion {
            let promoted = await runtimes.creationDraftRuntime
                .promoteOrdinaryPhotoDraft(draft)
            guard displayToken == displayGeneration,
                  requestGatewayGeneration == gatewayGeneration else {
                return
            }
            guard let promoted else {
                isOpeningSession = false
                isAttachmentDraftLocked = false
                operationError =
                    "Nile could not safely save this draft, so no session was created."
                return
            }
            recoveredCreationDraft = promoted
        }
        do {
            let created = try await runtimes.navigationRuntime.createSession(
                owner: navigationOwner
            )
            guard displayToken == displayGeneration,
                  requestGatewayGeneration == gatewayGeneration else {
                return
            }
            if let recoveredCreationDraft {
                let migrated = await runtimes.creationDraftRuntime.migrate(
                    recoveredCreationDraft,
                    to: created,
                    commitGuard: { [weak self] in
                        guard let self else {
                            return false
                        }
                        return self.displayGeneration == displayToken
                            && self.gatewayGeneration
                                == requestGatewayGeneration
                    }
                )
                guard displayToken == displayGeneration,
                      requestGatewayGeneration == gatewayGeneration else {
                    return
                }
                guard migrated else {
                    isOpeningSession = false
                    isAttachmentDraftLocked = false
                    composer = recoveredCreationDraft.composer
                    pendingAttachments =
                        recoveredCreationDraft.attachments
                    operationError =
                        recoveredCreationDraft
                        .recoveredFromInterruptedMutation
                            ? "Could not safely move the recovered photo draft. Try creating the session again."
                            : "Could not safely move the unsent draft. Try creating the session again."
                    return
                }
            }
            liveSession = created
            selectedSessionID = created.storedID
            runtimes.goalRuntime.reset()
            if recoveredCreationDraft == nil {
                pendingAttachments = []
            }
            storedMessages = []
            applyLiveSessionTranscript(created)
            isReadOnlySession = false
            isAttachmentDraftLocked = false
            sessions = overlaySelectedLiveSession(on: sessions)
            refreshUsage()
            isExpanded = false
            let fetched = try await runtimes.navigationRuntime.listSessions(
                owner: navigationOwner
            )
            guard displayToken == displayGeneration,
                  requestGatewayGeneration == gatewayGeneration else {
                return
            }
            recordListedSessionOwnership(fetched)
            sessions = overlaySelectedLiveSession(on: fetched)
            if let storedID = created.storedID {
                await syncGoalState(
                    liveSessionID: created.liveID,
                    storedSessionID: storedID,
                    displayToken: displayToken,
                    gatewayGeneration: requestGatewayGeneration
                )
            }
            isOpeningSession = false
            state = .loaded
        } catch is CancellationError {
            if displayToken == displayGeneration,
               requestGatewayGeneration == gatewayGeneration {
                isOpeningSession = false
                isAttachmentDraftLocked = false
            }
            return
        } catch {
            guard displayToken == displayGeneration,
                  requestGatewayGeneration == gatewayGeneration else {
                return
            }
            isOpeningSession = false
            isAttachmentDraftLocked = false
            state = .loaded
            operationError = error.localizedDescription
        }
    }

    private func createFixtureSession() {
        runtimes.renameRuntime.reset()
        cancelVoiceForOwnershipChange()
        runtimes.speechRuntime.stop()
        endTalkMode()
        resetSessionUsage()
        _ = beginSessionDisplayRequest()
        operationError = nil
        let session = HermesSession(
            id: "fixture-created",
            title: "New session",
            preview: nil,
            source: "niles",
            messageCount: 0,
            startedAt: Date().timeIntervalSince1970,
            lastMessageAt: nil
        )
        let created = LiveSession(
            liveID: "live-fixture-created",
            storedID: session.id,
            info: SessionInfo(model: nil, provider: nil),
            messages: [],
            running: false,
            status: "idle",
            inflight: nil
        )
        sessions = [session] + sessions.filter { $0.id != session.id }
        recordListedSessionOwnership(sessions)
        liveSession = created
        selectedSessionID = session.id
        runtimes.goalRuntime.reset()
        pendingAttachments = []
        storedMessages = []
        applyLiveSessionTranscript(created)
        isReadOnlySession = false
        isExpanded = false
        state = .loaded
    }
}
