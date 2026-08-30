#include "NileAndroidTextRenderer.h"

#include <hb.h>
#include <hb-ot.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MULTIPLE_MASTERS_H

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr int kLoadFlags =
    FT_LOAD_TARGET_NORMAL
        | FT_LOAD_NO_AUTOHINT
        | FT_LOAD_NO_BITMAP
        | FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH;

struct Glyph {
    FT_UInt id;
    float x;
    float y;
    float advance;
    uint32_t cluster;
};

struct ShapedRun {
    std::vector<Glyph> glyphs;
    float advance = 0;
};

struct ShapeContext {
    FT_Face face;
};

struct Token {
    std::string text;
    bool whitespace = false;
    ShapedRun shaped;
};

struct Line {
    std::vector<Glyph> glyphs;
    float advance = 0;
};

static hb_position_t horizontalAdvance(
    hb_font_t*,
    void* fontData,
    hb_codepoint_t glyph,
    void*
) {
    auto* context = static_cast<ShapeContext*>(fontData);
    FT_Set_Transform(context->face, nullptr, nullptr);
    if (FT_Load_Glyph(
            context->face,
            glyph,
            kLoadFlags | FT_LOAD_BITMAP_METRICS_ONLY
        ) != 0) {
        return 0;
    }
    const float advance =
        static_cast<float>(context->face->glyph->advance.x) / 64.0f;
    return static_cast<hb_position_t>(std::scalbn(advance, 8));
}

static void horizontalAdvances(
    hb_font_t* font,
    void* fontData,
    unsigned count,
    const hb_codepoint_t* firstGlyph,
    unsigned glyphStride,
    hb_position_t* firstAdvance,
    unsigned advanceStride,
    void* userData
) {
    const auto* glyphBytes =
        reinterpret_cast<const uint8_t*>(firstGlyph);
    auto* advanceBytes = reinterpret_cast<uint8_t*>(firstAdvance);
    for (unsigned index = 0; index < count; ++index) {
        const auto* glyph =
            reinterpret_cast<const hb_codepoint_t*>(glyphBytes);
        auto* advance =
            reinterpret_cast<hb_position_t*>(advanceBytes);
        *advance = horizontalAdvance(
            font,
            fontData,
            *glyph,
            userData
        );
        glyphBytes += glyphStride;
        advanceBytes += advanceStride;
    }
}

static hb_bool_t horizontalOrigin(
    hb_font_t*,
    void*,
    hb_codepoint_t,
    hb_position_t*,
    hb_position_t*,
    void*
) {
    return true;
}

class TextRenderer {
public:
    explicit TextRenderer(const NileAndroidTextRequest& request)
        : request_(request) {
        if (FT_Init_FreeType(&library_) != 0) {
            return;
        }
        if (FT_New_Face(
                library_,
                request.font_path_utf8,
                0,
                &face_
            ) != 0) {
            return;
        }
        if (FT_Set_Char_Size(
                face_,
                static_cast<FT_F26Dot6>(
                    std::lround(request.font_size_pixels * 64.0)
                ),
                static_cast<FT_F26Dot6>(
                    std::lround(request.font_size_pixels * 64.0)
                ),
                72,
                72
            ) != 0) {
            return;
        }
        if (!setWeight(request.font_weight)) {
            return;
        }
        blob_ = hb_blob_create_from_file_or_fail(
            request.font_path_utf8
        );
        if (blob_ == hb_blob_get_empty()) {
            return;
        }
        hbFace_ = hb_face_create(blob_, 0);
        ready_ = hbFace_ != hb_face_get_empty();
    }

    ~TextRenderer() {
        if (hbFace_ != nullptr) {
            hb_face_destroy(hbFace_);
        }
        if (blob_ != nullptr) {
            hb_blob_destroy(blob_);
        }
        if (face_ != nullptr) {
            FT_Done_Face(face_);
        }
        if (library_ != nullptr) {
            FT_Done_FreeType(library_);
        }
    }

    bool ready() const {
        return ready_;
    }

    std::vector<Line> layout() {
        std::vector<Line> lines;
        const std::string text(request_.text_utf8);
        size_t paragraphStart = 0;
        while (paragraphStart <= text.size()) {
            const size_t newline = text.find('\n', paragraphStart);
            const size_t paragraphEnd =
                newline == std::string::npos ? text.size() : newline;
            appendParagraph(
                text.substr(
                    paragraphStart,
                    paragraphEnd - paragraphStart
                ),
                &lines
            );
            if (newline == std::string::npos) {
                break;
            }
            paragraphStart = newline + 1;
        }
        if (lines.empty()) {
            lines.push_back(Line{});
        }
        return lines;
    }

    std::vector<uint8_t> render(const std::vector<Line>& lines) {
        const size_t width =
            static_cast<size_t>(request_.canvas_width_pixels);
        const size_t height =
            static_cast<size_t>(request_.canvas_height_pixels);
        std::vector<uint8_t> coverage(width * height, 0);
        for (size_t lineIndex = 0;
             lineIndex < lines.size();
             ++lineIndex) {
            const Line& line = lines[lineIndex];
            float originX = 0;
            if (
                request_.alignment
                    == NILE_ANDROID_TEXT_ALIGNMENT_CENTER
            ) {
                originX = (
                    static_cast<float>(width) - line.advance
                ) * 0.5f;
            } else if (
                request_.alignment
                    == NILE_ANDROID_TEXT_ALIGNMENT_TRAILING
            ) {
                originX =
                    static_cast<float>(width) - line.advance;
            }
            // Minikin resolves Compose's explicit line-height to a whole
            // device-pixel baseline step before placing subsequent lines.
            // Keeping the fractional value and rounding each accumulated
            // baseline instead produces a 46/46 cadence for a 46.2 px
            // style, while the Android paragraph uses 47/47.
            const double baselineStep =
                std::ceil(request_.line_height_pixels);
            const float baselineY = static_cast<float>(
                request_.first_baseline_pixels
                    + static_cast<double>(lineIndex) * baselineStep
            );
            renderLine(
                line,
                originX,
                baselineY,
                width,
                height,
                &coverage
            );
        }
        return composite(coverage);
    }

private:
    bool setWeight(float weight) {
        FT_MM_Var* variation = nullptr;
        if (FT_Get_MM_Var(face_, &variation) != 0) {
            return std::abs(weight - 400.0f) < 0.5f;
        }
        std::vector<FT_Fixed> coordinates(variation->num_axis);
        for (FT_UInt index = 0;
             index < variation->num_axis;
             ++index) {
            coordinates[index] = variation->axis[index].def;
            if (
                variation->axis[index].tag
                    == FT_MAKE_TAG('w', 'g', 'h', 't')
            ) {
                coordinates[index] = static_cast<FT_Fixed>(
                    std::lround(weight * 65536.0)
                );
            }
        }
        const bool succeeded =
            FT_Set_Var_Design_Coordinates(
                face_,
                variation->num_axis,
                coordinates.data()
            ) == 0;
        FT_Done_MM_Var(library_, variation);
        return succeeded;
    }

    ShapedRun shapePiece(
        const std::string& text,
        double letterSpacing
    ) {
        hb_font_t* otParent = hb_font_create(hbFace_);
        hb_ot_font_set_funcs(otParent);
        const unsigned upem = hb_face_get_upem(hbFace_);
        hb_font_set_scale(otParent, upem, upem);

        hb_font_t* variationParent =
            hb_font_create_sub_font(otParent);
        hb_variation_t variation{
            HB_TAG('w', 'g', 'h', 't'),
            request_.font_weight,
        };
        hb_font_set_variations(
            variationParent,
            &variation,
            1
        );

        hb_font_t* font = hb_font_create_sub_font(variationParent);
        ShapeContext context{face_};
        hb_font_funcs_t* functions = hb_font_funcs_create();
        hb_font_funcs_set_glyph_h_advance_func(
            functions,
            horizontalAdvance,
            nullptr,
            nullptr
        );
        hb_font_funcs_set_glyph_h_advances_func(
            functions,
            horizontalAdvances,
            nullptr,
            nullptr
        );
        hb_font_funcs_set_glyph_h_origin_func(
            functions,
            horizontalOrigin,
            nullptr,
            nullptr
        );
        hb_font_funcs_make_immutable(functions);
        hb_font_set_funcs(font, functions, &context, nullptr);
        hb_font_set_ppem(
            font,
            static_cast<unsigned>(
                std::lround(request_.font_size_pixels)
            ),
            static_cast<unsigned>(
                std::lround(request_.font_size_pixels)
            )
        );
        const int scale = static_cast<int>(
            std::lround(request_.font_size_pixels * 256.0)
        );
        hb_font_set_scale(font, scale, scale);

        hb_buffer_t* buffer = hb_buffer_create();
        hb_buffer_add_utf8(
            buffer,
            text.data(),
            static_cast<int>(text.size()),
            0,
            static_cast<int>(text.size())
        );
        hb_buffer_guess_segment_properties(buffer);
        hb_shape(font, buffer, nullptr, 0);

        unsigned count = 0;
        hb_glyph_info_t* info =
            hb_buffer_get_glyph_infos(buffer, &count);
        hb_glyph_position_t* positions =
            hb_buffer_get_glyph_positions(buffer, &count);
        ShapedRun run;
        run.glyphs.reserve(count);
        float x = 0;
        float y = 0;
        const double spacingHalf = letterSpacing * 0.5;
        if (count > 0 && letterSpacing != 0) {
            x += spacingHalf;
        }
        for (unsigned index = 0; index < count; ++index) {
            if (
                index > 0
                && info[index - 1].cluster != info[index].cluster
            ) {
                x += letterSpacing;
            }
            const float xOffset = std::scalbn(
                static_cast<float>(positions[index].x_offset),
                -8
            );
            const float yOffset = -std::scalbn(
                static_cast<float>(positions[index].y_offset),
                -8
            );
            const float advance = std::scalbn(
                static_cast<float>(positions[index].x_advance),
                -8
            );
            run.glyphs.push_back(
                Glyph{
                    info[index].codepoint,
                    x + xOffset,
                    y + yOffset,
                    advance,
                    info[index].cluster,
                }
            );
            x += advance;
            y += std::scalbn(
                static_cast<float>(positions[index].y_advance),
                -8
            );
        }
        if (count > 0 && letterSpacing != 0) {
            x += spacingHalf;
            for (Glyph& glyph : run.glyphs) {
                glyph.x -= static_cast<float>(spacingHalf);
            }
            x -= static_cast<float>(letterSpacing);
        }
        run.advance = x;

        hb_buffer_destroy(buffer);
        hb_font_destroy(font);
        hb_font_funcs_destroy(functions);
        hb_font_destroy(variationParent);
        hb_font_destroy(otParent);
        return run;
    }

    static bool isASCIIWhitespace(char value) {
        return value == ' ' || value == '\t';
    }

    std::vector<Token> tokenize(const std::string& paragraph) {
        std::vector<Token> tokens;
        size_t start = 0;
        while (start < paragraph.size()) {
            const bool whitespace =
                isASCIIWhitespace(paragraph[start]);
            size_t end = start + 1;
            while (
                end < paragraph.size()
                && isASCIIWhitespace(paragraph[end]) == whitespace
            ) {
                ++end;
            }
            Token token;
            token.text = paragraph.substr(start, end - start);
            token.whitespace = whitespace;
            token.shaped = shapeCachedPieces(token.text);
            tokens.push_back(std::move(token));
            start = end;
        }
        return tokens;
    }

    ShapedRun shapeCachedPieces(const std::string& text) {
        if (request_.letter_spacing_pixels != 0) {
            return shapePiece(
                text,
                stabilizedLetterSpacing()
            );
        }
        ShapedRun result;
        float penX = 0;
        size_t start = 0;
        while (start < text.size()) {
            size_t end = start + 1;
            if (!isASCIIWhitespace(text[start])) {
                while (
                    end < text.size()
                    && !isASCIIWhitespace(text[end])
                ) {
                    ++end;
                }
            }
            ShapedRun piece = shapePiece(
                text.substr(start, end - start),
                0
            );
            for (Glyph glyph : piece.glyphs) {
                glyph.x += penX;
                result.glyphs.push_back(glyph);
            }
            penX += piece.advance;
            start = end;
        }
        result.advance = penX;
        return result;
    }

    double stabilizedLetterSpacing() const {
        if (request_.letter_spacing_pixels >= 0) {
            return request_.letter_spacing_pixels;
        }
        // Compose stores letter spacing as Float but Minikin accumulates it
        // through a mixed Float/Double path. Nudging inward by three
        // millionths of a physical pixel reproduces its boundary tie on
        // Apple clang without changing any visible metric.
        return request_.letter_spacing_pixels + 0.000003;
    }

    static void appendRun(
        const ShapedRun& run,
        float originX,
        Line* line
    ) {
        for (Glyph glyph : run.glyphs) {
            glyph.x += originX;
            line->glyphs.push_back(glyph);
        }
        line->advance = originX + run.advance;
    }

    void appendTrackedLine(
        const std::string& text,
        std::vector<Line>* lines
    ) {
        const ShapedRun run = shapePiece(
            text,
            stabilizedLetterSpacing()
        );
        Line line;
        appendRun(run, 0, &line);
        lines->push_back(std::move(line));
    }

    void appendTrackedParagraph(
        const std::string& paragraph,
        std::vector<Line>* lines
    ) {
        const std::vector<Token> tokens = tokenize(paragraph);
        std::string lineText;
        std::string pendingWhitespace;
        float lineAdvance = 0;
        float pendingAdvance = 0;
        for (const Token& token : tokens) {
            if (token.whitespace) {
                pendingWhitespace += token.text;
                pendingAdvance += token.shaped.advance;
                continue;
            }
            const float proposed =
                lineAdvance + pendingAdvance + token.shaped.advance;
            if (
                !lineText.empty()
                && proposed
                    > static_cast<float>(
                        request_.canvas_width_pixels
                    )
            ) {
                appendTrackedLine(lineText, lines);
                lineText.clear();
                lineAdvance = 0;
                pendingWhitespace.clear();
                pendingAdvance = 0;
            } else {
                lineText += pendingWhitespace;
                lineAdvance += pendingAdvance;
                pendingWhitespace.clear();
                pendingAdvance = 0;
            }
            lineText += token.text;
            lineAdvance += token.shaped.advance;
        }
        appendTrackedLine(lineText, lines);
    }

    void appendParagraph(
        const std::string& paragraph,
        std::vector<Line>* lines
    ) {
        if (paragraph.empty()) {
            lines->push_back(Line{});
            return;
        }
        // Minikin caches untracked words independently, but tracked text is
        // shaped in line context so spacing is applied across word
        // boundaries. Measuring tokens still gives deterministic greedy
        // wrapping; the final line is then shaped as one run.
        if (request_.letter_spacing_pixels != 0) {
            appendTrackedParagraph(paragraph, lines);
            return;
        }
        const std::vector<Token> tokens = tokenize(paragraph);
        Line line;
        std::vector<const Token*> pendingWhitespace;
        for (const Token& token : tokens) {
            if (token.whitespace) {
                pendingWhitespace.push_back(&token);
                continue;
            }
            float pendingAdvance = 0;
            for (const Token* whitespace : pendingWhitespace) {
                pendingAdvance += whitespace->shaped.advance;
            }
            const float proposed =
                line.advance + pendingAdvance + token.shaped.advance;
            if (
                !line.glyphs.empty()
                && proposed
                    > static_cast<float>(
                        request_.canvas_width_pixels
                    )
            ) {
                lines->push_back(std::move(line));
                line = Line{};
                pendingWhitespace.clear();
            } else {
                for (const Token* whitespace : pendingWhitespace) {
                    appendRun(
                        whitespace->shaped,
                        line.advance,
                        &line
                    );
                }
                pendingWhitespace.clear();
            }
            appendRun(token.shaped, line.advance, &line);
        }
        lines->push_back(std::move(line));
    }

    static void blendCoverage(
        uint8_t source,
        uint8_t* destination
    ) {
        *destination = static_cast<uint8_t>(
            source
                + (
                    static_cast<unsigned>(*destination)
                        * (255 - source)
                    + 127
                ) / 255
        );
    }

    void renderLine(
        const Line& line,
        float originX,
        float baselineY,
        size_t width,
        size_t height,
        std::vector<uint8_t>* coverage
    ) {
        FT_Set_Transform(face_, nullptr, nullptr);
        for (const Glyph& glyph : line.glyphs) {
            const int glyphX = static_cast<int>(
                std::floor(originX + glyph.x + 0.5f)
            );
            const int glyphY = static_cast<int>(
                std::floor(baselineY + glyph.y + 0.5f)
            );
            if (
                FT_Load_Glyph(face_, glyph.id, kLoadFlags) != 0
                || FT_Render_Glyph(
                    face_->glyph,
                    FT_RENDER_MODE_NORMAL
                ) != 0
            ) {
                continue;
            }
            const FT_Bitmap& bitmap = face_->glyph->bitmap;
            const int left =
                glyphX + static_cast<int>(face_->glyph->bitmap_left);
            const int top =
                glyphY - static_cast<int>(face_->glyph->bitmap_top);
            for (unsigned row = 0; row < bitmap.rows; ++row) {
                const int y = top + static_cast<int>(row);
                if (y < 0 || y >= static_cast<int>(height)) {
                    continue;
                }
                for (
                    unsigned column = 0;
                    column < bitmap.width;
                    ++column
                ) {
                    const int x = left + static_cast<int>(column);
                    if (x < 0 || x >= static_cast<int>(width)) {
                        continue;
                    }
                    const uint8_t source = bitmap.buffer[
                        row * static_cast<unsigned>(bitmap.pitch)
                            + column
                    ];
                    blendCoverage(
                        source,
                        &(*coverage)[
                            static_cast<size_t>(y) * width + x
                        ]
                    );
                }
            }
        }
    }

    static uint8_t channel(uint32_t rgba, int shift) {
        return static_cast<uint8_t>((rgba >> shift) & 0xFF);
    }

    static uint8_t canonical3(uint8_t value) {
        const int reduced = value >> 5;
        return static_cast<uint8_t>(
            (reduced * 255 + 3) / 7
        );
    }

    void buildSkiaAlphaMap(uint8_t mapping[256]) const {
        constexpr float gamma = 1.4f;
        const uint8_t red = channel(request_.foreground_rgba, 24);
        const uint8_t green = channel(
            request_.foreground_rgba,
            16
        );
        const uint8_t blue = channel(
            request_.foreground_rgba,
            8
        );
        const uint8_t luminance = static_cast<uint8_t>(
            (
                static_cast<unsigned>(red) * 54
                    + static_cast<unsigned>(green) * 183
                    + static_cast<unsigned>(blue) * 19
            ) >> 8
        );
        const float source =
            static_cast<float>(canonical3(luminance)) / 255.0f;
        const float destination = 1.0f - source;
        const float linearSource = std::pow(source, gamma);
        const float linearDestination =
            std::pow(destination, gamma);
        for (int coverage = 0; coverage < 256; ++coverage) {
            const float alpha =
                static_cast<float>(coverage) / 255.0f;
            const float linearOutput =
                linearSource * alpha
                    + (1.0f - alpha) * linearDestination;
            const float output = std::pow(
                linearOutput,
                1.0f / gamma
            );
            const float denominator = source - destination;
            const float corrected =
                std::abs(denominator) < (1.0f / 256.0f)
                    ? alpha
                    : (output - destination) / denominator;
            mapping[coverage] = static_cast<uint8_t>(
                std::clamp(
                    static_cast<int>(
                        std::lround(255.0f * corrected)
                    ),
                    0,
                    255
                )
            );
        }
    }

    std::vector<uint8_t> composite(
        const std::vector<uint8_t>& coverage
    ) const {
        const size_t pixelCount = coverage.size();
        std::vector<uint8_t> rgba(pixelCount * 4);
        uint8_t alphaMap[256] = {};
        buildSkiaAlphaMap(alphaMap);
        const uint8_t foreground[] = {
            channel(request_.foreground_rgba, 24),
            channel(request_.foreground_rgba, 16),
            channel(request_.foreground_rgba, 8),
        };
        const uint8_t background[] = {
            channel(request_.background_rgba, 24),
            channel(request_.background_rgba, 16),
            channel(request_.background_rgba, 8),
        };
        const unsigned paintAlpha =
            channel(request_.foreground_rgba, 0);
        for (size_t pixel = 0; pixel < pixelCount; ++pixel) {
            // The supplied background is a rasterization basis, not an
            // instruction for the UILabel to paint its entire bounds.
            // Leaving untouched pixels transparent preserves underlying
            // borders and shapes while edge pixels remain precomposited
            // exactly as Android rendered them.
            if (coverage[pixel] == 0) {
                rgba[pixel * 4] = 0;
                rgba[pixel * 4 + 1] = 0;
                rgba[pixel * 4 + 2] = 0;
                rgba[pixel * 4 + 3] = 0;
                continue;
            }
            const unsigned correctedAlpha =
                (
                    static_cast<unsigned>(
                        alphaMap[coverage[pixel]]
                    ) * paintAlpha
                ) / 255;
            for (int component = 0; component < 3; ++component) {
                rgba[pixel * 4 + component] =
                    static_cast<uint8_t>(
                        (
                            static_cast<unsigned>(
                                foreground[component]
                            ) * correctedAlpha
                                + static_cast<unsigned>(
                                    background[component]
                                ) * (255 - correctedAlpha)
                        ) / 255
                    );
            }
            rgba[pixel * 4 + 3] = 255;
        }
        return rgba;
    }

    const NileAndroidTextRequest& request_;
    FT_Library library_ = nullptr;
    FT_Face face_ = nullptr;
    hb_blob_t* blob_ = nullptr;
    hb_face_t* hbFace_ = nullptr;
    bool ready_ = false;
};

static void clearResult(NileAndroidTextResult* result) {
    std::memset(result, 0, sizeof(*result));
}

}  // namespace

extern "C" int32_t nile_android_text_render(
    const NileAndroidTextRequest* request,
    NileAndroidTextResult* result
) {
    if (result == nullptr) {
        return 1;
    }
    clearResult(result);
    if (
        request == nullptr
        || request->text_utf8 == nullptr
        || request->font_path_utf8 == nullptr
        || request->canvas_width_pixels <= 0
        || request->canvas_height_pixels <= 0
        || request->font_size_pixels <= 0
        || request->line_height_pixels <= 0
    ) {
        return 2;
    }
    TextRenderer renderer(*request);
    if (!renderer.ready()) {
        return 3;
    }
    std::vector<Line> lines = renderer.layout();
    std::vector<uint8_t> pixels = renderer.render(lines);
    const size_t byteCount = pixels.size();
    auto* allocation = static_cast<uint8_t*>(
        std::malloc(byteCount)
    );
    if (allocation == nullptr) {
        return 4;
    }
    std::memcpy(allocation, pixels.data(), byteCount);
    result->rgba = allocation;
    result->width_pixels = request->canvas_width_pixels;
    result->height_pixels = request->canvas_height_pixels;
    result->bytes_per_row = request->canvas_width_pixels * 4;
    result->line_count = static_cast<int32_t>(lines.size());
    for (const Line& line : lines) {
        result->maximum_line_width_pixels = std::max(
            result->maximum_line_width_pixels,
            static_cast<double>(line.advance)
        );
    }
    return 0;
}

extern "C" void nile_android_text_result_destroy(
    NileAndroidTextResult* result
) {
    if (result == nullptr) {
        return;
    }
    std::free(result->rgba);
    clearResult(result);
}

extern "C" const char* nile_android_text_renderer_version(void) {
    return "android-15-freetype-2.13.2-harfbuzz-8.2.2-minikin-skia";
}
