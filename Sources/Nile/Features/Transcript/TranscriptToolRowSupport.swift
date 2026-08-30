import Foundation
import SwiftUI

struct ElbowDetail<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 15)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(NileColors.border)
                    .frame(width: 2)
                    .padding(.leading, 3)
            }
    }
}

struct StatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 7, height: 7)
            .opacity(status == "running" ? 0.78 : 1)
    }
}

func statusColor(_ status: String) -> Color {
    switch status {
    case "running":
        NileColors.text
    case "recorded":
        NileColors.muted
    case "error", "failed":
        NileColors.error
    case "stopped":
        NileColors.stopped
    default:
        NileColors.complete
    }
}

func formatToolDuration(_ seconds: Double) -> String {
    if seconds < 10 {
        return String(format: "%.1fs", locale: Locale(identifier: "en_US"), seconds)
    }
    if seconds < 60 {
        return "\(Int(seconds))s"
    }
    let minutes = Int(seconds) / 60
    let remainder = Int(seconds) % 60
    return remainder == 0
        ? "\(minutes)m"
        : "\(minutes)m \(remainder)s"
}

extension String {
    var nonBlankValue: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

extension Array {
    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}
