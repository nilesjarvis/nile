import SwiftUI
import UIKit

struct TranscriptView: View {
    let entries: [TranscriptEntry]
    let scrollOwner: TranscriptScrollOwner?
    let scrollCoordinator: TranscriptScrollCoordinator
    let delegationTurns: [DelegationTurnUI]
    let pinnedDelegationTurnID: String?
    let delegationControlsEnabled: Bool
    let activeTodos: [TodoItem]?
    let isSending: Bool
    let commandCatalog: CommandCatalog?
    var viewportInteractionEnabled = true
    var viewportAccessibilityHidden = false
    let onSelectQuickStart: (String) -> Void
    let onRespondToBlockingPrompt: (String, String) -> Void
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void
    let onOpenAttachment: (String) -> Void
    let onStopDelegatedAgent: (String) -> Void
    let onOpenDelegatedChild: (String) -> Void
    @Environment(\.nileReduceMotion) private var reduceMotion
    @State private var isAnchored = true
    @State private var jumpToBottomRevision = 0
    @State private var expandedToolGroupID: String?
    @State private var toolGroupRipple: ToolActivityRipple?
    @State private var toolGroupRippleID: String?
    @State private var toolGroupRippleGeneration = 0
    @State private var toolGroupRippleResetTask: Task<Void, Never>?

    var body: some View {
        let presentation = TranscriptPresentation(
            entries: entries,
            isSending: isSending,
            pinnedDelegationTurnID: pinnedDelegationTurnID
        )
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    TranscriptViewport(
                        owner: scrollOwner,
                        scrollState: scrollCoordinator,
                        lastUserEntryID: presentation.lastUserEntryID,
                        jumpToBottomRevision: jumpToBottomRevision,
                        automaticTailPinEnabled:
                            expandedToolGroupID == nil,
                        retainsTopInset: expandedToolGroupID != nil,
                        interactionEnabled: viewportInteractionEnabled,
                        accessibilityHidden: viewportAccessibilityHidden,
                        items: viewportItems(
                            presentation: presentation
                        ),
                        actions: TranscriptViewportActions(
                            onSelectQuickStart: onSelectQuickStart,
                            onRespondToBlockingPrompt:
                                onRespondToBlockingPrompt,
                            onSecureEntry: onSecureEntry,
                            onPermanentApproval: onPermanentApproval,
                            onOpenAttachment: onOpenAttachment,
                            onStopDelegatedAgent: onStopDelegatedAgent,
                            onOpenDelegatedChild: onOpenDelegatedChild,
                            onToggleToolGroup:
                                updateToolGroupDisclosureLayout,
                            onRippleToolGroup: startToolGroupRipple
                        ),
                        onAnchoredChange: { anchored in
                            isAnchored = anchored
                        },
                        onAnchorTransition: anchorTransition
                    )

                    if !isAnchored {
                        Button(action: jumpToBottom) {
                            NileMaterialIcon(
                                kind: .keyboardArrowDown
                            )
                            .foregroundStyle(
                                presentation.hasBlockingPrompt
                                    ? NileColors.warning
                                    : NileColors.link
                            )
                            .frame(width: 24, height: 24)
                            .frame(width: 48, height: 48)
                            .background(
                                presentation.hasBlockingPrompt
                                    ? NileColors.warning.opacity(0.14)
                                    : NileColors.panel
                            )
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(
                                    presentation.hasBlockingPrompt
                                        ? NileColors.warning
                                        : NileColors.border,
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(14)
                        .accessibilityLabel(
                            presentation.hasBlockingPrompt
                                ? "View request"
                                : "Scroll to bottom"
                        )
                        .accessibilityIdentifier(
                            NileAccessibilityID.transcriptJumpToBottom
                        )
                        .transition(
                            .scale(scale: 0.4).combined(with: .opacity)
                        )
                    }
                }
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(
                            response: 0.3,
                            dampingFraction: 0.62
                        ),
                    value: isAnchored
                )
            }

            if isSending, let activeTodos, !activeTodos.isEmpty {
                ActiveTodoPlan(todos: activeTodos)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
        }
        .onDisappear {
            toolGroupRippleResetTask?.cancel()
            toolGroupRippleResetTask = nil
        }
        .onChange(of: scrollOwner) { _, _ in
            resetTransientToolPresentation()
        }
    }

    private func viewportItems(
        presentation: TranscriptPresentation
    ) -> [TranscriptViewportItem] {
        if entries.isEmpty {
            return [
                TranscriptViewportItem(
                    id: "transcript-launchpad",
                    content: .launchpad(
                        commandCatalog.launchpadQuickStarts
                    ),
                    reduceMotion: reduceMotion
                ),
            ]
        }
        return presentation.rows.map { row in
            let delegationTurn: DelegationTurnUI? = {
                guard case let .entry(.delegation(anchor)) = row else {
                    return nil
                }
                return delegationTurns.first { $0.id == anchor.turnID }
            }()
            let groupID: String? = {
                guard case let .toolGroup(tools) = row else {
                    return nil
                }
                return tools.first?.id ?? "empty-tool-group"
            }()
            return TranscriptViewportItem(
                id: row.id,
                content: .row(row),
                streaming: row.id == presentation.streamingEntryID,
                delegationTurn: delegationTurn,
                delegationControlsEnabled: delegationControlsEnabled,
                toolGroupExpanded: groupID == expandedToolGroupID,
                toolGroupRipple:
                    groupID == toolGroupRippleID
                        ? toolGroupRipple
                        : nil,
                reduceMotion: reduceMotion
            )
        }
    }

    private func updateToolGroupDisclosureLayout(
        _ groupID: String,
        expanded: Bool
    ) {
        if expanded {
            expandedToolGroupID = groupID
            return
        }
        guard expandedToolGroupID == groupID else {
            return
        }
        expandedToolGroupID = nil
    }

    private func startToolGroupRipple(
        _ groupID: String,
        at origin: CGPoint
    ) {
        toolGroupRippleResetTask?.cancel()
        toolGroupRippleGeneration &+= 1
        let generation = toolGroupRippleGeneration
        toolGroupRippleID = groupID
        toolGroupRipple = ToolActivityRipple(
            origin: origin,
            generation: generation
        )
        toolGroupRippleResetTask = Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(reduceMotion ? 150 : 320)
            )
            guard !Task.isCancelled,
                  toolGroupRipple?.generation == generation else {
                return
            }
            toolGroupRipple = nil
            toolGroupRippleID = nil
            toolGroupRippleResetTask = nil
        }
    }

    private func resetTransientToolPresentation() {
        toolGroupRippleResetTask?.cancel()
        toolGroupRippleResetTask = nil
        expandedToolGroupID = nil
        toolGroupRipple = nil
        toolGroupRippleID = nil
    }

    private func jumpToBottom() {
        guard let scrollOwner else {
            return
        }
        let presentation = scrollCoordinator.jumpToBottom(
            owner: scrollOwner
        )
        isAnchored = presentation.isAnchored
        jumpToBottomRevision &+= 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func anchorTransition(
        _ transition: TranscriptScrollAnchorTransition
    ) {
        switch transition {
        case .leftBottom:
            UISelectionFeedbackGenerator().selectionChanged()
        case .reachedBottom:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
