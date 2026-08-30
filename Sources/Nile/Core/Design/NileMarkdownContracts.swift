enum MarkdownTableAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

struct MarkdownTableColumn: Equatable, Sendable {
    let title: String
    let alignment: MarkdownTableAlignment
}

enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(code: String, language: String?)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String, indent: Int)
    case quote(String)
    case table(columns: [MarkdownTableColumn], rows: [[String]])
    case rule
}
