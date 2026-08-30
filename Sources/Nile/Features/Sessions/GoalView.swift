import SwiftUI

struct GoalSheet: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss
    @State var objective: String
    @State var turnBudget: Int?
    @State var objectiveExpanded = false

    init(model: SessionListModel) {
        self.model = model
        let draft = model.composer.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        _objective = State(
            initialValue: !draft.isEmpty && !draft.hasPrefix("/") ? draft : ""
        )
        _turnBudget = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NileColors.background.ignoresSafeArea()
                ScrollView {
                    if let goal = model.goal {
                        goalDetails(goal)
                    } else {
                        goalCreation
                    }
                }
                .padding(.vertical, 4)
                .scrollIndicators(.hidden)
                .accessibilityIdentifier(NileAccessibilityID.goalSheet)
            }
            .navigationTitle("Standing Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.setGoalSheetVisible(false)
                    }
                }
            }
        }
        .presentationBackground(NileColors.background)
        .presentationCornerRadius(NileRadii.window)
        .presentationDragIndicator(.visible)
        .presentationDetents([
            .height(model.goal == nil ? 620 : 560),
            .large,
        ])
        .onChange(of: model.isGoalSheetVisible) { _, visible in
            if !visible {
                dismiss()
            }
        }
    }

    @ViewBuilder
    var goalError: some View {
        if let message = model.goalError {
            Text(message)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(NileColors.error.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    func composeText(
        _ text: String,
        style: NileTypography.TextStyle,
        color: Color,
        fillsWidth: Bool = false,
        backgroundColor: Color = NileColors.panel
    ) -> some View {
        NileComposeText(
            text: text,
            style: style,
            color: UIColor(color),
            backgroundColor: UIColor(backgroundColor),
            fillsWidth: fillsWidth
        )
    }
}
