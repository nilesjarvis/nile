#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let supportedSchemaVersion = 2
private let ssimWindowSize = 8

private enum VisualComparisonError: Error, CustomStringConvertible {
    case invalid(String)
    case io(String)

    var description: String {
        switch self {
        case let .invalid(message), let .io(message):
            message
        }
    }
}

private struct PixelInsets: Codable {
    let top: Int
    let bottom: Int
    let left: Int
    let right: Int
}

private struct SolidVerticalSpacerSpec: Codable {
    let top: Int
    let height: Int
    let expectedHex: String
}

private struct CaptureSpec: Codable {
    let path: String
    let nativeScale: Double
    let systemChromeInsetsPixels: PixelInsets
    let solidVerticalSpacerPixels: SolidVerticalSpacerSpec?
}

private struct CanonicalSpec: Codable {
    let widthPixels: Int
    let heightPixels: Int
}

private struct ThresholdSpec: Codable {
    let minimumSSIM: Double
    let maximumOutlierFraction: Double
    let channelDelta: Int
    let maximumLandmarkDeltaPoints: Double
    let maximumMaskFraction: Double
}

private struct PixelRect: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

private enum MaskCategory: String, Codable, CaseIterable {
    case systemChrome
    case textCursor
    case timestamp
    case dynamicAnimation
}

private struct MaskSpec: Codable {
    let name: String
    let category: MaskCategory
    let reason: String
    let rectPixels: PixelRect
}

private enum LandmarkAxis: String, Codable, Equatable {
    case horizontal
    case vertical
}

private enum LandmarkMeasurement: String, Codable, Equatable {
    case firstMatchStart
    case lastMatchEnd
    case matchingSpan
    case longestRunStart
    case longestRunEnd
    case longestRunLength
}

private struct LandmarkProbeSpec: Codable, Equatable {
    let axis: LandmarkAxis
    let fixedPoints: Double
    let startPoints: Double
    let endPoints: Double
    let expectedHex: String
    let maximumChannelDelta: Int?
    let minimumRunPoints: Double?
    let measurement: LandmarkMeasurement
}

private struct LandmarkSpec: Codable {
    let name: String
    let kind: String
    let reference: LandmarkProbeSpec
    let candidate: LandmarkProbeSpec
    let tolerancePoints: Double?
}

private struct SampleLocation: Codable {
    let xPoints: Double
    let yPoints: Double
    let radiusPoints: Double?
}

private struct ColorSampleSpec: Codable {
    let name: String
    let expectedHex: String
    let reference: SampleLocation
    let candidate: SampleLocation
}

private enum ManualReviewStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

private struct ManualReviewSpec: Codable {
    let status: ManualReviewStatus
    let reviewedBy: String?
    let notes: String?
}

private struct ComparisonManifest: Codable {
    let schemaVersion: Int
    let fixture: String
    let reference: CaptureSpec
    let candidate: CaptureSpec
    let canonical: CanonicalSpec
    let thresholds: ThresholdSpec
    let masks: [MaskSpec]?
    let landmarks: [LandmarkSpec]?
    let colorSamples: [ColorSampleSpec]?
    let manualReview: ManualReviewSpec
}

private struct RGB: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int(red),
            Int(green),
            Int(blue)
        )
    }
}

private struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: RGB) {
        self.width = width
        self.height = height
        pixels = Array(repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = fill.red
            pixels[offset + 1] = fill.green
            pixels[offset + 2] = fill.blue
            pixels[offset + 3] = 255
        }
    }

    init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0,
              height > 0,
              pixels.count == width * height * 4 else {
            throw VisualComparisonError.invalid(
                "RGBA image dimensions did not match its pixel buffer."
            )
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> RGB {
        get {
            let offset = ((y * width) + x) * 4
            return RGB(
                red: pixels[offset],
                green: pixels[offset + 1],
                blue: pixels[offset + 2]
            )
        }
        set {
            let offset = ((y * width) + x) * 4
            pixels[offset] = newValue.red
            pixels[offset + 1] = newValue.green
            pixels[offset + 2] = newValue.blue
            pixels[offset + 3] = 255
        }
    }

    mutating func fill(rect: PixelRect, color: RGB) {
        let minX = max(0, rect.x)
        let minY = max(0, rect.y)
        let maxX = min(width, rect.x + rect.width)
        let maxY = min(height, rect.y + rect.height)
        guard minX < maxX, minY < maxY else {
            return
        }
        for y in minY..<maxY {
            for x in minX..<maxX {
                self[x, y] = color
            }
        }
    }

    func cropped(systemChrome insets: PixelInsets) throws -> RGBAImage {
        guard insets.left == 0, insets.right == 0 else {
            throw VisualComparisonError.invalid(
                "Only top and bottom system chrome may be cropped; side cropping is forbidden."
            )
        }
        guard insets.top >= 0,
              insets.bottom >= 0,
              insets.top + insets.bottom < height else {
            throw VisualComparisonError.invalid(
                "System chrome insets were outside the source image."
            )
        }
        let maximumChrome = Int((Double(height) * 0.15).rounded(.down))
        guard insets.top <= maximumChrome,
              insets.bottom <= maximumChrome else {
            throw VisualComparisonError.invalid(
                "A system chrome crop exceeded 15% of the source height."
            )
        }
        let croppedHeight = height - insets.top - insets.bottom
        var output = Array(
            repeating: UInt8(0),
            count: width * croppedHeight * 4
        )
        for y in 0..<croppedHeight {
            let sourceStart = ((y + insets.top) * width) * 4
            let targetStart = (y * width) * 4
            output.replaceSubrange(
                targetStart..<(targetStart + width * 4),
                with: pixels[sourceStart..<(sourceStart + width * 4)]
            )
        }
        return try RGBAImage(
            width: width,
            height: croppedHeight,
            pixels: output
        )
    }

    func removing(solidVerticalSpacer spec: SolidVerticalSpacerSpec)
        throws -> RGBAImage {
        guard spec.top > 0,
              spec.height > 0,
              spec.top + spec.height < height else {
            throw VisualComparisonError.invalid(
                "A solid vertical spacer must be internal to app content."
            )
        }
        let maximumSpacer = Int((Double(height) * 0.10).rounded(.down))
        guard spec.height <= maximumSpacer else {
            throw VisualComparisonError.invalid(
                "A solid vertical spacer exceeded 10% of app-content height."
            )
        }
        let expected = try parseHex(spec.expectedHex)
        for y in spec.top..<(spec.top + spec.height) {
            for x in 0..<width where self[x, y] != expected {
                throw VisualComparisonError.invalid(
                    "A solid vertical spacer contained non-\(expected.hex) "
                        + "pixels at (\(x), \(y))."
                )
            }
        }
        let outputHeight = height - spec.height
        var output = Array(
            repeating: UInt8(0),
            count: width * outputHeight * 4
        )
        let firstByteCount = spec.top * width * 4
        output.replaceSubrange(
            0..<firstByteCount,
            with: pixels[0..<firstByteCount]
        )
        let sourceRemainderStart =
            (spec.top + spec.height) * width * 4
        output.replaceSubrange(
            firstByteCount..<output.count,
            with: pixels[sourceRemainderStart..<pixels.count]
        )
        return try RGBAImage(
            width: width,
            height: outputHeight,
            pixels: output
        )
    }

    func resized(width targetWidth: Int, height targetHeight: Int) throws
        -> RGBAImage {
        guard targetWidth > 0, targetHeight > 0 else {
            throw VisualComparisonError.invalid(
                "Canonical image dimensions must be positive."
            )
        }
        if width == targetWidth, height == targetHeight {
            return self
        }
        var output = Array(
            repeating: UInt8(0),
            count: targetWidth * targetHeight * 4
        )
        let xScale = Double(width) / Double(targetWidth)
        let yScale = Double(height) / Double(targetHeight)
        for targetY in 0..<targetHeight {
            let sourceY = (Double(targetY) + 0.5) * yScale - 0.5
            let y0 = max(0, min(height - 1, Int(floor(sourceY))))
            let y1 = max(0, min(height - 1, y0 + 1))
            let yWeight = max(0, min(1, sourceY - Double(y0)))
            for targetX in 0..<targetWidth {
                let sourceX = (Double(targetX) + 0.5) * xScale - 0.5
                let x0 = max(0, min(width - 1, Int(floor(sourceX))))
                let x1 = max(0, min(width - 1, x0 + 1))
                let xWeight = max(0, min(1, sourceX - Double(x0)))
                let targetOffset = (
                    (targetY * targetWidth) + targetX
                ) * 4
                for channel in 0..<4 {
                    let topLeft = Double(
                        pixels[((y0 * width + x0) * 4) + channel]
                    )
                    let topRight = Double(
                        pixels[((y0 * width + x1) * 4) + channel]
                    )
                    let bottomLeft = Double(
                        pixels[((y1 * width + x0) * 4) + channel]
                    )
                    let bottomRight = Double(
                        pixels[((y1 * width + x1) * 4) + channel]
                    )
                    let top = topLeft + (topRight - topLeft) * xWeight
                    let bottom =
                        bottomLeft + (bottomRight - bottomLeft) * xWeight
                    output[targetOffset + channel] = UInt8(
                        max(
                            0,
                            min(
                                255,
                                Int(
                                    (top + (bottom - top) * yWeight)
                                        .rounded()
                                )
                            )
                        )
                    )
                }
            }
        }
        return try RGBAImage(
            width: targetWidth,
            height: targetHeight,
            pixels: output
        )
    }

    func writePNG(to url: URL) throws {
        guard let provider = CGDataProvider(
            data: Data(pixels) as CFData
        ),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.last.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisualComparisonError.io(
                "Could not create PNG output at \(url.path)."
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisualComparisonError.io(
                "Could not finalize PNG output at \(url.path)."
            )
        }
    }
}

private struct CaptureRuntime {
    let spec: CaptureSpec
    let source: RGBAImage
    let content: RGBAImage
    let normalized: RGBAImage
}

private struct LandmarkResult: Codable {
    let name: String
    let kind: String
    let referenceProbe: LandmarkProbeSpec
    let candidateProbe: LandmarkProbeSpec
    let referencePoints: Double
    let candidatePoints: Double
    let deltaPoints: Double
    let tolerancePoints: Double
    let passed: Bool
}

private struct ColorSampleResult: Codable {
    let name: String
    let expectedHex: String
    let referenceHex: String
    let candidateHex: String
    let passed: Bool
}

private struct MetricResult: Codable {
    let structuralSimilarity: Double
    let outlierFraction: Double
    let meanAbsoluteChannelDelta: Double
    let maximumChannelDelta: Int
    let comparedPixels: Int
    let maskedPixels: Int
    let maskFraction: Double
}

private struct NormalizationResult: Codable {
    let sourceWidthPixels: Int
    let sourceHeightPixels: Int
    let contentWidthPixels: Int
    let contentHeightPixels: Int
    let logicalContentWidthPoints: Double
    let logicalContentHeightPoints: Double
    let canonicalWidthPixels: Int
    let canonicalHeightPixels: Int
    let horizontalScaleFactor: Double
    let verticalScaleFactor: Double
}

private struct ReviewResult: Codable {
    let status: String
    let reviewedBy: String?
    let notes: String?
    let passed: Bool
}

private struct ComparisonResult: Codable {
    let schemaVersion: Int
    let fixture: String
    let passed: Bool
    let failureReasons: [String]
    let metrics: MetricResult
    let thresholds: ThresholdSpec
    let referenceNormalization: NormalizationResult
    let candidateNormalization: NormalizationResult
    let masks: [MaskSpec]
    let landmarks: [LandmarkResult]
    let colorSamples: [ColorSampleResult]
    let manualReview: ReviewResult
    let artifacts: [String: String]
}

private struct ComparisonRun {
    let result: ComparisonResult
    let exitCode: Int32
}

private func loadImage(at url: URL) throws -> RGBAImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw VisualComparisonError.io(
            "Could not decode image at \(url.path)."
        )
    }
    let width = image.width
    let height = image.height
    var pixels = Array(repeating: UInt8(0), count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw VisualComparisonError.io(
            "Could not create an sRGB decode context for \(url.path)."
        )
    }
    context.interpolationQuality = .none
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: width, height: height)
    )
    for offset in stride(from: 3, to: pixels.count, by: 4) {
        if pixels[offset] == 255 {
            continue
        }
        let alpha = Double(pixels[offset]) / 255
        let pixelOffset = offset - 3
        for channel in 0..<3 {
            pixels[pixelOffset + channel] = UInt8(
                max(
                    0,
                    min(
                        255,
                        Int(
                            (
                                Double(pixels[pixelOffset + channel])
                                    * alpha
                            ).rounded()
                        )
                    )
                )
            )
        }
        pixels[offset] = 255
    }
    return try RGBAImage(width: width, height: height, pixels: pixels)
}

private func resolvePath(_ path: String, relativeTo manifestURL: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
    return manifestURL.deletingLastPathComponent()
        .appendingPathComponent(expanded)
        .standardizedFileURL
}

private func validate(_ manifest: ComparisonManifest) throws {
    guard manifest.schemaVersion == supportedSchemaVersion else {
        throw VisualComparisonError.invalid(
            "Unsupported visual manifest schema \(manifest.schemaVersion)."
        )
    }
    guard !manifest.fixture.trimmingCharacters(
        in: .whitespacesAndNewlines
    ).isEmpty else {
        throw VisualComparisonError.invalid("Fixture name cannot be blank.")
    }
    guard manifest.reference.nativeScale > 0,
          manifest.candidate.nativeScale > 0 else {
        throw VisualComparisonError.invalid(
            "Capture nativeScale values must be positive."
        )
    }
    guard manifest.canonical.widthPixels > 0,
          manifest.canonical.heightPixels > 0 else {
        throw VisualComparisonError.invalid(
            "Canonical dimensions must be positive."
        )
    }
    let thresholds = manifest.thresholds
    guard thresholds.minimumSSIM >= 0.82,
          thresholds.minimumSSIM <= 1 else {
        throw VisualComparisonError.invalid(
            "minimumSSIM must be between 0.82 and 1."
        )
    }
    guard thresholds.maximumOutlierFraction >= 0,
          thresholds.maximumOutlierFraction <= 0.10 else {
        throw VisualComparisonError.invalid(
            "maximumOutlierFraction cannot exceed 0.10."
        )
    }
    guard thresholds.channelDelta >= 0,
          thresholds.channelDelta <= 18 else {
        throw VisualComparisonError.invalid(
            "channelDelta cannot exceed 18."
        )
    }
    guard thresholds.maximumLandmarkDeltaPoints >= 0,
          thresholds.maximumLandmarkDeltaPoints <= 2 else {
        throw VisualComparisonError.invalid(
            "maximumLandmarkDeltaPoints cannot exceed 2."
        )
    }
    guard thresholds.maximumMaskFraction >= 0,
          thresholds.maximumMaskFraction <= 0.02 else {
        throw VisualComparisonError.invalid(
            "maximumMaskFraction cannot exceed 0.02."
        )
    }
    let usesReviewedNativeTier =
        thresholds.minimumSSIM < 0.97
            || thresholds.maximumOutlierFraction > 0.03
    if usesReviewedNativeTier {
        guard manifest.manualReview.status == .accepted else {
            throw VisualComparisonError.invalid(
                "The wider native-presentation tier requires an accepted "
                    + "manual review."
            )
        }
        guard !(manifest.landmarks ?? []).isEmpty,
              !(manifest.colorSamples ?? []).isEmpty else {
            throw VisualComparisonError.invalid(
                "The wider native-presentation tier requires landmark and "
                    + "exact flat-color checks."
            )
        }
    }
    for landmark in manifest.landmarks ?? [] {
        guard !landmark.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !landmark.kind.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw VisualComparisonError.invalid(
                "Every landmark needs a name and kind."
            )
        }
        let tolerance = landmark.tolerancePoints
            ?? thresholds.maximumLandmarkDeltaPoints
        guard tolerance >= 0,
              tolerance <= thresholds.maximumLandmarkDeltaPoints else {
            throw VisualComparisonError.invalid(
                "Landmark \(landmark.name) tolerance exceeds the global limit."
            )
        }
        guard landmark.reference == landmark.candidate else {
            throw VisualComparisonError.invalid(
                "Landmark \(landmark.name) must use an identical probe "
                    + "for reference and candidate pixels."
            )
        }
        for (side, probe) in [
            ("reference", landmark.reference),
            ("candidate", landmark.candidate),
        ] {
            _ = try parseHex(probe.expectedHex)
            guard probe.fixedPoints >= 0,
                  probe.startPoints >= 0,
                  probe.endPoints > probe.startPoints,
                  (probe.maximumChannelDelta ?? 0) >= 0,
                  (probe.maximumChannelDelta ?? 0) <= 12,
                  (probe.minimumRunPoints ?? 0) >= 0 else {
                throw VisualComparisonError.invalid(
                    "Landmark \(landmark.name) \(side) probe is invalid."
                )
            }
        }
    }
}

private func captureRuntime(
    spec: CaptureSpec,
    manifestURL: URL,
    canonical: CanonicalSpec
) throws -> CaptureRuntime {
    let source = try loadImage(
        at: resolvePath(spec.path, relativeTo: manifestURL)
    )
    var content = try source.cropped(
        systemChrome: spec.systemChromeInsetsPixels
    )
    if let spacer = spec.solidVerticalSpacerPixels {
        content = try content.removing(solidVerticalSpacer: spacer)
    }
    let normalized = try content.resized(
        width: canonical.widthPixels,
        height: canonical.heightPixels
    )
    return CaptureRuntime(
        spec: spec,
        source: source,
        content: content,
        normalized: normalized
    )
}

private func validatedMask(
    _ specs: [MaskSpec],
    canonical: CanonicalSpec,
    maximumFraction: Double
) throws -> [Bool] {
    let pixelCount = canonical.widthPixels * canonical.heightPixels
    var mask = Array(repeating: false, count: pixelCount)
    for spec in specs {
        guard !spec.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !spec.reason.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw VisualComparisonError.invalid(
                "Every mask needs a name and a technical reason."
            )
        }
        let rect = spec.rectPixels
        guard rect.x >= 0,
              rect.y >= 0,
              rect.width > 0,
              rect.height > 0,
              rect.x + rect.width <= canonical.widthPixels,
              rect.y + rect.height <= canonical.heightPixels else {
            throw VisualComparisonError.invalid(
                "Mask \(spec.name) lies outside the canonical image."
            )
        }
        let fraction = Double(rect.width * rect.height)
            / Double(pixelCount)
        guard fraction <= 0.01 else {
            throw VisualComparisonError.invalid(
                "Mask \(spec.name) covers more than 1% of app content."
            )
        }
        if spec.category == .systemChrome {
            let touchesEdge =
                rect.x == 0
                || rect.y == 0
                || rect.x + rect.width == canonical.widthPixels
                || rect.y + rect.height == canonical.heightPixels
            guard touchesEdge else {
                throw VisualComparisonError.invalid(
                    "A systemChrome mask must touch a canonical image edge."
                )
            }
        }
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                mask[y * canonical.widthPixels + x] = true
            }
        }
    }
    let maskedCount = mask.reduce(into: 0) { count, value in
        if value {
            count += 1
        }
    }
    guard Double(maskedCount) / Double(pixelCount) <= maximumFraction else {
        throw VisualComparisonError.invalid(
            "Combined masks exceed maximumMaskFraction."
        )
    }
    return mask
}

private func luminance(_ rgb: RGB) -> Double {
    0.2126 * Double(rgb.red)
        + 0.7152 * Double(rgb.green)
        + 0.0722 * Double(rgb.blue)
}

private func structuralSimilarity(
    reference: RGBAImage,
    candidate: RGBAImage,
    mask: [Bool]
) -> Double {
    let k1: Double = 0.01 * 255.0
    let k2: Double = 0.03 * 255.0
    let c1 = k1 * k1
    let c2 = k2 * k2
    var sum = 0.0
    var windowCount = 0
    for startY in stride(
        from: 0,
        to: reference.height,
        by: ssimWindowSize
    ) {
        for startX in stride(
            from: 0,
            to: reference.width,
            by: ssimWindowSize
        ) {
            let endX = min(reference.width, startX + ssimWindowSize)
            let endY = min(reference.height, startY + ssimWindowSize)
            var referenceValues: [Double] = []
            var candidateValues: [Double] = []
            referenceValues.reserveCapacity(ssimWindowSize * ssimWindowSize)
            candidateValues.reserveCapacity(ssimWindowSize * ssimWindowSize)
            for y in startY..<endY {
                for x in startX..<endX {
                    if mask[y * reference.width + x] {
                        continue
                    }
                    referenceValues.append(
                        luminance(reference[x, y])
                    )
                    candidateValues.append(
                        luminance(candidate[x, y])
                    )
                }
            }
            guard !referenceValues.isEmpty else {
                continue
            }
            let count = Double(referenceValues.count)
            let referenceMean = referenceValues.reduce(0, +) / count
            let candidateMean = candidateValues.reduce(0, +) / count
            var referenceVariance = 0.0
            var candidateVariance = 0.0
            var covariance = 0.0
            for index in referenceValues.indices {
                let referenceDelta =
                    referenceValues[index] - referenceMean
                let candidateDelta =
                    candidateValues[index] - candidateMean
                referenceVariance += referenceDelta * referenceDelta
                candidateVariance += candidateDelta * candidateDelta
                covariance += referenceDelta * candidateDelta
            }
            referenceVariance /= count
            candidateVariance /= count
            covariance /= count
            let numerator =
                (2 * referenceMean * candidateMean + c1)
                * (2 * covariance + c2)
            let denominator =
                (
                    referenceMean * referenceMean
                        + candidateMean * candidateMean
                        + c1
                )
                * (referenceVariance + candidateVariance + c2)
            sum += denominator == 0 ? 1 : numerator / denominator
            windowCount += 1
        }
    }
    return windowCount == 0 ? 1 : sum / Double(windowCount)
}

private func differenceArtifacts(
    reference: RGBAImage,
    candidate: RGBAImage,
    mask: [Bool],
    channelThreshold: Int
) throws -> (
    metric: MetricResult,
    difference: RGBAImage,
    heatmap: RGBAImage,
    maskImage: RGBAImage
) {
    var difference = RGBAImage(
        width: reference.width,
        height: reference.height,
        fill: RGB(red: 0, green: 0, blue: 0)
    )
    var heatmap = difference
    var maskImage = difference
    var comparedPixels = 0
    var maskedPixels = 0
    var outliers = 0
    var totalDelta = 0
    var maximumDelta = 0
    for y in 0..<reference.height {
        for x in 0..<reference.width {
            let pixelIndex = y * reference.width + x
            if mask[pixelIndex] {
                maskedPixels += 1
                maskImage[x, y] = RGB(
                    red: 255,
                    green: 255,
                    blue: 255
                )
                continue
            }
            comparedPixels += 1
            let left = reference[x, y]
            let right = candidate[x, y]
            let red = abs(Int(left.red) - Int(right.red))
            let green = abs(Int(left.green) - Int(right.green))
            let blue = abs(Int(left.blue) - Int(right.blue))
            let pixelMaximum = max(red, green, blue)
            maximumDelta = max(maximumDelta, pixelMaximum)
            totalDelta += red + green + blue
            if pixelMaximum > channelThreshold {
                outliers += 1
            }
            difference[x, y] = RGB(
                red: UInt8(red),
                green: UInt8(green),
                blue: UInt8(blue)
            )
            let intensity = sqrt(Double(pixelMaximum) / 255)
            let heatRed = UInt8(
                max(0, min(255, Int((intensity * 510).rounded())))
            )
            let heatGreen = UInt8(
                max(
                    0,
                    min(
                        255,
                        Int(
                            (
                                (1 - abs(intensity - 0.5) * 2)
                                    * 255
                            ).rounded()
                        )
                    )
                )
            )
            let heatBlue = UInt8(
                max(
                    0,
                    min(
                        255,
                        Int(((1 - intensity) * 160).rounded())
                    )
                )
            )
            heatmap[x, y] = RGB(
                red: heatRed,
                green: heatGreen,
                blue: heatBlue
            )
        }
    }
    let metric = MetricResult(
        structuralSimilarity: structuralSimilarity(
            reference: reference,
            candidate: candidate,
            mask: mask
        ),
        outlierFraction: comparedPixels == 0
            ? 0
            : Double(outliers) / Double(comparedPixels),
        meanAbsoluteChannelDelta: comparedPixels == 0
            ? 0
            : Double(totalDelta) / Double(comparedPixels * 3),
        maximumChannelDelta: maximumDelta,
        comparedPixels: comparedPixels,
        maskedPixels: maskedPixels,
        maskFraction: Double(maskedPixels)
            / Double(reference.width * reference.height)
    )
    return (metric, difference, heatmap, maskImage)
}

private func parseHex(_ value: String) throws -> RGB {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    guard normalized.count == 7,
          normalized.first == "#",
          let integer = Int(normalized.dropFirst(), radix: 16) else {
        throw VisualComparisonError.invalid(
            "Invalid RGB hex value \(value)."
        )
    }
    return RGB(
        red: UInt8((integer >> 16) & 0xFF),
        green: UInt8((integer >> 8) & 0xFF),
        blue: UInt8(integer & 0xFF)
    )
}

private func dominantColor(
    in image: RGBAImage,
    at location: SampleLocation,
    nativeScale: Double
) throws -> RGB {
    let x = Int((location.xPoints * nativeScale).rounded())
    let y = Int((location.yPoints * nativeScale).rounded())
    let radius = max(
        0,
        Int(((location.radiusPoints ?? 0) * nativeScale).rounded())
    )
    guard x >= 0, x < image.width, y >= 0, y < image.height else {
        throw VisualComparisonError.invalid(
            "A color sample lies outside app-content coordinates."
        )
    }
    var counts: [RGB: Int] = [:]
    for sampleY in max(0, y - radius)...min(image.height - 1, y + radius) {
        for sampleX in max(0, x - radius)...min(image.width - 1, x + radius) {
            counts[image[sampleX, sampleY], default: 0] += 1
        }
    }
    return counts.max {
        if $0.value != $1.value {
            return $0.value < $1.value
        }
        return $0.key.hex > $1.key.hex
    }?.key ?? image[x, y]
}

private struct PixelRun {
    let start: Int
    let end: Int

    var length: Int {
        end - start
    }
}

private func matches(
    _ actual: RGB,
    expected: RGB,
    maximumChannelDelta: Int
) -> Bool {
    abs(Int(actual.red) - Int(expected.red)) <= maximumChannelDelta
        && abs(Int(actual.green) - Int(expected.green))
            <= maximumChannelDelta
        && abs(Int(actual.blue) - Int(expected.blue))
            <= maximumChannelDelta
}

private func measuredLandmark(
    in image: RGBAImage,
    nativeScale: Double,
    probe: LandmarkProbeSpec,
    label: String
) throws -> Double {
    let expected = try parseHex(probe.expectedHex)
    let maximumChannelDelta = probe.maximumChannelDelta ?? 0
    guard maximumChannelDelta >= 0, maximumChannelDelta <= 12 else {
        throw VisualComparisonError.invalid(
            "\(label) maximumChannelDelta must be between 0 and 12."
        )
    }
    let minimumRunPoints = probe.minimumRunPoints ?? 0
    guard minimumRunPoints >= 0 else {
        throw VisualComparisonError.invalid(
            "\(label) minimumRunPoints cannot be negative."
        )
    }
    let fixedPixel = Int((probe.fixedPoints * nativeScale).rounded())
    let startPixel = Int((probe.startPoints * nativeScale).rounded())
    let endPixel = Int((probe.endPoints * nativeScale).rounded())
    let varyingLimit: Int
    let fixedLimit: Int
    switch probe.axis {
    case .horizontal:
        varyingLimit = image.width
        fixedLimit = image.height
    case .vertical:
        varyingLimit = image.height
        fixedLimit = image.width
    }
    guard fixedPixel >= 0,
          fixedPixel < fixedLimit,
          startPixel >= 0,
          endPixel > startPixel,
          endPixel <= varyingLimit else {
        throw VisualComparisonError.invalid(
            "\(label) scan lies outside app-content coordinates."
        )
    }
    var runs: [PixelRun] = []
    var runStart: Int?
    for variablePixel in startPixel..<endPixel {
        let color: RGB
        switch probe.axis {
        case .horizontal:
            color = image[variablePixel, fixedPixel]
        case .vertical:
            color = image[fixedPixel, variablePixel]
        }
        if matches(
            color,
            expected: expected,
            maximumChannelDelta: maximumChannelDelta
        ) {
            if runStart == nil {
                runStart = variablePixel
            }
        } else if let activeStart = runStart {
            runs.append(PixelRun(start: activeStart, end: variablePixel))
            runStart = nil
        }
    }
    if let runStart {
        runs.append(PixelRun(start: runStart, end: endPixel))
    }
    let minimumRunPixels = max(
        1,
        Int(ceil(minimumRunPoints * nativeScale))
    )
    runs = runs.filter { $0.length >= minimumRunPixels }
    guard let first = runs.first, let last = runs.last else {
        throw VisualComparisonError.invalid(
            "\(label) found no qualifying \(expected.hex) pixels."
        )
    }
    let longest = runs.sorted {
        if $0.length != $1.length {
            return $0.length > $1.length
        }
        return $0.start < $1.start
    }[0]
    let pixels: Int
    switch probe.measurement {
    case .firstMatchStart:
        pixels = first.start
    case .lastMatchEnd:
        pixels = last.end
    case .matchingSpan:
        pixels = last.end - first.start
    case .longestRunStart:
        pixels = longest.start
    case .longestRunEnd:
        pixels = longest.end
    case .longestRunLength:
        pixels = longest.length
    }
    return Double(pixels) / nativeScale
}

private func normalizationResult(
    runtime: CaptureRuntime,
    canonical: CanonicalSpec
) -> NormalizationResult {
    NormalizationResult(
        sourceWidthPixels: runtime.source.width,
        sourceHeightPixels: runtime.source.height,
        contentWidthPixels: runtime.content.width,
        contentHeightPixels: runtime.content.height,
        logicalContentWidthPoints:
            Double(runtime.content.width) / runtime.spec.nativeScale,
        logicalContentHeightPoints:
            Double(runtime.content.height) / runtime.spec.nativeScale,
        canonicalWidthPixels: canonical.widthPixels,
        canonicalHeightPixels: canonical.heightPixels,
        horizontalScaleFactor:
            Double(canonical.widthPixels) / Double(runtime.content.width),
        verticalScaleFactor:
            Double(canonical.heightPixels) / Double(runtime.content.height)
    )
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        try encoder.encode(value).write(to: url, options: .atomic)
    } catch {
        throw VisualComparisonError.io(
            "Could not write JSON at \(url.path): \(error)"
        )
    }
}

private func performComparison(
    manifest: ComparisonManifest,
    manifestURL: URL,
    outputURL: URL
) throws -> ComparisonRun {
    try validate(manifest)
    let fileManager = FileManager.default
    try fileManager.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true
    )
    let reference = try captureRuntime(
        spec: manifest.reference,
        manifestURL: manifestURL,
        canonical: manifest.canonical
    )
    let candidate = try captureRuntime(
        spec: manifest.candidate,
        manifestURL: manifestURL,
        canonical: manifest.canonical
    )
    let masks = manifest.masks ?? []
    let mask = try validatedMask(
        masks,
        canonical: manifest.canonical,
        maximumFraction: manifest.thresholds.maximumMaskFraction
    )
    let artifacts = try differenceArtifacts(
        reference: reference.normalized,
        candidate: candidate.normalized,
        mask: mask,
        channelThreshold: manifest.thresholds.channelDelta
    )
    let landmarkResults = try (manifest.landmarks ?? []).map { landmark in
        let tolerance = min(
            landmark.tolerancePoints
                ?? manifest.thresholds.maximumLandmarkDeltaPoints,
            manifest.thresholds.maximumLandmarkDeltaPoints
        )
        let referencePoints = try measuredLandmark(
            in: reference.content,
            nativeScale: reference.spec.nativeScale,
            probe: landmark.reference,
            label: "\(landmark.name) reference"
        )
        let candidatePoints = try measuredLandmark(
            in: candidate.content,
            nativeScale: candidate.spec.nativeScale,
            probe: landmark.candidate,
            label: "\(landmark.name) candidate"
        )
        let delta = abs(
            referencePoints - candidatePoints
        )
        return LandmarkResult(
            name: landmark.name,
            kind: landmark.kind,
            referenceProbe: landmark.reference,
            candidateProbe: landmark.candidate,
            referencePoints: referencePoints,
            candidatePoints: candidatePoints,
            deltaPoints: delta,
            tolerancePoints: tolerance,
            passed: delta <= tolerance
        )
    }
    let colorResults = try (manifest.colorSamples ?? []).map { sample in
        let expected = try parseHex(sample.expectedHex)
        let referenceColor = try dominantColor(
            in: reference.content,
            at: sample.reference,
            nativeScale: reference.spec.nativeScale
        )
        let candidateColor = try dominantColor(
            in: candidate.content,
            at: sample.candidate,
            nativeScale: candidate.spec.nativeScale
        )
        return ColorSampleResult(
            name: sample.name,
            expectedHex: expected.hex,
            referenceHex: referenceColor.hex,
            candidateHex: candidateColor.hex,
            passed: referenceColor == expected && candidateColor == expected
        )
    }
    var failureReasons: [String] = []
    if artifacts.metric.structuralSimilarity
        < manifest.thresholds.minimumSSIM {
        failureReasons.append(
            "SSIM \(artifacts.metric.structuralSimilarity) is below \(manifest.thresholds.minimumSSIM)."
        )
    }
    if artifacts.metric.outlierFraction
        > manifest.thresholds.maximumOutlierFraction {
        failureReasons.append(
            "Outlier fraction \(artifacts.metric.outlierFraction) exceeds \(manifest.thresholds.maximumOutlierFraction)."
        )
    }
    let failedLandmarks = landmarkResults.filter { !$0.passed }.map(\.name)
    if !failedLandmarks.isEmpty {
        failureReasons.append(
            "Landmark tolerance failed: \(failedLandmarks.joined(separator: ", "))."
        )
    }
    let failedColors = colorResults.filter { !$0.passed }.map(\.name)
    if !failedColors.isEmpty {
        failureReasons.append(
            "Exact flat-color samples failed: \(failedColors.joined(separator: ", "))."
        )
    }
    let reviewPassed: Bool
    switch manifest.manualReview.status {
    case .accepted:
        reviewPassed =
            !(manifest.manualReview.reviewedBy ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(manifest.manualReview.notes ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !reviewPassed {
            failureReasons.append(
                "Accepted manual review requires reviewedBy and notes."
            )
        }
    case .pending:
        reviewPassed = false
        failureReasons.append(
            "Manual visible-mismatch review is still pending."
        )
    case .rejected:
        reviewPassed = false
        failureReasons.append(
            "Manual review found a plainly visible mismatch."
        )
    }
    let review = ReviewResult(
        status: manifest.manualReview.status.rawValue,
        reviewedBy: manifest.manualReview.reviewedBy,
        notes: manifest.manualReview.notes,
        passed: reviewPassed
    )
    let artifactNames = [
        "reference": "reference-normalized.png",
        "candidate": "candidate-normalized.png",
        "difference": "diff.png",
        "heatmap": "heatmap.png",
        "mask": "mask.png",
        "measurements": "measurements.json",
        "result": "result.json",
    ]
    try reference.normalized.writePNG(
        to: outputURL.appendingPathComponent(artifactNames["reference"]!)
    )
    try candidate.normalized.writePNG(
        to: outputURL.appendingPathComponent(artifactNames["candidate"]!)
    )
    try artifacts.difference.writePNG(
        to: outputURL.appendingPathComponent(artifactNames["difference"]!)
    )
    try artifacts.heatmap.writePNG(
        to: outputURL.appendingPathComponent(artifactNames["heatmap"]!)
    )
    try artifacts.maskImage.writePNG(
        to: outputURL.appendingPathComponent(artifactNames["mask"]!)
    )
    struct Measurements: Codable {
        let landmarks: [LandmarkResult]
        let colorSamples: [ColorSampleResult]
    }
    try writeJSON(
        Measurements(
            landmarks: landmarkResults,
            colorSamples: colorResults
        ),
        to: outputURL.appendingPathComponent(
            artifactNames["measurements"]!
        )
    )
    let passed = failureReasons.isEmpty
    let result = ComparisonResult(
        schemaVersion: supportedSchemaVersion,
        fixture: manifest.fixture,
        passed: passed,
        failureReasons: failureReasons,
        metrics: artifacts.metric,
        thresholds: manifest.thresholds,
        referenceNormalization: normalizationResult(
            runtime: reference,
            canonical: manifest.canonical
        ),
        candidateNormalization: normalizationResult(
            runtime: candidate,
            canonical: manifest.canonical
        ),
        masks: masks,
        landmarks: landmarkResults,
        colorSamples: colorResults,
        manualReview: review,
        artifacts: artifactNames
    )
    try writeJSON(
        result,
        to: outputURL.appendingPathComponent(artifactNames["result"]!)
    )
    let exitCode: Int32 = passed
        ? 0
        : manifest.manualReview.status == .pending
            && failureReasons.count == 1
            ? 2
            : 1
    return ComparisonRun(result: result, exitCode: exitCode)
}

private func decodeManifest(at url: URL) throws -> ComparisonManifest {
    do {
        return try JSONDecoder().decode(
            ComparisonManifest.self,
            from: Data(contentsOf: url)
        )
    } catch {
        throw VisualComparisonError.invalid(
            "Could not decode visual manifest \(url.path): \(error)"
        )
    }
}

private func selfTest() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
        "nile-visual-comparer-\(UUID().uuidString)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    let keepsArtifacts =
        ProcessInfo.processInfo.environment[
            "NILE_VISUAL_KEEP_SELF_TEST"
        ] == "1"
    defer {
        if !keepsArtifacts {
            try? fileManager.removeItem(at: root)
        }
    }
    let canvas = RGB(red: 0x18, green: 0x18, blue: 0x18)
    let panel = RGB(red: 0x21, green: 0x21, blue: 0x21)
    let accent = RGB(red: 0x33, green: 0x9C, blue: 0xFF)
    var reference = RGBAImage(width: 80, height: 62, fill: canvas)
    reference.fill(
        rect: PixelRect(x: 0, y: 0, width: 80, height: 2),
        color: RGB(red: 0xFF, green: 0xFF, blue: 0xFF)
    )
    reference.fill(
        rect: PixelRect(x: 10, y: 12, width: 60, height: 40),
        color: panel
    )
    reference.fill(
        rect: PixelRect(x: 15, y: 17, width: 10, height: 5),
        color: accent
    )
    var candidate = RGBAImage(width: 80, height: 64, fill: canvas)
    candidate.fill(
        rect: PixelRect(x: 0, y: 0, width: 80, height: 4),
        color: RGB(red: 0xEE, green: 0xEE, blue: 0xEE)
    )
    candidate.fill(
        rect: PixelRect(x: 10, y: 14, width: 60, height: 40),
        color: panel
    )
    candidate.fill(
        rect: PixelRect(x: 15, y: 19, width: 10, height: 5),
        color: accent
    )
    candidate.fill(
        rect: PixelRect(x: 40, y: 24, width: 2, height: 2),
        color: RGB(red: 0xFF, green: 0, blue: 0)
    )
    let referenceURL = root.appendingPathComponent("reference.png")
    let candidateURL = root.appendingPathComponent("candidate.png")
    try reference.writePNG(to: referenceURL)
    try candidate.writePNG(to: candidateURL)
    let thresholds = ThresholdSpec(
        minimumSSIM: 0.97,
        maximumOutlierFraction: 0.03,
        channelDelta: 18,
        maximumLandmarkDeltaPoints: 2,
        maximumMaskFraction: 0.02
    )
    let manifest = ComparisonManifest(
        schemaVersion: supportedSchemaVersion,
        fixture: "self-test-pass",
        reference: CaptureSpec(
            path: "reference.png",
            nativeScale: 1,
            systemChromeInsetsPixels: PixelInsets(
                top: 2,
                bottom: 0,
                left: 0,
                right: 0
            ),
            solidVerticalSpacerPixels: nil
        ),
        candidate: CaptureSpec(
            path: "candidate.png",
            nativeScale: 1,
            systemChromeInsetsPixels: PixelInsets(
                top: 4,
                bottom: 0,
                left: 0,
                right: 0
            ),
            solidVerticalSpacerPixels: nil
        ),
        canonical: CanonicalSpec(widthPixels: 80, heightPixels: 60),
        thresholds: thresholds,
        masks: [
            MaskSpec(
                name: "timestamp",
                category: .timestamp,
                reason: "Synthetic dynamic timestamp pixels.",
                rectPixels: PixelRect(
                    x: 40,
                    y: 20,
                    width: 2,
                    height: 2
                )
            ),
        ],
        landmarks: [
            LandmarkSpec(
                name: "panel-leading-inset",
                kind: "inset",
                reference: LandmarkProbeSpec(
                    axis: .horizontal,
                    fixedPoints: 30,
                    startPoints: 0,
                    endPoints: 80,
                    expectedHex: "#212121",
                    maximumChannelDelta: 0,
                    minimumRunPoints: 5,
                    measurement: .longestRunStart
                ),
                candidate: LandmarkProbeSpec(
                    axis: .horizontal,
                    fixedPoints: 30,
                    startPoints: 0,
                    endPoints: 80,
                    expectedHex: "#212121",
                    maximumChannelDelta: 0,
                    minimumRunPoints: 5,
                    measurement: .longestRunStart
                ),
                tolerancePoints: nil
            ),
        ],
        colorSamples: [
            ColorSampleSpec(
                name: "canvas",
                expectedHex: "#181818",
                reference: SampleLocation(
                    xPoints: 2,
                    yPoints: 2,
                    radiusPoints: 1
                ),
                candidate: SampleLocation(
                    xPoints: 2,
                    yPoints: 2,
                    radiusPoints: 1
                )
            ),
            ColorSampleSpec(
                name: "panel",
                expectedHex: "#212121",
                reference: SampleLocation(
                    xPoints: 30,
                    yPoints: 30,
                    radiusPoints: 1
                ),
                candidate: SampleLocation(
                    xPoints: 30,
                    yPoints: 30,
                    radiusPoints: 1
                )
            ),
        ],
        manualReview: ManualReviewSpec(
            status: .accepted,
            reviewedBy: "self-test",
            notes: "Synthetic fixture is identical outside its narrow timestamp mask."
        )
    )
    let manifestURL = root.appendingPathComponent("manifest.json")
    try writeJSON(manifest, to: manifestURL)
    let decoded = try decodeManifest(at: manifestURL)
    let passingOutput = root.appendingPathComponent(
        "passing-output",
        isDirectory: true
    )
    let passing = try performComparison(
        manifest: decoded,
        manifestURL: manifestURL,
        outputURL: passingOutput
    )
    guard passing.exitCode == 0,
          passing.result.passed,
          passing.result.metrics.maskedPixels == 4 else {
        throw VisualComparisonError.invalid(
            "Self-test expected the narrow-mask fixture to pass: "
                + "\(passing.result.failureReasons), "
                + "SSIM=\(passing.result.metrics.structuralSimilarity), "
                + "outliers=\(passing.result.metrics.outlierFraction), "
                + "masked=\(passing.result.metrics.maskedPixels), "
                + "artifacts=\(root.path)."
        )
    }
    for name in [
        "reference-normalized.png",
        "candidate-normalized.png",
        "diff.png",
        "heatmap.png",
        "mask.png",
        "measurements.json",
        "result.json",
    ] {
        guard fileManager.fileExists(
            atPath: passingOutput.appendingPathComponent(name).path
        ) else {
            throw VisualComparisonError.invalid(
                "Self-test artifact \(name) was not produced."
            )
        }
    }
    var spacerReference = RGBAImage(
        width: reference.width,
        height: reference.height + 2,
        fill: canvas
    )
    for y in 0..<reference.height {
        let destinationY = y < 6 ? y : y + 2
        for x in 0..<reference.width {
            spacerReference[x, destinationY] = reference[x, y]
        }
    }
    let spacerReferenceURL = root.appendingPathComponent(
        "reference-with-solid-spacer.png"
    )
    try spacerReference.writePNG(to: spacerReferenceURL)
    let spacerManifest = ComparisonManifest(
        schemaVersion: manifest.schemaVersion,
        fixture: "self-test-solid-spacer",
        reference: CaptureSpec(
            path: "reference-with-solid-spacer.png",
            nativeScale: 1,
            systemChromeInsetsPixels: PixelInsets(
                top: 2,
                bottom: 0,
                left: 0,
                right: 0
            ),
            solidVerticalSpacerPixels: SolidVerticalSpacerSpec(
                top: 4,
                height: 2,
                expectedHex: "#181818"
            )
        ),
        candidate: manifest.reference,
        canonical: manifest.canonical,
        thresholds: manifest.thresholds,
        masks: nil,
        landmarks: manifest.landmarks,
        colorSamples: manifest.colorSamples,
        manualReview: manifest.manualReview
    )
    let spacerPassing = try performComparison(
        manifest: spacerManifest,
        manifestURL: manifestURL,
        outputURL: root.appendingPathComponent(
            "solid-spacer-output",
            isDirectory: true
        )
    )
    guard spacerPassing.exitCode == 0,
          spacerPassing.result.passed,
          spacerPassing.result.metrics.outlierFraction == 0 else {
        throw VisualComparisonError.invalid(
            "Self-test expected an exact solid spacer removal to pass."
        )
    }
    let invalidSpacerManifest = ComparisonManifest(
        schemaVersion: spacerManifest.schemaVersion,
        fixture: "self-test-non-solid-spacer",
        reference: CaptureSpec(
            path: spacerManifest.reference.path,
            nativeScale: spacerManifest.reference.nativeScale,
            systemChromeInsetsPixels:
                spacerManifest.reference.systemChromeInsetsPixels,
            solidVerticalSpacerPixels: SolidVerticalSpacerSpec(
                top: 12,
                height: 2,
                expectedHex: "#181818"
            )
        ),
        candidate: spacerManifest.candidate,
        canonical: spacerManifest.canonical,
        thresholds: spacerManifest.thresholds,
        masks: nil,
        landmarks: spacerManifest.landmarks,
        colorSamples: spacerManifest.colorSamples,
        manualReview: spacerManifest.manualReview
    )
    do {
        _ = try performComparison(
            manifest: invalidSpacerManifest,
            manifestURL: manifestURL,
            outputURL: root.appendingPathComponent(
                "non-solid-spacer-output",
                isDirectory: true
            )
        )
        throw VisualComparisonError.invalid(
            "Self-test expected a non-solid spacer to be rejected."
        )
    } catch let error as VisualComparisonError {
        guard error.description.contains("contained non-#181818") else {
            throw error
        }
    }
    guard let matchingLandmark = manifest.landmarks?.first else {
        throw VisualComparisonError.invalid(
            "Self-test landmark fixture is missing."
        )
    }
    let mismatchedProbeManifest = ComparisonManifest(
        schemaVersion: manifest.schemaVersion,
        fixture: "self-test-mismatched-probes",
        reference: manifest.reference,
        candidate: manifest.candidate,
        canonical: manifest.canonical,
        thresholds: manifest.thresholds,
        masks: manifest.masks,
        landmarks: [
            LandmarkSpec(
                name: matchingLandmark.name,
                kind: matchingLandmark.kind,
                reference: matchingLandmark.reference,
                candidate: LandmarkProbeSpec(
                    axis: .horizontal,
                    fixedPoints: 31,
                    startPoints: 0,
                    endPoints: 80,
                    expectedHex: "#212121",
                    maximumChannelDelta: 0,
                    minimumRunPoints: 5,
                    measurement: .longestRunStart
                ),
                tolerancePoints: matchingLandmark.tolerancePoints
            ),
        ],
        colorSamples: manifest.colorSamples,
        manualReview: manifest.manualReview
    )
    do {
        _ = try performComparison(
            manifest: mismatchedProbeManifest,
            manifestURL: manifestURL,
            outputURL: root.appendingPathComponent(
                "mismatched-probe-output",
                isDirectory: true
            )
        )
        throw VisualComparisonError.invalid(
            "Self-test expected mismatched landmark probes to be rejected."
        )
    } catch let error as VisualComparisonError {
        guard error.description.contains("identical probe") else {
            throw error
        }
    }
    var failingCandidate = candidate
    failingCandidate.fill(
        rect: PixelRect(x: 10, y: 14, width: 30, height: 40),
        color: RGB(red: 0xFF, green: 0x67, blue: 0x64)
    )
    let failingURL = root.appendingPathComponent("candidate-failing.png")
    try failingCandidate.writePNG(to: failingURL)
    let failingManifest = ComparisonManifest(
        schemaVersion: manifest.schemaVersion,
        fixture: "self-test-fail",
        reference: manifest.reference,
        candidate: CaptureSpec(
            path: "candidate-failing.png",
            nativeScale: 1,
            systemChromeInsetsPixels:
                manifest.candidate.systemChromeInsetsPixels,
            solidVerticalSpacerPixels:
                manifest.candidate.solidVerticalSpacerPixels
        ),
        canonical: manifest.canonical,
        thresholds: manifest.thresholds,
        masks: manifest.masks,
        landmarks: manifest.landmarks,
        colorSamples: manifest.colorSamples,
        manualReview: manifest.manualReview
    )
    let failing = try performComparison(
        manifest: failingManifest,
        manifestURL: manifestURL,
        outputURL: root.appendingPathComponent(
            "failing-output",
            isDirectory: true
        )
    )
    guard failing.exitCode == 1,
          !failing.result.passed,
          failing.result.metrics.outlierFraction > 0.03,
          failing.result.landmarks.first?.passed == false else {
        throw VisualComparisonError.invalid(
            "Self-test expected the visible mismatch fixture to fail."
        )
    }
    let broadMaskManifest = ComparisonManifest(
        schemaVersion: manifest.schemaVersion,
        fixture: "self-test-broad-mask",
        reference: manifest.reference,
        candidate: manifest.candidate,
        canonical: manifest.canonical,
        thresholds: manifest.thresholds,
        masks: [
            MaskSpec(
                name: "forbidden-broad-mask",
                category: .timestamp,
                reason: "Must be rejected.",
                rectPixels: PixelRect(
                    x: 0,
                    y: 0,
                    width: 80,
                    height: 10
                )
            ),
        ],
        landmarks: nil,
        colorSamples: nil,
        manualReview: manifest.manualReview
    )
    do {
        _ = try performComparison(
            manifest: broadMaskManifest,
            manifestURL: manifestURL,
            outputURL: root.appendingPathComponent(
                "invalid-output",
                isDirectory: true
            )
        )
        throw VisualComparisonError.invalid(
            "Self-test expected a broad mask to be rejected."
        )
    } catch let error as VisualComparisonError {
        guard error.description.contains("more than 1%") else {
            throw error
        }
    }
    print("Visual comparer self-test passed")
}

private func usage() {
    print(
        """
        Usage:
          compare.swift <manifest.json> --output <artifact-directory>
          compare.swift --self-test

        Exit codes:
          0  comparison and explicit visual review passed
          1  metrics, measurements, colors, or visual review failed
          2  metrics passed but visual review is pending
          64 invalid invocation or manifest
        """
    )
}

private func main() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        do {
            try selfTest()
            return 0
        } catch {
            fputs("Visual comparer self-test failed: \(error)\n", stderr)
            return 1
        }
    }
    guard arguments.count == 3,
          arguments[1] == "--output" else {
        usage()
        return 64
    }
    let manifestURL = URL(
        fileURLWithPath: (arguments[0] as NSString).expandingTildeInPath
    ).standardizedFileURL
    let outputURL = URL(
        fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath,
        isDirectory: true
    ).standardizedFileURL
    do {
        let manifest = try decodeManifest(at: manifestURL)
        let run = try performComparison(
            manifest: manifest,
            manifestURL: manifestURL,
            outputURL: outputURL
        )
        print(
            String(
                format:
                    "fixture=%@ passed=%@ ssim=%.6f outlier_fraction=%.6f",
                run.result.fixture,
                run.result.passed ? "true" : "false",
                run.result.metrics.structuralSimilarity,
                run.result.metrics.outlierFraction
            )
        )
        return run.exitCode
    } catch {
        fputs("Visual comparison failed: \(error)\n", stderr)
        return 64
    }
}

exit(main())
