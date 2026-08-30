import Foundation

/// Synchronous workspace eligibility, error, scroll-owner, and session-directory
/// projection. It has no transport, task, persistence, or event authority.
@MainActor
extension SessionListModel {
    var errorMessage: String? {
        if let operationError {
            return operationError
        }
        if let delegationControlError {
            return delegationControlError
        }
        if [.offline, .reconnecting, .restoring].contains(connectionPhase) {
            return nil
        }
        guard case let .failed(message) = state else {
            return nil
        }
        return message
    }

    var transcriptScrollOwner: TranscriptScrollOwner? {
        guard let gatewayID = currentGatewayID,
              let selectedSessionID else {
            return nil
        }
        return TranscriptScrollOwner(
            gatewayID: gatewayID,
            sessionID: selectedSessionID
        )
    }

    var showsComposer: Bool {
        state == .loaded
            && connectionPhase == .online
            && selectedSessionID != nil
            && liveSession != nil
            && !isReadOnlySession
    }

    func dismissOperationError() {
        operationError = nil
        delegationControlError = nil
    }

    var displayedSessions: [HermesSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prioritized = sessions.enumerated().sorted { left, right in
            let leftRank = priority(of: left.element)
            let rightRank = priority(of: right.element)
            return leftRank == rightRank
                ? left.offset < right.offset
                : leftRank < rightRank
        }.map(\.element)
        guard !query.isEmpty else {
            return prioritized
        }
        return prioritized.filter { session in
            [
                session.title,
                session.preview,
                session.source,
                session.visibleSourceLabel,
                session.id,
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var collapsedSessions: [HermesSession] {
        sessions.enumerated().sorted { left, right in
            let leftPinned = pinnedSessionIDs.contains(left.element.id)
            let rightPinned = pinnedSessionIDs.contains(right.element.id)
            if leftPinned != rightPinned {
                return leftPinned
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    var selectedSessionRuntime: SessionRuntimePresentation? {
        guard let selectedSessionID else {
            return nil
        }
        return runtimePresentation(for: selectedSessionID)
    }

    private func priority(of session: HermesSession) -> Int {
        if pinnedSessionIDs.contains(session.id) {
            return -1
        }
        if sessionsNeedingInput.contains(session.id)
            || activeStatuses[session.id] == "waiting" {
            return 0
        }
        if ["starting", "working"].contains(
            activeStatuses[session.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) {
            return 1
        }
        return 2
    }

    private func runtimePresentation(
        for storedSessionID: String
    ) -> SessionRuntimePresentation? {
        if sessionsNeedingInput.contains(storedSessionID)
            || activeStatuses[storedSessionID] == "waiting" {
            return .needsInput
        }
        switch activeStatuses[storedSessionID]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "starting":
            return .starting
        case "working":
            return .working
        default:
            return nil
        }
    }
}

enum SessionRuntimePresentation: Equatable, Sendable {
    case starting
    case working
    case needsInput

    var label: String {
        switch self {
        case .starting:
            "Starting"
        case .working:
            "Working"
        case .needsInput:
            "Needs input"
        }
    }
}

extension HermesSession {
    var isTerminalOwned: Bool {
        guard let source else {
            return false
        }
        return ["cli", "tui", "terminal"].contains(
            source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    var visibleSourceLabel: String? {
        switch source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "cli":
            return "CLI"
        case "tui":
            return "Terminal TUI"
        case "terminal":
            return "Terminal"
        case "cron":
            return "Cron"
        default:
            return nil
        }
    }
}
