#pragma once
#include <stdbool.h>
#include <stdint.h>

// Omni Event Constants mapped to Win32 Messages
#define OMNI_WM_CLOSE   1
#define OMNI_WM_SIZE    2
#define OMNI_WM_PAINT   3
#define OMNI_WM_COMMAND 4

typedef void (*OmniWindowEventCallback)(void* hwnd, uint32_t event_type, uint64_t w_param, int64_t l_param);

void omni_win_init(void);
void* omni_win_create_window(const char* title, int width, int height, OmniWindowEventCallback callback);
void omni_win_show(void* hwnd);
void omni_win_set_resizable(void* hwnd, int resizable);
void omni_win_hide(void* hwnd);
void omni_win_destroy(void* hwnd);

void omni_win_run_loop(void);
void omni_win_quit_loop(void);

void* omni_win_create_button(void* parent_hwnd, const char* title, int x, int y, int w, int h, int control_id);

void omni_win_set_text(void* hwnd, const char* text);
void omni_win_add_child(void* parent_hwnd, void* child_hwnd);

void* omni_win_create_canvas(void* parent_hwnd, int x, int y, int w, int h, int control_id);
void omni_win2d_attach(void* hwnd);
void omni_win2d_detach(void* hwnd);
void omni_win2d_begin_draw(void* hwnd);
void omni_win2d_end_draw(void* hwnd);

// Drawing Operations (r, g, b, a are 0.0 to 1.0)
void omni_win2d_clear(void* hwnd, float r, float g, float b, float a);
void omni_win2d_fill_rect(void* hwnd, float x, float y, float w, float h, float r, float g, float b, float a);
void omni_win2d_draw_rect(void* hwnd, float x, float y, float w, float h, float r, float g, float b, float a, float stroke_width);

void* omni_win_create_divider(void* parent_hwnd, int x, int y, int w, int h, bool is_vertical);

void* omni_win_create_frame(void* parent_hwnd, double width, double height);
void omni_win_set_frame(void* hwnd, double width, double height);
void omni_win_fill_parent(void* child_hwnd, void* parent_hwnd);

void omni_win_bind_tap(void* hwnd, void* callback_ptr);
void omni_win_bind_drag(void* hwnd, void* callback_ptr);
void omni_win_bind_scroll(void* hwnd, void* callback_ptr);
void omni_win_set_cursor(void* hwnd, const char* cursor_name);

void* omni_win_create_geometry_reader(void* parent_hwnd);
void omni_win_get_bounds(void* hwnd, double* width, double* height);

void* omni_win_create_hstack(void* parent_hwnd, double spacing);
void omni_win_set_stack_spacing(void* hwnd, double spacing);
void* omni_win_create_image(void* parent_hwnd, const char* name, bool is_system);

void* omni_win_create_progress(void* parent_hwnd, int x, int y, int w, int h);

void* omni_win_create_scrollview(void* parent_hwnd, bool is_vertical);
void omni_win_scrollview_set_offset(void* hwnd, double offset);
double omni_win_scrollview_get_offset(void* hwnd);
void omni_win_scrollview_update_content_size(void* hwnd, double content_width, double content_height);

void* omni_win_create_textfield(void* parent_hwnd, const char* placeholder, bool is_secure);
void omni_win_textfield_get_text(void* hwnd, char* buffer, int buffer_size);

void* omni_win_create_clip_view(void* parent_hwnd);
void omni_win_set_clip_radius(void* hwnd, double radius, bool is_circular);

void* omni_win_create_slider(void* parent_hwnd, int x, int y, int w, int h);
void omni_win_slider_set_range(void* hwnd, int min_val, int max_val);
void omni_win_slider_set_value(void* hwnd, int value);
int omni_win_slider_get_value(void* hwnd);

void* omni_win_create_spacer(void* parent_hwnd, double min_length);
void omni_win_spacer_set_min_length(void* hwnd, double min_length);

void* omni_win_create_splitview(void* parent_hwnd, bool is_vertical);
void omni_win_splitview_set_orientation(void* hwnd, bool is_vertical);

void* omni_win_create_swipe_view(void* parent_hwnd);
void omni_win_swipe_view_set_threshold(void* hwnd, double threshold_pixels);

// Implemented in CWinBridge.cxx. These were previously declared in the Android
// JNI header, where Picker+Windows.swift could not see them.
void* omni_win_create_picker(void* parent_hwnd, int x, int y, int w, int h, int control_id);
void omni_win_picker_clear(void* hwnd);
void omni_win_picker_add_item(void* hwnd, const char* label);
void omni_win_picker_set_selection(void* hwnd, int index);
int omni_win_picker_get_selection(void* hwnd);
