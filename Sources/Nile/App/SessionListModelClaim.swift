import Foundation

/// Displayed-session Claim presentation integration.
///
/// SessionClaimRuntime retains authenticated status/open requests, tasks,
/// generations, and dialog lifecycle. This extension owns UI-facing owner
/// capture and outcome forwarding. Successful state still crosses the guarded
/// gateway-context bridge before session projection changes.
@MainActor
extension SessionListModel {
    var isClaimDialogVisible: Bool {
        runtimes.claimRuntime.isDialogVisible
    }

    var isClaimingSession: Bool {
        runtimes.claimRuntime.isClaiming
    }

    func setClaimDialogVisible(_ visible: Bool) {
        let owner = captureClaimOwner(
            displayGeneration: displayGeneration,
            requiresIdlePresentation: true
        )
        runtimes.claimRuntime.setDialogVisible(
            visible,
            owner: owner,
            isCurrentOwner: claimOwnerValidator(),
            onStatus: { [weak self] status in
                guard let owner else {
                    return
                }
                self?.applyActiveStatus(
                    status,
                    storedSessionID: owner.storedSessionID
                )
            }
        )
    }

    func claimCurrentSession() async {
        guard hasSessionRepository,
              currentGatewayID != nil,
              state == .loaded,
              isReadOnlySession,
              let storedSessionID = selectedSessionID,
              !isOpeningSession,
              !isClaimingSession else {
            return
        }
        let displayToken = beginSessionDisplayRequest()
        let requestGatewayGeneration = gatewayGeneration
        guard let gatewayID = currentGatewayID else {
            return
        }
        let owner = SessionClaimRuntime.Owner(
            gatewayGeneration: requestGatewayGeneration,
            displayGeneration: displayToken,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID
        )
        isOpeningSession = true
        operationError = nil
        let outcome = await runtimes.claimRuntime.claim(
            owner: owner,
            isCurrentOwner: claimOwnerValidator(),
            onStatus: { [weak self] status in
                self?.applyActiveStatus(
                    status,
                    storedSessionID: storedSessionID
                )
            }
        )
        switch outcome {
        case let .succeeded(resumed):
            _ = applyClaimedSession(resumed, owner: owner)
        case .cancelled:
            if isCurrentClaimOwner(owner) {
                isOpeningSession = false
            }
        case let .failed(message):
            guard isCurrentClaimOwner(owner) else {
                return
            }
            isOpeningSession = false
            operationError = message
            state = .loaded
        case .stale:
            return
        }
    }

    private func captureClaimOwner(
        displayGeneration: Int,
        requiresIdlePresentation: Bool
    ) -> SessionClaimRuntime.Owner? {
        guard ((hasSessionRepository
                    && currentGatewayID != nil
                    && state == .loaded)
                || !hasSessionRepository),
              isReadOnlySession,
              let gatewayID = currentGatewayID,
              let selectedSessionID,
              (!requiresIdlePresentation || !isOpeningSession),
              !isClaimingSession else {
            return nil
        }
        return SessionClaimRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayID,
            storedSessionID: selectedSessionID
        )
    }

    private func isCurrentClaimOwner(
        _ owner: SessionClaimRuntime.Owner
    ) -> Bool {
        owner.gatewayGeneration == gatewayGeneration
            && owner.displayGeneration == displayGeneration
            && owner.gatewayID == currentGatewayID
            && owner.storedSessionID == selectedSessionID
            && isReadOnlySession
    }

    private func claimOwnerValidator()
        -> SessionClaimRuntime.OwnerValidator {
        { [weak self] owner in
            self?.isCurrentClaimOwner(owner) ?? false
        }
    }
}
