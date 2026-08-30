import SwiftUI
import UIKit

struct MarkdownListRow: View {
    let prefix: String
    let text: String
    let indent: Int
    let baseColor: Color
    let strongColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NileMeasuredComposeText(
                text: prefix,
                style: NileTypography.bodyMediumStyle,
                color: UIColor(NileColors.muted),
                backgroundColor: UIColor(NileColors.background)
            )
            if text.range(
                of: #"[*_`\[\]~]"#,
                options: .regularExpression
            ) != nil,
               let attributed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .modifier(
                        MarkdownTextStyleModifier(
                            style: NileTypography.bodyMediumStyle
                        )
                    )
                    .foregroundStyle(baseColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NileMeasuredComposeText(
                    text: text,
                    style: NileTypography.bodyMediumStyle,
                    color: UIColor(baseColor),
                    backgroundColor: UIColor(NileColors.background),
                    fillsWidth: true
                )
            }
        }
        .padding(.leading, CGFloat(indent * 16))
    }
}

struct MarkdownTextStyleModifier: ViewModifier {
    let style: NileTypography.TextStyle
    var italic = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let font = Font(style.scaledUIFont(for: dynamicTypeSize))
        content
            .font(italic ? font.italic() : font)
            .tracking(style.renderedTracking)
            .lineSpacing(style.additionalLineSpacing)
    }
}

func styledInlineMarkdown(
    _ text: String,
    strongColor: Color
) -> AttributedString? {
    guard var attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
        return nil
    }
    let strongRanges = attributed.runs.compactMap { run in
        run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            ? run.range
            : nil
    }
    for range in strongRanges {
        attributed[range].foregroundColor = strongColor
    }
    return attributed
}
