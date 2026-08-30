import SwiftUI

struct MomentumCard: View {
    let momentum: ActivityMomentum
    let periodDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Momentum")
                .font(NileTypography.titleMedium.weight(.semibold))
                .foregroundStyle(NileColors.text)
            Text(
                momentum.currentStreak > 0
                    ? "\(momentum.currentStreak) day active streak"
                    : "Start a new active streak"
            )
            .font(NileTypography.bodyLarge.weight(.semibold))
            .foregroundStyle(NileColors.accent)
            Text(
                "\(momentum.activeDays) active days in the last "
                    + "\(periodDays) · longest streak "
                    + "\(momentum.longestStreak) days"
            )
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.muted)
            Rectangle().fill(NileColors.border).frame(height: 1)
            Text(
                "This week · \(formatWhole(momentum.weeklySessions)) sessions · "
                    + "\(formatWhole(momentum.weeklyCalls)) calls"
            )
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.text)
            if momentum.bestDaySessions > 0 {
                Text(
                    "Personal best · "
                        + "\(formatWhole(momentum.bestDaySessions)) sessions in one day"
                )
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 161,
            alignment: .topLeading
        )
        .nilePanel()
    }
}

struct SummaryGrid: View {
    let stats: GatewayStats

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metric(
                    label: "Recorded tokens",
                    value: formatCompact(stats.totals.recordedTokens),
                    detail:
                        "\(formatCompact(stats.totals.inputTokens)) in · "
                        + "\(formatCompact(stats.totals.outputTokens)) out"
                )
                metric(
                    label: "Sessions",
                    value: formatWhole(stats.totals.sessions),
                    detail: "last \(stats.periodDays) days"
                )
            }
            HStack(spacing: 10) {
                metric(
                    label: "Model calls",
                    value: formatWhole(stats.totals.apiCalls),
                    detail: "successful recorded calls"
                )
                metric(
                    label: "Cache reads",
                    value: formatCompact(stats.totals.cacheReadTokens),
                    detail:
                        "\(formatCompact(stats.totals.reasoningTokens)) reasoning"
                )
            }
        }
    }

    private func metric(
        label: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
            Text(value)
                .font(NileTypography.bodyLarge.weight(.semibold))
                .foregroundStyle(NileColors.text)
            Text(detail)
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(NileColors.inset)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.small)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
    }
}
