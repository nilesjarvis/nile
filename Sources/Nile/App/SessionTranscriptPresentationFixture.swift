#if DEBUG || NILE_LOCAL_RELEASE
import Foundation

extension SessionListFixture {
    var transcriptEntries: [TranscriptEntry]? {
        switch self {
        case .visualRegressionBrand:
            return [
                .message(
                    TranscriptMessage(
                        id: "user-1",
                        role: .user,
                        content:
                            "Refine the Nile experience around the new visual direction."
                    )
                ),
                .message(
                    TranscriptMessage(
                        id: "assistant-1",
                        role: .assistant,
                        content:
                            """
                            ## Shaping the mobile agent experience

                            I mapped the supplied reference into Nile's own interaction system: neutral graphite layers, compact status rows, and a single anchored composer.

                            - Keep the transcript visually quiet and content-first.
                            - Reserve violet and cobalt for selections and primary actions.
                            - Use raised gray only for the user's message.

                            ## Key takeaways

                            1. Dense typography keeps more agent context visible.
                            2. Low-contrast surfaces make state and content—not containers—the focus.
                            """
                    )
                ),
                .tool(
                    TranscriptTool(
                        id: "tool-1",
                        name: "terminal",
                        status: "done",
                        content:
                            "./gradlew testDebugUnitTest assembleDebug\nBUILD SUCCESSFUL",
                        outcome: .succeeded,
                        kind: .terminal,
                        label: "Built and tested the iOS app",
                        summary: "Build passed in 18s",
                        durationSeconds: 18.2
                    )
                ),
                .message(
                    TranscriptMessage(
                        id: "assistant-2",
                        role: .assistant,
                        content:
                            "The neutral graphite theme, violet actions, circular controls, and compact composer are ready for a final visual review."
                    )
                ),
            ]
        case .visualRegressionMedia:
            return [
                .message(
                    TranscriptMessage(
                        id: "media-user",
                        role: .user,
                        content:
                            "Concatenate the four fragments NILE-, CLI-, FIXTURE-, and OK. Reply with only the concatenated token and no formatting."
                    )
                ),
                .message(
                    TranscriptMessage(
                        id: "media-assistant",
                        role: .assistant,
                        content: "NILE-CLI-FIXTURE-OK",
                        attachments: [
                            MessageAttachment(
                                path:
                                    "/tmp/hermes/images/niles-test-media.png",
                                filename: "niles-test-media.png",
                                kind: .image,
                                previewBase64:
                                    "iVBORw0KGgoAAAANSUhEUgAAAGAAAAA2CAYAAAA4T5zSAAAAkUlEQVR42u3coRHAIBREQWpBpQYsKiINMUMvVEJroNLCR7DiNXDrL42+ls6VjAAAwF9+PgUEAAAAAAAAAAAAAAAAAAAAAAAAAIBxAFwO8NapgAAAAAAAAAAAAAAAAAAAAAAAAAAAMA4AAAIAQKcASpsKCAAAAAAAAAAAAAAAAAAAAAAAAAAA4wC4HEAeswAotg1lLjCxBlaKcQAAAABJRU5ErkJggg==",
                                mimeType: "image/png"
                            ),
                        ]
                    )
                ),
            ]
        case .blockingClarification:
            return []
        default:
            return nil
        }
    }
}
#endif
