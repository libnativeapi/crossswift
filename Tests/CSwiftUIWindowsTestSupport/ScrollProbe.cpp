#include "DrawingProbe.h"
#include "SwiftUIWindows.h"
#include <functional>
#include <string>
#include <vector>
#include <windows.h>

namespace {
void Event(void *, int64_t, int) {}
HWND Window() {
  return CreateWindowExW(0, L"STATIC", L"Scroll pixel regression",
                         WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 420,
                         240, nullptr, nullptr, GetModuleHandleW(nullptr),
                         nullptr);
}
void RegisterProbeImage(const char *key) {
  const uint8_t bmp[] = {
    0x42, 0x4D, 58, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0,
    40, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0,
    0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0xE0, 0xB0, 0x30, 0};
  sui_register_memory_image(key, bmp, sizeof(bmp));
}
void Frame(void *surface, double offset, int revision, int backdrop,
           bool overlay) {
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 1000, 1000, 0, 0xFF102030, 0, 0);
  if (backdrop == 1) {
    const uint32_t colors[]{0xFF102030, 0xFF906040};
    sui_surface_gradient(surface, 20, 20, 180, 100, 0, 0, 0, 1, colors, 2);
  }
  if (backdrop >= 5 && backdrop <= 9) {
    // A sidebar filter and transform have bounded output outside the scroll.
    sui_surface_layer_begin(surface, 240, 20, 40, 40, 0.75, 1, 0, 1);
    sui_surface_translation(surface, 240, 20);
    sui_surface_shape(surface, 0, 0, 40, 40, 2, 0xFFC03020, 0, 0);
    sui_surface_restore(surface);
    sui_surface_layer_end(surface);
  }
  sui_surface_clip(surface, 20, 20, 180, 100, 0);
  sui_surface_scroll_begin(surface, 1, revision, 20, 20, 180, 100, 20,
                           20 - offset);
  for (int y = 0; y < 400; y += 20) {
    sui_surface_shape(surface, 30, 20 + y - offset, 120, 14, 3,
                      backdrop == 4 && y == 40 ? 0x80CC00CC
                      : backdrop == 2          ? 0x80CC00CC
                      : revision == 1          ? 0x80208040
                                               : 0x80804020,
                      0xFFFFFFFF, 1);
    sui_surface_text(surface, 40, 20 + y - offset, 100, 14, "Scroll text",
                     "Segoe UI", 10, 400, 0, 0xFFFFFFFF);
  }
  if (backdrop >= 5 && backdrop <= 9) {
    sui_surface_layer_begin(surface, 36, 54 - offset, 32, 24,
                            backdrop == 6 ? 0.25 : 0.8, 1, 0, 1);
    sui_surface_translation(surface, 36, 54 - offset);
    sui_surface_transform(surface, 16, 12, 15, 1, 1);
    sui_surface_shape(surface, 2, 2, 26, 18, 2, 0xFF7356C1, 0, 0);
    sui_surface_restore(surface);
    sui_surface_restore(surface);
    sui_surface_layer_end(surface);
  }
  if (backdrop >= 7 && backdrop <= 9) {
    // A one-pixel, opaque 24-bit BMP, drawn larger so an incorrect copy
    // or missed repaint is visible in the framebuffer comparison.
    const char *key = "mem://crossswift-scroll-probe.bmp";
    RegisterProbeImage(key);
    sui_surface_image(surface, backdrop == 7 ? key : "mem://unresolved",
                      76, 54 - offset, 24, 18);
    if (backdrop == 9)
      sui_surface_image(surface, "mem://large-unresolved", 21, 21 - offset, 180, 110);
  }
  if (backdrop >= 10) {
    const uint32_t fill = backdrop == 10 ? 0 : 0xFFB82345;
    sui_surface_shape(surface, 32, 36 - offset, 10, 10, 1, fill, 0, 0);
    sui_surface_shape(surface, 168, 98 - offset, 12, 10, 1, fill, 0, 0);
  }
  sui_surface_shape(surface, 194, 20 + offset / 4, 4, 20, 2, 0xFF999999, 0, 0);
  if (backdrop == 3)
    sui_surface_shape(surface, 50, 50, 10, 10, 0, 0xFFCC8844, 0, 0);
  sui_surface_scroll_end(surface);
  sui_surface_restore(surface);
  if (overlay)
    sui_surface_shape(surface, 40, 40, 20, 20, 0, 0xFFCC8844, 0, 0);
  sui_surface_end(surface);
}
std::vector<uint32_t> Pixels(HWND window) {
  RECT rect;
  GetClientRect(window, &rect);
  HDC screen = GetDC(window), dc = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, rect.right, rect.bottom);
  auto old = SelectObject(dc, bitmap);
  SendMessageW(window, WM_PRINTCLIENT, reinterpret_cast<WPARAM>(dc),
               PRF_CLIENT);
  GdiFlush();
  SelectObject(dc, old);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = rect.right;
  info.bmiHeader.biHeight = -rect.bottom;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  std::vector<uint32_t> pixels(rect.right * rect.bottom);
  GetDIBits(dc, bitmap, 0, rect.bottom, pixels.data(), &info, DIB_RGB_COLORS);
  DeleteObject(bitmap);
  DeleteDC(dc);
  ReleaseDC(window, screen);
  return pixels;
}
std::vector<uint32_t> TextPixels(HWND hwnd) {
  auto surface = sui_surface_create(hwnd, Event, nullptr, 0);
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 500, 300, 0, 0xFF383B3D, 0, 0);
  sui_surface_clip(surface, 24, 16, 218, 112, 4);
  sui_surface_text(surface, 20.5, 24.25, 110, 30, "Cached glyphs", "Segoe UI",
                   13, 400, 0, 0xFF44CCAA);
  sui_surface_text(surface, 51.25, 72.5, 160, 47, "First line\nsecond line",
                   "Segoe UI", 15, 600, 3, 0xAABBEEDD);
  sui_surface_restore(surface);
  sui_surface_end(surface);
  auto pixels = Pixels(hwnd);
  sui_surface_destroy(surface);
  return pixels;
}
enum class InkCase { NarrowLabel, StationaryLabel, Magnified, ImageArrival };
void InkFrame(void *surface, InkCase scenario, int offset, int version,
              const char *image_key) {
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 800, 600, 0, 0xFFFFFFFF, 0, 0);
  sui_surface_clip(surface, 20, 20, 180, 100, 0);
  sui_surface_scroll_begin(surface, 2, 0, 20, 20, 180, 100, 20, 20 - offset);
  sui_surface_shape(surface, 24, 45 - offset, 154, 18, 0, 0xFFB8B8B8, 0, 0);
  if (scenario == InkCase::NarrowLabel) {
    // The changing patch lies under the far side of the label. Partial
    // redraw must submit that label even though its layout box is elsewhere.
    sui_surface_shape(surface, 98, 43 - offset, 21, 25, 0,
                      version == 3 ? 0xFFAACCAA : 0xFFCCCCAA, 0, 0);
    const uint32_t color = version == 0 ? 0xFFCC2020 : version == 1 ? 0 : 0xFF1040D0;
    sui_surface_text(surface, 40, 40 - offset, 5, 30, "WWWWWWWW",
                     "Segoe UI", 18, 400, 0, color);
  } else if (scenario == InkCase::Magnified) {
    sui_surface_transform(surface, 80, 50 - offset, 90, 65536, 65536);
    sui_surface_shape(surface, 80 + (version ? 1.0 / 16384 : 0), 50 - offset,
                      1.0 / 4096, 1.0 / 4096, 0, 0xFFCA293E, 0, 0);
    sui_surface_restore(surface);
  } else if (scenario == InkCase::ImageArrival) {
    if (version) RegisterProbeImage(image_key);
    sui_surface_image(surface, image_key, 74, 46 - offset, 30, 24);
  }
  sui_surface_scroll_end(surface);
  sui_surface_restore(surface);
  if (scenario == InkCase::StationaryLabel)
    sui_surface_text(surface, 2, 42, 3, 30, "Stationary label overlaps viewport",
                     "Segoe UI", 18, 400, 0, 0xFFB4153B);
  sui_surface_end(surface);
}
void CheckInk(HWND actual, HWND expected, scroll_probe_result &result) {
  static unsigned long serial = 0;
  char image_key[96];
  wsprintfA(image_key, "mem://crossswift-ink-probe-%lu-%lu.bmp",
            GetCurrentProcessId(), ++serial);
  for (const auto scenario : {InkCase::NarrowLabel, InkCase::StationaryLabel,
                              InkCase::Magnified, InkCase::ImageArrival}) {
    auto surface = sui_surface_create(actual, Event, nullptr, 0);
    auto check = [&](int offset, int version, bool should_copy) {
      InkFrame(surface, scenario, offset, version, image_key);
      const auto pixels = Pixels(actual);
      if ((sui_surface_reused_pixels(surface) > 0) != should_copy)
        ++result.fallback_errors;
      auto reference = sui_surface_create(expected, Event, nullptr, 0);
      InkFrame(reference, scenario, offset, version, image_key);
      if (pixels != Pixels(expected)) ++result.pixel_errors;
      sui_surface_destroy(reference);
    };
    check(0, 0, false);
    check(4, 1, scenario == InkCase::NarrowLabel);
    if (scenario == InkCase::NarrowLabel) {
      check(8, 2, true);
      check(8, 3, false);
      check(8, 0, false);
    } else if (scenario == InkCase::ImageArrival) {
      check(8, 1, true);
    }
    sui_surface_destroy(surface);
  }
}
struct ProbeLabel {
  std::string text;
  const char *family = "Segoe UI";
  float size = 14, weight = 400, spacing = 0;
};
void LabelFrame(void *surface, const std::vector<ProbeLabel> &labels, int offset,
                int collisionStep) {
  sui_surface_begin(surface);
  sui_surface_shape(surface, 0, 0, 600, 400, 0, 0xFFFFFFFF, 0, 0);
  sui_surface_clip(surface, 16, 20, 244, 148, 0);
  sui_surface_scroll_begin(surface, 1, 0, 16, 20, 244, 148, 16, 20 - offset);
  for (size_t i = 0; i < labels.size(); ++i) {
    const auto &label = labels[i];
    const bool highlighted = collisionStep >= 0 ? collisionStep % 3 == 1 : offset == 4;
    const auto color = (i == 1 && highlighted) ? 0xFF3055D0 : 0xFF99333A;
    const int y = collisionStep >= 0 ? 30 + int(i) * 21 : 42 + int(i) * 32;
    sui_surface_text(surface, 34, y - offset, 5, collisionStep >= 0 ? 20 : 24,
                     label.text.c_str(), label.family, label.size, label.weight,
                     label.spacing, color);
  }
  sui_surface_scroll_end(surface);
  sui_surface_restore(surface);
  sui_surface_end(surface);
}
void CheckLabelInk(HWND actual, HWND expected, scroll_probe_result &result) {
  std::string slots[512];
  std::vector<ProbeLabel> collisions;
  for (int i = 0; collisions.empty(); ++i) {
    const auto text = "W" + std::to_string(i) + " overlapping text";
    const std::wstring wide(text.begin(), text.end());
    auto &prior = slots[std::hash<std::wstring>{}(wide) % 512];
    if (prior.empty()) prior = text;
    else collisions = {{prior}, {text}};
  }
  auto check = [&](void *surface, const std::vector<ProbeLabel> &labels,
                   int offset, bool shouldCopy, int collisionStep = -1) {
    LabelFrame(surface, labels, offset, collisionStep);
    const auto actualPixels = Pixels(actual);
    if ((sui_surface_reused_pixels(surface) > 0) != shouldCopy)
      ++result.fallback_errors;
    auto fresh = sui_surface_create(expected, Event, nullptr, 0);
    LabelFrame(fresh, labels, offset, collisionStep);
    if (actualPixels != Pixels(expected)) ++result.pixel_errors;
    sui_surface_destroy(fresh);
  };
  auto surface = sui_surface_create(actual, Event, nullptr, 0);
  // A half-pixel tie at 144 DPI moves between rounding directions here.
  // Alternate the colliding labels while changing one row's foreground.
  const std::vector<ProbeLabel> rows{collisions[1], collisions[0],
                                     collisions[1], collisions[0]};
  for (int step = 0; step < 15; ++step)
    check(surface, rows, 4 * (step % 4), step != 0, step);
  // Every label must keep its own measured overhang, including two sizes,
  // font families, weights and multiline line spacings with identical text.
  const std::string lines = "Wide\nlabel";
  const std::vector<ProbeLabel> styled{
      {lines, "Segoe UI", 13, 400, 0}, {lines, "Arial", 13, 400, 0},
      {lines, "Segoe UI", 13, 700, 0}, {lines, "Segoe UI", 13, 400, 7},
      {lines, "Segoe UI", 18, 400, 0}};
  check(surface, styled, 0, false);
  check(surface, styled, 4, true);
  check(surface, styled, 8, true);
  // A different surface can evict all 512 measurements. Unknown text must
  // repaint until this surface has observed its metrics again.
  auto eviction = sui_surface_create(expected, Event, nullptr, 0);
  sui_surface_begin(eviction);
  for (int i = 0; i < 520; ++i) {
    const auto text = "Eviction label " + std::to_string(i);
    sui_surface_text(eviction, 20, 30, 130, 20, text.c_str(), "Segoe UI", 12, 400, 0, 0xFF333333);
  }
  sui_surface_end(eviction);
  Pixels(expected);
  sui_surface_destroy(eviction);
  check(surface, styled, 12, false);
  check(surface, styled, 16, true);
  // Long strings stay out of the metadata cache. An excessively wide line
  // also exceeds the DirectWrite bitmap budget and exercises GDI+ fallback.
  std::string longText = "Long visible label";
  for (int i = 0; i < 1100; ++i) longText += u8"\u200b";
  const std::vector<ProbeLabel> longLine{{longText}};
  check(surface, longLine, 0, false);
  check(surface, longLine, 4, false);
  const std::vector<ProbeLabel> fallback{{std::string(500, 'W'), "Segoe UI", 24, 400, 0}};
  check(surface, fallback, 0, false);
  check(surface, fallback, 4, false);
  sui_surface_destroy(surface);
}
} // namespace
scroll_probe_result scroll_probe(void) {
  scroll_probe_result result{};
  HWND actual = Window(), expected = Window();
  auto surface = sui_surface_create(actual, Event, nullptr, 0);
  auto check = [&](double offset, int revision, int backdrop, bool overlay,
                   bool reuse) {
    Frame(surface, offset, revision, backdrop, overlay);
    const auto pixels = Pixels(actual);
    const bool copied = sui_surface_reused_pixels(surface) > 0;
    if (copied)
      ++result.copies;
    if (copied != reuse)
      ++result.fallback_errors;
    auto fresh = sui_surface_create(expected, Event, nullptr, 0);
    Frame(fresh, offset, revision, backdrop, overlay);
    if (pixels != Pixels(expected))
      ++result.pixel_errors;
    sui_surface_destroy(fresh);
  };
  check(0, 1, 0, false, false);
  for (double offset : {4., 8., 4., 0.})
    check(offset, 1, 0, false, true);
  check(4, 2, 0, false, false); // Content changed.
  check(8, 2, 2, false, false); // Changed paint with the same caller revision.
  check(4, 2, 2, false, true);
  check(0, 2, 3, false, false);
  check(4, 2, 3, false,
        false); // A stationary element inside the scroll content.
  check(0, 2, 1, false, false);
  check(4, 2, 1, false, false); // Nonuniform background.
  check(0, 2, 0, true, false);
  check(4, 2, 0, true, false); // Stationary overlay.
  check(0, 2, 0, false, false);
  check(48. / GetDpiForWindow(actual), 2, 0, false,
        false);                   // Half a physical pixel.
  check(160, 2, 0, false, false); // No overlapping pixels.
  check(0, 2, 0, false, false);
  Frame(surface, 4, 2, 0,
        false); // Reuse must refer to the last painted frame, not this pending
                // one.
  check(8, 2, 0, false, true);
  Frame(surface, 12, 2, 0, false);
  check(16, 3, 4, false, true); // Pending scroll plus local hover ink change.
  check(20, 3, 0, false, true); // Removing the hover repaints its old ink.
  check(0, 3, 5, false, false);
  check(4, 3, 5, false, true);
  check(8, 3, 6, false, false); // The opacity of a visible layer changed.
  check(12, 3, 6, false, true);
  check(0, 3, 7, false, false);
  check(4, 3, 7, false, true);
  check(8, 3, 8, false, false);
  check(12, 3, 8, false, true); // Redraw the small unresolved image inside the copy.
  check(0, 3, 9, false, false);
  check(4, 3, 9, false, false); // Large uncertain regions fall back.
  check(0, 3, 10, false, false);
  check(4, 3, 11, false, true); // Two distant hover regions gained ink.
  check(0, 3, 10, false, true); // Both pass back through zero opacity.
  sui_surface_destroy(surface);
  // The second surface blits glyphs rasterized by the first. Every output
  // pixel, including the fractional placement and clipped edges, must agree.
  CheckInk(actual, expected, result);
  CheckLabelInk(actual, expected, result);
  const auto cold = TextPixels(actual);
  if (cold != TextPixels(expected)) ++result.pixel_errors;
  DestroyWindow(actual);
  DestroyWindow(expected);
  return result;
}
