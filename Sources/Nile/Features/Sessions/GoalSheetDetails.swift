import SwiftUI

/// Active-goal details and action presentation for the sole `GoalSheet`.
///
/// Creation state and modal ownership remain in the core sheet. This extension
/// adds no stored state, model owner, transport path, or competing presentation.
extension GoalSheet {
    func goalDetails(_ goal: HermesGoal) -> some View {
        let statusColor = GoalPresentationPolicy.statusColor(
            for: goal,
            isFinalizing: model.isGoalFinalizing
        )
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NileGoalGlyph()
                    .stroke(statusColor, lineWidth: 2)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    composeText(
                        "Standing goal",
                        style: NileTypography.titleLargeSemiboldStyle,
                        color: NileColors.text
                    )
                    composeText(
                        GoalPresentationPolicy.statusSummary(
                            for: goal,
                            isFinalizing: model.isGoalFinalizing
                        ),
                        style: NileTypography.labelMediumStyle,
                        color: statusColor
                    )
                }
            }

            Button {
                objectiveExpanded.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    composeText(
                        "Objective",
                        style: NileTypography.labelMediumStyle,
                        color: NileColors.muted,
                        backgroundColor: NileColors.surfaceRaised
                    )
                    Text(goal.objective)
                        .font(NileTypography.bodyLarge)
                        .foregroundStyle(NileColors.text)
                        .lineLimit(objectiveExpanded ? nil : 4)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    composeText(
                        objectiveExpanded
                            ? "Collapse objective"
                            : "Show full objective",
                        style: NileTypography.labelMediumStyle,
                        color: NileColors.link,
                        backgroundColor: NileColors.surfaceRaised
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.vertical, 3)
                .nilePanel()
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                objectiveExpanded ? "Expanded" : "Collapsed"
            )
            .accessibilityIdentifier(
                NileAccessibilityID.goalDetailsObjective
            )

            if let reason = goal.lastReason {
                VStack(alignment: .leading, spacing: 4) {
                    composeText(
                        "Latest check",
                        style: NileTypography.labelMediumStyle,
                        color: NileColors.muted,
                        backgroundColor: NileColors.surfaceRaised
                    )
                    composeText(
                        reason,
                        style: NileTypography.bodyMediumStyle,
                        color: NileColors.text,
                        backgroundColor: NileColors.surfaceRaised
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.vertical, 1)
                .nilePanel()
            }

            goalError
            Rectangle()
                .fill(NileColors.border)
                .frame(height: 1)
                .padding(.bottom, 5.67)

            if model.isGoalFinalizing {
                HStack(spacing: 9) {
                    ProgressView().tint(NileColors.accent)
                    Text("Confirming the final result…")
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(NileColors.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                if goal.phase == .paused {
                    primaryGoalButton(
                        "Resume and run next step",
                        action: model.resumeGoal,
                        id: NileAccessibilityID.goalResume
                    )
                } else if [.active, .checking, .waiting].contains(goal.phase) {
                    outlinedGoalButton(
                        "Pause automatic turns",
                        action: model.pauseGoal,
                        id: NileAccessibilityID.goalPause
                    )
                }
                if goal.phase == .active, !model.isSending {
                    primaryGoalButton(
                        "Run next step",
                        action: model.continueGoal,
                        id: NileAccessibilityID.goalContinue
                    )
                }
                Button {
                    model.clearGoal()
                } label: {
                    composeText(
                        goal.phase == .finished
                            ? "Clear finished goal"
                            : "Stop and clear goal",
                        style: NileTypography.materialLabelLargeStyle,
                        color: NileColors.error
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .disabled(model.isGoalMutating)
                .accessibilityIdentifier(NileAccessibilityID.goalClear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    private func primaryGoalButton(
        _ title: String,
        action: @escaping () -> Void,
        id: String
    ) -> some View {
        Button(action: action) {
            composeText(
                title,
                style: NileTypography.materialLabelLargeStyle,
                color: NileColors.onAccent,
                backgroundColor: NileColors.accentStrong
            )
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(NileColors.accentStrong)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
        }
            .buttonStyle(.plain)
            .offset(y: 1.67)
            .frame(height: 48, alignment: .top)
            .disabled(model.isGoalMutating || model.isSending)
            .accessibilityIdentifier(id)
    }

    private func outlinedGoalButton(
        _ title: String,
        action: @escaping () -> Void,
        id: String
    ) -> some View {
        Button(action: action) {
            composeText(
                title,
                style: NileTypography.materialLabelLargeStyle,
                color: NileColors.text
            )
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.control)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }
        }
            .buttonStyle(.plain)
            .frame(height: 48, alignment: .top)
            .disabled(model.isGoalMutating)
            .accessibilityIdentifier(id)
    }
}
