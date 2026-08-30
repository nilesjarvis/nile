import CoreGraphics

enum TranscriptViewportSettlementAction: Equatable, Sendable {
    case none
    case pinToBottom
    case setOffset(CGFloat)
    case retryOffset
}

struct TranscriptViewportSettlementState: Sendable {
    private enum PendingPosition: Sendable {
        case bottom
        case offset(CGFloat)
    }

    private(set) var isAnchored = true
    private var automaticTailPinEnabled = true
    private var retainsTopInset = false
    private var retainedTopInset: CGFloat = 0
    private var pendingPosition: PendingPosition?
    private var pendingOffsetSettlementAttempts = 0
    private var preservedDetachedOffset: CGFloat?
    private var resizeState = TranscriptViewportResizeState()
    private var layoutGeneration = 0

    var hasPendingPosition: Bool {
        pendingPosition != nil
    }

    mutating func configure(
        automaticTailPinEnabled: Bool,
        retainsTopInset: Bool,
        currentTopInset: CGFloat
    ) {
        self.automaticTailPinEnabled = automaticTailPinEnabled
        if retainsTopInset, !self.retainsTopInset {
            retainedTopInset = currentTopInset
        }
        self.retainsTopInset = retainsTopInset
    }

    mutating func prepareForOwnerChange() {
        preservedDetachedOffset = nil
        resizeState.clearPreservedOffset()
    }

    mutating func clearOwner() {
        isAnchored = true
        pendingPosition = .offset(0)
        pendingOffsetSettlementAttempts = 0
    }

    mutating func apply(_ presentation: TranscriptScrollPresentation) {
        resizeState.clearPreservedOffset()
        isAnchored = presentation.isAnchored
        preservedDetachedOffset = presentation.contentOffsetY
        pendingPosition = presentation.isAnchored
            ? .bottom
            : presentation.contentOffsetY.map(PendingPosition.offset)
        pendingOffsetSettlementAttempts = 0
    }

    mutating func applyContentChange(
        _ presentation: TranscriptScrollPresentation,
        currentOffset: CGFloat
    ) {
        resizeState.clearPreservedOffset()
        isAnchored = presentation.isAnchored
        if presentation.isAnchored {
            preservedDetachedOffset = nil
            pendingPosition = .bottom
        } else {
            let offset = preservedDetachedOffset
                ?? presentation.contentOffsetY
                ?? currentOffset
            preservedDetachedOffset = offset
            pendingPosition = .offset(offset)
        }
        pendingOffsetSettlementAttempts = 0
    }

    mutating func clearResizePreservedOffset() {
        resizeState.clearPreservedOffset()
    }

    mutating func observeResize(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        currentOffset: CGFloat
    ) {
        resizeState.observe(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            currentOffset: currentOffset
        )
    }

    mutating func nextAction(
        geometry: TranscriptViewportGeometry
    ) -> TranscriptViewportSettlementAction {
        if let pendingPosition {
            switch pendingPosition {
            case .bottom:
                self.pendingPosition = nil
                return automaticTailPinEnabled ? .pinToBottom : .none
            case let .offset(offset):
                if offset > geometry.maximumOffsetY + 1,
                   pendingOffsetSettlementAttempts < 12 {
                    pendingOffsetSettlementAttempts &+= 1
                    return .retryOffset
                }
                self.pendingPosition = nil
                return .setOffset(geometry.clampedOffsetY(offset))
            }
        }
        if let preservedOffset = resizeState.preservedOffset {
            let offset = geometry.clampedOffsetY(preservedOffset)
            resizeState.settlePreservedOffset(offset)
            return .setOffset(offset)
        }
        if isAnchored, automaticTailPinEnabled {
            return .pinToBottom
        }
        if !isAnchored, let preservedDetachedOffset {
            return .setOffset(
                geometry.clampedOffsetY(preservedDetachedOffset)
            )
        }
        return .none
    }

    mutating func recordUserPosition(
        isAnchored: Bool,
        contentOffsetY: CGFloat
    ) {
        self.isAnchored = isAnchored
        preservedDetachedOffset = isAnchored ? nil : contentOffsetY
    }

    mutating func nextLayoutGeneration() -> Int {
        layoutGeneration &+= 1
        return layoutGeneration
    }

    func isCurrentLayoutGeneration(_ generation: Int) -> Bool {
        generation == layoutGeneration
    }

    mutating func desiredTopInset(
        bottomAligned: Bool,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        if !bottomAligned {
            retainedTopInset = 0
            return 0
        }
        if retainsTopInset {
            return retainedTopInset
        }
        let nextInset = max(0, viewportHeight - contentHeight)
        retainedTopInset = nextInset
        return nextInset
    }
}
