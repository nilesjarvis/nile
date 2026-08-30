import XCTest
@testable import Nile

final class TranscriptMessageParserTests: XCTestCase {
    func testMessageContentStripsMarkersAndExtractsImages() {
        let parsed = parseMessageContent(
            """
            What is this?

            [Image attached at: /img/a.png]
            [Image attached at: /img/b.jpg]
            [screenshot]
            """
        )
        XCTAssertEqual(parsed.text, "What is this?")
        XCTAssertEqual(parsed.imagePaths, ["/img/a.png", "/img/b.jpg"])
        XCTAssertTrue(parsed.inlineImages.isEmpty)

        let inline = parseMessageContent(
            "caption data:image/jpeg;base64,QUJD"
        )
        XCTAssertEqual(inline.text, "caption")
        XCTAssertEqual(inline.inlineImages, ["QUJD"])
        XCTAssertTrue(inline.imagePaths.isEmpty)
    }

    func testAssistantMediaTagsBecomeNativeAttachments() {
        let parsed = parseMessageContent(
            """
            Your files are ready.

            MEDIA:/home/hermes/images/chart.png
            MEDIA:"/home/hermes/reports/weekly report.pdf"
            """
        )

        XCTAssertEqual(parsed.text, "Your files are ready.")
        XCTAssertEqual(parsed.attachments, [
            MessageAttachment(
                path: "/home/hermes/images/chart.png",
                filename: "chart.png",
                kind: .image
            ),
            MessageAttachment(
                path: "/home/hermes/reports/weekly report.pdf",
                filename: "weekly report.pdf",
                kind: .file
            ),
        ])
    }

    func testMediaExtractionIgnoresMarkdownAndSerializedJSONExamples() {
        let parsed = parseMessageContent(
            """
            Ready.
            MEDIA:/tmp/real.png
            ```text
            MEDIA:/tmp/fenced.png
            ```
            Use `MEDIA:/tmp/inline.png` in a reply.
              > Example: MEDIA:/tmp/blockquote.png
            {"result":"MEDIA:/tmp/stale.png"}
            """
        )

        XCTAssertEqual(parsed.attachments.map(\.path), ["/tmp/real.png"])
        XCTAssertTrue(parsed.text.contains("```text\nMEDIA:/tmp/fenced.png\n```"))
        XCTAssertTrue(parsed.text.contains("`MEDIA:/tmp/inline.png`"))
        XCTAssertTrue(parsed.text.contains("MEDIA:/tmp/blockquote.png"))
        XCTAssertTrue(parsed.text.contains(#"{"result":"MEDIA:/tmp/stale.png"}"#))
    }

    func testMediaExtractionSupportsPinnedAbsolutePathAndURLForms() {
        let parsed = parseMessageContent(
            #"""
            MEDIA:/tmp/Jane Doe/speech.flac.
            MEDIA:C:\Users\Jane Doe\report.pdf,
            MEDIA:file:///tmp/generated chart.webp;
            MEDIA:https://cdn.example.test/video.mp4?token=abc).
            MEDIA:"/tmp/weekly report.pdf"
            MEDIA:`/tmp/backtick path.txt`
            MEDIA:'/tmp/single quoted path.md'
            MEDIA:/tmp/archive scan.tiff
            """#
        )

        XCTAssertEqual(parsed.attachments.map(\.path), [
            "/tmp/Jane Doe/speech.flac",
            #"C:\Users\Jane Doe\report.pdf"#,
            "file:///tmp/generated chart.webp",
            "https://cdn.example.test/video.mp4?token=abc",
            "/tmp/weekly report.pdf",
            "/tmp/backtick path.txt",
            "/tmp/single quoted path.md",
            "/tmp/archive scan.tiff",
        ])
        XCTAssertEqual(parsed.attachments.map(\.kind), [
            .audio, .file, .image, .video, .file, .file, .file, .image,
        ])
    }

    func testMediaExtractionPreservesRelativeExamplesAndCodeWhitespace() {
        let relative = "Example: MEDIA:images/generated.png"
        XCTAssertEqual(parseMessageContent(relative).text, relative)
        XCTAssertTrue(parseMessageContent(relative).attachments.isEmpty)

        let parsed = parseMessageContent(
            "Code:\n\n    val answer  =  42\n\nMEDIA:/home/hermes/result.txt"
        )
        XCTAssertEqual(parsed.text, "Code:\n\n    val answer  =  42")
    }

    func testDocumentDirectiveForcesFileDelivery() {
        let parsed = parseMessageContent(
            "Original quality [[audio_as_voice]] [[as_document]] "
                + "MEDIA:/home/hermes/images/chart.png"
        )
        XCTAssertEqual(parsed.text, "Original quality")
        XCTAssertEqual(parsed.attachments.count, 1)
        XCTAssertEqual(parsed.attachments.first?.kind, .file)

        let literal = parseMessageContent(
            "[[audio_as_voice]] [[as_document]] MEDIA:/home/hermes/images/chart.png",
            extractMedia: false
        )
        XCTAssertEqual(
            literal.text,
            "[[audio_as_voice]] [[as_document]] MEDIA:/home/hermes/images/chart.png"
        )
        XCTAssertTrue(literal.attachments.isEmpty)
    }
}
