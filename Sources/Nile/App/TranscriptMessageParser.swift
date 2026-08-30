import Foundation

enum TranscriptMessageParser {
    static func parse(
        _ raw: String,
        extractMedia: Bool
    ) -> ParsedMessageContent {
        let imageMatches = TranscriptRegex.matches(
            pattern: #"\[Image attached at:\s*([^\]]+)]"#,
            in: raw
        )
        let imagePaths = imageMatches.compactMap {
            TranscriptRegex.capture(1, from: $0, in: raw)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let inlineMatches = TranscriptRegex.matches(
            pattern: #"data:image/[\w.+-]+;base64,([A-Za-z0-9+/=]+)"#,
            in: raw
        )
        let inlineImages = inlineMatches.compactMap {
            TranscriptRegex.capture(1, from: $0, in: raw)
        }
        let forceDocument = extractMedia && TranscriptRegex.containsMatch(
            pattern: #"\[\[as_document]]"#,
            in: raw,
            options: [.caseInsensitive]
        )
        let mediaMarkers = extractMedia
            ? TranscriptMediaMarkerParser.markers(in: raw)
            : []
        let attachments = mediaMarkers.map {
            messageAttachment(path: $0.path, forceDocument: forceDocument)
        }

        var text = raw
        if extractMedia {
            let directiveRanges = TranscriptRegex.matches(
                pattern: #"\[\[(?:audio_as_voice|as_document)]]"#,
                in: raw,
                options: [.caseInsensitive]
            ).map(\.range)
            text = TranscriptRegex.removing(
                ranges: mediaMarkers.map(\.range) + directiveRanges,
                from: text
            )
        }
        text = TranscriptRegex.replacing(
            pattern: #"data:image/[\w.+-]+;base64,([A-Za-z0-9+/=]+)"#,
            in: text,
            with: ""
        )
        text = TranscriptRegex.replacing(
            pattern: #"\[Image attached at:\s*([^\]]+)]"#,
            in: text,
            with: ""
        )
        text = TranscriptRegex.replacing(
            pattern: #"\[screenshot]"#,
            in: text,
            with: ""
        )
        text = TranscriptRegex.replacing(
            pattern: #"\n{3,}"#,
            in: text,
            with: "\n\n"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedMessageContent(
            text: text,
            imagePaths: imagePaths,
            inlineImages: inlineImages,
            attachments: attachments
        )
    }

    private static func messageAttachment(
        path: String,
        forceDocument: Bool
    ) -> MessageAttachment {
        let pathWithoutQuery = path
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
        let normalized = pathWithoutQuery.replacingOccurrences(
            of: "\\",
            with: "/"
        )
        let filename = normalized.split(separator: "/").last.map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "attachment"
        let fileExtension = filename.split(separator: ".").last?
            .lowercased() ?? ""
        let imageExtensions = Set([
            "bmp", "gif", "jpeg", "jpg", "png", "svg", "tiff", "webp",
        ])
        let audioExtensions = Set([
            "flac", "m4a", "mp3", "ogg", "opus", "wav",
        ])
        let videoExtensions = Set([
            "avi", "mkv", "mov", "mp4", "webm",
        ])
        let kind: MessageAttachmentKind
        if forceDocument {
            kind = .file
        } else if imageExtensions.contains(fileExtension) {
            kind = .image
        } else if audioExtensions.contains(fileExtension) {
            kind = .audio
        } else if videoExtensions.contains(fileExtension) {
            kind = .video
        } else {
            kind = .file
        }
        return MessageAttachment(path: path, filename: filename, kind: kind)
    }
}
