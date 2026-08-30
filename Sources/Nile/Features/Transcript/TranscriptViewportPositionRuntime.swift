import UIKit

/// Owns UIKit transcript position, anchor, and inset settlement while the
/// viewport controller coordinates row content and accessibility projection.
@MainActor
final class TranscriptViewportPositionRuntime: NSObject,
    UICollectionViewDelegate {
    let collectionView: TranscriptLayoutObservingCollectionView

    private weak var rootView: UIView?
    private weak var scrollState: TranscriptScrollCoordinator?
    private var usesBottomAlignment: @MainActor () -> Bool = { false }
    private var owner: TranscriptScrollOwner?
    private var settlementState = TranscriptViewportSettlementState()
    private var userInteractionActive = false
    private var applyingPosition = false
    private var configuredJumpRevision: Int?
    private var lastPublishedAnchor: Bool?
    private var onAnchoredChange: ((Bool) -> Void)?
    private var onAnchorTransition: ((
        TranscriptScrollAnchorTransition
    ) -> Void)?

    override init() {
        collectionView = TranscriptViewportCollectionLayout.makeCollectionView()
        super.init()
    }

    func install(in rootView: UIView) {
        self.rootView = rootView
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = NileAccessibilityID.transcript
        collectionView.install(in: rootView)
    }

    func observeLayout(
        usesBottomAlignment: @escaping @MainActor () -> Bool
    ) {
        self.usesBottomAlignment = usesBottomAlignment
        collectionView.onLayout = { [weak self] in
            self?.settleAfterLayout()
        }
    }

    func ownerChanges(to nextOwner: TranscriptScrollOwner?) -> Bool {
        owner != nextOwner
    }

    func update(
        rowsChanged: Bool,
        owner nextOwner: TranscriptScrollOwner?,
        scrollState: TranscriptScrollCoordinator,
        lastUserEntryID: String?,
        jumpToBottomRevision: Int,
        automaticTailPinEnabled: Bool,
        retainsTopInset: Bool,
        onAnchoredChange: @escaping (Bool) -> Void,
        onAnchorTransition: @escaping (
            TranscriptScrollAnchorTransition
        ) -> Void
    ) {
        let ownerChanged = owner != nextOwner
        self.scrollState = scrollState
        settlementState.configure(
            automaticTailPinEnabled: automaticTailPinEnabled,
            retainsTopInset: retainsTopInset,
            currentTopInset: collectionView.contentInset.top
        )
        self.onAnchoredChange = onAnchoredChange
        self.onAnchorTransition = onAnchorTransition

        if ownerChanged {
            owner = nextOwner
            userInteractionActive = false
            settlementState.prepareForOwnerChange()
            if let nextOwner {
                apply(
                    scrollState.activate(
                        owner: nextOwner,
                        lastUserEntryID: lastUserEntryID
                    )
                )
            } else {
                settlementState.clearOwner()
            }
        } else if rowsChanged, let nextOwner {
            applyContentChange(
                scrollState.contentChanged(
                    owner: nextOwner,
                    lastUserEntryID: lastUserEntryID
                )
            )
        }

        if let configuredJumpRevision,
           configuredJumpRevision != jumpToBottomRevision,
           let nextOwner {
            settlementState.clearResizePreservedOffset()
            apply(scrollState.jumpToBottom(owner: nextOwner))
        }
        configuredJumpRevision = jumpToBottomRevision
        publishAnchorIfNeeded()
        scheduleLayoutSettlement()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userInteractionActive = true
        settlementState.clearResizePreservedOffset()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        recordUserPosition()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard userInteractionActive, !applyingPosition else {
            return
        }
        recordUserPosition()
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        recordUserPosition()
        if !decelerate {
            userInteractionActive = false
            settleAfterLayout()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        recordUserPosition()
        userInteractionActive = false
        settleAfterLayout()
    }

    private func apply(_ presentation: TranscriptScrollPresentation) {
        settlementState.apply(presentation)
    }

    private func applyContentChange(
        _ presentation: TranscriptScrollPresentation
    ) {
        settlementState.applyContentChange(
            presentation,
            currentOffset: collectionView.contentOffset.y
        )
    }

    private func scheduleLayoutSettlement() {
        let generation = settlementState.nextLayoutGeneration()
        rootView?.setNeedsLayout()
        collectionView.setNeedsLayout()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.settlementState.isCurrentLayoutGeneration(generation)
            else {
                return
            }
            self.rootView?.layoutIfNeeded()
            self.settleAfterLayout()
        }
    }

    private func settleAfterLayout() {
        guard !applyingPosition,
              collectionView.bounds.height > 0,
              collectionView.bounds.width > 0,
              !userInteractionActive else {
            return
        }
        settlementState.observeResize(
            viewportHeight: collectionView.bounds.height,
            contentHeight: collectionView.contentSize.height,
            currentOffset: collectionView.contentOffset.y
        )
        updateContentTopInset()
        switch settlementState.nextAction(geometry: viewportGeometry) {
        case .none:
            return
        case .pinToBottom:
            pinToBottom()
        case let .setOffset(offset):
            setContentOffsetY(offset)
        case .retryOffset:
            schedulePendingOffsetSettlement()
        }
    }

    private func pinToBottom() {
        let offset = viewportGeometry.maximumOffsetY
        setContentOffsetY(offset)
        if let owner {
            scrollState?.recordProgrammaticPosition(
                owner: owner,
                contentOffsetY: offset
            )
        }
    }

    private func setContentOffsetY(_ offset: CGFloat) {
        guard abs(collectionView.contentOffset.y - offset) > 0.25 else {
            return
        }
        applyingPosition = true
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: offset),
            animated: false
        )
        applyingPosition = false
    }

    private func recordUserPosition() {
        guard let owner, let scrollState else {
            return
        }
        let transition = scrollState.recordUserScroll(
            owner: owner,
            contentOffsetY: collectionView.contentOffset.y,
            isBottomVisible: viewportGeometry.isAtBottom()
        )
        settlementState.recordUserPosition(
            isAnchored: scrollState.isAnchored(owner: owner),
            contentOffsetY: collectionView.contentOffset.y
        )
        publishAnchorIfNeeded()
        if let transition {
            onAnchorTransition?(transition)
        }
    }

    private func publishAnchorIfNeeded() {
        guard lastPublishedAnchor != settlementState.isAnchored else {
            return
        }
        lastPublishedAnchor = settlementState.isAnchored
        let value = settlementState.isAnchored
        DispatchQueue.main.async { [weak self] in
            self?.onAnchoredChange?(value)
        }
    }

    private var viewportGeometry: TranscriptViewportGeometry {
        TranscriptViewportGeometry(
            contentOffsetY: collectionView.contentOffset.y,
            contentHeight: collectionView.contentSize.height,
            viewportHeight: collectionView.bounds.height,
            adjustedTopInset: collectionView.adjustedContentInset.top,
            adjustedBottomInset: collectionView.adjustedContentInset.bottom
        )
    }

    private func schedulePendingOffsetSettlement() {
        collectionView.setNeedsLayout()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0 / 60.0
        ) { [weak self] in
            guard let self, self.settlementState.hasPendingPosition else {
                return
            }
            self.collectionView.layoutIfNeeded()
            self.settleAfterLayout()
        }
    }

    private func updateContentTopInset() {
        let nextInset = settlementState.desiredTopInset(
            bottomAligned: usesBottomAlignment(),
            viewportHeight: collectionView.bounds.height,
            contentHeight: collectionView.contentSize.height
        )
        guard abs(collectionView.contentInset.top - nextInset) > 0.25 else {
            return
        }
        var inset = collectionView.contentInset
        inset.top = nextInset
        collectionView.contentInset = inset
        collectionView.scrollIndicatorInsets = inset
    }
}
