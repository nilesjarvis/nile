import SwiftUI

struct ClarificationPromptActions: View {
    let prompt: TranscriptBlockingPrompt
    let enabled: Bool
    let onRespond: (String, String) -> Void
    @State private var selectedValue: String?
    @State private var otherAnswer = ""

    var body: some View {
        ForEach(prompt.actions) { action in
            let selected = selectedValue == action.value
                && otherAnswer.isEmpty
            Button {
                selectedValue = action.value
                otherAnswer = ""
            } label: {
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(
                                selected
                                    ? NileColors.accent
                                    : NileColors.muted,
                                lineWidth: 0.75
                            )
                        if selected {
                            Circle()
                                .fill(NileColors.accent)
                                .padding(1.75)
                        }
                    }
                        .frame(width: 6, height: 6)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(action.label)
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(
                            enabled ? NileColors.text : NileColors.muted
                        )
                    Spacer()
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 6)
                .background(
                    selected ? NileColors.surfaceHover : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(BlockingPromptButtonStyle())
            .frame(
                maxWidth: .infinity,
                minHeight: 48,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .disabled(!enabled)
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityIdentifier(
                "\(NileAccessibilityID.blockingPromptAction).\(action.value)"
            )
        }

        if prompt.acceptsText {
            TextField(
                "",
                text: Binding(
                    get: { otherAnswer },
                    set: {
                        otherAnswer = $0
                        if !$0.isEmpty {
                            selectedValue = nil
                        }
                    }
                ),
                prompt: Text("Other answer")
                    .foregroundStyle(NileColors.muted),
                axis: .vertical
            )
            .lineLimit(1 ... 4)
            .font(NileTypography.bodyMedium)
            .foregroundStyle(NileColors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 64)
            .background(NileColors.panelAlt)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NileColors.border, lineWidth: 1)
            }
            .disabled(!enabled)
            .accessibilityIdentifier(
                NileAccessibilityID.blockingPromptOtherAnswer
            )
        }

        PromptActionButton(
            label: "Continue",
            enabled: enabled
                && (selectedValue != nil
                    || !otherAnswer.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty),
            emphasized: true,
            accessibilityID: NileAccessibilityID.blockingPromptContinue
        ) {
            let answer = selectedValue
                ?? otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                selectedValue = nil
                otherAnswer = ""
                onRespond(prompt.id, answer)
            }
        }
        if let skipLabel = prompt.skipLabel {
            PromptActionButton(label: skipLabel, enabled: enabled) {
                selectedValue = nil
                otherAnswer = ""
                onRespond(prompt.id, "")
            }
        }
    }
}

struct BlockingPromptStatusView: View {
    let prompt: TranscriptBlockingPrompt

    var body: some View {
        HStack(spacing: 10) {
            if prompt.status == .submitting {
                ProgressView()
                    .controlSize(.small)
                    .tint(NileColors.accent)
            }
            Text(prompt.statusMessage ?? fallback)
                .font(NileTypography.bodySmall)
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityIdentifier(
            NileAccessibilityID.blockingPromptStatus
        )
    }

    private var fallback: String {
        switch prompt.status {
        case .pending:
            "This request cannot be answered on this device."
        case .submitting:
            "Sending response…"
        case .resolved:
            "Answered"
        case .uncertain:
            "The response may have been received. It cannot be retried safely; stop the run if it remains waiting."
        case .unavailable:
            "This request is no longer available on this device. Answer elsewhere, or stop the run."
        }
    }

    private var color: Color {
        switch prompt.status {
        case .uncertain:
            NileColors.warning
        case .unavailable:
            NileColors.error
        default:
            NileColors.muted
        }
    }
}

struct PromptActionButton: View {
    let label: String
    let enabled: Bool
    var destructive = false
    var emphasized = false
    var accessibilityID = NileAccessibilityID.blockingPromptAction
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(
                    NileTypography.bodyMedium.weight(
                        emphasized ? .semibold : .regular
                    )
                )
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 10)
                .background(
                    emphasized && enabled
                        ? NileColors.accentSoft
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(BlockingPromptButtonStyle())
        .frame(
            maxWidth: .infinity,
            minHeight: 48,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .disabled(!enabled)
        .accessibilityIdentifier(accessibilityID)
    }

    private var color: Color {
        if !enabled {
            return NileColors.muted
        }
        if destructive {
            return NileColors.error
        }
        if emphasized {
            return NileColors.link
        }
        return NileColors.text
    }
}

private struct BlockingPromptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
