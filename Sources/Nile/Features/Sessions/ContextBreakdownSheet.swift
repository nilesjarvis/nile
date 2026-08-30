import SwiftUI

struct ContextBreakdownSheet: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NileColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Context")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                        Spacer()
                        if let usage = model.usage,
                           let used = usage.contextUsed,
                           let maximum = usage.contextMax {
                            Text(
                                "\(formatContextTokens(used)) of "
                                    + "\(formatContextTokens(maximum)) · "
                                    + "\(usage.contextPercent ?? inferredPercent(used: used, maximum: maximum))%"
                            )
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.text)
                        }
                    }

                    if let usage = model.usage,
                       !usage.categories.isEmpty {
                        StackedContextBar(
                            categories: usage.categories,
                            contextMaximum: usage.contextMax
                        )
                        .accessibilityIdentifier(
                            NileAccessibilityID.contextBreakdown
                        )

                        VStack(spacing: 10) {
                            ForEach(usage.categories, id: \.id) { category in
                                contextRow(
                                    color: categoryColor(category.id),
                                    label: category.label,
                                    tokens: category.tokens
                                )
                            }
                            if let used = usage.contextUsed,
                               let maximum = usage.contextMax {
                                contextRow(
                                    color: NileColors.panelAlt,
                                    label: "free",
                                    tokens: max(0, maximum - used),
                                    muted: true
                                )
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .nilePanel()
                    } else {
                        Text(
                            "No breakdown yet — it appears a moment after the session's agent finishes loading."
                        )
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 26)
                .padding(.horizontal, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier(NileAccessibilityID.contextSheet)
        }
        .presentationBackground(NileColors.background)
        .presentationCornerRadius(NileRadii.window)
        .presentationDragIndicator(.visible)
        .presentationDetents([.height(420), .large])
        .onChange(of: model.isContextSheetVisible) { _, visible in
            if !visible {
                dismiss()
            }
        }
    }

    private func contextRow(
        color: Color,
        label: String,
        tokens: Int,
        muted: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(NileTypography.bodySmall)
                .foregroundStyle(muted ? NileColors.muted : NileColors.text)
            Spacer()
            Text(formatContextTokens(tokens))
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .background(NileColors.inset)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
        .frame(maxWidth: .infinity)
    }
}

private struct StackedContextBar: View {
    let categories: [ContextCategory]
    let contextMaximum: Int?

    var body: some View {
        GeometryReader { geometry in
            let used = categories.reduce(0) {
                saturatingUsageAdd($0, $1.tokens)
            }
            let maximum = max(1, contextMaximum ?? used)
            let free = max(0, maximum - used)
            HStack(spacing: 2) {
                ForEach(categories, id: \.id) { category in
                    Rectangle()
                        .fill(categoryColor(category.id))
                        .frame(
                            width: segmentWidth(
                                tokens: category.tokens,
                                maximum: maximum,
                                available: geometry.size.width,
                                segmentCount: categories.count
                                    + (free > 0 ? 1 : 0)
                            )
                        )
                }
                if free > 0 {
                    Rectangle()
                        .fill(NileColors.panelAlt)
                        .frame(
                            width: segmentWidth(
                                tokens: free,
                                maximum: maximum,
                                available: geometry.size.width,
                                segmentCount: categories.count + 1
                            )
                        )
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }

    private func segmentWidth(
        tokens: Int,
        maximum: Int,
        available: CGFloat,
        segmentCount: Int
    ) -> CGFloat {
        let gaps = CGFloat(max(0, segmentCount - 1)) * 2
        return max(
            0,
            (available - gaps) * CGFloat(max(0, tokens)) / CGFloat(maximum)
        )
    }
}

private func categoryColor(_ id: String) -> Color {
    switch id {
    case "system_prompt": NileColors.chartBlue
    case "tool_definitions": NileColors.chartGreen
    case "rules": NileColors.chartPurple
    case "skills": NileColors.chartRed
    case "mcp": NileColors.chartOrange
    case "subagent_definitions": NileColors.chartCyan
    case "memory": NileColors.chartYellow
    case "conversation": NileColors.chartPink
    default: NileColors.muted
    }
}

private func inferredPercent(used: Int, maximum: Int) -> Int {
    boundedContextPercent(used: used, maximum: maximum)
}

private func formatContextTokens(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fk", Double(value) / 1_000)
    }
    return String(value)
}
