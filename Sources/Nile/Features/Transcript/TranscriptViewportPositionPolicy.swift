import CoreGraphics

struct TranscriptViewportGeometry: Equatable, Sendable {
    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let adjustedTopInset: CGFloat
    let adjustedBottomInset: CGFloat

    var minimumOffsetY: CGFloat {
        -adjustedTopInset
    }

    var maximumOffsetY: CGFloat {
        max(
            minimumOffsetY,
            contentHeight - viewportHeight + adjustedBottomInset
        )
    }

    func clampedOffsetY(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumOffsetY), maximumOffsetY)
    }

    func isAtBottom(tolerance: CGFloat = 1) -> Bool {
        contentOffsetY >= maximumOffsetY - tolerance
    }
}

struct TranscriptViewportResizeState: Equatable, Sendable {
    private(set) var preservedOffset: CGFloat?
    private var lastViewportHeight: CGFloat?
    private var lastContentHeight: CGFloat?

    mutating func clearPreservedOffset() {
        preservedOffset = nil
    }

    mutating func settlePreservedOffset(_ offset: CGFloat) {
        preservedOffset = offset
    }

    mutating func observe(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        currentOffset: CGFloat
    ) {
        defer {
            lastViewportHeight = viewportHeight
            lastContentHeight = contentHeight
        }
        guard let lastViewportHeight, let lastContentHeight else {
            return
        }
        if viewportHeight < lastViewportHeight - 1 {
            let contentPreviouslyFit = lastContentHeight
                <= lastViewportHeight + 1
            if preservedOffset != nil || contentPreviouslyFit {
                preservedOffset = currentOffset
            }
        } else if viewportHeight > lastViewportHeight + 1 {
            preservedOffset = nil
        }
    }
}
