import CoreGraphics
import Foundation

struct TranscriptScrollOwner: Equatable, Hashable, Sendable {
    let gatewayID: String
    let sessionID: String

    var stateKey: String {
        "\(gatewayID.utf16.count):\(gatewayID):\(sessionID)"
    }
}

struct TranscriptScrollPresentation: Equatable, Sendable {
    let isAnchored: Bool
    let contentOffsetY: CGFloat?
}

enum TranscriptScrollAnchorTransition: Equatable, Sendable {
    case leftBottom
    case reachedBottom
}

/// Owns the durable, per-session reading position for the transcript viewport.
///
/// UIKit owns the authoritative geometry. This coordinator stores only the
/// resulting mode and offset, rather than trying to reconstruct a viewport from
/// whichever lazy SwiftUI rows happened to publish a frame in the last pass.
@MainActor
final class TranscriptScrollCoordinator {
    private struct OwnerState {
        var isAnchored = true
        var contentOffsetY: CGFloat?
        var observedUserTailInitialized = false
        var observedLastUserEntryID: String?
    }

    private var states: [TranscriptScrollOwner: OwnerState] = [:]

    func activate(
        owner: TranscriptScrollOwner,
        lastUserEntryID: String?
    ) -> TranscriptScrollPresentation {
        var state = states[owner] ?? OwnerState()
        observeInitialUserTail(lastUserEntryID, state: &state)
        states[owner] = state
        return presentation(for: state)
    }

    func contentChanged(
        owner: TranscriptScrollOwner,
        lastUserEntryID: String?
    ) -> TranscriptScrollPresentation {
        var state = states[owner] ?? OwnerState()
        if !state.observedUserTailInitialized {
            observeInitialUserTail(lastUserEntryID, state: &state)
        } else if lastUserEntryID != state.observedLastUserEntryID {
            state.observedLastUserEntryID = lastUserEntryID
            if lastUserEntryID != nil {
                state.isAnchored = true
                state.contentOffsetY = nil
            }
        }
        states[owner] = state
        return presentation(for: state)
    }

    func recordUserScroll(
        owner: TranscriptScrollOwner,
        contentOffsetY: CGFloat,
        isBottomVisible: Bool
    ) -> TranscriptScrollAnchorTransition? {
        var state = states[owner] ?? OwnerState()
        state.contentOffsetY = contentOffsetY
        let wasAnchored = state.isAnchored
        state.isAnchored = isBottomVisible
        states[owner] = state
        guard wasAnchored != state.isAnchored else {
            return nil
        }
        return state.isAnchored ? .reachedBottom : .leftBottom
    }

    func recordProgrammaticPosition(
        owner: TranscriptScrollOwner,
        contentOffsetY: CGFloat
    ) {
        var state = states[owner] ?? OwnerState()
        state.contentOffsetY = contentOffsetY
        states[owner] = state
    }

    func jumpToBottom(
        owner: TranscriptScrollOwner
    ) -> TranscriptScrollPresentation {
        var state = states[owner] ?? OwnerState()
        state.isAnchored = true
        state.contentOffsetY = nil
        states[owner] = state
        return presentation(for: state)
    }

    func isAnchored(owner: TranscriptScrollOwner) -> Bool {
        states[owner]?.isAnchored ?? true
    }

    private func presentation(
        for state: OwnerState
    ) -> TranscriptScrollPresentation {
        TranscriptScrollPresentation(
            isAnchored: state.isAnchored,
            contentOffsetY: state.isAnchored ? nil : state.contentOffsetY
        )
    }

    private func observeInitialUserTail(
        _ lastUserEntryID: String?,
        state: inout OwnerState
    ) {
        state.observedUserTailInitialized = true
        state.observedLastUserEntryID = lastUserEntryID
    }
}
