import SwiftUI

enum MarkdownTablePresentation: Equatable {
    case grid
    case stacked
}

func markdownTablePresentation(
    columnCount: Int,
    compactWidth: Bool,
    accessibilitySize: Bool
) -> MarkdownTablePresentation {
    if accessibilitySize || compactWidth && columnCount == 2 {
        return .stacked
    }
    return .grid
}

struct MarkdownTable: View {
    let columns: [MarkdownTableColumn]
    let rows: [[String]]
    let strongColor: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var presentation: MarkdownTablePresentation {
        markdownTablePresentation(
            columnCount: columns.count,
            compactWidth: horizontalSizeClass == .compact,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    var body: some View {
        Group {
            switch presentation {
            case .grid:
                grid
            case .stacked:
                stackedRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NileColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: NileRadii.small))
        .overlay {
            RoundedRectangle(cornerRadius: NileRadii.small)
                .stroke(NileColors.border.opacity(0.55), lineWidth: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Table, \(rows.count) rows, \(columns.count) columns"
        )
        .accessibilityIdentifier(NileAccessibilityID.markdownTable)
    }

    private var grid: some View {
        let widths = preferredColumnWidths
        return ScrollView(.horizontal) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 0,
                verticalSpacing: 0
            ) {
                GridRow(alignment: .top) {
                    ForEach(columns.indices, id: \.self) { column in
                        MarkdownTableCell(
                            text: columns[column].title,
                            strongColor: strongColor,
                            font: NileTypography.bodySmall.weight(.semibold),
                            color: NileColors.text,
                            alignment: columns[column].alignment,
                            width: widths[column],
                            accessibilityLabel: columns[column].title,
                            accessibilityIdentifier:
                                NileAccessibilityID.markdownTableHeader(column)
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(NileColors.panelAlt)
                        .accessibilityAddTraits(.isHeader)
                    }
                }

                Divider()
                    .gridCellColumns(columns.count)
                    .accessibilityHidden(true)

                ForEach(Array(rows.enumerated()), id: \.offset) {
                    rowIndex,
                    row in
                    GridRow(alignment: .top) {
                        ForEach(columns.indices, id: \.self) { column in
                            MarkdownTableCell(
                                text: row.indices.contains(column)
                                    ? row[column]
                                    : "",
                                strongColor: strongColor,
                                font: NileTypography.bodyMedium,
                                color: NileColors.prose,
                                alignment: columns[column].alignment,
                                width: widths[column],
                                accessibilityLabel:
                                    "\(plainInlineMarkdown(columns[column].title)): \(plainInlineMarkdown(row.indices.contains(column) ? row[column] : ""))",
                                accessibilityIdentifier:
                                    NileAccessibilityID.markdownTableCell(
                                        row: rowIndex,
                                        column: column
                                    )
                            )
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(
                                rowIndex.isMultiple(of: 2)
                                    ? Color.clear
                                    : NileColors.panelAlt.opacity(0.42)
                            )
                        }
                    }

                    if rowIndex < rows.count - 1 {
                        Divider()
                            .gridCellColumns(columns.count)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .accessibilityHint("Swipe horizontally to review additional columns.")
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) {
                rowIndex,
                row in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(columns.indices, id: \.self) { column in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                styledInlineMarkdown(
                                    columns[column].title,
                                    strongColor: strongColor
                                ) ?? AttributedString(columns[column].title)
                            )
                            .font(NileTypography.bodySmall.weight(.semibold))
                            .foregroundStyle(NileColors.muted)
                            .accessibilityAddTraits(.isHeader)

                            MarkdownTableCell(
                                text: row.indices.contains(column)
                                    ? row[column]
                                    : "",
                                strongColor: strongColor,
                                font: NileTypography.bodyMedium,
                                color: NileColors.prose,
                                alignment: .leading,
                                width: nil,
                                accessibilityLabel:
                                    "\(plainInlineMarkdown(columns[column].title)): \(plainInlineMarkdown(row.indices.contains(column) ? row[column] : ""))",
                                accessibilityIdentifier:
                                    NileAccessibilityID.markdownTableCell(
                                        row: rowIndex,
                                        column: column
                                    )
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    rowIndex.isMultiple(of: 2)
                        ? Color.clear
                        : NileColors.panelAlt.opacity(0.42)
                )

                if rowIndex < rows.count - 1 {
                    Divider()
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var preferredColumnWidths: [CGFloat] {
        let minimumWidth: CGFloat = columns.count >= 3 ? 72 : 96
        let maximumWidth: CGFloat = columns.count >= 3 ? 144 : 184
        return columns.indices.map { column in
            let values = [columns[column].title] + rows.map {
                $0.indices.contains(column) ? $0[column] : ""
            }
            let longest = values.map {
                plainInlineMarkdown($0).count
            }.max() ?? 0
            return min(
                maximumWidth,
                max(minimumWidth, CGFloat(longest) * 6.5 + 28)
            )
        }
    }
}

private struct MarkdownTableCell: View {
    let text: String
    let strongColor: Color
    let font: Font
    let color: Color
    let alignment: MarkdownTableAlignment
    let width: CGFloat?
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    var body: some View {
        Text(
            styledInlineMarkdown(
                text,
                strongColor: strongColor
            ) ?? AttributedString(text)
        )
        .font(font)
        .foregroundStyle(color)
        .multilineTextAlignment(alignment.textAlignment)
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            width: width.map { max(1, $0 - 24) },
            alignment: alignment.frameAlignment
        )
        .frame(
            maxWidth: width == nil ? .infinity : nil,
            alignment: alignment.frameAlignment
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension MarkdownTableAlignment {
    var frameAlignment: Alignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }
}

private func plainInlineMarkdown(_ text: String) -> String {
    guard let attributed = try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
        return text
    }
    return String(attributed.characters)
}
