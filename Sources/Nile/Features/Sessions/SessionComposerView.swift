import SwiftUI
import PhotosUI
import UIKit

enum NileComposerLayout {
    static func minimumRowHeight(
        lineCount: Int,
        baselineStep: CGFloat
    ) -> CGFloat {
        max(44, 24 + CGFloat(min(max(lineCount, 1), 5)) * baselineStep)
    }
}

enum NileComposerSurfaceFeedback {
    static let expandedScale: CGFloat = 1.04

    static func scale(
        isHovered: Bool,
        isActivated: Bool,
        reduceMotion: Bool
    ) -> CGFloat {
        guard !reduceMotion, isHovered || isActivated else {
            return 1
        }
        return expandedScale
    }
}

struct SessionComposerView: View {
    @Bindable var model: SessionListModel
    let composerFocus: FocusState<Bool>.Binding

    @Environment(\.nileReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @State private var activityCueExpanded = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var composerFieldWidth: CGFloat = 0
    @State private var composerIsHovered = false
    @State private var composerFocusPulse = false
    @State private var composerDismissTapArmed = false
    @State private var composerFocusPulseGeneration = 0
    @State private var composerFocusPulseResetTask: Task<Void, Never>?

    private var hasContent: Bool {
        !model.composer.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty || !model.pendingAttachments.isEmpty
    }

    private var showsStop: Bool {
        model.composerIsBlocked || (model.isSending && !hasContent)
    }

    private var compactModelProviders: [ModelProvider] {
        model.selectableModelProviders.filter { provider in
            provider.models.contains { modelID in
                !provider.unavailableModels.contains(modelID)
            }
        }
    }

    private var composerRowMinimumHeight: CGFloat {
        let style = NileTypography.bodyLargeStyle
        let baseFont = UIFont(
            name: style.postScriptName,
            size: style.fontSize
        ) ?? UIFont.systemFont(ofSize: style.fontSize)
        let traits = UITraitCollection(
            preferredContentSizeCategory:
                dynamicTypeSize.uiContentSizeCategory
        )
        let font = UIFontMetrics(
            forTextStyle: style.uiTextStyle
        ).scaledFont(for: baseFont, compatibleWith: traits)
        let contentWidth = composerFieldWidth - 32
        let visibleText = model.composer.isEmpty
            ? model.composerPlaceholder
            : model.composer
        let lineCount = NileTextMeasurement.lineCount(
            text: visibleText,
            style: style,
            font: font,
            width: contentWidth,
            screenScale: displayScale
        ) ?? 1
        let scaledLineHeight =
            (
                style.targetLineHeight
                    ?? font.lineHeight * style.fontSize / font.pointSize
            ) * font.pointSize / style.fontSize
        let baselineStep = ceil(scaledLineHeight * displayScale)
            / displayScale
        return NileComposerLayout.minimumRowHeight(
            lineCount: lineCount,
            baselineStep: baselineStep
        )
    }

    private var composerIsInteracting: Bool {
        composerIsHovered || composerFocusPulse
    }

    private var composerAcceptsFocus: Bool {
        !model.isOpeningSession
            && !model.composerIsBlocked
            && !model.isAttachmentDraftLocked
            && !model.isListening
            && !model.isTranscribing
    }

    var body: some View {
        VStack(spacing: 0) {
            SlashCommandPalette(model: model)
                .padding(.bottom, model.composer.hasPrefix("/") ? 8 : 0)

            VStack(spacing: 0) {
                if model.isSending {
                    VStack(spacing: 0) {
                        turnStatus
                        Rectangle()
                            .fill(NileColors.border.opacity(0.3))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                    .transition(
                        .asymmetric(
                            insertion:
                                .opacity.combined(
                                    with: .scale(
                                        scale: 0.98,
                                        anchor: .bottom
                                    )
                                ),
                            removal:
                                .opacity.combined(
                                    with: .scale(
                                        scale: 0.985,
                                        anchor: .bottom
                                    )
                                )
                        )
                    )
                }

                if !model.pendingAttachments.isEmpty {
                    attachmentStrip
                }
                if model.isAttaching {
                    Text("Sending photo…")
                        .font(NileTypography.labelMedium)
                        .foregroundStyle(NileColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        .padding(.top, 8)
                        .accessibilityIdentifier(
                            NileAccessibilityID.attachmentProgress
                        )
                }
                HStack(alignment: .bottom, spacing: 0) {
                    actionSlot {
                        Button {
                            model.setGoalSheetVisible(true)
                        } label: {
                            Image(systemName: "target")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(
                                    model.goal != nil
                                        ? NileColors.accent
                                        : NileColors.muted
                                )
                                .frame(width: 28, height: 28)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(NileTactileButtonStyle())
                        .disabled(
                            model.goalAvailability != .available
                                || model.isOpeningSession
                                || model.isGoalMutating
                        )
                        .accessibilityLabel(
                            model.goal == nil
                                ? "Start a standing goal"
                                : "Open standing goal"
                        )
                        .accessibilityIdentifier(NileAccessibilityID.goalButton)
                    }

                    actionSlot {
                        attachmentMenu
                    }

                    TextField(
                        model.composerPlaceholder,
                        text: Binding(
                            get: { model.composer },
                            set: { text in
                                model.updateComposer(text)
                            }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(NileTypography.bodyLarge)
                    .foregroundStyle(NileColors.text)
                    .tint(NileColors.text)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .focused(composerFocus)
                    .disabled(!composerAcceptsFocus)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                    .frame(
                        minHeight: composerRowMinimumHeight,
                        alignment: .center
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    composerFieldWidth = geometry.size.width
                                }
                                .onChange(of: geometry.size.width) {
                                    _, width in
                                    composerFieldWidth = width
                            }
                        }
                    }
                    .overlay {
                        if composerDismissTapArmed {
                            Button {
                                composerDismissTapArmed = false
                                composerFocus.wrappedValue = false
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)
                        }
                    }
                    .onSubmit(submit)
                    .accessibilityIdentifier(NileAccessibilityID.composer)

                    actionSlot {
                        composerAction
                    }
                    .padding(.trailing, 6)
                }

                usageStrip
            }
            .background {
                Button(action: activateComposer) {
                    Color.clear
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: NileRadii.window,
                                style: .continuous
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                }
                .buttonStyle(.plain)
                .disabled(!composerAcceptsFocus)
                .accessibilityHidden(true)
            }
            .nileGlass(cornerRadius: NileRadii.window)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.composerSurface)
            .overlay { composerBorder }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: NileRadii.window,
                    style: .continuous
                )
            )
            .onHover { isHovered in
                composerIsHovered = isHovered
            }
            .scaleEffect(
                NileComposerSurfaceFeedback.scale(
                    isHovered: composerIsHovered,
                    isActivated: composerFocusPulse,
                    reduceMotion: reduceMotion
                )
            )
            .shadow(
                color: .black.opacity(composerIsInteracting ? 0.08 : 0.04),
                radius: composerIsInteracting ? 6 : 3,
                y: composerIsInteracting ? 3 : 2
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(
                        response: 0.18,
                        dampingFraction: 0.68,
                        blendDuration: 0.02
                    ),
                value: composerIsInteracting
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.28, dampingFraction: 0.82),
                value: model.isSending
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onChange(of: model.isSending, initial: true) { _, _ in
            updateActivityCueAnimation()
        }
        .onChange(of: model.isStopping) { _, _ in
            updateActivityCueAnimation()
        }
        .onChange(of: model.composerIsBlocked) { _, _ in
            updateActivityCueAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateActivityCueAnimation()
        }
        .onChange(of: composerFocus.wrappedValue) {
            wasFocused,
            isFocused in
            if isFocused && !wasFocused {
                startComposerFocusPulse()
            } else if !isFocused {
                resetComposerFocusInteraction()
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else {
                return
            }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    selectedPhoto = nil
                    model.attachImageData(data ?? Data())
                }
            }
        }
        .sheet(isPresented: $showsCamera) {
            NileCameraPicker { data in
                showsCamera = false
                if let data {
                    model.attachImageData(data)
                }
            }
            .ignoresSafeArea()
        }
        .onDisappear {
            resetComposerFocusInteraction()
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = UIImage(data: attachment.data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                NileColors.panelAlt
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(attachment.filename)
                        .accessibilityIdentifier(
                            NileAccessibilityID.pendingAttachment(
                                attachment.id
                            )
                        )

                        Button {
                            model.removeAttachment(id: attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(NileColors.text)
                                .frame(width: 22, height: 22)
                                .background(
                                    NileColors.background.opacity(0.7)
                                )
                                .clipShape(Circle())
                                .frame(
                                    width: 44,
                                    height: 44,
                                    alignment: .topTrailing
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(NileTactileButtonStyle())
                        .disabled(
                            model.isAttachmentDraftLocked
                                || model.isAttaching
                                || model.isOpeningSession
                                || model.composerIsBlocked
                        )
                        .accessibilityLabel(
                            "Remove \(attachment.filename)"
                        )
                        .accessibilityIdentifier(
                            NileAccessibilityID.removeAttachment(
                                attachment.id
                            )
                        )
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        .padding(.top, 10)
        .accessibilityIdentifier(NileAccessibilityID.attachmentStrip)
    }

    private var attachmentMenu: some View {
        Menu {
            Button("Take photo") {
                showsCamera = true
            }
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Choose from gallery")
            }
        } label: {
            Group {
                if model.isAttaching {
                    ProgressView()
                        .tint(NileColors.muted)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NileColors.muted)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(NileTactileButtonStyle())
        .disabled(
            model.isSending
                || model.isOpeningSession
                || model.composerIsBlocked
                || model.isAttaching
        )
        .accessibilityLabel("Attach photo")
        .accessibilityIdentifier(NileAccessibilityID.attachPhoto)
    }

    private var turnStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 9) {
                activityCue
                Text(turnStatusLabel)
                    .font(NileTypography.bodySmall.weight(.semibold))
                    .foregroundStyle(turnStatusColor)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let startedAt = model.turnStartedAt {
                    Text(elapsed(from: startedAt, to: context.date))
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted.opacity(0.75))
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 32)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Turn status")
            .accessibilityValue(
                turnStatusAccessibilityValue(at: context.date)
            )
            .accessibilityIdentifier(NileAccessibilityID.turnStatus)
        }
    }

    private var activityCue: some View {
        ZStack {
            Circle()
                .stroke(turnStatusColor.opacity(0.55), lineWidth: 1)
                .frame(width: 10, height: 10)
                .scaleEffect(activityCueExpanded ? 1.55 : 1)
                .opacity(activityCueExpanded ? 0 : 0.7)
            Circle()
                .fill(turnStatusColor)
                .frame(width: 5, height: 5)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var composerAction: some View {
        if model.isTranscribing {
            ProgressView()
                .tint(NileColors.muted)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Hermes is transcribing")
        } else if showsStop {
            Button {
                model.stopActiveRun()
            } label: {
                Group {
                    if model.isStopping {
                        ProgressView()
                            .tint(NileColors.panelAlt)
                            .frame(width: 16, height: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NileColors.panelAlt)
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 28, height: 28)
                .background(
                    model.isOpeningSession
                        ? NileColors.surfaceHighest
                        : NileColors.text
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: NileRadii.control)
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(NileTactileButtonStyle())
            .disabled(model.isOpeningSession || model.isStopping)
            .accessibilityLabel(
                model.isStopping ? "Stopping run" : "Stop run"
            )
            .accessibilityValue(
                model.isStopping ? "Stopping" : "Available"
            )
            .accessibilityIdentifier(NileAccessibilityID.composerStop)
        } else if model.isAttaching {
            ProgressView()
                .tint(NileColors.muted)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Sending photo")
        } else if model.voiceInputAvailable
            && (model.isListening || !hasContent)
            && !model.isSending
            && !model.composerIsBlocked {
            Button {
                if model.isListening {
                    model.stopVoiceInput()
                } else {
                    model.startTalkMode()
                }
            } label: {
                Image(systemName: model.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        model.isListening
                            ? NileColors.onAccent
                            : NileColors.text
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        model.isListening
                            ? NileColors.accentStrong
                            : NileColors.surfaceHighest
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.control)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NileTactileButtonStyle())
            .disabled(
                model.isOpeningSession
                    || model.isAttachmentDraftLocked
            )
            .accessibilityLabel(
                model.isListening ? "Stop voice input" : "Talk with Hermes"
            )
            .accessibilityIdentifier(NileAccessibilityID.talkEntry)
        } else {
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        model.composerCanSend
                            ? NileColors.background
                            : NileColors.muted
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        model.composerCanSend
                            ? NileColors.text
                            : NileColors.surfaceHighest
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.control)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NileTactileButtonStyle())
            .disabled(!model.composerCanSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier(NileAccessibilityID.composerSend)
        }
    }

    private var usageStrip: some View {
        HStack(spacing: 8) {
            Button {
                model.setSpeakRepliesEnabled(
                    !model.speakRepliesEnabled
                )
            } label: {
                Image(
                    systemName: model.speakRepliesEnabled
                        ? "speaker.wave.2.fill"
                        : "speaker.slash.fill"
                )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        model.speakRepliesEnabled
                            ? NileColors.accent
                            : NileColors.muted
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        model.speakRepliesEnabled
                            ? NileColors.accent.opacity(0.12)
                            : NileColors.surfaceHighest
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: NileRadii.control)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NileTactileButtonStyle())
            .accessibilityLabel("Automatically speak new Hermes replies")
            .accessibilityValue(
                model.speakRepliesEnabled ? "On" : "Off"
            )
            .accessibilityAddTraits(
                model.speakRepliesEnabled ? .isSelected : []
            )
            .accessibilityIdentifier(
                NileAccessibilityID.composerSpeakReplies
            )

            if let modelName = model.liveSession?.info.model {
                Menu {
                    if compactModelProviders.isEmpty {
                        Button {
                            model.prepareCompactModelMenu()
                        } label: {
                            Label(
                                model.modelOptionsError == nil
                                    ? "Loading models…"
                                    : "Retry model list",
                                systemImage:
                                    model.modelOptionsError == nil
                                        ? "arrow.trianglehead.2.clockwise.rotate.90"
                                        : "arrow.clockwise"
                            )
                        }
                        .disabled(model.isLoadingModelOptions)
                        .accessibilityIdentifier(
                            NileAccessibilityID.composerModelMenuStatus
                        )
                    } else {
                        ForEach(
                            compactModelProviders,
                            id: \.slug
                        ) { provider in
                            compactProviderMenu(provider)
                        }
                        Divider()
                    }
                    Button {
                        model.setModelPickerVisible(true)
                    } label: {
                        Label(
                            "Model settings…",
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .accessibilityIdentifier(
                        NileAccessibilityID.composerModelSettings
                    )
                } label: {
                    HStack(spacing: 4) {
                        if model.isUpdatingSessionControls {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(NileColors.muted)
                        }
                        Text(modelName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(NileTypography.labelMedium)
                    .foregroundStyle(NileColors.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NileColors.surfaceHighest)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NileTactileButtonStyle())
                .menuOrder(.fixed)
                .disabled(
                    model.isSending
                        || model.isAttaching
                        || model.isOpeningSession
                        || model.isUpdatingSessionControls
                )
                .accessibilityIdentifier(
                    NileAccessibilityID.composerModelName
                )
                .accessibilityLabel("Change model")
                .accessibilityValue(
                    model.isUpdatingSessionControls
                        ? "\(modelName), switching"
                        : modelName
                )
                .onAppear {
                    model.prepareCompactModelMenu()
                }
                .onChange(of: model.liveSession?.liveID) {
                    model.prepareCompactModelMenu()
                }
                .onChange(of: model.isSending) { _, isSending in
                    if !isSending {
                        model.prepareCompactModelMenu()
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                model.setContextSheetVisible(true)
            } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    if let usage = model.usage {
                        if let contextPercent = usage.contextPercent {
                            let remaining = min(
                                100,
                                max(0, 100 - contextPercent)
                            )
                            HStack(spacing: 8) {
                                ContextScaleBar(remainingPercent: remaining)
                                Text("\(remaining)% context left")
                                    .font(NileTypography.bodySmall)
                                    .foregroundStyle(NileColors.muted)
                                    .lineLimit(1)
                            }
                        }
                        Text(usageDetailText(usage))
                            .font(NileTypography.bodySmall)
                            .foregroundStyle(NileColors.muted)
                            .lineLimit(1)
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(NileColors.surfaceHighest)
                                    .frame(width: 40, height: 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(NileColors.surfaceHighest)
                                    .frame(width: 76, height: 9)
                            }
                            RoundedRectangle(cornerRadius: 3)
                                .fill(NileColors.surfaceHighest)
                                .frame(width: 104, height: 9)
                        }
                    }
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(NileTactileButtonStyle())
            .disabled(model.usage == nil)
            .accessibilityLabel("Session usage and context")
            .accessibilityValue(
                model.usage.map(usageAccessibilityValue) ?? "Loading"
            )
            .accessibilityIdentifier(NileAccessibilityID.composerUsage)
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .padding(.bottom, 2)
        .frame(minHeight: 40)
    }

    private func updateActivityCueAnimation() {
        guard model.isSending,
              !model.isStopping,
              !model.composerIsBlocked,
              !reduceMotion else {
            withAnimation(.none) {
                activityCueExpanded = false
            }
            return
        }
        activityCueExpanded = false
        withAnimation(
            .easeOut(duration: 1.05)
                .repeatForever(autoreverses: false)
        ) {
            activityCueExpanded = true
        }
    }

    private func compactProviderMenu(
        _ provider: ModelProvider
    ) -> some View {
        let availableModels = provider.models.filter {
            !provider.unavailableModels.contains($0)
        }
        let currentProvider =
            model.resolvedCurrentModelProviderSlug == provider.slug
        return Menu {
            ForEach(availableModels, id: \.self) { modelID in
                Button {
                    model.selectModel(modelID, provider: provider.slug)
                } label: {
                    if currentProvider,
                       model.liveSession?.info.model == modelID {
                        Label(modelID, systemImage: "checkmark")
                    } else {
                        Text(modelID)
                    }
                }
                .accessibilityIdentifier(
                    NileAccessibilityID.composerModelOption(
                        provider: provider.slug,
                        model: modelID
                    )
                )
            }
        } label: {
            if currentProvider {
                Label(
                    provider.name ?? provider.slug,
                    systemImage: "checkmark"
                )
            } else {
                Text(provider.name ?? provider.slug)
            }
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier(
            NileAccessibilityID.composerModelProvider(provider.slug)
        )
    }

    private var composerBorder: some View {
        let shape = RoundedRectangle(
            cornerRadius: NileRadii.window,
            style: .continuous
        )
        return shape.stroke(
            model.isSending ? NileColors.borderStrong : NileColors.border,
            lineWidth: 1
        )
    }

    private func actionSlot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(height: 44, alignment: .center)
    }

    private func startComposerFocusPulse() {
        composerFocusPulseResetTask?.cancel()
        composerFocusPulseGeneration &+= 1
        let generation = composerFocusPulseGeneration
        composerFocusPulse = true
        composerDismissTapArmed = false
        composerFocusPulseResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled,
                  composerFocusPulseGeneration == generation,
                  composerFocus.wrappedValue else {
                return
            }
            composerFocusPulse = false
            composerDismissTapArmed = true
            composerFocusPulseResetTask = nil
        }
    }

    private func resetComposerFocusInteraction() {
        composerFocusPulseResetTask?.cancel()
        composerFocusPulseResetTask = nil
        composerFocusPulse = false
        composerDismissTapArmed = false
    }

    private func activateComposer() {
        guard composerAcceptsFocus else {
            return
        }
        composerDismissTapArmed = false
        composerFocus.wrappedValue = true
    }

    private func submit() {
        if model.sendMessage() {
            composerFocus.wrappedValue = false
        }
    }

    private var turnStatusLabel: String {
        if model.isStopping {
            return "Stopping"
        }
        if model.composerIsBlocked {
            return "Needs input"
        }
        return "Working"
    }

    private var turnStatusColor: Color {
        model.composerIsBlocked ? NileColors.warning : NileColors.muted
    }

    private func turnStatusAccessibilityValue(at date: Date) -> String {
        guard let startedAt = model.turnStartedAt else {
            return turnStatusLabel
        }
        return "\(turnStatusLabel), \(elapsedAccessibility(from: startedAt, to: date)) elapsed"
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
        }
        return "\(seconds / 3_600)h \(String(format: "%02d", (seconds % 3_600) / 60))m"
    }

    private func elapsedAccessibility(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 {
            return "\(seconds) " + (seconds == 1 ? "second" : "seconds")
        }
        if seconds < 3_600 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            let minuteText =
                "\(minutes) " + (minutes == 1 ? "minute" : "minutes")
            guard remainder > 0 else {
                return minuteText
            }
            return minuteText + ", \(remainder) "
                + (remainder == 1 ? "second" : "seconds")
        }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let hourText = "\(hours) " + (hours == 1 ? "hour" : "hours")
        guard minutes > 0 else {
            return hourText
        }
        return hourText + ", \(minutes) "
            + (minutes == 1 ? "minute" : "minutes")
    }

    private func usageDetailText(_ usage: SessionUsage) -> String {
        var pieces: [String] = []
        if usage.compactionCount > 0 {
            pieces.append(
                "\(usage.compactionCount) "
                    + (usage.compactionCount == 1
                        ? "compaction" : "compactions")
            )
        }
        pieces.append(
            "\(formatUsageTokens(usage.inputTokens))↑ "
                + "\(formatUsageTokens(usage.outputTokens))↓ · "
                + "\(usage.apiCalls) calls"
        )
        return pieces.joined(separator: " · ")
    }

    private func usageAccessibilityValue(_ usage: SessionUsage) -> String {
        let context = usage.contextPercent.map {
            "\(max(0, 100 - $0)) percent context left. "
        } ?? ""
        return context + usageDetailText(usage)
    }

    private func formatUsageTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000)
        }
        return String(tokens)
    }
}

private struct ContextScaleBar: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(NileColors.border)
                Capsule()
                    .fill(NileColors.muted)
                    .frame(
                        width: geometry.size.width
                            * CGFloat(min(100, max(0, remainingPercent)))
                            / 100
                    )
            }
        }
        .frame(width: 40, height: 4)
        .accessibilityElement()
        .accessibilityLabel("Context remaining")
        .accessibilityValue("\(remainingPercent)% context left")
        .accessibilityIdentifier(NileAccessibilityID.composerContextScale)
    }
}

private struct ArrowUpGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = glyphTransform(for: rect)
        return Path { path in
            path.move(to: CGPoint(x: 4, y: 12))
            path.addLine(to: CGPoint(x: 5.41, y: 13.41))
            path.addLine(to: CGPoint(x: 11, y: 7.83))
            path.addLine(to: CGPoint(x: 11, y: 20))
            path.addLine(to: CGPoint(x: 13, y: 20))
            path.addLine(to: CGPoint(x: 13, y: 7.83))
            path.addLine(to: CGPoint(x: 18.58, y: 13.42))
            path.addLine(to: CGPoint(x: 20, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.closeSubpath()
        }
        .applying(transform)
    }
}

private struct NileCameraPicker: UIViewControllerRepresentable {
    let completion: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(
            .camera
        ) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    @MainActor
    final class Coordinator:
        NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let completion: (Data?) -> Void

        init(completion: @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            completion(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [
                UIImagePickerController.InfoKey: Any
            ]
        ) {
            let image = info[.originalImage] as? UIImage
            completion(image?.jpegData(compressionQuality: 1))
        }
    }
}

private struct SpeakerOffGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = glyphTransform(for: rect)
        return Path { path in
            path.move(to: CGPoint(x: 3, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 15))
            path.addLine(to: CGPoint(x: 7, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 20))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 7, y: 9))
            path.closeSubpath()
            path.move(to: CGPoint(x: 4.27, y: 3))
            path.addLine(to: CGPoint(x: 3, y: 4.27))
            path.addLine(to: CGPoint(x: 19.73, y: 21))
            path.addLine(to: CGPoint(x: 21, y: 19.73))
            path.closeSubpath()
        }
        .applying(transform)
    }
}

private struct SpeakerGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = glyphTransform(for: rect)
        return Path { path in
            path.move(to: CGPoint(x: 3, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 15))
            path.addLine(to: CGPoint(x: 7, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 20))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 7, y: 9))
            path.closeSubpath()
            path.move(to: CGPoint(x: 15.5, y: 8))
            path.addCurve(
                to: CGPoint(x: 15.5, y: 16),
                control1: CGPoint(x: 18, y: 9.7),
                control2: CGPoint(x: 18, y: 14.3)
            )
            path.move(to: CGPoint(x: 18, y: 5.5))
            path.addCurve(
                to: CGPoint(x: 18, y: 18.5),
                control1: CGPoint(x: 22, y: 8.5),
                control2: CGPoint(x: 22, y: 15.5)
            )
        }
        .applying(transform)
    }
}

private struct GoalGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let unit = min(rect.width, rect.height)
            path.addEllipse(
                in: CGRect(
                    x: center.x - unit * 0.44,
                    y: center.y - unit * 0.44,
                    width: unit * 0.88,
                    height: unit * 0.88
                )
            )
            path.addEllipse(
                in: CGRect(
                    x: center.x - unit * 0.25,
                    y: center.y - unit * 0.25,
                    width: unit * 0.5,
                    height: unit * 0.5
                )
            )
            path.addEllipse(
                in: CGRect(
                    x: center.x - unit * 0.07,
                    y: center.y - unit * 0.07,
                    width: unit * 0.14,
                    height: unit * 0.14
                )
            )
        }
    }
}

private func glyphTransform(for rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width, rect.height) / 24
    return CGAffineTransform(
        a: scale,
        b: 0,
        c: 0,
        d: scale,
        tx: rect.midX - 12 * scale,
        ty: rect.midY - 12 * scale
    )
}
