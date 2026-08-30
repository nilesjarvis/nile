import Foundation

#if DEBUG || NILE_LOCAL_RELEASE
/// Applies the selected deterministic state after the real graph or its narrow
/// fixture collaborators have been assembled.
@MainActor
enum NileAppGraphFixtureInstaller {
    static func install(
        _ plan: NileAppGraphFixturePlan,
        on sessionList: SessionListModel
    ) -> Task<Void, Never>? {
        if plan.showsUsageFixture {
            sessionList.usage = NileAppGraphFixtures.sessionUsage()
            sessionList.isContextSheetVisible = true
        }
        if let composerActivity = plan.composerActivityFixture {
            composerActivity.apply(to: sessionList)
        }
        if plan.showsStatsFixture {
            installStatistics(on: sessionList)
        }
#if DEBUG
        if plan.showsDelegationActiveFixture
            || plan.showsDelegationSettledFixture
        {
            sessionList.installDelegationFixture(
                settled: plan.showsDelegationSettledFixture
            )
        }
        if plan.showsAndroidVisualDelegationFixture {
            sessionList.installAndroidVisualDelegationFixture()
        }
#endif
        if plan.showsAndroidVisualRenameFixture {
            sessionList.setRenameDialogVisible(true)
        }
        if let transcript = plan.streamingTranscriptFixture {
            installStreamingTranscript(transcript, on: sessionList)
        }
        let streamingTask = plan.showsStreamingStressFixture
            ? installStreamingStress(on: sessionList)
            : nil
        if plan.showsActivePlanFixture {
            installActivePlan(on: sessionList)
        }
        if let phase = plan.recoveryFixturePhase {
            sessionList.setConnectionRecoveryPhase(phase)
        }
        return streamingTask
    }

    private static func installStatistics(on sessionList: SessionListModel) {
        let referenceDate = NileAppGraphFixtures.gatewayStatsReferenceDate()
        sessionList.gatewayStats = NileAppGraphFixtures.gatewayStats(
            days: 30,
            referenceDate: referenceDate
        )
        sessionList.heatmapDailyStats = NileAppGraphFixtures.gatewayStats(
            days: 91,
            referenceDate: referenceDate
        ).daily
        sessionList.statsReferenceDate = referenceDate
        sessionList.isStatsSheetVisible = true
    }

    private static func installStreamingTranscript(
        _ fixture: NileAppGraphFixtures.StreamingTranscriptFixture,
        on sessionList: SessionListModel
    ) {
        sessionList.transcriptEntries = [
            .message(
                TranscriptMessage(
                    id: "streaming-user",
                    role: .user,
                    content: "Show the live response without a cursor."
                )
            ),
            .message(
                TranscriptMessage(
                    id: "streaming-assistant",
                    role: .assistant,
                    content: fixture.content,
                    images: fixture.images
                )
            ),
        ]
        sessionList.isSending = fixture.isStreaming
    }

    private static func installActivePlan(on sessionList: SessionListModel) {
        sessionList.transcriptEntries = sessionList.transcriptEntries.map {
            entry in
            guard case let .tool(original) = entry,
                  original.name == "skill_view" else {
                return entry
            }
            var tool = original
            tool.label =
                "Reading the transcript design guidance without cutting "
                + "off the important context"
            return .tool(tool)
        }
        sessionList.activeTodos = [
            TodoItem(
                content: "Inspect the transcript layout",
                status: "completed"
            ),
            TodoItem(
                content:
                    "Keep the current task readable while collapsed "
                    + "without cutting off the end",
                status: "in_progress"
            ),
            TodoItem(
                content: "Verify the expanded checklist spacing",
                status: "pending"
            ),
            TodoItem(
                content: "Confirm the transcript remains usable",
                status: "pending"
            ),
            TodoItem(
                content: "Capture the final compact plan",
                status: "pending"
            ),
        ]
        sessionList.isSending = true
    }

    private static func installStreamingStress(
        on sessionList: SessionListModel
    ) -> Task<Void, Never> {
        let history = (1...14).flatMap { index in
            [
                TranscriptEntry.message(
                    TranscriptMessage(
                        id: "stream-stress-user-\(index)",
                        role: .user,
                        content: "Earlier request \(index)"
                    )
                ),
                TranscriptEntry.message(
                    TranscriptMessage(
                        id: "stream-stress-assistant-\(index)",
                        role: .assistant,
                        content:
                            "Earlier response \(index) remains laid out while the live response grows."
                    )
                ),
            ]
        }
        let user = TranscriptEntry.message(
            TranscriptMessage(
                id: "stream-stress-user-live",
                role: .user,
                content: "Stream a long response while I keep reading."
            )
        )
        sessionList.transcriptEntries = history + [
            user,
            streamingStressAssistant(content: ""),
        ]
        sessionList.isSending = true

        return Task { @MainActor [weak sessionList] in
            try? await Task.sleep(for: .seconds(2))
            guard let sessionList, !Task.isCancelled else {
                return
            }
            var content = ""
            for (index, fragment) in streamingStressFragments.enumerated() {
                content += fragment
                replaceStreamingStressAssistant(
                    content: content,
                    on: sessionList
                )
                try? await Task.sleep(
                    for: index == 39 ? .seconds(8) : .milliseconds(90)
                )
                guard !Task.isCancelled else {
                    return
                }
            }
            content += "\nSTREAM COMPLETE\n"
            replaceStreamingStressAssistant(
                content: content,
                on: sessionList
            )
            sessionList.isSending = false
        }
    }

    private static func replaceStreamingStressAssistant(
        content: String,
        on sessionList: SessionListModel
    ) {
        let replacement = streamingStressAssistant(content: content)
        sessionList.transcriptEntries = sessionList.transcriptEntries.map {
            $0.id == replacement.id ? replacement : $0
        }
    }

    private static func streamingStressAssistant(
        content: String
    ) -> TranscriptEntry {
        .message(
            TranscriptMessage(
                id: "stream-stress-assistant-live",
                role: .assistant,
                content: content
            )
        )
    }

    private static var streamingStressFragments: [String] {
        var fragments = (1...40).map { index in
            var fragment =
                "Streaming paragraph \(index) keeps its own measured height as new text arrives.\n\n"
            if index.isMultiple(of: 10) {
                fragment += "## STREAM CHECKPOINT \(index)\n\n"
            }
            return fragment
        }
        fragments += [
            "| Area | State |\n",
            "| --- | --- |\n",
            "| viewport | stable |\n",
            "| reading position | retained |\n\n",
            "```swift\n",
            "let transcript = ReliableViewport()\n",
            "transcript.followTail()\n",
            "```\n\n",
        ]
        fragments += (41...60).map { index in
            "Streaming paragraph \(index) verifies continued growth after syntax changes.\n\n"
        }
        return fragments
    }
}
#else
@MainActor
enum NileAppGraphFixtureInstaller {
    static func install(
        _ plan: NileAppGraphFixturePlan,
        on sessionList: SessionListModel
    ) -> Task<Void, Never>? { nil }
}
#endif
