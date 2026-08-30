import Foundation
import Observation

@MainActor
@Observable
final class GatewayStatsRuntime {
    static let periodOptions = [7, 30, 90]

    struct Owner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String
    }

    var isSheetVisible = false
    var periodDays = 30
    var stats: GatewayStats?
    var heatmapDailyStats: [DailyGatewayStats]?
    var referenceDate: Date?
    var isLoadingStats = false
    var isLoadingHeatmap = false
    var error: String?

    private let repository: (any HermesGatewayStatsServing)?
    private var task: Task<Void, Never>?
    private var generation: Int64 = 0
    private var currentOwner: Owner?

    init(repository: (any HermesGatewayStatsServing)?) {
        self.repository = repository
    }

    isolated deinit {
        task?.cancel()
    }

    func setSheetVisible(
        _ visible: Bool,
        owner: Owner?
    ) {
        guard visible else {
            task?.cancel()
            task = nil
            generation &+= 1
            currentOwner = nil
            isSheetVisible = false
            isLoadingStats = false
            isLoadingHeatmap = false
            return
        }
        guard repository != nil, let owner else {
            return
        }
        currentOwner = owner
        isSheetVisible = true
        isLoadingStats = true
        isLoadingHeatmap = true
        error = nil
        load(clearExisting: false, refreshHeatmap: true)
    }

    func selectPeriod(_ days: Int) {
        guard isSheetVisible,
              Self.periodOptions.contains(days),
              days != periodDays else {
            return
        }
        periodDays = days
        stats = nil
        isLoadingStats = true
        error = nil
        load(
            clearExisting: true,
            refreshHeatmap: heatmapDailyStats == nil
        )
    }

    func refresh() {
        guard isSheetVisible else {
            return
        }
        load(clearExisting: false, refreshHeatmap: true)
    }

    func reset() {
        task?.cancel()
        task = nil
        generation &+= 1
        currentOwner = nil
        isSheetVisible = false
        periodDays = 30
        stats = nil
        heatmapDailyStats = nil
        isLoadingStats = false
        isLoadingHeatmap = false
        error = nil
    }

    private func load(
        clearExisting: Bool,
        refreshHeatmap: Bool
    ) {
        guard let repository,
              let owner = currentOwner else {
            return
        }
        task?.cancel()
        generation &+= 1
        let generation = generation
        let requestedDays = periodDays
        if clearExisting {
            stats = nil
        }
        isLoadingStats = true
        isLoadingHeatmap = refreshHeatmap
        error = nil
        task = Task { [weak self] in
            do {
                let stats = try await repository.gatewayStats(
                    days: requestedDays
                )
                if let self {
                    guard self.isCurrent(
                        owner: owner,
                        generation: generation
                    ), self.periodDays == requestedDays else {
                        return
                    }
                    self.stats = stats
                    self.isLoadingStats = false
                    self.error = nil
                }
            } catch is CancellationError {
                return
            } catch {
                if let self,
                   self.isCurrent(
                        owner: owner,
                        generation: generation
                   ), self.periodDays == requestedDays {
                    self.isLoadingStats = false
                    self.error = error.localizedDescription
                }
            }

            guard refreshHeatmap,
                  !Task.isCancelled else {
                if let self,
                   self.isCurrent(
                        owner: owner,
                        generation: generation
                   ) {
                    self.task = nil
                }
                return
            }
            do {
                let heatmap = try await repository.gatewayStats(days: 91)
                if let self {
                    guard self.isCurrent(
                        owner: owner,
                        generation: generation
                    ) else {
                        return
                    }
                    self.heatmapDailyStats = heatmap.daily
                    self.isLoadingHeatmap = false
                }
            } catch is CancellationError {
                return
            } catch {
                if let self {
                    guard self.isCurrent(
                        owner: owner,
                        generation: generation
                    ) else {
                        return
                    }
                    if self.heatmapDailyStats == nil {
                        self.heatmapDailyStats = self.stats?.daily
                    }
                    self.isLoadingHeatmap = false
                }
            }
            if let self,
               self.isCurrent(
                    owner: owner,
                    generation: generation
               ) {
                self.task = nil
            }
        }
    }

    private func isCurrent(
        owner: Owner,
        generation: Int64
    ) -> Bool {
        generation == self.generation
            && owner == currentOwner
            && isSheetVisible
    }
}
