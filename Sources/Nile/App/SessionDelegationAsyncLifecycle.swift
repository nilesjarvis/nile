import Foundation

/// Interrupt, snapshot, reconciliation, and persistence task execution.
///
/// The observable runtime remains the sole capability, coordinator, task,
/// generation, gateway, and presentation-state authority. This same-runtime
/// extension drives admitted asynchronous work without introducing another
/// repository owner or event path.
@MainActor
extension SessionDelegationRuntime {
    func interrupt(
        subagentID: String,
        gatewayID: String?,
        onProjection: @escaping ProjectionHandler
    ) {
        guard let gatewayID,
              gatewayID == activeGatewayID,
              let repository,
              let request = coordinator.beginInterrupt(
                  subagentID: subagentID
              ) else {
            return
        }
        controlError = nil
        onProjection()
        let taskID = UUID()
        let lifecycle = lifecycleGeneration
        tasks[taskID] = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.coordinator.completeInterrupt(request)
                self.tasks.removeValue(forKey: taskID)
            }
            do {
                let result = try await repository.interruptSubagent(
                    subagentID: request.subagentID
                )
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: gatewayID
                ), self.coordinator.applyInterruptResult(
                    request,
                    found: result.found
                ) else {
                    return
                }
                onProjection()
                if !result.found {
                    self.reconcile(
                        gatewayID: gatewayID,
                        onProjection: onProjection
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: gatewayID
                ), self.coordinator.applyInterruptFailure(
                    request,
                    uncertain: Self.isUncertainMutationFailure(error)
                ) else {
                    return
                }
                self.controlError = error.localizedDescription
                onProjection()
            }
        }
    }

    func loadSnapshots(
        owner: DelegationOwner,
        onProjection: @escaping ProjectionHandler
    ) {
        guard activateGateway(owner.gatewayID),
              let repository,
              coordinator.beginSnapshotLoad(owner: owner) else {
            return
        }
        let taskID = UUID()
        let lifecycle = lifecycleGeneration
        tasks[taskID] = Task { [weak self] in
            guard let self else {
                return
            }
            var completed = false
            defer {
                if !completed,
                   self.lifecycleGeneration == lifecycle {
                    self.coordinator.releaseSnapshotLoad(owner: owner)
                }
                self.tasks.removeValue(forKey: taskID)
            }
            do {
                let infos = try await repository.listDelegationSnapshots(
                    storedSessionID: owner.storedSessionID,
                    limit: retainedSettledDelegationTurns
                )
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: owner.gatewayID
                ) else {
                    return
                }
                for info in infos.reversed() {
                    do {
                        let snapshot = try await repository
                            .loadDelegationSnapshot(path: info.path)
                        guard self.isCurrent(
                            lifecycle: lifecycle,
                            gatewayID: owner.gatewayID
                        ) else {
                            return
                        }
                        self.coordinator.addSnapshot(
                            owner: owner,
                            path: info.path,
                            snapshot: snapshot
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        self.controlError = error.localizedDescription
                    }
                }
                self.coordinator.completeSnapshotLoad(owner: owner)
                completed = true
                onProjection()
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: owner.gatewayID
                ) else {
                    return
                }
                self.controlError = error.localizedDescription
            }
        }
    }

    func reconcile(
        gatewayID: String?,
        onProjection: @escaping ProjectionHandler
    ) {
        guard let gatewayID,
              activateGateway(gatewayID),
              let repository else {
            return
        }
        let reconciliation = coordinator.beginReconciliation(
            gatewayID: gatewayID
        )
        let lifecycle = lifecycleGeneration
        isReconciling = true
        let taskID = UUID()
        tasks[taskID] = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.tasks.removeValue(forKey: taskID)
                if self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: gatewayID
                ), self.coordinator.isCurrentReconciliation(reconciliation) {
                    self.isReconciling = false
                }
            }
            do {
                let active = try await repository.delegationStatus().active
                let activeByID = Dictionary(
                    active.map { ($0.subagentID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: gatewayID
                ), self.coordinator.applyReconciliation(
                    generation: reconciliation,
                    gatewayID: gatewayID,
                    currentGatewayID: self.activeGatewayID,
                    activeByID: activeByID
                ) else {
                    return
                }
                onProjection()
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: gatewayID
                ), self.coordinator.isCurrentReconciliation(reconciliation)
                else {
                    return
                }
                self.controlError = error.localizedDescription
            }
        }
    }

    func persist(
        _ snapshot: DelegationSnapshot?,
        owner: DelegationOwner
    ) {
        guard let snapshot, let repository else {
            return
        }
        let taskID = UUID()
        let lifecycle = lifecycleGeneration
        tasks[taskID] = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.tasks.removeValue(forKey: taskID)
            }
            do {
                _ = try await repository.saveDelegationSnapshot(snapshot)
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrent(
                    lifecycle: lifecycle,
                    gatewayID: owner.gatewayID
                ) else {
                    return
                }
                self.controlError = error.localizedDescription
            }
        }
    }

    private static func isUncertainMutationFailure(
        _ error: any Error
    ) -> Bool {
        guard let hermesError = error as? HermesError else {
            return true
        }
        return hermesError.retryable
    }
}
