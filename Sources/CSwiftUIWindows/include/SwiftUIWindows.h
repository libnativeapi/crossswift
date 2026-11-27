#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*sui_event_callback)(void *context, int64_t id, int event);
void sui_set_application_identifier(const char *identifier);
typedef struct {
  double width, height;
} sui_size;
typedef int (*sui_input_callback)(void *, int64_t, int, double, double, int,
                                  int);
void sui_surface_schedule(void *);
void sui_surface_request_wheel_update(void *surface);
void sui_surface_trace_update(void *, int begin);
void sui_surface_trace_duration(void *surface, int stage, double milliseconds);
void sui_surface_flush(void *);
void sui_surface_input(void *, sui_input_callback);
void sui_surface_edit(void *surface, void *edit, int64_t id,
                      uint64_t native_view);
void sui_surface_remove_edit(void *surface, void *edit);
void sui_edit_order(void *surface, void *edit);
void sui_edit_set_transparent(void *surface, void *edit, int transparent,
                              double sample_x, double sample_y,
                              const char *placeholder, uint32_t text_argb,
                              uint32_t placeholder_argb, int multiline);
void sui_surface_set_background(void *surface, uint32_t argb);
void sui_surface_set_window_shadow(void *surface, int enabled, int is_dark);
void sui_surface_flush_paint(void *surface);
void sui_surface_show_on_top(void *surface, int defer_paint);
void sui_surface_begin_pending_resize(void *surface, double logical_width,
                                      double logical_height);
void sui_surface_prerender_pending_resize(void *surface);
void sui_surface_commit_pending_resize(void *surface);
void sui_surface_flush_edits(void *surface);
void sui_surface_set_content_offset(void *surface, double offset_x,
                                    double offset_y);
void sui_surface_set_pending_offset(void *surface, double offset_x,
                                    double offset_y);
void sui_surface_custom_view(void *surface, void *view_hwnd,
                             uint64_t native_view);
void sui_surface_remove_custom_view(void *surface, void *view_hwnd);
void sui_custom_view_order(void *surface, void *view_hwnd);
void sui_edit_line_metrics(void *surface, void *edit, double *center,
                           double *height);
void sui_control_clip(void *, double, double, double, double);
void sui_surface_control_clip(void *surface, void *control, double x, double y,
                              double width, double height);
void sui_control_opacity(void *control, double opacity);
void sui_surface_pointer(void *, int event, double x, double y, int value);
int sui_surface_cursor(void *surface, double *x, double *y);

void *sui_surface_create(void *host, sui_event_callback callback, void *context,
                         uint64_t native_view);
void sui_surface_destroy(void *surface);
void sui_surface_begin(void *surface);
void sui_surface_shape(void *surface, double x, double y, double width,
                       double height, double radius, uint32_t fill,
                       uint32_t stroke, double stroke_width);
double sui_surface_scale(void *surface);
// Immutable masks are retained by published display lists after release.
void *sui_mask_create(const uint8_t *alpha, int width, int height);
void sui_mask_destroy(void *mask);
void sui_surface_mask(void *surface, void *mask, double x, double y,
                      double width, double height, uint32_t color);
void sui_surface_text(void *surface, double x, double y, double width,
                      double height, const char *text, const char *family,
                      double size, double weight, double line_spacing,
                      uint32_t color);
void sui_surface_path(void *surface, const double *commands, int count,
                      uint32_t fill, uint32_t stroke, double width, int clip);
void sui_surface_translation(void *surface, double x, double y);
void sui_surface_transform(void *surface, double cx, double cy, double rotation,
                           double sx, double sy);
void sui_surface_gradient(void *surface, double x, double y, double width,
                          double height, double sx, double sy, double ex,
                          double ey, const uint32_t *colors, int count);
void sui_surface_gradient_ex(void *surface, int kind, double x, double y,
                             double width, double height, double sx, double sy,
                             double ex, double ey, double start_param,
                             double end_param, const uint32_t *colors,
                             const double *locations, int count);
void sui_surface_layer_begin(void *surface, double x, double y, double width,
                             double height, double opacity, double blur_radius,
                             double brightness, double contrast);
void sui_surface_layer_end(void *surface);
void sui_surface_image(void *surface, const char *file, double x, double y,
                       double width, double height);
void sui_register_memory_image(const char *key, const uint8_t *bytes, int count);
void sui_surface_clip(void *surface, double x, double y, double width,
                      double height, double radius);
void sui_surface_restore(void *surface);
void sui_surface_scroll_begin(void *surface, int64_t id, int64_t revision,
                              double x, double y, double width, double height,
                              double content_x, double content_y);
void sui_surface_scroll_end(void *surface);
int64_t sui_surface_reused_pixels(void *surface);
typedef struct {
  double raster_ms, blit_ms;
  int paints;
} sui_paint_stats;
sui_paint_stats sui_surface_paint_stats(void *surface);
sui_paint_stats sui_surface_total_paint_stats(void *surface);
double sui_surface_publish_time(void *surface, int stage);
void sui_control_tab_visible(void *surface, void *control, int visible);
void sui_control_set_passthrough(void *surface, void *control, int passthrough);
void sui_surface_end(void *surface);
void sui_control_frame(void *surface, void *control, double x, double y,
                       double width, double height);
// Group native controls under a scrolling content window. Coordinates remain
// relative to the surface; nested groups and clipping are handled by the
// bridge.
void sui_controls_begin(void *surface);
void sui_controls_push(void *surface, int64_t id, double x, double y,
                       double width, double height, double clip_x,
                       double clip_y, double clip_width, double clip_height);
void sui_controls_pop(void *surface);
void sui_surface_button(void *surface, void *button, int64_t id,
                        int custom_draw, uint64_t native_view);
void sui_surface_remove_button(void *surface, void *button);
void sui_button_update(void *surface, void *button, double radius,
                       const char *help, double x, double y, double width,
                       double height);
void sui_button_set_accessibility(void *button, const char *label,
                                  const char *description);
void sui_surface_focus_next(void *surface, void *current, int backward);
sui_size sui_measure_text(const char *text, const char *family, double size,
                          double weight);
// Sends BM_CLICK to one owned native control. Does not post global input.
void sui_button_activate(void *button);

void *sui_offscreen_create(int width, int height);
void sui_offscreen_shape(void *canvas, double x, double y, double width,
                         double height, double radius, uint32_t fill,
                         uint32_t stroke, double stroke_width);
void sui_offscreen_path(void *canvas, const double *commands, int count,
                        uint32_t fill, uint32_t stroke, double stroke_width);
void sui_offscreen_text(void *canvas, double x, double y, double width,
                        double height, const char *text, double size,
                        uint32_t color);
uint8_t *sui_offscreen_finish_png(void *canvas, int *out_len);
void sui_free_bytes(void *ptr);
void sui_window_set_dark_mode(void *window, int dark);

// Native owned popup window helpers (`.popover`, `._menuPopover`, `.contextMenu`).
typedef void (*sui_popup_event_callback)(void *context, int event,
                                         void *other_hwnd);
typedef struct {
  double anchor_x, anchor_y, anchor_w, anchor_h;
  double work_x, work_y, work_w, work_h;
  int work_px_left, work_px_top;
  double scale;
} sui_popup_metrics;

typedef struct {
  int is_visible;
  int is_popup_style;
  int is_tool_window;
  int has_app_window;
  int is_topmost;
  int left, top, width, height;
  void *owner_hwnd;
} sui_popup_window_info;

void *sui_surface_root_hwnd(void *surface);
int sui_hwnd_is_visible(void *hwnd);
int sui_popup_measure_anchor(void *surface, double x, double y, double w,
                             double h, sui_popup_metrics *out_metrics);
void sui_popup_configure(void *popup_hwnd, void *owner_hwnd,
                         void *popup_surface, int is_dark,
                         sui_popup_event_callback callback, void *context);
void sui_popup_unconfigure(void *popup_hwnd);
void sui_popup_owner_attach(void *owner_hwnd, sui_popup_event_callback callback,
                            void *context);
void sui_popup_owner_detach(void *owner_hwnd);
void sui_popup_owner_set_popups(void *owner_hwnd, void *const *popup_hwnds,
                                int count, int blocks_background);
void sui_popup_set_bounds_px(void *popup_hwnd, void *owner_hwnd, int x, int y,
                             int width, int height, int show, int activate);
void sui_popup_restore_owner_focus(void *popup_hwnd, void *owner_hwnd);
int sui_popup_get_window_info(void *hwnd, sui_popup_window_info *out_info);
#ifdef __cplusplus
}
#endif
