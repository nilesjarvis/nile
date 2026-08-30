#if DEBUG || NILE_LOCAL_RELEASE
import Foundation

extension SessionListFixture {
    var liveSessions: [String: LiveSession] {
        if self == .empty {
            return [:]
        }
        if self == .terminalBusy {
            return [:]
        }
        if self == .visualRegressionMedia {
            return [:]
        }
        if self == .blockingClarification {
            return [
                "brand": LiveSession(
                    liveID: "live-brand",
                    storedID: "brand",
                    info: SessionInfo(
                        model: nil,
                        provider: nil,
                        reasoningEffort: nil,
                        reasoningEffortSessionScopeSupported: false
                    ),
                    messages: [],
                    running: true,
                    status: "waiting",
                    inflight: nil
                ),
            ]
        }
        if self == .visualRegressionModelPicker
            || self == .visualRegressionAttachments
            || self == .visualRegressionSyntax
            || self == .visualRegressionDelegation
            || self == .visualRegressionContext
            || self == .visualRegressionStats
            || self == .goalCreation
            || self == .goalActive
        {
            return [
                "session": LiveSession(
                    liveID: "live-session",
                    storedID: "session",
                    info: SessionInfo(
                        model:
                            self == .visualRegressionModelPicker
                                ? "reasoning-model"
                                : nil,
                        provider:
                            self == .visualRegressionModelPicker
                                ? "provider"
                                : nil,
                        reasoningEffort: nil,
                        reasoningEffortSessionScopeSupported: false
                    ),
                    messages:
                        self == .visualRegressionSyntax
                            ? visualRegressionSyntaxMessages()
                            : self == .visualRegressionAttachments
                                ? attachmentMessages()
                                : [],
                    running: false,
                    status: "idle",
                    inflight: nil
                ),
            ]
        }
        if self == .transcriptScroll {
            return [
                "scroll-alpha": scrollLiveSession(
                    prefix: "Alpha",
                    sessionID: "scroll-alpha",
                    liveID: "live-scroll-alpha"
                ),
                "scroll-beta": scrollLiveSession(
                    prefix: "Beta",
                    sessionID: "scroll-beta",
                    liveID: "live-scroll-beta"
                ),
            ]
        }
        let blocking = !blockingEvents.isEmpty
        let messages: [HermesMessage] = if self == .visualRegressionBrand {
            []
        } else if self == .attachments {
            attachmentMessages()
        } else {
            [
                HermesMessage(
                    role: "user",
                    text: "Polish the chat surface and verify the complete interaction."
                ),
                HermesMessage(
                    role: "assistant",
                    text: "I’ll inspect the shared design language, exercise the transcript states, and keep the result intentionally compact."
                ),
                HermesMessage(
                    role: "tool",
                    text: "113 tests passed",
                    toolName: "terminal",
                    toolContext: "Running `xcodebuild test`",
                    toolOutcome: .succeeded
                ),
                HermesMessage(
                    role: "tool",
                    text: "Loaded the native UI guidance.",
                    toolName: "skill_view",
                    toolContext: "Reading transcript design",
                    toolOutcome: .succeeded
                ),
                HermesMessage(
                    role: "assistant",
                    text: "The transcript now preserves **chronological assistant segments**, compact tool activity, and Nile's neutral graphite hierarchy."
                ),
            ]
        }
        let model = self == .modelPicker
            ? "gemini-3-pro"
            : "Gemini 3 Pro"
        let provider = self == .modelPicker
            ? "google"
            : "design-fixture"
        return [
            "brand": LiveSession(
                liveID: "live-brand",
                storedID: "brand",
                info: SessionInfo(
                    model: model,
                    provider: provider,
                    reasoningEffort: "high",
                    reasoningEffortSessionScopeSupported: true
                ),
                messages: messages,
                running: blocking,
                status: blocking ? "waiting" : "idle",
                inflight: nil
            ),
        ]
    }

    var storedMessages: [String: [HermesMessage]] {
        [
            "cli": [
                HermesMessage(
                    role: "user",
                    text: "Audit the gateway ownership boundary."
                ),
                HermesMessage(
                    role: "assistant",
                    text: "The terminal session remains a read-only mirror until you explicitly Claim it."
                ),
            ],
        ]
    }

    private func attachmentMessages() -> [HermesMessage] {
        [
            HermesMessage(
                role: "user",
                text: "Compare these two references."
            ),
            HermesMessage(
                role: "assistant",
                text:
                    "I generated the visual comparison.\n\nMEDIA:/tmp/nile-comparison.png"
            ),
            HermesMessage(
                role: "assistant",
                text:
                    "The source notes are attached too.\n\n[[as_document]] MEDIA:\"/tmp/reference notes.txt\""
            ),
        ]
    }

    private func scrollLiveSession(
        prefix: String,
        sessionID: String,
        liveID: String
    ) -> LiveSession {
        var messages = (1...38).map { index in
            HermesMessage(
                role: "assistant",
                text: "\(prefix) message \(index)"
            )
        }
        messages.append(
            HermesMessage(
                role: "assistant",
                text:
                    "\(prefix) syntax reference:\n\n```kotlin\nval name = \"hermes\" // agent\n```"
            )
        )
        messages.append(
            HermesMessage(
                role: "user",
                text: "\(prefix) message 40"
            )
        )
        return LiveSession(
            liveID: liveID,
            storedID: sessionID,
            info: SessionInfo(
                model: "Gemini 3 Pro",
                provider: "scroll-fixture",
                reasoningEffort: "high",
                reasoningEffortSessionScopeSupported: true
            ),
            messages: messages,
            running: false,
            status: "idle",
            inflight: nil
        )
    }

    private func visualRegressionSyntaxMessages() -> [HermesMessage] {
        var messages = (1...38).map { index in
            HermesMessage(
                role: "assistant",
                text: "History message \(index)"
            )
        }
        messages.append(
            HermesMessage(
                role: "assistant",
                text:
                    "Syntax reference:\n\n```kotlin\nval name = \"hermes\" // agent\n```"
            )
        )
        messages.append(
            HermesMessage(
                role: "user",
                text: "History message 40"
            )
        )
        return messages
    }
}
#endif
