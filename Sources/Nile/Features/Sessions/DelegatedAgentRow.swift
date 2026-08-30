import SwiftUI

struct DelegatedAgentRow: View {
    let agent: DelegatedAgentUI
    let turnStartedAtEpochSeconds: Double?
    let controlsEnabled: Bool
    let compact: Bool
    let onStopAgent: (String) -> Void
    let onOpenChild: (String) -> Void
    @State private var expanded = false

    private var supportingText: String? {
        if agent.status.isFinished, let summary = clean(agent.summary) {
            return summary
        }
        return clean(agent.latestActivity)
    }

    private var statusLine: String {
        var parts = [agent.status.label]
        if agent.taskCount > 0,
           (0..<agent.taskCount).contains(agent.taskIndex) {
            parts.append("task \(agent.taskIndex + 1) of \(agent.taskCount)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                DelegationStatusDot(status: agent.status.dotStatus)
                Text(clean(agent.goal) ?? "Delegated task")
                    .font(NileTypography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(NileColors.text)
                    .lineLimit(expanded ? nil : 1)
                Spacer(minLength: 6)
                DelegationDuration(
                    status: agent.status,
                    recorded: agent.durationSeconds,
                    startedAt: turnStartedAtEpochSeconds
                )
                Text(expanded ? "▾" : "▸")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }

            if !agent.status.isFinished, !expanded {
                HStack(spacing: 0) {
                    Text(statusLine)
                    if let supportingText {
                        Text(" · \(supportingText)")
                            .lineLimit(1)
                    }
                }
                .nileTextStyle(NileTypography.materialLabelSmallStyle)
                .foregroundStyle(NileColors.muted)
                .padding(.leading, 16)
                .frame(height: 16, alignment: .top)
            } else {
                delegationText(
                    statusLine,
                    style: NileTypography.materialLabelSmallStyle,
                    color:
                        agent.status.isUnsuccessful
                        ? NileColors.error
                        : NileColors.muted
                )
                    .padding(.leading, 16)
                    .frame(height: 16, alignment: .top)
            }

            if !expanded, agent.status.isFinished, let supportingText {
                DelegationSupportingText(
                    text: "\(clean(agent.summary) == nil ? "Last activity" : "Result")"
                        + " · \(supportingText)"
                )
                .padding(.leading, 16)
                .padding(.trailing, 24)
                .padding(.top, 1)
            }

            if expanded {
                DelegatedAgentDetail(
                    agent: agent,
                    controlsEnabled: controlsEnabled,
                    onStopAgent: onStopAgent,
                    onOpenChild: onOpenChild
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 6 : 8)
        .background(NileColors.inset)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.small)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expanded.toggle()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(clean(agent.goal) ?? "Delegated task")
        .accessibilityValue(
            "\(agent.status.label), details \(expanded ? "expanded" : "collapsed")"
        )
        .accessibilityIdentifier(
            NileAccessibilityID.delegationAgentRow(agent.rowID)
        )
    }
}
