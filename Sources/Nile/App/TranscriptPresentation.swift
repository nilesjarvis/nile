import Foundation

enum TranscriptDisplayRow: Equatable, Sendable, Identifiable {
    case entry(TranscriptEntry)
    case toolGroup([TranscriptTool])

    var id: String {
        switch self {
        case let .entry(entry):
            entry.id
        case let .toolGroup(tools):
            tools.first?.id ?? "empty-tool-group"
        }
    }
}

struct TranscriptPresentation: Equatable, Sendable {
    let rows: [TranscriptDisplayRow]
    let streamingEntryID: String?
    let lastUserEntryID: String?
    let hasBlockingPrompt: Bool

    init(
        entries: [TranscriptEntry],
        isSending: Bool,
        pinnedDelegationTurnID: String?
    ) {
        var visibleEntries = entries.visibleTranscriptEntries(
            sending: isSending
        )
        if let pinnedDelegationTurnID {
            visibleEntries.removeAll { entry in
                guard case let .delegation(anchor) = entry else {
                    return false
                }
                return anchor.turnID == pinnedDelegationTurnID
            }
        }

        rows = visibleEntries.displayRows()
        if isSending,
           case let .message(message) = visibleEntries.last,
           message.role == .assistant {
            streamingEntryID = message.id
        } else {
            streamingEntryID = nil
        }
        lastUserEntryID = visibleEntries.last { entry in
            guard case let .message(message) = entry else {
                return false
            }
            return message.role == .user
        }?.id
        hasBlockingPrompt = visibleEntries.contains { entry in
            guard case let .blockingPrompt(prompt) = entry else {
                return false
            }
            return prompt.status.isOpen && prompt.actionable
        }
    }
}

extension Array where Element == TranscriptEntry {
    func displayRows() -> [TranscriptDisplayRow] {
        var rows: [TranscriptDisplayRow] = []
        var pendingTools: [TranscriptTool] = []

        func flushTools() {
            switch pendingTools.count {
            case 0:
                break
            case 1:
                rows.append(.entry(.tool(pendingTools[0])))
            default:
                rows.append(.toolGroup(pendingTools))
            }
            pendingTools.removeAll(keepingCapacity: true)
        }

        for entry in self {
            if case let .tool(tool) = entry {
                pendingTools.append(tool)
            } else {
                flushTools()
                rows.append(.entry(entry))
            }
        }
        flushTools()
        return rows
    }

    func visibleTranscriptEntries(sending: Bool) -> [TranscriptEntry] {
        enumerated().compactMap { index, entry in
            switch entry {
            case let .tool(tool):
                return tool.name == "clarify" ? nil : entry
            case let .message(message):
                guard message.role == .assistant else {
                    return entry
                }
                let meaningful = !message.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                    && message.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() != "null"
                return meaningful
                    || !message.images.isEmpty
                    || !message.attachments.isEmpty
                    || (sending && index == count - 1)
                    ? entry
                    : nil
            case .blockingPrompt:
                return entry
            case .command:
                return entry
            case .delegation:
                return entry
            }
        }
    }
}
