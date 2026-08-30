import SwiftUI

struct DelegatedActivityOverview: View {
    let turn: DelegationTurnUI
    let controlsEnabled: Bool
    let onStopAgent: (String) -> Void
    let onOpenChild: (String) -> Void
    @State private var expanded = false

    var body: some View {
        if !turn.agents.isEmpty {
            DelegationGroup(
                turn: turn,
                controlsEnabled: controlsEnabled,
                compact: true,
                expanded: $expanded,
                onStopAgent: onStopAgent,
                onOpenChild: onOpenChild
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .nilePanel()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.delegationOverview)
        }
    }
}

struct DelegationTranscriptGroup: View {
    let turn: DelegationTurnUI
    let controlsEnabled: Bool
    let onStopAgent: (String) -> Void
    let onOpenChild: (String) -> Void
    @State private var expanded: Bool

    init(
        turn: DelegationTurnUI,
        controlsEnabled: Bool,
        onStopAgent: @escaping (String) -> Void,
        onOpenChild: @escaping (String) -> Void
    ) {
        self.turn = turn
        self.controlsEnabled = controlsEnabled
        self.onStopAgent = onStopAgent
        self.onOpenChild = onOpenChild
        _expanded = State(initialValue: turn.isPinned)
    }

    var body: some View {
        if !turn.agents.isEmpty {
            DelegationGroup(
                turn: turn,
                controlsEnabled: controlsEnabled,
                compact: false,
                expanded: $expanded,
                onStopAgent: onStopAgent,
                onOpenChild: onOpenChild
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .nilePanel()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                NileAccessibilityID.delegationTranscriptGroup(turn.id)
            )
        }
    }
}

private struct DelegationGroup: View {
    let turn: DelegationTurnUI
    let controlsEnabled: Bool
    let compact: Bool
    @Binding var expanded: Bool
    let onStopAgent: (String) -> Void
    let onOpenChild: (String) -> Void

    private var representative: DelegatedAgentUI {
        turn.agents.first(where: { $0.status == .running })
            ?? turn.agents.first(where: {
                $0.status == .interrupting
                    || $0.status == .interruptUnconfirmed
            })
            ?? turn.agents.first(where: { $0.status == .requested })
            ?? turn.agents.first(where: {
                $0.status == .completionUnknown
            })
            ?? turn.agents.first(where: \.status.isUnsuccessful)
            ?? turn.agents[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    DelegationStatusDot(status: groupDotStatus(turn.agents))
                    VStack(alignment: .leading, spacing: 1) {
                        delegationText(
                            "Delegated work",
                            style: NileTypography.bodySmallMediumStyle,
                            color: NileColors.text
                        )
                        delegationText(
                            delegationAggregate(turn.agents),
                            style: NileTypography.materialLabelSmallStyle,
                            color: NileColors.muted
                        )
                    }
                    Spacer(minLength: 8)
                    Text(expanded ? "▾" : "▸")
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: compact ? 36 : 40,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(
                NileAccessibilityID.delegationToggle(turn.id)
            )

            if expanded {
                ForEach(turn.agents) { agent in
                    DelegatedAgentRow(
                        agent: agent,
                        turnStartedAtEpochSeconds:
                            turn.startedAtEpochSeconds,
                        controlsEnabled: controlsEnabled,
                        compact: false,
                        onStopAgent: onStopAgent,
                        onOpenChild: onOpenChild
                    )
                    .padding(.top, 6)
                }
            } else {
                DelegatedAgentRow(
                    agent: representative,
                    turnStartedAtEpochSeconds: turn.startedAtEpochSeconds,
                    controlsEnabled: controlsEnabled,
                    compact: true,
                    onStopAgent: onStopAgent,
                    onOpenChild: onOpenChild
                )
                .padding(.top, 6)
                if turn.agents.count > 1 {
                    Text(
                        "+\(turn.agents.count - 1) more "
                            + (turn.agents.count == 2 ? "agent" : "agents")
                    )
                    .nileTextStyle(NileTypography.materialLabelSmallStyle)
                    .foregroundStyle(NileColors.muted)
                    .padding(.leading, 16)
                    .padding(.top, 1)
                }
            }
        }
    }
}
