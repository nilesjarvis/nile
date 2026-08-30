import SwiftUI

@main
struct NileApp: App {
    @UIApplicationDelegateAdaptor(NileAppDelegate.self)
    private var appDelegate
    @State private var graph = NileAppGraph()

    var body: some Scene {
        WindowGroup {
            GatewayRootView(graph: graph)
        }
    }
}

private struct GatewayRootView: View {
    @Bindable var graph: NileAppGraph
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: GatewaySetupModel {
        graph.gatewaySetup
    }

    var body: some View {
        ZStack {
            ZStack {
                Group {
                    if graph.showsSessionFixture {
                        SessionShellView(model: graph.sessionList) {}
                    } else if let loginURL = model.gatewaySignInURL {
                        GatewaySignInView(
                            loginURL: loginURL,
                            fixtureHTML: model.signInFixtureHTML,
                            onContinue: {
                                Task {
                                    await model.completeGatewaySignIn()
                                }
                            },
                            onCancel: {
                                Task {
                                    await model.cancelGatewaySignIn()
                                }
                            }
                        )
                    } else if model.state == .loading {
                        NileLoadingView()
                    } else if model.showsSessionShell || model.connectedProfile != nil {
                        SessionShellView(model: graph.sessionList) {
                            model.showSettings()
                        }
                        .task(id: model.connectedProfile?.id) {
                            guard model.state == .connected,
                                  let profile = model.connectedProfile
                            else {
                                return
                            }
                            await graph.sessionList.load(
                                gatewayID: profile.id,
                                preferredSessionID: profile.lastSessionID
                            )
                        }
                        .sheet(isPresented: Binding(
                            get: { model.isSettingsVisible },
                            set: { visible in if !visible { model.dismissSettings() } }
                        )) {
                            SettingsView(model: model, appLock: graph.appLock)
                        }
                    } else {
                        SettingsView(
                            model: model,
                            appLock: graph.appLock
                        )
                    }
                }
                if graph.notificationEducation.isVisible,
                   graph.sessionList.talk == nil {
                    NotificationEducationView(
                        model: graph.notificationEducation
                    )
                }
                if graph.forcesReducedMotionFixture {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Reduced motion")
                        .accessibilityValue("Enabled")
                        .accessibilityIdentifier(
                            NileAccessibilityID.reducedMotionFixture
                        )
                }
            }
            .accessibilityHidden(graph.appLock.showsPrivacyShield)
            if graph.appLock.showsPrivacyShield {
                NileColors.background
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .zIndex(200)
            }
        }
        .task {
            for await route in TurnNotificationRouteCenter.shared.routes {
                graph.receiveTurnNotificationRoute(route)
            }
        }
        .onChange(of: model.state) {
            Task {
                await graph.resolvePendingTurnNotificationRoute()
            }
        }
        .onChange(of: graph.sessionList.state) {
            Task {
                await graph.resolvePendingTurnNotificationRoute()
            }
        }
        .onChange(of: model.gatewaySignInURL) {
            Task {
                await graph.resolvePendingTurnNotificationRoute()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            graph.sessionList.onAppForegroundChanged(phase == .active)
            switch phase {
            case .active:
                model.onAppForeground()
                Task {
                    await graph.appLock.appDidBecomeActive()
                    await graph.resolvePendingTurnNotificationRoute()
                }
            case .inactive:
                graph.appLock.appDidBecomeInactive()
                graph.sessionList.flushDrafts()
            case .background:
                graph.appLock.appDidEnterBackground()
                graph.sessionList.flushDrafts()
            @unknown default:
                graph.appLock.appDidEnterBackground()
                graph.sessionList.flushDrafts()
            }
        }
        .environment(
            \.nileReduceMotion,
            reduceMotion || graph.forcesReducedMotionFixture
        )
        .transaction { transaction in
            guard reduceMotion || graph.forcesReducedMotionFixture else {
                return
            }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .background {
            BiometricAppLockWindowBridge(model: graph.appLock)
                .frame(width: 0, height: 0)
        }
    }
}

private struct NileLoadingView: View {
    @State private var shifted = false

    var body: some View {
        ZStack {
            NileColors.background.ignoresSafeArea()
            VStack(spacing: 14) {
                NilePixelGrid(color: NileColors.text, shifted: shifted)
                HStack(spacing: 8) {
                    Text("Connecting to Hermes")
                        .font(NileTypography.bodySmall)
                        .foregroundStyle(NileColors.muted)
                    Text("NILE")
                        .font(NileTypography.labelMedium)
                        .tracking(0.8)
                        .foregroundStyle(NileColors.faint)
                }
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    shifted = true
                }
            }
        }
    }
}
