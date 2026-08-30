import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Nile

final class NileImageEncoderTests: XCTestCase {
    func testTranscriptImageCacheDecodesStablePayloadOnce() throws {
        let cache = TranscriptImageCache(
            countLimit: 2,
            totalCostLimit: 1_024 * 1_024
        )
        let payload = try imageData(
            width: 1,
            height: 1,
            type: .png
        ).base64EncodedString()

        let first = try XCTUnwrap(cache.image(forBase64: payload))
        let second = try XCTUnwrap(cache.image(forBase64: payload))

        XCTAssertTrue(first === second)
        XCTAssertEqual(cache.decodeCount, 1)
    }

    func testLargeImageBecomesBoundedJPEGWithStableFilenameContract() throws {
        let source = try imageData(
            width: 3_200,
            height: 1_600,
            type: .png
        )

        let attachment = try XCTUnwrap(NileImageEncoder.encode(source))
        XCTAssertEqual(attachment.fileExtension, ".jpg")
        XCTAssertEqual(
            attachment.filename,
            "photo_\(attachment.data.count).jpg"
        )
        XCTAssertLessThanOrEqual(
            attachment.data.count,
            ProtectedAttachmentDraftStore.maximumAttachmentBytes
        )

        let encoded = try XCTUnwrap(
            CGImageSourceCreateWithData(attachment.data as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)
                as? [CFString: Any]
        )
        let width = try XCTUnwrap(
            (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        )
        let height = try XCTUnwrap(
            (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        )
        XCTAssertEqual(max(width, height), NileImageEncoder.maximumEdge)
        XCTAssertEqual(width, height * 2)
        XCTAssertEqual(
            CGImageSourceGetType(encoded) as String?,
            UTType.jpeg.identifier
        )
    }

    func testInvalidImageFailsWithoutCreatingAttachment() {
        XCTAssertNil(
            NileImageEncoder.encode(Data("not an image".utf8))
        )
    }

    private func imageData(
        width: Int,
        height: Int,
        type: UTType
    ) throws -> Data {
        let colorSpace = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.sRGB)
        )
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [0.2, 0.5, 0.8, 1]
            )!
        )
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                output,
                type.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
