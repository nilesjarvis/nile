import XCTest
@testable import Nile

final class NileAndroidTextRendererTests: XCTestCase {
    func testRendererVersionPinsAndroidTextStack() {
        XCTAssertEqual(
            NileAndroidTextRendererVerification.version,
            "android-15-freetype-2.13.2-harfbuzz-8.2.2-"
                + "minikin-skia"
        )
    }

    func testInvalidRequestFailsClosed() {
        XCTAssertEqual(
            NileAndroidTextRendererVerification
                .invalidRequestStatus(),
            2
        )
    }

    func testTrackedMultilineProbeIsDeterministicAndTransparent() throws {
        let fontPath = try XCTUnwrap(
            Bundle.main.path(
                forResource: "Roboto-Regular",
                ofType: "ttf"
            )
        )
        let first = try XCTUnwrap(
            NileAndroidTextRendererVerification.renderProbe(
                fontPath: fontPath
            )
        )
        let second = try XCTUnwrap(
            NileAndroidTextRendererVerification.renderProbe(
                fontPath: fontPath
            )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.width, 180)
        XCTAssertEqual(first.height, 150)
        XCTAssertEqual(first.bytesPerRow, 180 * 4)
        XCTAssertGreaterThan(first.lineCount, 1)
        XCTAssertLessThanOrEqual(first.maximumLineWidth, 180)
        XCTAssertEqual(first.pixels.count, 180 * 150 * 4)

        let bytes = [UInt8](first.pixels)
        var transparentPixels = 0
        var opaquePixels = 0
        var foregroundPixels = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            switch bytes[offset + 3] {
            case 0:
                transparentPixels += 1
                XCTAssertEqual(bytes[offset], 0)
                XCTAssertEqual(bytes[offset + 1], 0)
                XCTAssertEqual(bytes[offset + 2], 0)
            case 255:
                opaquePixels += 1
                if bytes[offset] == 255,
                   bytes[offset + 1] == 255,
                   bytes[offset + 2] == 255 {
                    foregroundPixels += 1
                }
            default:
                XCTFail("Renderer emitted a partially transparent pixel")
            }
        }
        XCTAssertGreaterThan(transparentPixels, 0)
        XCTAssertGreaterThan(opaquePixels, 0)
        XCTAssertGreaterThan(foregroundPixels, 0)
    }

    func testPinnedChatParagraphsUseAndroidLineBreaks() throws {
        let fontPath = try XCTUnwrap(
            Bundle.main.path(
                forResource: "Roboto-Regular",
                ofType: "ttf"
            )
        )
        let paragraph =
            "I mapped the supplied reference into Nile' own interaction "
            + "system: neutral graphite layers, compact status rows, and a "
            + "single anchored composer."
        let final =
            "The neutral graphite theme, violet actions, circular controls, "
            + "and compact composer are ready for a final visual review."
        XCTAssertEqual(
            NileAndroidTextRendererVerification.lineCount(
                text: paragraph,
                fontPath: fontPath,
                widthPixels: 990,
                fontSizePixels: 39,
                fontWeight: 400,
                lineHeightPixels: 55.38
            ),
            3
        )
        XCTAssertEqual(
            NileAndroidTextRendererVerification.lineCount(
                text: final,
                fontPath: fontPath,
                widthPixels: 990,
                fontSizePixels: 39,
                fontWeight: 400,
                lineHeightPixels: 55.38
            ),
            3
        )
    }

    func testComposerUsesAndroidSingleAndMultilineContainerHeights() throws {
        let fontPath = try XCTUnwrap(
            Bundle.main.path(
                forResource: "Roboto-Regular",
                ofType: "ttf"
            )
        )
        let widthPixels: Int32 = 582
        let fontSizePixels = 42.0
        let lineHeightPixels = 57.96

        let placeholderLines = try XCTUnwrap(
            NileAndroidTextRendererVerification.lineCount(
                text: "Ask Nile",
                fontPath: fontPath,
                widthPixels: widthPixels,
                fontSizePixels: fontSizePixels,
                fontWeight: 400,
                lineHeightPixels: lineHeightPixels
            )
        )
        let draftLines = try XCTUnwrap(
            NileAndroidTextRendererVerification.lineCount(
                text: "Review the final interaction details",
                fontPath: fontPath,
                widthPixels: widthPixels,
                fontSizePixels: fontSizePixels,
                fontWeight: 400,
                lineHeightPixels: lineHeightPixels
            )
        )
        let baselineStep = 58.0 / 3.0

        XCTAssertEqual(placeholderLines, 1)
        XCTAssertEqual(draftLines, 2)
        XCTAssertEqual(
            NileComposerLayout.minimumRowHeight(
                lineCount: placeholderLines,
                baselineStep: baselineStep
            ),
            44,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NileComposerLayout.minimumRowHeight(
                lineCount: draftLines,
                baselineStep: baselineStep
            ),
            62.666,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NileComposerLayout.minimumRowHeight(
                lineCount: 9,
                baselineStep: baselineStep
            ),
            120.666,
            accuracy: 0.001
        )
    }
}
