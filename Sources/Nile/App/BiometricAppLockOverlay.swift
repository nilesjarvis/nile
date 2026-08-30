import SwiftUI
import UIKit

/// Scene-bound lock surface that stays above app-owned presentation windows.
///
/// `NileApp` remains the sole scene/lifecycle owner. This bridge only mirrors
/// the lock model's fail-closed visibility into one modal accessibility window.
struct BiometricAppLockWindowBridge: UIViewRepresentable {
    @Bindable var model: BiometricAppLockModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = {
            [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(
        _ uiView: WindowAttachmentView,
        context: Context
    ) {
        context.coordinator.attach(to: uiView.window)
        context.coordinator.setVisible(model.showsPrivacyShield)
    }

    static func dismantleUIView(
        _ uiView: WindowAttachmentView,
        coordinator: Coordinator
    ) {
        uiView.onWindowChange = nil
        coordinator.tearDown()
    }

    final class WindowAttachmentView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private let model: BiometricAppLockModel
        private weak var hostWindow: UIWindow?
        private weak var previousKeyWindow: UIWindow?
        private var overlayWindow: UIWindow?
        private var shouldBeVisible = false

        init(model: BiometricAppLockModel) {
            self.model = model
        }

        func attach(to hostWindow: UIWindow?) {
            guard let hostWindow,
                  let windowScene = hostWindow.windowScene else {
                return
            }
            self.hostWindow = hostWindow
            if overlayWindow?.windowScene !== windowScene {
                overlayWindow?.isHidden = true
                overlayWindow = makeOverlayWindow(in: windowScene)
            }
            applyVisibility()
        }

        func setVisible(_ visible: Bool) {
            shouldBeVisible = visible
            applyVisibility()
        }

        func tearDown() {
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
            previousKeyWindow = nil
            hostWindow = nil
        }

        private func makeOverlayWindow(
            in windowScene: UIWindowScene
        ) -> UIWindow {
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = UIWindow.Level(
                rawValue: UIWindow.Level.alert.rawValue + 1
            )
            window.backgroundColor = UIColor(NileColors.background)
            let rootController = UIHostingController(
                rootView: BiometricAppLockView(model: model)
            )
            rootController.view.backgroundColor =
                UIColor(NileColors.background)
            rootController.view.accessibilityViewIsModal = true
            window.rootViewController = rootController
            window.isHidden = true
            return window
        }

        private func applyVisibility() {
            guard let overlayWindow,
                  let windowScene = overlayWindow.windowScene else {
                return
            }
            if shouldBeVisible {
                if overlayWindow.isHidden {
                    previousKeyWindow =
                        windowScene.windows.first(where: {
                            $0 !== overlayWindow && $0.isKeyWindow
                        }) ?? hostWindow
                    overlayWindow.makeKeyAndVisible()
                }
            } else if !overlayWindow.isHidden {
                overlayWindow.isHidden = true
                if let previousKeyWindow,
                   previousKeyWindow.windowScene === windowScene {
                    previousKeyWindow.makeKey()
                } else {
                    hostWindow?.makeKey()
                }
                previousKeyWindow = nil
            }
        }
    }
}

private struct BiometricAppLockView: View {
    @Bindable var model: BiometricAppLockModel

    var body: some View {
        ZStack {
            NileColors.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                NileMark()
                    .frame(width: 56, height: 56)

                VStack(spacing: 8) {
                    Text("Nile is locked")
                        .font(NileTypography.titleLarge)
                        .foregroundStyle(NileColors.text)
                    Text(
                        "Authenticate with \(model.biometryName) to continue."
                    )
                    .font(NileTypography.bodyLarge)
                    .foregroundStyle(NileColors.muted)
                    .multilineTextAlignment(.center)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.error)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            NileAccessibilityID.biometricLockError
                        )
                }

                Button {
                    Task {
                        await model.unlock()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.isAuthenticating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(NileColors.onAccent)
                        }
                        Text(
                            model.isAuthenticating
                                ? "Authenticating…"
                                : "Unlock with \(model.biometryName)"
                        )
                        .font(
                            NileTypography.font(
                                size: 14,
                                weight: .semibold
                            )
                        )
                    }
                    .foregroundStyle(NileColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(NileColors.accentStrong)
                    .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
                }
                .buttonStyle(.plain)
                .disabled(model.isAuthenticating || !model.canEnable)
                .accessibilityIdentifier(
                    NileAccessibilityID.biometricLockUnlock
                )
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NileAccessibilityID.biometricLock)
    }
}
