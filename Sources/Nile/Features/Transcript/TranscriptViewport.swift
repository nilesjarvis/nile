import os
import SwiftUI
import UIKit

struct TranscriptViewportItem: Equatable, Identifiable {
    enum Content: Equatable {
        case launchpad([SessionLaunchpadQuickStart])
        case row(TranscriptDisplayRow)
    }

    let id: String
    let content: Content
    var streaming = false
    var delegationTurn: DelegationTurnUI?
    var delegationControlsEnabled = false
    var toolGroupExpanded = false
    var toolGroupRipple: ToolActivityRipple?
    var reduceMotion: Bool
}

struct TranscriptViewportChangeSet: Equatable {
    let structureChanged: Bool
    let removedIDs: Set<String>
    let changedIDs: Set<String>
    let nextItemsByID: [String: TranscriptViewportItem]
    let nextIDs: [String]

    init(
        previousItemsByID: [String: TranscriptViewportItem],
        previousIDs: [String],
        nextItems: [TranscriptViewportItem]
    ) {
        let ids = nextItems.map(\.id)
        let itemsByID = Dictionary(
            uniqueKeysWithValues: nextItems.map { ($0.id, $0) }
        )
        nextIDs = ids
        nextItemsByID = itemsByID
        structureChanged = previousIDs != ids
        removedIDs = Set(previousIDs).subtracting(ids)
        changedIDs = Set(ids.filter { id in
            previousItemsByID[id] != itemsByID[id]
        })
    }
}

struct TranscriptViewportActions {
    let onSelectQuickStart: (String) -> Void
    let onRespondToBlockingPrompt: (String, String) -> Void
    let onSecureEntry: (TranscriptBlockingPrompt) -> Void
    let onPermanentApproval: (TranscriptBlockingPrompt) -> Void
    let onOpenAttachment: (String) -> Void
    let onStopDelegatedAgent: (String) -> Void
    let onOpenDelegatedChild: (String) -> Void
    let onToggleToolGroup: (String, Bool) -> Void
    let onRippleToolGroup: (String, CGPoint) -> Void
}

struct TranscriptViewport: UIViewControllerRepresentable {
    let owner: TranscriptScrollOwner?
    let scrollState: TranscriptScrollCoordinator
    let lastUserEntryID: String?
    let jumpToBottomRevision: Int
    let automaticTailPinEnabled: Bool
    let retainsTopInset: Bool
    let interactionEnabled: Bool
    let accessibilityHidden: Bool
    let items: [TranscriptViewportItem]
    let actions: TranscriptViewportActions
    let onAnchoredChange: (Bool) -> Void
    let onAnchorTransition: (TranscriptScrollAnchorTransition) -> Void

    func makeUIViewController(
        context: Context
    ) -> TranscriptViewportController {
        TranscriptViewportController()
    }

    func updateUIViewController(
        _ controller: TranscriptViewportController,
        context: Context
    ) {
        controller.update(
            items: items,
            actions: actions,
            owner: owner,
            scrollState: scrollState,
            lastUserEntryID: lastUserEntryID,
            jumpToBottomRevision: jumpToBottomRevision,
            automaticTailPinEnabled: automaticTailPinEnabled,
            retainsTopInset: retainsTopInset,
            interactionEnabled: interactionEnabled,
            accessibilityHidden: accessibilityHidden,
            onAnchoredChange: onAnchoredChange,
            onAnchorTransition: onAnchorTransition
        )
    }
}
