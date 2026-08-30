import SwiftUI

struct GoalStatusCard: View {
    @Bindable var model: SessionListModel
    let goal: HermesGoal

    private var statusColor: Color {
        GoalPresentationPolicy.statusColor(
            for: goal,
            isFinalizing: model.isGoalFinalizing
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.setGoalSheetVisible(true)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.14))
                        NileGoalGlyph()
                            .stroke(statusColor, lineWidth: 2)
                            .padding(8)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.objective)
                            .font(
                                NileTypography.bodyMedium.weight(.medium)
                            )
                            .foregroundStyle(NileColors.text)
                            .lineLimit(1)
                        Text(statusSummary)
                            .font(NileTypography.labelMedium)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(NileAccessibilityID.goalCard)

            if model.isGoalMutating || model.isGoalFinalizing {
                ProgressView()
                    .tint(NileColors.accent)
                    .frame(width: 64, height: 44)
            } else {
                goalAction
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 66)
        .background(NileColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.card)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 3, y: 2)
    }

    @ViewBuilder
    private var goalAction: some View {
        switch goal.phase {
        case .paused:
            Button("Resume", action: model.resumeGoal)
                .buttonStyle(.plain)
                .foregroundStyle(NileColors.accent)
                .frame(width: 64, height: 44)
                .accessibilityIdentifier(NileAccessibilityID.goalResume)
        case .active, .checking, .waiting:
            Button("Pause", action: model.pauseGoal)
                .buttonStyle(.plain)
                .foregroundStyle(NileColors.accent)
                .frame(width: 64, height: 44)
                .accessibilityIdentifier(NileAccessibilityID.goalPause)
        case .finished:
            Text("View")
                .foregroundStyle(NileColors.accent)
                .frame(width: 64, height: 44)
        }
    }

    private var statusSummary: String {
        GoalPresentationPolicy.statusSummary(
            for: goal,
            isFinalizing: model.isGoalFinalizing
        )
    }
}

struct NileGoalGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = min(rect.width, rect.height)
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - diameter * 0.44,
                y: center.y - diameter * 0.44,
                width: diameter * 0.88,
                height: diameter * 0.88
            )
        )
        path.addEllipse(
            in: CGRect(
                x: center.x - diameter * 0.25,
                y: center.y - diameter * 0.25,
                width: diameter * 0.50,
                height: diameter * 0.50
            )
        )
        path.addEllipse(
            in: CGRect(
                x: center.x - diameter * 0.07,
                y: center.y - diameter * 0.07,
                width: diameter * 0.14,
                height: diameter * 0.14
            )
        )
        return path
    }
}
