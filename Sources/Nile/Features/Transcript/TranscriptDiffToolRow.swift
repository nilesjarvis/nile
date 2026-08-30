import Foundation
import SwiftUI

struct DiffToolCard: View {
    let tool: TranscriptTool
    let diff: String
    @State private var expanded = false

    private var allLines: [String] {
        diff.components(separatedBy: .newlines)
            .droppingBlankEdges()
    }

    private var displayedLines: [String] {
        expanded ? allLines : Array(allLines.prefix(24))
    }

    var body: some View {
        Button {
            if allLines.count > 24 {
                expanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    StatusDot(status: tool.status)
                    Text("Edited")
                        .font(NileTypography.bodySmall.weight(.medium))
                        .foregroundStyle(NileColors.text)
                    if let label = tool.label?.nonBlankValue {
                        Text(label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(NileColors.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("+\(allLines.count { $0.hasPrefix("+") })")
                        .foregroundStyle(NileColors.complete)
                    Text("−\(allLines.count { $0.hasPrefix("-") })")
                        .foregroundStyle(NileColors.error)
                }
                .font(NileTypography.bodySmall)
                .padding(10)
                Rectangle().fill(NileColors.border).frame(height: 1)
                ElbowDetail {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(
                            Array(displayedLines.enumerated()),
                            id: \.offset
                        ) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(diffColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(diffBackground(line))
                        }
                        if !expanded, allLines.count > 24 {
                            Text("… \(allLines.count - 24) more lines")
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                    }
                    .background(NileColors.panelAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(8)
            }
            .nilePanel()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(NileAccessibilityID.transcriptTool(tool.id))
    }

    private func diffColor(_ line: String) -> Color {
        if line.hasPrefix("+") {
            return NileColors.complete
        }
        if line.hasPrefix("-") {
            return NileColors.error
        }
        return NileColors.muted
    }

    private func diffBackground(_ line: String) -> Color {
        if line.hasPrefix("+") {
            return NileColors.complete.opacity(0.10)
        }
        if line.hasPrefix("-") {
            return NileColors.error.opacity(0.10)
        }
        return .clear
    }
}

private extension Array where Element == String {
    func droppingBlankEdges() -> [String] {
        var copy = self
        while copy.first?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == true {
            copy.removeFirst()
        }
        while copy.last?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty == true {
            copy.removeLast()
        }
        return copy
    }
}
