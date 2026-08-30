import SwiftUI
import UIKit

struct NileComposeText: UIViewRepresentable {
    let text: String
    let style: NileTypography.TextStyle
    let color: UIColor
    let backgroundColor: UIColor
    var fillsWidth = false
    var alignment: NSTextAlignment = .natural

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.lineBreakStrategy = []
        label.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.setContentCompressionResistancePriority(
            fillsWidth ? .defaultLow : .required,
            for: .horizontal
        )
        label.setContentHuggingPriority(
            fillsWidth ? .defaultLow : .defaultHigh,
            for: .horizontal
        )
        let font = style.scaledUIFont(for: dynamicTypeSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        // Compose greedily fills each line. UIKit's standard label strategy
        // includes push-out, which moves a fitting word to avoid an orphan.
        paragraph.lineBreakStrategy = []
        paragraph.lineSpacing = 0
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .kern: 0,
                .paragraphStyle: paragraph,
            ]
        )
        label.accessibilityLabel = text
        label.isAccessibilityElement = true
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UILabel,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let measured = uiView.sizeThatFits(
            CGSize(
                width: width,
                height: UIView.layoutFittingExpandedSize.height
            )
        )
        return CGSize(
            width: fillsWidth
                ? proposal.width ?? measured.width
                : min(proposal.width ?? measured.width, measured.width),
            height: measured.height
        )
    }
}

struct NileMeasuredComposeText: View {
    let text: String
    let style: NileTypography.TextStyle
    let color: UIColor
    let backgroundColor: UIColor
    var fillsWidth = false
    var alignment: NSTextAlignment = .natural

    var body: some View {
        NileComposeText(
            text: text,
            style: style,
            color: color,
            backgroundColor: backgroundColor,
            fillsWidth: fillsWidth,
            alignment: alignment
        )
    }
}
