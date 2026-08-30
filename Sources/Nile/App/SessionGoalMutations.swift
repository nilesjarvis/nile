import Foundation

extension SessionGoalRuntime {
    func start(
        objective: String,
        maxTurns: Int?,
        context: ActionContext,
        onPrompt: @escaping PromptHandler
    ) {
        guard let owner = prepareOwner(context.owner) else {
            return
        }
        let admission: GoalStartAdmission
        switch GoalRuntimePolicy.startAdmission(
            objective: objective,
            maxTurns: maxTurns,
            availability: availability,
            context: context,
            currentGoal: goal
        ) {
        case let .allowed(allowed):
            admission = allowed
        case let .rejected(message):
            error = message
            return
        }
        guard let repository else {
            goal = HermesGoal(
                objective: admission.objective,
                phase: .active,
                turnsUsed: 0,
                maxTurns: admission.maxTurns ?? 20
            )
            isSheetVisible = false
            onPrompt(owner, admission.objective)
            return
        }

        guard beginMutation(owner: owner, operation: { [weak self] token in
            do {
                let start = try await repository.setGoal(
                    liveSessionID: owner.liveSessionID,
                    objective: admission.objective,
                    maxTurns: admission.maxTurns
                )
                guard let self,
                      self.isCurrentMutation(owner: owner, token: token) else {
                    return
                }
                self.goal = start.goal
                self.availability = .available
                self.isSheetVisible = false
                self.finishMutation(owner: owner, token: token)
                onPrompt(owner, start.kickoffPrompt)
            } catch is CancellationError {
                self?.finishMutation(owner: owner, token: token)
            } catch {
                guard self?.isCurrentMutation(
                    owner: owner,
                    token: token
                ) == true else {
                    return
                }
                let recovered: HermesGoal?
                if GoalRuntimePolicy.isUncertainMutationFailure(error) {
                    recovered = await self?.status.recover(
                        liveSessionID: owner.liveSessionID
                    )
                } else {
                    recovered = nil
                }
                guard let self,
                      self.isCurrentMutation(owner: owner, token: token) else {
                    return
                }
                if let recovered {
                    self.goal = recovered
                    self.availability = .available
                    self.error =
                        "The goal was saved, but its first turn was not started. Tap Run next step."
                } else {
                    self.error = error.localizedDescription
                }
                self.finishMutation(
                    owner: owner,
                    token: token,
                    clearError: false
                )
            }
        }) else {
            return
        }
    }

    func pause(context: ActionContext) {
        guard let owner = prepareOwner(context.owner), !isMutating else {
            return
        }
        guard let repository else {
            if let goal {
                self.goal = GoalRuntimePolicy.replacingPhase(
                    goal,
                    with: .paused
                )
            }
            return
        }
        guard beginMutation(owner: owner, operation: { [weak self] token in
            do {
                let updated = try await repository.pauseGoal(
                    liveSessionID: owner.liveSessionID
                )
                self?.settleMutation(
                    updated,
                    operation: "pause",
                    owner: owner,
                    token: token
                )
            } catch is CancellationError {
                self?.finishMutation(owner: owner, token: token)
            } catch {
                self?.settleMutationFailure(
                    owner: owner,
                    token: token,
                    error: error
                )
            }
        }) else {
            return
        }
    }

    func resume(
        context: ActionContext,
        onPrompt: @escaping PromptHandler
    ) {
        guard let owner = prepareOwner(context.owner) else {
            return
        }
        if let message = GoalRuntimePolicy.resumeError(
            context: context,
            isMutating: isMutating
        ) {
            error = message
            return
        }
        guard let repository else {
            if let goal {
                self.goal = GoalRuntimePolicy.replacingPhase(
                    goal,
                    with: .active
                )
                isSheetVisible = false
                onPrompt(owner, goal.objective)
            }
            return
        }
        guard beginMutation(owner: owner, operation: { [weak self] token in
            do {
                let resumed = try await repository.resumeGoal(
                    liveSessionID: owner.liveSessionID
                )
                guard let self,
                      self.isCurrentMutation(owner: owner, token: token) else {
                    return
                }
                self.goal = resumed
                self.finishMutation(owner: owner, token: token)
                if let resumed {
                    self.isSheetVisible = false
                    onPrompt(owner, resumed.objective)
                } else {
                    self.error = "There is no goal to resume."
                }
            } catch is CancellationError {
                self?.finishMutation(owner: owner, token: token)
            } catch {
                self?.settleMutationFailure(
                    owner: owner,
                    token: token,
                    error: error
                )
            }
        }) else {
            return
        }
    }

    func continuePrompt(context: ActionContext) -> (Owner, String)? {
        guard let owner = prepareOwner(context.owner), let goal else {
            return nil
        }
        switch GoalRuntimePolicy.continuationDecision(
            context: context,
            isMutating: isMutating
        ) {
        case .allowed:
            break
        case .ignored:
            return nil
        case let .rejected(message):
            error = message
            return nil
        }
        isSheetVisible = false
        error = nil
        return (owner, goal.objective)
    }

    func clear(context: ActionContext) {
        guard let owner = prepareOwner(context.owner), !isMutating else {
            return
        }
        guard let repository else {
            goal = nil
            isSheetVisible = false
            error = nil
            return
        }
        guard beginMutation(owner: owner, operation: { [weak self] token in
            do {
                try await repository.clearGoal(
                    liveSessionID: owner.liveSessionID
                )
                guard let self,
                      self.isCurrentMutation(owner: owner, token: token) else {
                    return
                }
                self.goal = nil
                self.isSheetVisible = false
                self.isFinalizing = false
                self.finishMutation(owner: owner, token: token)
            } catch is CancellationError {
                self?.finishMutation(owner: owner, token: token)
            } catch {
                self?.settleMutationFailure(
                    owner: owner,
                    token: token,
                    error: error
                )
            }
        }) else {
            return
        }
    }
}
