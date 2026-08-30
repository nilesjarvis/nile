import SwiftUI

struct GatewayStatsSheet: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NileColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    periodControls
                    statsBody
                    if model.gatewayStats != nil,
                       let error = model.statsError {
                        Text("Refresh failed: \(error)")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.error)
                    }
                    Text(
                        "Token figures are local Hermes records, not provider billing. Auxiliary calls, retries, fallbacks, and some cache activity may be absent."
                    )
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 34)
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier(NileAccessibilityID.statsSheet)
        }
        .presentationBackground(NileColors.background)
        .presentationCornerRadius(NileRadii.window)
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(732)])
        .onChange(of: model.isStatsSheetVisible) { _, visible in
            if !visible {
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Activity & usage")
                    .font(NileTypography.titleLarge)
                    .foregroundStyle(NileColors.text)
                Text("Recorded across this Hermes profile")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }
            Spacer()
            if model.isLoadingStats, model.gatewayStats != nil {
                ProgressView()
                    .tint(NileColors.accent)
                    .controlSize(.small)
            }
        }
    }

    private var periodControls: some View {
        HStack(spacing: 8) {
            ForEach(SessionListModel.statsPeriodOptions, id: \.self) { days in
                Button {
                    model.selectStatsPeriod(days)
                } label: {
                    Text("\(days)d")
                        .font(NileTypography.bodySmall.weight(.semibold))
                        .foregroundStyle(
                            model.statsPeriodDays == days
                                ? NileColors.onAccent
                                : NileColors.muted
                        )
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(
                            model.statsPeriodDays == days
                                ? NileColors.accentStrong
                                : NileColors.panelAlt
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
                        .overlay {
                            if model.statsPeriodDays != days {
                                RoundedRectangle(cornerRadius: NileRadii.control)
                                    .strokeBorder(NileColors.border, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    model.statsPeriodDays == days ? .isSelected : []
                )
                .accessibilityIdentifier(
                    NileAccessibilityID.statsPeriod(days)
                )
            }
            Spacer()
            Button(action: model.refreshStats) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NileColors.muted)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingStats)
            .accessibilityLabel("Refresh statistics")
            .accessibilityIdentifier(NileAccessibilityID.statsRefresh)
        }
    }

    @ViewBuilder
    private var statsBody: some View {
        if let stats = model.gatewayStats {
            StatsContent(
                stats: stats,
                heatmapDaily: model.heatmapDailyStats ?? stats.daily,
                heatmapLoading: model.isLoadingHeatmap,
                referenceDate: model.statsReferenceDate
            )
        } else if model.isLoadingStats {
            ProgressView()
                .tint(NileColors.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        } else if let error = model.statsError {
            VStack(spacing: 10) {
                Text("Could not load statistics")
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.text)
                Text(error)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .multilineTextAlignment(.center)
                Button("Try again", action: model.refreshStats)
                    .buttonStyle(.plain)
                    .font(NileTypography.bodyMedium)
                    .foregroundStyle(NileColors.link)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .nileGlass(cornerRadius: NileRadii.card, tint: NileColors.panelAlt)
        } else {
            Text("No recorded activity for this period.")
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
                .padding(.vertical, 28)
        }
    }
}
