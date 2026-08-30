import SwiftUI

struct TalkModeView: View {
    @Bindable var model: SessionListModel
    let sessionTitle: String
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void

    @Environment(\.nileReduceMotion) private var reduceMotion

    private var state: TalkUIState {
        model.talk ?? TalkUIState()
    }

    private var hasBlockingPrompt: Bool {
        model.composerIsBlocked
    }

    private var presentation: TalkPresentation {
        TalkPresentation(
            phase: state.phase,
            workingLabel: model.selectedSessionRuntime?.label,
            hasBlockingPrompt: hasBlockingPrompt,
            runActive: model.isSending
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasBlockingPrompt {
                blockingContent
            } else {
                phaseContent
            }
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NileColors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Talk with Hermes")
        .accessibilityIdentifier(NileAccessibilityID.talkSurface)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: model.endTalkMode) {
                Color.clear
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NileColors.text)
                    }
                    .nileGlass(
                        cornerRadius: NileRadii.control,
                        interactive: true
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End Talk mode")
            .accessibilityIdentifier(NileAccessibilityID.talkClose)

            VStack(spacing: 4) {
                Text("Talk with Hermes")
                    .font(NileTypography.titleMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                Text(sessionTitle)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 64)
        .background(NileColors.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NileColors.border)
                .frame(height: 1)
        }
    }

    private var phaseContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            TalkOrb(
                phase: state.phase,
                animated: !reduceMotion
            )
            Text(presentation.status)
                .font(NileTypography.titleLarge.weight(.semibold))
                .foregroundStyle(NileColors.text)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .accessibilityLabel("Talk status")
                .accessibilityValue(presentation.status)
                .accessibilityIdentifier(NileAccessibilityID.talkStatus)
            Text(presentation.detail)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            talkError
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var blockingContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(presentation.status)
                    .font(NileTypography.titleLarge.weight(.semibold))
                    .foregroundStyle(NileColors.warning)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Talk status")
                    .accessibilityValue(presentation.status)
                    .accessibilityIdentifier(NileAccessibilityID.talkStatus)

                if let prompt = model.talkBlockingPrompt {
                    BlockingPromptRow(
                        prompt: prompt,
                        onRespond: model.respondToBlockingPrompt,
                        onSecureEntry: onSecureEntry,
                        onPermanentApproval: onPermanentApproval
                    )
                    .allowsHitTesting(!model.isStopping)
                    .accessibilityIdentifier(
                        NileAccessibilityID.talkBlockingPrompt
                    )
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "The session is waiting for a response that is not available on this device."
                        )
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(NileColors.text)
                        Text(
                            "End Talk mode to inspect the transcript, or stop the run."
                        )
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(NileColors.panel)
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.card)
                    )
                    .accessibilityIdentifier(
                        NileAccessibilityID.talkBlockingPrompt
                    )
                }
                talkError
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var talkError: some View {
        if let message = state.message ?? model.operationError,
           !message.isBlank {
            Text(message)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.error)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .accessibilityIdentifier(NileAccessibilityID.talkError)
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 0) {
            TalkControl(
                label: "Transcript",
                symbol: "text.bubble",
                accessibilityLabel:
                    "End Talk mode and view transcript",
                accessibilityID: NileAccessibilityID.talkViewTranscript,
                action: model.endTalkMode
            )
            .frame(maxWidth: .infinity)

            Group {
                switch presentation.primaryAction {
                case .pause:
                    TalkControl(
                        label: "Pause",
                        symbol: "pause.fill",
                        accessibilityLabel: "Pause microphone",
                        accessibilityID: NileAccessibilityID.talkPause,
                        action: model.pauseTalkMode
                    )
                case .resume:
                    TalkControl(
                        label: "Resume",
                        symbol: "mic.fill",
                        accessibilityLabel: "Resume listening",
                        accessibilityID: NileAccessibilityID.talkResume,
                        action: model.resumeTalkMode
                    )
                case .interruptSpeech:
                    TalkControl(
                        label: "Listen",
                        symbol: "ear.fill",
                        accessibilityLabel:
                            "Stop Hermes speaking and listen",
                        accessibilityID:
                            NileAccessibilityID.talkInterruptSpeech,
                        action: model.interruptTalkSpeech
                    )
                case .stopRun:
                    TalkControl(
                        label: model.isStopping ? "Stopping" : "Stop",
                        symbol: "stop.fill",
                        accessibilityLabel: model.isStopping
                            ? "Stopping run"
                            : "Stop run",
                        accessibilityID: NileAccessibilityID.composerStop,
                        enabled: !model.isStopping,
                        action: model.stopActiveRun
                    )
                case nil:
                    Color.clear.frame(width: 92, height: 72)
                }
            }
            .frame(width: 92)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.talkPrimary)

            TalkControl(
                label: "End",
                symbol: "xmark",
                accessibilityLabel: "End Talk mode",
                accessibilityID: NileAccessibilityID.talkEnd,
                action: model.endTalkMode
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
