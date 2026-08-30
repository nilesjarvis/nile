import Foundation
import Observation

@MainActor
@Observable
final class SessionUsageRuntime {
    struct SessionOwner: Equatable, Sendable {
        let gatewayGeneration: Int
        let displayGeneration: Int
        let gatewayID: String
        let storedSessionID: String
        let liveSessionID: String
    }

    var usage: SessionUsage?
    var isContextSheetVisible = false

    private let repository: (any HermesSessionUsageServing)?
    private let usagePollInterval: Duration
    private let usageMaxAttempts: Int
    private var usageTask: Task<Void, Never>?
    private var usageGeneration: Int64 = 0
    private var currentSessionOwner: SessionOwner?

    init(
        repository: (any HermesSessionUsageServing)?,
        usagePollInterval: Duration = .milliseconds(1_200),
        usageMaxAttempts: Int = 600
    ) {
        self.repository = repository
        self.usagePollInterval = usagePollInterval
        self.usageMaxAttempts = max(1, usageMaxAttempts)
    }

    isolated deinit {
        usageTask?.cancel()
    }

    func setContextSheetVisible(
        _ visible: Bool,
        owner: SessionOwner?
    ) {
        guard visible else {
            isContextSheetVisible = false
            return
        }
        guard let owner else {
            return
        }
        isContextSheetVisible = true
        refreshUsage(owner: owner)
    }

    func refreshUsage(owner: SessionOwner?) {
        guard let repository, let owner else {
            return
        }
        usageTask?.cancel()
        usageGeneration &+= 1
        currentSessionOwner = owner
        let generation = usageGeneration
        let interval = usagePollInterval
        let attempts = usageMaxAttempts
        usageTask = Task { [weak self] in
            let clock = ContinuousClock()
            for attempt in 0..<attempts {
                guard !Task.isCancelled else {
                    return
                }
                let reading: SessionUsage?
                do {
                    reading = try await repository.sessionUsage(
                        liveSessionID: owner.liveSessionID
                    )
                } catch is CancellationError {
                    return
                } catch {
                    reading = nil
                }
                if let self {
                    guard self.isCurrentUsageRequest(
                        owner: owner,
                        generation: generation
                    ) else {
                        return
                    }
                    if let reading {
                        self.usage = reading
                        if reading.contextPercent != nil {
                            self.usageTask = nil
                            return
                        }
                    }
                } else {
                    return
                }
                guard attempt < attempts - 1 else {
                    break
                }
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
            }
            if let self,
               self.isCurrentUsageRequest(
                    owner: owner,
                    generation: generation
               ) {
                self.usageTask = nil
            }
        }
    }

    func resetSessionUsage() {
        usageTask?.cancel()
        usageTask = nil
        usageGeneration &+= 1
        currentSessionOwner = nil
        usage = nil
        isContextSheetVisible = false
    }

    private func isCurrentUsageRequest(
        owner: SessionOwner,
        generation: Int64
    ) -> Bool {
        generation == usageGeneration && owner == currentSessionOwner
    }

}
