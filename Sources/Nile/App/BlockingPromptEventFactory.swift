import Foundation

/// Interprets one Hermes event without owning prompt lifecycle state.
struct BlockingPromptEventRequest {
    let liveSessionID: String
    let requestID: String?
    let deduplicationKind: BlockingPromptKind?

    private let event: HermesStreamEvent
    private let identifierKind: String

    init?(_ event: HermesStreamEvent) {
        switch event {
        case let .clarificationRequest(sessionID, requestID, _, _):
            liveSessionID = sessionID
            self.requestID = requestID
            deduplicationKind = .clarification
            identifierKind = "clarify"
        case let .approvalRequest(sessionID, _, _, _):
            liveSessionID = sessionID
            requestID = nil
            deduplicationKind = nil
            identifierKind = "approval"
        case let .sudoRequest(sessionID, requestID):
            liveSessionID = sessionID
            self.requestID = requestID
            deduplicationKind = .sudo
            identifierKind = "sudo"
        case let .secretRequest(sessionID, requestID, _, _, _):
            liveSessionID = sessionID
            self.requestID = requestID
            deduplicationKind = .secret
            identifierKind = "secret"
        case let .blockingRequestInvalid(sessionID, _, _):
            liveSessionID = sessionID
            requestID = nil
            deduplicationKind = nil
            identifierKind = "invalid"
        default:
            return nil
        }
        self.event = event
    }

    func makePrompt(sequence: Int64) -> TranscriptBlockingPrompt {
        let id = promptID(sequence: sequence)
        switch event {
        case let .clarificationRequest(_, _, question, choices):
            return TranscriptBlockingPrompt(
                id: id,
                kind: .clarification,
                title: "Hermes needs your input",
                message: question,
                actions: (choices ?? []).map {
                    BlockingPromptAction(value: $0, label: $0)
                },
                acceptsText: true,
                skipLabel: "Skip"
            )
        case let .approvalRequest(_, command, description, allowPermanent):
            var actions = [
                BlockingPromptAction(value: "once", label: "Allow once"),
                BlockingPromptAction(
                    value: "session",
                    label: "Allow for this session"
                ),
            ]
            if allowPermanent {
                actions.append(
                    BlockingPromptAction(
                        value: "always",
                        label: "Always allow"
                    )
                )
            }
            actions.append(
                BlockingPromptAction(
                    value: "deny",
                    label: "Deny",
                    destructive: true
                )
            )
            return TranscriptBlockingPrompt(
                id: id,
                kind: .approval,
                title: "Run this command?",
                message: description,
                detail: command,
                actions: actions
            )
        case .sudoRequest:
            return TranscriptBlockingPrompt(
                id: id,
                kind: .sudo,
                title: "Administrator password needed",
                message:
                    "Hermes needs a sudo password to continue this command.",
                acceptsText: true,
                sensitive: true,
                skipLabel: "Cancel"
            )
        case let .secretRequest(_, _, envVar, message, metadata):
            var context = ["Environment variable: \(envVar)"]
            if let skillName = metadata?.skillName {
                context.append("Skill: \(skillName)")
            }
            if let requiredFor = metadata?.requiredFor {
                context.append("Required for: \(requiredFor)")
            }
            if let help = metadata?.help {
                context.append(help)
            }
            return TranscriptBlockingPrompt(
                id: id,
                kind: .secret,
                title: "Secret needed",
                message: message,
                detail: context.joined(separator: "\n"),
                acceptsText: true,
                sensitive: true,
                skipLabel: "Skip"
            )
        case let .blockingRequestInvalid(_, _, message):
            return TranscriptBlockingPrompt(
                id: id,
                kind: .unavailable,
                title: "Input request unavailable",
                message: message,
                detail:
                    "Hermes did not provide enough information to answer safely. Stop the run to continue.",
                status: .uncertain,
                statusMessage: "This request cannot be answered safely.",
                actionable: false
            )
        default:
            preconditionFailure("Blocking prompt request retained an invalid event")
        }
    }

    private func promptID(sequence: Int64) -> String {
        var result = "blocking-\(identifierKind)-"
        if let requestID {
            result += "\(requestID)-"
        }
        return result + String(sequence)
    }
}
