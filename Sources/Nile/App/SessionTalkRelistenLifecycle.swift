import Foundation

/// Owns delayed Talk relisten work independently from reply settlement.
@MainActor
final class SessionTalkRelistenRuntime {
    private let delay: Duration
    private var task: Task<Void, Never>?
    private var generation: Int64 = 0

    init(delay: Duration) {
        self.delay = delay
    }

    isolated deinit {
        task?.cancel()
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func replace(
        with operation: @escaping @MainActor () -> Void
    ) {
        cancel()
        let operationGeneration = generation
        task = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if generation == operationGeneration {
                    task = nil
                }
            }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            operation()
        }
    }
}

extension SessionTalkRuntime {
    func scheduleRelisten(
        _ request: TalkRelistenToken,
        environmentProvider: @escaping EnvironmentProvider,
        onError: @escaping ErrorHandler
    ) {
        relisten.replace { [weak self] in
            guard let self else {
                return
            }
            let environment = environmentProvider()
            handleRelistenDecision(
                coordinator.claimRelisten(
                    request,
                    currentOwner: environment.owner,
                    canListen: environment.canListen
                ),
                onError: onError
            )
        }
    }

    func handleRelistenDecision(
        _ decision: TalkRelistenDecision,
        onError: ErrorHandler
    ) {
        switch decision {
        case .start:
            publishState()
            resetInputPresentation()
            onError(nil)
            voice.startCapture(composer: "")
        case .invalidated:
            clearPresentation()
            resetInputPresentation()
        case .paused:
            publishState()
            resetInputPresentation()
        case .ignored:
            break
        }
    }

    func pauseAndScheduleResume(
        _ mode: TalkModeToken,
        message: String,
        environmentProvider: @escaping EnvironmentProvider,
        onError: @escaping ErrorHandler
    ) {
        guard coordinator.isCurrent(mode),
              coordinator.pause(mode, message: message) else {
            return
        }
        publishState()
        resetInputPresentation()
        relisten.replace { [weak self] in
            guard let self,
                  coordinator.isCurrent(mode) else {
                return
            }
            let environment = environmentProvider()
            handleRelistenDecision(
                coordinator.resume(
                    mode,
                    currentOwner: environment.owner,
                    canListen: environment.canListen
                ),
                onError: onError
            )
        }
    }

    func cancelRelisten() {
        relisten.cancel()
    }
}
