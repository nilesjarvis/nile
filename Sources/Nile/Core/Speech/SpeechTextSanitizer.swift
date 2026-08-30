import Foundation

func sanitizeTextForSpeech(_ text: String) -> String {
    var result = normalizeSpeechLineBreaks(text)
    result = result.replacingRegex(
        #"(?s)```.*?(?:```|$)"#,
        with: " "
    )
    result = result.replacingRegex(
        #"(?i)^\s*(?:\([^)\n]{1,48}\)\s*)?(?:processing|thinking|reasoning|analyzing|pondering|contemplating|musing|cogitating|ruminating|deliberating|mulling|reflecting|computing|synthesizing|formulating|brainstorming)\.\.\.\s*"#,
        with: " "
    )
    result = result.replacingRegex(
        #"\[([^]]+)]\([^)]+\)"#,
        with: "$1"
    )
    result = result.replacingRegex(#"`([^`]+)`"#, with: "$1")
    result = result.replacingRegex(
        #"(?i)\bhttps?://\S+"#,
        with: " link "
    )
    result = withoutEmojiPresentationCodePoints(result)
    result = result.replacingRegex(#"(?m)^#{1,6}\s+"#, with: "")
    result = result.replacingRegex(#"[*_~>#]"#, with: "")
    result = result.replacingRegex(#"(?m)^\s*[-+*]\s+"#, with: "")
    result = result.replacingRegex(#"\s+"#, with: " ")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func chunkTextForSpeech(
    _ text: String,
    maxCharacters: Int = 1_800
) -> [String] {
    precondition(maxCharacters >= 2, "maxCharacters must be at least 2")
    let normalized = text.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    guard !normalized.isEmpty else {
        return []
    }

    let utf16 = normalized as NSString
    var chunks: [String] = []
    var start = 0
    while start < utf16.length {
        var end = min(start + maxCharacters, utf16.length)
        if end < utf16.length {
            let searchFloor = start + maxCharacters / 2
            var sentenceEnd: Int?
            if end > searchFloor {
                for index in stride(
                    from: end - 1,
                    through: searchFloor,
                    by: -1
                ) {
                    if isSpeechSentenceEnding(utf16.character(at: index)),
                       isUTF16Whitespace(utf16.character(at: index + 1)) {
                        sentenceEnd = index
                        break
                    }
                }
            }

            var wordEnd: Int?
            if sentenceEnd == nil, end > start {
                for index in stride(
                    from: end - 1,
                    through: start,
                    by: -1
                ) where isUTF16Whitespace(utf16.character(at: index)) {
                    wordEnd = index
                    break
                }
            }

            if let sentenceEnd {
                end = sentenceEnd + 1
            } else if let wordEnd {
                end = wordEnd
            } else if end > start,
                      isHighSurrogate(utf16.character(at: end - 1)),
                      isLowSurrogate(utf16.character(at: end)) {
                end -= 1
            }
        }

        let chunk = utf16.substring(
            with: NSRange(location: start, length: end - start)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
        start = end
        while start < utf16.length,
              isUTF16Whitespace(utf16.character(at: start)) {
            start += 1
        }
    }
    return chunks
}

private func normalizeSpeechLineBreaks(_ text: String) -> String {
    var result = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingRegex(#"(\p{L})-\n(\p{L})"#, with: "$1$2")
    result = result.replacingRegex(
        #"([.!?])?[ \t]*\n{2,}[ \t]*"#
    ) { match, source in
        guard match.numberOfRanges > 1,
              let punctuationRange = Range(
                  match.range(at: 1),
                  in: source
              ) else {
            return ". "
        }
        return "\(source[punctuationRange]) "
    }
    return result.replacingRegex(#"[ \t]*\n[ \t]*"#, with: " ")
}

private func withoutEmojiPresentationCodePoints(
    _ text: String
) -> String {
    String(
        text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(0x1F000...0x1FAFF).contains(value)
                && !(0x2600...0x27BF).contains(value)
                && value != 0xFE0F
                && value != 0x200D
                && !(0xE0020...0xE007F).contains(value)
        }
    )
}

private func isSpeechSentenceEnding(_ value: unichar) -> Bool {
    [46, 33, 63, 59, 58].contains(value)
}

private func isUTF16Whitespace(_ value: unichar) -> Bool {
    guard let scalar = UnicodeScalar(UInt32(value)) else {
        return false
    }
    return CharacterSet.whitespacesAndNewlines.contains(scalar)
}

private func isHighSurrogate(_ value: unichar) -> Bool {
    (0xD800...0xDBFF).contains(value)
}

private func isLowSurrogate(_ value: unichar) -> Bool {
    (0xDC00...0xDFFF).contains(value)
}

private extension String {
    func replacingRegex(
        _ pattern: String,
        with template: String
    ) -> String {
        replacingOccurrences(
            of: pattern,
            with: template,
            options: .regularExpression
        )
    }

    func replacingRegex(
        _ pattern: String,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }
        let source = self
        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        var result = source
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: transform(match, source))
        }
        return result
    }
}
