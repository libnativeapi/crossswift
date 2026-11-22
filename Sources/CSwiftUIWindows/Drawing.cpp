#include "SwiftUIWindows.h"
#include <nativeapi.h>
#include <windows.h>
#include <shobjidl.h>

#include <algorithm>
#include <commctrl.h>
#include <dwmapi.h>
#include <windowsx.h>
using std::max;
using std::min;
#include <cmath>
#include <cstring>
#include <gdiplus.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include "FrameTrace.h"

namespace {
using namespace Gdiplus;
constexpr UINT_PTR subclass_id = 0x53554950;
constexpr UINT deferred_input = WM_APP + 581;
struct AlphaMask {
  std::vector<uint32_t> pixels;
  Bitmap bitmap;
  AlphaMask(const uint8_t *alpha, int width, int height)
      : pixels(size_t(width) * height),
        bitmap(width, height, width * 4, PixelFormat32bppPARGB,
               reinterpret_cast<BYTE *>(pixels.data())) {
    for (size_t i = 0; i < pixels.size(); ++i)
      pixels[i] = uint32_t(alpha[i]) * 0x01010101u;
  }
};
using MaskHandle = std::shared_ptr<AlphaMask>;
struct Command {
  int kind = 0; // shape, text, clip, restore
  RectF rect;
  float radius = 0, stroke_width = 0, size = 14, weight = 400, line_spacing = 0;
  uint32_t fill = 0, stroke = 0;
  std::wstring text, family;
  std::vector<double> path;
  std::vector<uint32_t> colors;
  PointF start, end;
  MaskHandle mask;
  size_t clip_end = 0;
  bool operator==(const Command &c) const {
    return kind == c.kind && rect.Equals(c.rect) && radius == c.radius &&
           stroke_width == c.stroke_width && size == c.size &&
           weight == c.weight && line_spacing == c.line_spacing &&
           fill == c.fill && stroke == c.stroke && text == c.text &&
           family == c.family && path == c.path && colors == c.colors &&
           start.X == c.start.X && start.Y == c.start.Y && end.X == c.end.X &&
           end.Y == c.end.Y && mask == c.mask;
  }
};
struct ButtonHook {
  int64_t id;
  bool custom_draw;
  bool hovered = false;
  std::wstring help;
  RECT clip{};
  int clip_width = -1, clip_height = -1, clip_radius = -1;
  bool tab_visible = true;
};
struct EditHook {
  int64_t id;
  UINT cached_dpi = 0;
  LONG lf_height = 0;
  LONG lf_weight = 0;
  wchar_t face[LF_FACESIZE]{};
  double line_center = 0;
  double line_height = 0;
  HBRUSH bg_brush = nullptr;
  COLORREF bg_color = CLR_INVALID;
  bool transparent_bg = true;
  bool en_change_fired = false;
  bool pending_text_paint = false;
  bool caret_hidden = false;
  bool ime_composing = false;
  bool multiline = false;
  bool unthemed = false;
  uint32_t text_argb = 0xFF000000u;
  uint32_t placeholder_argb = 0x6B000000u;
  std::wstring placeholder;
  double sample_x = 0;
  double sample_y = 0;
};
struct Framebuffer {
  UINT width, height;
  UINT capacity_width, capacity_height;
  UINT stride_pixels;
  HDC dc = CreateCompatibleDC(nullptr);
  HBITMAP dib = nullptr;
  HGDIOBJ previous = nullptr;
  uint32_t *pixels = nullptr;
  std::unique_ptr<Bitmap> bitmap;
  Framebuffer(UINT w, UINT h, bool round_capacity = false)
      : width(w), height(h),
        capacity_width(round_capacity ? ((w + 255u) & ~255u) : w),
        capacity_height(round_capacity ? ((h + 255u) & ~255u) : h),
        stride_pixels(capacity_width) {
    void *raw_pixels = nullptr;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = LONG(capacity_width);
    info.bmiHeader.biHeight = -LONG(capacity_height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    dib = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &raw_pixels, nullptr, 0);
    pixels = static_cast<uint32_t *>(raw_pixels);
    previous = SelectObject(dc, dib);
    bitmap = std::make_unique<Bitmap>(capacity_width, capacity_height,
                                      INT(capacity_width * 4), PixelFormat32bppPARGB,
                                      static_cast<BYTE *>(raw_pixels));
  }
  bool CanReuseFor(UINT w, UINT h) const {
    return w <= capacity_width && h <= capacity_height &&
           w * 2 >= capacity_width && h * 2 >= capacity_height;
  }
  ~Framebuffer() {
    bitmap.reset();
    SelectObject(dc, previous);
    DeleteObject(dib);
    DeleteDC(dc);
  }
};
struct FontKey {
  std::wstring family;
  uint32_t size_bits = 0;
  bool bold = false;
  bool operator==(const FontKey &other) const {
    return size_bits == other.size_bits && bold == other.bold &&
           family == other.family;
  }
};
struct FontKeyHash {
  size_t operator()(const FontKey &k) const noexcept {
    size_t h = std::hash<std::wstring>{}(k.family);
    h ^= std::hash<uint32_t>{}(k.size_bits) + 0x9e3779b9u + (h << 6) + (h >> 2);
    h ^= size_t(k.bold ? 1 : 0) + 0x9e3779b9u + (h << 6) + (h >> 2);
    return h;
  }
};
inline uint32_t FloatBits(float v) {
  uint32_t bits = 0;
  std::memcpy(&bits, &v, sizeof(bits));
  return bits;
}
struct TextFont {
  FontFamily family;
  Font font;
  float size;
  UINT cached_dpi = 0;
  float cached_center = 0;
  float cached_line_height = -1.f;
  TextFont(const std::wstring &family_name, float font_size, bool bold)
      : family(family_name.c_str()),
        font(family.GetLastStatus() == Ok ? &family
                                          : FontFamily::GenericSansSerif(),
             font_size, bold ? FontStyleBold : FontStyleRegular, UnitPixel),
        size(font_size) {}
  TextFont(const Command &c)
      : TextFont(c.family, c.size, c.weight >= 600.f) {}
  float LineHeight(const Graphics &g) {
    if (cached_line_height < 0.f) {
      cached_line_height = font.GetHeight(&g);
    }
    return cached_line_height;
  }
  float OpticalCenter(UINT dpi, float line_height) {
    if (dpi == 0)
      dpi = 96;
    if (cached_dpi == dpi)
      return cached_center;
    cached_dpi = dpi;
    cached_center = line_height * 0.5f;
    if (size <= 0.f || size > 200.f)
      return cached_center;
    // GDI+ positions strings from the font's WinAscent cell top, which on
    // Segoe UI includes asymmetric diacritic headroom and ClearType ppem jumps
    // that push single-line control labels visibly below centre. Measure the
    // rasterized cap-to-baseline bounds of 'H' once per (font, DPI) under the
    // exact surface rasterizer state so labels sit optically centred.
    const float scale = dpi / 96.f;
    const int cell_w = max(16, int(std::ceil(size * scale * 1.5f)) + 8);
    const int w = cell_w * 4;
    const int h = max(24, int(std::ceil(size * scale * 2.5f)) + 16);
    std::vector<uint32_t> pixels(size_t(w) * h, 0xFFFFFFFFu);
    {
      Bitmap bitmap(w, h, w * 4, PixelFormat32bppPARGB,
                    reinterpret_cast<BYTE *>(pixels.data()));
      Graphics g(&bitmap);
      g.SetSmoothingMode(SmoothingModeAntiAlias);
      g.SetPixelOffsetMode(PixelOffsetModeHalf);
      g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
      g.ScaleTransform(scale, scale);
      StringFormat format(StringFormat::GenericTypographic());
      format.SetFormatFlags(StringFormatFlagsNoWrap |
                            StringFormatFlagsMeasureTrailingSpaces);
      SolidBrush black(Color(255, 0, 0, 0));
      for (int i = 0; i < 4; ++i) {
        const float ox = (2.f + i * cell_w) / scale;
        const float oy = (4.f + i * 0.25f) / scale;
        g.DrawString(L"H", 1, &font, PointF(ox, oy), &format, &black);
      }
    }
    float sum = 0.f;
    for (int i = 0; i < 4; ++i) {
      const int x0 = i * cell_w, x1 = x0 + cell_w;
      int min_y = h, max_y = -1;
      for (int py = 0; py < h; ++py) {
        const uint32_t *row = pixels.data() + size_t(py) * w;
        for (int px = x0; px < x1; ++px) {
          if (((row[px] >> 16) & 255) < 220 || ((row[px] >> 8) & 255) < 220 ||
              (row[px] & 255) < 220) {
            min_y = min(min_y, py);
            max_y = max(max_y, py);
          }
        }
      }
      if (max_y < min_y)
        return cached_center;
      const float oy = (4.f + i * 0.25f) / scale;
      sum += ((min_y + max_y + 1) * 0.5f) / scale - oy;
    }
    const float cap_center = sum * 0.25f;
    cached_center = cap_center + (line_height * 0.5f - cap_center) * 0.25f;
    return cached_center;
  }
};
struct ControlContext {
  HWND parent;
  double origin_x, origin_y;
  int x, y;
};
struct ControlGroup {
  HWND viewport, window;
};
struct ScrollDrawing {
  int64_t id, revision;
  RectF viewport;
  double x, y;
  size_t begin, end = 0;
};
struct ScrollCopy {
  RECT destination{};
  int dx = 0, dy = 0;
  RECT repaint{};
};
struct Surface {
  HWND host;
  sui_event_callback callback;
  void *context;
  std::vector<Command> commands;
  std::vector<Command> pending;
  std::unique_ptr<Framebuffer> buffer;
  bool buffer_dirty = true;
  RECT damage{};
  std::vector<RECT> damage_rects;
  UINT buffer_dpi = 0;
  std::vector<ControlContext> control_contexts;
  std::unordered_map<int64_t, ControlGroup> control_groups;
  std::unordered_set<int64_t> live_groups;
  std::vector<HWND> control_order, focus_order;
  bool controls_updated = false;
  std::unordered_map<HWND, ButtonHook> buttons;
  HWND tooltip = nullptr;
  sui_input_callback input = nullptr;
  std::unordered_map<HWND, EditHook> edits;
  std::unordered_set<HWND> custom_views;
  uint32_t background_argb = 0xFFFFFFFFu;
  std::unordered_map<FontKey, std::unique_ptr<TextFont>, FontKeyHash> fonts;
  std::unordered_map<std::wstring, std::unique_ptr<Image>> images;
  std::unordered_map<std::string, std::wstring> wide_families;
  std::unordered_map<HWND, native_view_t> native_views;
  std::unordered_map<HWND, HWND> native_parents;
  bool updating_views = false;
  bool native_state_changed = true;
  std::vector<ScrollDrawing> scrolls, pending_scrolls;
  // The immutable frame actually present in the DIB while later publications
  // are waiting for WM_PAINT. Never copy pixels relative to an unpainted frame.
  std::vector<Command> painted_commands;
  std::vector<ScrollDrawing> painted_scrolls;
  std::vector<size_t> scroll_stack;
  ScrollCopy scroll_copy;
  int64_t reused_pixels = 0;
  sui_paint_stats paint_stats{};
  sui_paint_stats total_paint_stats{};
  double publish_times[6]{};
  bool host_clipped_children = false;
  bool window_shadow_enabled = false;
  bool window_shadow_dark = false;
  bool positioning_shadow = false;
  HWND shadow_layer = nullptr;
  HWND shadow_root = nullptr;
  HWND hooked_root = nullptr;
  int shadow_margin = 0;
  int shadow_width = 0;
  int shadow_height = 0;
  uint64_t shadow_hash = 0;
  LONG pending_width = 0;
  LONG pending_height = 0;
  bool defer_commit = false;
  bool commit_on_pos_change = false;
  double origin_offset_x = 0.0;
  double origin_offset_y = 0.0;
  double pending_offset_x = 0.0;
  double pending_offset_y = 0.0;
  bool has_pending_offset = false;
  bool offset_changed_since_paint = false;
  struct DeferredFrame {
    double x, y, w, h;
  };
  struct DeferredClip {
    double x, y, w, h;
  };
  std::unordered_map<HWND, DeferredFrame> deferred_frames;
  std::unordered_map<HWND, DeferredClip> deferred_clips;
  struct PendingShadow {
    HDC dc = nullptr;
    HBITMAP dib = nullptr;
    HGDIOBJ old_bmp = nullptr;
    int sw = 0, sh = 0, margin = 0, bw = 0, bh = 0;
    uint64_t hash = 0;
    bool hide_only = false;
    bool clear_all = false;
    bool valid = false;
    void Reset() {
      if (dc) {
        if (old_bmp) SelectObject(dc, old_bmp);
        if (dib) DeleteObject(dib);
        DeleteDC(dc);
      }
      dc = nullptr;
      dib = nullptr;
      old_bmp = nullptr;
      hide_only = false;
      clear_all = false;
      valid = false;
    }
    ~PendingShadow() { Reset(); }
  } pending_shadow;
  FrameTrace trace;
};

RECT SurfaceClientRect(const Surface *s) {
  if (s->pending_width > 0 && s->pending_height > 0) {
    return RECT{0, 0, s->pending_width, s->pending_height};
  }
  RECT client{};
  GetClientRect(s->host, &client);
  return client;
}

void EffectiveOffset(const Surface *s, double &ox, double &oy) {
  if (s->defer_commit && s->has_pending_offset) {
    ox = s->pending_offset_x;
    oy = s->pending_offset_y;
  } else {
    ox = s->origin_offset_x;
    oy = s->origin_offset_y;
  }
}

constexpr UINT_PTR kShadowRootSubclassId = 0x5AD00001u;

void PositionWindowShadow(Surface *s) {
  if (!s || !s->shadow_layer || !s->shadow_root || s->positioning_shadow || s->defer_commit)
    return;
  s->positioning_shadow = true;
  struct Guard {
    bool &flag;
    ~Guard() { flag = false; }
  } guard{s->positioning_shadow};

  if (!IsWindow(s->shadow_root) || !IsWindowVisible(s->shadow_root) || IsIconic(s->shadow_root)) {
    if (IsWindowVisible(s->shadow_layer)) {
      ShowWindow(s->shadow_layer, SW_HIDE);
    }
    return;
  }
  const bool root_topmost = (GetWindowLongPtrW(s->shadow_root, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  const bool layer_topmost = (GetWindowLongPtrW(s->shadow_layer, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  if (root_topmost != layer_topmost) {
    SetWindowPos(
        s->shadow_layer, root_topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
  }
  RECT rect{};
  if (!GetWindowRect(s->shadow_root, &rect)) return;
  if ((rect.right - rect.left) != s->shadow_width ||
      (rect.bottom - rect.top) != s->shadow_height) {
    return;
  }
  const int target_x = rect.left - s->shadow_margin;
  const int target_y = rect.top - s->shadow_margin;
  RECT cur{};
  if (IsWindowVisible(s->shadow_layer) && GetWindowRect(s->shadow_layer, &cur) &&
      cur.left == target_x && cur.top == target_y &&
      GetWindow(s->shadow_root, GW_HWNDNEXT) == s->shadow_layer) {
    return;
  }
  SetWindowPos(
      s->shadow_layer, s->shadow_root, target_x, target_y, 0, 0,
      SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
}

void CommitPendingResizeImpl(Surface *s, bool from_pos_changed);

LRESULT CALLBACK ShadowRootSubclassProc(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR subclass_id, DWORD_PTR data
) {
  auto *s = reinterpret_cast<Surface *>(data);
  if (msg == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, ShadowRootSubclassProc, subclass_id);
    if (s) {
      if (s->hooked_root == hwnd) s->hooked_root = nullptr;
      if (s->shadow_root == hwnd) {
        s->shadow_root = nullptr;
        if (s->shadow_layer) {
          DestroyWindow(s->shadow_layer);
          s->shadow_layer = nullptr;
        }
      }
    }
    return DefSubclassProc(hwnd, msg, wp, lp);
  }
  if (s && msg == WM_WINDOWPOSCHANGED && s->defer_commit && s->commit_on_pos_change) {
    CommitPendingResizeImpl(s, true);
  }
  const LRESULT res = DefSubclassProc(hwnd, msg, wp, lp);
  if (s && s->shadow_layer && (msg == WM_WINDOWPOSCHANGED || msg == WM_SHOWWINDOW)) {
    PositionWindowShadow(s);
  }
  return res;
}

void EnsureRootHook(Surface *s, HWND root) {
  if (!s || !root || !IsWindow(root)) return;
  if (s->hooked_root != root) {
    if (s->hooked_root && IsWindow(s->hooked_root)) {
      RemoveWindowSubclass(s->hooked_root, ShadowRootSubclassProc, kShadowRootSubclassId);
    }
    s->hooked_root = root;
  }
  SetWindowSubclass(root, ShadowRootSubclassProc, kShadowRootSubclassId, reinterpret_cast<DWORD_PTR>(s));
}

void UnhookRoot(Surface *s) {
  if (!s) return;
  if (s->hooked_root && IsWindow(s->hooked_root)) {
    RemoveWindowSubclass(s->hooked_root, ShadowRootSubclassProc, kShadowRootSubclassId);
  }
  s->hooked_root = nullptr;
}

void ClearWindowShadow(Surface *s) {
  if (!s) return;
  s->shadow_root = nullptr;
  if (s->shadow_layer) {
    if (IsWindow(s->shadow_layer)) DestroyWindow(s->shadow_layer);
    s->shadow_layer = nullptr;
  }
  s->shadow_hash = 0;
  s->shadow_width = 0;
  s->shadow_height = 0;
}

void BoxBlur1DHorizontal(
    const uint16_t *src, uint16_t *dst, int w, int h, int radius
) {
  const int diam = radius * 2 + 1;
  for (int y = 0; y < h; ++y) {
    const uint16_t *in = src + size_t(y) * w;
    uint16_t *out = dst + size_t(y) * w;
    uint32_t acc = uint32_t(in[0]) * (radius + 1);
    for (int x = 1; x <= radius; ++x) acc += in[min(w - 1, x)];
    for (int x = 0; x < w; ++x) {
      out[x] = uint16_t((acc + diam / 2) / diam);
      const int left = max(0, x - radius);
      const int right = min(w - 1, x + radius + 1);
      acc += in[right] - in[left];
    }
  }
}

void BoxBlur1DVertical(
    const uint16_t *src, uint16_t *dst, int w, int h, int radius
) {
  const int diam = radius * 2 + 1;
  for (int x = 0; x < w; ++x) {
    uint32_t acc = uint32_t(src[x]) * (radius + 1);
    for (int y = 1; y <= radius; ++y) acc += src[size_t(min(h - 1, y)) * w + x];
    for (int y = 0; y < h; ++y) {
      dst[size_t(y) * w + x] = uint16_t((acc + diam / 2) / diam);
      const int top = max(0, y - radius);
      const int bot = min(h - 1, y + radius + 1);
      acc += src[size_t(bot) * w + x] - src[size_t(top) * w + x];
    }
  }
}

void BoxBlur3Pass(uint16_t *buf, uint16_t *tmp, int w, int h, int radius) {
  if (radius <= 0 || w <= 1 || h <= 1) return;
  for (int pass = 0; pass < 3; ++pass) {
    BoxBlur1DHorizontal(buf, tmp, w, h, radius);
    BoxBlur1DVertical(tmp, buf, w, h, radius);
  }
}

LRESULT CALLBACK ShadowLayerWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCHITTEST) return HTTRANSPARENT;
  if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(hwnd, msg, wp, lp);
}

bool EnsureShadowLayerWindow(Surface *s, HWND root) {
  if (!s || !root || !IsWindow(root)) return false;
  if (s->shadow_root != root) {
    ClearWindowShadow(s);
  }
  if (!s->shadow_layer) {
    static ATOM cls_atom = [] {
      WNDCLASSW wc{};
      wc.lpfnWndProc = ShadowLayerWndProc;
      wc.hInstance = GetModuleHandleW(nullptr);
      wc.lpszClassName = L"CrossSwiftUIShadowLayer";
      return RegisterClassW(&wc);
    }();
    (void)cls_atom;
    s->shadow_layer = CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"CrossSwiftUIShadowLayer", L"", WS_POPUP,
        0, 0, 0, 0, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!s->shadow_layer) return false;
    s->shadow_root = root;
    EnsureRootHook(s, root);
  }
  return true;
}

void PublishPendingShadow(Surface *s) {
  if (!s || !s->pending_shadow.valid) return;
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (s->pending_shadow.clear_all || !root || !IsWindow(root)) {
    s->pending_shadow.Reset();
    ClearWindowShadow(s);
    return;
  }
  if (s->pending_shadow.hide_only) {
    if (s->shadow_layer) ShowWindow(s->shadow_layer, SW_HIDE);
    s->shadow_hash = s->pending_shadow.hash;
    s->pending_shadow.Reset();
    return;
  }
  if (!EnsureShadowLayerWindow(s, root)) {
    s->pending_shadow.Reset();
    return;
  }
  RECT root_rect{};
  GetWindowRect(root, &root_rect);
  POINT dest_pt{root_rect.left - s->pending_shadow.margin, root_rect.top - s->pending_shadow.margin};
  POINT src_pt{0, 0};
  SIZE layer_sz{s->pending_shadow.sw, s->pending_shadow.sh};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(
      s->shadow_layer, nullptr, &dest_pt, &layer_sz, s->pending_shadow.dc, &src_pt, 0, &blend, ULW_ALPHA);
  s->shadow_margin = s->pending_shadow.margin;
  s->shadow_width = s->pending_shadow.bw;
  s->shadow_height = s->pending_shadow.bh;
  s->shadow_hash = s->pending_shadow.hash;
  s->pending_shadow.Reset();
  PositionWindowShadow(s);
}

void UpdateSurfaceWindowShadow(Surface *s) {
  if (!s) return;
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (!s->window_shadow_enabled || (s->background_argb >> 24) >= 255 ||
      !root || !IsWindow(root) || !s->buffer || !s->buffer->pixels ||
      s->buffer->width == 0 || s->buffer->height == 0) {
    if (s->defer_commit) {
      s->pending_shadow.Reset();
      s->pending_shadow.clear_all = true;
      s->pending_shadow.valid = true;
    } else {
      s->pending_shadow.Reset();
      ClearWindowShadow(s);
    }
    return;
  }
  const int bw = int(s->buffer->width);
  const int bh = int(s->buffer->height);
  const size_t bstride = size_t(s->buffer->stride_pixels);
  if (int64_t(bw) * bh > 8000000) {
    if (s->defer_commit) {
      s->pending_shadow.Reset();
      s->pending_shadow.clear_all = true;
      s->pending_shadow.valid = true;
    } else {
      s->pending_shadow.Reset();
      ClearWindowShadow(s);
    }
    return;
  }
  uint64_t hash = 14695981039346656037ULL;
  hash = (hash ^ uint64_t(bw)) * 1099511628211ULL;
  hash = (hash ^ uint64_t(bh)) * 1099511628211ULL;
  hash = (hash ^ uint64_t(s->window_shadow_dark ? 1 : 0)) * 1099511628211ULL;
  bool any_opaque = false;
  for (int y = 0; y < bh; y += 2) {
    const uint32_t *row = s->buffer->pixels + size_t(y) * bstride;
    uint64_t bits = 0;
    for (int x = 0; x < bw; x += 4) {
      const uint32_t a = row[x] >> 24;
      if (a >= 16) any_opaque = true;
      bits = (bits << 2) | ((a >> 6) & 3u);
      if ((x & 60) == 60) {
        hash = (hash ^ bits) * 1099511628211ULL;
        bits = 0;
      }
    }
    hash = (hash ^ bits) * 1099511628211ULL;
  }
  if (!any_opaque) {
    if (s->defer_commit) {
      s->pending_shadow.Reset();
      s->pending_shadow.hide_only = true;
      s->pending_shadow.hash = hash;
      s->pending_shadow.valid = true;
    } else {
      s->pending_shadow.Reset();
      if (s->shadow_layer) ShowWindow(s->shadow_layer, SW_HIDE);
      s->shadow_hash = hash;
    }
    return;
  }
  if (s->shadow_layer && s->shadow_root == root && s->shadow_hash == hash &&
      s->shadow_width == bw && s->shadow_height == bh) {
    s->pending_shadow.Reset();
    if (!s->defer_commit) {
      PositionWindowShadow(s);
    }
    return;
  }

  const double scale = max(1.0, (s->buffer_dpi ? s->buffer_dpi : 96) / 96.0);
  const int margin = int(std::ceil(38.0 * scale));
  const int dy_far = int(std::lround(8.0 * scale));
  const int dy_near = int(std::lround(1.5 * scale));
  const int sw = bw + margin * 2;
  const int sh = bh + margin * 2;
  const int dw = (sw + 1) / 2;
  const int dh = (sh + 1) / 2;

  std::vector<uint16_t> far_grid(size_t(dw) * dh, 0);
  std::vector<uint16_t> near_grid(size_t(dw) * dh, 0);
  std::vector<uint16_t> tmp_grid(size_t(dw) * dh, 0);
  uint16_t *far_ptr = far_grid.data();
  uint16_t *near_ptr = near_grid.data();
  uint16_t *tmp_ptr = tmp_grid.data();

  for (int y = 0; y < bh; y += 2) {
    const uint32_t *row = s->buffer->pixels + size_t(y) * bstride;
    const int fy = (y + margin + dy_far) / 2;
    const int ny = (y + margin + dy_near) / 2;
    for (int x = 0; x < bw; x += 2) {
      const uint16_t a = uint16_t(row[x] >> 24);
      if (!a) continue;
      const int gx = (x + margin) / 2;
      if (fy >= 0 && fy < dh && gx >= 0 && gx < dw) {
        far_ptr[size_t(fy) * dw + gx] = a;
      }
      if (ny >= 0 && ny < dh && gx >= 0 && gx < dw) {
        near_ptr[size_t(ny) * dw + gx] = a;
      }
    }
  }

  const int r_far = max(2, int(std::lround(8.5 * scale)));
  const int r_near = max(1, int(std::lround(2.0 * scale)));
  BoxBlur3Pass(far_ptr, tmp_ptr, dw, dh, r_far);
  BoxBlur3Pass(near_ptr, tmp_ptr, dw, dh, r_near);

  HDC dc = CreateCompatibleDC(nullptr);
  if (!dc) return;
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = sw;
  info.bmiHeader.biHeight = -sh;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void *bits = nullptr;
  HBITMAP dib = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    if (dib) DeleteObject(dib);
    DeleteDC(dc);
    return;
  }
  HGDIOBJ old_bmp = SelectObject(dc, dib);
  auto *out = static_cast<uint32_t *>(bits);

  // Dual-layer shadow strength (ambient/elevation + crisp contact shadow)
  const uint32_t far_strength = s->window_shadow_dark ? 112u : 58u;
  const uint32_t near_strength = s->window_shadow_dark ? 68u : 34u;

  for (int py = 0; py < sh; ++py) {
    uint32_t *dst_row = out + size_t(py) * sw;
    const int by = py - margin;
    const uint32_t *src_row = (by >= 0 && by < bh) ? (s->buffer->pixels + size_t(by) * bstride) : nullptr;
    const int gy0 = min(dh - 1, py >> 1);
    const int gy1 = min(dh - 1, gy0 + (py & 1));
    const uint16_t *far_r0 = far_ptr + size_t(gy0) * dw;
    const uint16_t *far_r1 = far_ptr + size_t(gy1) * dw;
    const uint16_t *near_r0 = near_ptr + size_t(gy0) * dw;
    const uint16_t *near_r1 = near_ptr + size_t(gy1) * dw;
    for (int px = 0; px < sw; ++px) {
      uint32_t body_a = 0;
      if (src_row) {
        const int bx = px - margin;
        if (bx >= 0 && bx < bw) {
          body_a = src_row[bx] >> 24;
          if (body_a >= 200) {
            dst_row[px] = 0;
            continue;
          }
        }
      }
      const int gx0 = min(dw - 1, px >> 1);
      const int gx1 = min(dw - 1, gx0 + (px & 1));
      const uint32_t far_v =
          (uint32_t(far_r0[gx0]) + uint32_t(far_r0[gx1]) +
           uint32_t(far_r1[gx0]) + uint32_t(far_r1[gx1]) + 2u) >> 2;
      const uint32_t near_v =
          (uint32_t(near_r0[gx0]) + uint32_t(near_r0[gx1]) +
           uint32_t(near_r1[gx0]) + uint32_t(near_r1[gx1]) + 2u) >> 2;
      const uint32_t f_a = (far_v * far_strength + 127u) / 255u;
      const uint32_t n_a = (near_v * near_strength + 127u) / 255u;
      uint32_t combined = f_a + ((n_a * (255u - f_a) + 127u) / 255u);
      if (body_a > 0) {
        const uint32_t mask_out = min(255u, (body_a * 280u) >> 8);
        combined = (combined * (255u - mask_out) + 127u) / 255u;
      }
      dst_row[px] = (min(255u, combined) << 24);
    }
  }

  if (s->defer_commit) {
    s->pending_shadow.Reset();
    s->pending_shadow.dc = dc;
    s->pending_shadow.dib = dib;
    s->pending_shadow.old_bmp = old_bmp;
    s->pending_shadow.sw = sw;
    s->pending_shadow.sh = sh;
    s->pending_shadow.margin = margin;
    s->pending_shadow.bw = bw;
    s->pending_shadow.bh = bh;
    s->pending_shadow.hash = hash;
    s->pending_shadow.valid = true;
    return;
  }

  if (!EnsureShadowLayerWindow(s, root)) {
    SelectObject(dc, old_bmp);
    DeleteObject(dib);
    DeleteDC(dc);
    return;
  }

  RECT root_rect{};
  GetWindowRect(root, &root_rect);
  POINT dest_pt{root_rect.left - margin, root_rect.top - margin};
  POINT src_pt{0, 0};
  SIZE layer_sz{sw, sh};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  UpdateLayeredWindow(s->shadow_layer, nullptr, &dest_pt, &layer_sz, dc, &src_pt, 0, &blend, ULW_ALPHA);

  SelectObject(dc, old_bmp);
  DeleteObject(dib);
  DeleteDC(dc);

  s->shadow_margin = margin;
  s->shadow_width = bw;
  s->shadow_height = bh;
  s->shadow_hash = hash;
  PositionWindowShadow(s);
}
double ClockMilliseconds() {
  static const double frequency = [] {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return double(f.QuadPart) / 1000.;
  }();
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return now.QuadPart / frequency;
}
void InitializeGraphics() {
  static ULONG_PTR token = [] {
    ULONG_PTR result = 0;
    GdiplusStartupInput input;
    GdiplusStartup(&result, &input, nullptr);
    return result;
  }();
  (void)token;
}
std::wstring Wide(const char *text) {
  if (!text || !*text)
    return {};
  int count = MultiByteToWideChar(CP_UTF8, 0, text, -1, nullptr, 0);
  std::wstring result(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text, -1, result.data(), count);
  result.pop_back();
  return result;
}
void RoundedPath(GraphicsPath &path, RectF r, float radius) {
  float d = max(0.f, min(radius * 2, min(r.Width, r.Height)));
  if (d < 0.01f) {
    path.AddRectangle(r);
    return;
  }
  path.AddArc(r.X, r.Y, d, d, 180, 90);
  path.AddArc(r.GetRight() - d, r.Y, d, d, 270, 90);
  path.AddArc(r.GetRight() - d, r.GetBottom() - d, d, d, 0, 90);
  path.AddArc(r.X, r.GetBottom() - d, d, d, 90, 90);
  path.CloseFigure();
}
const StringFormat &TypographicFormat() {
  static const StringFormat *format = [] {
    auto *f = new StringFormat(StringFormat::GenericTypographic());
    f->SetFormatFlags(StringFormatFlagsNoWrap |
                      StringFormatFlagsMeasureTrailingSpaces);
    return f;
  }();
  return *format;
}
void DrawTextCommand(Surface *s, Graphics &g, SolidBrush &brush,
                     const Command &c) {
  FontKey key{c.family, FloatBits(c.size), c.weight >= 600.f};
  auto found = s->fonts.find(key);
  if (found == s->fonts.end()) {
    if (s->fonts.size() >= 256)
      s->fonts.clear();
    found = s->fonts.emplace(std::move(key), std::make_unique<TextFont>(c)).first;
  }
  auto &font = found->second->font;
  const auto &format = TypographicFormat();
  brush.SetColor(Color(c.fill));
  // Explicit newlines and line spacing, without inventing a wrapping policy.
  const float line_height = found->second->LineHeight(g);
  const float center = found->second->OpticalCenter(s->buffer_dpi, line_height);
  const size_t first_nl = c.text.find(L'\n');
  if (first_nl == std::wstring::npos) {
    const float y = c.rect.Y + c.rect.Height * 0.5f - center;
    g.DrawString(c.text.c_str(), int(c.text.size()), &font,
                 PointF(c.rect.X, y), &format, &brush);
    return;
  }
  const float step = line_height + c.line_spacing;
  int lines = 2;
  for (size_t pos = first_nl + 1; (pos = c.text.find(L'\n', pos)) != std::wstring::npos;
       ++pos) {
    ++lines;
  }
  float y =
      c.rect.Y + c.rect.Height * 0.5f - center - step * (lines - 1) * 0.5f;
  size_t start = 0;
  while (start <= c.text.size()) {
    const size_t end = c.text.find(L'\n', start);
    const size_t len =
        (end == std::wstring::npos) ? (c.text.size() - start) : (end - start);
    g.DrawString(c.text.c_str() + start, int(len), &font, PointF(c.rect.X, y),
                 &format, &brush);
    if (end == std::wstring::npos)
      break;
    start = end + 1;
    y += step;
  }
}
void VectorPath(GraphicsPath &path, const std::vector<double> &commands) {
  PointF current;
  for (size_t i = 0; i < commands.size();) {
    const int op = int(commands[i++]);
    if (op == 3) {
      path.CloseFigure();
      continue;
    }
    if (i + (op == 2 ? 6 : 2) > commands.size())
      break;
    PointF p{float(commands[i]), float(commands[i + 1])};
    i += 2;
    if (op == 0) {
      path.StartFigure();
      current = p;
    } else if (op == 1) {
      path.AddLine(current, p);
      current = p;
    } else if (op == 2) {
      PointF c2{float(commands[i]), float(commands[i + 1])},
          end{float(commands[i + 2]), float(commands[i + 3])};
      i += 4;
      path.AddBezier(current, p, c2, end);
      current = end;
    }
  }
}
// A Bezier curve is contained by the convex hull of its control points. These
// conservative bounds avoid allocating GDI+ paths merely to reject invisible
// ink.
RectF PathBounds(const std::vector<double> &commands) {
  double left = 0, top = 0, right = 0, bottom = 0;
  bool first = true;
  for (size_t i = 0; i < commands.size();) {
    const int op = int(commands[i++]);
    const size_t count = op == 3 ? 0 : op == 2 ? 6 : 2;
    if (i + count > commands.size())
      break;
    for (size_t end = i + count; i < end; i += 2) {
      const auto x = commands[i], y = commands[i + 1];
      if (first) {
        left = right = x;
        top = bottom = y;
        first = false;
      } else {
        left = min(left, x);
        top = min(top, y);
        right = max(right, x);
        bottom = max(bottom, y);
      }
    }
  }
  return RectF(float(left), float(top), float(right - left),
               float(bottom - top));
}
void RenderFrame(Surface *s) {
  RECT client = SurfaceClientRect(s);
  const auto dpi = GetDpiForWindow(s->host);
  const auto width = UINT(max(1L, client.right));
  const auto height = UINT(max(1L, client.bottom));
  const bool same_size =
      s->buffer && s->buffer->width == width && s->buffer->height == height;
  if (same_size && s->buffer_dpi == dpi && !s->buffer_dirty)
    return;
  FrameTrace::Span raster_trace(s->trace, 6, 0, s->host);
  const double started = ClockMilliseconds();
  if (!same_size) {
    if (s->buffer && s->buffer->CanReuseFor(width, height)) {
      s->buffer->width = width;
      s->buffer->height = height;
    } else {
      s->buffer = std::make_unique<Framebuffer>(width, height, true);
    }
  }
  const bool full = !same_size || s->buffer_dpi != dpi || s->offset_changed_since_paint;
  s->offset_changed_since_paint = false;
  s->buffer_dpi = dpi;
  s->buffer_dirty = false;
  RECT copied{};
  RECT repaint = s->scroll_copy.repaint;
  if (!full) {
    const auto &copy = s->scroll_copy;
    if (!IsRectEmpty(&copy.destination)) {
      const auto &r = copy.destination;
      GdiFlush();
      if (BitBlt(s->buffer->dc, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, s->buffer->dc, r.left - copy.dx,
                 r.top - copy.dy, SRCCOPY)) {
        GdiFlush();
        copied = r;
        s->reused_pixels = int64_t(r.right - r.left) * (r.bottom - r.top);
      }
    }
  }
  s->scroll_copy = {};
  // Complete GDI access before opening GDI+ over the same DIB storage.
  if (full && s->buffer->pixels) {
    const uint32_t bg = s->background_argb;
    const uint32_t bg_a = bg >> 24;
    const uint32_t bg_premul =
        bg_a == 255u ? bg
        : bg_a == 0u ? 0u
        : ((bg_a << 24) |
           ((((((bg >> 16) & 255u) * bg_a + 127u) / 255u) & 255u) << 16) |
           ((((((bg >> 8) & 255u) * bg_a + 127u) / 255u) & 255u) << 8) |
           ((((bg & 255u) * bg_a + 127u) / 255u) & 255u));
    const size_t stride = size_t(s->buffer->stride_pixels);
    for (UINT y = 0; y < height; ++y) {
      std::fill_n(s->buffer->pixels + size_t(y) * stride, width, bg_premul);
    }
  }
  Graphics g(s->buffer->bitmap.get());
  RECT dirty_px = s->damage;
  std::vector<RECT> active_damage_rects;
  if (!full) {
    Region dirty;
    dirty.MakeEmpty();
    if (!s->damage_rects.empty()) {
      for (const auto &dr : s->damage_rects) {
        if (!IsRectEmpty(&dr)) {
          dirty.Union(Rect(dr.left, dr.top, dr.right - dr.left, dr.bottom - dr.top));
          active_damage_rects.push_back(dr);
        }
      }
    } else if (!IsRectEmpty(&s->damage)) {
      dirty.Union(Rect(s->damage.left, s->damage.top,
                       s->damage.right - s->damage.left,
                       s->damage.bottom - s->damage.top));
      active_damage_rects.push_back(s->damage);
    }
    if (!IsRectEmpty(&copied))
      dirty.Exclude(Rect(copied.left, copied.top, copied.right - copied.left,
                         copied.bottom - copied.top));
    if (!IsRectEmpty(&repaint)) {
      dirty.Union(Rect(repaint.left, repaint.top, repaint.right - repaint.left,
                       repaint.bottom - repaint.top));
      UnionRect(&dirty_px, &dirty_px, &repaint);
      active_damage_rects.push_back(repaint);
    }
    g.SetClip(&dirty);
  }
  SolidBrush solid_brush(Color(s->background_argb));
  if (!full) {
    g.SetCompositingMode(CompositingModeSourceCopy);
    g.FillRectangle(&solid_brush, 0, 0, INT(width), INT(height));
    g.SetCompositingMode(CompositingModeSourceOver);
  } else {
    g.SetClip(Rect(0, 0, INT(width), INT(height)));
  }
  s->damage = {};
  s->damage_rects.clear();
  g.SetSmoothingMode(SmoothingModeAntiAlias);
  g.SetPixelOffsetMode(PixelOffsetModeHalf);
  g.SetTextRenderingHint((s->background_argb >> 24) < 255
                             ? TextRenderingHintAntiAliasGridFit
                             : TextRenderingHintClearTypeGridFit);
  float scale = dpi / 96.f;
  g.ScaleTransform(scale, scale);
  double surf_ox = 0.0, surf_oy = 0.0;
  EffectiveOffset(s, surf_ox, surf_oy);
  if (surf_ox != 0.0 || surf_oy != 0.0) {
    g.TranslateTransform(float(surf_ox), float(surf_oy));
  }
  struct LogicalBox { float l, t, r, b; };
  std::vector<LogicalBox> dmg_boxes;
  if (!full) {
    dmg_boxes.reserve(active_damage_rects.size());
    for (const auto &dr : active_damage_rects) {
      dmg_boxes.push_back({
          float(dr.left / scale - surf_ox) - 1.f,
          float(dr.top / scale - surf_oy) - 1.f,
          float(dr.right / scale - surf_ox) + 1.f,
          float(dr.bottom / scale - surf_oy) + 1.f});
    }
  }
  auto IntersectsDamage = [&](const RectF &r) -> bool {
    const float rl = r.X, rt = r.Y, rr = r.X + r.Width, rb = r.Y + r.Height;
    for (const auto &b : dmg_boxes) {
      if (rr > b.l && rl < b.r && rb > b.t && rt < b.b)
        return true;
    }
    return false;
  };
  std::vector<GraphicsState> clips;
  std::vector<bool> clip_transforms;
  int transform_depth = 0;
  auto IsRectVisible = [&](const RectF &bounds) -> bool {
    if (!full && transform_depth == 0 && !IntersectsDamage(bounds))
      return false;
    return g.IsVisible(bounds) != FALSE;
  };
  for (size_t i = 0; i < s->commands.size(); ++i) {
    const auto &c = s->commands[i];
    if ((c.kind == 2 || c.kind == 5) && c.clip_end > i) {
      auto bounds = c.rect;
      bounds.Inflate(1, 1);
      if (!IsRectVisible(bounds)) {
        i = c.clip_end;
        continue;
      }
    }
    if (c.kind == 3) {
      if (!clips.empty()) {
        g.Restore(clips.back());
        clips.pop_back();
        if (!clip_transforms.empty()) {
          if (clip_transforms.back())
            --transform_depth;
          clip_transforms.pop_back();
        }
      }
    } else if (c.kind == 4 || c.kind == 5) {
      auto bounds = c.rect;
      bounds.Inflate(1 + c.stroke_width / 2, 1 + c.stroke_width / 2);
      if (c.kind == 4 && !IsRectVisible(bounds))
        continue;
      GraphicsPath path;
      VectorPath(path, c.path);
      if (c.kind == 5) {
        path.SetFillMode(FillModeWinding);
        clips.push_back(g.Save());
        clip_transforms.push_back(false);
        g.SetClip(&path, CombineModeIntersect);
      } else {
        if (c.fill >> 24) {
          solid_brush.SetColor(Color(c.fill));
          g.FillPath(&solid_brush, &path);
        }
        if (c.stroke_width > 0 && c.stroke >> 24) {
          Pen pen(Color(c.stroke), c.stroke_width);
          pen.SetStartCap(LineCapRound);
          pen.SetEndCap(LineCapRound);
          pen.SetLineJoin(LineJoinRound);
          g.DrawPath(&pen, &path);
        }
      }
    } else if (c.kind == 6) {
      clips.push_back(g.Save());
      clip_transforms.push_back(true);
      ++transform_depth;
      g.SetTextRenderingHint(TextRenderingHintAntiAlias);
      g.TranslateTransform(c.rect.X, c.rect.Y);
      g.RotateTransform(c.radius);
      g.ScaleTransform(c.size, c.weight);
      g.TranslateTransform(-c.rect.X, -c.rect.Y);
    } else if (c.kind == 7 && c.colors.size() >= 2) {
      if (!IsRectVisible(c.rect))
        continue;
      LinearGradientBrush brush(c.start, c.end, Color(c.colors.front()),
                                Color(c.colors.back()));
      std::vector<Color> colors;
      std::vector<REAL> stops;
      for (size_t j = 0; j < c.colors.size(); ++j) {
        colors.emplace_back(c.colors[j]);
        stops.push_back(REAL(j) / REAL(c.colors.size() - 1));
      }
      brush.SetInterpolationColors(colors.data(), stops.data(),
                                   int(colors.size()));
      g.FillRectangle(&brush, c.rect);
    } else if (c.kind == 9) {
      clips.push_back(g.Save());
      clip_transforms.push_back(true);
      ++transform_depth;
      g.TranslateTransform(c.rect.X, c.rect.Y);
    } else if (c.kind == 10 && c.mask) {
      if (!IsRectVisible(c.rect))
        continue;
      ColorMatrix tint{};
      tint.m[0][0] = ((c.fill >> 16) & 255) / 255.f;
      tint.m[1][1] = ((c.fill >> 8) & 255) / 255.f;
      tint.m[2][2] = (c.fill & 255) / 255.f;
      tint.m[3][3] = (c.fill >> 24) / 255.f;
      tint.m[4][4] = 1;
      ImageAttributes attributes;
      attributes.SetColorMatrix(&tint);
      g.DrawImage(&c.mask->bitmap, c.rect, 0, 0,
                  REAL(c.mask->bitmap.GetWidth()), REAL(c.mask->bitmap.GetHeight()),
                  UnitPixel, &attributes);
    } else if (c.kind == 8) {
      if (!IsRectVisible(c.rect))
        continue;
      auto it = s->images.find(c.text);
      if (it == s->images.end()) {
        if (s->images.size() >= 64)
          s->images.clear();
        it = s->images.emplace(c.text, std::make_unique<Image>(c.text.c_str())).first;
      }
      if (it->second)
        g.DrawImage(it->second.get(), c.rect);
    } else if (c.kind == 2) {
      clips.push_back(g.Save());
      clip_transforms.push_back(false);
      if (c.radius < 0.01f) {
        g.SetClip(c.rect, CombineModeIntersect);
      } else {
        GraphicsPath path;
        RoundedPath(path, c.rect, c.radius);
        g.SetClip(&path, CombineModeIntersect);
      }
    } else if (c.rect.Width > 0 && c.rect.Height > 0 && IsRectVisible(c.rect)) {
      if (c.kind == 1) {
        DrawTextCommand(s, g, solid_brush, c);
        continue;
      }
      const bool plain_rect = c.radius < 0.01f;
      if (c.fill >> 24) {
        solid_brush.SetColor(Color(c.fill));
        if (plain_rect) {
          g.FillRectangle(&solid_brush, c.rect);
        } else {
          GraphicsPath fill;
          RoundedPath(fill, c.rect, c.radius);
          g.FillPath(&solid_brush, &fill);
        }
      }
      if (c.stroke_width > 0 && c.stroke >> 24) {
        auto r = c.rect;
        r.Inflate(-c.stroke_width / 2, -c.stroke_width / 2);
        if (r.Width > 0 && r.Height > 0) {
          Pen pen(Color(c.stroke), c.stroke_width);
          const float inner_r = max(0.f, c.radius - c.stroke_width / 2);
          if (inner_r < 0.01f) {
            g.DrawRectangle(&pen, r);
          } else {
            GraphicsPath edge;
            RoundedPath(edge, r, inner_r);
            g.DrawPath(&pen, &edge);
          }
        }
      }
    }
  }
  g.Flush(FlushIntentionSync);
  UpdateSurfaceWindowShadow(s);
  const double elapsed = ClockMilliseconds() - started;
  s->paint_stats.raster_ms += elapsed;
  s->total_paint_stats.raster_ms += elapsed;
  raster_trace.tag = uint64_t(s->reused_pixels);
  s->painted_commands.clear();
  s->painted_scrolls.clear();
}
void Draw(Surface *s, HWND target, HDC dc) {
  RenderFrame(s);
  FrameTrace::Span blit_trace(s->trace, 7, target == s->host, target);
  const double started = ClockMilliseconds();
  ++s->paint_stats.paints;
  ++s->total_paint_stats.paints;
  RECT client;
  GetClientRect(target, &client);
  POINT offset = {0, 0};
  MapWindowPoints(target, s->host, &offset, 1);
  // The framebuffer is already opaque and in physical pixels. BitBlt avoids
  // re-locking/converting the full GDI+ image for every child HWND's paint.
  RECT clip;
  if (GetClipBox(dc, &clip) == NULLREGION)
    return;
  const int saved = SaveDC(dc);
  if (target == s->host) {
    // Styled controls are input/accessibility HWNDs over this shared canvas.
    // Preserve native EDIT and unstyled BUTTON pixels; layered edits compose
    // themselves over the canvas and must retain its background underneath.
    auto exclude = [&](HWND hwnd) {
      if (!IsWindowVisible(hwnd) ||
          (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_LAYERED))
        return;
      RECT r;
      GetWindowRect(hwnd, &r);
      MapWindowPoints(nullptr, s->host, reinterpret_cast<POINT *>(&r), 2);
      ExcludeClipRect(dc, r.left, r.top, r.right, r.bottom);
    };
    for (const auto &entry : s->edits)
      exclude(entry.first);
    for (HWND cv : s->custom_views)
      exclude(cv);
    for (const auto &entry : s->buttons)
      if (!entry.second.custom_draw)
        exclude(entry.first);
  }
  IntersectRect(&client, &client, &clip);
  RECT source{-offset.x, -offset.y, LONG(s->buffer->width) - offset.x,
              LONG(s->buffer->height) - offset.y};
  IntersectRect(&client, &client, &source);
  if (!IsRectEmpty(&client))
    BitBlt(dc, client.left, client.top, client.right - client.left,
           client.bottom - client.top, s->buffer->dc, client.left + offset.x,
           client.top + offset.y, SRCCOPY);
  RestoreDC(dc, saved);
  const double elapsed = ClockMilliseconds() - started;
  s->paint_stats.blit_ms += elapsed;
  s->total_paint_stats.blit_ms += elapsed;
}
LRESULT Paint(Surface *s, HWND hwnd, UINT msg, WPARAM wp) {
  if (msg == WM_ERASEBKGND)
    return 1;
  if (msg == WM_PRINTCLIENT) {
    Draw(s, hwnd, reinterpret_cast<HDC>(wp));
    return 0;
  }
  PAINTSTRUCT ps;
  FrameTrace::Span traced(s->trace, 4, hwnd == s->host ? 1 : 0, hwnd);
  HDC dc = BeginPaint(hwnd, &ps);
  Draw(s, hwnd, dc);
  if (hwnd == s->host) {
    RECT clip{}, client{};
    GetClientRect(hwnd, &client);
    // An OS-wide expose/theme repaint can invalidate every input HWND after
    // publication. A full canvas paint already covered these styled buttons;
    // acknowledge that damage instead of copying the same pixels per control.
    // Partial/complex paints and overlaps with native widgets remain separate.
    if (GetClipBox(dc, &clip) == SIMPLEREGION && EqualRect(&clip, &client)) {
      std::vector<RECT> native;
      auto bounds = [&](HWND child) {
        RECT r{};
        GetWindowRect(child, &r);
        MapWindowPoints(nullptr, s->host, reinterpret_cast<POINT *>(&r), 2);
        return r;
      };
      for (const auto &entry : s->edits)
        if (IsWindowVisible(entry.first)) native.push_back(bounds(entry.first));
      for (HWND cv : s->custom_views)
        if (IsWindowVisible(cv)) native.push_back(bounds(cv));
      for (const auto &entry : s->buttons)
        if (!entry.second.custom_draw && IsWindowVisible(entry.first))
          native.push_back(bounds(entry.first));
      for (const auto &entry : s->buttons) {
        if (!entry.second.custom_draw) continue;
        const auto r = bounds(entry.first);
        RECT covered{};
        if (!IntersectRect(&covered, &r, &clip) || !EqualRect(&covered, &r)) continue;
        bool overlap = false;
        for (const auto &area : native) {
          RECT intersection{};
          overlap |= IntersectRect(&intersection, &r, &area) != FALSE;
        }
        if (!overlap) ValidateRect(entry.first, nullptr);
      }
    }
  }
  EndPaint(hwnd, &ps);
  if (hwnd == s->host) {
    FrameTrace::Span marker_trace(s->trace, 8, 0, hwnd);
    s->trace.Marker(hwnd);
  }
  return 0;
}
int Modifiers() {
  return ((GetKeyState(VK_SHIFT) & 0x8000) ? 1 : 0) |
         ((GetKeyState(VK_CONTROL) & 0x8000) ? 2 : 0) |
         ((GetKeyState(VK_MENU) & 0x8000) ? 4 : 0) |
         (((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000) ? 8 : 0);
}
int Input(Surface *s, HWND hwnd, int64_t id, UINT msg, WPARAM wp, LPARAM lp) {
  if (!s->input)
    return 0;
  int event = 0, value = 0;
  POINT point = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
  switch (msg) {
  case WM_MOUSEMOVE:
    event = 1;
    break;
  case WM_LBUTTONDOWN:
    event = 2;
    break;
  case WM_LBUTTONUP:
    event = 3;
    break;
  case WM_LBUTTONDBLCLK:
    event = 4;
    break;
  case WM_MOUSEHWHEEL:
  case WM_MOUSEWHEEL:
    event = 5;
    value = GET_WHEEL_DELTA_WPARAM(wp);
    ScreenToClient(hwnd, &point);
    break;
  case WM_KEYDOWN:
  case WM_SYSKEYDOWN:
    event = 6;
    value = int(wp);
    point = {0, 0};
    break;
  case WM_RBUTTONDOWN:
    event = 9;
    break;
  case WM_MOUSELEAVE:
    event = 10;
    break;
  }
  if (!event)
    return 0;
  if (event != 6)
    MapWindowPoints(hwnd, s->host, &point, 1);
  double scale = GetDpiForWindow(s->host) / 96.;
  const double lx = event == 6 ? 0.0 : (point.x / scale - s->origin_offset_x);
  const double ly = event == 6 ? 0.0 : (point.y / scale - s->origin_offset_y);
  return s->input(s->context, id, event, lx, ly,
                  msg == WM_MOUSEHWHEEL ? -value : value,
                  Modifiers() | (msg == WM_MOUSEHWHEEL ? 1 : 0));
}
namespace {
constexpr UINT_PTR kEditPrintSubclassId = 0x5AD00002u;
HWND g_print_edit = nullptr;
COLORREF g_print_bg = CLR_INVALID;

LRESULT CALLBACK EditPrintColorSubclassProc(HWND wnd, UINT msg, WPARAM wp,
                                            LPARAM lp, UINT_PTR, DWORD_PTR) {
  const LRESULT base = DefSubclassProc(wnd, msg, wp, lp);
  if ((msg == WM_CTLCOLOREDIT || msg == WM_CTLCOLORSTATIC) &&
      reinterpret_cast<HWND>(lp) == g_print_edit && g_print_bg != CLR_INVALID) {
    HDC hdc = reinterpret_cast<HDC>(wp);
    SetBkColor(hdc, g_print_bg);
    SetBkMode(hdc, OPAQUE);
    return reinterpret_cast<LRESULT>(
        GetStockObject(g_print_bg == 0 ? BLACK_BRUSH : WHITE_BRUSH));
  }
  return base;
}

void DisableEditVisualThemeOnce(HWND hwnd, EditHook &hook) {
  if (hook.unthemed || !hwnd || !IsWindow(hwnd))
    return;
  hook.unthemed = true;
  HMODULE uxtheme = GetModuleHandleW(L"uxtheme.dll");
  if (!uxtheme)
    uxtheme = LoadLibraryW(L"uxtheme.dll");
  if (!uxtheme)
    return;
  using SetWindowThemeFn = HRESULT(WINAPI *)(HWND, LPCWSTR, LPCWSTR);
  if (auto fn = reinterpret_cast<SetWindowThemeFn>(
          GetProcAddress(uxtheme, "SetWindowTheme"))) {
    fn(hwnd, L"", L"");
  }
}

void CompositeTransparentEditToDC(Surface *s, HWND hwnd, HDC target_dc) {
  RenderFrame(s);
  RECT cr{};
  GetClientRect(hwnd, &cr);
  const int w = cr.right - cr.left;
  const int h = cr.bottom - cr.top;
  if (w <= 0 || h <= 0 || !s->buffer || !s->buffer->pixels ||
      s->buffer->width == 0 || s->buffer->height == 0) {
    return;
  }
  auto hook_it = s->edits.find(hwnd);
  if (hook_it == s->edits.end())
    return;
  EditHook &hook = hook_it->second;
  DisableEditVisualThemeOnce(hwnd, hook);

  POINT offset = {0, 0};
  MapWindowPoints(hwnd, s->host, &offset, 1);

  Framebuffer pass_b{UINT(w), UINT(h)};
  Framebuffer pass_w{UINT(w), UINT(h)};
  RECT full{0, 0, w, h};
  FillRect(pass_b.dc, &full, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
  FillRect(pass_w.dc, &full, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));

  const bool empty_idle =
      (GetWindowTextLengthW(hwnd) == 0) && !hook.ime_composing;
  uint32_t alpha_scale = 255;

  if (empty_idle) {
    alpha_scale = (hook.placeholder_argb >> 24) & 0xFF;
    if (!hook.placeholder.empty() && alpha_scale > 0) {
      const COLORREF cue_rgb = RGB((hook.placeholder_argb >> 16) & 0xFF,
                                   (hook.placeholder_argb >> 8) & 0xFF,
                                   hook.placeholder_argb & 0xFF);
      RECT fmt{0, 0, w, h};
      SendMessageW(hwnd, EM_GETRECT, 0, reinterpret_cast<LPARAM>(&fmt));
      if (fmt.right <= fmt.left || fmt.bottom <= fmt.top)
        fmt = full;
      HFONT hfont =
          reinterpret_cast<HFONT>(SendMessageW(hwnd, WM_GETFONT, 0, 0));
      const UINT dt_flags =
          DT_LEFT | DT_TOP | DT_NOPREFIX |
          (hook.multiline ? (DT_WORDBREAK | DT_EDITCONTROL) : DT_SINGLELINE);
      for (HDC dc : {pass_b.dc, pass_w.dc}) {
        HGDIOBJ old_font = hfont ? SelectObject(dc, hfont) : nullptr;
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, cue_rgb);
        RECT draw_rc = fmt;
        DrawTextW(dc, hook.placeholder.c_str(), int(hook.placeholder.size()),
                  &draw_rc, dt_flags);
        if (old_font)
          SelectObject(dc, old_font);
      }
    }
  } else {
    alpha_scale = (hook.text_argb >> 24) & 0xFF;
    HWND parent = GetParent(hwnd);
    if (!parent)
      parent = s->host;

    const LONG_PTR saved_style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if (saved_style & WS_DISABLED) {
      SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style & ~WS_DISABLED);
    }

    g_print_edit = hwnd;
    const BOOL hooked = SetWindowSubclass(
        parent, EditPrintColorSubclassProc, kEditPrintSubclassId, 0);

    g_print_bg = RGB(0, 0, 0);
    DefSubclassProc(hwnd, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(pass_b.dc),
                    PRF_CLIENT);
    g_print_bg = RGB(255, 255, 255);
    DefSubclassProc(hwnd, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(pass_w.dc),
                    PRF_CLIENT);

    if (hooked) {
      RemoveWindowSubclass(parent, EditPrintColorSubclassProc,
                           kEditPrintSubclassId);
    }
    g_print_edit = nullptr;
    g_print_bg = CLR_INVALID;

    if (saved_style & WS_DISABLED) {
      SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style);
    }
  }

  const int buf_w = int(s->buffer->width);
  const int buf_h = int(s->buffer->height);
  const size_t buf_stride = size_t(s->buffer->stride_pixels);
  for (int y = 0; y < h; ++y) {
    const int sy = max(0, min(buf_h - 1, int(offset.y) + y));
    const uint32_t *bg_row = s->buffer->pixels + size_t(sy) * buf_stride;
    uint32_t *b_row = pass_b.pixels + size_t(y) * size_t(w);
    const uint32_t *w_row = pass_w.pixels + size_t(y) * size_t(w);
    for (int x = 0; x < w; ++x) {
      const int sx = max(0, min(buf_w - 1, int(offset.x) + x));
      const uint32_t d = bg_row[sx];
      const uint32_t pb = b_row[x];
      const uint32_t pw = w_row[x];
      const int dA = (d >> 24) & 0xFF;
      const int dR = (d >> 16) & 0xFF, dG = (d >> 8) & 0xFF, dB = d & 0xFF;
      const int bR = (pb >> 16) & 0xFF, bG = (pb >> 8) & 0xFF, bB = pb & 0xFF;
      const int wR = (pw >> 16) & 0xFF, wG = (pw >> 8) & 0xFF, wB = pw & 0xFF;
      int cov_R = 255 - max(0, min(255, wR - bR));
      int cov_G = 255 - max(0, min(255, wG - bG));
      int cov_B = 255 - max(0, min(255, wB - bB));
      int pm_R = bR, pm_G = bG, pm_B = bB;
      if (alpha_scale < 255) {
        cov_R = (cov_R * int(alpha_scale) + 127) / 255;
        cov_G = (cov_G * int(alpha_scale) + 127) / 255;
        cov_B = (cov_B * int(alpha_scale) + 127) / 255;
        pm_R = (pm_R * int(alpha_scale) + 127) / 255;
        pm_G = (pm_G * int(alpha_scale) + 127) / 255;
        pm_B = (pm_B * int(alpha_scale) + 127) / 255;
      }
      const int invA_R = 255 - cov_R;
      const int invA_G = 255 - cov_G;
      const int invA_B = 255 - cov_B;
      const int invA = (invA_R + invA_G + invA_B) / 3;
      const uint32_t outA =
          uint32_t(min(255, (255 - invA) + (invA * dA + 127) / 255));
      const uint32_t outR =
          uint32_t(min(255, pm_R + (invA_R * dR + 127) / 255));
      const uint32_t outG =
          uint32_t(min(255, pm_G + (invA_G * dG + 127) / 255));
      const uint32_t outB =
          uint32_t(min(255, pm_B + (invA_B * dB + 127) / 255));
      b_row[x] = (outA << 24) | (outR << 16) | (outG << 8) | outB;
    }
  }
  BitBlt(target_dc, 0, 0, w, h, pass_b.dc, 0, 0, SRCCOPY);
}

void PaintTransparentEdit(Surface *s, HWND hwnd) {
  PAINTSTRUCT ps{};
  HDC screen_dc = BeginPaint(hwnd, &ps);
  CompositeTransparentEditToDC(s, hwnd, screen_dc);
  EndPaint(hwnd, &ps);
  auto hook_it = s->edits.find(hwnd);
  if (hook_it != s->edits.end() && hook_it->second.caret_hidden) {
    hook_it->second.caret_hidden = false;
    ShowCaret(hwnd);
  }
}
} // namespace

LRESULT CALLBACK EditProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR,
                          DWORD_PTR data) {
  auto *s = reinterpret_cast<Surface *>(data);
  auto found = s->edits.find(hwnd);
  if (found == s->edits.end())
    return DefSubclassProc(hwnd, msg, wp, lp);
  const bool transparent = found->second.transparent_bg;
  auto id = found->second.id;
  if (msg == WM_IME_STARTCOMPOSITION) {
    found->second.ime_composing = true;
  } else if (msg == WM_IME_ENDCOMPOSITION) {
    found->second.ime_composing = false;
  } else if (msg == WM_KILLFOCUS || msg == WM_NCDESTROY) {
    found->second.caret_hidden = false;
    found->second.ime_composing = false;
  }
  if (transparent) {
    if (msg == WM_ERASEBKGND)
      return 1;
    if (msg == WM_PRINTCLIENT && g_print_edit != hwnd) {
      CompositeTransparentEditToDC(s, hwnd, reinterpret_cast<HDC>(wp));
      return 0;
    }
    if (msg == WM_PAINT) {
      if (found->second.pending_text_paint || s->defer_commit) {
        PAINTSTRUCT ps{};
        BeginPaint(hwnd, &ps);
        EndPaint(hwnd, &ps);
        return 0;
      }
      PaintTransparentEdit(s, hwnd);
      return 0;
    }
  }
  if (msg == WM_KEYDOWN && wp == VK_TAB) {
    sui_surface_focus_next(s, hwnd, (Modifiers() & 1) != 0);
    return 0;
  }
  if ((msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN || msg == WM_MOUSEWHEEL) &&
      Input(s, hwnd, id, msg, wp, lp))
    return 0;
  auto snapshot_text = [](HWND edit_hwnd) -> std::wstring {
    int len = GetWindowTextLengthW(edit_hwnd);
    if (len <= 0) return {};
    std::wstring buf(size_t(len) + 1, L'\0');
    GetWindowTextW(edit_hwnd, buf.data(), len + 1);
    buf.resize(size_t(len));
    return buf;
  };
  found->second.en_change_fired = false;
  const bool suppress_direct_paint =
      transparent &&
      (msg == WM_CHAR || msg == EM_REPLACESEL || msg == WM_PASTE ||
       msg == WM_CUT || msg == WM_CLEAR || msg == WM_UNDO ||
       msg == WM_IME_STARTCOMPOSITION || msg == WM_IME_COMPOSITION ||
       msg == WM_IME_ENDCOMPOSITION || msg == WM_IME_CHAR ||
       (msg == WM_KEYDOWN && (wp == VK_BACK || wp == VK_DELETE)));
  std::wstring before_text = suppress_direct_paint ? snapshot_text(hwnd) : std::wstring{};
  LONG_PTR saved_style = 0;
  if (suppress_direct_paint) {
    saved_style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    if (saved_style & WS_VISIBLE) {
      SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style & ~WS_VISIBLE);
    }
  }
  const LRESULT res = DefSubclassProc(hwnd, msg, wp, lp);
  if (suppress_direct_paint && (saved_style & WS_VISIBLE)) {
    SetWindowLongPtrW(hwnd, GWL_STYLE, saved_style);
  }
  auto after = s->edits.find(hwnd);
  const bool text_mutated =
      suppress_direct_paint && IsWindow(hwnd) && (snapshot_text(hwnd) != before_text);
  const bool changed =
      (after != s->edits.end()) && (after->second.en_change_fired || text_mutated);
  if (after != s->edits.end()) {
    after->second.en_change_fired = false;
    if (changed) {
      after->second.pending_text_paint = true;
      ValidateRect(hwnd, nullptr);
      if (GetFocus() == hwnd && !after->second.caret_hidden) {
        if (HideCaret(hwnd)) after->second.caret_hidden = true;
      }
    }
  }
  if (msg == WM_IME_STARTCOMPOSITION || msg == WM_IME_COMPOSITION ||
      msg == WM_IME_ENDCOMPOSITION) {
    s->callback(s->context, id, 7);
  }
  if (transparent && !changed && !s->defer_commit &&
      (msg == WM_CHAR || msg == WM_KEYDOWN || msg == WM_KEYUP ||
       msg == WM_SETTEXT || msg == EM_SETSEL || msg == EM_REPLACESEL ||
       msg == WM_PASTE || msg == WM_CUT || msg == WM_CLEAR || msg == WM_UNDO ||
       msg == WM_HSCROLL || msg == WM_VSCROLL || msg == WM_SETFOCUS ||
       msg == WM_KILLFOCUS || msg == WM_LBUTTONDOWN || msg == WM_LBUTTONUP ||
       msg == WM_LBUTTONDBLCLK || (msg == WM_MOUSEMOVE && (wp & MK_LBUTTON)) ||
       msg == WM_IME_STARTCOMPOSITION || msg == WM_IME_COMPOSITION ||
       msg == WM_IME_ENDCOMPOSITION)) {
    RedrawWindow(hwnd, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW);
  }
  return res;
}
LRESULT CALLBACK HostProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR,
                          DWORD_PTR data) {
  auto *s = reinterpret_cast<Surface *>(data);
  FrameTrace::Span traced(s->trace,
      msg == WM_MOUSEMOVE || msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL ? 1 :
      msg == deferred_input ? 2 : msg == WM_TIMER ? 5 : 0, int(msg), hwnd);
  if (msg == WM_NCDESTROY && hwnd == s->host) s->trace.Finish();
  // NativeAPI observes notifications on its content HWND. Scroll grouping is
  // an implementation detail and must not interrupt BUTTON/EDIT notifications.
  if (hwnd != s->host &&
      (msg == WM_COMMAND || msg == WM_CTLCOLOREDIT || msg == WM_CTLCOLORSTATIC))
    return SendMessageW(s->host, msg, wp, lp);
  if (hwnd == s->host && msg == WM_COMMAND && HIWORD(wp) == EN_CHANGE && lp) {
    auto edit_it = s->edits.find(reinterpret_cast<HWND>(lp));
    if (edit_it != s->edits.end() && edit_it->second.transparent_bg) {
      edit_it->second.en_change_fired = true;
      edit_it->second.pending_text_paint = true;
    }
  }
  if (msg == WM_DPICHANGED || msg == WM_DPICHANGED_AFTERPARENT) {
    // NativeAPI first applies the suggested bounds. Logical dimensions may
    // stay identical, but retained control frames still need the new DPI.
    const auto result = DefSubclassProc(hwnd, msg, wp, lp);
    if (hwnd == s->host && s->input)
      s->input(s->context, 0, 12, 0, 0, 0, 0);
    return result;
  }
  if (msg == deferred_input) {
    if (s->input)
      s->input(s->context, 0, 11, 0, 0, 0, 0);
    return 0;
  }
  if (msg == WM_PAINT || msg == WM_PRINTCLIENT || msg == WM_ERASEBKGND)
    return Paint(s, hwnd, msg, wp);
  if (msg == WM_TIMER && wp == subclass_id) {
    if (s->input)
      s->input(s->context, 0, 8, 0, 0, 0, 0);
    return 0;
  }
  if (msg == WM_DRAWITEM && lp) {
    auto *item = reinterpret_cast<DRAWITEMSTRUCT *>(lp);
    auto found = s->buttons.find(item->hwndItem);
    if (found != s->buttons.end() && found->second.custom_draw) {
      Draw(s, item->hwndItem, item->hDC);
      return TRUE;
    }
  }
  if (msg == WM_LBUTTONDOWN) {
    SetCapture(hwnd);
    HWND cur_focus = GetFocus();
    if (!cur_focus || (cur_focus != s->host && !IsChild(s->host, cur_focus))) {
      SetFocus(s->host);
    }
  }
  if (msg == WM_LBUTTONUP && GetCapture() == hwnd)
    ReleaseCapture();
  if (msg == WM_MOUSEMOVE) {
    TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&track);
  }
  if (Input(s, hwnd, 0, msg, wp, lp)) {
    if (msg == WM_LBUTTONDOWN && GetCapture() == hwnd &&
        !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
      ReleaseCapture();
    }
    return 0;
  }
  if (msg == WM_KEYDOWN && wp == VK_TAB) {
    sui_surface_focus_next(s, nullptr, (GetKeyState(VK_SHIFT) & 0x8000) != 0);
    return 0;
  }
  return DefSubclassProc(hwnd, msg, wp, lp);
}
LRESULT CALLBACK ButtonProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR,
                            DWORD_PTR data) {
  auto *s = reinterpret_cast<Surface *>(data);
  FrameTrace::Span traced(s->trace,
      msg == WM_MOUSEMOVE || msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL ? 1 : 0,
      int(msg), hwnd);
  auto found = s->buttons.find(hwnd);
  if (found == s->buttons.end())
    return DefSubclassProc(hwnd, msg, wp, lp);
  // Scrolling only moves the clipping parent with redraw suppressed. Native
  // button state changes can still schedule their own paint, which the next
  // canvas publication must absorb. Do not scan every HWND on every scroll.
  switch (msg) {
  case WM_MOUSEMOVE:
  case WM_MOUSELEAVE:
  case BM_SETSTATE:
  case WM_SETFOCUS:
  case WM_KILLFOCUS:
  case WM_SETTEXT:
  case WM_SETFONT:
  case WM_ENABLE:
  case WM_STYLECHANGED:
  case WM_WINDOWPOSCHANGED:
    s->native_state_changed = true;
    break;
  }
  const int64_t id = found->second.id;
  if ((msg == WM_MOUSEWHEEL || msg == WM_MOUSEHWHEEL || msg == WM_RBUTTONDOWN ||
       msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) &&
      Input(s, hwnd, id, msg, wp, lp))
    return 0;
  if (found->second.custom_draw &&
      (msg == WM_PAINT || msg == WM_PRINTCLIENT || msg == WM_ERASEBKGND))
    return Paint(s, hwnd, msg, wp);
  if (msg == WM_KEYDOWN && wp == VK_TAB) {
    sui_surface_focus_next(s, hwnd, (GetKeyState(VK_SHIFT) & 0x8000) != 0);
    return 0;
  }
  if (msg == WM_KEYDOWN && wp == VK_RETURN && !(lp & (1L << 30))) {
    sui_button_activate(hwnd);
    return 0;
  }
  int event = 0;
  if (msg == WM_MOUSEMOVE && !found->second.hovered) {
    found->second.hovered = true;
    TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&track);
    event = 1;
  } else if (msg == WM_MOUSELEAVE && found->second.hovered) {
    found->second.hovered = false;
    event = 2;
  } else if (msg == BM_SETSTATE)
    event = wp ? 3 : 4;
  else if (msg == WM_SETFOCUS)
    event = 5;
  else if (msg == WM_KILLFOCUS)
    event = 6;
  // Capture, keyboard activation, focus and BN_CLICKED remain the BUTTON's.
  if (event)
    s->callback(s->context, id, event);
  return DefSubclassProc(hwnd, msg, wp, lp);
}
Command Box(int kind, double x, double y, double w, double h, double radius) {
  Command c;
  c.kind = kind;
  c.rect = RectF(float(x), float(y), float(w), float(h));
  c.radius = float(std::isfinite(radius) ? radius : min(w, h) / 2);
  return c;
}
void OrderControl(Surface *s, HWND hwnd) {
  if (!s->controls_updated)
    sui_controls_begin(s);
  s->control_order.push_back(hwnd);
  if (s->buttons.count(hwnd) || s->edits.count(hwnd))
    s->focus_order.push_back(hwnd);
}
ControlContext CurrentControls(Surface *s) {
  if (!s->control_contexts.empty()) return s->control_contexts.back();
  double ox = 0.0, oy = 0.0;
  EffectiveOffset(s, ox, oy);
  return ControlContext{s->host, -ox, -oy, 0, 0};
}
int ControlPixel(double value, double scale) {
  return int(std::floor(value * scale + 0.5 + 1e-8));
}
ControlContext ChildControls(Surface *s, HWND parent, double x, double y,
                             double scale) {
  const auto ancestor = CurrentControls(s);
  return {parent, x, y, ancestor.x + ControlPixel(x - ancestor.origin_x, scale),
          ancestor.y + ControlPixel(y - ancestor.origin_y, scale)};
}
native_view_t NativeView(Surface *s, HWND hwnd) {
  auto found = s->native_views.find(hwnd);
  if (found != s->native_views.end())
    return found->second;
  auto view = native_view_create_with_native_view(hwnd);
  // An existing native control already has explicit geometry. Preserve it
  // when enrolling the borrowed view in NativeAPI's absolute layout tree.
  native_view_set_frame(view, native_view_get_frame(view));
  s->native_views.emplace(hwnd, view);
  return view;
}
void ReleaseControl(Surface *s, HWND hwnd) {
  s->deferred_frames.erase(hwnd);
  s->deferred_clips.erase(hwnd);
  auto found = s->native_views.find(hwnd);
  if (found == s->native_views.end())
    return;
  auto parent = s->native_parents.find(hwnd);
  if (parent != s->native_parents.end()) {
    auto host = s->native_views.find(parent->second);
    if (host != s->native_views.end())
      native_view_remove_subview(host->second, found->second);
    s->native_parents.erase(parent);
  }
  native_view_free(found->second);
  s->native_views.erase(found);
}
void DestroyControlGroup(Surface *s, const ControlGroup &group) {
  RemoveWindowSubclass(group.window, HostProc, subclass_id);
  RemoveWindowSubclass(group.viewport, HostProc, subclass_id);
  ReleaseControl(s, group.window);
  ReleaseControl(s, group.viewport);
  DestroyWindow(group.window);
  DestroyWindow(group.viewport);
}
void ParentControl(Surface *s, HWND hwnd) {
  const auto context = CurrentControls(s);
  if (s->native_parents[hwnd] != context.parent ||
      GetParent(hwnd) != context.parent) {
    native_view_add_subview(NativeView(s, context.parent), NativeView(s, hwnd));
    s->native_parents[hwnd] = context.parent;
  }
}
void ApplyRegion(HWND hwnd, HRGN region) {
  HRGN old = CreateRectRgn(0, 0, 0, 0);
  const bool equal = GetWindowRgn(hwnd, old) != ERROR && EqualRgn(old, region);
  DeleteObject(old);
  // Changing even an identical region sends WM_WINDOWPOSCHANGED, and redraws
  // the control synchronously. Hover must not move/repaint the other controls.
  if (equal || !SetWindowRgn(hwnd, region, FALSE))
    DeleteObject(region);
}
RectF InkBounds(const Command &c) {
  auto bounds = c.rect;
  if (c.kind == 4)
    bounds.Inflate(c.stroke_width / 2, c.stroke_width / 2);
  return bounds;
}
bool SavesGraphics(int kind) {
  return kind == 2 || kind == 5 || kind == 6 || kind == 9;
}
bool Contains(RectF outer, RectF inner) {
  return outer.X <= inner.X && outer.Y <= inner.Y &&
         outer.GetRight() >= inner.GetRight() &&
         outer.GetBottom() >= inner.GetBottom();
}
bool Near(double a, double b) { return std::abs(a - b) < 0.0001; }
bool Translates(const Command &a, const Command &b, double dx, double dy,
                bool allow_color_change = false) {
  if (a.kind != b.kind || !Near(a.rect.X + dx, b.rect.X) ||
      !Near(a.rect.Y + dy, b.rect.Y) || !Near(a.rect.Width, b.rect.Width) ||
      !Near(a.rect.Height, b.rect.Height) || a.radius != b.radius ||
      a.stroke_width != b.stroke_width || a.size != b.size ||
      a.weight != b.weight || a.line_spacing != b.line_spacing ||
      (!allow_color_change && (a.fill != b.fill || a.stroke != b.stroke)) ||
      a.text != b.text || a.family != b.family || a.colors != b.colors ||
      a.path.size() != b.path.size() || a.mask != b.mask)
    return false;
  if (a.kind == 7 &&
      (!Near(a.start.X + dx, b.start.X) || !Near(a.start.Y + dy, b.start.Y) ||
       !Near(a.end.X + dx, b.end.X) || !Near(a.end.Y + dy, b.end.Y)))
    return false;
  for (size_t i = 0; i < a.path.size();) {
    if (a.path[i] != b.path[i])
      return false;
    const int op = int(a.path[i++]);
    const size_t count = op == 3 ? 0 : op == 2 ? 6 : 2;
    if (i + count > a.path.size())
      return false;
    for (const size_t end = i + count; i < end; i += 2)
      if (!Near(a.path[i] + dx, b.path[i]) ||
          !Near(a.path[i + 1] + dy, b.path[i + 1]))
        return false;
  }
  return true;
}
struct InkIterator {
  const std::vector<Command> &commands;
  size_t position, end;
  double dx, dy;
  RectF area;
  std::vector<const Command *> clips;
  bool valid = true;
  const Command *next() {
    while (position < end) {
      const auto &c = commands[position++];
      if (c.kind == 6 || c.kind == 9) {
        valid = false;
        return nullptr;
      }
      if (c.kind == 2 || c.kind == 5) {
        clips.push_back(&c);
        continue;
      }
      if (c.kind == 3) {
        if (clips.empty()) {
          valid = false;
          return nullptr;
        }
        clips.pop_back();
        continue;
      }
      if ((c.kind == 0 || c.kind == 4) && !(c.fill >> 24) && !(c.stroke >> 24))
        continue;
      auto ink = InkBounds(c);
      ink.Inflate(2, 2);
      for (const auto *clip : clips)
        ink.Intersect(clip->rect);
      ink.Offset(float(dx), float(dy));
      if (ink.IntersectsWith(area)) {
        // External bitmap files can change without changing their command.
        if (c.kind == 8) {
          valid = false;
          return nullptr;
        }
        return &c;
      }
    }
    return nullptr;
  }
};
bool ScrollInkTranslates(Surface *s, const std::vector<Command> &commands,
                         const ScrollDrawing &a, const ScrollDrawing &b,
                         RECT destination, int dx, int dy, double scale,
                         RECT &repaint) {
  RectF area(float(destination.left / scale), float(destination.top / scale),
             float((destination.right - destination.left) / scale),
             float((destination.bottom - destination.top) / scale));
  InkIterator before{commands, a.begin, a.end, dx / scale, dy / scale, area};
  InkIterator after{s->pending, b.begin, b.end, 0, 0, area};
  for (;;) {
    const auto *old = before.next(), *next = after.next();
    if (!before.valid || !after.valid)
      return false;
    if (!old || !next)
      return old == next;
    if (!Translates(*old, *next, dx / scale, dy / scale, true) ||
        before.clips.size() != after.clips.size())
      return false;
    if (old->fill != next->fill || old->stroke != next->stroke) {
      auto ink = InkBounds(*next);
      ink.Inflate(2, 2);
      RECT changed{LONG(std::floor(ink.X * scale)),
                   LONG(std::floor(ink.Y * scale)),
                   LONG(std::ceil(ink.GetRight() * scale)),
                   LONG(std::ceil(ink.GetBottom() * scale))};
      IntersectRect(&changed, &changed, &destination);
      UnionRect(&repaint, &repaint, &changed);
    }
    for (size_t i = 0; i < before.clips.size(); ++i)
      if (!Translates(*before.clips[i], *after.clips[i], dx / scale,
                      dy / scale))
        return false;
  }
}
// Pixel translation is only safe over a uniform opaque backdrop, with no
// stationary overlay intersecting the viewport. Anything uncertain repaints.
bool ScrollBackdrop(Surface *s, const ScrollDrawing &scroll, RectF copy_area) {
  RECT client = SurfaceClientRect(s);
  const float scale = GetDpiForWindow(s->host) / 96.f;
  struct Scope {
    RectF clip;
    bool complex = false;
  };
  std::vector<Scope> scopes{
      {RectF(0, 0, client.right / scale, client.bottom / scale)}};
  bool flat = true; // The framebuffer's initial clear is solid white.
  for (size_t i = 0; i < s->pending.size(); ++i) {
    if (i == scroll.begin) {
      if (scopes.back().complex || !Contains(scopes.back().clip, copy_area)) {
        return false;
      }
      i = scroll.end - 1;
      continue;
    }
    const auto &c = s->pending[i];
    if (c.kind == 6 || c.kind == 9)
      return false;
    if (c.kind == 2 || c.kind == 5) {
      auto scope = scopes.back();
      scope.clip.Intersect(c.rect);
      scope.complex |= c.kind == 5 || c.radius != 0;
      scopes.push_back(scope);
      continue;
    }
    if (c.kind == 3) {
      if (scopes.size() > 1)
        scopes.pop_back();
      continue;
    }
    if (c.kind == 0 && !(c.fill >> 24) && !(c.stroke >> 24))
      continue;
    auto ink = InkBounds(c);
    ink.Inflate(2, 2);
    ink.Intersect(scopes.back().clip);
    if (!ink.IntersectsWith(copy_area))
      continue;
    if (i >= scroll.end) {
      return false;
    }
    flat = !scopes.back().complex && c.kind == 0 && c.radius == 0 &&
           (c.fill >> 24) == 255 && c.stroke_width == 0 &&
           Contains(c.rect, copy_area) &&
           Contains(scopes.back().clip, copy_area);
  }
  return flat;
}
ScrollCopy PrepareScrollCopy(Surface *s) {
  double ox = 0.0, oy = 0.0;
  EffectiveOffset(s, ox, oy);
  if (ox != 0.0 || oy != 0.0)
    return {};
  RECT client = SurfaceClientRect(s);
  const auto dpi = GetDpiForWindow(s->host);
  if (!s->buffer || s->buffer_dpi != dpi ||
      s->buffer->width != UINT(client.right) ||
      s->buffer->height != UINT(client.bottom))
    return {};
  const double scale = dpi / 96.;
  const auto &commands = s->buffer_dirty ? s->painted_commands : s->commands;
  const auto &scrolls = s->buffer_dirty ? s->painted_scrolls : s->scrolls;
  for (const auto &b : s->pending_scrolls) {
    for (const auto &a : scrolls) {
      if (a.id != b.id || !a.viewport.Equals(b.viewport) ||
          a.begin != b.begin || a.end <= a.begin || b.end <= b.begin ||
          commands.size() - a.end != s->pending.size() - b.end)
        continue;
      const double x = (b.x - a.x) * scale, y = (b.y - a.y) * scale;
      const int dx = int(std::round(x)), dy = int(std::round(y));
      if ((!dx && !dy) || std::abs(x - dx) > 0.001 || std::abs(y - dy) > 0.001)
        continue;
      // Repaint stationary borders/overhang on every edge and reserve both
      // potential scroll-indicator strips. Only the interior can be copied.
      RECT area{LONG(std::ceil((b.viewport.X + 4) * scale)),
                LONG(std::ceil((b.viewport.Y + 4) * scale)),
                LONG(std::floor((b.viewport.GetRight() - 8) * scale)),
                LONG(std::floor((b.viewport.GetBottom() - 8) * scale))};
      IntersectRect(&area, &area, &client);
      const RectF copy_area(float(area.left / scale), float(area.top / scale),
                            float((area.right - area.left) / scale),
                            float((area.bottom - area.top) / scale));
      const bool outside =
          std::equal(commands.begin(), commands.begin() + a.begin,
                     s->pending.begin()) &&
          std::equal(commands.begin() + a.end, commands.end(),
                     s->pending.begin() + b.end);
      const bool backdrop = ScrollBackdrop(s, b, copy_area);
      if (!outside || !backdrop)
        continue;
      RECT shifted = area, destination;
      OffsetRect(&shifted, dx, dy);
      if (!IntersectRect(&destination, &area, &shifted))
        continue;
      RECT repaint{};
      const bool ink = ScrollInkTranslates(s, commands, a, b, destination, dx,
                                           dy, scale, repaint);
      if (!ink)
        continue;
      // A broad theme/content change is cheaper to redraw. Small hover color
      // changes repaint their ink over the translated, last-painted pixels.
      if (int64_t(repaint.right - repaint.left) *
              (repaint.bottom - repaint.top) >
          int64_t(destination.right - destination.left) *
              (destination.bottom - destination.top) / 2)
        continue;
      return {destination, dx, dy, repaint};
    }
  }
  return {};
}
// When culling changes the command count, retain the common enclosing clip.
// A scroll viewport stays fixed even though its visible descendants change.
RECT ChangedScope(Surface *s, RECT client) {
  const auto &a = s->commands, &b = s->pending;
  size_t prefix = 0, suffix = 0;
  while (prefix < min(a.size(), b.size()) && a[prefix] == b[prefix])
    ++prefix;
  while (suffix < min(a.size(), b.size()) - prefix &&
         a[a.size() - suffix - 1] == b[b.size() - suffix - 1])
    ++suffix;
  struct Scope {
    RECT clip;
    bool transformed;
  };
  std::vector<Scope> scopes{{client, false}};
  const double scale = GetDpiForWindow(s->host) / 96.;
  double ox = 0.0, oy = 0.0;
  EffectiveOffset(s, ox, oy);
  for (size_t i = 0; i < prefix; ++i) {
    const auto &c = a[i];
    if (SavesGraphics(c.kind)) {
      auto next = scopes.back();
      if ((c.kind == 2 || c.kind == 5) && !next.transformed) {
        const auto r = InkBounds(c);
        RECT clip{LONG(std::floor((r.X + ox) * scale)), LONG(std::floor((r.Y + oy) * scale)),
                  LONG(std::ceil((r.GetRight() + ox) * scale)),
                  LONG(std::ceil((r.GetBottom() + oy) * scale))};
        IntersectRect(&next.clip, &next.clip, &clip);
      }
      next.transformed |= c.kind == 6 || c.kind == 9;
      scopes.push_back(next);
    } else if (c.kind == 3 && scopes.size() > 1) {
      scopes.pop_back();
    }
  }
  size_t enclosing = scopes.size() - 1;
  bool simple_middle = !scopes.back().transformed;
  RECT middle_damage{};
  for (const auto *commands : {&a, &b}) {
    size_t depth = scopes.size() - 1;
    for (size_t i = prefix; i < commands->size() - suffix; ++i) {
      const auto &cmd = (*commands)[i];
      const auto kind = cmd.kind;
      if (SavesGraphics(kind)) {
        ++depth;
        simple_middle = false;
      } else if (kind == 3 && depth > 0) {
        --depth;
        simple_middle = false;
      } else if (simple_middle) {
        if (!(kind == 0 && !(cmd.fill >> 24) && !(cmd.stroke >> 24))) {
          auto r = InkBounds(cmd);
          r.Inflate(2 + cmd.stroke_width, 2 + cmd.stroke_width);
          RECT pixels{LONG(std::floor((r.X + ox) * scale)),
                      LONG(std::floor((r.Y + oy) * scale)),
                      LONG(std::ceil((r.GetRight() + ox) * scale)),
                      LONG(std::ceil((r.GetBottom() + oy) * scale))};
          UnionRect(&middle_damage, &middle_damage, &pixels);
        }
      }
      enclosing = min(enclosing, depth);
    }
  }
  if (simple_middle) {
    RECT tight{};
    IntersectRect(&tight, &middle_damage, &scopes[enclosing].clip);
    return tight;
  }
  return scopes[enclosing].clip;
}
void AddDamageRect(std::vector<RECT> &rects, const RECT &r) {
  if (IsRectEmpty(&r))
    return;
  for (auto &existing : rects) {
    RECT expanded{existing.left - 8, existing.top - 8, existing.right + 8,
                  existing.bottom + 8};
    RECT overlap{};
    if (IntersectRect(&overlap, &expanded, &r)) {
      UnionRect(&existing, &existing, &r);
      return;
    }
  }
  if (rects.size() < 12) {
    rects.push_back(r);
  } else {
    UnionRect(&rects[0], &rects[0], &r);
  }
}
RECT Damage(Surface *s, std::vector<RECT> &out_rects) {
  out_rects.clear();
  RECT client = SurfaceClientRect(s);
  if (!s->buffer || s->offset_changed_since_paint) {
    AddDamageRect(out_rects, client);
    return client;
  }
  if (s->commands.size() != s->pending.size()) {
    RECT r = ChangedScope(s, client);
    AddDamageRect(out_rects, r);
    return r;
  }
  RECT damage{};
  const double scale = GetDpiForWindow(s->host) / 96.;
  double ox = 0.0, oy = 0.0;
  EffectiveOffset(s, ox, oy);
  std::vector<bool> transforms;
  int transformed = 0;
  for (size_t i = 0; i < s->commands.size(); ++i) {
    const auto &a = s->commands[i], &b = s->pending[i];
    if (!(a == b)) {
      if (a.kind != b.kind || transformed || a.kind == 2 || a.kind == 3 ||
          a.kind == 5 || a.kind == 6 || a.kind == 9) {
        out_rects.clear();
        RECT r = ChangedScope(s, client);
        AddDamageRect(out_rects, r);
        return r;
      }
      if (!(a.kind == 0 && !(a.fill >> 24) && !(a.stroke >> 24) &&
            !(b.fill >> 24) && !(b.stroke >> 24))) {
        for (const auto *c : {&a, &b}) {
          auto r = InkBounds(*c);
          // Include antialiasing and text overhang at the edge of a node.
          r.Inflate(2 + c->stroke_width, 2 + c->stroke_width);
          RECT pixels{LONG(std::floor((r.X + ox) * scale)),
                      LONG(std::floor((r.Y + oy) * scale)),
                      LONG(std::ceil((r.GetRight() + ox) * scale)),
                      LONG(std::ceil((r.GetBottom() + oy) * scale))};
          RECT clipped{};
          if (IntersectRect(&clipped, &pixels, &client)) {
            UnionRect(&damage, &damage, &clipped);
            AddDamageRect(out_rects, clipped);
          }
        }
      }
    }
    if (b.kind == 2 || b.kind == 5 || b.kind == 6 || b.kind == 9) {
      bool transform = b.kind == 6 || b.kind == 9;
      transforms.push_back(transform);
      transformed += transform;
    } else if (b.kind == 3 && !transforms.empty()) {
      transformed -= transforms.back();
      transforms.pop_back();
    }
  }
  IntersectRect(&damage, &damage, &client);
  return damage;
}
void CommitPendingResizeImpl(Surface *s, bool from_pos_changed) {
  if (!s || !s->host || !IsWindow(s->host) || !s->defer_commit) return;
  const LONG target_w = s->pending_width;
  const LONG target_h = s->pending_height;
  if (s->has_pending_offset) {
    if (std::abs(s->origin_offset_x - s->pending_offset_x) > 1e-6 ||
        std::abs(s->origin_offset_y - s->pending_offset_y) > 1e-6) {
      s->offset_changed_since_paint = true;
    }
    s->origin_offset_x = s->pending_offset_x;
    s->origin_offset_y = s->pending_offset_y;
    s->has_pending_offset = false;
  }
  s->defer_commit = false;
  s->commit_on_pos_change = false;
  s->pending_width = 0;
  s->pending_height = 0;
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (from_pos_changed && s->host != root && target_w > 0 && target_h > 0) {
    SetWindowPos(
        s->host, nullptr, 0, 0, target_w, target_h,
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_NOREDRAW | SWP_NOCOPYBITS);
  }
  if (!s->deferred_frames.empty()) {
    if (!s->updating_views) {
      native_view_begin_updates();
      s->updating_views = true;
    }
    auto frames = std::move(s->deferred_frames);
    s->deferred_frames.clear();
    for (const auto &entry : frames) {
      if (IsWindow(entry.first)) {
        native_view_set_frame(
            NativeView(s, entry.first),
            {entry.second.x, entry.second.y, entry.second.w, entry.second.h});
      }
    }
  }
  if (s->updating_views) {
    native_view_end_updates(false);
    s->updating_views = false;
  }
  if (!s->deferred_clips.empty()) {
    auto clips = std::move(s->deferred_clips);
    s->deferred_clips.clear();
    for (const auto &entry : clips) {
      if (IsWindow(entry.first)) {
        sui_control_clip(
            entry.first, entry.second.x, entry.second.y, entry.second.w, entry.second.h);
      }
    }
  }
  for (auto &entry : s->edits) {
    entry.second.pending_text_paint = false;
  }
  s->native_state_changed = false;
  RenderFrame(s);
  PublishPendingShadow(s);
  if (root && IsWindowVisible(root)) {
    RedrawWindow(
        s->host, nullptr, nullptr,
        RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW | RDW_ALLCHILDREN);
    PositionWindowShadow(s);
  }
}
} // namespace
extern "C" {
void sui_set_application_identifier(const char *identifier) {
  if (identifier && *identifier)
    SetCurrentProcessExplicitAppUserModelID(Wide(identifier).c_str());
}
void *sui_surface_create(void *host, sui_event_callback callback, void *context,
                         uint64_t native_view) {
  InitializeGraphics();
  auto *s = new Surface{static_cast<HWND>(host), callback, context};
  if (!SetWindowSubclass(s->host, HostProc, subclass_id,
                         reinterpret_cast<DWORD_PTR>(s))) {
    delete s;
    return nullptr;
  }
  if (native_view)
    s->native_views.emplace(s->host, native_handle_retain(native_view));
  const auto style = GetWindowLongPtrW(s->host, GWL_STYLE);
  s->host_clipped_children = (style & WS_CLIPCHILDREN) != 0;
  SetWindowLongPtrW(s->host, GWL_STYLE, style & ~WS_CLIPCHILDREN);
  s->tooltip = CreateWindowExW(
      WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr, WS_POPUP | TTS_ALWAYSTIP,
      CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, s->host,
      nullptr, GetModuleHandleW(nullptr), nullptr);
  SetTimer(s->host, subclass_id, 16, nullptr);
  return s;
}
void sui_surface_destroy(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  KillTimer(s->host, subclass_id);
  while (!s->custom_views.empty())
    sui_surface_remove_custom_view(s, *s->custom_views.begin());
  while (!s->edits.empty())
    sui_surface_remove_edit(s, s->edits.begin()->first);
  for (const auto &entry : s->buttons)
    RemoveWindowSubclass(entry.first, ButtonProc, subclass_id);
  for (const auto &entry : s->buttons)
    ReleaseControl(s, entry.first);
  for (const auto &entry : s->control_groups) {
    DestroyControlGroup(s, entry.second);
  }
  ReleaseControl(s, s->host);
  if (s->updating_views)
    native_view_end_updates(false);
  RemoveWindowSubclass(s->host, HostProc, subclass_id);
  ClearWindowShadow(s);
  UnhookRoot(s);
  if (s->host_clipped_children)
    SetWindowLongPtrW(s->host, GWL_STYLE,
                      GetWindowLongPtrW(s->host, GWL_STYLE) | WS_CLIPCHILDREN);
  if (s->tooltip)
    DestroyWindow(s->tooltip);
  delete s;
}
void sui_surface_trace_duration(void *handle, int stage, double milliseconds) {
  auto *s = static_cast<Surface *>(handle);
  if (s->trace.Enabled())
    s->trace.Add(9, stage, FrameTrace::Now(), s->host,
                 uint64_t((std::max)(0.0, milliseconds) * 1000000));
}
void sui_surface_trace_update(void *handle, int begin) {
  auto *s = static_cast<Surface *>(handle);
  if (!s->trace.Enabled()) return;
  if (begin) s->trace.update_start = FrameTrace::Now();
  else s->trace.Add(2, 2, s->trace.update_start, s->host);
}
void sui_surface_schedule(void *handle) {
  PostMessageW(static_cast<Surface *>(handle)->host, deferred_input, 0, 0);
}
void sui_surface_flush(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  MSG msg;
  while (PeekMessageW(&msg, s->host, deferred_input, deferred_input, PM_REMOVE))
    DispatchMessageW(&msg);
}
void sui_surface_input(void *handle, sui_input_callback callback) {
  static_cast<Surface *>(handle)->input = callback;
}
void sui_surface_edit(void *handle, void *edit, int64_t id,
                      uint64_t native_view) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(edit);
  s->native_state_changed = true;
  if (native_view)
    s->native_views.emplace(hwnd, native_handle_retain(native_view));
  ParentControl(s, hwnd);
  s->edits.emplace(hwnd, EditHook{id});
  SetWindowSubclass(hwnd, EditProc, subclass_id,
                    reinterpret_cast<DWORD_PTR>(s));
}
void sui_surface_remove_edit(void *handle, void *edit) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(edit);
  auto found = s->edits.find(hwnd);
  if (found == s->edits.end())
    return;
  if (found->second.bg_brush)
    DeleteObject(found->second.bg_brush);
  s->edits.erase(found);
  RemoveWindowSubclass(hwnd, EditProc, subclass_id);
  ReleaseControl(s, hwnd);
}
void sui_edit_order(void *handle, void *edit) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(edit);
  ParentControl(s, hwnd);
  OrderControl(s, hwnd);
}
void sui_edit_set_transparent(void *handle, void *edit, int transparent,
                              double sample_x, double sample_y,
                              const char *placeholder, uint32_t text_argb,
                              uint32_t placeholder_argb, int multiline) {
  auto *s = static_cast<Surface *>(handle);
  if (!s)
    return;
  HWND hwnd = static_cast<HWND>(edit);
  auto found = s->edits.find(hwnd);
  if (found == s->edits.end())
    return;
  auto &hook = found->second;
  const bool want_transparent = transparent != 0;
  std::wstring next_placeholder = Wide(placeholder);
  const bool want_multiline = multiline != 0;
  const bool visual_changed =
      hook.transparent_bg != want_transparent ||
      hook.placeholder != next_placeholder || hook.text_argb != text_argb ||
      hook.placeholder_argb != placeholder_argb ||
      hook.multiline != want_multiline;
  hook.transparent_bg = want_transparent;
  hook.sample_x = sample_x;
  hook.sample_y = sample_y;
  hook.placeholder = std::move(next_placeholder);
  hook.text_argb = text_argb;
  hook.placeholder_argb = placeholder_argb;
  hook.multiline = want_multiline;
  if (hook.transparent_bg) {
    DisableEditVisualThemeOnce(hwnd, hook);
  } else {
    hook.bg_color = CLR_INVALID;
  }
  if (visual_changed && IsWindow(hwnd) && !s->defer_commit) {
    InvalidateRect(hwnd, nullptr, FALSE);
  }
}
void sui_surface_set_background(void *handle, uint32_t argb) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || s->background_argb == argb)
    return;
  s->background_argb = argb;
  s->buffer_dirty = true;
  RECT client = SurfaceClientRect(s);
  UnionRect(&s->damage, &s->damage, &client);
  s->damage_rects.clear();
  if (!s->defer_commit) {
    InvalidateRect(s->host, nullptr, FALSE);
  }
}
void sui_surface_set_window_shadow(void *handle, int enabled, int is_dark) {
  auto *s = static_cast<Surface *>(handle);
  if (!s) return;
  const bool want = enabled != 0;
  const bool dark = is_dark != 0;
  if (s->window_shadow_enabled == want && s->window_shadow_dark == dark) return;
  s->window_shadow_enabled = want;
  s->window_shadow_dark = dark;
  if (!want) {
    if (s->defer_commit) {
      s->pending_shadow.Reset();
      s->pending_shadow.clear_all = true;
      s->pending_shadow.valid = true;
    } else {
      ClearWindowShadow(s);
    }
  } else if (!s->defer_commit && s->buffer && s->buffer->pixels) {
    UpdateSurfaceWindowShadow(s);
  }
}
void sui_surface_flush_paint(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || !s->host || !IsWindow(s->host) || s->defer_commit) return;
  RenderFrame(s);
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (root && IsWindowVisible(root)) {
    RedrawWindow(
        s->host, nullptr, nullptr,
        RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW | RDW_ALLCHILDREN);
    PositionWindowShadow(s);
  }
}
void sui_surface_begin_pending_resize(void *handle, double logical_width,
                                      double logical_height) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || !s->host || !IsWindow(s->host)) return;
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (root && IsWindow(root)) {
    EnsureRootHook(s, root);
  }
  const UINT dpi = GetDpiForWindow(s->host);
  const double scale = (dpi ? dpi : 96) / 96.0;
  s->pending_width = max(1L, LONG(std::lround(logical_width * scale)));
  s->pending_height = max(1L, LONG(std::lround(logical_height * scale)));
  s->defer_commit = true;
  s->commit_on_pos_change = false;
  s->buffer_dirty = true;
  RECT pending{0, 0, s->pending_width, s->pending_height};
  UnionRect(&s->damage, &s->damage, &pending);
  s->damage_rects.clear();
}
void sui_surface_prerender_pending_resize(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || !s->host || !IsWindow(s->host)) return;
  RenderFrame(s);
  if (s->defer_commit) {
    s->commit_on_pos_change = true;
  }
}
void sui_surface_commit_pending_resize(void *handle) {
  CommitPendingResizeImpl(static_cast<Surface *>(handle), false);
}
void sui_surface_flush_edits(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || !s->host || !IsWindow(s->host) || s->defer_commit) return;
  for (auto &entry : s->edits) {
    if (entry.second.pending_text_paint) {
      entry.second.pending_text_paint = false;
      if (IsWindow(entry.first) && IsWindowVisible(entry.first)) {
        RedrawWindow(
            entry.first, nullptr, nullptr,
            RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW);
      }
    }
  }
}
void sui_surface_set_content_offset(void *handle, double ox, double oy) {
  auto *s = static_cast<Surface *>(handle);
  if (!s) return;
  s->has_pending_offset = false;
  if (std::abs(s->origin_offset_x - ox) < 1e-6 &&
      std::abs(s->origin_offset_y - oy) < 1e-6) {
    return;
  }
  s->origin_offset_x = ox;
  s->origin_offset_y = oy;
  s->offset_changed_since_paint = true;
  s->buffer_dirty = true;
  s->scroll_copy = {};
  RECT client = SurfaceClientRect(s);
  UnionRect(&s->damage, &s->damage, &client);
  s->damage_rects.clear();
}
void sui_surface_set_pending_offset(void *handle, double ox, double oy) {
  auto *s = static_cast<Surface *>(handle);
  if (!s) return;
  if (std::abs(s->origin_offset_x - ox) > 1e-6 ||
      std::abs(s->origin_offset_y - oy) > 1e-6 ||
      (s->has_pending_offset &&
       (std::abs(s->pending_offset_x - ox) > 1e-6 ||
        std::abs(s->pending_offset_y - oy) > 1e-6))) {
    s->offset_changed_since_paint = true;
    s->buffer_dirty = true;
    s->scroll_copy = {};
    RECT client = SurfaceClientRect(s);
    UnionRect(&s->damage, &s->damage, &client);
    s->damage_rects.clear();
  }
  s->pending_offset_x = ox;
  s->pending_offset_y = oy;
  s->has_pending_offset = true;
}
namespace {
LRESULT CALLBACK CustomViewProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp,
                                UINT_PTR, DWORD_PTR data) {
  auto *s = reinterpret_cast<Surface *>(data);
  if (s && (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN || msg == WM_MOUSEWHEEL)) {
    if (Input(s, hwnd, 0, msg, wp, lp))
      return 0;
  }
  if (msg == WM_CHAR && (wp == 0x0A || wp == 0x1B))
    return 0;
  return DefSubclassProc(hwnd, msg, wp, lp);
}
} // namespace
void sui_surface_custom_view(void *handle, void *view_hwnd,
                             uint64_t native_view) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(view_hwnd);
  if (!s || !hwnd)
    return;
  s->native_state_changed = true;
  if (native_view && !s->native_views.count(hwnd))
    s->native_views.emplace(hwnd, native_handle_retain(native_view));
  ParentControl(s, hwnd);
  if (s->custom_views.insert(hwnd).second) {
    SetWindowSubclass(hwnd, CustomViewProc, subclass_id,
                      reinterpret_cast<DWORD_PTR>(s));
  }
}
void sui_surface_remove_custom_view(void *handle, void *view_hwnd) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(view_hwnd);
  if (!s || !hwnd)
    return;
  if (!s->custom_views.erase(hwnd))
    return;
  RemoveWindowSubclass(hwnd, CustomViewProc, subclass_id);
  ReleaseControl(s, hwnd);
}
void sui_custom_view_order(void *handle, void *view_hwnd) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(view_hwnd);
  if (!s || !hwnd)
    return;
  ParentControl(s, hwnd);
  OrderControl(s, hwnd);
}
void sui_edit_line_metrics(void *handle, void *edit, double *center,
                           double *height) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(edit);
  const UINT dpi = GetDpiForWindow(hwnd);
  const double scale = (dpi ? dpi : 96) / 96.;
  auto found = s->edits.find(hwnd);
  HFONT hfont = reinterpret_cast<HFONT>(SendMessageW(hwnd, WM_GETFONT, 0, 0));
  if (!hfont)
    hfont = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
  LOGFONTW lf{};
  GetObjectW(hfont, sizeof(lf), &lf);
  if (found != s->edits.end()) {
    auto &hook = found->second;
    if (hook.cached_dpi == dpi && hook.lf_height == lf.lfHeight &&
        hook.lf_weight == lf.lfWeight &&
        wcscmp(hook.face, lf.lfFaceName) == 0 && hook.line_height > 0) {
      *center = hook.line_center;
      *height = hook.line_height;
      return;
    }
  }
  HDC dc = CreateCompatibleDC(nullptr);
  HGDIOBJ old_font = SelectObject(dc, hfont);
  TEXTMETRICW tm{};
  GetTextMetricsW(dc, &tm);
  const int w = max(24, int(tm.tmAveCharWidth) * 4 + 8);
  const int h = max(24, int(tm.tmHeight) + 8);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = w;
  info.bmiHeader.biHeight = -h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void *raw = nullptr;
  HBITMAP dib = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &raw, nullptr, 0);
  double resolved_height = max(1., double(tm.tmHeight)) / scale;
  double resolved_center = resolved_height * 0.5;
  if (dib && raw) {
    auto *pixels = static_cast<uint32_t *>(raw);
    std::fill(pixels, pixels + size_t(w) * h, 0xFFFFFFFFu);
    HGDIOBJ old_bmp = SelectObject(dc, dib);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(0, 0, 0));
    ExtTextOutW(dc, 2, 0, 0, nullptr, L"H", 1, nullptr);
    GdiFlush();
    int min_y = h, max_y = -1;
    for (int py = 0; py < h; ++py) {
      const uint32_t *row = pixels + size_t(py) * w;
      for (int px = 0; px < w; ++px) {
        if (((row[px] >> 16) & 255) < 220 || ((row[px] >> 8) & 255) < 220 ||
            (row[px] & 255) < 220) {
          min_y = min(min_y, py);
          max_y = max(max_y, py);
        }
      }
    }
    if (max_y >= min_y) {
      const double cap_center = ((min_y + max_y + 1) * 0.5) / scale;
      resolved_center =
          cap_center + (resolved_height * 0.5 - cap_center) * 0.25;
    }
    SelectObject(dc, old_bmp);
    DeleteObject(dib);
  }
  SelectObject(dc, old_font);
  DeleteDC(dc);
  if (found != s->edits.end()) {
    auto &hook = found->second;
    hook.cached_dpi = dpi;
    hook.lf_height = lf.lfHeight;
    hook.lf_weight = lf.lfWeight;
    wcsncpy_s(hook.face, LF_FACESIZE, lf.lfFaceName, _TRUNCATE);
    hook.line_center = resolved_center;
    hook.line_height = resolved_height;
  }
  *center = resolved_center;
  *height = resolved_height;
}
void sui_control_clip(void *control, double x, double y, double w, double h) {
  HWND hwnd = static_cast<HWND>(control);
  double scale = GetDpiForWindow(hwnd) / 96.;
  const bool visible = w > 0 && h > 0;
  const bool style_visible = (GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_VISIBLE) != 0;
  if (style_visible != visible)
    ShowWindow(hwnd, visible ? SW_SHOWNA : SW_HIDE);
  ApplyRegion(hwnd, CreateRectRgn(int(std::floor(x * scale)),
                                  int(std::floor(y * scale)),
                                  int(std::ceil((x + w) * scale)),
                                  int(std::ceil((y + h) * scale))));
}
void sui_surface_control_clip(void *handle, void *control, double x, double y,
                              double w, double h) {
  auto *s = static_cast<Surface *>(handle);
  if (s && s->defer_commit) {
    s->deferred_clips[static_cast<HWND>(control)] = {x, y, w, h};
    return;
  }
  sui_control_clip(control, x, y, w, h);
}
void sui_control_opacity(void *control, double opacity) {
  auto hwnd = static_cast<HWND>(control);
  auto style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  if (opacity < 1) {
    if (!(style & WS_EX_LAYERED))
      SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style | WS_EX_LAYERED);
    SetLayeredWindowAttributes(hwnd, 0, BYTE(max(0., min(1., opacity)) * 255),
                               LWA_ALPHA);
  } else if (style & WS_EX_LAYERED)
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style & ~WS_EX_LAYERED);
}
void sui_surface_pointer(void *handle, int event, double x, double y,
                         int value) {
  auto *s = static_cast<Surface *>(handle);
  double scale = GetDpiForWindow(s->host) / 96.;
  POINT point = {LONG(std::round((x + s->origin_offset_x) * scale)),
                 LONG(std::round((y + s->origin_offset_y) * scale))};
  UINT msg = event == 2   ? WM_LBUTTONDOWN
             : event == 3 ? WM_LBUTTONUP
             : event == 5 ? WM_MOUSEWHEEL
             : event == 9 ? WM_RBUTTONDOWN
                          : WM_MOUSEMOVE;
  WPARAM wp = (event == 1 || event == 2) ? MK_LBUTTON : 0;
  if (event == 5) {
    ClientToScreen(s->host, &point);
    wp = MAKEWPARAM(0, value);
  }
  SendMessageW(s->host, msg, wp, MAKELPARAM(point.x, point.y));
}
int sui_surface_cursor(void *handle, double *x, double *y) {
  auto *s = static_cast<Surface *>(handle);
  if (!s || !s->host || !x || !y || !IsWindowVisible(s->host))
    return 0;
  HWND root = GetAncestor(s->host, GA_ROOT);
  if (!root || !IsWindowVisible(root) || IsIconic(root))
    return 0;
  POINT cursor{};
  if (!GetCursorPos(&cursor))
    return 0;
  RECT client{};
  if (!GetClientRect(s->host, &client))
    return 0;
  POINT local = cursor;
  if (!ScreenToClient(s->host, &local) || local.x < 0 || local.y < 0 ||
      local.x >= client.right || local.y >= client.bottom)
    return 0;
  HWND hit = WindowFromPoint(cursor);
  if (!hit || (hit != s->host && hit != s->tooltip && !IsChild(s->host, hit)))
    return 0;
  const UINT dpi = GetDpiForWindow(s->host);
  const double scale = (dpi ? dpi : 96) / 96.;
  *x = local.x / scale - s->origin_offset_x;
  *y = local.y / scale - s->origin_offset_y;
  return 1;
}
void sui_surface_begin(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (s->trace.Enabled()) s->trace.publication_start = FrameTrace::Now();
  if (!s->updating_views) {
    native_view_begin_updates();
    s->updating_views = true;
  }
  if (s->defer_commit) {
    s->deferred_frames.clear();
    s->deferred_clips.clear();
  }
  s->pending.clear();
  s->pending_scrolls.clear();
  s->scroll_stack.clear();
  s->control_contexts.clear();
  s->live_groups.clear();
  s->control_order.clear();
  s->controls_updated = false;
}
void sui_surface_shape(void *h, double x, double y, double w, double height,
                       double radius, uint32_t fill, uint32_t stroke,
                       double width) {
  auto c = Box(0, x, y, w, height, radius);
  c.fill = fill;
  c.stroke = stroke;
  c.stroke_width = float(width);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
double sui_surface_scale(void *h) {
  return GetDpiForWindow(static_cast<Surface *>(h)->host) / 96.;
}
void *sui_mask_create(const uint8_t *alpha, int width, int height) {
  if (!alpha || width <= 0 || height <= 0 || width > 2048 || height > 2048)
    return nullptr;
  InitializeGraphics();
  return new MaskHandle(std::make_shared<AlphaMask>(alpha, width, height));
}
void sui_mask_destroy(void *mask) { delete static_cast<MaskHandle *>(mask); }
void sui_surface_mask(void *h, void *mask, double x, double y,
                      double width, double height, uint32_t color) {
  if (!mask) return;
  auto c = Box(10, x, y, width, height, 0);
  c.fill = color;
  c.mask = *static_cast<MaskHandle *>(mask);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_text(void *h, double x, double y, double w, double height,
                      const char *text, const char *family, double size,
                      double weight, double line_spacing, uint32_t color) {
  auto *s = static_cast<Surface *>(h);
  auto c = Box(1, x, y, w, height, 0);
  c.text = Wide(text);
  if (family && *family) {
    auto it = s->wide_families.find(family);
    if (it == s->wide_families.end()) {
      if (s->wide_families.size() >= 64)
        s->wide_families.clear();
      it = s->wide_families.emplace(family, Wide(family)).first;
    }
    c.family = it->second;
  }
  c.size = float(size);
  c.weight = float(weight);
  c.fill = color;
  c.line_spacing = float(line_spacing);
  s->pending.push_back(std::move(c));
}
void sui_surface_path(void *h, const double *commands, int count, uint32_t fill,
                      uint32_t stroke, double width, int clip) {
  Command c;
  c.kind = clip ? 5 : 4;
  c.path.assign(commands, commands + count);
  c.rect = PathBounds(c.path);
  c.fill = fill;
  c.stroke = stroke;
  c.stroke_width = float(width);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_translation(void *h, double x, double y) {
  Command c;
  c.kind = 9;
  c.rect = RectF(float(x), float(y), 0, 0);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_transform(void *h, double cx, double cy, double rotation,
                           double sx, double sy) {
  Command c;
  c.kind = 6;
  c.rect = RectF(float(cx), float(cy), 0, 0);
  c.radius = float(rotation);
  c.size = float(sx);
  c.weight = float(sy);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_gradient(void *h, double x, double y, double width,
                          double height, double sx, double sy, double ex,
                          double ey, const uint32_t *colors, int count) {
  auto c = Box(7, x, y, width, height, 0);
  c.start = PointF(float(x + sx * width), float(y + sy * height));
  c.end = PointF(float(x + ex * width), float(y + ey * height));
  c.colors.assign(colors, colors + count);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_image(void *h, const char *file, double x, double y,
                       double width, double height) {
  auto c = Box(8, x, y, width, height, 0);
  c.text = Wide(file);
  static_cast<Surface *>(h)->pending.push_back(std::move(c));
}
void sui_surface_clip(void *h, double x, double y, double w, double height,
                      double radius) {
  static_cast<Surface *>(h)->pending.push_back(Box(2, x, y, w, height, radius));
}
void sui_surface_restore(void *h) {
  Command c;
  c.kind = 3;
  static_cast<Surface *>(h)->pending.push_back(c);
}
void sui_surface_end(void *h) {
  auto *s = static_cast<Surface *>(h);
  double started = ClockMilliseconds();
  auto checkpoint = [&](int stage) {
    auto now = ClockMilliseconds();
    s->publish_times[stage] = now - started;
    started = now;
  };
  s->scroll_copy = PrepareScrollCopy(s);
  checkpoint(0);
  s->reused_pixels = 0;
  s->paint_stats = {};
  // Animation-only publications have no control traversal. Keep their hosts.
  if (s->controls_updated) {
    for (auto it = s->control_groups.begin(); it != s->control_groups.end();) {
      if (s->live_groups.count(it->first)) {
        ++it;
        continue;
      }
      DestroyControlGroup(s, it->second);
      it = s->control_groups.erase(it);
    }
    // Later painted siblings are in front. Tab order is retained separately.
    std::unordered_map<HWND, HWND> previous;
    for (auto it = s->control_order.rbegin(); it != s->control_order.rend();
         ++it) {
      auto hwnd = *it;
      auto &above = previous[GetParent(hwnd)];
      if (GetWindow(hwnd, GW_HWNDPREV) != above)
        SetWindowPos(hwnd, above ? above : HWND_TOP, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOREDRAW);
      above = hwnd;
    }
  }
  checkpoint(1);
  std::vector<size_t> scopes;
  for (size_t i = 0; i < s->pending.size(); ++i) {
    auto &command = s->pending[i];
    if (SavesGraphics(command.kind))
      scopes.push_back(i);
    else if (command.kind == 3 && !scopes.empty()) {
      s->pending[scopes.back()].clip_end = i;
      scopes.pop_back();
    }
  }
  checkpoint(2);
  if (s->updating_views && !s->defer_commit) {
    native_view_end_updates(false);
    s->updating_views = false;
  }
  checkpoint(3);
  std::vector<RECT> frame_damage_rects;
  RECT damage = Damage(s, frame_damage_rects);
  if (s->trace.Enabled() && !IsRectEmpty(&damage)) ++s->trace.frame;
  checkpoint(4);
  const bool had_existing_damage = !IsRectEmpty(&s->damage);
  UnionRect(&s->damage, &s->damage, &damage);
  if (had_existing_damage && s->damage_rects.empty()) {
    AddDamageRect(s->damage_rects, s->damage);
  } else {
    for (const auto &dr : frame_damage_rects) {
      AddDamageRect(s->damage_rects, dr);
    }
  }
  if (!s->buffer_dirty) {
    s->painted_commands = std::move(s->commands);
    s->painted_scrolls = std::move(s->scrolls);
  }
  s->commands.swap(s->pending);
  s->scrolls.swap(s->pending_scrolls);
  if (s->defer_commit) {
    if (!IsRectEmpty(&s->damage)) s->buffer_dirty = true;
    checkpoint(5);
    s->trace.Add(3, !IsRectEmpty(&damage), s->trace.publication_start, s->host);
    return;
  }
  if (!IsRectEmpty(&s->damage)) {
    s->buffer_dirty = true;
    std::vector<RECT> native_damage;
    auto native_area = [&](HWND hwnd) {
      if (!IsWindowVisible(hwnd) ||
          (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_LAYERED))
        return;
      RECT r;
      GetWindowRect(hwnd, &r);
      MapWindowPoints(nullptr, s->host, reinterpret_cast<POINT *>(&r), 2);
      if (IntersectRect(&r, &r, &s->damage))
        native_damage.push_back(r);
    };
    for (const auto &entry : s->edits)
      native_area(entry.first);
    for (HWND cv : s->custom_views)
      native_area(cv);
    for (const auto &entry : s->buttons)
      if (!entry.second.custom_draw)
        native_area(entry.first);
    // One canvas copy paints all styled controls. Independent native widgets
    // still receive their own damage; do not blit the same pixels per HWND.
    RECT exposed;
    if (GetUpdateRect(s->host, &exposed, FALSE)) {
      UnionRect(&s->damage, &s->damage, &exposed);
      if (!s->damage_rects.empty()) AddDamageRect(s->damage_rects, exposed);
    }
    if (s->native_state_changed) {
      RedrawWindow(s->host, nullptr, nullptr,
                   RDW_VALIDATE | RDW_NOERASE | RDW_NOFRAME | RDW_ALLCHILDREN);
      s->native_state_changed = false;
    }
    for (const auto &entry : s->buttons) {
      if (entry.second.custom_draw) {
        // A styled popup over an opaque native editor still needs its own
        // paint: the canvas deliberately excludes that editor's rectangle.
        if (!native_damage.empty()) {
          RECT r, overlap;
          GetWindowRect(entry.first, &r);
          MapWindowPoints(nullptr, s->host, reinterpret_cast<POINT *>(&r), 2);
          for (const auto &native : native_damage) {
            if (IntersectRect(&overlap, &r, &native)) {
              InvalidateRect(entry.first, nullptr, FALSE);
              break;
            }
          }
        }
      } else
        InvalidateRect(entry.first, nullptr, FALSE);
    }
    bool any_pending_edit = false;
    for (const auto &entry : s->edits) {
      if (entry.second.pending_text_paint) {
        any_pending_edit = true;
        break;
      }
    }
    const RECT frame_damage = s->damage;
    RedrawWindow(
        s->host, &frame_damage, nullptr,
        RDW_INVALIDATE | RDW_NOCHILDREN | (any_pending_edit ? RDW_UPDATENOW : 0));
    for (auto &entry : s->edits) {
      const bool was_pending = entry.second.pending_text_paint;
      RECT r;
      GetWindowRect(entry.first, &r);
      MapWindowPoints(nullptr, s->host, reinterpret_cast<POINT *>(&r), 2);
      if (was_pending || IntersectRect(&r, &r, &frame_damage)) {
        entry.second.pending_text_paint = false;
        if (entry.second.transparent_bg) {
          RedrawWindow(
              entry.first, nullptr, nullptr,
              RDW_INVALIDATE | RDW_NOERASE | (was_pending ? RDW_UPDATENOW : 0));
        } else {
          RedrawWindow(entry.first, nullptr, nullptr,
                       RDW_INVALIDATE | RDW_ERASE | RDW_FRAME);
        }
      }
    }
  } else {
    sui_surface_flush_edits(s);
  }
  checkpoint(5);
  s->trace.Add(3, !IsRectEmpty(&damage), s->trace.publication_start, s->host);
}
double sui_surface_publish_time(void *handle, int stage) {
  return stage >= 0 && stage < 6
             ? static_cast<Surface *>(handle)->publish_times[stage]
             : 0;
}
void sui_surface_scroll_begin(void *handle, int64_t id, int64_t revision,
                              double x, double y, double width, double height,
                              double content_x, double content_y) {
  auto *s = static_cast<Surface *>(handle);
  s->scroll_stack.push_back(s->pending_scrolls.size());
  s->pending_scrolls.push_back(
      {id, revision, RectF(float(x), float(y), float(width), float(height)),
       content_x, content_y, s->pending.size()});
}
void sui_surface_scroll_end(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (s->scroll_stack.empty())
    return;
  s->pending_scrolls[s->scroll_stack.back()].end = s->pending.size();
  s->scroll_stack.pop_back();
}
int64_t sui_surface_reused_pixels(void *handle) {
  return static_cast<Surface *>(handle)->reused_pixels;
}
sui_paint_stats sui_surface_paint_stats(void *handle) {
  return static_cast<Surface *>(handle)->paint_stats;
}
sui_paint_stats sui_surface_total_paint_stats(void *handle) {
  return static_cast<Surface *>(handle)->total_paint_stats;
}
void sui_control_tab_visible(void *handle, void *control, int visible) {
  auto *s = static_cast<Surface *>(handle);
  auto found = s->buttons.find(static_cast<HWND>(control));
  if (found != s->buttons.end())
    found->second.tab_visible = visible != 0;
}
void sui_control_frame(void *handle, void *control, double x, double y,
                       double width, double height) {
  auto *s = static_cast<Surface *>(handle);
  HWND hwnd = static_cast<HWND>(control);
  ParentControl(s, hwnd);
  const auto context = CurrentControls(s);
  const double scale = GetDpiForWindow(s->host) / 96.;
  const auto view = NativeView(s, hwnd);
  // Read through NativeAPI so a frame queued earlier in this transaction is
  // visible here, even while the physical HWND still has its previous frame.
  const auto current = native_view_get_frame(view);
  RECT before{ControlPixel(current.x, scale), ControlPixel(current.y, scale),
               ControlPixel(current.x, scale) + ControlPixel(current.width, scale),
               ControlPixel(current.y, scale) + ControlPixel(current.height, scale)};
  // Subtract logical origins before snapping. Rounding world coordinates
  // independently makes stable child frames jump at negative half pixels.
  const double local_x = x - context.origin_x, local_y = y - context.origin_y;
  const int px = ControlPixel(local_x, scale);
  const int py = ControlPixel(local_y, scale);
  const int pw = max(0, ControlPixel(width, scale));
  const int ph = max(0, ControlPixel(height, scale));
  RECT after{px, py, px + pw, py + ph};
  if (EqualRect(&before, &after)) {
    if (s->defer_commit) {
      s->deferred_frames.erase(hwnd);
    }
    return;
  }
  if (s->defer_commit) {
    s->deferred_frames[hwnd] = {local_x, local_y, width, height};
  } else {
    // NativeAPI owns the control hierarchy, coalesced layout and deferred moves.
    native_view_set_frame(view, {local_x, local_y, width, height});
  }
  RECT client = SurfaceClientRect(s), damage;
  UnionRect(&damage, &before, &after);
  OffsetRect(&damage, context.x, context.y);
  IntersectRect(&damage, &damage, &client);
  UnionRect(&s->damage, &s->damage, &damage);
  if (!s->damage_rects.empty()) AddDamageRect(s->damage_rects, damage);
}
void sui_controls_begin(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  s->controls_updated = true;
  s->focus_order.clear();
}
void sui_controls_push(void *handle, int64_t id, double x, double y,
                       double width, double height, double clip_x,
                       double clip_y, double clip_width, double clip_height) {
  auto *s = static_cast<Surface *>(handle);
  s->live_groups.insert(id);
  auto found = s->control_groups.find(id);
  if (found == s->control_groups.end()) {
    auto create = [&](HWND parent) {
      auto hwnd = CreateWindowExW(
          WS_EX_CONTROLPARENT, L"STATIC", L"",
          WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | SS_NOTIFY, 0, 0, 1, 1,
          parent, nullptr, GetModuleHandleW(nullptr), nullptr);
      if (hwnd)
        SetWindowSubclass(hwnd, HostProc, subclass_id,
                          reinterpret_cast<DWORD_PTR>(s));
      return hwnd;
    };
    auto viewport = create(CurrentControls(s).parent);
    auto content = viewport ? create(viewport) : nullptr;
    if (!content) {
      if (viewport)
        DestroyWindow(viewport);
      s->control_contexts.push_back(CurrentControls(s));
      return;
    }
    found =
        s->control_groups.emplace(id, ControlGroup{viewport, content}).first;
  }
  auto &group = found->second;
  const double scale = GetDpiForWindow(s->host) / 96.;
  sui_control_frame(s, group.viewport, clip_x, clip_y, clip_width, clip_height);
  OrderControl(s, group.viewport);
  s->control_contexts.push_back(
      ChildControls(s, group.viewport, clip_x, clip_y, scale));
  // A fixed viewport clips a translated content HWND without changing HRGNs
  // on every tick (which makes Windows recalculate every child's visibility).
  auto damage = s->damage;
  sui_control_frame(s, group.window, x, y, width, height);
  if (!EqualRect(&damage, &s->damage)) {
    double ox = 0.0, oy = 0.0;
    EffectiveOffset(s, ox, oy);
    RECT viewport{int(std::floor((clip_x + ox) * scale)),
                  int(std::floor((clip_y + oy) * scale)),
                  int(std::ceil((clip_x + ox + clip_width) * scale)),
                  int(std::ceil((clip_y + oy + clip_height) * scale))};
    UnionRect(&s->damage, &damage, &viewport);
    if (!s->damage_rects.empty()) AddDamageRect(s->damage_rects, viewport);
  }
  const auto content = ChildControls(s, group.window, x, y, scale);
  s->control_contexts.pop_back();
  s->control_contexts.push_back(content);
}
void sui_controls_pop(void *handle) {
  auto *s = static_cast<Surface *>(handle);
  if (!s->control_contexts.empty())
    s->control_contexts.pop_back();
}
void sui_surface_button(void *h, void *button, int64_t id, int custom_draw,
                        uint64_t native_view) {
  auto *s = static_cast<Surface *>(h);
  HWND hwnd = static_cast<HWND>(button);
  s->native_state_changed = true;
  if (native_view)
    s->native_views.emplace(hwnd, native_handle_retain(native_view));
  ParentControl(s, hwnd);
  s->buttons.emplace(hwnd, ButtonHook{id, custom_draw != 0});
  if (custom_draw)
    SetWindowLongPtrW(hwnd, GWL_STYLE,
                      (GetWindowLongPtrW(hwnd, GWL_STYLE) & ~BS_TYPEMASK) |
                          BS_OWNERDRAW);
  SetWindowSubclass(hwnd, ButtonProc, subclass_id,
                    reinterpret_cast<DWORD_PTR>(s));
  TOOLINFOW tool = {sizeof(tool)};
  tool.uFlags = TTF_IDISHWND | TTF_SUBCLASS;
  tool.hwnd = s->host;
  tool.uId = reinterpret_cast<UINT_PTR>(hwnd);
  tool.lpszText = const_cast<wchar_t *>(L"");
  if (s->tooltip)
    SendMessageW(s->tooltip, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
}
void sui_surface_remove_button(void *h, void *button) {
  auto *s = static_cast<Surface *>(h);
  HWND hwnd = static_cast<HWND>(button);
  RemoveWindowSubclass(hwnd, ButtonProc, subclass_id);
  TOOLINFOW tool = {sizeof(tool)};
  tool.hwnd = s->host;
  tool.uId = reinterpret_cast<UINT_PTR>(hwnd);
  if (s->tooltip)
    SendMessageW(s->tooltip, TTM_DELTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
  s->buttons.erase(hwnd);
  ReleaseControl(s, hwnd);
}
void sui_button_update(void *h, void *button, double radius, const char *help,
                       double x, double y, double w, double height) {
  auto *s = static_cast<Surface *>(h);
  HWND hwnd = static_cast<HWND>(button);
  ParentControl(s, hwnd);
  // Preserve declaration order without churning every HWND on a state update.
  OrderControl(s, hwnd);
  auto found = s->buttons.find(hwnd);
  if (found == s->buttons.end())
    return;
  auto &hook = found->second;
  RECT rect;
  GetClientRect(hwnd, &rect);
  const double limit = min(rect.right, rect.bottom) / 2.;
  const int r = int(
      std::ceil(std::isfinite(radius)
                    ? max(0., min(radius * GetDpiForWindow(hwnd) / 96., limit))
                    : limit));
  const double scale = GetDpiForWindow(hwnd) / 96.;
  RECT clipped{int(std::floor(x * scale)), int(std::floor(y * scale)),
               int(std::ceil((x + w) * scale)),
               int(std::ceil((y + height) * scale))};
  IntersectRect(&clipped, &clipped, &rect);
  // A translation does not change a fully visible control's local region.
  // Avoid allocating/querying HRGNs for every control on every scroll tick.
  if (hook.clip_width != rect.right || hook.clip_height != rect.bottom ||
      hook.clip_radius != r || !EqualRect(&hook.clip, &clipped)) {
    HRGN region = r ? CreateRoundRectRgn(0, 0, rect.right + 1, rect.bottom + 1,
                                         r * 2, r * 2)
                    : CreateRectRgn(0, 0, rect.right, rect.bottom);
    HRGN clip = CreateRectRgnIndirect(&clipped);
    CombineRgn(region, region, clip, RGN_AND);
    DeleteObject(clip);
    ApplyRegion(hwnd, region);
    hook.clip = clipped;
    hook.clip_width = rect.right;
    hook.clip_height = rect.bottom;
    hook.clip_radius = r;
  }
  if ((!help || !*help) && hook.help.empty()) {
    return;
  }
  auto text = Wide(help);
  if (text != hook.help) {
    hook.help = std::move(text);
    TOOLINFOW tool = {sizeof(tool)};
    tool.hwnd = s->host;
    tool.uId = reinterpret_cast<UINT_PTR>(hwnd);
    tool.lpszText = hook.help.data();
    if (s->tooltip)
      SendMessageW(s->tooltip, TTM_UPDATETIPTEXTW, 0,
                   reinterpret_cast<LPARAM>(&tool));
  }
}
void sui_surface_focus_next(void *h, void *current, int backward) {
  auto *s = static_cast<Surface *>(h);
  const auto count = int(s->focus_order.size());
  if (!count)
    return;
  auto found = std::find(s->focus_order.begin(), s->focus_order.end(),
                         static_cast<HWND>(current));
  int index = found == s->focus_order.end()
                  ? (backward ? 0 : -1)
                  : int(found - s->focus_order.begin());
  for (int i = 0; i < count; ++i) {
    index = (index + (backward ? count - 1 : 1)) % count;
    const auto hwnd = s->focus_order[index];
    const auto button = s->buttons.find(hwnd);
    if (button != s->buttons.end() && !button->second.tab_visible)
      continue;
    if (IsWindowVisible(hwnd) && IsWindowEnabled(hwnd)) {
      SetFocus(hwnd);
      return;
    }
  }
}
sui_size sui_measure_text(const char *text, const char *family_name,
                          double size, double weight) {
  InitializeGraphics();
  struct TextMeasureCache {
    Bitmap bitmap;
    Graphics graphics;
    std::unordered_map<std::string, std::wstring> wide_families;
    std::unordered_map<FontKey, std::unique_ptr<TextFont>, FontKeyHash> fonts;
    TextMeasureCache()
        : bitmap(1, 1, PixelFormat32bppPARGB), graphics(&bitmap) {
      graphics.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    }
  };
  static TextMeasureCache *cache = new TextMeasureCache();
  auto text_w = Wide(text);
  std::wstring family_w;
  if (family_name && *family_name) {
    auto fit = cache->wide_families.find(family_name);
    if (fit == cache->wide_families.end()) {
      if (cache->wide_families.size() >= 64)
        cache->wide_families.clear();
      fit = cache->wide_families.emplace(family_name, Wide(family_name)).first;
    }
    family_w = fit->second;
  }
  const float fsize = float(size);
  const bool bold = weight >= 600.0;
  FontKey key{family_w, FloatBits(fsize), bold};
  auto found = cache->fonts.find(key);
  if (found == cache->fonts.end()) {
    if (cache->fonts.size() >= 256)
      cache->fonts.clear();
    found = cache->fonts
                .emplace(std::move(key),
                         std::make_unique<TextFont>(family_w, fsize, bold))
                .first;
  }
  RectF measured;
  cache->graphics.MeasureString(text_w.empty() ? L" " : text_w.c_str(), -1,
                                &found->second->font, PointF(0, 0),
                                &TypographicFormat(), &measured);
  return {text_w.empty() ? 0 : std::ceil(measured.Width),
          std::ceil(measured.Height)};
}
void sui_button_activate(void *button) {
  HWND hwnd = static_cast<HWND>(button);
  if (IsWindowEnabled(hwnd))
    SendMessageW(hwnd, BM_CLICK, 0, 0);
}

namespace {
struct OffscreenCanvas {
  std::unique_ptr<Bitmap> bitmap;
  std::unique_ptr<Graphics> graphics;
};
} // namespace

void *sui_offscreen_create(int width, int height) {
  if (width <= 0 || height <= 0) return nullptr;
  InitializeGraphics();
  auto *c = new OffscreenCanvas();
  c->bitmap = std::make_unique<Bitmap>(width, height, PixelFormat32bppARGB);
  c->graphics = std::make_unique<Graphics>(c->bitmap.get());
  c->graphics->Clear(Color(0, 0, 0, 0));
  c->graphics->SetSmoothingMode(SmoothingModeAntiAlias);
  c->graphics->SetPixelOffsetMode(PixelOffsetModeHalf);
  c->graphics->SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
  return c;
}

void sui_offscreen_shape(void *canvas, double x, double y, double width,
                         double height, double radius, uint32_t fill,
                         uint32_t stroke, double stroke_width) {
  auto *c = static_cast<OffscreenCanvas *>(canvas);
  if (!c || !c->graphics || width <= 0 || height <= 0) return;
  RectF rect{float(x), float(y), float(width), float(height)};
  float rad = float(std::isfinite(radius) ? radius : min(width, height) * 0.5);
  GraphicsPath path;
  RoundedPath(path, rect, rad);
  if (fill >> 24) {
    Color fill_col(fill);
    SolidBrush brush(fill_col);
    c->graphics->FillPath(&brush, &path);
  }
  if (stroke_width > 0 && (stroke >> 24)) {
    Color stroke_col(stroke);
    Pen pen(stroke_col, float(stroke_width));
    pen.SetStartCap(LineCapRound);
    pen.SetEndCap(LineCapRound);
    pen.SetLineJoin(LineJoinRound);
    c->graphics->DrawPath(&pen, &path);
  }
}

void sui_offscreen_path(void *canvas, const double *commands, int count,
                        uint32_t fill, uint32_t stroke, double stroke_width) {
  auto *c = static_cast<OffscreenCanvas *>(canvas);
  if (!c || !c->graphics || !commands || count <= 0) return;
  std::vector<double> vec(commands, commands + count);
  GraphicsPath path;
  VectorPath(path, vec);
  if (fill >> 24) {
    path.SetFillMode(FillModeWinding);
    Color fill_col(fill);
    SolidBrush brush(fill_col);
    c->graphics->FillPath(&brush, &path);
  }
  if (stroke_width > 0 && (stroke >> 24)) {
    Color stroke_col(stroke);
    Pen pen(stroke_col, float(stroke_width));
    pen.SetStartCap(LineCapRound);
    pen.SetEndCap(LineCapRound);
    pen.SetLineJoin(LineJoinRound);
    c->graphics->DrawPath(&pen, &path);
  }
}

void sui_offscreen_text(void *canvas, double x, double y, double width,
                        double height, const char *text, double size,
                        uint32_t color) {
  auto *c = static_cast<OffscreenCanvas *>(canvas);
  if (!c || !c->graphics || !text || !(color >> 24)) return;
  auto wtext = Wide(text);
  if (wtext.empty()) return;
  FontFamily fam(L"Segoe UI");
  Font font(fam.GetLastStatus() == Ok ? &fam : FontFamily::GenericSansSerif(),
            float(max(1.0, size)), FontStyleRegular, UnitPixel);
  Color text_col(color);
  SolidBrush brush(text_col);
  StringFormat fmt(StringFormat::GenericTypographic());
  fmt.SetFormatFlags(StringFormatFlagsNoWrap);
  RectF box{float(x), float(y), float(width), float(height)};
  c->graphics->DrawString(wtext.c_str(), -1, &font, box, &fmt, &brush);
}

uint8_t *sui_offscreen_finish_png(void *canvas, int *out_len) {
  if (out_len) *out_len = 0;
  auto *c = static_cast<OffscreenCanvas *>(canvas);
  if (!c) return nullptr;
  uint8_t *result = nullptr;
  if (c->graphics) c->graphics->Flush(FlushIntentionSync);
  c->graphics.reset();
  if (c->bitmap) {
    UINT num = 0, sz = 0;
    GetImageEncodersSize(&num, &sz);
    CLSID png_clsid{};
    bool found = false;
    if (sz > 0) {
      std::vector<uint8_t> buf(sz);
      auto *info = reinterpret_cast<ImageCodecInfo *>(buf.data());
      GetImageEncoders(num, sz, info);
      for (UINT i = 0; i < num; ++i) {
        if (wcscmp(info[i].MimeType, L"image/png") == 0) {
          png_clsid = info[i].Clsid;
          found = true;
          break;
        }
      }
    }
    if (found) {
      IStream *stream = nullptr;
      if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) && stream) {
        if (c->bitmap->Save(stream, &png_clsid, nullptr) == Ok) {
          HGLOBAL hg = nullptr;
          if (SUCCEEDED(GetHGlobalFromStream(stream, &hg)) && hg) {
            SIZE_T bytes = GlobalSize(hg);
            void *ptr = GlobalLock(hg);
            if (ptr && bytes > 0) {
              result = static_cast<uint8_t *>(std::malloc(bytes));
              if (result) {
                std::memcpy(result, ptr, bytes);
                if (out_len) *out_len = int(bytes);
              }
              GlobalUnlock(hg);
            }
          }
        }
        stream->Release();
      }
    }
  }
  delete c;
  return result;
}

void sui_free_bytes(void *ptr) {
  std::free(ptr);
}

void sui_window_set_dark_mode(void *window, int dark) {
  HWND hwnd = static_cast<HWND>(window);
  if (!hwnd || !IsWindow(hwnd)) return;
  BOOL value = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &value, sizeof(value));
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  RedrawWindow(hwnd, nullptr, nullptr, RDW_FRAME | RDW_INVALIDATE);
}
}
