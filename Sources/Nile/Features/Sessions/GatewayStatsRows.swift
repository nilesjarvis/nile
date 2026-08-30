import SwiftUI

struct StatsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(NileTypography.titleMedium)
                .foregroundStyle(NileColors.text)
            Rectangle().fill(NileColors.border).frame(height: 1)
            content
        }
    }
}

struct DailyUsageRow: View {
    let day: DailyGatewayStats
    let maximum: Int64

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(formatStatsDate(day.day))
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .frame(width: 58, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NileColors.panelAlt)
                        if day.recordedTokens > 0 {
                            Capsule()
                                .fill(NileColors.accentStrong)
                                .frame(
                                    width: geometry.size.width
                                        * max(
                                            0.025,
                                            min(
                                                1,
                                                Double(day.recordedTokens)
                                                    / Double(maximum)
                                            )
                                        )
                                )
                        }
                    }
                }
                .frame(height: 7)
                Text(formatCompact(day.recordedTokens))
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.text)
                    .frame(width: 52, alignment: .trailing)
            }
            Text(
                "\(formatWhole(day.sessions)) sessions · "
                    + "\(formatWhole(day.apiCalls)) calls"
            )
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 68)
        }
    }
}

struct RankedUsageSection: View {
    let title: String
    let rows: [NamedUsageStat]

    var body: some View {
        StatsSection(title: title) {
            VStack(spacing: 11) {
                ForEach(
                    Array(rows.prefix(6).enumerated()),
                    id: \.offset
                ) { _, row in
                    NamedStatRow(
                        name: row.name,
                        detail: "\(formatWhole(row.count)) uses"
                    )
                }
            }
        }
    }
}

struct NamedStatRow: View {
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.text)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                .lineLimit(1)
        }
    }
}
