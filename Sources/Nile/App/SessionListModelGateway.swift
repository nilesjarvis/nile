import Foundation

@MainActor
extension SessionListModel {
    func restoreAfterReconnect(
        gatewayID: String,
        preferredSessionID: String?
    ) async -> Bool {
        connectionPhase = .restoring
        await load(
            gatewayID: gatewayID,
            preferredSessionID: preferredSessionID ?? selectedSessionID
        )
        guard state == .loaded else {
            connectionPhase = .reconnecting
            return false
        }
        runtimes.lifecycleRuntime.reconcileStatuses(
            gatewayID: gatewayID,
            statuses: activeStatuses
        )
        connectionPhase = .online
        return true
    }

    func load(gatewayID: String, preferredSessionID: String?) async {
        guard hasSessionRepository else {
            return
        }
        let previousGatewayID = productionGatewayID
        if previousGatewayID == gatewayID,
           case .failed = state {
            // Retry the same gateway without clearing gateway-scoped terminal
            // provenance or successful Claim memory.
        } else if previousGatewayID == gatewayID {
            startRefreshingIfNeeded()
            return
        }
        let changedGateway = previousGatewayID != gatewayID
        if changedGateway, let previousGatewayID {
            runtimes.claimRuntime.reset()
            runtimes.renameRuntime.reset()
            cancelVoiceForOwnershipChange()
            runtimes.speechRuntime.stop()
            endTalkMode()
            runtimes.blockingPromptRuntime.reset()
            runtimes.composerRuntime.invalidateGateway(previousGatewayID)
            runtimes.composerRuntime.clearGatewayRecovery(previousGatewayID)
            runtimes.turnRuntime.reset()
            outboundTasks.values.forEach { $0.cancel() }
            outboundTasks.removeAll()
            runtimes.goalRuntime.reset()
            clearDelegationState()
        }
        gatewayGeneration += 1
        let loadGeneration = gatewayGeneration
        displayGeneration += 1
        resetSessionUsage()
        resetGatewayStats()
        runtimes.claimRuntime.cancelStatus()
        setLoadedGatewayID(gatewayID)
        let navigationOwner = SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: loadGeneration,
            gatewayID: gatewayID
        )
        if changedGateway {
            runtimes.navigationRuntime.resetGateway(owner: navigationOwner)
            runtimes.timelineRuntime.reset()
            clearSessionOwnership()
            sessions = []
            activeStatuses = [:]
            sessionsNeedingInput = []
            runtimes.pinRuntime.resetGateway(
                owner: SessionPinRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
            selectedSessionID = nil
            liveSession = nil
            storedMessages = []
            transcriptEntries = []
            sessionSwitchPresentation = nil
            activeTodos = nil
            composer = ""
            pendingAttachments = []
            isAttaching = false
            isAttachmentDraftLocked = false
            isSending = false
            isStopping = false
            turnStartedAt = nil
            attachedToExistingTurn = false
            liveTranscript.beginTurn()
            liveTranscript.clearCachedImages()
            runtimes.mediaRuntime.reset()
            runtimes.attachmentRuntime.reset()
            runtimes.attachmentPersistenceRuntime.resetQuarantine()
            runtimes.commandRuntime.resetGateway()
            runtimes.modelControlRuntime.resetGateway(
                owner: SessionModelControlRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
            isReadOnlySession = false
            runtimes.claimRuntime.reset()
            runtimes.renameRuntime.reset()
            operationError = nil
        }
        if !changedGateway {
            runtimes.navigationRuntime.synchronizeGateway(owner: navigationOwner)
            runtimes.commandRuntime.resetCompletions()
            runtimes.pinRuntime.synchronizeGateway(
                owner: SessionPinRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
            runtimes.modelControlRuntime.synchronizeGateway(
                owner: SessionModelControlRuntime.GatewayOwner(
                    gatewayGeneration: gatewayGeneration,
                    gatewayID: gatewayID
                )
            )
        }
        beginRoutingEventsIfNeeded()
        state = .loading
        let draftRestoreErrors: [String] = if changedGateway {
            await [
                restorePersistedDrafts(gatewayID: gatewayID),
                restorePersistedAttachmentState(gatewayID: gatewayID),
                restorePersistedSessionPins(gatewayID: gatewayID),
                restorePersistedModelPins(gatewayID: gatewayID),
            ].compactMap { $0 }
        } else {
            []
        }
        guard isCurrentGateway(gatewayID, generation: loadGeneration) else {
            return
        }
        do {
            async let directory = runtimes.navigationRuntime.loadDirectory(
                owner: navigationOwner
            )
            async let discoveredCatalog = runtimes.commandRuntime.fetchCatalog()
            let snapshot = try await directory
            guard isCurrentGateway(gatewayID, generation: loadGeneration) else {
                return
            }
            let fetched = snapshot.sessions
            sessions = fetched
            recordListedSessionOwnership(fetched)
            activeStatuses = snapshot.activeStatuses
            let catalog = await discoveredCatalog
            guard isCurrentGateway(gatewayID, generation: loadGeneration) else {
                return
            }
            runtimes.commandRuntime.applyCatalog(catalog)
            state = .loaded
            operationError = nil

            let initialID = preferredSessionID
                .flatMap { candidate in
                    fetched.contains(where: { $0.id == candidate }) ? candidate : nil
                }
                ?? fetched.first?.id
            if let initialID {
                await selectSession(id: initialID)
            } else {
                await presentUnavailableRecoveredDraft(
                    preferredSessionID: preferredSessionID,
                    gatewayID: gatewayID,
                    gatewayGeneration: loadGeneration,
                    navigationOwner: navigationOwner
                )
            }
            guard isCurrentGateway(gatewayID, generation: loadGeneration) else {
                return
            }
            if !draftRestoreErrors.isEmpty {
                operationError = draftRestoreErrors.joined(separator: "\n")
            }
            startRefreshingIfNeeded()
            reconcileDelegations()
        } catch is CancellationError {
            return
        } catch {
            if isCurrentGateway(gatewayID, generation: loadGeneration) {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func retry(gatewayID: String, preferredSessionID: String?) async {
        await load(
            gatewayID: gatewayID,
            preferredSessionID: preferredSessionID
        )
    }

    private func restorePersistedDrafts(gatewayID: String) async -> String? {
        do {
            try await runtimes.draftLifecycleRuntime.restore(
                gatewayID: gatewayID
            )
            return nil
        } catch {
            return "Nile could not restore protected drafts: \(error.localizedDescription)"
        }
    }

    private func restorePersistedModelPins(
        gatewayID: String
    ) async -> String? {
        await runtimes.modelControlRuntime.restorePins(
            owner: SessionModelControlRuntime.GatewayOwner(
                gatewayGeneration: gatewayGeneration,
                gatewayID: gatewayID
            )
        )
    }

    private func restorePersistedSessionPins(
        gatewayID: String
    ) async -> String? {
        await runtimes.pinRuntime.restorePins(
            owner: SessionPinRuntime.GatewayOwner(
                gatewayGeneration: gatewayGeneration,
                gatewayID: gatewayID
            )
        )
    }
}
