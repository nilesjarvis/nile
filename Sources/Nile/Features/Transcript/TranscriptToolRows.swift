import Foundation
import SwiftUI

struct ToolRow: View {
    let tool: TranscriptTool
    @State private var expanded = false

    var body: some View {
        if let todos = tool.todos {
            TodoToolCard(tool: tool, todos: todos)
        } else if let diff = tool.inlineDiff {
            DiffToolCard(tool: tool, diff: diff)
        } else {
            DefaultToolCard(tool: tool, expanded: $expanded)
        }
    }
}

private struct DefaultToolCard: View {
    let tool: TranscriptTool
    @Binding var expanded: Bool

    private var trimmedBody: String {
        tool.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var lines: [String] {
        trimmedBody.components(separatedBy: .newlines)
    }

    private var collapsible: Bool {
        lines.count > 2 || trimmedBody.count > 160
    }

    var body: some View {
        Button {
            if collapsible {
                expanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ToolHeader(
                    tool: tool,
                    title: title,
                    detail: detail,
                    collapsible: collapsible,
                    expanded: expanded,
                    lineCount: lines.count
                )
                if tool.status == "stopped" {
                    ElbowDetail {
                        Text("Stopped before completion")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                    }
                }
                if !trimmedBody.isEmpty {
                    ElbowDetail {
                        VStack(alignment: .leading, spacing: 4) {
                            if tool.kind != .terminal,
                               let summary = tool.summary?.nonBlankValue,
                               summary != detail {
                                Text(summary)
                                    .font(NileTypography.bodySmall)
                                    .foregroundStyle(NileColors.text)
                            }
                            Text(
                                !collapsible || expanded
                                    ? tool.content
                                    : lines.first(where: {
                                        !$0.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty
                                    }) ?? ""
                            )
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(NileColors.muted)
                            .lineLimit(
                                !collapsible || expanded ? nil : 1
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(tool.kind == .terminal ? 8 : 0)
                        .background(
                            tool.kind == .terminal
                                ? NileColors.panelAlt
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(8)
            .nileGlass(cornerRadius: NileRadii.small, tint: NileColors.inset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(NileAccessibilityID.transcriptTool(tool.id))
    }

    private var title: String {
        if tool.kind == .terminal {
            let code = tool.name == "execute_code"
            return switch tool.status {
            case "running":
                code ? "Running code" : "Running"
            case "stopped":
                code ? "Code stopped" : "Stopped"
            case "error", "failed":
                code ? "Code failed" : "Failed"
            default:
                code ? "Ran code" : "Ran"
            }
        }
        return switch tool.kind {
        case .skill:
            "Skill"
        case .memory:
            "Memory"
        case .tool:
            tool.name
        case .terminal:
            "Ran"
        }
    }

    private var detail: String? {
        guard let label = tool.label?.nonBlankValue,
              label != trimmedBody else {
            return nil
        }
        guard tool.kind == .terminal else {
            return label
        }
        if let first = label.firstIndex(of: "`"),
           let second = label[label.index(after: first)...].firstIndex(of: "`") {
            return String(label[label.index(after: first)..<second])
        }
        let prefix = tool.name == "execute_code" ? "Running code" : "Running"
        let value = label.hasPrefix(prefix)
            ? String(label.dropFirst(prefix.count))
            : label
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonBlankValue
    }
}

private struct ToolHeader: View {
    let tool: TranscriptTool
    let title: String
    let detail: String?
    let collapsible: Bool
    let expanded: Bool
    let lineCount: Int

    var body: some View {
        HStack(spacing: 9) {
            if tool.kind == .terminal {
                Image(
                    systemName: tool.name == "execute_code"
                        ? "chevron.left.forwardslash.chevron.right"
                        : "terminal"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor(tool.status))
                .frame(width: 14)
            } else {
                StatusDot(status: tool.status)
            }
            Text(title)
                .font(NileTypography.bodySmall.weight(.medium))
                .foregroundStyle(
                    tool.kind == .terminal
                        ? statusColor(tool.status)
                        : NileColors.text
                )
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(
                        tool.kind == .terminal
                            ? .system(size: 11, design: .monospaced)
                            : NileTypography.bodySmall
                    )
                    .foregroundStyle(
                        tool.kind == .terminal
                            ? NileColors.text
                            : NileColors.muted
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let duration = tool.durationSeconds {
                Text(formatToolDuration(duration))
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }
            if collapsible {
                Text(
                    expanded
                        ? "▾"
                        : lineCount > 1
                            ? "▸ \(lineCount) lines"
                            : "▸ expand"
                )
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
            }
        }
    }
}
