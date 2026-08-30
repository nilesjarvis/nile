import Foundation

#if DEBUG || NILE_LOCAL_RELEASE
/// Deterministic fixture selection kept outside production dependency wiring.
///
/// The initializer is the single precedence table for launch arguments. In a
/// Release build `NileDebugFixturePolicy` supplies no arguments, so every
/// optional fixture collaborator remains absent.
struct NileAppGraphFixturePlan {
    enum GatewayVisualFixture: Equatable {
        case switchConfirmation
        case removal
    }

    let forcesReducedMotionFixture: Bool
    let showsNotificationEducationFixture: Bool
    let showsSessionFixture: Bool
    let gatewayVisualFixture: GatewayVisualFixture?

    let showsUsageFixture: Bool
    let composerActivityFixture:
        NileAppGraphFixtures.ComposerActivityFixture?
    let showsStatsFixture: Bool
    let showsDelegationActiveFixture: Bool
    let showsDelegationSettledFixture: Bool
    let showsAndroidVisualDelegationFixture: Bool
    let showsAndroidVisualRenameFixture: Bool
    let streamingTranscriptFixture:
        NileAppGraphFixtures.StreamingTranscriptFixture?
    let showsStreamingStressFixture: Bool
    let showsActivePlanFixture: Bool
    let recoveryFixturePhase: SessionConnectionPhase?

    let showsBiometricLockFailureFixture: Bool
    let showsHermesVoiceFixture: Bool
    let showsTerminalBusyFixture: Bool
    let showsTalkFixture: Bool
    let showsSessionSwitchFixture: Bool
    let showsEmptySessionSwitchFixture: Bool
    let sessionFixture: SessionListFixture?

    var confirmsGatewaySwitchFixture: Bool {
        gatewayVisualFixture == .switchConfirmation
    }

    init(arguments: [String]) {
        let arguments = Set(
            NileDebugFixturePolicy.arguments(from: arguments)
        )
        let showsGatewayRemovalFixture = arguments.contains(
            "--nile-fixture-android-visual-gateway-removal"
        )
        let showsGatewaySwitchFixture = arguments.contains(
            "--nile-fixture-android-visual-gateway-switch"
        )
        gatewayVisualFixture =
            if showsGatewaySwitchFixture {
                .switchConfirmation
            } else if showsGatewayRemovalFixture {
                .removal
            } else {
                nil
            }

        forcesReducedMotionFixture = arguments.contains(
            "--nile-fixture-reduced-motion"
        )
        showsBiometricLockFailureFixture = arguments.contains(
            "--nile-fixture-biometric-lock-fail-on-return"
        )
        showsHermesVoiceFixture = arguments.contains(
            "--nile-fixture-hermes-voice"
        )
        showsTerminalBusyFixture = arguments.contains(
            "--nile-fixture-terminal-busy"
        )
        composerActivityFixture =
            NileAppGraphFixtures.ComposerActivityFixture(
                arguments: Array(arguments)
            )
        showsTalkFixture = arguments.contains("--nile-fixture-talk")
        showsUsageFixture = arguments.contains(
            "--nile-fixture-usage-context"
        )
        showsStatsFixture = arguments.contains("--nile-fixture-stats")
        showsDelegationActiveFixture = arguments.contains(
            "--nile-fixture-delegation-active"
        )
        showsDelegationSettledFixture = arguments.contains(
            "--nile-fixture-delegation-settled"
        )
        showsAndroidVisualDelegationFixture = arguments.contains(
            "--nile-fixture-android-delegation-mixed"
        )
        showsAndroidVisualRenameFixture = arguments.contains(
            "--nile-fixture-android-visual-rename"
        )
        showsNotificationEducationFixture = arguments.contains(
            "--nile-fixture-notification-education"
        )
        let showsTranscriptScrollFixture = arguments.contains(
            "--nile-fixture-transcript-scroll"
        )
        showsStreamingStressFixture = arguments.contains(
            "--nile-fixture-streaming-stress"
        ) || arguments.contains(
            "--nile-performance-streaming-stress"
        )
        showsActivePlanFixture = arguments.contains(
            "--nile-fixture-active-plan"
        )
        showsSessionSwitchFixture = arguments.contains(
            "--nile-fixture-session-switching"
        )
        showsEmptySessionSwitchFixture = arguments.contains(
            "--nile-fixture-session-switching-empty"
        )
        let showsAndroidVisualSyntaxFixture = arguments.contains(
            "--nile-fixture-android-visual-transcript-syntax"
        )
        streamingTranscriptFixture = NileSessionFixturePolicy.streamingTranscript(
            arguments: arguments
        )
        let showsEmptySessionFixture = arguments.contains(
            "--nile-fixture-session-empty"
        )
        recoveryFixturePhase = NileSessionFixturePolicy.recoveryPhase(
            arguments: arguments
        )
        sessionFixture = NileSessionFixturePolicy.sessionFixture(
            arguments: arguments,
            composerActivity: composerActivityFixture
        )
        showsSessionFixture = arguments.contains("--nile-fixture-sessions")
            || composerActivityFixture != nil
            || showsTerminalBusyFixture
            || showsTalkFixture
            || showsUsageFixture
            || showsStatsFixture
            || showsDelegationActiveFixture
            || showsDelegationSettledFixture
            || showsNotificationEducationFixture
            || showsTranscriptScrollFixture
            || showsStreamingStressFixture
            || showsActivePlanFixture
            || showsSessionSwitchFixture
            || showsEmptySessionSwitchFixture
            || showsAndroidVisualSyntaxFixture
            || streamingTranscriptFixture != nil
            || showsEmptySessionFixture
            || recoveryFixturePhase != nil
            || sessionFixture != nil
    }

    var automaticallyRestoresGateway: Bool {
        !showsSessionFixture
            && !showsHermesVoiceFixture
            && gatewayVisualFixture == nil
    }

}
#else
struct NileAppGraphFixturePlan {
    let forcesReducedMotionFixture = false
    let showsNotificationEducationFixture = false
    let showsSessionFixture = false
    let confirmsGatewaySwitchFixture = false

    init(arguments: [String]) {}

    var automaticallyRestoresGateway: Bool { true }
}
#endif
