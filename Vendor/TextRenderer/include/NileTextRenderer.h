#ifndef NILE_TEXT_RENDERER_H
#define NILE_TEXT_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum NileTextAlignment {
    NILE_TEXT_ALIGNMENT_LEADING = 0,
    NILE_TEXT_ALIGNMENT_CENTER = 1,
    NILE_TEXT_ALIGNMENT_TRAILING = 2,
} NileTextAlignment;

typedef struct NileTextRequest {
    const char* text_utf8;
    const char* font_path_utf8;
    int32_t canvas_width_pixels;
    int32_t canvas_height_pixels;
    double font_size_pixels;
    float font_weight;
    double letter_spacing_pixels;
    double line_height_pixels;
    double first_baseline_pixels;
    uint32_t foreground_rgba;
    uint32_t background_rgba;
    NileTextAlignment alignment;
} NileTextRequest;

typedef struct NileTextResult {
    uint8_t* rgba;
    int32_t width_pixels;
    int32_t height_pixels;
    int32_t bytes_per_row;
    int32_t line_count;
    double maximum_line_width_pixels;
} NileTextResult;

int32_t nile_text_render(
    const NileTextRequest* request,
    NileTextResult* result
);

void nile_text_result_destroy(NileTextResult* result);

const char* nile_text_renderer_version(void);

#ifdef __cplusplus
}
#endif

#endif
