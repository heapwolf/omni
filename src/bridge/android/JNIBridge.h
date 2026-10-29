// src/lib/CAndroid/JNIBridge.h
#ifndef OMNI_JNIBRIDGE_H
#define OMNI_JNIBRIDGE_H

#ifdef __ANDROID__
#include <jni.h>
#include <stdint.h>

extern JavaVM* global_jvm;
extern jobject global_activity;

JNIEnv* omni_get_env(void);
jobject omni_jni_activity(void);

extern const int MATCH_PARENT;
extern const int WRAP_CONTENT;
/// A width or height the caller does not want to change.
extern const int OMNI_LAYOUT_KEEP;

extern const int GRAVITY_LEFT;
extern const int GRAVITY_RIGHT;
extern const int GRAVITY_CENTER_HORIZONTAL;
extern const int GRAVITY_CENTER_VERTICAL;
extern const int GRAVITY_CENTER;

void omni_jni_init(JNIEnv *env, jobject activity);

jobject omni_jni_create_view(JNIEnv *env, const char* classPath);
void omni_jni_call_void_method_string(JNIEnv *env, jobject obj, const char* methodName, const char* arg);
void omni_jni_call_void_method_int(JNIEnv *env, jobject obj, const char* methodName, int arg);
void omni_jni_call_void_method_bool(JNIEnv *env, jobject obj, const char* methodName, int arg);

void omni_jni_add_view(JNIEnv *env, jobject parent, jobject child);
void omni_jni_remove_view(JNIEnv *env, jobject child);
void omni_jni_move_child(JNIEnv *env, jobject parent, jobject child, int index);
void omni_jni_animate_replacement(JNIEnv *env, jobject scene_root, jobject parent, jobject arriving,
                                  jobject leaving, int duration_ms, int curve,
                                  float in_x, float in_y, int in_fade,
                                  float out_x, float out_y, int out_fade);
void omni_jni_set_layout_params(JNIEnv *env, jobject view, int width, int height);
void omni_jni_set_linear_layout_params(JNIEnv *env, jobject view, int width, int height, float weight);
void omni_jni_set_stack_child(JNIEnv *env, jobject child, int vertical, int fillsCrossAxis, float weight);
/// A weighted stack child measured at its content's size along the stack, the
/// surplus shared on top, rather than from zero.
void omni_jni_size_to_content(JNIEnv *env, jobject child, int vertical);
int omni_jni_linear_orientation(JNIEnv *env, jobject view);
void omni_jni_resolve_child_size(JNIEnv *env, jobject child, int fillsWidth, int fillsHeight);
void omni_jni_set_spacer_extent(JNIEnv *env, jobject view, int vertical);
void omni_jni_dump_view_tree(JNIEnv *env, jobject root);
void omni_jni_install_root(JNIEnv *env, jobject activity, jobject root);

void omni_jni_set_text_color(JNIEnv *env, jobject view, int a, int r, int g, int b);
void omni_jni_set_text_spacing(JNIEnv *env, jobject view, float linePoints, float letterEm);
void omni_jni_set_background_color(JNIEnv *env, jobject view, int a, int r, int g, int b);
void omni_jni_set_box(JNIEnv *env, jobject view, int hasFill,
                      int fa, int fr, int fg, int fb,
                      int strokePoints, int sa, int sr, int sg, int sb);
void omni_jni_set_padding(JNIEnv *env, jobject view, int left, int top, int right, int bottom);
void omni_jni_set_alpha(JNIEnv *env, jobject view, float alpha);
/// .offset (points) and .scaleEffect, drawn without moving the layout, as on iOS.
void omni_jni_set_transform(JNIEnv *env, jobject view, float x, float y, float scale);
/// Image's content mode: 1 crops to fill the view, 0 fits it whole.
void omni_jni_set_image_scale(JNIEnv *env, jobject view, int fill);
/// .shadow: elevation (points) on the container's content, the container left flat.
void omni_jni_set_shadow(JNIEnv *env, jobject container, float radius);
void omni_jni_set_elevation(JNIEnv *env, jobject view, float elevation);
void omni_jni_set_text_size(JNIEnv *env, jobject view, float size);
void omni_jni_set_monospace(JNIEnv *env, jobject view, int isMonospaced);
int omni_jni_register_font(JNIEnv *env, const char* family, const char* path);
void omni_jni_set_typeface(JNIEnv *env, jobject view, const char* family, int weight, int italic, int monospaced);
void omni_jni_set_gravity(JNIEnv *env, jobject view, int gravity);
void omni_jni_set_child_gravity(JNIEnv *env, jobject child, int gravity);
void omni_jni_begin_transition(JNIEnv *env, jobject root, long durationMs, int curve);
void omni_jni_begin_navigation_transition(JNIEnv *env, jobject root, int isPush, long durationMs);

void omni_jni_set_on_click(JNIEnv *env, jobject view, void* swift_ptr);
void omni_jni_set_on_press(JNIEnv *env, jobject view, void* swift_ptr);
void omni_jni_haptic(JNIEnv *env, int kind);
int omni_jni_reduce_motion(JNIEnv *env);
void omni_jni_set_glass(JNIEnv *env, jobject view, int fill, int stroke, float radius, int circular);
void omni_jni_set_minimum_size(JNIEnv *env, jobject view, float width, float height);
void omni_jni_copy_text(JNIEnv *env, const char* text);
char* omni_jni_pasted_text(JNIEnv *env);
void omni_jni_send_text(JNIEnv *env, const char* method, const char* text);
void omni_jni_dismiss_keyboard(JNIEnv *env);
void omni_jni_set_keyboard_covers(JNIEnv *env, int covers);
void omni_jni_set_accessibility(JNIEnv *env, jobject view, const char* label, const char* value, const char* hint, int element, int traits);
void omni_jni_set_accessibility_hidden(JNIEnv *env, jobject view, int hidden);
void omni_jni_set_image(JNIEnv *env, jobject view, const char* name, int isSystem);
/// In-memory counterpart: decodes `data` rather than resolving a resource name,
/// for Image(data:).
void omni_jni_set_image_bytes(JNIEnv *env, jobject view, const uint8_t* data, int length);
void omni_jni_tint_symbols(JNIEnv *env, jobject view, int a, int r, int g, int b);
void omni_jni_set_autofill_hint(JNIEnv *env, jobject view, const char* hint);
void omni_jni_set_stroke(JNIEnv *env, jobject view, int kind, float radius, float width,
                         int inset, int a, int r, int g, int b);
void omni_jni_set_linear_gradient(JNIEnv *env, jobject view, const int32_t* colors, int count,
                                  float start_x, float start_y, float end_x, float end_y);
void omni_jni_set_linear_layout_spacing(JNIEnv *env, jobject view, int spacing);

void omni_jni_set_checked(JNIEnv *env, jobject view, int isChecked);
void omni_jni_attach_on_checked(JNIEnv *env, jobject view, void* swift_ptr);

void omni_jni_attach_text_watcher(JNIEnv *env, jobject view, void* swift_ptr);
void omni_jni_detach_text_field(JNIEnv *env, jobject view);
char* omni_jni_get_text(JNIEnv *env, jobject view);
void omni_jni_set_secure_text(JNIEnv *env, jobject view);
void omni_jni_set_multiline(JNIEnv *env, jobject view);

// Add under Event Routing if not already there
void omni_jni_attach_on_seek_bar_change(JNIEnv *env, jobject view, void* swift_ptr);

void omni_jni_attach_frame_gestures(JNIEnv *env, jobject view, void* tap_ptr, void* tap_loc_ptr, void* drag_ptr, void* drag_end_ptr, void* scroll_ptr);
void omni_jni_attach_swipe_gestures(JNIEnv *env, jobject view, void* left_ptr, void* right_ptr);

void omni_jni_set_clip_radius(JNIEnv *env, jobject view, float radius, int isCircular);

void omni_jni_attach_on_scroll_change(JNIEnv *env, jobject view, void* swift_ptr);
jobject omni_jni_present_sheet(JNIEnv *env, jobject content, void* swift_ptr,
                               float fraction, float height_dp, float corner_radius_dp,
                               int shows_indicator, int is_dismissable, int surface_argb);
jobject omni_jni_present_alert(JNIEnv *env, jobject anchor, const char* title, const char* message,
                               const char* titles, const char* roles, void* swift_ptr);
void omni_jni_dismiss_dialog(JNIEnv *env, jobject dialog);
void omni_jni_attach_on_layout_change(JNIEnv *env, jobject view, void* swift_ptr);
void omni_jni_scroll_to(JNIEnv *env, jobject view, int x, int y);
/// Paged (a page at a time, told to page_ptr's EventHandlerInt) and/or not moved by a drag.
void omni_jni_set_scroll_behavior(JNIEnv *env, jobject view, int paging, int disabled, void* page_ptr);
/// Slides a paged scroll view to `page`; at once if it has no size yet.
void omni_jni_show_page(JNIEnv *env, jobject view, int page);
/// PageScrubber: move by `pages`, let go at `velocity` pages a second, or slide to `page`.
void omni_jni_scrub_pages(JNIEnv *env, jobject view, float pages);
void omni_jni_release_scrub(JNIEnv *env, jobject view, float velocity);
void omni_jni_go_to_page(JNIEnv *env, jobject view, int page);
/// The scroll view's size and its content's, in dp, to two EventHandlerFloat2s after each layout.
void omni_jni_attach_scroll_sizes(JNIEnv *env, jobject view, void* size_ptr, void* content_ptr);

void omni_jni_set_spinner_options(JNIEnv *env, jobject view, const char* options_joined);
void omni_jni_attach_on_item_selected(JNIEnv *env, jobject view, void* swift_ptr);

void omni_jni_canvas_reset(JNIEnv *env, jobject view);
void omni_jni_canvas_begin_path(JNIEnv *env, jobject view);
void omni_jni_canvas_move_to(JNIEnv *env, jobject view, float x, float y);
void omni_jni_canvas_line_to(JNIEnv *env, jobject view, float x, float y);
void omni_jni_canvas_cubic_to(JNIEnv *env, jobject view, float c1x, float c1y, float c2x, float c2y, float x, float y);
void omni_jni_canvas_set_stroke_color(JNIEnv *env, jobject view, int a, int r, int g, int b);
void omni_jni_canvas_set_fill_color(JNIEnv *env, jobject view, int a, int r, int g, int b);
void omni_jni_canvas_set_stroke_width(JNIEnv *env, jobject view, float width);
void omni_jni_canvas_stroke(JNIEnv *env, jobject view);
void omni_jni_canvas_fill(JNIEnv *env, jobject view);
void omni_jni_canvas_invalidate(JNIEnv *env, jobject view);

int omni_jni_check_self_permission(JNIEnv *env, jobject activity, const char* permission);
void omni_jni_request_permission(JNIEnv *env, jobject activity, const char* permission, int requestCode, void* swift_ptr);
int omni_jni_launch_camera_capture(JNIEnv *env, jobject activity, const char* outputPath, int requestCode, int frontFacing, void* swift_ptr);
void omni_jni_launch_image_pick(JNIEnv *env, jobject activity, int requestCode, void* swift_ptr);
uint8_t* omni_jni_read_uri(JNIEnv *env, jobject activity, const char* uri, int* outLength);
char* omni_jni_cache_dir(JNIEnv *env, jobject activity);
char* omni_jni_files_dir(JNIEnv *env, jobject activity);
uint8_t* omni_jni_encode_image(JNIEnv *env, const uint8_t* input, int inputLength,
                               int maxDimension, const char* format, double quality, int* outLength);
void omni_jni_image_dimensions(JNIEnv *env, const uint8_t* data, int length, int* outWidth, int* outHeight);


void omni_jni_call_void_method(JNIEnv *env, jobject obj, const char* methodName);
/// Hands the Swift WebEventHandler's address to the view as a jlong, which the
/// int form would truncate.
void omni_jni_web_attach(JNIEnv *env, jobject view, void* swift_ptr);
void omni_jni_web_load_html(JNIEnv *env, jobject view, const char* html, const char* baseURL);

#endif // __ANDROID__

void omni_jni_log(const char *tag, const char *message);


// MARK: - Keystore (OmniKeychain)
int      omni_jni_keystore_set(JNIEnv *env, jobject context, const char *key,
                               const uint8_t *value, int length, int level);
uint8_t* omni_jni_keystore_get(JNIEnv *env, jobject context, const char *key, int *outLength);
int      omni_jni_keystore_has(JNIEnv *env, jobject context, const char *key);
int      omni_jni_keystore_delete(JNIEnv *env, jobject context, const char *key);

// MARK: - Device keys (OmniKeychain)
/// x9.63, 65 bytes; malloc'd, the caller frees. NULL on failure.
uint8_t* omni_jni_device_key_public(JNIEnv *env, jobject context, const char *tag, int *outLength);
/// DER; malloc'd, the caller frees. NULL on failure.
uint8_t* omni_jni_device_key_sign(JNIEnv *env, jobject context, const char *tag,
                                  const uint8_t *message, int length, int *outLength);
int      omni_jni_device_key_delete(JNIEnv *env, jobject context, const char *tag);

// MARK: - Approval keys (OmniKeychain)
/// 1 if a strong biometric is usable, else 0.
int      omni_jni_approval_biometry(JNIEnv *env, jobject context);
int      omni_jni_approval_key_has(JNIEnv *env, jobject context, const char *tag);
/// Replaces any key. x9.63, malloc'd, or NULL.
uint8_t* omni_jni_approval_key_create(JNIEnv *env, jobject context, const char *tag, int *outLength);
int      omni_jni_approval_key_delete(JNIEnv *env, jobject context, const char *tag);
/// Prompts, then signs. DER, malloc'd, or NULL with `*outStatus`: 1 cancelled,
/// 2 invalidated, 3 not found, 4 failed. Blocks: call on its own thread.
uint8_t* omni_jni_approval_key_sign(const char *tag, const uint8_t *message, int length,
                                    const char *title, const char *reason, const char *cancel,
                                    int *outLength, int *outStatus);

/// Play Integrity (OmniKeychain): a token for `requestHash`, malloc'd, or NULL
/// when the app wasn't built with it or it failed. Blocks: call it on a
/// thread of its own, which this attaches to the VM and detaches again.
char*    omni_jni_attest_token(const char *requestHash);

#endif // OMNI_JNIBRIDGE_H