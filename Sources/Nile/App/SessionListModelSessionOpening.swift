import Foundation

/// Resolves and applies one authenticated production session opening.
/// Local selection reset and fixture projection remain in the navigation bridge.
@MainActor
extension SessionListModel {
    struct SessionOpeningRequest: Sendable {
        let session: HermesSession
        let displayToken: Int
        let gatewayGeneration: Int
        let gatewayID: String
        let settlingIncomingContent: Bool
    }

    func openProductionSession(_ request: SessionOpeningRequest) async {
        let session = request.session
        let id = session.id
        let navigationOwner = SessionNavigationRuntime.GatewayOwner(
            gatewayGeneration: request.gatewayGeneration,
            gatewayID: request.gatewayID
        )

        do {
            let route = try await displayRoute(
                for: session,
                owner: navigationOwner
            )
            guard isCurrentDisplayRequest(
                request.displayToken,
                sessionID: id,
                gatewayGeneration: request.gatewayGeneration
            ) else {
                return
            }
            switch route {
            case .terminalHistory:
                recordTerminalSessionOwnership(storedSessionID: id)
                isReadOnlySession = true
                let messages = try await runtimes.navigationRuntime
                    .readStoredSession(
                        storedSessionID: id,
                        owner: navigationOwner
                    )
                guard isCurrentDisplayRequest(
                    request.displayToken,
                    sessionID: id,
                    gatewayGeneration: request.gatewayGeneration
                ) else {
                    return
                }
                storedMessages = messages
                liveSession = nil
                applyStoredTranscript(messages)
            case .live:
                isReadOnlySession = false
                if try await runtimes.attachmentRecoveryRuntime
                    .reconcileStoredMutations(
                        owner: ComposerDraftOwner(
                            gatewayID: request.gatewayID,
                            storedSessionID: id
                        ),
                        navigationOwner: navigationOwner
                    ) {
                    let messages = try await runtimes.navigationRuntime
                        .readStoredSession(
                            storedSessionID: id,
                            owner: navigationOwner
                        )
                    guard isCurrentDisplayRequest(
                        request.displayToken,
                        sessionID: id,
                        gatewayGeneration: request.gatewayGeneration
                    ) else {
                        return
                    }
                    storedMessages = messages
                    liveSession = nil
                    applyStoredTranscript(messages)
                    operationError = Self.attachmentQuarantineMessage
                    finishSessionDisplay(
                        settlingIncomingContent:
                            request.settlingIncomingContent
                    )
                    state = .loaded
                    return
                }
                let opened = try await runtimes.navigationRuntime.openSession(
                    storedSessionID: id,
                    owner: navigationOwner
                )
                guard isCurrentDisplayRequest(
                    request.displayToken,
                    sessionID: id,
                    gatewayGeneration: request.gatewayGeneration
                ) else {
                    return
                }
                storedMessages = []
                if !restoreCachedLiveTimeline(
                    storedSessionID: id,
                    resumed: opened
                ) {
                    liveSession = opened
                    applyLiveSessionTranscript(opened)
                }
                refreshUsage()
                await syncGoalState(
                    liveSessionID: opened.liveID,
                    storedSessionID: id,
                    displayToken: request.displayToken,
                    gatewayGeneration: request.gatewayGeneration
                )
            case .needsSourceLookup:
                throw HermesError(
                    "Could not determine who owns the stored session",
                    retryable: false
                )
            }
            guard isCurrentDisplayRequest(
                request.displayToken,
                sessionID: id,
                gatewayGeneration: request.gatewayGeneration
            ) else { return }
            finishSessionDisplay(
                settlingIncomingContent: request.settlingIncomingContent
            )
            state = .loaded
        } catch is CancellationError {
            if isCurrentDisplayRequest(
                request.displayToken,
                sessionID: id,
                gatewayGeneration: request.gatewayGeneration
            ) {
                isOpeningSession = false
                sessionSwitchPresentation = nil
            }
        } catch {
            guard isCurrentDisplayRequest(
                request.displayToken,
                sessionID: id,
                gatewayGeneration: request.gatewayGeneration
            ) else {
                return
            }
            liveSession = nil
            isOpeningSession = false
            sessionSwitchPresentation = nil
            state = .loaded
            operationError = error.localizedDescription
        }
    }

    private func displayRoute(
        for session: HermesSession,
        owner: SessionNavigationRuntime.GatewayOwner
    ) async throws -> SessionDisplayRoute {
        let route = sessionDisplayRoute(for: session)
        guard route == .needsSourceLookup else {
            return route
        }
        guard let source = try await runtimes.navigationRuntime
            .readStoredSessionSource(
                storedSessionID: session.id,
                owner: owner
            ), !source.isBlank else {
            throw HermesError(
                "Could not determine who owns the stored session",
                retryable: false
            )
        }
        if ["cli", "tui", "terminal"].contains(
            source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) {
            return .terminalHistory
        }
        return .live
    }
}
