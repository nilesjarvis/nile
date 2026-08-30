import Foundation

func parseMarkdownBlocks(
    _ content: String,
    streaming: Bool = false
) -> [MarkdownBlock] {
    let lines = content.components(separatedBy: "\n")
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var index = 0

    func flushParagraph() {
        guard !paragraph.isEmpty else {
            return
        }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph.removeAll(keepingCapacity: true)
    }

    while index < lines.count {
        let line = lines[index]
        let fence = line.drop(while: { $0 == " " || $0 == "\t" })
        if fence.hasPrefix("```") {
            flushParagraph()
            let language = String(fence.dropFirst(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .nonBlankMarkdown
            var codeLines: [String] = []
            index += 1
            while index < lines.count {
                let candidate = lines[index].drop(
                    while: { $0 == " " || $0 == "\t" }
                )
                if candidate.hasPrefix("```") {
                    break
                }
                codeLines.append(lines[index])
                index += 1
            }
            blocks.append(
                .code(code: codeLines.joined(separator: "\n"), language: language)
            )
        } else if line.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            flushParagraph()
        } else if let header = markdownTableCells(line),
                  index + 1 < lines.count,
                  let alignments = markdownTableAlignments(lines[index + 1]),
                  header.count == alignments.count,
                  !streaming
                    || index + 1 < lines.count - 1
                    || content.hasSuffix("\n")
                    || hasUnescapedTrailingPipe(lines[index + 1]) {
            flushParagraph()
            let columns = zip(header, alignments).map {
                MarkdownTableColumn(title: $0.0, alignment: $0.1)
            }
            var rows: [[String]] = []
            var nextIndex = index + 2
            while nextIndex < lines.count {
                let rowLine = lines[nextIndex]
                let isUnterminatedStreamingTail =
                    streaming
                    && nextIndex == lines.count - 1
                    && !content.hasSuffix("\n")
                    && !hasUnescapedTrailingPipe(rowLine)
                if isUnterminatedStreamingTail {
                    nextIndex += 1
                    break
                }
                guard let cells = markdownTableCells(rowLine) else {
                    break
                }
                rows.append(
                    columns.indices.map {
                        cells.indices.contains($0) ? cells[$0] : ""
                    }
                )
                nextIndex += 1
            }
            index = nextIndex - 1
            blocks.append(.table(columns: columns, rows: rows))
        } else if let captures = markdownCaptures(
            #"^(#{1,6})\s+(.*)"#,
            in: line
        ) {
            flushParagraph()
            blocks.append(
                .heading(
                    level: captures[0].count,
                    text: captures[1]
                )
            )
        } else if line.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).range(
            of: #"^(?:-{3,}|\*{3,}|_{3,})$"#,
            options: .regularExpression
        ) != nil {
            flushParagraph()
            blocks.append(.rule)
        } else if let captures = markdownCaptures(
            #"^>\s?(.*)"#,
            in: line
        ) {
            flushParagraph()
            blocks.append(.quote(captures[0]))
        } else if let captures = markdownCaptures(
            #"^(\s*)(\d+)\.\s+(.*)"#,
            in: line
        ) {
            flushParagraph()
            blocks.append(
                .numbered(
                    number: Int(captures[1]) ?? 1,
                    text: captures[2],
                    indent: captures[0].count / 2
                )
            )
        } else if let captures = markdownCaptures(
            #"^(\s*)[-*+]\s+(.*)"#,
            in: line
        ) {
            flushParagraph()
            blocks.append(
                .bullet(
                    text: captures[1],
                    indent: captures[0].count / 2
                )
            )
        } else {
            paragraph.append(line)
        }
        index += 1
    }
    flushParagraph()
    return blocks
}

private func markdownTableAlignments(
    _ line: String
) -> [MarkdownTableAlignment]? {
    guard let cells = markdownTableCells(line), !cells.isEmpty else {
        return nil
    }
    var alignments: [MarkdownTableAlignment] = []
    for cell in cells {
        let marker = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard marker.range(
            of: #"^:?-{2,}:?$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        if marker.hasPrefix(":") && marker.hasSuffix(":") {
            alignments.append(.center)
        } else if marker.hasSuffix(":") {
            alignments.append(.trailing)
        } else {
            alignments.append(.leading)
        }
    }
    return alignments
}

private func markdownTableCells(_ line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    var cells: [String] = []
    var current = ""
    var escaped = false
    var foundDelimiter = false
    for character in trimmed {
        if escaped {
            current.append("\\")
            current.append(character)
            escaped = false
        } else if character == "\\" {
            escaped = true
        } else if character == "|" {
            foundDelimiter = true
            cells.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    if escaped {
        current.append("\\")
    }
    cells.append(current)

    guard foundDelimiter else {
        return nil
    }
    if trimmed.hasPrefix("|"), !cells.isEmpty {
        cells.removeFirst()
    }
    if hasUnescapedTrailingPipe(trimmed), !cells.isEmpty {
        cells.removeLast()
    }
    guard !cells.isEmpty else {
        return nil
    }
    return cells.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func hasUnescapedTrailingPipe(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.last == "|" else {
        return false
    }
    var slashCount = 0
    var index = trimmed.index(before: trimmed.endIndex)
    while index > trimmed.startIndex {
        let previous = trimmed.index(before: index)
        guard trimmed[previous] == "\\" else {
            break
        }
        slashCount += 1
        index = previous
    }
    return slashCount.isMultiple(of: 2)
}

private func markdownCaptures(
    _ pattern: String,
    in line: String
) -> [String]? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
              in: line,
              range: NSRange(line.startIndex..., in: line)
          ) else {
        return nil
    }
    return (1..<match.numberOfRanges).compactMap { index in
        guard let range = Range(match.range(at: index), in: line) else {
            return nil
        }
        return String(line[range])
    }
}

private extension String {
    var nonBlankMarkdown: String? {
        isEmpty ? nil : self
    }
}
