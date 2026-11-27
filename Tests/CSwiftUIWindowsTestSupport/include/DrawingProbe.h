#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
  int dpi, aware, pixel_errors, child_pixel_errors;
  int hover_events, position_changes, immediate_paints, clip_errors,
      atomic_errors;
  int damage_pixels, surface_pixels;
  int scope_errors;
  int group_errors;
  int expose_errors;
} drawing_probe_result;
drawing_probe_result drawing_probe(void);
int control_order_probe(void);
int input_reentry_probe(void);
typedef struct {
  int copies, pixel_errors, fallback_errors;
} scroll_probe_result;
scroll_probe_result scroll_probe(void);
int shadow_probe(const uint8_t *alpha, int width, int height, double inset,
                 double scale);
int editor_resize_probe(void);
int control_visible(void *control);
int control_clip_width(void *control);
int control_has_vscroll(void *control);
int control_is_multiline_edit(void *control);
int control_print_distinct_pixels(void *control);
uint32_t control_print_pixel(void *control, int px, int py);
void control_send_key(void *control, int vk);
void control_send_char(void *control, int ch);
int host_region_distinct_pixels(void *host, double x, double y, double w, double h);
void pump_pending_win32_messages(void);
uint32_t control_screen_pixel_in_window(void *root_window, void *control, int rel_x, int rel_y);
int control_offset_in_host_x(void *host, void *control);
int control_offset_in_host_y(void *host, void *control);
#ifdef __cplusplus
}
#endif
