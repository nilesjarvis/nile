import Foundation

enum TranscriptRegex {
    static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return []
        }
        return expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }

    static func containsMatch(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        !matches(pattern: pattern, in: text, options: options).isEmpty
    }

    static func replacing(
        pattern: String,
        in text: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in text: String
    ) -> String? {
        substring(text, range: match.range(at: index))
    }

    static func captureRange(
        _ index: Int,
        from match: NSTextCheckingResult
    ) -> NSRange? {
        present(match.range(at: index))
    }

    static func namedCaptureRange(
        _ name: String,
        from match: NSTextCheckingResult
    ) -> NSRange? {
        present(match.range(withName: name))
    }

    static func substring(_ text: String, range: NSRange) -> String? {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    static func masking(ranges: [NSRange], in text: String) -> String {
        var units = Array(text.utf16)
        for range in ranges {
            guard range.location != NSNotFound else {
                continue
            }
            let lower = max(0, range.location)
            let upper = min(units.count, range.location + range.length)
            guard lower < upper else {
                continue
            }
            for index in lower..<upper where units[index] != 10 {
                units[index] = 32
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func removing(ranges: [NSRange], from text: String) -> String {
        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard range.location != NSNotFound,
                  range.location + range.length <= mutable.length else {
                continue
            }
            mutable.replaceCharacters(in: range, with: "")
        }
        return mutable as String
    }

    private static func present(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }
}
