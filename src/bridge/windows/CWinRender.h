// Drawing for omni's Windows backend: Direct2D for shapes and images, DirectWrite
// for text, WIC for decoding. Every view is drawn by Swift (src/ui/windows) into
// one render target per window; only text inputs, pickers and web views are
// Win32 controls of their own.
//
// Coordinates are DIPs (points): a target begun with the window's DPI scales
// them to pixels. Colours are straight (non-premultiplied) RGBA, 0...1.
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: Targets

/// A render target for a window's client area.
void* omni_r_target_create(void* hwnd);
void omni_r_target_destroy(void* target);
/// The client area's size in pixels.
void omni_r_target_resize(void* target, uint32_t pixel_width, uint32_t pixel_height);
void omni_r_begin(void* target, float dpi);
/// 1 when the device was lost and the target must be made again.
int omni_r_end(void* target);
void omni_r_clear(void* target, float r, float g, float b, float a);

/// The transform from points to the target: a b c d tx ty, as D2D1_MATRIX_3X2_F.
void omni_r_set_transform(void* target, float a, float b, float c, float d, float tx, float ty);
/// Clips what follows to a rectangle, with rounded corners when radius > 0.
void omni_r_push_clip(void* target, float x, float y, float w, float h, float radius);
void omni_r_pop_clip(void* target);
/// What follows is composited at this opacity.
void omni_r_push_opacity(void* target, float opacity);
void omni_r_pop_opacity(void* target);

// MARK: Shapes

void omni_r_fill_rrect(void* target, float x, float y, float w, float h, float radius,
                       float r, float g, float b, float a);
void omni_r_stroke_rrect(void* target, float x, float y, float w, float h, float radius, float width,
                         float r, float g, float b, float a);
void omni_r_fill_ellipse(void* target, float cx, float cy, float rx, float ry,
                         float r, float g, float b, float a);
void omni_r_stroke_ellipse(void* target, float cx, float cy, float rx, float ry, float width,
                           float r, float g, float b, float a);
void omni_r_line(void* target, float x1, float y1, float x2, float y2, float width,
                 float r, float g, float b, float a);
/// A linear gradient over a rounded rectangle, from (x0, y0) to (x1, y1).
/// `stops` is `count` runs of position, r, g, b, a.
void omni_r_gradient_rrect(void* target, float x, float y, float w, float h, float radius,
                           float x0, float y0, float x1, float y1, const float* stops, int count);

// MARK: Paths

void* omni_r_path_create(void);
void omni_r_path_move(void* path, float x, float y);
void omni_r_path_line(void* path, float x, float y);
void omni_r_path_quad(void* path, float cx, float cy, float x, float y);
void omni_r_path_cubic(void* path, float c1x, float c1y, float c2x, float c2y, float x, float y);
/// An elliptical arc to (x, y), as SVG's.
void omni_r_path_arc(void* path, float x, float y, float rx, float ry, float rotation, int large, int clockwise);
void omni_r_path_close(void* path);
void omni_r_path_fill(void* target, void* path, float r, float g, float b, float a);
void omni_r_path_stroke(void* target, void* path, float width, float r, float g, float b, float a);
void omni_r_path_release(void* path);

// MARK: Text

/// A laid-out paragraph. `family` may be NULL (Segoe UI Variable, else Segoe UI).
/// align: 0 leading, 1 center, 2 trailing. wrap: 0 one line, 1 words.
/// line_limit: 0 none, else at most that many lines, the last trimmed.
/// trim: 0 clip, 1 tail ellipsis, 2 head, 3 middle (ellipsis at the end: DirectWrite trims ends only).
void* omni_t_layout(const uint16_t* text, int length, const uint16_t* family, float size, int weight,
                    int italic, float max_width, int align, int wrap, int line_limit, int trim,
                    float letter_spacing, float line_spacing, int strikethrough, int underline);
/// The text's own size, and its first line's baseline from the top.
void omni_t_metrics(void* layout, float* width, float* height, float* baseline);
void omni_t_draw(void* target, void* layout, float x, float y, float r, float g, float b, float a);
void omni_t_release(void* layout);
/// Makes a font file's families available to omni_t_layout. 1 on success.
int omni_t_register_font(const uint16_t* path);

// MARK: Images

/// Decodes a file (PNG, JPEG, ICO, BMP, GIF's first frame) or bytes in memory.
void* omni_i_load_file(const uint16_t* path, uint32_t* width, uint32_t* height);
void* omni_i_load_memory(const void* data, uint32_t length, uint32_t* width, uint32_t* height);
/// From 32-bit straight RGBA rows.
void* omni_i_from_rgba(const void* pixels, uint32_t width, uint32_t height);
void omni_i_draw(void* target, void* image, float x, float y, float w, float h, float opacity, int smooth);
void omni_i_release(void* image);

// MARK: The main queue

/// libdispatch's main-queue event, signalled when work is queued for the main thread.
void* omni_main_queue_handle(void);
/// Runs what is queued for the main thread.
void omni_main_queue_drain(void);

#ifdef __cplusplus
}
#endif
