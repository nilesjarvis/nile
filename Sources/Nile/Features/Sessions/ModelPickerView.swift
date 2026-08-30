import SwiftUI

struct ModelPickerOverlay: View {
    @Bindable var model: SessionListModel
    @State private var catalogSearchIsFocused = false

    var controlsEnabled: Bool {
        !model.isSending
            && !model.isAttaching
            && !model.isOpeningSession
            && !model.isLoadingModelOptions
            && model.modelOptionsError == nil
            && !model.isUpdatingSessionControls
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.setModelPickerVisible(false)
                }
                .accessibilityLabel("Dismiss model picker")
                .accessibilityIdentifier(
                    NileAccessibilityID.modelPickerScrim
                )

            VStack(spacing: 8) {
                Capsule()
                    .fill(NileColors.muted.opacity(0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                header
                if model.isUpdatingSessionControls {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(NileColors.accent)
                        ModelPickerText(
                            "Applying model settings…",
                            style: NileTypography.bodySmallStyle,
                            color: NileColors.muted,
                            background: NileColors.background
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        NileAccessibilityID.modelSwitchProgress
                    )
                }

                if let error = model.operationError {
                    Button {
                        model.dismissOperationError()
                    } label: {
                        ModelPickerText(
                            "\(error) — tap to dismiss",
                            style: NileTypography.bodySmallStyle,
                            color: NileColors.error,
                            background: NileColors.background,
                            fillsWidth: true
                        )
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 48,
                                maxHeight: 96,
                                alignment: .leading
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(error). Dismiss error")
                    .accessibilityIdentifier(
                        NileAccessibilityID.sessionControlError
                    )
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        catalogState
                        reasoningControl
                        ModelPickerCatalogView(
                            model: model,
                            controlsEnabled: controlsEnabled,
                            searchIsFocused: $catalogSearchIsFocused
                        )
                    }
                }
                .accessibilityIdentifier(NileAccessibilityID.modelPicker)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: 720)
            .frame(maxHeight: 720)
            .fixedSize(horizontal: false, vertical: !catalogSearchIsFocused)
            .nilePanel(cornerRadius: NileRadii.window)
            .shadow(color: .black.opacity(0.14), radius: 24, y: 8)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.modelPickerSurface)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                ModelPickerText(
                    "Session model settings",
                    style: NileTypography.bodyMediumSemiboldStyle,
                    color: NileColors.text,
                    background: NileColors.background
                )
                ModelPickerText(
                    model.sessions.first {
                        $0.id == model.selectedSessionID
                    }?.title ?? "Current session",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    background: NileColors.background
                )
            }
            Spacer()
            Button {
                model.setModelPickerVisible(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        model.isUpdatingSessionControls
                            ? NileColors.border
                            : NileColors.text
                    )
                    .frame(width: 48, height: 48)
                    .nileGlass(
                        cornerRadius: NileRadii.control,
                        interactive: true
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.isUpdatingSessionControls)
            .accessibilityLabel("Close model picker")
            .accessibilityIdentifier(NileAccessibilityID.closeModelPicker)
        }
    }

    @ViewBuilder
    private var catalogState: some View {
        if model.isLoadingModelOptions,
           model.selectableModelProviders.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(NileColors.accent)
                ModelPickerText(
                    "Loading model catalog…",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    background: NileColors.background
                )
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(NileAccessibilityID.modelCatalogStatus)
        } else if model.isLoadingModelOptions {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(NileColors.accent)
                ModelPickerText(
                    "Refreshing models…",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.muted,
                    background: NileColors.background
                )
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(NileAccessibilityID.modelCatalogStatus)
        }
        if let error = model.modelOptionsError {
            VStack(alignment: .leading, spacing: 8) {
                ModelPickerText(
                    "Couldn’t refresh models: \(error)",
                    style: NileTypography.bodySmallStyle,
                    color: NileColors.error,
                    background: NileColors.panel,
                    fillsWidth: true
                )
                Button("Retry") {
                    model.refreshModelOptions()
                }
                .buttonStyle(NileTextButtonStyle())
                .disabled(!controlsEnabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier(
                    NileAccessibilityID.modelOptionsRetry
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NileAccessibilityID.modelCatalogStatus)
        }
    }

}
