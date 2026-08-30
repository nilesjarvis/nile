import SwiftUI
import UIKit

struct NileMarkdownText: View {
    let content: String
    var baseColor = NileColors.prose
    var strongColor = NileColors.proseStrong
    var isStreaming = false

    private var blocks: [MarkdownBlock] {
        MarkdownBlockCache.shared.blocks(
            for: content,
            streaming: isStreaming
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(
                    block: block,
                    baseColor: baseColor,
                    strongColor: strongColor
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(NileColors.link)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let baseColor: Color
    let strongColor: Color

    var body: some View {
        switch block {
        case let .paragraph(text):
            markdownText(
                text,
                style: NileTypography.bodyMediumStyle,
                color: baseColor
            )
        case let .heading(level, text):
            markdownText(
                text,
                style:
                    level == 1
                    ? NileTypography.markdownHeadingLargeStyle
                    : level == 2
                        ? NileTypography.markdownHeadingMediumStyle
                        : NileTypography.markdownHeadingSmallStyle,
                color: NileColors.text
            )
        case let .code(code, language):
            MarkdownCodeBlock(code: code, language: language)
        case let .bullet(text, indent):
            MarkdownListRow(
                prefix: "•",
                text: text,
                indent: indent,
                baseColor: baseColor,
                strongColor: strongColor
            )
        case let .numbered(number, text, indent):
            MarkdownListRow(
                prefix: "\(number).",
                text: text,
                indent: indent,
                baseColor: baseColor,
                strongColor: strongColor
            )
        case let .quote(text):
            HStack(alignment: .top, spacing: 6) {
                Text("▏")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(NileColors.border)
                inlineText(text, color: NileColors.muted)
                    .modifier(
                        MarkdownTextStyleModifier(
                            style: NileTypography.bodyMediumStyle,
                            italic: true
                        )
                    )
            }
        case let .table(columns, rows):
            MarkdownTable(
                columns: columns,
                rows: rows,
                strongColor: strongColor
            )
        case .rule:
            Rectangle()
                .fill(NileColors.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func inlineText(
        _ text: String,
        color: Color
    ) -> some View {
        if let attributed = styledInline(text) {
            Text(attributed)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func markdownText(
        _ text: String,
        style: NileTypography.TextStyle,
        color: Color
    ) -> some View {
        if containsInlineMarkdown(text) {
            inlineText(text, color: color)
                .modifier(MarkdownTextStyleModifier(style: style))
        } else {
            NileMeasuredComposeText(
                text: text,
                style: style,
                color: UIColor(color),
                backgroundColor: UIColor(NileColors.background),
                fillsWidth: true
            )
        }
    }

    private func containsInlineMarkdown(_ text: String) -> Bool {
        text.range(
            of: #"[*_`\[\]~]"#,
            options: .regularExpression
        ) != nil
    }

    private func styledInline(_ text: String) -> AttributedString? {
        styledInlineMarkdown(text, strongColor: strongColor)
    }
}

private struct MarkdownCodeBlock: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NileColors.muted)
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(NileColors.muted)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied" : "Copy",
                        systemImage: copied ? "checkmark" : "square.on.square"
                    )
                    .font(NileTypography.labelMedium.weight(.medium))
                    .foregroundStyle(NileColors.muted)
                    .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            Rectangle().fill(NileColors.border).frame(height: 1)
            ScrollView(.horizontal) {
                Text(
                    attributedHighlightedCode(
                        code,
                        language: language
                    )
                )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NileColors.text)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nilePanel()
        .accessibilityHint(language.map { "\($0) code" } ?? "Code")
    }
}
