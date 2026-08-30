import Foundation

enum BlockingPromptPolicy {
    static func timeoutMilliseconds(for kind: BlockingPromptKind) -> Int64? {
        switch kind {
        case .clarification, .secret:
            300_000
        case .sudo:
            120_000
        case .approval, .unavailable:
            nil
        }
    }

    static func responseLabel(
        prompt: TranscriptBlockingPrompt,
        response: String
    ) -> String {
        switch prompt.kind {
        case .clarification:
            if response.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                return "Skipped"
            }
            if let action = prompt.actions.first(where: {
                $0.value == response
            }) {
                return "Answered: \(action.label)"
            }
            return "Answered"
        case .approval:
            return switch response {
            case "once": "Allowed once"
            case "session": "Allowed for this session"
            case "always": "Always allowed"
            case "deny": "Denied"
            default: "Answered"
            }
        case .sudo:
            return response.isEmpty ? "Cancelled" : "Password sent"
        case .secret:
            return response.isEmpty ? "Skipped" : "Secret sent"
        case .unavailable:
            return "Unavailable"
        }
    }

    static func isActionable(
        prompt: TranscriptBlockingPrompt,
        isApprovalQueueHead: Bool
    ) -> Bool {
        guard prompt.status == .pending,
              prompt.kind != .unavailable else {
            return false
        }
        return prompt.kind != .approval || isApprovalQueueHead
    }

    static func isRuntimeBusy(status: String?) -> Bool {
        busyStatuses.contains(
            status?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
        )
    }

    static func hasUncertainOutcome(_ error: any Error) -> Bool {
        if let hermes = error as? HermesError {
            return hermes.isConnectionFailure
                || hermes.requestMayHaveSucceeded
        }
        return error is URLError
    }

    static func merge(
        visiblePrompts: [TranscriptBlockingPrompt],
        into transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        let visibleByID = Dictionary(
            uniqueKeysWithValues: visiblePrompts.map { ($0.id, $0) }
        )
        var merged = transcript.compactMap { entry -> TranscriptEntry? in
            guard case let .blockingPrompt(prompt) = entry else {
                return entry
            }
            return visibleByID[prompt.id].map(TranscriptEntry.blockingPrompt)
        }
        let presentIDs = Set<String>(merged.compactMap {
            guard case let .blockingPrompt(prompt) = $0 else {
                return nil
            }
            return prompt.id
        })
        merged.append(
            contentsOf: visiblePrompts
                .filter { !presentIDs.contains($0.id) }
                .map(TranscriptEntry.blockingPrompt)
        )
        return merged
    }

    private static let busyStatuses = Set([
        "working",
        "waiting",
        "starting",
    ])
}
