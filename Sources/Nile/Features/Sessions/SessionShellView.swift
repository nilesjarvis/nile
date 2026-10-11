import SwiftUI
import QuickLook

struct SessionShellView: View {
    @Bindable var model: SessionListModel
    let showSettings: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.nileReduceMotion) private var reduceMotion
    @State private var securePrompt: TranscriptBlockingPrompt?
    @State private var permanentApprovalPrompt: TranscriptBlockingPrompt?

    var body: some View {
        GeometryReader { geometry in
            let maximumExpandedHeight = min(
                max(430, geometry.size.height * 0.60),
                max(430, geometry.size.height - 104)
            )
            ZStack(alignment: .top) {
                NileColors.background
                    .ignoresSafeArea()
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Session shell")
                    .accessibilityIdentifier(NileAccessibilityID.sessionShell)

                if model.talk == nil {
                    SessionWorkspaceView(
                        model: model,
                        showSettings: showSettings,
                        onSecureEntry: { securePrompt = $0 },
                        onPermanentApproval: {
                            permanentApprovalPrompt = $0
                        }
                    )
                    .padding(.top, 78)

                    if model.isExpanded {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(
                                    reduceMotion
                                        ? nil
                                        : .smooth(duration: 0.24)
                                ) {
                                    model.isExpanded = false
                                }
                            }
                            .accessibilityLabel("Close sessions")
                    }

                    SessionSectionView(
                        model: model,
                        maximumExpandedHeight: maximumExpandedHeight
                    )
                }

                if model.isClaimDialogVisible {
                    ClaimTerminalSessionDialog(model: model)
                        .transition(.opacity)
                        .zIndex(10)
                }

                if model.isModelPickerVisible {
                    ModelPickerOverlay(model: model)
                        .zIndex(15)
                }

                if model.isRenameDialogVisible {
                    RenameSessionDialog(model: model)
                        .transition(.opacity)
                        .zIndex(20)
                }

                if let securePrompt {
                    SecureBlockingPromptOverlay(
                        prompt: securePrompt,
                        onDismiss: { self.securePrompt = nil },
                        onSubmit: { value in
                            self.securePrompt = nil
                            model.respondToBlockingPrompt(
                                promptID: securePrompt.id,
                                response: value
                            )
                        }
                    )
                    .transition(.opacity)
                    .zIndex(50)
                }

                if let confirmation = model.modelSwitchConfirmation {
                    ModelSwitchConfirmationOverlay(
                        confirmation: confirmation,
                        updating: model.isUpdatingSessionControls,
                        canConfirm: model.canConfirmModelSwitch,
                        error: model.operationError,
                        onDismissError: model.dismissOperationError,
                        onDismiss: model.dismissModelSwitchConfirmation,
                        onConfirm: model.confirmModelSwitch
                    )
                    .transition(.opacity)
                    .zIndex(25)
                }

                if let permanentApprovalPrompt {
                    PermanentApprovalOverlay(
                        onDismiss: {
                            self.permanentApprovalPrompt = nil
                        },
                        onConfirm: {
                            self.permanentApprovalPrompt = nil
                            model.respondToBlockingPrompt(
                                promptID: permanentApprovalPrompt.id,
                                response: ApprovalChoice.always.rawValue
                            )
                        }
                    )
                    .transition(.opacity)
                    .zIndex(50)
                }

                if model.talk != nil {
                    TalkModeView(
                        model: model,
                        sessionTitle: model.sessions.first {
                            $0.id == model.selectedSessionID
                        }?.title ?? model.selectedSessionID ?? "Hermes",
                        onSecureEntry: { securePrompt = $0 },
                        onPermanentApproval: {
                            permanentApprovalPrompt = $0
                        }
                    )
                    .transition(.opacity)
                    .zIndex(40)
                }
            }
        }
        .onChange(of: model.selectedSessionID) {
            securePrompt = nil
            permanentApprovalPrompt = nil
        }
        .onChange(of: model.pendingActionableBlockingPromptIDs) { _, ids in
            if let securePrompt,
               !ids.contains(securePrompt.id) {
                self.securePrompt = nil
            }
            if let permanentApprovalPrompt,
               !ids.contains(permanentApprovalPrompt.id) {
                self.permanentApprovalPrompt = nil
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.onAppForegroundChanged(phase == .active)
            if phase != .active {
                securePrompt = nil
                permanentApprovalPrompt = nil
            }
        }
        .onDisappear {
            model.onSessionSurfaceHidden()
        }
        .sheet(
            item: Binding(
                get: { model.openedAttachment },
                set: { value in
                    if value == nil {
                        model.dismissOpenedAttachment()
                    }
                }
            )
        ) { attachment in
            AttachmentPreviewSheet(
                attachment: attachment,
                onDismiss: model.dismissOpenedAttachment
            )
        }
        .sheet(
            isPresented: Binding(
                get: { model.isGoalSheetVisible },
                set: { model.setGoalSheetVisible($0) }
            )
        ) {
            GoalSheet(model: model)
        }
        .sheet(
            isPresented: Binding(
                get: { model.isContextSheetVisible },
                set: { model.setContextSheetVisible($0) }
            )
        ) {
            ContextBreakdownSheet(model: model)
        }
        .sheet(
            isPresented: Binding(
                get: { model.isStatsSheetVisible },
                set: { model.setStatsSheetVisible($0) }
            )
        ) {
            GatewayStatsSheet(model: model)
        }
    }
}

private struct SessionWorkspaceView: View {
    @Bindable var model: SessionListModel
    let showSettings: () -> Void
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void
    @State private var sessionActionsPresented = false
    @FocusState private var composerFocused: Bool

    private var selected: HermesSession? {
        model.sessions.first { $0.id == model.selectedSessionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selected {
                HStack(alignment: .center, spacing: 12) {
                    if model.isOpeningSession {
                        sessionHeaderIdentity(
                            selected,
                            switching: true
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 48,
                            alignment: .leading
                        )
                    } else {
                        Button {
                            model.setModelPickerVisible(true)
                        } label: {
                            sessionHeaderIdentity(
                                selected,
                                switching: false
                            )
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 48,
                                alignment: .leading
                            )
                        }
                        .buttonStyle(SessionHeaderButtonStyle())
                        .disabled(
                            model.isReadOnlySession
                                || model.connectionPhase != .online
                                || model.isSending
                                || model.isAttaching
                                || model.isUpdatingSessionControls
                        )
                        .accessibilityLabel(
                            "Change model and view reasoning"
                        )
                        .accessibilityIdentifier(
                            NileAccessibilityID.modelControls
                        )
                    }
                    workspaceActionRail
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(NileColors.panel)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(NileColors.border)
                        .frame(height: 1)
                }
            }

            if model.state == .loading || model.isOpeningSession {
                SessionSwitchingWorkspace(
                    presentation: model.sessionSwitchPresentation,
                    scrollCoordinator:
                        model.transcriptScrollCoordinator
                )
            } else if selected == nil {
                Spacer()
                VStack(spacing: 10) {
                    Text(model.sessions.isEmpty ? "No sessions yet" : "No open session")
                        .font(NileTypography.titleMedium.weight(.semibold))
                        .foregroundStyle(NileColors.text)
                    Text(
                        model.hasDraftWithoutOpenSession
                            ? "Your unsent draft is safe on this device. Create a session to continue."
                            : "Create a session to start a conversation with Hermes."
                    )
                        .font(NileTypography.bodyMedium)
                        .foregroundStyle(NileColors.muted)
                        .multilineTextAlignment(.center)
                    Button {
                        UINotificationFeedbackGenerator()
                            .notificationOccurred(.success)
                        Task { await model.createSession() }
                    } label: {
                        Text("Create session")
                            .font(
                                NileTypography.bodyMedium.weight(.semibold)
                            )
                            .foregroundStyle(NileColors.onAccent)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 49)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(NileColors.accentStrong)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canCreateSession)
                    .accessibilityIdentifier(
                        NileAccessibilityID.createSessionEmpty
                    )
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(NileAccessibilityID.sessionEmpty)
                Spacer()
            } else {
                SessionTranscriptRegion(
                    model: model,
                    onSecureEntry: onSecureEntry,
                    onPermanentApproval: onPermanentApproval
                )
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier(NileAccessibilityID.sessionError)
            }

            if !model.isOpeningSession {
                if model.isReadOnlySession {
                    ReadOnlySessionBar(model: model, session: selected)
                } else if model.showsComposer {
                    if let turn = model.pinnedDelegationTurn {
                        DelegatedActivityOverview(
                            turn: turn,
                            controlsEnabled:
                                model.delegationControlsEnabled,
                            onStopAgent:
                                model.interruptDelegatedAgent,
                            onOpenChild:
                                model.openDelegatedChild
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .offset(y: -6)
                    }
                    if let goal = model.goal {
                        GoalStatusCard(model: model, goal: goal)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .offset(y: -3.67)
                    }
                    SessionComposerView(
                        model: model,
                        composerFocus: $composerFocused
                    )
                }
            }
        }
        .onChange(of: model.selectedSessionID) { _, _ in
            composerFocused = false
        }
        .onChange(of: model.isOpeningSession) { _, isOpening in
            if isOpening {
                composerFocused = false
            }
        }
        .onDisappear {
            composerFocused = false
        }
    }

    @ViewBuilder
    private func sessionHeaderIdentity(
        _ session: HermesSession,
        switching: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? session.id)
                .font(NileTypography.titleMedium)
                .foregroundStyle(NileColors.text)
                .lineLimit(1)
            if switching {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(NileColors.accent)
                        .accessibilityHidden(true)
                    Text("Switching session…")
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Switching to \(session.title ?? session.id)"
                )
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(
                    NileAccessibilityID.sessionSwitchStatus
                )
            } else {
                Text(sessionSubtitle(session))
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(
                        model.composerIsBlocked
                            ? NileColors.warning
                            : NileColors.muted
                    )
                    .lineLimit(1)
                    .accessibilityIdentifier(
                        NileAccessibilityID
                            .sessionConnectionStatus
                    )
            }
        }
    }

    private var workspaceActionRail: some View {
        HStack(spacing: 0) {
            Button {
                sessionActionsPresented = true
            } label: {
                Group {
                    if model.isRenamingSession {
                        ProgressView()
                            .controlSize(.small)
                            .tint(NileColors.accent)
                    } else {
                        Image(systemName: "ellipsis")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(SessionHeaderActionButtonStyle())
            .accessibilityLabel("Session actions")
            .accessibilityIdentifier(
                NileAccessibilityID.sessionActionsMenu
            )
            .popover(
                isPresented: $sessionActionsPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                sessionActionsPopover
                    .presentationCompactAdaptation(.popover)
            }

            Rectangle()
                .fill(NileColors.border.opacity(0.5))
                .frame(width: 0.5, height: 24)
                .accessibilityHidden(true)

            Button(action: showSettings) {
                NileMaterialIcon(kind: .settings)
                    .frame(width: 16, height: 16)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SessionHeaderActionButtonStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(NileAccessibilityID.sessionSettings)
        }
        .background {
            RoundedRectangle(
                cornerRadius: NileRadii.control,
                style: .continuous
            )
                .fill(NileColors.panelAlt)
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: NileRadii.control,
                style: .continuous
            )
                .strokeBorder(NileColors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var sessionActionsPopover: some View {
        VStack(spacing: 2) {
            if model.canShowRenameSession {
                sessionPopoverButton(
                    kind: .edit,
                    label: "Rename session",
                    identifier: NileAccessibilityID.renameSession
                ) {
                    sessionActionsPresented = false
                    model.setRenameDialogVisible(true)
                }
                .disabled(model.isRenamingSession)
            }

            sessionPopoverButton(
                kind: .stats,
                label: "Usage statistics",
                identifier: NileAccessibilityID.statsButton
            ) {
                sessionActionsPresented = false
                model.setStatsSheetVisible(true)
            }
        }
        .padding(8)
        .frame(minWidth: 240)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            NileAccessibilityID.sessionActionsPopover
        )
    }

    private func sessionPopoverButton(
        kind: NileMaterialIcon.Kind,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                NileMaterialIcon(kind: kind)
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(NileTypography.bodyLarge)
                Spacer(minLength: 16)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionPopoverActionButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func sessionSubtitle(_ session: HermesSession) -> String {
        switch model.connectionPhase {
        case .offline:
            return "Waiting for network…"
        case .reconnecting:
            return "Reconnecting…"
        case .restoring:
            return "Restoring session…"
        case .failed:
            return "Connection lost"
        case .online:
            break
        }
        if model.isReadOnlySession {
            return "\(session.visibleSourceLabel ?? "Terminal") · read-only mirror"
        }
        if model.composerIsBlocked {
            return "Needs input"
        }
        if let info = model.liveSession?.info {
            let reportedModel = info.model?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = reportedModel.flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Model unavailable"
            let normalizedEffort = info.reasoningEffort?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let effort = switch normalizedEffort {
            case "none":
                "off"
            case let value? where !value.isEmpty:
                value
            default:
                "default"
            }
            return "\(modelName) · effort \(effort) ▾"
        }
        return session.visibleSourceLabel ?? "Hermes session"
    }
}

private struct SessionTranscriptRegion: View {
    @Bindable var model: SessionListModel
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void

    var body: some View {
        TranscriptView(
            entries: model.transcriptEntries,
            scrollOwner: model.transcriptScrollOwner,
            scrollCoordinator: model.transcriptScrollCoordinator,
            delegationTurns: model.delegationTurns,
            pinnedDelegationTurnID: model.pinnedDelegationTurnID,
            delegationControlsEnabled: model.delegationControlsEnabled,
            activeTodos: model.activeTodos,
            isSending: model.isSending,
            commandCatalog: model.commandCatalog,
            onSelectQuickStart: model.updateComposer,
            onRespondToBlockingPrompt: model.respondToBlockingPrompt,
            onSecureEntry: onSecureEntry,
            onPermanentApproval: onPermanentApproval,
            onOpenAttachment: model.openAttachment,
            onStopDelegatedAgent: model.interruptDelegatedAgent,
            onOpenDelegatedChild: model.openDelegatedChild
        )
    }
}

private struct SessionSwitchingWorkspace: View {
    let presentation: SessionSwitchPresentation?
    let scrollCoordinator: TranscriptScrollCoordinator

    var body: some View {
        Group {
            if let presentation {
                TranscriptView(
                    entries: presentation.entries,
                    scrollOwner: presentation.scrollOwner,
                    scrollCoordinator: scrollCoordinator,
                    delegationTurns: presentation.delegationTurns,
                    pinnedDelegationTurnID:
                        presentation.pinnedDelegationTurnID,
                    delegationControlsEnabled: false,
                    activeTodos: presentation.activeTodos,
                    isSending: presentation.isSending,
                    commandCatalog: nil,
                    viewportInteractionEnabled: false,
                    viewportAccessibilityHidden: true,
                    onSelectQuickStart: { _ in },
                    onRespondToBlockingPrompt: { _, _ in },
                    onSecureEntry: { _ in },
                    onPermanentApproval: { _ in },
                    onOpenAttachment: { _ in },
                    onStopDelegatedAgent: { _ in },
                    onOpenDelegatedChild: { _ in }
                )
                .saturation(0.72)
                .opacity(0.48)
                .overlay {
                    NileColors.background.opacity(0.12)
                }
                .disabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                SessionTranscriptPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionTranscriptPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 36)
            placeholderBubble(
                alignment: .leading,
                width: 0.72,
                lineWidths: [0.76, 0.48]
            )
            placeholderBubble(
                alignment: .trailing,
                width: 0.56,
                lineWidths: [0.68]
            )
            placeholderBubble(
                alignment: .leading,
                width: 0.64,
                lineWidths: [0.82, 0.54]
            )
            Spacer()
                .frame(height: 28)
        }
        .padding(.horizontal, 14)
        .accessibilityRepresentation {
            Text("Loading conversation")
                .accessibilityIdentifier(
                    NileAccessibilityID.sessionSwitchPlaceholder
                )
        }
    }

    private func placeholderBubble(
        alignment: Alignment,
        width: CGFloat,
        lineWidths: [CGFloat]
    ) -> some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) {
                    _, lineWidth in
                    Capsule()
                        .fill(NileColors.border.opacity(0.45))
                        .frame(
                            width: geometry.size.width
                                * width
                                * lineWidth,
                            height: 8
                        )
                }
            }
            .padding(12)
            .frame(
                width: geometry.size.width * width,
                alignment: .leading
            )
            .background(NileColors.panel.opacity(0.72))
            .clipShape(
                RoundedRectangle(cornerRadius: NileRadii.card)
            )
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(height: lineWidths.count == 1 ? 40 : 55)
    }
}

private struct SessionHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct SessionHeaderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed
                    ? NileColors.accent
                    : NileColors.muted
            )
            .background(
                configuration.isPressed
                    ? NileColors.accentSoft
                    : Color.clear
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct SessionPopoverActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(NileColors.text)
            .background(
                configuration.isPressed
                    ? NileColors.surfaceHover
                    : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: NileRadii.small,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

private struct AttachmentPreviewSheet: View {
    let attachment: CachedAttachment
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            QuickLookAttachmentPreview(url: attachment.url)
                .background(NileColors.background)
                .navigationTitle(attachment.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done", action: onDismiss)
                            .foregroundStyle(NileColors.text)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: attachment.url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(NileColors.text)
                        }
                        .accessibilityLabel("Share attachment")
                        .accessibilityIdentifier(
                            NileAccessibilityID.shareAttachment
                        )
                    }
                }
        }
        .accessibilityIdentifier(NileAccessibilityID.attachmentPreview)
    }
}

private struct QuickLookAttachmentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QLPreviewController,
        context: Context
    ) {}

    final class Coordinator:
        NSObject,
        QLPreviewControllerDataSource
    {
        let url: NSURL

        init(url: URL) {
            self.url = url as NSURL
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url
        }
    }
}

private struct ReadOnlySessionBar: View {
    @Bindable var model: SessionListModel
    let session: HermesSession?

    private var source: String {
        session?.visibleSourceLabel ?? "Terminal"
    }

    private var runtime: SessionRuntimePresentation? {
        model.selectedSessionRuntime
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(
                    model.isClaimingSession
                        ? "Claiming \(source) session…"
                        : "\(source) session · read-only mirror"
                )
                .font(NileTypography.bodyLarge)
                .foregroundStyle(
                    runtime != nil || model.isClaimingSession
                        ? NileColors.text
                        : NileColors.muted
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                Button {
                    model.setClaimDialogVisible(true)
                } label: {
                    Group {
                        if model.isClaimingSession {
                            ProgressView()
                                .tint(NileColors.muted)
                        } else {
                            Text("Claim")
                                .font(NileTypography.bodySmall.weight(.semibold))
                                .foregroundStyle(NileColors.onAccent)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(
                        model.isClaimingSession
                            ? NileColors.border
                            : NileColors.accentStrong
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.control)
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    model.state != .loaded
                        || model.isOpeningSession
                        || model.isClaimingSession
                )
                .accessibilityIdentifier(NileAccessibilityID.claimSession)
                .padding(.trailing, 4)
            }
            .frame(height: 56)

            Rectangle()
                .fill(NileColors.border)
                .frame(height: 1)

            Text(statusText)
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 12)
                .padding(.top, 7)
                .padding(.trailing, 12)
                .padding(.bottom, 11)
        }
        .background(NileColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.sheet))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.sheet)
                .stroke(
                    model.isClaimingSession
                        ? NileColors.accentStrong
                        : NileColors.border.opacity(0.55),
                    lineWidth: model.isClaimingSession ? 2 : 1
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Read-only terminal session")
                .accessibilityIdentifier(
                    NileAccessibilityID.readOnlySession
                )
        }
    }

    private var statusText: String {
        switch runtime {
        case .starting:
            "Wait for the terminal session to finish starting."
        case .working:
            "Stop the terminal turn before claiming."
        case .needsInput:
            "Resolve or stop the terminal request before claiming."
        case nil:
            "History refreshes every 5 seconds."
        }
    }
}

private struct ClaimTerminalSessionDialog: View {
    @Bindable var model: SessionListModel

    private var runtime: SessionRuntimePresentation? {
        model.selectedSessionRuntime
    }

    private var terminalBusy: Bool {
        runtime != nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    model.setClaimDialogVisible(false)
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("Claim terminal session?")
                    .font(NileTypography.bodyMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                Text(explanation)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(
                        terminalBusy ? NileColors.warning : NileColors.muted
                    )
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Button("Cancel") {
                        model.setClaimDialogVisible(false)
                    }
                    .buttonStyle(.plain)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)

                    Spacer()

                    Button {
                        Task { await model.claimCurrentSession() }
                    } label: {
                        Text(confirmLabel)
                            .font(NileTypography.bodySmall.weight(.semibold))
                            .foregroundStyle(
                                model.isClaimingSession || terminalBusy
                                    ? NileColors.muted
                                    : NileColors.link
                            )
                            .frame(minHeight: 48)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isClaimingSession || terminalBusy)
                    .accessibilityIdentifier(
                        NileAccessibilityID.confirmClaimSession
                    )
                }
            }
            .padding(14)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
            .padding(.horizontal, 24)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Claim terminal session")
                    .accessibilityIdentifier(
                        NileAccessibilityID.claimDialog
                    )
            }
        }
    }

    private var explanation: String {
        switch runtime {
        case .starting:
            "Hermes is still starting this terminal session. Let it settle and close that terminal before claiming it in Nile."
        case .working:
            "The terminal is still running this session. Stop its current turn and close that terminal before claiming it in Nile."
        case .needsInput:
            "The terminal session is waiting for input. Resolve or stop that request and close the terminal before claiming it in Nile."
        case nil:
            "This resumes the stored conversation as a live Nile session. Hermes cannot close the original terminal through this API, so close that terminal first to avoid two processes writing to the same conversation."
        }
    }

    private var confirmLabel: String {
        if model.isClaimingSession {
            return "Claiming…"
        }
        return switch runtime {
        case .starting:
            "Terminal starting"
        case .working:
            "Terminal working"
        case .needsInput:
            "Needs input"
        case nil:
            "Claim in Nile"
        }
    }
}

private struct RenameSessionDialog: View {
    @Bindable var model: SessionListModel
    @State private var title: String

    init(model: SessionListModel) {
        self.model = model
        let selected = model.sessions.first {
            $0.id == model.selectedSessionID
        }
        _title = State(
            initialValue:
                selected?.title ?? model.selectedSessionID ?? ""
        )
    }

    private var placeholder: String {
        model.selectedSessionID ?? "Session title"
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && !model.isRenamingSession
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !model.isRenamingSession else {
                        return
                    }
                    model.setRenameDialogVisible(false)
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("Rename session")
                    .font(NileTypography.bodyMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)

                outlinedTitleField

                if let error = model.renameSessionError {
                    NileComposeText(
                        text: error,
                        style: NileTypography.bodySmallStyle,
                        color: UIColor(NileColors.error),
                        backgroundColor: UIColor(NileColors.panelAlt),
                        fillsWidth: true
                    )
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(NileColors.error.opacity(0.12))
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(error)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier(
                        NileAccessibilityID.renameSessionError
                    )
                }

                NileComposeText(
                    text:
                        "Only the currently open Hermes session can be\nrenamed.",
                    style: NileTypography.bodySmallStyle,
                    color: UIColor(NileColors.muted),
                    backgroundColor: UIColor(NileColors.panelAlt),
                    fillsWidth: true
                )
                .padding(10)
                .frame(minHeight: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NileColors.panelAlt)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(
                    "Only the currently open Hermes session can be renamed."
                )

                HStack(spacing: 0) {
                    Button {
                        model.setRenameDialogVisible(false)
                    } label: {
                        Text("Cancel")
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                            .frame(minWidth: 48, minHeight: 48)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRenamingSession)
                    .accessibilityIdentifier(
                        NileAccessibilityID.renameSessionCancel
                    )

                    Spacer()

                    Button {
                        model.renameCurrentSession(title)
                    } label: {
                        Text(
                            model.isRenamingSession ? "Saving…" : "Save"
                        )
                        .font(NileTypography.bodySmall.weight(.semibold))
                        .foregroundStyle(
                            canSave
                                ? NileColors.link
                                : NileColors.muted
                        )
                        .frame(minWidth: 48, minHeight: 48)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityIdentifier(
                        NileAccessibilityID.renameSessionSave
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: 320)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Rename session")
                    .accessibilityIdentifier(
                        NileAccessibilityID.renameSessionDialog
                    )
            }
            .padding(.horizontal, 24)
        }
    }

    private var outlinedTitleField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(NileColors.border, lineWidth: 1)
            TextField(
                "",
                text: $title,
                prompt: Text(placeholder)
                    .foregroundStyle(NileColors.muted)
            )
            .textFieldStyle(.plain)
            .font(NileTypography.bodyMedium)
            .foregroundStyle(NileColors.text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .disabled(model.isRenamingSession)
            .submitLabel(.done)
            .onSubmit {
                guard canSave else {
                    return
                }
                model.renameCurrentSession(title)
            }
            .accessibilityLabel("Title")
            .accessibilityIdentifier(
                NileAccessibilityID.renameSessionTitle
            )

            Text("Title")
                .font(NileTypography.bodySmall)
                .foregroundStyle(NileColors.muted)
                .padding(.horizontal, 4)
                .background(NileColors.panel)
                .offset(x: 8, y: -7)
        }
        .frame(height: 56)
        .padding(.top, 7)
    }
}

struct SessionCreateSwipePolicy {
    static let commitFraction: CGFloat = 0.85
    static let flingVelocity: CGFloat = 500
    static let initialResistance: CGFloat = 0.45

    static func canBegin(
        collapsed: Bool,
        atStartEdge: Bool,
        sessionCount: Int,
        canCreateSession: Bool
    ) -> Bool {
        collapsed
            && atStartEdge
            && sessionCount > 0
            && canCreateSession
    }

    static func shouldClaim(
        translation: CGSize,
        touchSlop: CGFloat = 10
    ) -> Bool {
        translation.width > touchSlop
            && translation.width > abs(translation.height)
    }

    static func resistedOffset(
        currentOffset: CGFloat,
        delta: CGFloat,
        pillWidth: CGFloat
    ) -> CGFloat {
        guard pillWidth > 0 else {
            return 0
        }
        let progress = min(max(currentOffset / pillWidth, 0), 1)
        let resistance =
            initialResistance + (1 - initialResistance) * progress
        return min(max(currentOffset + delta * resistance, 0), pillWidth)
    }

    static func shouldCreate(
        fingerX: CGFloat,
        stripWidth: CGFloat,
        velocityX: CGFloat
    ) -> Bool {
        guard stripWidth > 0 else {
            return false
        }
        return fingerX >= stripWidth * commitFraction
            || velocityX > flingVelocity
    }
}

struct SessionExpandSwipePolicy {
    static func shouldExpand(
        translation: CGSize,
        touchSlop: CGFloat = 10
    ) -> Bool {
        translation.height > touchSlop
            && translation.height > abs(translation.width)
    }
}

private struct SessionSectionView: View {
    @Bindable var model: SessionListModel
    let maximumExpandedHeight: CGFloat
    @Environment(\.nileReduceMotion) private var reduceMotion
    @State private var collapsedStripAtStartEdge = true
    @State private var stripWidth: CGFloat = 0
    @State private var createSwipeOffset: CGFloat = 0
    @State private var createSwipeFingerX: CGFloat = 0
    @State private var createSwipeStartedAt: Date?
    @State private var createSwipeLastTranslation: CGFloat = 0
    @State private var createSwipeEligible = false
    @State private var createSwipeClaimed = false
    @State private var createSwipeReady = false
    @State private var positionedCollapsedSelection = false
    @State private var searchPresented = false

    private let createSwipePillWidth: CGFloat = 170
    private let createSwipePillSpacing: CGFloat = 8
    private let collapsedStripCoordinateSpace =
        "nile.collapsed-session-strip"

    private var expandedHeight: CGFloat {
        let isSearching = searchPresented || !model.searchText.isEmpty
        let rowSourceCount =
            isSearching ? model.displayedSessions.count : model.sessions.count
        let visibleRowCount = min(max(rowSourceCount, 1), 5)
        let searchHeight: CGFloat = isSearching ? 60 : 0
        let contentHeight =
            118 + CGFloat(visibleRowCount) * 63 + searchHeight
        return min(maximumExpandedHeight, max(250, contentHeight))
    }

    var body: some View {
        Group {
            if model.isExpanded {
                expandedSheet
                    .transition(
                        .move(edge: .top).combined(with: .opacity)
                    )
            } else {
                collapsedStrip.transition(.opacity)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: model.isExpanded ? expandedHeight : 102,
            maxHeight: model.isExpanded ? expandedHeight : 102,
            alignment: .top
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.24),
            value: model.isExpanded
        )
        .onChange(of: model.isExpanded) { _, expanded in
            if !expanded, model.searchText.isEmpty {
                searchPresented = false
            }
        }
    }

    private var expandedSheet: some View {
        VStack(spacing: 0) {
            Button {
                dismissExpandedSessions()
            } label: {
                Capsule()
                    .fill(NileColors.muted.opacity(0.48))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close sessions")
            .accessibilityIdentifier(NileAccessibilityID.closeSessions)

            expandedHeader
                .frame(height: 48)
                .padding(.horizontal, 12)

            if searchPresented || !model.searchText.isEmpty {
                SessionSearchBar(
                    text: $model.searchText,
                    onCancel: {
                        model.searchText = ""
                        withAnimation(
                            reduceMotion ? nil : .smooth(duration: 0.18)
                        ) {
                            searchPresented = false
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            sessionRows
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .nileGlass(cornerRadius: NileRadii.window)
        .overlay {
            RoundedRectangle(
                cornerRadius: NileRadii.window,
                style: .continuous
            )
                .strokeBorder(NileColors.border, lineWidth: 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NileAccessibilityID.sessionsSheet)
    }

    @ViewBuilder
    private var sessionRows: some View {
        if model.displayedSessions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(NileColors.muted)
                Text("No matching sessions")
                    .font(NileTypography.bodyMedium.weight(.semibold))
                    .foregroundStyle(NileColors.text)
                Text("Try another title, source, or session ID.")
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(NileColors.panel)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: NileRadii.card,
                    style: .continuous
                )
            )
            .accessibilityElement(children: .combine)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(model.displayedSessions.enumerated()),
                        id: \.element.id
                    ) { index, session in
                        SessionRowView(
                            session: session,
                            selected:
                                session.id == model.selectedSessionID,
                            runtime: runtime(for: session.id),
                            pinned:
                                model.pinnedSessionIDs.contains(
                                    session.id
                                ),
                            select: {
                                Task {
                                    await model.selectSession(id: session.id)
                                }
                            },
                            togglePin: {
                                Task { @MainActor in
                                    await Task.yield()
                                    model.togglePin(id: session.id)
                                }
                            }
                        )

                        if index < model.displayedSessions.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(NileColors.panel)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: NileRadii.card,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: NileRadii.card,
                    style: .continuous
                )
                .strokeBorder(
                    NileColors.border,
                    lineWidth: 1
                )
            }
        }
    }

    private var collapsedStrip: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    if createSwipeOffset > 0 {
                        NewSessionSwipePill(ready: createSwipeReady)
                            .frame(width: createSwipePillWidth, height: 54)
                            .scaleEffect(
                                0.9
                                    + 0.1
                                    * min(
                                        createSwipeOffset
                                            / createSwipePillWidth,
                                        1
                                    )
                            )
                            .opacity(
                                min(
                                    createSwipeOffset
                                        / createSwipePillWidth,
                                    1
                                )
                            )
                            .offset(
                                x: createSwipeOffset
                                    - createSwipePillWidth,
                                y: 3
                            )
                    }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(
                                    Array(
                                        model.collapsedSessions.enumerated()
                                    ),
                                    id: \.element.id
                                ) { index, session in
                                    SessionPillView(
                                        session: session,
                                        selected:
                                            session.id
                                                == model.selectedSessionID,
                                        runtime: runtime(for: session.id)
                                    ) {
                                        Task {
                                            await model.selectSession(
                                                id: session.id
                                            )
                                        }
                                    }
                                    .id(session.id)
                                    .background {
                                        if index == 0 {
                                            GeometryReader { pillGeometry in
                                                Color.clear.preference(
                                                    key:
                                                        FirstSessionPillMinXKey
                                                        .self,
                                                    value: pillGeometry.frame(
                                                        in: .named(
                                                            collapsedStripCoordinateSpace
                                                        )
                                                    ).minX
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .offset(
                                x: createSwipeOffset
                                    + createSwipePillSpacing
                                    * min(
                                        createSwipeOffset
                                            / createSwipePillWidth,
                                        1
                                    )
                            )
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.hidden)
                        .coordinateSpace(
                            name: collapsedStripCoordinateSpace
                        )
                        .modifier(
                            HorizontalStartEdgeTracker(
                                isAtStartEdge:
                                    $collapsedStripAtStartEdge
                            )
                        )
                        .onAppear {
                            positionCollapsedSelection(
                                with: proxy,
                                animated: false
                            )
                        }
                        .onChange(of: model.selectedSessionID) {
                            positionCollapsedSelection(
                                with: proxy,
                                animated: positionedCollapsedSelection
                            )
                        }
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(createSessionSwipeGesture)
                .onAppear {
                    stripWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { _, width in
                    stripWidth = width
                }
                .onPreferenceChange(FirstSessionPillMinXKey.self) {
                    if #unavailable(iOS 18.0) {
                        collapsedStripAtStartEdge = $0 >= 9.5
                    }
                }
                .accessibilityIdentifier(NileAccessibilityID.sessionsStrip)
            }
            .frame(height: 58)

            HStack(spacing: 0) {
                Button(action: expandSessions) {
                    Capsule()
                        .fill(NileColors.borderStrong)
                        .frame(width: 32, height: 4)
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show all sessions")
                .accessibilityIdentifier(NileAccessibilityID.sessionsPullHandle)

                if !model.sessionsNeedingInput.isEmpty {
                    Text("\(model.sessionsNeedingInput.count)")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(NileColors.warning.opacity(0.14))
                        )
                        .accessibilityLabel(needsInputLabel)
                        .accessibilityIdentifier(
                            NileAccessibilityID.sessionsNeedsInputCount
                        )
                }
            }
            .frame(height: 44)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(expandSessionsSwipeGesture)
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            Text("Sessions")
                .font(NileTypography.titleMedium)
                .foregroundStyle(NileColors.text)

            if !model.sessionsNeedingInput.isEmpty {
                Text(needsInputBadge)
                    .font(NileTypography.labelMedium)
                    .foregroundStyle(NileColors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(NileColors.warning.opacity(0.13))
                    )
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Spacer()

            Button {
                withAnimation(
                    reduceMotion ? nil : .smooth(duration: 0.18)
                ) {
                    searchPresented.toggle()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NileColors.text)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .nileGlassButton()
            .accessibilityLabel(
                searchPresented ? "Hide session search" : "Search sessions"
            )
            .accessibilityIdentifier(
                NileAccessibilityID.sessionSearchToggle
            )

            Button {
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
                Task { await model.createSession() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NileColors.text)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .nileGlassButton()
            .disabled(!model.canCreateSession)
            .accessibilityLabel("New session")
            .accessibilityIdentifier(NileAccessibilityID.newSession)
        }
    }

    private var needsInputBadge: String {
        let count = model.sessionsNeedingInput.count
        return count == 1 ? "1 needs input" : "\(count) need input"
    }

    private var needsInputLabel: String {
        let count = model.sessionsNeedingInput.count
        return count == 1
            ? "1 session needs input"
            : "\(count) sessions need input"
    }

    private func runtime(for id: String) -> SessionRuntimePresentation? {
        if model.sessionsNeedingInput.contains(id) {
            return .needsInput
        }
        switch model.activeStatuses[id]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "starting":
            return .starting
        case "working":
            return .working
        default:
            return nil
        }
    }

    private var createSessionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if createSwipeStartedAt == nil {
                    createSwipeStartedAt = value.time
                    createSwipeEligible =
                        SessionCreateSwipePolicy.canBegin(
                            collapsed: !model.isExpanded,
                            atStartEdge: collapsedStripAtStartEdge,
                            sessionCount: model.collapsedSessions.count,
                            canCreateSession: model.canCreateSession
                        )
                    createSwipeLastTranslation = 0
                }
                guard createSwipeEligible else {
                    return
                }
                if !createSwipeClaimed {
                    guard SessionCreateSwipePolicy.shouldClaim(
                        translation: value.translation
                    ) else {
                        return
                    }
                    createSwipeClaimed = true
                    createSwipeLastTranslation = 10
                }
                let delta =
                    value.translation.width - createSwipeLastTranslation
                createSwipeLastTranslation = value.translation.width
                createSwipeOffset =
                    SessionCreateSwipePolicy.resistedOffset(
                        currentOffset: createSwipeOffset,
                        delta: delta,
                        pillWidth: createSwipePillWidth
                    )
                createSwipeFingerX = value.location.x
                let wasReady = createSwipeReady
                createSwipeReady =
                    createSwipeFingerX
                    >= stripWidth
                        * SessionCreateSwipePolicy.commitFraction
                if createSwipeReady && !wasReady {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { value in
                let elapsed = max(
                    value.time.timeIntervalSince(
                        createSwipeStartedAt ?? value.time
                    ),
                    0.001
                )
                let velocityX = value.translation.width / elapsed
                let shouldCreate = createSwipeClaimed
                    && createSwipeEligible
                    && SessionCreateSwipePolicy.shouldCreate(
                        fingerX: value.location.x,
                        stripWidth: stripWidth,
                        velocityX: velocityX
                    )
                resetCreateSwipe()
                if shouldCreate {
                    UINotificationFeedbackGenerator()
                        .notificationOccurred(.success)
                    Task { await model.createSession() }
                }
            }
    }

    private var expandSessionsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                guard SessionExpandSwipePolicy.shouldExpand(
                    translation: value.translation
                ) else {
                    return
                }
                expandSessions()
            }
    }

    private func expandSessions() {
        withAnimation(
            reduceMotion ? nil : .smooth(duration: 0.24)
        ) {
            model.isExpanded = true
        }
    }

    private func resetCreateSwipe() {
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.34, dampingFraction: 0.78)
        ) {
            createSwipeOffset = 0
        }
        createSwipeFingerX = 0
        createSwipeStartedAt = nil
        createSwipeLastTranslation = 0
        createSwipeEligible = false
        createSwipeClaimed = false
        createSwipeReady = false
    }

    private func dismissExpandedSessions() {
        withAnimation(
            reduceMotion ? nil : .smooth(duration: 0.24)
        ) {
            model.isExpanded = false
        }
    }

    private func positionCollapsedSelection(
        with proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let selectedSessionID = model.selectedSessionID,
              let selectedIndex = model.collapsedSessions.firstIndex(
                  where: { $0.id == selectedSessionID }
              ) else {
            return
        }
        let anchor: UnitPoint = selectedIndex == 0 ? .leading : .center
        if animated && !reduceMotion {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(selectedSessionID, anchor: anchor)
            }
        } else {
            proxy.scrollTo(selectedSessionID, anchor: anchor)
        }
        positionedCollapsedSelection = true
    }
}

private struct FirstSessionPillMinXKey: PreferenceKey {
    static let defaultValue: CGFloat = 10

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HorizontalStartEdgeTracker: ViewModifier {
    @Binding var isAtStartEdge: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.x
                    <= geometry.contentInsets.leading + 0.5
            } action: { _, atStartEdge in
                isAtStartEdge = atStartEdge
            }
        } else {
            content
        }
    }
}

private struct NewSessionSwipePill: View {
    let ready: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
            Text("New session")
                .font(NileTypography.bodySmall)
                .lineLimit(1)
        }
        .foregroundStyle(ready ? NileColors.text : NileColors.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ready ? NileColors.surfaceSelected : NileColors.surfaceRaised
        )
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New session")
        .accessibilityValue(
            ready ? "Release to create a new session" : ""
        )
        .accessibilityIdentifier(NileAccessibilityID.sessionsCreateSwipe)
    }
}

private struct SessionSearchBar: View {
    @Binding var text: String
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NileColors.muted)
                    .frame(width: 20, height: 20)
                TextField(
                    "Search sessions",
                    text: $text
                )
                .focused($isFocused)
                .font(NileTypography.bodyMedium)
                .foregroundStyle(NileColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search sessions")
                .accessibilityIdentifier(
                    NileAccessibilityID.sessionSearch
                )
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(NileColors.muted)
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 44)
            .background(NileColors.inset)
            .clipShape(
                RoundedRectangle(cornerRadius: NileRadii.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NileRadii.small)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .font(NileTypography.bodyMedium)
                    .foregroundStyle(NileColors.accent)
                    .frame(minWidth: 54, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(
                NileAccessibilityID.sessionSearchCancel
            )
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
    }
}

private struct SessionPillView: View {
    let session: HermesSession
    let selected: Bool
    let runtime: SessionRuntimePresentation?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if let runtime {
                        SessionRuntimeDot(runtime: runtime)
                    }
                    Text(session.title ?? session.id)
                        .font(
                            NileTypography.bodyMedium.weight(
                                selected ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(NileColors.text)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(NileTypography.bodySmall)
                    .foregroundStyle(NileColors.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(width: 172, height: 54)
            .background {
                RoundedRectangle(
                    cornerRadius: NileRadii.card,
                    style: .continuous
                )
                .fill(surface)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: NileRadii.card,
                    style: .continuous
                )
            )
            .overlay {
                if !selected {
                    RoundedRectangle(
                        cornerRadius: NileRadii.card,
                        style: .continuous
                    )
                    .strokeBorder(
                        NileColors.border.opacity(0.25),
                        lineWidth: 0.5
                    )
                }
            }
            .shadow(
                color: selected ? Color.black.opacity(0.04) : .clear,
                radius: 2,
                y: 1
            )
            .animation(.easeOut(duration: 0.16), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.title ?? session.id)
        .accessibilityValue(runtime?.label ?? detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(NileAccessibilityID.sessionPill(session.id))
    }

    private var surface: Color {
        if selected {
            return NileColors.panelAlt
        }
        if runtime == .needsInput {
            return NileColors.needsInputSurface
        }
        return NileColors.panel
    }

    private var detail: String {
        if let runtime, let source = session.visibleSourceLabel {
            return "\(runtime.label) · \(source)"
        }
        if let runtime {
            return runtime.label
        }
        if let source = session.visibleSourceLabel {
            return "\(source) · \(session.lastMessageLabel)"
        }
        return session.lastMessageLabel
    }
}

private struct SessionRowView: View {
    let session: HermesSession
    let selected: Bool
    let runtime: SessionRuntimePresentation?
    let pinned: Bool
    let select: () -> Void
    let togglePin: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 10) {
                    stateIndicator
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(session.title ?? session.id)
                                .font(
                                    NileTypography.bodyMedium.weight(
                                        selected ? .semibold : .regular
                                    )
                                )
                                .foregroundStyle(NileColors.text)
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            Text(session.lastMessageLabel)
                                .font(NileTypography.bodySmall)
                                .foregroundStyle(NileColors.muted)
                                .lineLimit(1)
                        }

                        Text(detail)
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(detailColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.title ?? session.id)
            .accessibilityValue(runtime?.label ?? detail)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(
                NileAccessibilityID.sessionRow(session.id)
            )

            Button(action: togglePin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        pinned ? NileColors.accent : NileColors.muted
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                pinned ? "Unpin session" : "Pin session"
            )
            .accessibilityIdentifier(
                NileAccessibilityID.sessionPin(session.id)
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(surface)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NileColors.accent)
        } else if runtime == .needsInput {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NileColors.warning)
        } else if let runtime {
            SessionRuntimeDot(runtime: runtime)
        } else {
            Circle()
                .strokeBorder(NileColors.border, lineWidth: 1)
                .frame(width: 9, height: 9)
        }
    }

    private var detailColor: Color {
        runtime == .needsInput ? NileColors.warning : NileColors.muted
    }

    private var surface: Color {
        if selected {
            return NileColors.surfaceSelected
        }
        if runtime == .needsInput {
            return NileColors.warning.opacity(0.06)
        }
        return .clear
    }

    private var detail: String {
        let summary = session.preview ?? "\(session.messageCount) messages"
        let sessionDetail = session.visibleSourceLabel.map { "\($0) · \(summary)" }
            ?? summary
        return runtime.map { "\($0.label) · \(sessionDetail)" } ?? sessionDetail
    }
}

private struct SessionRuntimeDot: View {
    let runtime: SessionRuntimePresentation

    var body: some View {
        Circle()
            .fill(runtime == .needsInput ? NileColors.warning : NileColors.text)
            .frame(
                width: runtime == .needsInput ? 9 : 7,
                height: runtime == .needsInput ? 9 : 7
            )
    }
}

private extension HermesSession {
    var lastMessageLabel: String {
        guard messageCount > 0 else {
            return "no messages yet"
        }
        guard let timestamp = lastMessageAt ?? startedAt else {
            return "\(messageCount) messages"
        }
        let normalized = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        let seconds = max(0, Int(Date().timeIntervalSince1970 - normalized))
        switch seconds {
        case ..<45:
            return "just now"
        case ..<90:
            return "1 minute ago"
        case ..<3_600:
            return "\(seconds / 60) minutes ago"
        case ..<5_400:
            return "1 hour ago"
        case ..<86_400:
            return "\(seconds / 3_600) hours ago"
        case ..<172_800:
            return "yesterday"
        case ..<604_800:
            return "\(seconds / 86_400) days ago"
        case ..<1_209_600:
            return "1 week ago"
        case ..<2_592_000:
            return "\(seconds / 604_800) weeks ago"
        case ..<5_184_000:
            return "1 month ago"
        case ..<31_536_000:
            return "\(seconds / 2_592_000) months ago"
        case ..<63_072_000:
            return "1 year ago"
        default:
            return "\(seconds / 31_536_000) years ago"
        }
    }
}
