#include "DrawingProbe.h"
#include "SwiftUIWindows.h"
#include <nativeapi.h>
#include <windows.h>

#include <cmath>
#include <commctrl.h>

namespace {
struct Probe {
  drawing_probe_result result{};
  void *surface = nullptr;
  HWND host = nullptr, button = nullptr;
  bool track = false;
  int clicks = 0;
};
LRESULT CALLBACK Observe(HWND hwnd, UINT message, WPARAM wp, LPARAM lp,
                         UINT_PTR, DWORD_PTR data) {
  auto *probe = reinterpret_cast<Probe *>(data);
  if (message == WM_COMMAND && HIWORD(wp) == BN_CLICKED)
    ++probe->clicks;
  if (probe->track) {
    if (message == WM_WINDOWPOSCHANGED)
      ++probe->result.position_changes;
    if (message == WM_PAINT)
      ++probe->result.immediate_paints;
  }
  return DefSubclassProc(hwnd, message, wp, lp);
}
void Frame(Probe &p, bool hover, double clip_width = 80) {
  sui_surface_begin(p.surface);
  sui_surface_shape(p.surface, 0, 0, 1000, 1000, 0, 0xFF102030, 0, 0);
  sui_surface_shape(p.surface, 20, 20, 80, 30, 0,
                    hover ? 0xFF804020 : 0xFF208040, 0, 0);
  sui_surface_text(p.surface, 25, 20, 70, 30, "Hover", "Segoe UI", 14, 400, 0,
                   0xFFFFFFFF);
  sui_button_update(p.surface, p.button, 0, "", 0, 0, clip_width, 30);
  sui_surface_end(p.surface);
}
void Event(void *context, int64_t, int event) {
  auto &p = *static_cast<Probe *>(context);
  if (event == 1 || event == 2) {
    ++p.result.hover_events;
    Frame(p, event == 1);
  }
}
struct Capture {
  HDC dc;
  HBITMAP bitmap;
  HGDIOBJ old;
  Capture(HWND hwnd) {
    RECT rect;
    GetClientRect(hwnd, &rect);
    HDC screen = GetDC(hwnd);
    dc = CreateCompatibleDC(screen);
    bitmap = CreateCompatibleBitmap(screen, rect.right, rect.bottom);
    old = SelectObject(dc, bitmap);
    ReleaseDC(hwnd, screen);
    SendMessageW(hwnd, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(dc),
                 PRF_CLIENT);
  }
  ~Capture() {
    SelectObject(dc, old);
    DeleteObject(bitmap);
    DeleteDC(dc);
  }
};
} // namespace
int control_visible(void *control) {
  return (GetWindowLongPtrW(static_cast<HWND>(control), GWL_STYLE) & WS_VISIBLE) != 0;
}

int control_clip_width(void *control) {
  RECT box{};
  const int kind = GetWindowRgnBox(static_cast<HWND>(control), &box);
  if (kind == ERROR || kind == NULLREGION)
    return 0;
  return int(box.right - box.left);
}

int editor_resize_probe(void) {
  HWND host = CreateWindowExW(0, L"STATIC", L"Editor resize regression",
                              WS_OVERLAPPEDWINDOW, 0, 0, 1000, 500, nullptr,
                              nullptr, GetModuleHandleW(nullptr), nullptr);
  void *surface = sui_surface_create(host, nullptr, nullptr, 0);
  native_text_field_t field = native_text_field_create("");
  native_text_field_set_multiline(field, true);
  native_text_field_set_bordered(field, false);
  native_text_field_set_font_family(field, "Segoe UI");
  native_text_field_set_font_size(field, 16.0 * 72.0 / 96.0);
  native_text_field_set_font_weight(field, 400);
  native_text_field_set_text_color(field, {0x10, 0x20, 0x30, 0xFF});
  native_view_set_background_color(field, {0xFA, 0xF9, 0xF6, 0xFF});
  auto editor = static_cast<HWND>(native_view_get_native_object(field));
  sui_surface_edit(surface, editor, 10, field);
  HWND sidebar_button = nullptr;
  const double scale = sui_surface_scale(surface);
  auto px = [scale](double value) { return int(std::round(value * scale)); };
  auto frame = [&](double sidebar) {
    // Collapsing navigation replaces labelled controls with icon controls.
    // That publication validates stale child damage before scheduling repaint.
    if (sidebar_button) {
      sui_surface_remove_button(surface, sidebar_button);
      DestroyWindow(sidebar_button);
    }
    sidebar_button = CreateWindowExW(
        0, L"BUTTON", L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0,
        px(sidebar), px(30), host, nullptr, GetModuleHandleW(nullptr), nullptr);
    sui_surface_button(surface, sidebar_button, 12, 1, 0);
    sui_surface_begin(surface);
    sui_surface_shape(surface, 0, 0, 1000, 500, 0, 0xFFFAF9F6, 0, 0);
    sui_surface_shape(surface, 0, 0, sidebar, 300, 0, 0xFF102030, 0, 0);
    sui_controls_begin(surface);
    sui_controls_push(surface, 11, sidebar, 0, 600 - sidebar, 300,
                       sidebar, 0, 600 - sidebar, 300);
    sui_control_frame(surface, editor, sidebar + 20, 40, 560 - sidebar, 60);
    sui_edit_order(surface, editor);
    sui_control_clip(editor, 0, 0, 560 - sidebar, 60);
    sui_controls_pop(surface);
    sui_surface_end(surface);
  };
  frame(172);
  ShowWindow(host, SW_SHOWNOACTIVATE);
  SetWindowPos(host, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  RedrawWindow(host, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW);
  int errors = 0;
  const double sidebars[] = {48., 172., 48.};
  for (double sidebar : sidebars) {
    frame(sidebar);
    // Process only the damage published by the renderer, not a full expose.
    RedrawWindow(host, nullptr, nullptr, RDW_UPDATENOW | RDW_ALLCHILDREN);
    HDC screen = GetDC(host);
    for (int y = px(40); y < px(98); ++y)
      for (int x = px(sidebar + 20); x < px(190); ++x)
        if (GetPixel(screen, x, y) != RGB(250, 249, 246)) ++errors;
    ReleaseDC(host, screen);
  }
  sui_surface_remove_button(surface, sidebar_button);
  DestroyWindow(sidebar_button);
  sui_surface_remove_edit(surface, editor);
  native_text_field_free(field);

  // Double-clicking or dragging inside an already-focused empty single-line
  // EDIT must keep its native cue banner visible without waiting on a render.
  native_text_field_t single = native_text_field_create("");
  native_text_field_set_bordered(single, false);
  native_text_field_set_placeholder(single, "Placeholder");
  native_text_field_set_font_family(single, "Segoe UI");
  native_text_field_set_font_size(single, 16.0 * 72.0 / 96.0);
  native_view_set_background_color(single, {0xFA, 0xF9, 0xF6, 0xFF});
  auto single_hwnd = static_cast<HWND>(native_view_get_native_object(single));
  sui_surface_edit(surface, single_hwnd, 13, single);
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 1000, 500, 0, 0xFFFAF9F6, 0, 0);
  sui_controls_begin(surface);
  sui_control_frame(surface, single_hwnd, 40, 140, 240, 32);
  sui_edit_order(surface, single_hwnd);
  sui_control_clip(single_hwnd, 0, 0, 240, 32);
  sui_surface_end(surface);
  SetActiveWindow(host);
  SetFocus(single_hwnd);
  RedrawWindow(host, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  auto cue_ink = [&]() {
    int ink = 0;
    HDC dc = GetDC(single_hwnd);
    for (int y = px(2); y < px(30); ++y)
      for (int x = px(2); x < px(200); ++x)
        if (GetPixel(dc, x, y) != RGB(250, 249, 246)) ++ink;
    ReleaseDC(single_hwnd, dc);
    return ink;
  };
  const int initial_cue = cue_ink();
  SendMessageW(single_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(px(12), px(12)));
  SendMessageW(single_hwnd, WM_LBUTTONUP, 0, MAKELPARAM(px(12), px(12)));
  SendMessageW(single_hwnd, WM_LBUTTONDBLCLK, MK_LBUTTON, MAKELPARAM(px(12), px(12)));
  SendMessageW(single_hwnd, WM_MOUSEMOVE, MK_LBUTTON, MAKELPARAM(px(40), px(12)));
  SendMessageW(single_hwnd, WM_LBUTTONUP, 0, MAKELPARAM(px(40), px(12)));
  RedrawWindow(single_hwnd, nullptr, nullptr, RDW_UPDATENOW);
  if (initial_cue == 0 || cue_ink() != initial_cue) ++errors;

  // Single-line EDIT optical alignment must centre cap-to-baseline ink inside
  // a control-height slot (e.g. a 28pt Combobox with 12px Segoe UI).
  native_text_field_set_text(single, "Hover");
  native_text_field_set_font_size(single, 12.0 * 72.0 / 96.0);
  native_text_field_set_text_color(single, {0x10, 0x20, 0x30, 0xFF});
  double edit_center = 0, edit_height = 0;
  sui_edit_line_metrics(surface, single_hwnd, &edit_center, &edit_height);
  const double slot_y = 140.0, slot_h = 28.0;
  const double edit_y = slot_y + slot_h * 0.5 - edit_center;
  const double edit_box_h = edit_height > (slot_y + slot_h - edit_y)
                                ? edit_height
                                : (slot_y + slot_h - edit_y);
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 1000, 500, 0, 0xFFFAF9F6, 0, 0);
  sui_controls_begin(surface);
  sui_control_frame(surface, single_hwnd, 40, edit_y, 240, edit_box_h);
  sui_edit_order(surface, single_hwnd);
  sui_control_clip(single_hwnd, 0, 0, 240, edit_box_h);
  sui_surface_end(surface);
  RedrawWindow(host, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  {
    HDC dc = GetDC(host);
    const int box_top = px(slot_y), box_bottom = px(slot_y + slot_h) - 1;
    int min_y = box_bottom + 1, max_y = -1;
    for (int y = box_top; y <= box_bottom; ++y)
      for (int x = px(42); x < px(160); ++x)
        if (GetRValue(GetPixel(dc, x, y)) < 200) {
          if (y < min_y) min_y = y;
          if (y > max_y) max_y = y;
        }
    ReleaseDC(host, dc);
    const int top_gap = min_y - box_top;
    const int bottom_gap = box_bottom - max_y;
    if (max_y < min_y || std::abs(top_gap - bottom_gap) > 1) ++errors;
  }

  sui_surface_remove_edit(surface, single_hwnd);
  native_text_field_free(single);

  sui_surface_destroy(surface);
  DestroyWindow(host);
  return errors;
}

int shadow_probe(const uint8_t *alpha, int width, int height, double inset,
                 double mask_scale) {
  HWND host = CreateWindowExW(0, L"STATIC", L"Shadow regression", WS_OVERLAPPEDWINDOW,
                              0, 0, 500, 500, nullptr, nullptr,
                              GetModuleHandleW(nullptr), nullptr);
  void *surface = sui_surface_create(host, nullptr, nullptr, 0);
  void *mask = sui_mask_create(alpha, width, height);
  const double scale = sui_surface_scale(surface);
  auto px = [scale](double value) { return int(std::round(value * scale)); };
  auto frame = [&](double x, uint32_t color, bool clipped = false) {
    sui_surface_begin(surface);
    sui_surface_shape(surface, 0, 0, 500, 500, 0, 0xFFFFFFFF, 0, 0);
    if (clipped) sui_surface_clip(surface, 100, 100, 200, 160, 0);
    sui_surface_mask(surface, mask, x - inset, 108 - inset,
                      width / mask_scale, height / mask_scale, color);
    if (clipped) sui_surface_restore(surface);
    sui_surface_shape(surface, x, 100, 200, 160, 12, 0xFFFFFFFF, 0, 0);
    sui_surface_end(surface);
  };
  int errors = 0, full = 0;
  frame(100, 0x66000000);
  {
    Capture capture(host);
    auto darkness = [&](int x) { return 255 - GetRValue(GetPixel(capture.dc, px(x), px(180))); };
    full = darkness(90);
    if (full <= 20 || darkness(76) <= 8 || darkness(26) > 1) ++errors;
    int previous = 0;
    for (int x = 26; x < 100; ++x) {
      int value = darkness(x);
      if (value < previous || value - previous > 3) ++errors;
      previous = value;
    }
  }
  frame(100, 0x33000000);
  {
    Capture capture(host);
    if (std::abs((255 - int(GetRValue(GetPixel(capture.dc, px(90), px(180))))) - full / 2.) > 2)
      ++errors;
  }
  frame(100, 0x66FF0000);
  {
    Capture capture(host);
    auto color = GetPixel(capture.dc, px(90), px(180));
    if (GetRValue(color) != 255 || std::abs(255 - int(GetGValue(color)) - full) > 2)
      ++errors;
  }
  frame(100, 0x66000000, true);
  {
    Capture capture(host);
    if (GetPixel(capture.dc, px(90), px(180)) != RGB(255, 255, 255)) ++errors;
  }
  frame(100, 0x66000000);
  { Capture capture(host); }
  frame(200, 0x66000000);
  sui_mask_destroy(mask); // The retained frame must keep the bitmap alive.
  {
    Capture capture(host);
    if (GetPixel(capture.dc, px(90), px(180)) != RGB(255, 255, 255)) ++errors;
    if (255 - GetRValue(GetPixel(capture.dc, px(190), px(180))) <= 20) ++errors;
  }
  sui_surface_destroy(surface);
  DestroyWindow(host);
  return errors;
}
drawing_probe_result drawing_probe(void) {
  Probe p;
  p.host = CreateWindowExW(0, L"STATIC", L"SwiftUI drawing regression test",
                           WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT,
                           CW_USEDEFAULT, 420, 240, nullptr, nullptr,
                           GetModuleHandleW(nullptr), nullptr);
  p.result.dpi = int(GetDpiForWindow(p.host));
  p.result.aware =
      AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(p.host),
                                   DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const double scale = p.result.dpi / 96.;
  auto px = [scale](double value) { return int(std::round(value * scale)); };
  p.surface = sui_surface_create(p.host, Event, &p, 0);
  p.button = CreateWindowExW(
      0, L"BUTTON", L"Hover", WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_CLIPSIBLINGS,
      px(20), px(20), px(80), px(30), p.host, nullptr, GetModuleHandleW(nullptr),
      nullptr);
  sui_surface_button(p.surface, p.button, 1, 1, 0);
  Frame(p, false);
  ShowWindow(p.host, SW_SHOWNOACTIVATE);
  UpdateWindow(p.host);
  UpdateWindow(p.button);
  ValidateRect(p.host, nullptr);
  ValidateRect(p.button, nullptr);
  SetWindowPos(p.host, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  const auto before_expose = sui_surface_total_paint_stats(p.surface).paints;
  RedrawWindow(p.host, nullptr, nullptr,
               RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
  if (sui_surface_total_paint_stats(p.surface).paints - before_expose != 1)
    ++p.result.expose_errors;
  // A styled control above a real native editor still needs its own paint:
  // the canvas deliberately leaves that editor's rectangle untouched.
  native_text_field_t field = native_text_field_create("");
  native_text_field_set_bordered(field, false);
  auto editor = native_view_get_native_object(field);
  sui_surface_edit(p.surface, editor, 9, field);
  SetWindowPos(static_cast<HWND>(editor), HWND_BOTTOM, px(20), px(20), px(80),
               px(30), SWP_NOACTIVATE);
  RedrawWindow(p.host, nullptr, nullptr,
               RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN);
  HDC visible = GetDC(p.host);
  if (GetPixel(visible, px(22), px(22)) != RGB(32, 128, 64))
    ++p.result.expose_errors;
  ReleaseDC(p.host, visible);
  sui_surface_remove_edit(p.surface, editor);
  native_text_field_free(field);
  SetWindowSubclass(p.button, Observe, 1, reinterpret_cast<DWORD_PTR>(&p));
  p.track = true;
  for (int i = 0; i < 20; ++i) {
    SendMessageW(p.button, WM_MOUSEMOVE, 0, MAKELPARAM(px(5), px(5)));
    SendMessageW(p.button, WM_MOUSELEAVE, 0, 0);
  }
  p.track = false;
  RECT damaged{}, surface{};
  GetUpdateRect(p.host, &damaged, FALSE);
  GetClientRect(p.host, &surface);
  p.result.damage_pixels =
      (damaged.right - damaged.left) * (damaged.bottom - damaged.top);
  p.result.surface_pixels = surface.right * surface.bottom;
  sui_surface_begin(p.surface);
  sui_surface_shape(p.surface, 0, 0, 1000, 1000, 0, 0xFFFF0000, 0, 0);
  {
    Capture previous(p.host);
    if (GetPixel(previous.dc, px(5), px(5)) != RGB(16, 32, 48))
      ++p.result.atomic_errors;
  }
  sui_surface_end(p.surface);
  {
    Capture published(p.host);
    if (GetPixel(published.dc, px(5), px(5)) != RGB(255, 0, 0))
      ++p.result.atomic_errors;
  }
  Frame(p, false);
  {
    Capture parent(p.host), child(p.button);
    // Exact colour boundaries must occur at logical coordinates * DPI scale.
    // This catches both bitmap virtualization and DrawImage's implicit scaling.
    for (int x = px(5); x < px(120); ++x) {
      const auto expected =
          x >= px(20) && x < px(100) ? RGB(32, 128, 64) : RGB(16, 32, 48);
      if (GetPixel(parent.dc, x, px(22)) != expected)
        ++p.result.pixel_errors;
    }
    int min_ink_y = px(30), max_ink_y = -1;
    for (int y = 0; y < px(30); ++y)
      for (int x = 0; x < px(80); ++x) {
        const auto color = GetPixel(child.dc, x, y);
        if (color != GetPixel(parent.dc, x + px(20), y + px(20)))
          ++p.result.child_pixel_errors;
        // ClearType lights R and B subpixels independently on 1px stems at 96 DPI.
        if (GetRValue(color) > 160 || GetBValue(color) > 160) {
          if (y < min_ink_y) min_ink_y = y;
          if (y > max_ink_y) max_ink_y = y;
        }
      }
    const int top_gap = min_ink_y;
    const int bottom_gap = px(30) - 1 - max_ink_y;
    if (max_ink_y < min_ink_y || std::abs(top_gap - bottom_gap) > 1)
      ++p.result.pixel_errors;
  }
  Frame(p, false, 40);
  HRGN region = CreateRectRgn(0, 0, 0, 0);
  GetWindowRgn(p.button, region);
  if (!PtInRegion(region, px(10), px(10)) || PtInRegion(region, px(60), px(10)))
    ++p.result.clip_errors;
  Frame(p, false);
  GetWindowRgn(p.button, region);
  if (!PtInRegion(region, px(60), px(10)))
    ++p.result.clip_errors;
  DeleteObject(region);
  auto clippedFrame = [&](bool extra) {
    sui_surface_begin(p.surface);
    sui_surface_shape(p.surface, 0, 0, 1000, 1000, 0, 0xFF102030, 0, 0);
    sui_surface_clip(p.surface, 120, 80, 80, 40, 0);
    sui_surface_shape(p.surface, 100, 80, 140, 40, 0,
                      extra ? 0xFF804020 : 0xFF208040, 0, 0);
    if (extra)
      sui_surface_shape(p.surface, 130, 90, 20, 20, 0, 0xFFFFFFFF, 0, 0);
    sui_surface_restore(p.surface);
    sui_surface_end(p.surface);
  };
  clippedFrame(false);
  {
    Capture initial(p.host);
  }
  ValidateRect(p.host, nullptr);
  clippedFrame(true);
  RECT changed;
  GetUpdateRect(p.host, &changed, FALSE);
  if (changed.left < px(120) || changed.top < px(80) ||
      changed.right > px(200) || changed.bottom > px(120) ||
      IsRectEmpty(&changed))
    ++p.result.scope_errors;
  {
    Capture updated(p.host);
    if (GetPixel(updated.dc, px(125), px(85)) != RGB(128, 64, 32) ||
        GetPixel(updated.dc, px(140), px(100)) != RGB(255, 255, 255) ||
        GetPixel(updated.dc, px(110), px(85)) != RGB(16, 32, 48))
      ++p.result.scope_errors;
  }
  clippedFrame(false);
  {
    Capture removed(p.host);
    if (GetPixel(removed.dc, px(140), px(100)) != RGB(32, 128, 64))
      ++p.result.scope_errors;
  }
  const auto hover_positions = p.result.position_changes;
  p.track = true;
  sui_surface_begin(p.surface);
  sui_control_frame(p.surface, p.button, 30, 30, 80, 30);
  if (p.result.position_changes != hover_positions)
    ++p.result.scope_errors;
  sui_surface_end(p.surface);
  p.track = false;
  // Native layout must only queue damage; publication performs the paint.
  if (p.result.position_changes != hover_positions + 1)
    ++p.result.scope_errors;
  p.result.position_changes = hover_positions;
  HWND outside = CreateWindowExW(
      0, L"BUTTON", L"Outside", WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_CLIPSIBLINGS,
      px(210), px(140), px(40), px(20), p.host, nullptr, GetModuleHandleW(nullptr),
      nullptr);
  sui_surface_button(p.surface, outside, 2, 1, 0);
  SetWindowSubclass(p.host, Observe, 2, reinterpret_cast<DWORD_PTR>(&p));
  auto grouped = [&](int outer, int inner) {
    sui_surface_begin(p.surface);
    sui_surface_shape(p.surface, 0, 0, 1000, 1000, 0, 0xFF102030, 0, 0);
    sui_surface_shape(p.surface, 30, 30 - outer - inner, 80, 30, 0, 0xFF208040,
                      0, 0);
    sui_controls_begin(p.surface);
    sui_controls_push(p.surface, 100, 10, 10 - outer, 250, 600, 10, 10, 250,
                      120);
    sui_controls_push(p.surface, 101, 20, 20 - outer - inner, 200, 400, 20,
                      20 - outer, 200, 90);
    sui_control_frame(p.surface, p.button, 30, 30 - outer - inner, 80, 30);
    sui_button_update(p.surface, p.button, 0, "", 0, 0, 80, 30);
    sui_controls_pop(p.surface);
    sui_controls_pop(p.surface);
    sui_control_frame(p.surface, outside, 210, 140, 40, 20);
    sui_button_update(p.surface, outside, 0, "", 0, 0, 40, 20);
    sui_surface_end(p.surface);
  };
  grouped(0, 0);
  const auto grouped_parent = GetParent(p.button);
  for (int i = 0; i < 12; ++i) {
    const int outer = i % 3 * 4, inner = i % 2 * 2;
    const auto positions = p.result.position_changes;
    p.track = true;
    grouped(outer, inner);
    p.track = false;
    // Parent translations must not issue position updates to each descendant.
    if (p.result.position_changes != positions ||
        GetParent(p.button) != grouped_parent)
      ++p.result.group_errors;
    RECT actual;
    GetWindowRect(p.button, &actual);
    MapWindowPoints(nullptr, p.host, reinterpret_cast<POINT *>(&actual), 2);
    if (actual.left != px(30) || actual.top != px(30 - outer - inner))
      ++p.result.group_errors;
    Capture parent(p.host), child(p.button);
    if (GetPixel(child.dc, px(5), px(5)) != RGB(32, 128, 64) ||
        GetPixel(parent.dc, px(35), px(35 - outer - inner)) != RGB(32, 128, 64))
      ++p.result.group_errors;
  }
  grouped(0, 0);
  sui_surface_focus_next(p.surface, nullptr, 0);
  if (GetFocus() != p.button)
    ++p.result.group_errors;
  sui_surface_focus_next(p.surface, p.button, 0);
  if (GetFocus() != outside)
    ++p.result.group_errors;
  sui_surface_focus_next(p.surface, outside, 1);
  if (GetFocus() != p.button)
    ++p.result.group_errors;
  sui_control_tab_visible(p.surface, p.button, 0);
  sui_surface_focus_next(p.surface, outside, 0);
  if (GetFocus() != outside)
    ++p.result.group_errors;
  sui_control_tab_visible(p.surface, p.button, 1);
  sui_button_activate(p.button);
  if (p.clicks != 1)
    ++p.result.group_errors;
  auto fractional = [&](double offset) {
    sui_surface_begin(p.surface);
    sui_surface_shape(p.surface, 0, 0, 1000, 1000, 0, 0xFF102030, 0, 0);
    sui_controls_push(p.surface, 100, 0, -offset, 250, 600, 0, 0, 250, 120);
    sui_control_frame(p.surface, p.button, 20, 0.5 / scale - offset, 80, 30);
    sui_button_update(p.surface, p.button, 0, "", 0, 0, 80, 30);
    sui_controls_pop(p.surface);
    sui_surface_end(p.surface);
  };
  fractional(0);
  const auto fractional_positions = p.result.position_changes;
  p.track = true;
  const double offsets[] = {48., 96., 48., 0., 48., 0.};
  for (double offset : offsets)
    fractional(offset);
  p.track = false;
  if (p.result.position_changes != fractional_positions)
    ++p.result.group_errors;
  RemoveWindowSubclass(p.host, Observe, 2);
  p.result.position_changes = hover_positions;
  RemoveWindowSubclass(p.button, Observe, 1);
  sui_surface_destroy(p.surface);
  DestroyWindow(p.host);
  return p.result;
}

extern "C" int host_region_distinct_pixels(void *raw_host, double x, double y, double w, double h) {
  HWND host = static_cast<HWND>(raw_host);
  if (!host || !IsWindow(host) || w <= 0 || h <= 0) return 0;
  RECT client{};
  GetClientRect(host, &client);
  const int cw = client.right - client.left;
  const int ch = client.bottom - client.top;
  if (cw <= 0 || ch <= 0) return 0;
  BITMAPINFO bmi{};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = cw;
  bmi.bmiHeader.biHeight = -ch;
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  uint32_t *pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  HBITMAP dib = CreateDIBSection(mem, &bmi, DIB_RGB_COLORS, reinterpret_cast<void **>(&pixels), nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (!dib || !pixels) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem);
    return 0;
  }
  HGDIOBJ old = SelectObject(mem, dib);
  SendMessageW(host, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(mem), PRF_CLIENT);
  const double scale = GetDpiForWindow(host) / 96.0;
  const int x0 = (std::max)(0, int(std::floor(x * scale)));
  const int y0 = (std::max)(0, int(std::floor(y * scale)));
  const int x1 = (std::min)(cw, int(std::ceil((x + w) * scale)));
  const int y1 = (std::min)(ch, int(std::ceil((y + h) * scale)));
  int distinct = 0;
  if (x1 > x0 && y1 > y0) {
    const uint32_t base = pixels[y0 * cw + x0] & 0x00FFFFFFu;
    for (int py = y0; py < y1; ++py) {
      for (int px = x0; px < x1; ++px) {
        if ((pixels[py * cw + px] & 0x00FFFFFFu) != base) {
          ++distinct;
        }
      }
    }
  }
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  return distinct;
}

extern "C" int control_has_vscroll(void *control) {
  HWND hwnd = static_cast<HWND>(control);
  if (!hwnd || !IsWindow(hwnd)) return 0;
  return (GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_VSCROLL) != 0 ? 1 : 0;
}

extern "C" int control_is_multiline_edit(void *control) {
  HWND hwnd = static_cast<HWND>(control);
  if (!hwnd || !IsWindow(hwnd)) return 0;
  return (GetWindowLongPtrW(hwnd, GWL_STYLE) & ES_MULTILINE) != 0 ? 1 : 0;
}

extern "C" int control_print_distinct_pixels(void *control) {
  HWND hwnd = static_cast<HWND>(control);
  if (!hwnd || !IsWindow(hwnd)) return 0;
  RECT cr{};
  GetClientRect(hwnd, &cr);
  const int cw = cr.right - cr.left;
  const int ch = cr.bottom - cr.top;
  if (cw <= 0 || ch <= 0) return 0;
  BITMAPINFO bmi{};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = cw;
  bmi.bmiHeader.biHeight = -ch;
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  uint32_t *pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  HBITMAP dib = CreateDIBSection(mem, &bmi, DIB_RGB_COLORS, reinterpret_cast<void **>(&pixels), nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (!dib || !pixels) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem);
    return 0;
  }
  HGDIOBJ old = SelectObject(mem, dib);
  SendMessageW(hwnd, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(mem), PRF_CLIENT);
  const uint32_t base = pixels[0] & 0x00FFFFFFu;
  int distinct = 0;
  for (int i = 0; i < cw * ch; ++i) {
    if ((pixels[i] & 0x00FFFFFFu) != base) {
      ++distinct;
    }
  }
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  return distinct;
}

extern "C" void control_send_key(void *control, int vk) {
  HWND hwnd = static_cast<HWND>(control);
  if (!hwnd || !IsWindow(hwnd)) return;
  SendMessageW(hwnd, WM_KEYDOWN, static_cast<WPARAM>(vk), 0);
  SendMessageW(hwnd, WM_KEYUP, static_cast<WPARAM>(vk), 1L << 31);
}

extern "C" void control_send_char(void *control, int ch) {
  HWND hwnd = static_cast<HWND>(control);
  if (!hwnd || !IsWindow(hwnd)) return;
  SendMessageW(hwnd, WM_CHAR, static_cast<WPARAM>(ch), 0);
}
