import Foundation

struct LiveToolEvent: Equatable, Sendable {
    let toolID: String?
    let name: String
    let status: String
    let content: String
    var outcome: ToolCompletionOutcome = .unknown
    var label: String?
    var summary: String?
    var durationSeconds: Double?
    var todos: [TodoItem]?
    var inlineDiff: String?
}

struct LiveTranscriptProjection: Equatable, Sendable {
    let transcript: [TranscriptEntry]
    let activeTodos: [TodoItem]?
}

struct LiveTranscriptToolProjector {
    private let clockMilliseconds: () -> Int64

    init(clockMilliseconds: @escaping () -> Int64) {
        self.clockMilliseconds = clockMilliseconds
    }

    func startsNewTool(
        in transcript: [TranscriptEntry],
        event: LiveToolEvent
    ) -> Bool {
        let id = toolID(for: event)
        return !transcript.contains { $0.id == id }
    }

    func upsert(
        in transcript: [TranscriptEntry],
        activeTodos: [TodoItem]?,
        event: LiveToolEvent
    ) -> LiveTranscriptProjection {
        let id = toolID(for: event)
        let resolvedKind = toolKind(event.name)
        let resolvedLabel = event.label?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false ? event.label : nil
        var updated = transcript
        if let index = updated.firstIndex(where: { $0.id == id }),
           case var .tool(tool) = updated[index] {
            tool.status = event.status
            if !event.content
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tool.content = event.content
            }
            tool.outcome = event.outcome
            tool.kind = resolvedKind
            tool.label = resolvedLabel
                ?? tool.label
                ?? defaultToolLabel(event.name)
            tool.summary = event.summary ?? tool.summary
            tool.durationSeconds = event.durationSeconds ?? tool.durationSeconds
            tool.todos = event.todos ?? tool.todos
            tool.inlineDiff = event.inlineDiff ?? tool.inlineDiff
            updated[index] = .tool(tool)
        } else {
            updated.append(
                .tool(
                    TranscriptTool(
                        id: id,
                        name: event.name,
                        status: event.status,
                        content: event.content,
                        outcome: event.outcome,
                        kind: resolvedKind,
                        label: resolvedLabel ?? defaultToolLabel(event.name),
                        summary: event.summary,
                        durationSeconds: event.durationSeconds,
                        todos: event.todos,
                        inlineDiff: event.inlineDiff,
                        startedAtMilliseconds: event.status == "running"
                            ? clockMilliseconds()
                            : nil
                    )
                )
            )
        }
        return LiveTranscriptProjection(
            transcript: updated,
            activeTodos: event.todos == nil
                ? activeTodos
                : event.todos?.isEmpty == false ? event.todos : nil
        )
    }

    private func toolID(for event: LiveToolEvent) -> String {
        "tool-\(event.toolID ?? event.name)"
    }
}
