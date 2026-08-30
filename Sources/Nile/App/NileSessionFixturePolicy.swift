#if DEBUG || NILE_LOCAL_RELEASE
/// Pure precedence for session-facing launch fixtures.
///
/// The app-graph plan retains filtered argument state and global fixture
/// admission; this policy alone maps those arguments to session catalog,
/// streaming, and recovery values.
enum NileSessionFixturePolicy {
    static func streamingTranscript(
        arguments: Set<String>
    ) -> NileAppGraphFixtures.StreamingTranscriptFixture? {
        if arguments.contains("--nile-fixture-streaming-empty") {
            return .empty
        }
        if arguments.contains("--nile-fixture-streaming-partial") {
            return .partial
        }
        if arguments.contains("--nile-fixture-markdown-table") {
            return .table
        }
        return nil
    }

    static func recoveryPhase(
        arguments: Set<String>
    ) -> SessionConnectionPhase? {
        if arguments.contains("--nile-fixture-offline") {
            return .offline
        }
        if arguments.contains("--nile-fixture-reconnecting") {
            return .reconnecting
        }
        if arguments.contains("--nile-fixture-restoring") {
            return .restoring
        }
        return nil
    }

    static func sessionFixture(
        arguments: Set<String>,
        composerActivity: NileAppGraphFixtures.ComposerActivityFixture?
    ) -> SessionListFixture? {
        if let composerActivity {
            return composerActivity == .needsInput
                ? .blockingClarification
                : .androidBrand
        }
        let mappings: [(String, SessionListFixture)] = [
            ("--nile-fixture-session-empty", .empty),
            ("--nile-fixture-session-switching", .androidBrand),
            ("--nile-fixture-session-switching-empty", .androidVisualBrand),
            ("--nile-fixture-android-visual-brand", .androidVisualBrand),
            ("--nile-fixture-android-visual-media", .androidVisualMedia),
            ("--nile-fixture-android-visual-attachments", .androidVisualAttachments),
            ("--nile-fixture-android-visual-transcript-syntax", .androidVisualSyntax),
            ("--nile-fixture-transcript-scroll", .transcriptScroll),
            ("--nile-fixture-android-delegation-mixed", .androidVisualDelegation),
            ("--nile-fixture-usage-context", .androidVisualContext),
            ("--nile-fixture-stats", .androidVisualStats),
            ("--nile-fixture-android-visual-rename", .androidVisualContext),
            ("--nile-fixture-blocking-clarification", .blockingClarification),
            ("--nile-fixture-blocking-approvals", .blockingApprovals),
            ("--nile-fixture-blocking-sudo", .blockingSudo),
            ("--nile-fixture-blocking-secret", .blockingSecret),
            ("--nile-fixture-blocking-invalid", .blockingInvalid),
            ("--nile-fixture-attachments", .attachments),
            ("--nile-fixture-android-visual-model-picker", .androidVisualModelPicker),
            ("--nile-fixture-model-picker", .modelPicker),
            ("--nile-fixture-goal-create", .goalCreation),
            ("--nile-fixture-goal-active", .goalActive),
        ]
        return mappings.first { arguments.contains($0.0) }?.1
    }
}
#endif
