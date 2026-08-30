import Foundation

/// Periodic directory refresh and owner-fenced display reconciliation tasks.
///
/// The core runtime remains the sole session capability, immutable-owner,
/// task, operation-ID, cancellation, and reset authority. This same-runtime
/// extension drives long-lived work without another repository owner or event
/// path.
@MainActor
extension SessionNavigationRuntime {
    func startRefreshing(sink: RefreshSink) {
        guard repository != nil, refreshTask == nil else {
            return
        }
        if let refreshTicks {
            refreshTask = Task { [weak self] in
                for await _ in refreshTicks {
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.refreshOnce(sink: sink)
                }
            }
        } else {
            refreshTask = Task { [weak self] in
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    do {
                        try await clock.sleep(for: .seconds(5))
                    } catch {
                        return
                    }
                    await self?.refreshOnce(sink: sink)
                }
            }
        }
    }

    func reconcileDisplay(
        owner: DisplayOwner,
        onSession: @escaping DisplayHandler
    ) {
        guard reconciliationTask == nil,
              currentGatewayOwner == owner.gatewayOwner,
              let repository else {
            return
        }
        let operationID = UUID()
        reconciliationID = operationID
        reconciliationTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.finishReconciliation(operationID) }
            do {
                let session = try await repository.openSession(
                    storedSessionID: owner.storedSessionID
                )
                guard !Task.isCancelled,
                      self.reconciliationID == operationID,
                      self.currentGatewayOwner == owner.gatewayOwner else {
                    return
                }
                onSession(owner, session)
            } catch {
                return
            }
        }
    }

    func refreshCompletedAttachedTurn(
        owner: DisplayOwner,
        onSession: @escaping DisplayHandler
    ) {
        guard currentGatewayOwner == owner.gatewayOwner,
              let repository else {
            return
        }
        cancelAttachedTurnRefresh()
        let operationID = UUID()
        attachedTurnRefreshID = operationID
        attachedTurnRefreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.finishAttachedTurnRefresh(operationID) }
            do {
                let session = try await repository.openSession(
                    storedSessionID: owner.storedSessionID
                )
                guard !Task.isCancelled,
                      self.attachedTurnRefreshID == operationID,
                      self.currentGatewayOwner == owner.gatewayOwner else {
                    return
                }
                onSession(owner, session)
            } catch {
                return
            }
        }
    }

    func cancelAttachedTurnRefresh() {
        attachedTurnRefreshTask?.cancel()
        attachedTurnRefreshTask = nil
        attachedTurnRefreshID = nil
    }

    func cancelDisplayTasks() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        reconciliationID = nil
        cancelAttachedTurnRefresh()
    }

    private func refreshOnce(sink: RefreshSink) async {
        guard let repository,
              let request = sink.request(),
              currentGatewayOwner == request.gatewayOwner else {
            return
        }
        guard let sessions = try? await repository.listSessions(limit: 50),
              currentGatewayOwner == request.gatewayOwner else {
            return
        }
        sink.sessions(request.gatewayOwner, sessions)

        let applyStatuses = sink.prepareStatuses(request.gatewayOwner)
        if let statuses = try? await repository.activeSessionStatuses(),
           currentGatewayOwner == request.gatewayOwner {
            applyStatuses(statuses)
        }

        guard let displayOwner = request.readOnlyDisplayOwner,
              currentGatewayOwner == displayOwner.gatewayOwner,
              let messages = try? await repository.readStoredSession(
                  storedSessionID: displayOwner.storedSessionID
              ),
              currentGatewayOwner == displayOwner.gatewayOwner else {
            return
        }
        sink.history(displayOwner, messages)
    }

    private func finishReconciliation(_ operationID: UUID) {
        guard reconciliationID == operationID else {
            return
        }
        reconciliationTask = nil
        reconciliationID = nil
    }

    private func finishAttachedTurnRefresh(_ operationID: UUID) {
        guard attachedTurnRefreshID == operationID else {
            return
        }
        attachedTurnRefreshTask = nil
        attachedTurnRefreshID = nil
    }

    func cancelAllTasks() {
        refreshTask?.cancel()
        refreshTask = nil
        cancelDisplayTasks()
    }
}
