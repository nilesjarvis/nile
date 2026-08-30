import SwiftUI

struct ContributionHeatmap: View {
    let daily: [DailyGatewayStats]
    let isLoading: Bool
    let referenceDate: Date?

    private let weeks = 13
    private let daysPerWeek = 7

    var body: some View {
        let projection = HeatmapProjection(
            daily: daily,
            now: referenceDate ?? Date()
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 13 weeks")
                    .font(NileTypography.bodyMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                if isLoading {
                    ProgressView()
                        .tint(NileColors.accent)
                        .controlSize(.mini)
                }
                Spacer()
                Text(
                    "\(formatHeatmapDate(projection.start)) – "
                        + "\(formatHeatmapDate(projection.today))"
                )
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
            }
            .frame(height: 19.5)

            GeometryReader { geometry in
                let horizontalGap: CGFloat = 3.375
                let verticalGap: CGFloat = 3.125
                let labelWidth: CGFloat = 18
                let calculated = (
                    max(302.375, geometry.size.width)
                        - labelWidth
                        - horizontalGap * CGFloat(weeks)
                ) / CGFloat(weeks)
                let cell = min(18.5, max(8, calculated))
                HStack(alignment: .top, spacing: horizontalGap) {
                    VStack(spacing: verticalGap) {
                        ForEach(0..<daysPerWeek, id: \.self) { weekday in
                            Text(weekdayLabel(weekday))
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                                .frame(
                                    width: labelWidth,
                                    height: cell,
                                    alignment: .leading
                                )
                        }
                    }
                    HStack(spacing: horizontalGap) {
                        ForEach(0..<weeks, id: \.self) { week in
                            VStack(spacing: verticalGap) {
                                ForEach(0..<daysPerWeek, id: \.self) { day in
                                    let offset = week * daysPerWeek + day
                                    let date = projection.date(at: offset)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            date > projection.today
                                                ? Color.clear
                                                : heatmapColor(
                                                    projection.level(at: offset)
                                                )
                                        )
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 144)

            HStack(spacing: 3) {
                Spacer()
                Text("Less")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .padding(.trailing, 3)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(level))
                        .frame(width: 11, height: 11)
                }
                Text("More")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .padding(.leading, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(projection.accessibilityLabel)
        .accessibilityIdentifier(NileAccessibilityID.statsHeatmap)
    }

    private func weekdayLabel(_ index: Int) -> String {
        switch index {
        case 1: "M"
        case 3: "W"
        case 5: "F"
        default: ""
        }
    }
}

private func heatmapColor(_ level: Int) -> Color {
    switch level {
    case 1: NileColors.link.opacity(0.25)
    case 2: NileColors.link.opacity(0.45)
    case 3: NileColors.link.opacity(0.68)
    case 4: NileColors.link
    default: NileColors.panelAlt
    }
}
