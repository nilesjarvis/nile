import SwiftUI

struct StatsContent: View {
    let stats: GatewayStats
    let heatmapDaily: [DailyGatewayStats]
    let heatmapLoading: Bool
    let referenceDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MomentumCard(
                momentum: stats.activityMomentum(
                    today: referenceDate ?? Date()
                ),
                periodDays: stats.periodDays
            )
            SummaryGrid(stats: stats)
                .padding(.top, 2)

            StatsSection(title: "Recent activity") {
                VStack(alignment: .leading, spacing: 18) {
                    ContributionHeatmap(
                        daily: heatmapDaily,
                        isLoading: heatmapLoading,
                        referenceDate: referenceDate
                    )
                    let rows = stats.daily.sorted { $0.day < $1.day }
                        .suffix(7)
                    if !rows.isEmpty {
                        Text("Latest days")
                            .font(
                                NileTypography.bodySmall.weight(.semibold)
                            )
                            .foregroundStyle(NileColors.muted)
                        let maximum = max(
                            1,
                            rows.map(\.recordedTokens).max() ?? 1
                        )
                        VStack(spacing: 12) {
                            ForEach(Array(rows), id: \.day) { row in
                                DailyUsageRow(day: row, maximum: maximum)
                            }
                        }
                    }
                }
            }

            if !stats.models.isEmpty {
                StatsSection(title: "Models") {
                    VStack(spacing: 12) {
                        ForEach(
                            Array(stats.models.prefix(6)),
                            id: \.model
                        ) { model in
                            NamedStatRow(
                                name: model.model,
                                detail:
                                    "\(formatCompact(model.recordedTokens)) tokens · "
                                    + "\(formatWhole(model.apiCalls)) calls · "
                                    + "\(formatWhole(model.sessions)) sessions"
                            )
                        }
                    }
                }
            }
            if !stats.tools.isEmpty {
                RankedUsageSection(title: "Top tools", rows: stats.tools)
            }
            if !stats.skills.isEmpty {
                RankedUsageSection(title: "Top skills", rows: stats.skills)
            }
        }
    }
}
