import UIKit
import NileTextRenderer

enum NileTextMeasurement {
    static func height(
        text: String,
        style: NileTypography.TextStyle,
        font: UIFont,
        width: CGFloat,
        screenScale: CGFloat
    ) -> CGFloat? {
        guard let lineCount = lineCount(
            text: text,
            style: style,
            font: font,
            width: width,
            screenScale: screenScale
        ) else {
            return nil
        }
        let lineHeightPoints =
            (
                style.targetLineHeight
                    ?? font.lineHeight * style.fontSize / font.pointSize
            ) * font.pointSize / style.fontSize
        let baselineStep = ceil(lineHeightPoints * screenScale)
            / screenScale
        let firstLineHeight = max(
            font.lineHeight,
            (
                style.minimumSingleLineHeight.map {
                    $0 * font.pointSize / style.fontSize
                }
            ) ?? 0
        )
        return firstLineHeight
            + CGFloat(lineCount - 1) * baselineStep
    }

    static func lineCount(
        text: String,
        style: NileTypography.TextStyle,
        font: UIFont,
        width: CGFloat,
        screenScale: CGFloat
    ) -> Int? {
        guard
            !text.isEmpty,
            width.isFinite,
            width > 0,
            let fontPath = Bundle.main.path(
                forResource: style.fontResourceName,
                ofType: "ttf"
            )
        else {
            return nil
        }
        let widthPixelsValue = (width * screenScale).rounded()
        guard
            widthPixelsValue.isFinite,
            widthPixelsValue > 0,
            widthPixelsValue <= CGFloat(Int32.max)
        else {
            return nil
        }
        let lineHeightPoints =
            (
                style.targetLineHeight
                    ?? font.lineHeight * style.fontSize / font.pointSize
            ) * font.pointSize / style.fontSize
        var request = NileTextRequest()
        var result = NileTextResult()
        let status = text.withCString { textPointer in
            fontPath.withCString { pathPointer in
                request.text_utf8 = textPointer
                request.font_path_utf8 = pathPointer
                request.canvas_width_pixels = Int32(widthPixelsValue)
                request.canvas_height_pixels = 1
                request.font_size_pixels =
                    Double(font.pointSize * screenScale)
                request.font_weight = style.rendererWeight
                request.letter_spacing_pixels = letterSpacingPixels(
                    style: style,
                    font: font,
                    screenScale: screenScale
                )
                request.line_height_pixels =
                    Double(lineHeightPoints * screenScale)
                request.first_baseline_pixels = 0
                request.foreground_rgba = 0xFFFFFFFF
                request.background_rgba = 0x000000FF
                request.alignment =
                    NILE_TEXT_ALIGNMENT_LEADING
                return nile_text_render(&request, &result)
            }
        }
        guard status == 0, result.line_count > 0 else {
            nile_text_result_destroy(&result)
            return nil
        }
        defer {
            nile_text_result_destroy(&result)
        }
        return Int(result.line_count)
    }

    static func letterSpacingPixels(
        style: NileTypography.TextStyle,
        font: UIFont,
        screenScale: CGFloat
    ) -> Double {
        switch style.rendererLetterSpacing {
        case .none:
            return 0
        case let .em(value):
            return Double(value)
                * Double(Float(font.pointSize * screenScale))
        case let .points(value):
            let dynamicScale = Float(font.pointSize / style.fontSize)
            let spacingPixels =
                value * Float(screenScale) * dynamicScale
            let fontPixels = Float(font.pointSize * screenScale)
            return Double(
                Float(spacingPixels / fontPixels)
            ) * Double(fontPixels)
        }
    }
}
