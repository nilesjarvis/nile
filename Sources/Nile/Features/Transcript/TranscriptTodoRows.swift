import SwiftUI

struct TodoToolCard: View {
    let tool: TranscriptTool
    let todos: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                StatusDot(status: tool.status)
                Text("To-do")
                    .font(NileTypography.bodySmall.weight(.medium))
                    .foregroundStyle(NileColors.text)
                Spacer()
                Text("\(todos.count { $0.status == "completed" })/\(todos.count)")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }
            ElbowDetail {
                TodoChecklist(todos: todos)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(NileAccessibilityID.transcriptTool(tool.id))
    }
}

struct ActiveTodoPlan: View {
    let todos: [TodoItem]
    @State private var expanded = false

    private var current: TodoItem? {
        todos.first { $0.status == "in_progress" }
            ?? todos.first { $0.status == "pending" }
            ?? todos.last
    }

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    StatusDot(status: "running")
                    Text("Plan")
                        .font(NileTypography.bodySmall.weight(.medium))
                        .foregroundStyle(NileColors.text)
                    Spacer()
                    Text("\(todos.count { $0.status == "completed" })/\(todos.count)")
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                    Text(expanded ? "▾" : "▸")
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                }
                if expanded {
                    ElbowDetail { TodoChecklist(todos: todos) }
                } else if let current {
                    ElbowDetail { TodoChecklist(todos: [current]) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .nilePanel()
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier(NileAccessibilityID.activePlan)
    }
}

private struct TodoChecklist: View {
    let todos: [TodoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                HStack(alignment: .top, spacing: 8) {
                    Text(glyph(todo.status))
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(glyphColor(todo.status))
                    Text(todo.content)
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(
                            todo.status == "in_progress"
                                ? NileColors.text
                                : NileColors.muted
                        )
                        .strikethrough(
                            ["completed", "cancelled"].contains(todo.status)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func glyph(_ status: String) -> String {
        switch status {
        case "completed":
            "✔"
        case "in_progress":
            "◉"
        case "cancelled":
            "✕"
        default:
            "▢"
        }
    }

    private func glyphColor(_ status: String) -> Color {
        status == "completed"
            ? NileColors.complete
            : status == "in_progress"
                ? NileColors.text
                : NileColors.muted
    }
}
