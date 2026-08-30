import SwiftUI

struct DelegationSupportingText: View {
    let text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .nileTextStyle(NileTypography.materialLabelSmallStyle)
                .foregroundStyle(NileColors.muted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 16, alignment: .top)
            Text(text)
                .nileTextStyle(NileTypography.materialLabelSmallStyle)
                .foregroundStyle(NileColors.muted)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(height: 32, alignment: .top)
        }
    }
}

struct DelegationDuration: View {
    let status: DelegatedAgentStatus
    let recorded: Double?
    let startedAt: Double?
    @State private var now = Date().timeIntervalSince1970

    private var duration: Double? {
        recorded ?? (
            status.isActive
                ? startedAt.map { max(0, now - $0) }
                : nil
        )
    }

    var body: some View {
        if let duration, duration >= 1 {
            delegationText(
                formatToolDuration(duration),
                style: NileTypography.materialLabelSmallStyle,
                color: NileColors.muted
            )
                .frame(height: 16, alignment: .top)
                .task(id: status) {
                    while !Task.isCancelled, status.isActive {
                        try? await Task.sleep(for: .seconds(1))
                        now = Date().timeIntervalSince1970
                    }
                }
        }
    }
}

struct DelegationStatusDot: View {
    let status: String

    private var color: Color {
        switch status {
        case "running": NileColors.agent
        case "failed": NileColors.error
        case "complete": NileColors.complete
        default: NileColors.muted
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

extension DelegatedAgentStatus {
    var label: String {
        switch self {
        case .requested: "Queued"
        case .running: "Working"
        case .interrupting: "Stopping"
        case .interruptUnconfirmed: "Stop not confirmed"
        case .completionUnknown: "Status unavailable"
        case let .finished(status):
            switch status {
            case .completed: "Finished"
            case .interrupted: "Stopped"
            case .failed: "Failed"
            case .timeout: "Timed out"
            case .error: "Error"
            case .unknown: "Status unavailable"
            }
        }
    }

    var dotStatus: String {
        if self == .finished(.completed) {
            return "complete"
        }
        if isUnsuccessful {
            return "failed"
        }
        return isActive ? "running" : "recorded"
    }
}

func delegationText(
    _ text: String,
    style: NileTypography.TextStyle,
    color: Color
) -> some View {
    NileComposeText(
        text: text,
        style: style,
        color: UIColor(color),
        backgroundColor: UIColor(NileColors.panel)
    )
}

func groupDotStatus(_ agents: [DelegatedAgentUI]) -> String {
    if agents.contains(where: {
        [.requested, .running, .interrupting, .interruptUnconfirmed]
            .contains($0.status)
    }) {
        return "running"
    }
    if agents.contains(where: \.status.isUnsuccessful) {
        return "failed"
    }
    return "recorded"
}

func delegationAggregate(_ agents: [DelegatedAgentUI]) -> String {
    let rows: [(Int, String)] = [
        (agents.count { $0.status == .requested }, "queued"),
        (
            agents.count {
                [.running, .interrupting, .interruptUnconfirmed]
                    .contains($0.status)
            },
            "working"
        ),
        (agents.count(where: \.status.isUnsuccessful), "failed"),
        (agents.count { $0.status == .finished(.completed) }, "finished"),
        (agents.count { $0.status == .finished(.interrupted) }, "stopped"),
        (
            agents.count {
                $0.status == .completionUnknown
                    || $0.status == .finished(.unknown)
            },
            "unavailable"
        ),
    ]
    let visible = rows.compactMap { count, label in
        count > 0 ? "\(count) \(label)" : nil
    }
    return visible.isEmpty
        ? "\(agents.count) agents"
        : visible.joined(separator: " · ")
}

func clean(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned?.isEmpty == false ? cleaned : nil
}
