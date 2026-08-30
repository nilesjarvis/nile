import XCTest
@testable import Nile

final class NileMarkdownTests: XCTestCase {
    func testSettledMarkdownCacheParsesStableContentOnce() {
        let cache = MarkdownBlockCache(countLimit: 4, totalCostLimit: 4_096)
        let content = "# Cached\n\nA **stable** response."

        let first = cache.blocks(for: content, streaming: false)
        let second = cache.blocks(for: content, streaming: false)

        XCTAssertEqual(first, second)
        XCTAssertEqual(cache.parseCount, 1)

        _ = cache.blocks(for: content + " partial", streaming: true)
        _ = cache.blocks(for: content + " partial", streaming: true)
        XCTAssertEqual(cache.parseCount, 3)
    }

    func testCodeHighlightCacheTokenizesStableFenceOnce() {
        let cache = NileCodeHighlightCache(
            countLimit: 2,
            totalCostLimit: 4_096
        )
        let code = "let answer = 42 // stable"

        let first = cache.highlightedCode(code, language: "javascript")
        let second = cache.highlightedCode(code, language: "javascript")

        XCTAssertEqual(first, second)
        XCTAssertEqual(cache.highlightCount, 1)
    }


    func testPipeTableParsesHeaderAndRows() {
        let blocks = parseMarkdownBlocks(
            """
            Flags:

            | flag | value |
            |------|-------|
            | minify | true |
            | shrinkResources | **true** |

            done
            """
        )
        let tables = blocks.compactMap {
            block -> ([MarkdownTableColumn], [[String]])? in
            guard case let .table(columns, rows) = block else {
                return nil
            }
            return (columns, rows)
        }
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(
            tables[0].0,
            [
                MarkdownTableColumn(title: "flag", alignment: .leading),
                MarkdownTableColumn(title: "value", alignment: .leading),
            ]
        )
        XCTAssertEqual(tables[0].1, [
            ["minify", "true"],
            ["shrinkResources", "**true**"],
        ])
        XCTAssertEqual(blocks.last, .paragraph("done"))
    }

    func testPipeTablePreservesAlignmentAndSupportsOptionalOuterPipes() {
        let blocks = parseMarkdownBlocks(
            """
            Area | Status | Checks
            :--- | :---: | ---:
            Gateway | Ready | 18
            Accessibility | Review | 4
            """
        )

        XCTAssertEqual(
            blocks,
            [
                .table(
                    columns: [
                        MarkdownTableColumn(
                            title: "Area",
                            alignment: .leading
                        ),
                        MarkdownTableColumn(
                            title: "Status",
                            alignment: .center
                        ),
                        MarkdownTableColumn(
                            title: "Checks",
                            alignment: .trailing
                        ),
                    ],
                    rows: [
                        ["Gateway", "Ready", "18"],
                        ["Accessibility", "Review", "4"],
                    ]
                ),
            ]
        )
    }

    func testPipeTablePreservesInlineMarkdownAndEscapedPipes() {
        let blocks = parseMarkdownBlocks(
            """
            | command | result |
            | --- | --- |
            | `build \\| test` | **ready** |
            """
        )

        XCTAssertEqual(
            blocks,
            [
                .table(
                    columns: [
                        MarkdownTableColumn(
                            title: "command",
                            alignment: .leading
                        ),
                        MarkdownTableColumn(
                            title: "result",
                            alignment: .leading
                        ),
                    ],
                    rows: [["`build \\| test`", "**ready**"]]
                ),
            ]
        )
    }

    func testTableSeparatorMustMatchHeaderColumnCount() {
        XCTAssertEqual(
            parseMarkdownBlocks(
                """
                | Area | Status |
                | --- |
                | Gateway | Ready |
                """
            ),
            [
                .paragraph(
                    """
                    | Area | Status |
                    | --- |
                    | Gateway | Ready |
                    """
                ),
            ]
        )
    }

    func testStreamingTableWithholdsUnterminatedFinalRow() {
        let partial = parseMarkdownBlocks(
            """
            | Area | Status |
            | --- | --- |
            | Gateway | Rea
            """,
            streaming: true
        )
        let complete = parseMarkdownBlocks(
            """
            | Area | Status |
            | --- | --- |
            | Gateway | Ready |
            """,
            streaming: true
        )

        guard case let .table(_, partialRows) = partial.first,
              case let .table(_, completeRows) = complete.first else {
            return XCTFail("Expected both inputs to parse as tables")
        }
        XCTAssertEqual(partialRows, [])
        XCTAssertEqual(completeRows, [["Gateway", "Ready"]])
    }

    func testTablePresentationAdaptsToWidthAndContentSize() {
        XCTAssertEqual(
            markdownTablePresentation(
                columnCount: 2,
                compactWidth: true,
                accessibilitySize: false
            ),
            .stacked
        )
        XCTAssertEqual(
            markdownTablePresentation(
                columnCount: 2,
                compactWidth: false,
                accessibilitySize: false
            ),
            .grid
        )
        XCTAssertEqual(
            markdownTablePresentation(
                columnCount: 3,
                compactWidth: true,
                accessibilitySize: false
            ),
            .grid
        )
        XCTAssertEqual(
            markdownTablePresentation(
                columnCount: 3,
                compactWidth: false,
                accessibilitySize: true
            ),
            .stacked
        )
    }

    func testTableWithoutSeparatorStaysParagraphText() {
        XCTAssertEqual(
            parseMarkdownBlocks("| flag | value |"),
            [.paragraph("| flag | value |")]
        )
    }

    func testFenceLanguageAndUnclosedContentArePreserved() {
        XCTAssertEqual(
            parseMarkdownBlocks("```kotlin\nval x = 1\n```"),
            [.code(code: "val x = 1", language: "kotlin")]
        )
        XCTAssertEqual(
            parseMarkdownBlocks("```python\nprint(1)"),
            [.code(code: "print(1)", language: "python")]
        )
    }

    func testHeadingsListsQuotesAndRuleProjectInOrder() {
        XCTAssertEqual(
            parseMarkdownBlocks(
                """
                # Heading

                - bullet
                  2. nested
                > note
                ---
                done
                """
            ),
            [
                .heading(level: 1, text: "Heading"),
                .bullet(text: "bullet", indent: 0),
                .numbered(number: 2, text: "nested", indent: 1),
                .quote("note"),
                .rule,
                .paragraph("done"),
            ]
        )
    }

    func testHighlighterColorsKeywordsStringsValuesAndComments() {
        let code = "val name = \"hermes\" + 42 // agent"
        let highlighted = highlightCode(code, language: "kotlin")

        XCTAssertEqual(highlighted.text, code)
        XCTAssertEqual(
            highlighted.spans,
            [
                span(in: code, token: "val", kind: .keyword),
                span(in: code, token: "\"hermes\"", kind: .string),
                span(in: code, token: "42", kind: .value),
                span(
                    in: code,
                    token: "// agent",
                    kind: .comment
                ),
            ]
        )
    }

    func testHighlighterPassesUnknownLanguageThrough() {
        XCTAssertEqual(
            highlightCode("SELECT 1;", language: "sql"),
            NileHighlightedCode(text: "SELECT 1;", spans: [])
        )
    }

    func testCommentMarkerInsideStringIsNotAComment() {
        let code = "s = \"a # b\"  # real comment"
        let highlighted = highlightCode(code, language: "python")
        let realComment = span(
            in: code,
            token: "# real comment",
            kind: .comment
        )

        XCTAssertTrue(highlighted.spans.contains(realComment))
        XCTAssertFalse(
            highlighted.spans.contains {
                $0.kind == .comment && $0.start < realComment.start
            }
        )
    }

    private func span(
        in text: String,
        token: String,
        kind: NileCodeHighlightKind
    ) -> NileCodeHighlightSpan {
        let range = (text as NSString).range(of: token)
        return NileCodeHighlightSpan(
            start: range.location,
            end: NSMaxRange(range),
            kind: kind
        )
    }
}
