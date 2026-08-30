struct ParsedMessageContent: Equatable, Sendable {
    let text: String
    let imagePaths: [String]
    let inlineImages: [String]
    let attachments: [MessageAttachment]
}

func parseMessageContent(
    _ raw: String,
    extractMedia: Bool = true
) -> ParsedMessageContent {
    TranscriptMessageParser.parse(raw, extractMedia: extractMedia)
}
