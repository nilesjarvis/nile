import SwiftUI

struct DelegatedAgentDetail: View {
    let agent: DelegatedAgentUI
    let controlsEnabled: Bool
    let onStopAgent: (String) -> Void
    let onOpenChild: (String) -> Void
    @State private var outputExpanded = false

    private var outputs: [SubagentOutput] {
        outputExpanded
            ? agent.outputTail
            : Array(agent.outputTail.suffix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(NileColors.border)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 0) {
                if agent.status.isFinished {
                    DetailLine(label: "Result", value: agent.summary)
                    DetailLine(
                        label: "Terminal status",
                        value: agent.rawTerminalStatus
                    )
                }
                DetailLine(
                    label: clean(agent.toolName) == nil
                        ? "Thinking / activity"
                        : "Activity",
                    value: agent.latestActivity
                )
                DetailLine(
                    label: "Tool",
                    value: [agent.toolName, agent.toolPreview]
                        .compactMap(clean)
                        .joined(separator: " · ")
                )
                DetailLine(label: "Model", value: agent.model)
                DetailLine(
                    label: "Toolsets",
                    value: agent.toolsets.compactMap(clean)
                        .joined(separator: ", ")
                )
                DetailLine(
                    label: "Tools",
                    value: agent.toolCount > 0 ? String(agent.toolCount) : nil
                )
                DetailLine(
                    label: "Tokens",
                    value: [
                        agent.inputTokens.map { "\($0) in" },
                        agent.outputTokens.map { "\($0) out" },
                        agent.reasoningTokens.map { "\($0) reasoning" },
                    ].compactMap { $0 }.joined(separator: " · ")
                )
                DetailLine(
                    label: "API calls",
                    value: agent.apiCalls.map(String.init)
                )
                DetailLine(
                    label: "Files read",
                    value: agent.filesRead.compactMap(clean)
                        .joined(separator: ", ")
                )
                DetailLine(
                    label: "Files written",
                    value: agent.filesWritten.compactMap(clean)
                        .joined(separator: ", ")
                )

                if !outputs.isEmpty {
                    Text("Output")
                        .nileTextStyle(
                            NileTypography.materialLabelSmallStyle
                        )
                        .foregroundStyle(NileColors.muted)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(outputs.enumerated()), id: \.offset) {
                                _, output in
                                Text(outputText(output))
                                    .font(
                                        .system(size: 10, design: .monospaced)
                                    )
                                    .foregroundStyle(
                                        output.isError
                                            ? NileColors.error
                                            : NileColors.muted
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 160)
                    .background(NileColors.panelAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    if agent.outputTail.count > 3 {
                        Button(
                            outputExpanded
                                ? "Show latest 3"
                                : "Show all \(agent.outputTail.count)"
                        ) {
                            outputExpanded.toggle()
                        }
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.link)
                        .frame(minHeight: 48)
                    }
                }

                HStack {
                    if let id = clean(agent.subagentID),
                       agent.status.isActive {
                        Button {
                            onStopAgent(id)
                        } label: {
                            NileComposeText(
                                text:
                                    agent.status == .interrupting
                                    ? "Stopping agent"
                                    : "Stop agent",
                                style:
                                    NileTypography.materialLabelLargeStyle,
                                color: UIColor(NileColors.text),
                                backgroundColor: UIColor(NileColors.panel)
                            )
                            .frame(height: 20)
                            .padding(.horizontal, 12)
                        }
                        .disabled(
                            !controlsEnabled || agent.status == .interrupting
                        )
                        .frame(minHeight: 48)
                        .accessibilityIdentifier(
                            NileAccessibilityID.delegationStop(agent.rowID)
                        )
                    }
                    Spacer(minLength: 12)
                    if let child = clean(agent.childSessionID) {
                        Button {
                            onOpenChild(child)
                        } label: {
                            NileComposeText(
                                text: "Open child session",
                                style:
                                    NileTypography.materialLabelLargeStyle,
                                color: UIColor(NileColors.text),
                                backgroundColor: UIColor(NileColors.panel)
                            )
                            .frame(height: 20)
                            .padding(.horizontal, 12)
                        }
                        .disabled(!controlsEnabled)
                        .frame(minHeight: 48)
                        .accessibilityIdentifier(
                            NileAccessibilityID.delegationOpenChild(
                                agent.rowID
                            )
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 3)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            NileAccessibilityID.delegationAgentDetail(agent.rowID)
        )
    }

    private func outputText(_ output: SubagentOutput) -> String {
        let tool = clean(output.tool) ?? "Tool"
        let detail = clean(output.preview) ?? clean(output.status)
        return detail.map { "\(tool): \($0)" } ?? tool
    }
}

struct DetailLine: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = clean(value) {
            delegationText(
                "\(label): \(value)",
                style: NileTypography.materialLabelSmallStyle,
                color: NileColors.muted
            )
            .frame(minHeight: 16, alignment: .top)
        }
    }
}
