import SwiftUI

struct TalkOrb: View {
    let phase: TalkPhase
    let animated: Bool

    @State private var pulsing = false

    private var shouldPulse: Bool {
        [.listening, .transcribing, .working, .preparingSpeech, .speaking]
            .contains(phase)
    }

    private var color: Color {
        switch phase {
        case .listening, .transcribing:
            NileColors.accent
        case .speaking:
            NileColors.agent
        case .preparingInput, .working, .preparingSpeech, .submitting:
            NileColors.accentStrong
        case .off, .paused:
            NileColors.muted
        }
    }

    var body: some View {
        ZStack {
            NileColors.canvas
            VStack(spacing: 12) {
                NilePixelGrid(color: color, shifted: pulsing, squareSize: 7)

                Text(activityLabel)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }
        }
        .frame(width: 172, height: 148)
        .clipShape(
            RoundedRectangle(
                cornerRadius: NileRadii.window,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.window)
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Talk activity")
        .accessibilityIdentifier(NileAccessibilityID.talkOrb)
        .onAppear {
            guard shouldPulse && animated else {
                return
            }
            withAnimation(
                .easeInOut(duration: 0.75).repeatForever(
                    autoreverses: true
                )
            ) {
                pulsing = true
            }
        }
        .onChange(of: phase) {
            pulsing = false
            guard shouldPulse && animated else {
                return
            }
            withAnimation(
                .easeInOut(duration: 0.75).repeatForever(
                    autoreverses: true
                )
            ) {
                pulsing = true
            }
        }
    }

    private var activityLabel: String {
        switch phase {
        case .listening, .preparingInput:
            "Listening"
        case .speaking, .preparingSpeech:
            "Speaking"
        case .paused:
            "Paused"
        default:
            "Thinking"
        }
    }
}

struct TalkControl: View {
    let label: String
    let symbol: String
    let accessibilityLabel: String
    let accessibilityID: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        enabled ? NileColors.text : NileColors.muted
                    )
                    .frame(width: 44, height: 44)
                    .nileGlass(
                        cornerRadius: NileRadii.control,
                        interactive: enabled
                    )
                Text(label)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(
                        enabled ? NileColors.text : NileColors.muted
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: 92)
            .frame(minHeight: 72)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityID)
    }
}
