import SwiftUI
import UIKit

struct TranscriptRow: View {
    let entry: TranscriptEntry
    let streaming: Bool
    let onRespond: (String, String) -> Void
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void
    let onOpenAttachment: (String) -> Void
    let delegationTurn: DelegationTurnUI?
    let delegationControlsEnabled: Bool
    let onStopDelegatedAgent: (String) -> Void
    let onOpenDelegatedChild: (String) -> Void

    var body: some View {
        switch entry {
        case let .message(message):
            MessageRow(
                message: message,
                streaming: streaming,
                onOpenAttachment: onOpenAttachment
            )
        case let .tool(tool):
            ToolRow(tool: tool)
        case let .blockingPrompt(prompt):
            BlockingPromptRow(
                prompt: prompt,
                onRespond: onRespond,
                onSecureEntry: onSecureEntry,
                onPermanentApproval: onPermanentApproval
            )
        case let .command(command):
            CommandRow(command: command)
        case .delegation:
            if let delegationTurn {
                DelegationTranscriptGroup(
                    turn: delegationTurn,
                    controlsEnabled: delegationControlsEnabled,
                    onStopAgent: onStopDelegatedAgent,
                    onOpenChild: onOpenDelegatedChild
                )
            }
        }
    }
}

private struct MessageRow: View {
    let message: TranscriptMessage
    let streaming: Bool
    let onOpenAttachment: (String) -> Void

    var body: some View {
        switch message.role {
        case .user:
            if message.isGoalPrompt {
                StandingGoalPromptRow(message: message)
            } else {
                UserMessageBubble(message: message)
            }
        case .assistant:
            AssistantMessageRow(
                message: message,
                streaming: streaming,
                onOpenAttachment: onOpenAttachment
            )
        case .system:
            SystemNoticeRow(message: message)
        }
    }
}

private struct AssistantMessageRow: View {
    let message: TranscriptMessage
    let streaming: Bool
    let onOpenAttachment: (String) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.content.isEmpty {
                ZStack(alignment: .topTrailing) {
                    NileMarkdownText(
                        content: message.content,
                        baseColor: NileColors.prose,
                        strongColor: NileColors.proseStrong,
                        isStreaming: streaming
                    )
                    .padding(.trailing, streaming ? 0 : 44)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !streaming {
                        Button {
                            UIPasteboard.general.string = message.content
                            copied = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        } label: {
                            Image(
                                systemName: copied
                                    ? "checkmark"
                                    : "square.on.square"
                            )
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                copied
                                    ? NileColors.accent
                                    : NileColors.muted
                            )
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(
                                RoundedRectangle(
                                    cornerRadius: NileRadii.control
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            copied ? "Response copied" : "Copy response"
                        )
                        .accessibilityIdentifier(
                            NileAccessibilityID.copyAssistantResponse(message.id)
                        )
                    }
                }
            } else if message.images.isEmpty && message.attachments.isEmpty {
                Text(" ")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(NileColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }

            ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                MessageImageView(image: image, maxHeight: 320)
            }
            ForEach(
                Array(message.attachments.enumerated()),
                id: \.offset
            ) { _, attachment in
                MessageAttachmentCard(
                    attachment: attachment,
                    onOpen: { onOpenAttachment(attachment.path) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Assistant message")
                .accessibilityIdentifier(
                    NileAccessibilityID.transcriptMessage(message.id)
                )
        }
    }

}

private struct UserMessageBubble: View {
    let message: TranscriptMessage

    private let bubble = UnevenRoundedRectangle(
        topLeadingRadius: NileRadii.card,
        bottomLeadingRadius: NileRadii.card,
        bottomTrailingRadius: 4,
        topTrailingRadius: NileRadii.card
    )

    var body: some View {
        HStack {
            Spacer(minLength: 54)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(
                    Array(message.images.enumerated()),
                    id: \.offset
                ) { _, image in
                    MessageImageView(image: image, maxHeight: 300)
                        .frame(maxWidth: 300, alignment: .trailing)
                }
                if message.pending {
                    Text("queued · steering")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.muted)
                }
                if !message.content.isEmpty || message.images.isEmpty {
                    Text(message.content.isEmpty ? " " : message.content)
                        .nileTextStyle(NileTypography.bodyMediumStyle)
                        .foregroundStyle(
                            NileColors.text
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            NileColors.panelAlt
                        )
                        .clipShape(bubble)
                        .overlay {
                            bubble.stroke(
                                NileColors.border,
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: message.pending ? [5, 4] : []
                                )
                            )
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(
            NileAccessibilityID.transcriptMessage(message.id)
        )
    }
}
