import SwiftUI

/// Maps viewport values and actions into the SwiftUI row root hosted by UIKit.
@MainActor
enum TranscriptViewportRowFactory {
    static func make(
        item: TranscriptViewportItem,
        actions: TranscriptViewportActions?
    ) -> AnyView {
        guard let actions else {
            return AnyView(EmptyView())
        }
        switch item.content {
        case let .launchpad(quickStarts):
            return AnyView(
                SessionLaunchpad(
                    quickStarts: quickStarts,
                    onSelect: actions.onSelectQuickStart
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.nileReduceMotion, item.reduceMotion)
            )
        case let .row(.entry(entry)):
            return AnyView(
                TranscriptRow(
                    entry: entry,
                    streaming: item.streaming,
                    onRespond: actions.onRespondToBlockingPrompt,
                    onSecureEntry: actions.onSecureEntry,
                    onPermanentApproval: actions.onPermanentApproval,
                    onOpenAttachment: actions.onOpenAttachment,
                    delegationTurn: item.delegationTurn,
                    delegationControlsEnabled:
                        item.delegationControlsEnabled,
                    onStopDelegatedAgent:
                        actions.onStopDelegatedAgent,
                    onOpenDelegatedChild:
                        actions.onOpenDelegatedChild
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.nileReduceMotion, item.reduceMotion)
            )
        case let .row(.toolGroup(tools)):
            let groupID = item.id
            return AnyView(
                ToolActivityGroup(
                    tools: tools,
                    expanded: item.toolGroupExpanded,
                    ripple: item.toolGroupRipple,
                    onToggle: { expanded in
                        actions.onToggleToolGroup(groupID, expanded)
                    },
                    onRipple: { origin in
                        actions.onRippleToolGroup(groupID, origin)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.nileReduceMotion, item.reduceMotion)
            )
        }
    }
}
