import SwiftUI

struct BlockingPromptRow: View {
    let prompt: TranscriptBlockingPrompt
    let onRespond: (String, String) -> Void
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void

    private var canRespond: Bool {
        prompt.actionable
            && prompt.status == .pending
            && prompt.kind != .unavailable
    }

    var body: some View {
        if prompt.status == .resolved {
            resolvedRow
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.title)
                    .font(NileTypography.bodyMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                if let message = prompt.message,
                   !message.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   ).isEmpty {
                    Text(message)
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(NileColors.text)
                }
                if let detail = prompt.detail,
                   !detail.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   ).isEmpty {
                    promptDetail(detail)
                    .padding(10)
                    .background(NileColors.panelAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.card)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(
                NileAccessibilityID.blockingPrompt(prompt.id)
            )
        }
    }

    @ViewBuilder
    private var actions: some View {
        if prompt.status != .pending || prompt.kind == .unavailable {
            BlockingPromptStatusView(prompt: prompt)
        } else {
            switch prompt.kind {
            case .clarification:
                ClarificationPromptActions(
                    prompt: prompt,
                    enabled: canRespond,
                    onRespond: onRespond
                )
            case .approval:
                ForEach(prompt.actions) { action in
                    PromptActionButton(
                        label: action.label,
                        enabled: canRespond,
                        destructive: action.destructive
                            || action.value == ApprovalChoice.deny.rawValue,
                        emphasized: action.value
                            == ApprovalChoice.once.rawValue,
                        accessibilityID:
                            "\(NileAccessibilityID.blockingPromptAction).\(action.value)"
                    ) {
                        if action.value == ApprovalChoice.always.rawValue {
                            onPermanentApproval(prompt)
                        } else {
                            onRespond(prompt.id, action.value)
                        }
                    }
                }
                if !prompt.actionable {
                    statusText(
                        prompt.statusMessage
                            ?? "Waiting for an earlier approval in this session."
                    )
                }
            case .sudo, .secret:
                PromptActionButton(
                    label: "Enter securely",
                    enabled: canRespond
                ) {
                    onSecureEntry(prompt)
                }
                if let skipLabel = prompt.skipLabel {
                    PromptActionButton(
                        label: skipLabel,
                        enabled: canRespond,
                        destructive: prompt.kind == .sudo
                    ) {
                        onRespond(prompt.id, "")
                    }
                }
            case .unavailable:
                statusText(
                    prompt.statusMessage
                        ?? "This request cannot be answered on this device."
                )
            }
        }
    }

    private var resolvedRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(NileColors.complete)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedHeading)
                    .font(NileTypography.bodySmall.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                Text(prompt.statusMessage ?? "Answered")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .accessibilityIdentifier(
                        NileAccessibilityID.blockingPromptStatus
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NileColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            NileAccessibilityID.blockingPrompt(prompt.id)
        )
    }

    @ViewBuilder
    private func promptDetail(_ detail: String) -> some View {
        if prompt.kind == .approval {
            ScrollView(.horizontal) {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NileColors.text)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.hidden)
        } else {
            Text(detail)
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resolvedHeading: String {
        switch prompt.kind {
        case .clarification:
            "Decision answered"
        case .approval:
            "Permission answered"
        case .sudo, .secret:
            "Secure input sent"
        case .unavailable:
            "Request closed"
        }
    }

    private var borderColor: Color {
        switch prompt.status {
        case .unavailable:
            NileColors.error.opacity(0.5)
        case .resolved:
            NileColors.border
        case .pending, .submitting, .uncertain:
            NileColors.warning.opacity(0.5)
        }
    }

    private var accessibilityLabel: String {
        let prefix = switch prompt.status {
        case .pending: "Hermes needs your input."
        case .submitting: "Sending your response."
        case .resolved: "Hermes input request answered."
        case .uncertain: "Hermes response status is uncertain."
        case .unavailable: "Hermes input request unavailable."
        }
        return [prefix, prompt.title, prompt.message]
            .compactMap { value in
                guard let value,
                      !value.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ).isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " ")
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(NileTypography.bodySmall)
            .foregroundStyle(NileColors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(
                NileAccessibilityID.blockingPromptStatus
            )
    }
}
