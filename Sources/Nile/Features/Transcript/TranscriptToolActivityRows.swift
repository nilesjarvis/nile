import Foundation
import SwiftUI

struct ToolActivityGroup: View {
    let tools: [TranscriptTool]
    let expanded: Bool
    let ripple: ToolActivityRipple?
    let onToggle: (Bool) -> Void
    let onRipple: (CGPoint) -> Void
    @Environment(\.nileReduceMotion) private var reduceMotion

    private var status: String {
        if tools.contains(where: { ["error", "failed"].contains($0.status) }) {
            return "failed"
        }
        if tools.contains(where: { $0.status == "stopped" }) {
            return "stopped"
        }
        if tools.contains(where: { $0.status == "running" }) {
            return "running"
        }
        return "done"
    }

    private var heading: String {
        switch status {
        case "running":
            "Acting"
        case "failed":
            "Actions failed"
        case "stopped":
            "Actions stopped"
        default:
            "Completed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleDisclosure()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        StatusDot(status: status)
                        Text(heading)
                            .font(NileTypography.bodySmall.weight(.semibold))
                            .foregroundStyle(statusColor(status))
                        Spacer()
                        Text(actionCount)
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                        Text(expanded ? "▾" : "▸")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                    }
                    if !expanded, let current =
                        tools.last(where: { $0.status == "running" })
                            ?? tools.last {
                        ElbowDetail {
                            Text(current.label?.nonBlankValue
                                ?? defaultToolLabel(current.name))
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, expanded ? 0 : 10)
                .contentShape(Rectangle())
                .overlay {
                    if let ripple {
                        ToolActivityWave(
                            origin: ripple.origin,
                            reduceMotion: reduceMotion
                        )
                        .id(ripple.generation)
                        .clipShape(
                            RoundedRectangle(cornerRadius: NileRadii.card)
                        )
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onRipple(value.location)
                    }
            )
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(
                NileAccessibilityID.toolActivityGroup(
                    tools.first?.id ?? ""
                )
            )

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools) { tool in
                        ToolRow(tool: tool)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(NileColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.card)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.24),
            value: expanded
        )
    }

    private var actionCount: String {
        let settled = tools.count { $0.status != "running" }
        let count = status == "done"
            ? "\(tools.count) actions"
            : "\(settled)/\(tools.count) actions"
        guard let duration = tools.compactMap(\.durationSeconds)
            .nonEmpty?.reduce(0, +) else {
            return count
        }
        return "\(formatToolDuration(duration)) · \(count)"
    }

    private func toggleDisclosure() {
        onToggle(!expanded)
    }
}

struct ToolActivityRipple: Equatable {
    let origin: CGPoint
    let generation: Int
}

private struct ToolActivityWave: View {
    let origin: CGPoint
    let reduceMotion: Bool
    @State private var finished = false

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                RoundedRectangle(cornerRadius: NileRadii.card)
                    .fill(NileColors.text.opacity(0.1))
                    .opacity(finished ? 0 : 1)
            } else {
                let point = CGPoint(
                    x: min(max(0, origin.x), geometry.size.width),
                    y: min(max(0, origin.y), geometry.size.height)
                )
                let radius = max(
                    max(
                        hypot(point.x, point.y),
                        hypot(geometry.size.width - point.x, point.y)
                    ),
                    max(
                        hypot(point.x, geometry.size.height - point.y),
                        hypot(
                            geometry.size.width - point.x,
                            geometry.size.height - point.y
                        )
                    )
                )
                Circle()
                    .fill(NileColors.text.opacity(0.11))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(point)
                    .scaleEffect(finished ? 1 : 0.01)
                    .opacity(finished ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(
                .easeOut(duration: reduceMotion ? 0.15 : 0.32)
            ) {
                finished = true
            }
        }
    }
}
