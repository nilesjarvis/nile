import SwiftUI

private struct GoalQuickStart: Identifiable {
    let label: String
    let objective: String
    var id: String { label }
}

private let goalQuickStarts = [
    GoalQuickStart(
        label: "Finish this task",
        objective:
            "Finish the current task completely, verify the result, and stop if you need my input."
    ),
    GoalQuickStart(
        label: "Fix and verify",
        objective:
            "Find and fix the current problem, add or update the relevant tests, and verify they pass."
    ),
    GoalQuickStart(
        label: "Get checks green",
        objective:
            "Run the relevant checks, resolve every failure in scope, and finish with the passing results."
    ),
]

private let goalTurnBudgets = [5, 10, 20, 40]

/// Creation rendering for the sole `GoalSheet`.
///
/// Draft and budget state remain in the core sheet. This extension adds no
/// stored state, model owner, transport path, or competing modal authority.
extension GoalSheet {
    var goalCreation: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                composeText(
                    "Set a standing goal",
                    style: NileTypography.titleLargeSemiboldStyle,
                    color: NileColors.text,
                    fillsWidth: true
                )
                composeText(
                    "Hermes keeps taking turns until it finishes, pauses, or reaches the turn budget.",
                    style: NileTypography.bodyMediumStyle,
                    color: NileColors.muted,
                    fillsWidth: true
                )
            }

            composeText(
                "Quick starts",
                style: NileTypography.labelMediumStyle,
                color: NileColors.muted
            )
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(goalQuickStarts) { item in
                        Button {
                            objective = item.objective
                        } label: {
                            composeText(
                                item.label,
                                style: NileTypography
                                    .materialLabelLargeStyle,
                                color: NileColors.text
                            )
                        }
                        .nileOutlinedButton()
                    }
                }
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: 7) {
                Text("What should Hermes finish?")
                    .font(.subheadline.weight(.semibold))
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $objective)
                        .font(NileTypography.bodyLarge)
                        .foregroundStyle(NileColors.text)
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(10)
                        .background(NileColors.panelAlt)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: NileRadii.card,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: NileRadii.card,
                                style: .continuous
                            )
                            .stroke(
                                NileColors.border,
                                lineWidth: 1
                            )
                        }
                        .onChange(of: objective) { _, value in
                            if value.count > 2_000 {
                                objective = String(value.prefix(2_000))
                            }
                        }
                        .accessibilityLabel("What should Hermes finish?")
                        .accessibilityIdentifier(
                            NileAccessibilityID.goalObjective
                        )
                    if objective.isEmpty {
                        Text("Describe the outcome and how Hermes should verify it.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                composeText(
                    "Name the result and verification. Your chat draft stays untouched.",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    fillsWidth: true
                )
                .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 7) {
                composeText(
                    "Turn budget",
                    style: NileTypography.labelMediumStyle,
                    color: NileColors.muted
                )
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        budgetButton(label: "Profile default", turns: nil)
                            .accessibilityIdentifier(
                                NileAccessibilityID.goalBudgetDefault
                            )
                        ForEach(goalTurnBudgets, id: \.self) { turns in
                            budgetButton(
                                label: "\(turns) turns",
                                turns: turns
                            )
                            .accessibilityIdentifier(
                                NileAccessibilityID.goalBudget(turns)
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
                .scrollIndicators(.hidden)
                composeText(
                    turnBudget == nil
                        ? "Uses this Hermes profile's setting (20 turns unless configured)."
                        : "Saves \(turnBudget ?? 20) turns as this Hermes profile's default.",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    fillsWidth: true
                )
            }

            goalError

            Button {
                model.startGoal(objective, maxTurns: turnBudget)
            } label: {
                HStack(spacing: 8) {
                    if model.isGoalMutating {
                        ProgressView().tint(NileColors.onAccent)
                    }
                    composeText(
                        "Start goal",
                        style: NileTypography.materialLabelLargeStyle,
                        color: NileColors.onAccent
                    )
                }
                .foregroundStyle(NileColors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 41.67)
                .background(NileColors.accentStrong)
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
            }
            .buttonStyle(.plain)
            .disabled(
                objective.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || model.isGoalMutating || model.isSending
            )
            .opacity(
                objective.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || model.isGoalMutating || model.isSending
                    ? 0.45 : 1
            )
            .accessibilityIdentifier(NileAccessibilityID.goalStart)
            .padding(.top, 7)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private func budgetButton(label: String, turns: Int?) -> some View {
        Button {
            turnBudget = turns
        } label: {
            composeText(
                label,
                style: NileTypography.materialLabelLargeStyle,
                color: NileColors.text
            )
                .padding(.horizontal, turns == nil ? 22 : 19.5)
                .frame(height: 33.33)
                .background(
                    turnBudget == turns
                        ? NileColors.accentSoft
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
                .overlay {
                    RoundedRectangle(cornerRadius: NileRadii.control)
                        .stroke(
                            turnBudget == turns
                                ? Color.clear
                                : NileColors.border,
                            lineWidth: 1
                        )
                }
        }
    }
}

private extension View {
    func nileOutlinedButton() -> some View {
        foregroundStyle(NileColors.text)
            .padding(.horizontal, 22)
            .frame(height: 44)
            .nileGlass(cornerRadius: NileRadii.control, interactive: true)
    }
}
