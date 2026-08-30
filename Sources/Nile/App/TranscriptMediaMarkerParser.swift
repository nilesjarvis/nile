import Foundation

struct TranscriptMediaMarker {
    let range: NSRange
    let path: String
}

enum TranscriptMediaMarkerParser {
    private static let supportedExtensions = Set([
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "svg",
        "mp4", "mov", "avi", "mkv", "webm",
        "mp3", "wav", "ogg", "opus", "m4a", "flac",
        "pdf", "docx", "doc", "odt", "rtf", "txt", "md", "epub",
        "xlsx", "xls", "ods", "csv", "tsv", "json", "xml", "yaml", "yml",
        "pptx", "ppt", "odp", "key",
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "apk", "ipa",
        "html", "htm",
    ])

    static func markers(in raw: String) -> [TranscriptMediaMarker] {
        let protected = maskProtectedExamples(in: raw)
        let scan = maskJSONExamples(in: protected)
        let extensions = supportedExtensions
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern =
            #"[`"']?MEDIA:\s*(?<value>`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|(?:(?:https://|file://|~/|/|[A-Za-z]:[/\\])\S+(?:[^\S\n]+\S+)*?\.(?:"# +
            extensions +
            #")(?:[?#][^\s`"'<>]*?[A-Za-z0-9_~/%+=&-])?))(?=(?:[\s`"',;:!?)\]}]|\.(?=\s|$)|$))[`"']?"#

        return TranscriptRegex.matches(
            pattern: pattern,
            in: scan,
            options: [.caseInsensitive]
        ).compactMap { match in
            guard let valueRange = TranscriptRegex.namedCaptureRange(
                "value",
                from: match
            ), let rawPath = TranscriptRegex.substring(
                scan,
                range: valueRange
            ) else {
                return nil
            }
            let path = normalizePath(rawPath)
            guard isSupportedReference(path) else {
                return nil
            }
            return TranscriptMediaMarker(range: match.range, path: path)
        }
    }

    private static func maskProtectedExamples(in raw: String) -> String {
        var ranges = TranscriptRegex.matches(
            pattern: #"```[^\n]*\n.*?```"#,
            in: raw,
            options: [.dotMatchesLineSeparators]
        ).map(\.range)

        for match in TranscriptRegex.matches(pattern: #"`[^`\n]+`"#, in: raw) {
            let start = max(0, match.range.location - 24)
            let prefixRange = NSRange(
                location: start,
                length: match.range.location - start
            )
            let prefix = TranscriptRegex.substring(raw, range: prefixRange) ?? ""
            if !TranscriptRegex.containsMatch(
                pattern: #"MEDIA:\s*$"#,
                in: prefix,
                options: [.caseInsensitive]
            ) {
                ranges.append(match.range)
            }
        }
        ranges += TranscriptRegex.matches(
            pattern: #"^[ \t]{0,3}>.*$"#,
            in: raw,
            options: [.anchorsMatchLines]
        ).map(\.range)
        return TranscriptRegex.masking(ranges: ranges, in: raw)
    }

    private static func maskJSONExamples(in raw: String) -> String {
        guard raw.contains("\""),
              raw.range(of: "MEDIA:", options: .caseInsensitive) != nil else {
            return raw
        }
        let valueMatches = TranscriptRegex.matches(
            pattern: #"(?<=[:,{\[])\s*"((?:[^"\\\n]|\\.)*)""#,
            in: raw
        )
        let mediaPattern =
            #"MEDIA:\s*(?:https://|file://|~/|/|[A-Za-z]:[/\\])"#
        let ranges = valueMatches.compactMap { match -> NSRange? in
            guard let bodyRange = TranscriptRegex.captureRange(1, from: match),
                  let body = TranscriptRegex.substring(raw, range: bodyRange),
                  TranscriptRegex.containsMatch(
                      pattern: mediaPattern,
                      in: body,
                      options: [.caseInsensitive]
                  ) else {
                return nil
            }
            return bodyRange
        }
        return TranscriptRegex.masking(ranges: ranges, in: raw)
    }

    private static func normalizePath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2,
           let first = value.first,
           first == value.last,
           ["`", "\"", "'"].contains(String(first)) {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.trimmingCharacters(
            in: CharacterSet(charactersIn: "`\"',.;:)}]!")
        )
    }

    private static func isSupportedReference(_ value: String) -> Bool {
        let lower = value.lowercased()
        let windows = lower.range(
            of: #"^[a-z]:[/\\]"#,
            options: .regularExpression
        ) != nil
        guard value.hasPrefix("/")
            || value.hasPrefix("~/")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("https://")
            || windows else {
            return false
        }
        let path = value
            .split(
                separator: "?",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
            .split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
        guard let extensionPart = path.split(separator: ".").last else {
            return false
        }
        return supportedExtensions.contains(extensionPart.lowercased())
    }
}
