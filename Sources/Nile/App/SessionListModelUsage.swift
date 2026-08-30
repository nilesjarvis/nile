import Foundation

/// Displayed-session usage and gateway-statistics presentation integration.
///
/// The dedicated runtimes retain authenticated requests, task cancellation,
/// generations, and telemetry state. This extension owns only observable
/// forwarding, immutable owner capture, and lifecycle calls from the core model.
@MainActor
extension SessionListModel {
    static var statsPeriodOptions: [Int] {
        GatewayStatsRuntime.periodOptions
    }

    var usage: SessionUsage? {
        get { runtimes.usageRuntime.usage }
        set { runtimes.usageRuntime.usage = newValue }
    }

    var isContextSheetVisible: Bool {
        get { runtimes.usageRuntime.isContextSheetVisible }
        set { runtimes.usageRuntime.isContextSheetVisible = newValue }
    }

    var isStatsSheetVisible: Bool {
        get { runtimes.gatewayStatsRuntime.isSheetVisible }
        set { runtimes.gatewayStatsRuntime.isSheetVisible = newValue }
    }

    var statsPeriodDays: Int {
        get { runtimes.gatewayStatsRuntime.periodDays }
        set { runtimes.gatewayStatsRuntime.periodDays = newValue }
    }

    var gatewayStats: GatewayStats? {
        get { runtimes.gatewayStatsRuntime.stats }
        set { runtimes.gatewayStatsRuntime.stats = newValue }
    }

    var heatmapDailyStats: [DailyGatewayStats]? {
        get { runtimes.gatewayStatsRuntime.heatmapDailyStats }
        set { runtimes.gatewayStatsRuntime.heatmapDailyStats = newValue }
    }

    var statsReferenceDate: Date? {
        get { runtimes.gatewayStatsRuntime.referenceDate }
        set { runtimes.gatewayStatsRuntime.referenceDate = newValue }
    }

    var isLoadingStats: Bool {
        get { runtimes.gatewayStatsRuntime.isLoadingStats }
        set { runtimes.gatewayStatsRuntime.isLoadingStats = newValue }
    }

    var isLoadingHeatmap: Bool {
        get { runtimes.gatewayStatsRuntime.isLoadingHeatmap }
        set { runtimes.gatewayStatsRuntime.isLoadingHeatmap = newValue }
    }

    var statsError: String? {
        get { runtimes.gatewayStatsRuntime.error }
        set { runtimes.gatewayStatsRuntime.error = newValue }
    }

    func setContextSheetVisible(_ visible: Bool) {
        runtimes.usageRuntime.setContextSheetVisible(
            visible,
            owner: captureUsageOwner()
        )
    }

    func setStatsSheetVisible(_ visible: Bool) {
        runtimes.gatewayStatsRuntime.setSheetVisible(
            visible,
            owner: captureGatewayStatsOwner()
        )
    }

    func selectStatsPeriod(_ days: Int) {
        runtimes.gatewayStatsRuntime.selectPeriod(days)
    }

    func refreshStats() {
        runtimes.gatewayStatsRuntime.refresh()
    }

    func refreshUsage() {
        runtimes.usageRuntime.refreshUsage(owner: captureUsageOwner())
    }

    private func captureUsageOwner()
        -> SessionUsageRuntime.SessionOwner?
    {
        guard hasSessionRepository,
              let gatewayID = currentGatewayID,
              let storedSessionID = selectedSessionID,
              let liveSessionID = liveSession?.liveID,
              !isReadOnlySession else {
            return nil
        }
        return SessionUsageRuntime.SessionOwner(
            gatewayGeneration: gatewayGeneration,
            displayGeneration: displayGeneration,
            gatewayID: gatewayID,
            storedSessionID: storedSessionID,
            liveSessionID: liveSessionID
        )
    }

    private func captureGatewayStatsOwner()
        -> GatewayStatsRuntime.Owner?
    {
        guard hasSessionRepository,
              let gatewayID = currentGatewayID,
              state == .loaded else {
            return nil
        }
        return GatewayStatsRuntime.Owner(
            gatewayGeneration: gatewayGeneration,
            gatewayID: gatewayID
        )
    }

    func resetSessionUsage() {
        runtimes.usageRuntime.resetSessionUsage()
    }

    func resetGatewayStats() {
        runtimes.gatewayStatsRuntime.reset()
    }
}
