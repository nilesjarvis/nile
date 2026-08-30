import Foundation
import NileTextRenderer

struct NileTextRendererProbe: Equatable {
    let pixels: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let lineCount: Int
    let maximumLineWidth: Double
}

enum NileTextRendererVerification {
    static var version: String {
        String(cString: nile_text_renderer_version())
    }

    static func invalidRequestStatus() -> Int32 {
        var result = NileTextResult()
        return nile_text_render(nil, &result)
    }

    static func renderProbe(
        fontPath: String
    ) -> NileTextRendererProbe? {
        var request = NileTextRequest()
        var result = NileTextResult()
        let status = "Tracked words wrap consistently".withCString {
            textPointer in
            fontPath.withCString { pathPointer in
                request.text_utf8 = textPointer
                request.font_path_utf8 = pathPointer
                request.canvas_width_pixels = 180
                request.canvas_height_pixels = 150
                request.font_size_pixels = 33
                request.font_weight = 500
                request.letter_spacing_pixels = 0.1
                request.line_height_pixels = 47
                request.first_baseline_pixels = 34
                request.foreground_rgba = 0xFFFFFFFF
                request.background_rgba = 0x212121FF
                request.alignment =
                    NILE_TEXT_ALIGNMENT_LEADING
                return nile_text_render(
                    &request,
                    &result
                )
            }
        }
        guard status == 0, let pixels = result.rgba else {
            nile_text_result_destroy(&result)
            return nil
        }
        defer {
            nile_text_result_destroy(&result)
        }
        let byteCount = Int(
            result.bytes_per_row * result.height_pixels
        )
        return NileTextRendererProbe(
            pixels: Data(bytes: pixels, count: byteCount),
            width: Int(result.width_pixels),
            height: Int(result.height_pixels),
            bytesPerRow: Int(result.bytes_per_row),
            lineCount: Int(result.line_count),
            maximumLineWidth: result.maximum_line_width_pixels
        )
    }

    static func lineCount(
        text: String,
        fontPath: String,
        widthPixels: Int32,
        fontSizePixels: Double,
        fontWeight: Double,
        lineHeightPixels: Double
    ) -> Int? {
        var request = NileTextRequest()
        var result = NileTextResult()
        let status = text.withCString { textPointer in
            fontPath.withCString { pathPointer in
                request.text_utf8 = textPointer
                request.font_path_utf8 = pathPointer
                request.canvas_width_pixels = widthPixels
                request.canvas_height_pixels = 2_000
                request.font_size_pixels = fontSizePixels
                request.font_weight = Float(fontWeight)
                request.letter_spacing_pixels = 0
                request.line_height_pixels = lineHeightPixels
                request.first_baseline_pixels = fontSizePixels
                request.foreground_rgba = 0xFFFFFFFF
                request.background_rgba = 0x181818FF
                request.alignment =
                    NILE_TEXT_ALIGNMENT_LEADING
                return nile_text_render(&request, &result)
            }
        }
        guard status == 0 else {
            nile_text_result_destroy(&result)
            return nil
        }
        defer {
            nile_text_result_destroy(&result)
        }
        return Int(result.line_count)
    }
}
