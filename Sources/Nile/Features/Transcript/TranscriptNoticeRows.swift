import SwiftUI

struct SystemNoticeRow: View {
    let message: TranscriptMessage
    @State private var expanded = false

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(alignment: .top, spacing: 9) {
                StatusDot(status: message.isError ? "failed" : "recorded")
                    .frame(height: 16)
                Text(message.content.isEmpty ? " " : message.content)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(
                        message.isError ? NileColors.error : NileColors.muted
                    )
                    .lineLimit(expanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(expanded ? "⌃" : "⌄")
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.muted)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier(
            NileAccessibilityID.systemNotice(message.id)
        )
    }
}

struct StandingGoalPromptRow: View {
    let message: TranscriptMessage
    @State private var expanded = false

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(NileColors.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Standing goal started")
                        .font(NileTypography.labelMedium.weight(.semibold))
                        .foregroundStyle(NileColors.accent)
                    Text(
                        message.content.isEmpty
                            ? "Goal objective unavailable"
                            : message.content
                    )
                    .font(NileTypography.bodyMedium)
                    .foregroundStyle(NileColors.text)
                    .lineLimit(expanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(expanded ? "⌃" : "⌄")
                    .font(NileTypography.titleMedium)
                    .foregroundStyle(NileColors.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .nilePanel()
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
}
