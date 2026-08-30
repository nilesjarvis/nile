#if DEBUG
import Foundation

struct SessionDelegationEventFixture {
    struct Event {
        let kind: SubagentEventKind
        let data: SubagentEventData
    }

    let events: [Event]
    let marksParentCompleted: Bool

    static func make(settled: Bool) -> Self {
        let primary = SubagentEventData(
            goal:
                "Compare every delegated-agent state with the Android reference",
            taskCount: settled ? 1 : 2,
            taskIndex: 0,
            subagentID: "fixture-agent-one",
            parentID: "fixture-parent",
            childSessionID: "fixture-child-one",
            depth: 1,
            model: "gemini-3-pro",
            toolCount: settled ? 7 : 4,
            toolsets: ["terminal", "read_file"],
            text: settled ? "Visual diff complete" : "Running simulator checks",
            toolName: "terminal",
            toolPreview: "xcodebuild test",
            terminalStatus: settled ? .completed : nil,
            rawTerminalStatus: settled ? "completed" : nil,
            summary: settled ? "All delegated checks matched." : nil,
            durationSeconds: settled ? 42 : nil,
            inputTokens: 12_400,
            outputTokens: 2_100,
            reasoningTokens: 900,
            apiCalls: 8,
            filesRead: ["DelegationUi.kt", "DelegationView.swift"],
            filesWritten: settled ? ["PARITY_REPORT.md"] : [],
            outputTail: [
                SubagentOutput(
                    tool: "terminal",
                    preview: settled ? "19 tests passed" : "Testing…",
                    isError: false,
                    status: settled ? "done" : "running"
                ),
            ]
        )
        var events = [
            Event(
                kind: settled ? .completed : .progress,
                data: primary
            ),
        ]
        if !settled {
            events.append(
                Event(
                    kind: .spawnRequested,
                    data: SubagentEventData(
                        goal: "Audit snapshot recovery and interrupt semantics",
                        taskCount: 2,
                        taskIndex: 1,
                        subagentID: "fixture-agent-two",
                        parentID: "fixture-parent",
                        childSessionID: nil,
                        depth: 1,
                        model: "claude-sonnet-4",
                        toolCount: 0,
                        toolsets: ["read_file"],
                        text: "Waiting for an execution slot",
                        toolName: nil,
                        toolPreview: nil,
                        terminalStatus: nil,
                        rawTerminalStatus: nil,
                        summary: nil,
                        durationSeconds: nil,
                        inputTokens: nil,
                        outputTokens: nil,
                        reasoningTokens: nil,
                        apiCalls: nil,
                        filesRead: [],
                        filesWritten: [],
                        outputTail: []
                    )
                )
            )
        }
        return Self(
            events: events,
            marksParentCompleted: settled
        )
    }
}

struct SessionDelegationPresentationFixture {
    let turns: [DelegationTurnUI]
    let pinnedTurnID: String?
    let transcript: [TranscriptEntry]

    static let androidVisual: Self = {
        let agents = [
            DelegatedAgentUI(
                rowID: "analysis-row",
                subagentID: "subagent-analysis-row",
                parentID: "parent-agent",
                childSessionID: "child-analysis-row",
                goal: "Analyze protocol",
                taskCount: 3,
                taskIndex: 1,
                depth: 1,
                model: "test-model",
                status: .finished(.completed),
                toolCount: 2,
                toolsets: ["files"],
                latestActivity: "Processing fixture",
                toolName: "read",
                toolPreview: "fixture.kt",
                rawTerminalStatus: "completed",
                summary: nil,
                durationSeconds: 3,
                inputTokens: 100,
                outputTokens: 25,
                reasoningTokens: 10,
                apiCalls: 2,
                filesRead: ["fixture.kt"],
                filesWritten: [],
                outputTail: []
            ),
            DelegatedAgentUI(
                rowID: "ui-row",
                subagentID: "subagent-ui-row",
                parentID: "parent-agent",
                childSessionID: "child-ui",
                goal: "Build delegation UI",
                taskCount: 3,
                taskIndex: 1,
                depth: 1,
                model: "test-model",
                status: .running,
                toolCount: 2,
                toolsets: ["files"],
                latestActivity: "Processing fixture",
                toolName: "read",
                toolPreview: "fixture.kt",
                rawTerminalStatus: nil,
                summary: nil,
                durationSeconds: 3,
                inputTokens: 100,
                outputTokens: 25,
                reasoningTokens: 10,
                apiCalls: 2,
                filesRead: ["fixture.kt"],
                filesWritten: [],
                outputTail: []
            ),
            DelegatedAgentUI(
                rowID: "qa-row",
                subagentID: "subagent-qa-row",
                parentID: "parent-agent",
                childSessionID: "child-qa-row",
                goal: "Verify failure handling",
                taskCount: 3,
                taskIndex: 1,
                depth: 1,
                model: "test-model",
                status: .finished(.failed),
                toolCount: 2,
                toolsets: ["files"],
                latestActivity: "Processing fixture",
                toolName: "read",
                toolPreview: "fixture.kt",
                rawTerminalStatus: "failed",
                summary:
                    "Gateway rejected the child request after validating the retry path and preserving the full failure context for review",
                durationSeconds: 3,
                inputTokens: 100,
                outputTokens: 25,
                reasoningTokens: 10,
                apiCalls: 2,
                filesRead: ["fixture.kt"],
                filesWritten: [],
                outputTail: []
            ),
        ]
        let turn = DelegationTurnUI(
            id: "delegation-turn",
            storedSessionID: "session",
            agents: agents,
            startedAtEpochSeconds: 100,
            finishedAtEpochSeconds: nil,
            isPinned: true
        )
        return Self(
            turns: [turn],
            pinnedTurnID: turn.id,
            transcript: [
                .delegation(
                    TranscriptDelegation(
                        id: "delegation-entry-\(turn.id)",
                        turnID: turn.id
                    )
                ),
            ]
        )
    }()
}
#endif
