import Foundation

/// Model/reasoning mutation admission, confirmation, and settlement.
///
/// The core runtime remains the sole stored-state, capability, task, generation,
/// and reset authority. This same-runtime extension drives that lifecycle
/// without introducing another runtime, repository owner, or event path.
@MainActor
extension SessionModelControlRuntime {
    func selectModel(
        _ model: String,
        provider: String,
        currentInfo: SessionInfo,
        owner: SessionOwner?,
        onApplied: @escaping AppliedHandler,
        onError: @escaping ErrorHandler
    ) {
        guard let owner else {
            onError(
                "Wait for this session to be idle before changing its model."
            )
            return
        }
        currentSessionOwner = owner
        let admission: ModelSelectionAdmission
        switch ModelControlPolicy.modelSelection(
            model: model,
            provider: provider,
            currentInfo: currentInfo,
            selectableProviders: selectableProviders
        ) {
        case let .apply(allowed):
            admission = allowed
        case .unchanged:
            setPickerVisible(false, owner: owner, onError: onError)
            return
        case let .rejected(message):
            onError(message)
            return
        }
        startModelSwitch(
            owner: owner,
            model: admission.model,
            provider: admission.provider,
            reasoningEffort: currentInfo.reasoningEffort,
            confirmExpensiveModel: false,
            onApplied: onApplied,
            onError: onError
        )
    }

    func setReasoningEffort(
        _ effort: String,
        currentInfo: SessionInfo,
        owner: SessionOwner?,
        onApplied: @escaping AppliedHandler,
        onError: @escaping ErrorHandler
    ) {
        guard currentInfo.reasoningEffortSessionScopeSupported else {
            onError(
                "Update Hermes before changing reasoning for this session."
            )
            return
        }
        guard let owner else {
            onError(
                "Wait for this session to be idle before changing reasoning."
            )
            return
        }
        currentSessionOwner = owner
        let normalized: String
        switch ModelControlPolicy.reasoningSelection(
            effort: effort,
            currentEffort: currentInfo.reasoningEffort
        ) {
        case let .apply(allowed):
            normalized = allowed
        case .unchanged:
            setPickerVisible(false, owner: owner, onError: onError)
            return
        case let .rejected(message):
            onError(message)
            return
        }
        controlTask?.cancel()
        controlGeneration &+= 1
        let generation = controlGeneration
        isUpdatingControls = true
        onError(nil)
        guard let repository else {
            return
        }
        controlTask = Task { [weak self] in
            do {
                let resolved = try await repository.setReasoningEffort(
                    liveSessionID: owner.liveSessionID,
                    effort: normalized
                )
                try Task.checkCancellation()
                guard let self,
                      self.isCurrentControlRequest(
                        owner: owner,
                        generation: generation
                      ) else {
                    return
                }
                self.isPickerVisible = false
                self.isUpdatingControls = false
                onError(nil)
                onApplied(
                    AppliedControl(
                        owner: owner,
                        model: currentInfo.model,
                        provider: currentInfo.provider,
                        reasoningEffort: resolved,
                        notice: ModelControlPolicy.reasoningNotice(resolved)
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrentControlRequest(
                        owner: owner,
                        generation: generation
                      ) else {
                    return
                }
                self.isUpdatingControls = false
                onError(error.localizedDescription)
            }
            if let self, self.controlGeneration == generation {
                self.controlTask = nil
            }
        }
    }

    func confirmModelSwitch(
        owner: SessionOwner?,
        currentInfo: SessionInfo,
        onApplied: @escaping AppliedHandler,
        onError: @escaping ErrorHandler
    ) {
        guard let owner,
              let pendingSwitch,
              pendingSwitch.owner == owner,
              currentSessionOwner == owner else {
            return
        }
        startModelSwitch(
            owner: owner,
            model: pendingSwitch.model,
            provider: pendingSwitch.provider,
            reasoningEffort: currentInfo.reasoningEffort,
            confirmExpensiveModel: true,
            onApplied: onApplied,
            onError: onError
        )
    }

    func dismissSwitchConfirmation(onError: @escaping ErrorHandler) {
        guard !isUpdatingControls else {
            return
        }
        pendingSwitch = nil
        switchConfirmation = nil
        onError(nil)
    }

    func canConfirmModelSwitch(owner: SessionOwner?) -> Bool {
        guard let owner, let pendingSwitch else {
            return false
        }
        return pendingSwitch.owner == owner && currentSessionOwner == owner
    }

    private func startModelSwitch(
        owner: SessionOwner,
        model: String,
        provider: String,
        reasoningEffort: String?,
        confirmExpensiveModel: Bool,
        onApplied: @escaping AppliedHandler,
        onError: @escaping ErrorHandler
    ) {
        guard currentSessionOwner == owner else {
            return
        }
        controlTask?.cancel()
        controlGeneration &+= 1
        let generation = controlGeneration
        isUpdatingControls = true
        onError(nil)
        guard let repository else {
            return
        }
        controlTask = Task { [weak self] in
            do {
                let outcome = try await repository.setSessionModel(
                    liveSessionID: owner.liveSessionID,
                    model: model,
                    provider: provider,
                    confirmExpensiveModel: confirmExpensiveModel
                )
                try Task.checkCancellation()
                guard let self,
                      self.isCurrentControlRequest(
                        owner: owner,
                        generation: generation
                      ) else {
                    return
                }
                switch outcome {
                case let .applied(resolvedModel, warning):
                    self.pendingSwitch = nil
                    self.switchConfirmation = nil
                    self.isPickerVisible = false
                    self.isUpdatingControls = false
                    onError(nil)
                    onApplied(
                        AppliedControl(
                            owner: owner,
                            model: resolvedModel,
                            provider: provider,
                            reasoningEffort: reasoningEffort,
                            notice: ModelControlPolicy.appliedModelNotice(
                                resolvedModel: resolvedModel,
                                warning: warning
                            )
                        )
                    )
                case let .confirmationRequired(resolvedModel, message):
                    self.pendingSwitch = PendingSwitch(
                        owner: owner,
                        model: resolvedModel,
                        provider: provider
                    )
                    self.switchConfirmation = ModelSwitchConfirmation(
                        model: resolvedModel,
                        provider: provider,
                        message: message
                    )
                    self.isPickerVisible = false
                    self.isUpdatingControls = false
                    onError(nil)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrentControlRequest(
                        owner: owner,
                        generation: generation
                      ) else {
                    return
                }
                let failure = ModelControlPolicy.mutationFailure(error)
                if failure.isUncertain {
                    self.isPickerVisible = false
                    self.pendingSwitch = nil
                    self.switchConfirmation = nil
                }
                self.isUpdatingControls = false
                onError(failure.message)
            }
            if let self, self.controlGeneration == generation {
                self.controlTask = nil
            }
        }
    }

    private func isCurrentControlRequest(
        owner: SessionOwner,
        generation: Int64
    ) -> Bool {
        generation == controlGeneration && currentSessionOwner == owner
    }
}

struct PendingSwitch: Sendable {
    let owner: SessionModelControlRuntime.SessionOwner
    let model: String
    let provider: String
}
