import os
import UIKit

@MainActor
final class TranscriptViewportController: UIViewController {
    private static let signposter = OSSignposter(
        subsystem: "com.niles.Nile",
        category: "Transcript"
    )

    private let positionRuntime = TranscriptViewportPositionRuntime()
    private let rowHost = TranscriptViewportRowHost()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        positionRuntime.install(in: view)
        rowHost.install(
            collectionView: positionRuntime.collectionView,
            parent: self
        )
        positionRuntime.observeLayout { [weak rowHost] in
            rowHost?.usesBottomAlignment ?? false
        }
    }

    func update(
        items: [TranscriptViewportItem],
        actions: TranscriptViewportActions,
        owner nextOwner: TranscriptScrollOwner?,
        scrollState: TranscriptScrollCoordinator,
        lastUserEntryID: String?,
        jumpToBottomRevision: Int,
        automaticTailPinEnabled: Bool,
        retainsTopInset: Bool,
        interactionEnabled: Bool,
        accessibilityHidden: Bool,
        onAnchoredChange: @escaping (Bool) -> Void,
        onAnchorTransition: @escaping (
            TranscriptScrollAnchorTransition
        ) -> Void
    ) {
        let signpostState = Self.signposter.beginInterval(
            "Transcript viewport update"
        )
        defer {
            Self.signposter.endInterval(
                "Transcript viewport update",
                signpostState,
                "rows=\(items.count)"
            )
        }
        loadViewIfNeeded()
        let ownerChanged = positionRuntime.ownerChanges(to: nextOwner)
        updateViewportAccessibility(
            interactionEnabled: interactionEnabled,
            accessibilityHidden: accessibilityHidden
        )
        let rowsChanged = rowHost.update(
            items: items,
            actions: actions,
            resetHostedRows: ownerChanged
        )
        positionRuntime.update(
            rowsChanged: rowsChanged,
            owner: nextOwner,
            scrollState: scrollState,
            lastUserEntryID: lastUserEntryID,
            jumpToBottomRevision: jumpToBottomRevision,
            automaticTailPinEnabled: automaticTailPinEnabled,
            retainsTopInset: retainsTopInset,
            onAnchoredChange: onAnchoredChange,
            onAnchorTransition: onAnchorTransition
        )
    }

    private func updateViewportAccessibility(
        interactionEnabled: Bool,
        accessibilityHidden: Bool
    ) {
        view.isUserInteractionEnabled = interactionEnabled
        positionRuntime.collectionView.isUserInteractionEnabled =
            interactionEnabled
        view.accessibilityElementsHidden = accessibilityHidden
        positionRuntime.collectionView.accessibilityElementsHidden =
            accessibilityHidden
        rowHost.setAccessibilityHidden(accessibilityHidden)
    }
}
