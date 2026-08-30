import Foundation
import SwiftUI

enum NileCodeHighlightKind: Equatable, Sendable {
    case keyword
    case string
    case value
    case comment
}

struct NileCodeHighlightSpan: Equatable, Sendable {
    let start: Int
    let end: Int
    let kind: NileCodeHighlightKind
}

struct NileHighlightedCode: Equatable, Sendable {
    let text: String
    let spans: [NileCodeHighlightSpan]
}

private final class NileHighlightedCodeBox: NSObject {
    let value: NileHighlightedCode

    init(_ value: NileHighlightedCode) {
        self.value = value
    }
}

final class NileCodeHighlightCache: @unchecked Sendable {
    static let shared = NileCodeHighlightCache()

    private let cache = NSCache<NSString, NileHighlightedCodeBox>()
    private let lock = NSLock()
    private var unlockedHighlightCount = 0

    init(countLimit: Int = 64, totalCostLimit: Int = 2 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    var highlightCount: Int {
        lock.withLock { unlockedHighlightCount }
    }

    func highlightedCode(
        _ code: String,
        language: String?
    ) -> NileHighlightedCode {
        let key = "\(language ?? "")\u{0}\(code)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        let value = highlightCode(code, language: language)
        lock.withLock { unlockedHighlightCount &+= 1 }
        cache.setObject(
            NileHighlightedCodeBox(value),
            forKey: key,
            cost: code.utf8.count + value.spans.count * 24
        )
        return value
    }
}

private let nileCodeKeywordsByLanguage: [String: Set<String>] = {
    let kotlin: Set<String> = [
        "val", "var", "fun", "if", "else", "when", "for", "while",
        "return", "class", "object", "interface", "data", "sealed",
        "null", "true", "false", "private", "internal", "public",
        "override", "import", "package", "suspend", "try", "catch",
        "finally", "throw", "is", "in",
    ]
    let java: Set<String> = [
        "public", "private", "protected", "static", "final", "void",
        "int", "long", "boolean", "class", "interface", "extends",
        "implements", "new", "return", "if", "else", "for", "while",
        "try", "catch", "finally", "throw", "throws", "import",
        "package", "null", "true", "false",
    ]
    let python: Set<String> = [
        "def", "return", "if", "elif", "else", "for", "while", "import",
        "from", "class", "try", "except", "finally", "with", "as",
        "lambda", "None", "True", "False", "and", "or", "not", "in",
        "is", "raise", "pass", "yield", "async", "await",
    ]
    let javascript: Set<String> = [
        "const", "let", "var", "function", "return", "if", "else",
        "for", "while", "class", "import", "export", "from", "null",
        "undefined", "true", "false", "new", "try", "catch", "finally",
        "throw", "await", "async", "typeof", "in", "of", "this",
    ]
    let shell: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done",
        "while", "case", "esac", "function", "echo", "export", "local",
        "return", "exit",
    ]
    return [
        "kotlin": kotlin,
        "kt": kotlin,
        "java": java,
        "python": python,
        "py": python,
        "javascript": javascript,
        "js": javascript,
        "typescript": javascript,
        "ts": javascript,
        "jsx": javascript,
        "tsx": javascript,
        "bash": shell,
        "sh": shell,
        "shell": shell,
        "zsh": shell,
        "json": ["true", "false", "null"],
    ]
}()

private let nileCodeCommentPrefixByLanguage: [String: String] = [
    "kotlin": "//",
    "kt": "//",
    "java": "//",
    "javascript": "//",
    "js": "//",
    "typescript": "//",
    "ts": "//",
    "jsx": "//",
    "tsx": "//",
    "python": "#",
    "py": "#",
    "bash": "#",
    "sh": "#",
    "shell": "#",
    "zsh": "#",
]

private let nileCodeTokenExpression = try! NSRegularExpression(
    pattern:
        #""(?:\\.|[^"\\])*"?|'(?:\\.|[^'\\])*'?|[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?"#
)

func highlightCode(
    _ code: String,
    language: String?
) -> NileHighlightedCode {
    guard let language,
          let keywords = nileCodeKeywordsByLanguage[language] else {
        return NileHighlightedCode(text: code, spans: [])
    }
    let commentPrefix = nileCodeCommentPrefixByLanguage[language]
    var spans: [NileCodeHighlightSpan] = []
    var lineOffset = 0

    for (lineIndex, line) in code.components(separatedBy: "\n").enumerated() {
        if lineIndex > 0 {
            lineOffset += 1
        }
        let lineNSString = line as NSString
        let commentStart = commentPrefix.flatMap {
            nileCommentStart(in: lineNSString, marker: $0)
        }
        let codeLength = commentStart ?? lineNSString.length
        nileCodeTokenExpression.enumerateMatches(
            in: line,
            range: NSRange(location: 0, length: codeLength)
        ) { match, _, _ in
            guard let range = match?.range,
                  range.location != NSNotFound else {
                return
            }
            let token = lineNSString.substring(with: range)
            let kind: NileCodeHighlightKind?
            if token.hasPrefix("\"") || token.hasPrefix("'") {
                kind = .string
            } else if token.unicodeScalars.first.map(
                { CharacterSet.decimalDigits.contains($0) }
            ) == true {
                kind = .value
            } else if keywords.contains(token) {
                kind = .keyword
            } else {
                kind = nil
            }
            if let kind {
                spans.append(
                    NileCodeHighlightSpan(
                        start: lineOffset + range.location,
                        end: lineOffset + NSMaxRange(range),
                        kind: kind
                    )
                )
            }
        }
        if let commentStart {
            spans.append(
                NileCodeHighlightSpan(
                    start: lineOffset + commentStart,
                    end: lineOffset + lineNSString.length,
                    kind: .comment
                )
            )
        }
        lineOffset += lineNSString.length
    }
    return NileHighlightedCode(text: code, spans: spans)
}

func attributedHighlightedCode(
    _ code: String,
    language: String?
) -> AttributedString {
    let highlighted = NileCodeHighlightCache.shared.highlightedCode(
        code,
        language: language
    )
    var attributed = AttributedString(highlighted.text)
    for span in highlighted.spans {
        let nsRange = NSRange(
            location: span.start,
            length: span.end - span.start
        )
        guard let stringRange = Range(nsRange, in: highlighted.text),
              let lower = AttributedString.Index(
                  stringRange.lowerBound,
                  within: attributed
              ),
              let upper = AttributedString.Index(
                  stringRange.upperBound,
                  within: attributed
              ) else {
            continue
        }
        let range = lower..<upper
        attributed[range].foregroundColor = switch span.kind {
        case .keyword:
            NileColors.syntaxKeyword
        case .string:
            NileColors.syntaxString
        case .value:
            NileColors.syntaxValue
        case .comment:
            NileColors.syntaxComment
        }
        if span.kind == .comment {
            attributed[range].font = .system(
                size: 11,
                design: .monospaced
            ).italic()
        }
    }
    return attributed
}

private func nileCommentStart(
    in line: NSString,
    marker: String
) -> Int? {
    var searchLocation = 0
    while searchLocation <= line.length {
        let range = line.range(
            of: marker,
            options: [],
            range: NSRange(
                location: searchLocation,
                length: line.length - searchLocation
            )
        )
        guard range.location != NSNotFound else {
            return nil
        }
        let before = line.substring(
            with: NSRange(location: 0, length: range.location)
        )
        let quoteCount = before.reduce(into: 0) { count, character in
            if character == "\"" || character == "'" {
                count += 1
            }
        }
        if quoteCount.isMultiple(of: 2) {
            return range.location
        }
        searchLocation = range.location + 1
    }
    return nil
}
