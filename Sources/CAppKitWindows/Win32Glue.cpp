#ifdef _WIN32
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>
#include <dwmapi.h>
#include <commctrl.h>
#include <imm.h>
#include <bcrypt.h>
#include <wincred.h>
#include <objidl.h>
#include <gdiplus.h>
#pragma comment(lib, "comctl32.lib")

#include "CAppKitWindows.h"

#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <cerrno>
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#include <mutex>
#include <share.h>
#include <string>
#include <sys/stat.h>
#include <unordered_map>
#include <vector>

namespace {

std::wstring ToWide(const char *utf8) {
  if (!utf8 || !*utf8) return L"";
  int needed = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  if (needed <= 1) return L"";
  std::wstring out(needed - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out.data(), needed);
  return out;
}

std::string ToUtf8(const std::wstring &wide) {
  if (wide.empty()) return "";
  int needed = WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), nullptr, 0, nullptr, nullptr);
  if (needed <= 0) return "";
  std::string out(needed, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), out.data(), needed, nullptr, nullptr);
  return out;
}

char *DupString(const std::string &s) {
  char *buf = (char *)std::malloc(s.size() + 1);
  if (!buf) return nullptr;
  std::memcpy(buf, s.data(), s.size());
  buf[s.size()] = '\0';
  return buf;
}

void CopyToBuf(const std::string &s, char *buf, int cap) {
  if (!buf || cap <= 0) return;
  size_t n = std::min((size_t)(cap - 1), s.size());
  std::memcpy(buf, s.data(), n);
  buf[n] = '\0';
}

void EnsureGdiPlus() {
  static ULONG_PTR token = 0;
  static bool initialized = false;
  if (!initialized) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&token, &input, nullptr) == Gdiplus::Ok) {
      initialized = true;
    }
  }
}

bool GetPngClsid(CLSID *out_clsid) {
  EnsureGdiPlus();
  UINT num = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return false;
  std::vector<uint8_t> buf(size);
  auto *info = reinterpret_cast<Gdiplus::ImageCodecInfo *>(buf.data());
  Gdiplus::GetImageEncoders(num, size, info);
  for (UINT i = 0; i < num; ++i) {
    if (std::wcscmp(info[i].MimeType, L"image/png") == 0) {
      *out_clsid = info[i].Clsid;
      return true;
    }
  }
  return false;
}

uint8_t *EncodeBitmapToPng(Gdiplus::Bitmap *bmp, size_t *out_len) {
  if (!bmp || bmp->GetLastStatus() != Gdiplus::Ok) return nullptr;
  CLSID png_clsid;
  if (!GetPngClsid(&png_clsid)) return nullptr;
  IStream *stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) || !stream) return nullptr;
  uint8_t *result = nullptr;
  if (bmp->Save(stream, &png_clsid, nullptr) == Gdiplus::Ok) {
    HGLOBAL hg = nullptr;
    if (SUCCEEDED(GetHGlobalFromStream(stream, &hg)) && hg) {
      SIZE_T sz = GlobalSize(hg);
      void *ptr = GlobalLock(hg);
      if (ptr && sz > 0) {
        result = (uint8_t *)std::malloc(sz);
        if (result) {
          std::memcpy(result, ptr, sz);
          if (out_len) *out_len = sz;
        }
        GlobalUnlock(hg);
      }
    }
  }
  stream->Release();
  return result;
}

Gdiplus::Bitmap *DecodeBitmapFromMemory(const uint8_t *data, size_t len) {
  if (!data || len == 0) return nullptr;
  EnsureGdiPlus();
  HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, len);
  if (!hg) return nullptr;
  void *ptr = GlobalLock(hg);
  if (!ptr) {
    GlobalFree(hg);
    return nullptr;
  }
  std::memcpy(ptr, data, len);
  GlobalUnlock(hg);
  IStream *stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(hg, TRUE, &stream)) || !stream) {
    GlobalFree(hg);
    return nullptr;
  }
  auto *bmp = Gdiplus::Bitmap::FromStream(stream);
  stream->Release();
  if (!bmp || bmp->GetLastStatus() != Gdiplus::Ok) {
    delete bmp;
    return nullptr;
  }
  return bmp;
}

Gdiplus::Bitmap *BitmapFromHIconWithAlpha(HICON hicon) {
  if (!hicon) return nullptr;
  EnsureGdiPlus();
  ICONINFO ii{};
  if (!GetIconInfo(hicon, &ii)) return nullptr;
  BITMAP bm{};
  Gdiplus::Bitmap *result = nullptr;
  if (ii.hbmColor && GetObjectW(ii.hbmColor, sizeof(bm), &bm) && bm.bmBitsPixel == 32) {
    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = bm.bmWidth;
    bmi.bmiHeader.biHeight = -bm.bmHeight; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    std::vector<uint8_t> pixels((size_t)bm.bmWidth * (size_t)bm.bmHeight * 4);
    HDC hdc = GetDC(nullptr);
    if (GetDIBits(hdc, ii.hbmColor, 0, bm.bmHeight, pixels.data(), &bmi, DIB_RGB_COLORS)) {
      result = new Gdiplus::Bitmap(bm.bmWidth, bm.bmHeight, PixelFormat32bppARGB);
      Gdiplus::BitmapData bd{};
      Gdiplus::Rect rect(0, 0, bm.bmWidth, bm.bmHeight);
      if (result->LockBits(&rect, Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB, &bd) == Gdiplus::Ok) {
        for (int y = 0; y < bm.bmHeight; ++y) {
          std::memcpy(
              static_cast<uint8_t *>(bd.Scan0) + y * bd.Stride,
              pixels.data() + (size_t)y * bm.bmWidth * 4,
              (size_t)bm.bmWidth * 4);
        }
        result->UnlockBits(&bd);
      }
    }
    ReleaseDC(nullptr, hdc);
  }
  if (!result) {
    result = Gdiplus::Bitmap::FromHICON(hicon);
  }
  if (ii.hbmColor) DeleteObject(ii.hbmColor);
  if (ii.hbmMask) DeleteObject(ii.hbmMask);
  return result;
}

bool IsRealAppWindow(HWND hwnd) {
  if (!IsWindowVisible(hwnd)) return false;
  LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  if (ex & WS_EX_TOOLWINDOW) return false;
  HWND owner = GetWindow(hwnd, GW_OWNER);
  if (owner != nullptr && !(ex & WS_EX_APPWINDOW)) return false;
  INT cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked != 0) {
    return false;
  }
  wchar_t cls[64] = {};
  GetClassNameW(hwnd, cls, 63);
  if (std::wcscmp(cls, L"Progman") == 0 || std::wcscmp(cls, L"WorkerW") == 0 ||
      std::wcscmp(cls, L"Shell_TrayWnd") == 0 || std::wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) {
    return false;
  }
  return true;
}

int HashBCrypt(LPCWSTR alg_id, const uint8_t *key, size_t key_len, const uint8_t *data, size_t data_len, uint8_t *out, size_t out_len) {
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  ULONG flags = key ? BCRYPT_ALG_HANDLE_HMAC_FLAG : 0;
  if (BCryptOpenAlgorithmProvider(&hAlg, alg_id, nullptr, flags) != 0) return 0;
  NTSTATUS st = BCryptHash(
      hAlg,
      const_cast<PUCHAR>(key), (ULONG)key_len,
      const_cast<PUCHAR>(data), (ULONG)data_len,
      out, (ULONG)out_len);
  BCryptCloseAlgorithmProvider(hAlg, 0);
  return st == 0 ? 1 : 0;
}

} // namespace

extern "C" {

void cak_free(void *ptr) {
  std::free(ptr);
}

static bool OpenClipboardRetry() {
  for (int attempt = 0; attempt < 5; ++attempt) {
    if (OpenClipboard(nullptr)) return true;
    Sleep(3);
  }
  return false;
}

static bool ClipboardHasImage() {
  static UINT png_fmt = RegisterClipboardFormatW(L"PNG");
  static UINT mime_png_fmt = RegisterClipboardFormatW(L"image/png");
  return IsClipboardFormatAvailable(png_fmt) ||
         IsClipboardFormatAvailable(mime_png_fmt) ||
         IsClipboardFormatAvailable(CF_DIBV5) ||
         IsClipboardFormatAvailable(CF_DIB) ||
         IsClipboardFormatAvailable(CF_BITMAP);
}

char *cak_clipboard_get_text(void) {
  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  char *result = nullptr;
  HANDLE hData = GetClipboardData(CF_UNICODETEXT);
  if (hData) {
    const wchar_t *wstr = static_cast<const wchar_t *>(GlobalLock(hData));
    if (wstr) {
      result = DupString(ToUtf8(wstr));
      GlobalUnlock(hData);
    }
  }
  CloseClipboard();
  return result;
}

static int WriteClipboardTextImpl(const char *utf8_text, bool clear_first) {
  if (!utf8_text) return 0;
  std::wstring wide = ToWide(utf8_text);
  if (!OpenClipboardRetry()) return 0;
  if (clear_first) EmptyClipboard();
  size_t bytes = (wide.size() + 1) * sizeof(wchar_t);
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, bytes);
  int ok = 0;
  if (hMem) {
    void *ptr = GlobalLock(hMem);
    if (ptr) {
      std::memcpy(ptr, wide.c_str(), bytes);
      GlobalUnlock(hMem);
      if (SetClipboardData(CF_UNICODETEXT, hMem)) {
        ok = 1;
      } else {
        GlobalFree(hMem);
      }
    } else {
      GlobalFree(hMem);
    }
  }
  CloseClipboard();
  return ok;
}

int cak_clipboard_set_text(const char *utf8_text) {
  return WriteClipboardTextImpl(utf8_text, true);
}

int cak_clipboard_add_text(const char *utf8_text) {
  return WriteClipboardTextImpl(utf8_text, false);
}

char *cak_clipboard_get_files_newline(void) {
  if (!IsClipboardFormatAvailable(CF_HDROP)) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  std::string joined;
  HDROP hDrop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  if (hDrop) {
    UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      UINT len = DragQueryFileW(hDrop, i, nullptr, 0);
      if (len > 0) {
        std::wstring path(len + 1, L'\0');
        DragQueryFileW(hDrop, i, path.data(), len + 1);
        path.resize(len);
        if (!joined.empty()) joined.push_back('\n');
        joined += ToUtf8(path);
      }
    }
  }
  CloseClipboard();
  return joined.empty() ? nullptr : DupString(joined);
}

static int WriteClipboardFilesImpl(const char *const *utf8_paths, int count, bool clear_first) {
  if (!utf8_paths || count <= 0) return 0;
  std::vector<wchar_t> multi;
  for (int i = 0; i < count; ++i) {
    std::wstring w = ToWide(utf8_paths[i]);
    if (w.empty()) continue;
    for (auto &ch : w) {
      if (ch == L'/') ch = L'\\';
    }
    if (w.size() >= 3 && w[0] == L'\\' && iswalpha(w[1]) && w[2] == L':') {
      w.erase(0, 1);
    }
    multi.insert(multi.end(), w.begin(), w.end());
    multi.push_back(L'\0');
  }
  if (multi.empty()) return 0;
  multi.push_back(L'\0');
  size_t total = sizeof(DROPFILES) + multi.size() * sizeof(wchar_t);
  if (!OpenClipboardRetry()) return 0;
  if (clear_first) EmptyClipboard();
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total);
  int ok = 0;
  if (hMem) {
    auto *df = static_cast<DROPFILES *>(GlobalLock(hMem));
    if (df) {
      df->pFiles = sizeof(DROPFILES);
      df->fWide = TRUE;
      std::memcpy(reinterpret_cast<uint8_t *>(df) + sizeof(DROPFILES), multi.data(), multi.size() * sizeof(wchar_t));
      GlobalUnlock(hMem);
      if (SetClipboardData(CF_HDROP, hMem)) ok = 1;
      else GlobalFree(hMem);
    } else {
      GlobalFree(hMem);
    }
  }
  CloseClipboard();
  return ok;
}

int cak_clipboard_set_files(const char *const *utf8_paths, int count) {
  return WriteClipboardFilesImpl(utf8_paths, count, true);
}

int cak_clipboard_add_files(const char *const *utf8_paths, int count) {
  return WriteClipboardFilesImpl(utf8_paths, count, false);
}

static Gdiplus::Bitmap *BitmapFromHBitmapPreservingAlpha(HBITMAP hbmp) {
  if (!hbmp) return nullptr;
  EnsureGdiPlus();
  BITMAP bm{};
  if (GetObjectW(hbmp, sizeof(bm), &bm) && bm.bmWidth > 0 && bm.bmHeight != 0) {
    const int w = bm.bmWidth;
    const int h = std::abs(bm.bmHeight);
    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = w;
    bmi.bmiHeader.biHeight = -h; // top-down
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    std::vector<uint8_t> pixels((size_t)w * (size_t)h * 4);
    HDC hdc = GetDC(nullptr);
    int scanlines = GetDIBits(hdc, hbmp, 0, (UINT)h, pixels.data(), &bmi, DIB_RGB_COLORS);
    ReleaseDC(nullptr, hdc);
    if (scanlines > 0) {
      bool any_alpha = false;
      if (bm.bmBitsPixel == 32) {
        for (size_t i = 3; i < pixels.size(); i += 4) {
          if (pixels[i] != 0) {
            any_alpha = true;
            break;
          }
        }
      }
      if (!any_alpha) {
        for (size_t i = 3; i < pixels.size(); i += 4) {
          pixels[i] = 255;
        }
      }
      auto *out = new Gdiplus::Bitmap(w, h, PixelFormat32bppARGB);
      Gdiplus::BitmapData bd{};
      Gdiplus::Rect rect(0, 0, w, h);
      if (out->LockBits(&rect, Gdiplus::ImageLockModeWrite, PixelFormat32bppARGB, &bd) == Gdiplus::Ok) {
        for (int y = 0; y < h; ++y) {
          std::memcpy(
              static_cast<uint8_t *>(bd.Scan0) + y * bd.Stride,
              pixels.data() + (size_t)y * (size_t)w * 4,
              (size_t)w * 4);
        }
        out->UnlockBits(&bd);
        return out;
      }
      delete out;
    }
  }
  return Gdiplus::Bitmap::FromHBITMAP(hbmp, nullptr);
}

uint8_t *cak_clipboard_get_png(size_t *out_len) {
  if (out_len) *out_len = 0;
  if (!ClipboardHasImage()) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  uint8_t *result = nullptr;
  const UINT png_fmts[2] = {
      RegisterClipboardFormatW(L"PNG"),
      RegisterClipboardFormatW(L"image/png")};
  for (UINT fmt : png_fmts) {
    if (fmt && IsClipboardFormatAvailable(fmt)) {
      HANDLE hData = GetClipboardData(fmt);
      if (hData) {
        SIZE_T sz = GlobalSize(hData);
        const void *ptr = GlobalLock(hData);
        if (ptr && sz > 0) {
          result = (uint8_t *)std::malloc(sz);
          if (result) {
            std::memcpy(result, ptr, sz);
            if (out_len) *out_len = sz;
          }
          GlobalUnlock(hData);
          if (result) break;
        }
      }
    }
  }
  if (!result && IsClipboardFormatAvailable(CF_BITMAP)) {
    HBITMAP hBmp = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
    if (hBmp) {
      Gdiplus::Bitmap *bmp = BitmapFromHBitmapPreservingAlpha(hBmp);
      result = EncodeBitmapToPng(bmp, out_len);
      delete bmp;
    }
  }
  if (!result && IsClipboardFormatAvailable(CF_DIB)) {
    HANDLE hDib = GetClipboardData(CF_DIB);
    if (hDib) {
      const auto *bi = static_cast<const BITMAPINFO *>(GlobalLock(hDib));
      if (bi && bi->bmiHeader.biSize >= sizeof(BITMAPINFOHEADER)) {
        EnsureGdiPlus();
        HDC hdc = GetDC(nullptr);
        const uint8_t *base = reinterpret_cast<const uint8_t *>(bi);
        size_t palette_bytes = 0;
        if (bi->bmiHeader.biCompression == BI_BITFIELDS) {
          palette_bytes = (bi->bmiHeader.biSize == sizeof(BITMAPINFOHEADER)) ? 12 : 0;
        } else if (bi->bmiHeader.biBitCount <= 8) {
          UINT colors = bi->bmiHeader.biClrUsed ? bi->bmiHeader.biClrUsed : (1u << bi->bmiHeader.biBitCount);
          palette_bytes = colors * sizeof(RGBQUAD);
        }
        const void *bits = base + bi->bmiHeader.biSize + palette_bytes;
        HBITMAP hBmp = CreateDIBitmap(hdc, &bi->bmiHeader, CBM_INIT, bits, bi, DIB_RGB_COLORS);
        ReleaseDC(nullptr, hdc);
        if (hBmp) {
          Gdiplus::Bitmap *bmp = BitmapFromHBitmapPreservingAlpha(hBmp);
          result = EncodeBitmapToPng(bmp, out_len);
          delete bmp;
          DeleteObject(hBmp);
        }
      }
      if (bi) GlobalUnlock(hDib);
    }
  }
  CloseClipboard();
  return result;
}

static int WriteClipboardPngImpl(const uint8_t *png_data, size_t len, bool clear_first) {
  Gdiplus::Bitmap *bmp = DecodeBitmapFromMemory(png_data, len);
  if (!bmp) return 0;
  if (!OpenClipboardRetry()) {
    delete bmp;
    return 0;
  }
  if (clear_first) EmptyClipboard();
  int ok = 0;
  UINT png_fmt = RegisterClipboardFormatW(L"PNG");
  HGLOBAL hPng = GlobalAlloc(GMEM_MOVEABLE, len);
  if (hPng) {
    void *ptr = GlobalLock(hPng);
    if (ptr) {
      std::memcpy(ptr, png_data, len);
      GlobalUnlock(hPng);
      if (SetClipboardData(png_fmt, hPng)) ok = 1;
      else GlobalFree(hPng);
    } else {
      GlobalFree(hPng);
    }
  }
  const int w = (int)bmp->GetWidth();
  const int h = (int)bmp->GetHeight();
  if (w > 0 && h > 0) {
    Gdiplus::BitmapData bd{};
    Gdiplus::Rect rect(0, 0, w, h);
    if (bmp->LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &bd) == Gdiplus::Ok) {
      const size_t pixel_bytes = (size_t)w * (size_t)h * 4;
      HGLOBAL hDib = GlobalAlloc(GMEM_MOVEABLE, sizeof(BITMAPINFOHEADER) + pixel_bytes);
      if (hDib) {
        auto *hdr = static_cast<BITMAPINFOHEADER *>(GlobalLock(hDib));
        if (hdr) {
          std::memset(hdr, 0, sizeof(BITMAPINFOHEADER));
          hdr->biSize = sizeof(BITMAPINFOHEADER);
          hdr->biWidth = w;
          hdr->biHeight = h; // bottom-up DIB for maximum Win32 compatibility
          hdr->biPlanes = 1;
          hdr->biBitCount = 32;
          hdr->biCompression = BI_RGB;
          hdr->biSizeImage = (DWORD)pixel_bytes;
          uint8_t *dst = reinterpret_cast<uint8_t *>(hdr) + sizeof(BITMAPINFOHEADER);
          for (int y = 0; y < h; ++y) {
            const uint8_t *src_row =
                static_cast<const uint8_t *>(bd.Scan0) + (size_t)(h - 1 - y) * bd.Stride;
            std::memcpy(dst + (size_t)y * (size_t)w * 4, src_row, (size_t)w * 4);
          }
          GlobalUnlock(hDib);
          if (SetClipboardData(CF_DIB, hDib)) ok = 1;
          else GlobalFree(hDib);
        } else {
          GlobalFree(hDib);
        }
      }
      bmp->UnlockBits(&bd);
    }
  }
  CloseClipboard();
  delete bmp;
  return ok;
}

int cak_clipboard_set_png(const uint8_t *png_data, size_t len) {
  return WriteClipboardPngImpl(png_data, len, true);
}

int cak_clipboard_add_png(const uint8_t *png_data, size_t len) {
  return WriteClipboardPngImpl(png_data, len, false);
}

int cak_clipboard_add_custom(const char *utf8_format, const uint8_t *data, size_t len) {
  std::wstring w = ToWide(utf8_format);
  if (w.empty()) return 0;
  UINT fmt = RegisterClipboardFormatW(w.c_str());
  if (!fmt) return 0;
  if (!OpenClipboardRetry()) return 0;
  const size_t alloc_bytes = sizeof(uint64_t) + len;
  HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, alloc_bytes);
  int ok = 0;
  if (hMem) {
    auto *ptr = static_cast<uint8_t *>(GlobalLock(hMem));
    if (ptr) {
      uint64_t sz = (uint64_t)len;
      std::memcpy(ptr, &sz, sizeof(uint64_t));
      if (len > 0 && data) {
        std::memcpy(ptr + sizeof(uint64_t), data, len);
      }
      GlobalUnlock(hMem);
      if (SetClipboardData(fmt, hMem)) ok = 1;
      else GlobalFree(hMem);
    } else {
      GlobalFree(hMem);
    }
  }
  CloseClipboard();
  return ok;
}

uint8_t *cak_clipboard_get_custom(const char *utf8_format, size_t *out_len) {
  if (out_len) *out_len = 0;
  std::wstring w = ToWide(utf8_format);
  if (w.empty()) return nullptr;
  UINT fmt = RegisterClipboardFormatW(w.c_str());
  if (!fmt || !IsClipboardFormatAvailable(fmt)) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  uint8_t *result = nullptr;
  HANDLE hData = GetClipboardData(fmt);
  if (hData) {
    SIZE_T raw_sz = GlobalSize(hData);
    const auto *ptr = static_cast<const uint8_t *>(GlobalLock(hData));
    if (ptr && raw_sz >= sizeof(uint64_t)) {
      uint64_t payload_sz = 0;
      std::memcpy(&payload_sz, ptr, sizeof(uint64_t));
      if (payload_sz <= raw_sz - sizeof(uint64_t)) {
        result = (uint8_t *)std::malloc(std::max<size_t>(1, (size_t)payload_sz));
        if (result) {
          if (payload_sz > 0) std::memcpy(result, ptr + sizeof(uint64_t), (size_t)payload_sz);
          else result[0] = 0;
          if (out_len) *out_len = (size_t)payload_sz;
        }
      }
    }
    if (ptr) GlobalUnlock(hData);
  }
  CloseClipboard();
  return result;
}

uint8_t *cak_clipboard_get_rtf(size_t *out_len) {
  if (out_len) *out_len = 0;
  static UINT rtf_fmt = RegisterClipboardFormatW(L"Rich Text Format");
  if (!rtf_fmt || !IsClipboardFormatAvailable(rtf_fmt)) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  uint8_t *result = nullptr;
  HANDLE hData = GetClipboardData(rtf_fmt);
  if (hData) {
    SIZE_T sz = GlobalSize(hData);
    const char *ptr = static_cast<const char *>(GlobalLock(hData));
    if (ptr && sz > 0) {
      size_t actual = strnlen(ptr, sz);
      if (actual > 0) {
        result = (uint8_t *)std::malloc(actual);
        if (result) {
          std::memcpy(result, ptr, actual);
          if (out_len) *out_len = actual;
        }
      }
      GlobalUnlock(hData);
    }
  }
  CloseClipboard();
  return result;
}

uint8_t *cak_clipboard_get_html(size_t *out_len) {
  if (out_len) *out_len = 0;
  static UINT html_fmt = RegisterClipboardFormatW(L"HTML Format");
  if (!html_fmt || !IsClipboardFormatAvailable(html_fmt)) return nullptr;
  if (!OpenClipboardRetry()) return nullptr;
  uint8_t *result = nullptr;
  HANDLE hData = GetClipboardData(html_fmt);
  if (hData) {
    SIZE_T sz = GlobalSize(hData);
    const char *ptr = static_cast<const char *>(GlobalLock(hData));
    if (ptr && sz > 0) {
      size_t actual = strnlen(ptr, sz);
      std::string raw(ptr, actual);
      size_t start_off = 0, end_off = actual;
      auto sf = raw.find("StartFragment:");
      auto ef = raw.find("EndFragment:");
      if (sf != std::string::npos && ef != std::string::npos) {
        long s = std::strtol(raw.c_str() + sf + 14, nullptr, 10);
        long e = std::strtol(raw.c_str() + ef + 12, nullptr, 10);
        if (s >= 0 && e > s && (size_t)e <= actual) {
          start_off = (size_t)s;
          end_off = (size_t)e;
        }
      }
      const size_t frag_len = end_off - start_off;
      if (frag_len > 0) {
        result = (uint8_t *)std::malloc(frag_len);
        if (result) {
          std::memcpy(result, raw.data() + start_off, frag_len);
          if (out_len) *out_len = frag_len;
        }
      }
      GlobalUnlock(hData);
    }
  }
  CloseClipboard();
  return result;
}

int cak_open_url_or_path(const char *utf8_target) {
  std::wstring w = ToWide(utf8_target);
  if (w.empty()) return 0;
  HINSTANCE res = ShellExecuteW(nullptr, L"open", w.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(res) > 32 ? 1 : 0;
}

int cak_open_with_app(const char *utf8_app, const char *utf8_arg) {
  std::wstring app = ToWide(utf8_app);
  if (app.empty()) return 0;
  std::wstring arg = ToWide(utf8_arg);
  if (!arg.empty()) arg = L"\"" + arg + L"\"";
  HINSTANCE res = ShellExecuteW(nullptr, L"open", app.c_str(), arg.empty() ? nullptr : arg.c_str(), nullptr, SW_SHOWNORMAL);
  return reinterpret_cast<INT_PTR>(res) > 32 ? 1 : 0;
}

int cak_reveal_in_explorer(const char *utf8_path) {
  std::wstring w = ToWide(utf8_path);
  if (w.empty()) return 0;
  for (auto &ch : w) {
    if (ch == L'/') ch = L'\\';
  }
  PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(w.c_str());
  if (!pidl) return 0;
  HRESULT hr = SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
  ILFree(pidl);
  return SUCCEEDED(hr) ? 1 : 0;
}

uint32_t cak_frontmost_pid(void) {
  HWND fg = GetForegroundWindow();
  if (!fg) return 0;
  DWORD pid = 0;
  GetWindowThreadProcessId(fg, &pid);
  return (uint32_t)pid;
}

uint32_t cak_frontmost_real_pid(void) {
  HWND fg = GetForegroundWindow();
  if (fg && IsRealAppWindow(fg)) {
    DWORD pid = 0;
    GetWindowThreadProcessId(fg, &pid);
    if (pid != 0) return (uint32_t)pid;
  }
  DWORD found_pid = 0;
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    if (!IsRealAppWindow(hwnd) || IsIconic(hwnd)) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != 0) {
      *reinterpret_cast<DWORD *>(lp) = pid;
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&found_pid));
  return (uint32_t)found_pid;
}

uint32_t cak_current_pid(void) {
  return (uint32_t)GetCurrentProcessId();
}

uint32_t cak_current_thread_id(void) {
  return (uint32_t)GetCurrentThreadId();
}

int cak_process_info(uint32_t pid, char *exe_buf, int exe_cap, char *title_buf, int title_cap) {
  if (exe_buf && exe_cap > 0) exe_buf[0] = '\0';
  if (title_buf && title_cap > 0) title_buf[0] = '\0';
  if (pid == 0) return 0;
  HANDLE hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!hProc) return 0;
  wchar_t path[MAX_PATH * 2] = {};
  DWORD sz = MAX_PATH * 2;
  bool ok = QueryFullProcessImageNameW(hProc, 0, path, &sz) != FALSE;
  CloseHandle(hProc);
  if (!ok) return 0;
  CopyToBuf(ToUtf8(path), exe_buf, exe_cap);

  struct TitleCtx {
    DWORD pid;
    std::wstring title;
  } ctx{pid, L""};
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    auto *c = reinterpret_cast<TitleCtx *>(lp);
    DWORD wpid = 0;
    GetWindowThreadProcessId(hwnd, &wpid);
    if (wpid != c->pid || !IsRealAppWindow(hwnd)) return TRUE;
    int len = GetWindowTextLengthW(hwnd);
    if (len > 0) {
      c->title.resize(len + 1);
      GetWindowTextW(hwnd, c->title.data(), len + 1);
      c->title.resize(len);
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&ctx));
  CopyToBuf(ToUtf8(ctx.title), title_buf, title_cap);
  return 1;
}

int cak_activate_pid(uint32_t pid) {
  if (pid == 0) return 0;
  HWND target = nullptr;
  struct FindCtx {
    DWORD pid;
    HWND found;
  } ctx{pid, nullptr};
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    auto *c = reinterpret_cast<FindCtx *>(lp);
    DWORD wpid = 0;
    GetWindowThreadProcessId(hwnd, &wpid);
    if (wpid == c->pid && IsRealAppWindow(hwnd)) {
      c->found = hwnd;
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&ctx));
  target = ctx.found;
  if (!target) return 0;
  if (IsIconic(target)) ShowWindow(target, SW_RESTORE);
  HWND fg = GetForegroundWindow();
  if (fg == target) return 1;
  DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
  DWORD targetThread = GetWindowThreadProcessId(target, nullptr);
  DWORD curThread = GetCurrentThreadId();
  if (fgThread && fgThread != curThread) AttachThreadInput(curThread, fgThread, TRUE);
  if (targetThread && targetThread != curThread && targetThread != fgThread) {
    AttachThreadInput(curThread, targetThread, TRUE);
  }
  INPUT unlock{};
  unlock.type = INPUT_KEYBOARD;
  unlock.ki.wVk = 0xFF;
  unlock.ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(1, &unlock, sizeof(INPUT));
  BringWindowToTop(target);
  BOOL ok = SetForegroundWindow(target);
  SetActiveWindow(target);
  if (targetThread && targetThread != curThread && targetThread != fgThread) {
    AttachThreadInput(curThread, targetThread, FALSE);
  }
  if (fgThread && fgThread != curThread) AttachThreadInput(curThread, fgThread, FALSE);
  return (ok || GetForegroundWindow() == target) ? 1 : 0;
}

int cak_hide_pid(uint32_t pid) {
  if (pid == 0) return 0;
  struct HideCtx {
    DWORD pid;
    int count;
  } ctx{pid, 0};
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    auto *c = reinterpret_cast<HideCtx *>(lp);
    DWORD wpid = 0;
    GetWindowThreadProcessId(hwnd, &wpid);
    if (wpid == c->pid && IsRealAppWindow(hwnd)) {
      ShowWindow(hwnd, SW_MINIMIZE);
      c->count++;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&ctx));
  return ctx.count > 0 ? 1 : 0;
}

int cak_terminate_pid(uint32_t pid, int force) {
  if (pid == 0) return 0;
  if (!force) {
    struct CloseCtx {
      DWORD pid;
      int sent;
    } ctx{pid, 0};
    EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
      auto *c = reinterpret_cast<CloseCtx *>(lp);
      DWORD wpid = 0;
      GetWindowThreadProcessId(hwnd, &wpid);
      if (wpid == c->pid && IsWindowVisible(hwnd)) {
        PostMessageW(hwnd, WM_CLOSE, 0, 0);
        c->sent++;
      }
      return TRUE;
    }, reinterpret_cast<LPARAM>(&ctx));
    if (ctx.sent > 0) return 1;
  }
  HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
  if (!hProc) return 0;
  BOOL ok = TerminateProcess(hProc, 0);
  CloseHandle(hProc);
  return ok ? 1 : 0;
}

uint32_t *cak_enum_gui_pids(int *out_count) {
  if (out_count) *out_count = 0;
  std::vector<uint32_t> pids;
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    if (!IsRealAppWindow(hwnd)) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != 0) {
      auto *vec = reinterpret_cast<std::vector<uint32_t> *>(lp);
      if (std::find(vec->begin(), vec->end(), (uint32_t)pid) == vec->end()) {
        vec->push_back((uint32_t)pid);
      }
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&pids));
  if (pids.empty()) return nullptr;
  auto *arr = (uint32_t *)std::malloc(pids.size() * sizeof(uint32_t));
  if (!arr) return nullptr;
  std::memcpy(arr, pids.data(), pids.size() * sizeof(uint32_t));
  if (out_count) *out_count = (int)pids.size();
  return arr;
}

uint8_t *cak_file_icon_png(const char *utf8_path, int size_px, size_t *out_len) {
  if (out_len) *out_len = 0;
  std::wstring w = ToWide(utf8_path);
  if (w.empty()) return nullptr;
  for (auto &ch : w) {
    if (ch == L'/') ch = L'\\';
  }
  if (w.size() >= 3 && w[0] == L'\\' && iswalpha(w[1]) && w[2] == L':') {
    w.erase(0, 1);
  }
  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  SHFILEINFOW sfi{};
  DWORD attrs = FILE_ATTRIBUTE_NORMAL;
  UINT flags = SHGFI_ICON | (size_px > 20 ? SHGFI_LARGEICON : SHGFI_SMALLICON);
  if (GetFileAttributesW(w.c_str()) == INVALID_FILE_ATTRIBUTES) {
    flags |= SHGFI_USEFILEATTRIBUTES;
  }
  DWORD_PTR ok = SHGetFileInfoW(w.c_str(), attrs, &sfi, sizeof(sfi), flags);
  if (!ok || !sfi.hIcon) {
    if (SUCCEEDED(hrInit)) CoUninitialize();
    return nullptr;
  }
  EnsureGdiPlus();
  Gdiplus::Bitmap *bmp = BitmapFromHIconWithAlpha(sfi.hIcon);
  DestroyIcon(sfi.hIcon);
  uint8_t *png = EncodeBitmapToPng(bmp, out_len);
  delete bmp;
  if (SUCCEEDED(hrInit)) CoUninitialize();
  return png;
}

uint8_t *cak_shell_thumbnail_png(const char *utf8_path, int max_px, int *out_w, int *out_h, size_t *out_len) {
  if (out_w) *out_w = 0;
  if (out_h) *out_h = 0;
  if (out_len) *out_len = 0;
  std::wstring w = ToWide(utf8_path);
  if (w.empty() || max_px <= 0) return nullptr;
  for (auto &ch : w) {
    if (ch == L'/') ch = L'\\';
  }
  if (w.size() >= 3 && w[0] == L'\\' && iswalpha(w[1]) && w[2] == L':') {
    w.erase(0, 1);
  }
  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  uint8_t *png = nullptr;
  IShellItemImageFactory *factory = nullptr;
  if (SUCCEEDED(SHCreateItemFromParsingName(w.c_str(), nullptr, IID_PPV_ARGS(&factory))) && factory) {
    SIZE req{max_px, max_px};
    HBITMAP hbmp = nullptr;
    if (SUCCEEDED(factory->GetImage(req, SIIGBF_BIGGERSIZEOK, &hbmp)) && hbmp) {
      Gdiplus::Bitmap *bmp = BitmapFromHBitmapPreservingAlpha(hbmp);
      if (bmp && bmp->GetWidth() > 0 && bmp->GetHeight() > 0) {
        int bw = (int)bmp->GetWidth();
        int bh = (int)bmp->GetHeight();
        if (bw > max_px || bh > max_px) {
          double scale = (double)max_px / (double)std::max(bw, bh);
          int nw = std::max(1, (int)(bw * scale + 0.5));
          int nh = std::max(1, (int)(bh * scale + 0.5));
          Gdiplus::Bitmap dst(nw, nh, PixelFormat32bppARGB);
          {
            Gdiplus::Graphics g(&dst);
            g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
            g.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
            g.DrawImage(bmp, 0, 0, nw, nh);
          }
          png = EncodeBitmapToPng(&dst, out_len);
          if (png) {
            if (out_w) *out_w = nw;
            if (out_h) *out_h = nh;
          }
        } else {
          png = EncodeBitmapToPng(bmp, out_len);
          if (png) {
            if (out_w) *out_w = bw;
            if (out_h) *out_h = bh;
          }
        }
      }
      delete bmp;
      DeleteObject(hbmp);
    }
    factory->Release();
  }
  if (SUCCEEDED(hrInit)) CoUninitialize();
  if (png) return png;

  png = cak_file_icon_png(utf8_path, max_px, out_len);
  if (png && out_len && *out_len > 0) {
    int iw = 32, ih = 32;
    cak_image_dimensions(png, *out_len, &iw, &ih);
    if (out_w) *out_w = iw;
    if (out_h) *out_h = ih;
  }
  return png;
}

int cak_resolve_lnk(
    const char *utf8_lnk_path,
    char *target_buf, int target_cap,
    char *args_buf, int args_cap,
    char *icon_buf, int icon_cap,
    int *out_icon_index,
    char *desc_buf, int desc_cap
) {
  if (target_buf && target_cap > 0) target_buf[0] = '\0';
  if (args_buf && args_cap > 0) args_buf[0] = '\0';
  if (icon_buf && icon_cap > 0) icon_buf[0] = '\0';
  if (desc_buf && desc_cap > 0) desc_buf[0] = '\0';
  if (out_icon_index) *out_icon_index = 0;

  std::wstring wpath = ToWide(utf8_lnk_path);
  if (wpath.empty()) return 0;

  HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  IShellLinkW *psl = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&psl));
  if (FAILED(hr) || !psl) {
    if (SUCCEEDED(hrInit)) CoUninitialize();
    return 0;
  }
  IPersistFile *ppf = nullptr;
  int ok = 0;
  if (SUCCEEDED(psl->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&ppf))) && ppf) {
    if (SUCCEEDED(ppf->Load(wpath.c_str(), STGM_READ))) {
      wchar_t target[MAX_PATH * 2] = {};
      if (SUCCEEDED(psl->GetPath(target, MAX_PATH * 2, nullptr, SLGP_RAWPATH))) {
        wchar_t expanded[MAX_PATH * 2] = {};
        if (ExpandEnvironmentStringsW(target, expanded, MAX_PATH * 2) > 0) {
          CopyToBuf(ToUtf8(expanded), target_buf, target_cap);
        } else {
          CopyToBuf(ToUtf8(target), target_buf, target_cap);
        }
      }
      wchar_t args[1024] = {};
      if (SUCCEEDED(psl->GetArguments(args, 1024))) CopyToBuf(ToUtf8(args), args_buf, args_cap);
      wchar_t icon[MAX_PATH * 2] = {};
      int icon_idx = 0;
      if (SUCCEEDED(psl->GetIconLocation(icon, MAX_PATH * 2, &icon_idx))) {
        wchar_t expanded[MAX_PATH * 2] = {};
        if (icon[0] && ExpandEnvironmentStringsW(icon, expanded, MAX_PATH * 2) > 0) {
          CopyToBuf(ToUtf8(expanded), icon_buf, icon_cap);
        } else {
          CopyToBuf(ToUtf8(icon), icon_buf, icon_cap);
        }
        if (out_icon_index) *out_icon_index = icon_idx;
      }
      wchar_t desc[1024] = {};
      if (SUCCEEDED(psl->GetDescription(desc, 1024))) CopyToBuf(ToUtf8(desc), desc_buf, desc_cap);
      ok = 1;
    }
    ppf->Release();
  }
  psl->Release();
  if (SUCCEEDED(hrInit)) CoUninitialize();
  return ok;
}

char *cak_known_start_menu_dirs_newline(void) {
  std::string joined;
  const KNOWNFOLDERID ids[] = {FOLDERID_CommonPrograms, FOLDERID_Programs};
  for (const auto &fid : ids) {
    PWSTR p = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(fid, 0, nullptr, &p)) && p) {
      if (!joined.empty()) joined.push_back('\n');
      joined += ToUtf8(p);
      CoTaskMemFree(p);
    }
  }
  return joined.empty() ? nullptr : DupString(joined);
}

int cak_image_dimensions(const uint8_t *data, size_t len, int *out_w, int *out_h) {
  Gdiplus::Bitmap *bmp = DecodeBitmapFromMemory(data, len);
  if (!bmp) return 0;
  if (out_w) *out_w = (int)bmp->GetWidth();
  if (out_h) *out_h = (int)bmp->GetHeight();
  delete bmp;
  return 1;
}

int cak_image_file_dimensions(const char *utf8_path, int *out_w, int *out_h) {
  EnsureGdiPlus();
  std::wstring w = ToWide(utf8_path);
  if (w.empty()) return 0;
  Gdiplus::Bitmap bmp(w.c_str());
  if (bmp.GetLastStatus() != Gdiplus::Ok || bmp.GetWidth() == 0) return 0;
  if (out_w) *out_w = (int)bmp.GetWidth();
  if (out_h) *out_h = (int)bmp.GetHeight();
  return 1;
}

uint8_t *cak_image_resize_png_dims(const uint8_t *data, size_t len, int max_px, int *out_w, int *out_h, size_t *out_len) {
  if (out_w) *out_w = 0;
  if (out_h) *out_h = 0;
  if (out_len) *out_len = 0;
  Gdiplus::Bitmap *src = DecodeBitmapFromMemory(data, len);
  if (!src) return nullptr;
  int w = (int)src->GetWidth();
  int h = (int)src->GetHeight();
  if (w <= 0 || h <= 0 || max_px <= 0) {
    delete src;
    return nullptr;
  }
  double scale = 1.0;
  if (w > max_px || h > max_px) {
    scale = (double)max_px / (double)std::max(w, h);
  }
  int nw = std::max(1, (int)(w * scale + 0.5));
  int nh = std::max(1, (int)(h * scale + 0.5));
  if (nw == w && nh == h) {
    uint8_t *png = EncodeBitmapToPng(src, out_len);
    delete src;
    if (png) {
      if (out_w) *out_w = w;
      if (out_h) *out_h = h;
    }
    return png;
  }
  Gdiplus::Bitmap dst(nw, nh, PixelFormat32bppARGB);
  {
    Gdiplus::Graphics g(&dst);
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    g.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
    g.DrawImage(src, 0, 0, nw, nh);
  }
  delete src;
  uint8_t *png = EncodeBitmapToPng(&dst, out_len);
  if (png) {
    if (out_w) *out_w = nw;
    if (out_h) *out_h = nh;
  }
  return png;
}

uint8_t *cak_image_resize_png(const uint8_t *data, size_t len, int max_px, size_t *out_len) {
  return cak_image_resize_png_dims(data, len, max_px, nullptr, nullptr, out_len);
}

void cak_font_metrics(
    const char *family,
    double size,
    double weight,
    double *out_ascender,
    double *out_descender,
    double *out_cap_height,
    double *out_x_height,
    double *out_leading
) {
  EnsureGdiPlus();
  std::wstring wfam = ToWide(family);
  Gdiplus::FontFamily ff(wfam.empty() ? L"Segoe UI" : wfam.c_str());
  const Gdiplus::FontFamily *use = ff.IsAvailable() ? &ff : Gdiplus::FontFamily::GenericSansSerif();
  INT style = weight >= 600.0 ? Gdiplus::FontStyleBold : Gdiplus::FontStyleRegular;
  UINT16 em = use->GetEmHeight(style);
  if (em == 0) em = 2048;
  double asc = size * (double)use->GetCellAscent(style) / (double)em;
  double desc = -size * (double)use->GetCellDescent(style) / (double)em;
  double line = size * (double)use->GetLineSpacing(style) / (double)em;
  if (out_ascender) *out_ascender = asc;
  if (out_descender) *out_descender = desc;
  if (out_cap_height) *out_cap_height = size * 0.70;
  if (out_x_height) *out_x_height = size * 0.50;
  if (out_leading) *out_leading = std::max(0.0, line - (asc - desc));
}

void cak_enable_per_monitor_dpi(void) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}

void cak_window_set_backdrop(void *hwnd_ptr, int backdrop_kind, int is_dark) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd) return;
  BOOL dark = is_dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark, sizeof(dark));
  int backdrop = backdrop_kind; // 1=None, 2=Mica, 3=Acrylic, 4=Tabbed
  DwmSetWindowAttribute(hwnd, 38 /* DWMWA_SYSTEMBACKDROP_TYPE */, &backdrop, sizeof(backdrop));
  if (backdrop_kind == 1) {
    COLORREF none_border = 0xFFFFFFFEu; // DWMWA_COLOR_NONE
    DwmSetWindowAttribute(hwnd, 34 /* DWMWA_BORDER_COLOR */, &none_border, sizeof(none_border));
    int dont_round = 1; // DWMWCP_DONOTROUND
    DwmSetWindowAttribute(hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &dont_round, sizeof(dont_round));
  }
}

void cak_window_set_tool_style(void *hwnd_ptr, int hide_from_taskbar, int non_activating) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd) return;
  LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  if (hide_from_taskbar) ex = (ex | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
  if (non_activating) ex |= WS_EX_NOACTIVATE;
  else ex &= ~WS_EX_NOACTIVATE;
  SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
}

static LRESULT CALLBACK FramelessSubclassProc(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR subclass_id, DWORD_PTR
) {
  switch (msg) {
    case WM_WINDOWPOSCHANGING: {
      if (lp) {
        auto *pos = reinterpret_cast<WINDOWPOS *>(lp);
        if (!(pos->flags & SWP_NOMOVE)) {
          RECT cur{};
          if (GetWindowRect(hwnd, &cur) && (pos->x != cur.left || pos->y != cur.top)) {
            pos->flags |= SWP_NOCOPYBITS;
          }
        }
      }
      break;
    }
    case WM_NCCALCSIZE:
      return 0;
    case WM_NCPAINT:
    case 0x00AE: // WM_NCUAHDRAWCAPTION
    case 0x00AF: // WM_NCUAHDRAWFRAME
      return 0;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCDESTROY:
      RemovePropW(hwnd, L"CAKFramelessApplied");
      RemoveWindowSubclass(hwnd, FramelessSubclassProc, subclass_id);
      break;
    default:
      break;
  }
  return DefSubclassProc(hwnd, msg, wp, lp);
}

void cak_window_apply_frameless(void *hwnd_ptr, int is_frameless) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd || !IsWindow(hwnd)) return;
  constexpr UINT_PTR kFramelessSubclassId = 0xCA41F001u;
  if (!is_frameless) {
    RemovePropW(hwnd, L"CAKFramelessApplied");
    RemoveWindowSubclass(hwnd, FramelessSubclassProc, kFramelessSubclassId);
    return;
  }
  SetWindowSubclass(hwnd, FramelessSubclassProc, kFramelessSubclassId, 0);
  LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
  const LONG_PTR stripped_style =
      (style & ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX |
                 WS_MAXIMIZEBOX | WS_BORDER | WS_DLGFRAME)) |
      WS_POPUP;
  bool changed = false;
  if (stripped_style != style) {
    SetWindowLongPtrW(hwnd, GWL_STYLE, stripped_style);
    changed = true;
  }
  LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  const LONG_PTR stripped_ex =
      ex & ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE);
  if (stripped_ex != ex) {
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, stripped_ex);
    changed = true;
  }
  if (!GetPropW(hwnd, L"CAKFramelessApplied")) {
    SetPropW(hwnd, L"CAKFramelessApplied", reinterpret_cast<HANDLE>(1));
    changed = true;
  }
  if (!changed) return;
  DWMNCRENDERINGPOLICY policy = DWMNCRP_ENABLED;
  DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY, &policy, sizeof(policy));
  COLORREF none_border = 0xFFFFFFFEu;
  DwmSetWindowAttribute(hwnd, 34 /* DWMWA_BORDER_COLOR */, &none_border, sizeof(none_border));
  int dont_round = 1; // DWMWCP_DONOTROUND
  DwmSetWindowAttribute(hwnd, 33 /* DWMWA_WINDOW_CORNER_PREFERENCE */, &dont_round, sizeof(dont_round));
  SetWindowPos(
      hwnd, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
          SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_NOCOPYBITS);
}

uint32_t cak_modifier_flags(void) {
  uint32_t flags = 0;
  if (GetAsyncKeyState(VK_SHIFT) & 0x8000) flags |= (1u << 17);   // .shift
  if (GetAsyncKeyState(VK_CONTROL) & 0x8000) flags |= (1u << 18); // .control
  if (GetAsyncKeyState(VK_MENU) & 0x8000) flags |= (1u << 19);    // .option
  if ((GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000) flags |= (1u << 20); // .command
  if (GetKeyState(VK_CAPITAL) & 0x0001) flags |= (1u << 16);      // .capsLock
  return flags;
}

void cak_set_cursor(int cursor_kind) {
  LPCWSTR id = IDC_ARROW;
  switch (cursor_kind) {
    case 1: id = IDC_IBEAM; break;
    case 2: id = IDC_HAND; break;
    case 3: id = IDC_CROSS; break;
    case 4: id = IDC_SIZEWE; break;
    case 5: id = IDC_SIZENS; break;
    default: id = IDC_ARROW; break;
  }
  SetCursor(LoadCursorW(nullptr, id));
}

void *cak_focused_hwnd(void) {
  return GetFocus();
}

void cak_edit_get_selection(void *hwnd_ptr, int *out_start, int *out_length) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  DWORD s = 0, e = 0;
  if (hwnd) SendMessageW(hwnd, EM_GETSEL, reinterpret_cast<WPARAM>(&s), reinterpret_cast<LPARAM>(&e));
  if (out_start) *out_start = (int)s;
  if (out_length) *out_length = (int)(e >= s ? e - s : 0);
}

void cak_edit_set_selection(void *hwnd_ptr, int start, int length) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd) return;
  int end = length < 0 ? -1 : (start + length);
  SendMessageW(hwnd, EM_SETSEL, (WPARAM)start, (LPARAM)end);
}

int cak_edit_has_ime_composition(void *hwnd_ptr) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd) return 0;
  HIMC imc = ImmGetContext(hwnd);
  if (!imc) return 0;
  LONG bytes = ImmGetCompositionStringW(imc, GCS_COMPSTR, nullptr, 0);
  ImmReleaseContext(hwnd, imc);
  return bytes > 0 ? 1 : 0;
}

char *cak_hwnd_get_text(void *hwnd_ptr) {
  HWND hwnd = static_cast<HWND>(hwnd_ptr);
  if (!hwnd) return DupString("");
  int len = GetWindowTextLengthW(hwnd);
  if (len <= 0) return DupString("");
  std::wstring w(len + 1, L'\0');
  GetWindowTextW(hwnd, w.data(), len + 1);
  w.resize(len);
  return DupString(ToUtf8(w));
}

static int SendCtrlLetterChord(WORD letter) {
  std::vector<INPUT> inputs;
  inputs.reserve(10);
  auto push_key = [&](WORD vk, DWORD flags) {
    INPUT in{};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.dwFlags = flags;
    inputs.push_back(in);
  };
  // Release any held Alt/Shift/Win modifiers so e.g. Alt+Enter ("Paste and Keep Window Open")
  // sends a clean Ctrl+V rather than Ctrl+Alt+V.
  const WORD mods_to_clear[] = {VK_MENU, VK_LMENU, VK_RMENU, VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_LWIN, VK_RWIN};
  for (WORD m : mods_to_clear) {
    if (GetAsyncKeyState(m) & 0x8000) {
      push_key(m, KEYEVENTF_KEYUP);
    }
  }
  push_key(VK_CONTROL, 0);
  push_key(letter, 0);
  push_key(letter, KEYEVENTF_KEYUP);
  push_key(VK_CONTROL, KEYEVENTF_KEYUP);
  return SendInput((UINT)inputs.size(), inputs.data(), sizeof(INPUT)) == inputs.size() ? 1 : 0;
}

int cak_send_paste_chord(void) {
  return SendCtrlLetterChord('V');
}

int cak_send_copy_chord(void) {
  return SendCtrlLetterChord('C');
}

int cak_pump_mouse_tracking_step(int *out_event, double *out_screen_x, double *out_screen_y) {
  if (out_event) *out_event = 0;
  auto fill_pos = [&]() {
    POINT pt{};
    GetCursorPos(&pt);
    if (out_screen_x) *out_screen_x = (double)pt.x;
    if (out_screen_y) *out_screen_y = (double)pt.y;
  };
  if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
    fill_pos();
    if (out_event) *out_event = 2; // leftMouseUp
    return 1;
  }
  MsgWaitForMultipleObjectsEx(0, nullptr, 12, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
  int reported = 0;
  MSG msg{};
  while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
    if (msg.message == WM_QUIT) {
      PostQuitMessage((int)msg.wParam);
      fill_pos();
      if (out_event) *out_event = 2;
      return 1;
    }
    if (msg.message == WM_LBUTTONUP || msg.message == WM_NCLBUTTONUP ||
        msg.message == WM_CANCELMODE) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
      fill_pos();
      if (out_event) *out_event = 2; // leftMouseUp
      return 1;
    }
    if (msg.message == WM_MOUSEMOVE || msg.message == WM_NCMOUSEMOVE) {
      reported = 1; // leftMouseDragged
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  fill_pos();
  if (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
    reported = 2;
  }
  if (out_event) *out_event = reported;
  return reported != 0 ? 1 : 0;
}

int cak_send_vk_key(uint16_t vk) {
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = vk;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = vk;
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  return SendInput(2, inputs, sizeof(INPUT)) == 2 ? 1 : 0;
}

int cak_send_unicode_text(const char *utf8_text) {
  std::wstring w = ToWide(utf8_text);
  if (w.empty()) return 1;
  std::vector<INPUT> inputs;
  inputs.reserve(w.size() * 2);
  for (wchar_t ch : w) {
    if (ch == L'\r') continue;
    if (ch == L'\n') {
      INPUT down{}, up{};
      down.type = INPUT_KEYBOARD;
      down.ki.wVk = VK_RETURN;
      up = down;
      up.ki.dwFlags = KEYEVENTF_KEYUP;
      inputs.push_back(down);
      inputs.push_back(up);
      continue;
    }
    INPUT down{}, up{};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = ch;
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  if (inputs.empty()) return 1;
  return SendInput((UINT)inputs.size(), inputs.data(), sizeof(INPUT)) == inputs.size() ? 1 : 0;
}

int cak_send_backspaces(int count) {
  if (count <= 0) return 1;
  std::vector<INPUT> inputs;
  inputs.reserve((size_t)count * 2);
  for (int i = 0; i < count; ++i) {
    INPUT down{}, up{};
    down.type = INPUT_KEYBOARD;
    down.ki.wVk = VK_BACK;
    up = down;
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  return SendInput((UINT)inputs.size(), inputs.data(), sizeof(INPUT)) == inputs.size() ? 1 : 0;
}

cak_win_entry *cak_enum_top_windows(int *out_count) {
  if (out_count) *out_count = 0;
  std::vector<cak_win_entry> list;
  EnumWindows([](HWND hwnd, LPARAM lp) -> BOOL {
    if (!IsRealAppWindow(hwnd)) return TRUE;
    RECT r{};
    if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &r, sizeof(r)))) {
      GetWindowRect(hwnd, &r);
    }
    if (r.right <= r.left || r.bottom <= r.top) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    cak_win_entry e{};
    e.hwnd = (uint64_t)(uintptr_t)hwnd;
    e.pid = (uint32_t)pid;
    e.x = r.left;
    e.y = r.top;
    e.width = r.right - r.left;
    e.height = r.bottom - r.top;
    e.is_maximized = IsZoomed(hwnd) ? 1 : 0;
    e.is_minimized = IsIconic(hwnd) ? 1 : 0;
    reinterpret_cast<std::vector<cak_win_entry> *>(lp)->push_back(e);
    return TRUE;
  }, reinterpret_cast<LPARAM>(&list));
  if (list.empty()) return nullptr;
  auto *arr = (cak_win_entry *)std::malloc(list.size() * sizeof(cak_win_entry));
  if (!arr) return nullptr;
  std::memcpy(arr, list.data(), list.size() * sizeof(cak_win_entry));
  if (out_count) *out_count = (int)list.size();
  return arr;
}

char *cak_hwnd_title(uint64_t hwnd_val) {
  return cak_hwnd_get_text(reinterpret_cast<void *>((uintptr_t)hwnd_val));
}

int cak_set_window_rect(uint64_t hwnd_val, int x, int y, int width, int height) {
  HWND hwnd = reinterpret_cast<HWND>((uintptr_t)hwnd_val);
  if (!hwnd || !IsWindow(hwnd)) return 0;
  if (IsZoomed(hwnd)) ShowWindow(hwnd, SW_RESTORE);
  // Compensate invisible Win10/11 DWM resize borders so visual frame lands on (x, y, width, height)
  RECT winRect{}, extRect{};
  if (GetWindowRect(hwnd, &winRect) &&
      SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &extRect, sizeof(extRect)))) {
    int leftPad = extRect.left - winRect.left;
    int topPad = extRect.top - winRect.top;
    int rightPad = winRect.right - extRect.right;
    int bottomPad = winRect.bottom - extRect.bottom;
    x -= leftPad;
    y -= topPad;
    width += leftPad + rightPad;
    height += topPad + bottomPad;
  }
  return SetWindowPos(hwnd, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE) ? 1 : 0;
}

int cak_control_window(uint64_t hwnd_val, int action) {
  HWND hwnd = reinterpret_cast<HWND>((uintptr_t)hwnd_val);
  if (!hwnd || !IsWindow(hwnd)) return 0;
  switch (action) {
    case 1: return ShowWindow(hwnd, SW_MINIMIZE) ? 1 : 1;
    case 2: return ShowWindow(hwnd, SW_MAXIMIZE) ? 1 : 1;
    case 3: return ShowWindow(hwnd, SW_RESTORE) ? 1 : 1;
    case 4: return PostMessageW(hwnd, WM_CLOSE, 0, 0) ? 1 : 0;
    case 5: {
      if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
      return SetForegroundWindow(hwnd) ? 1 : 0;
    }
    default: return 0;
  }
}

int cak_lock_workstation(void) {
  return LockWorkStation() ? 1 : 0;
}

int cak_empty_recycle_bin(void) {
  HRESULT hr = SHEmptyRecycleBinW(nullptr, nullptr, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
  return (SUCCEEDED(hr) || hr == E_UNEXPECTED) ? 1 : 0;
}

int cak_sha256(const uint8_t *data, size_t len, uint8_t out_digest[32]) {
  return HashBCrypt(BCRYPT_SHA256_ALGORITHM, nullptr, 0, data, len, out_digest, 32);
}

int cak_sha384(const uint8_t *data, size_t len, uint8_t out_digest[48]) {
  return HashBCrypt(BCRYPT_SHA384_ALGORITHM, nullptr, 0, data, len, out_digest, 48);
}

int cak_sha512(const uint8_t *data, size_t len, uint8_t out_digest[64]) {
  return HashBCrypt(BCRYPT_SHA512_ALGORITHM, nullptr, 0, data, len, out_digest, 64);
}

int cak_sha1(const uint8_t *data, size_t len, uint8_t out_digest[20]) {
  return HashBCrypt(BCRYPT_SHA1_ALGORITHM, nullptr, 0, data, len, out_digest, 20);
}

int cak_md5(const uint8_t *data, size_t len, uint8_t out_digest[16]) {
  return HashBCrypt(BCRYPT_MD5_ALGORITHM, nullptr, 0, data, len, out_digest, 16);
}

int cak_pbkdf2(
    int alg_id,
    const uint8_t *password, size_t password_len,
    const uint8_t *salt, size_t salt_len,
    uint32_t iterations,
    uint8_t *out_key, size_t key_len
) {
  const wchar_t *alg_name = nullptr;
  switch (alg_id) {
    case 1: alg_name = BCRYPT_SHA1_ALGORITHM; break;
    case 3: alg_name = BCRYPT_SHA256_ALGORITHM; break;
    case 4: alg_name = BCRYPT_SHA384_ALGORITHM; break;
    case 5: alg_name = BCRYPT_SHA512_ALGORITHM; break;
    default: return 0;
  }
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  if (BCryptOpenAlgorithmProvider(&hAlg, alg_name, nullptr, BCRYPT_ALG_HANDLE_HMAC_FLAG) != 0) {
    return 0;
  }
  NTSTATUS st = BCryptDeriveKeyPBKDF2(
      hAlg,
      const_cast<PUCHAR>(password), (ULONG)password_len,
      const_cast<PUCHAR>(salt), (ULONG)salt_len,
      (ULONGLONG)iterations,
      out_key, (ULONG)key_len,
      0);
  BCryptCloseAlgorithmProvider(hAlg, 0);
  return st == 0 ? 1 : 0;
}

int cak_aes_crypt(
    int decrypt,
    int ecb_mode,
    int pkcs7_pad,
    const uint8_t *key, size_t key_len,
    const uint8_t *iv,
    const uint8_t *data, size_t data_len,
    uint8_t *out_buf, size_t out_cap,
    size_t *out_written
) {
  if (out_written) *out_written = 0;
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, nullptr, 0) != 0) return 0;
  const wchar_t *mode = ecb_mode ? BCRYPT_CHAIN_MODE_ECB : BCRYPT_CHAIN_MODE_CBC;
  ULONG mode_bytes = ecb_mode ? sizeof(BCRYPT_CHAIN_MODE_ECB) : sizeof(BCRYPT_CHAIN_MODE_CBC);
  int ok = 0;
  if (BCryptSetProperty(
          hAlg, BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(const_cast<wchar_t *>(mode)),
          mode_bytes, 0) == 0) {
    BCRYPT_KEY_HANDLE hKey = nullptr;
    if (BCryptGenerateSymmetricKey(
            hAlg, &hKey, nullptr, 0, const_cast<PUCHAR>(key), (ULONG)key_len, 0) == 0) {
      uint8_t iv_copy[16] = {};
      if (!ecb_mode && iv) std::memcpy(iv_copy, iv, 16);
      ULONG flags = pkcs7_pad ? BCRYPT_BLOCK_PADDING : 0;
      ULONG written = 0;
      static const uint8_t dummy = 0;
      PUCHAR in_ptr = data_len > 0 ? const_cast<PUCHAR>(data) : const_cast<PUCHAR>(&dummy);
      NTSTATUS st = decrypt
          ? BCryptDecrypt(
                hKey, in_ptr, (ULONG)data_len, nullptr,
                ecb_mode ? nullptr : iv_copy, ecb_mode ? 0 : 16,
                out_buf, (ULONG)out_cap, &written, flags)
          : BCryptEncrypt(
                hKey, in_ptr, (ULONG)data_len, nullptr,
                ecb_mode ? nullptr : iv_copy, ecb_mode ? 0 : 16,
                out_buf, (ULONG)out_cap, &written, flags);
      if (st == 0) {
        if (out_written) *out_written = (size_t)written;
        ok = 1;
      }
      BCryptDestroyKey(hKey);
    }
  }
  BCryptCloseAlgorithmProvider(hAlg, 0);
  return ok;
}

int cak_hmac_sha256(
    const uint8_t *key, size_t key_len,
    const uint8_t *data, size_t data_len,
    uint8_t out_mac[32]
) {
  return HashBCrypt(BCRYPT_SHA256_ALGORITHM, key, key_len, data, data_len, out_mac, 32);
}

int cak_aes_gcm_decrypt(
    const uint8_t *key, size_t key_len,
    const uint8_t *nonce, size_t nonce_len,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t *aad, size_t aad_len,
    const uint8_t *tag, size_t tag_len,
    uint8_t *out_plaintext
) {
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, nullptr, 0) != 0) return 0;
  int ok = 0;
  if (BCryptSetProperty(
          hAlg, BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(const_cast<wchar_t *>(BCRYPT_CHAIN_MODE_GCM)),
          sizeof(BCRYPT_CHAIN_MODE_GCM), 0) == 0) {
    BCRYPT_KEY_HANDLE hKey = nullptr;
    if (BCryptGenerateSymmetricKey(
            hAlg, &hKey, nullptr, 0, const_cast<PUCHAR>(key), (ULONG)key_len, 0) == 0) {
      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
      BCRYPT_INIT_AUTH_MODE_INFO(info);
      info.pbNonce = const_cast<PUCHAR>(nonce);
      info.cbNonce = (ULONG)nonce_len;
      info.pbAuthData = aad_len > 0 ? const_cast<PUCHAR>(aad) : nullptr;
      info.cbAuthData = (ULONG)aad_len;
      info.pbTag = const_cast<PUCHAR>(tag);
      info.cbTag = (ULONG)tag_len;
      ULONG written = 0;
      if (BCryptDecrypt(
              hKey, const_cast<PUCHAR>(ciphertext), (ULONG)ciphertext_len,
              &info, nullptr, 0, out_plaintext, (ULONG)ciphertext_len, &written, 0) == 0) {
        ok = 1;
      }
      BCryptDestroyKey(hKey);
    }
  }
  BCryptCloseAlgorithmProvider(hAlg, 0);
  return ok;
}

int cak_aes_gcm_encrypt(
    const uint8_t *key, size_t key_len,
    const uint8_t *nonce, size_t nonce_len,
    const uint8_t *plaintext, size_t plaintext_len,
    const uint8_t *aad, size_t aad_len,
    uint8_t *out_ciphertext,
    uint8_t *out_tag, size_t tag_len
) {
  BCRYPT_ALG_HANDLE hAlg = nullptr;
  if (BCryptOpenAlgorithmProvider(&hAlg, BCRYPT_AES_ALGORITHM, nullptr, 0) != 0) return 0;
  int ok = 0;
  if (BCryptSetProperty(
          hAlg, BCRYPT_CHAINING_MODE,
          reinterpret_cast<PUCHAR>(const_cast<wchar_t *>(BCRYPT_CHAIN_MODE_GCM)),
          sizeof(BCRYPT_CHAIN_MODE_GCM), 0) == 0) {
    BCRYPT_KEY_HANDLE hKey = nullptr;
    if (BCryptGenerateSymmetricKey(
            hAlg, &hKey, nullptr, 0, const_cast<PUCHAR>(key), (ULONG)key_len, 0) == 0) {
      BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
      BCRYPT_INIT_AUTH_MODE_INFO(info);
      info.pbNonce = const_cast<PUCHAR>(nonce);
      info.cbNonce = (ULONG)nonce_len;
      info.pbAuthData = aad_len > 0 ? const_cast<PUCHAR>(aad) : nullptr;
      info.cbAuthData = (ULONG)aad_len;
      info.pbTag = out_tag;
      info.cbTag = (ULONG)tag_len;
      ULONG written = 0;
      if (BCryptEncrypt(
              hKey, const_cast<PUCHAR>(plaintext), (ULONG)plaintext_len,
              &info, nullptr, 0, out_ciphertext, (ULONG)plaintext_len, &written, 0) == 0) {
        ok = 1;
      }
      BCryptDestroyKey(hKey);
    }
  }
  BCryptCloseAlgorithmProvider(hAlg, 0);
  return ok;
}

int cak_random_bytes(uint8_t *buf, size_t len) {
  if (!buf || len == 0) return 1;
  return BCryptGenRandom(nullptr, buf, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0 ? 1 : 0;
}

namespace {

std::wstring NormalizeWinPath(const char *utf8_path) {
  std::wstring w = ToWide(utf8_path);
  if (w.empty()) return w;
  for (auto &ch : w) {
    if (ch == L'/') ch = L'\\';
  }
  if (w.size() >= 3 && w[0] == L'\\' && iswalpha(w[1]) && w[2] == L':') {
    w.erase(0, 1);
  }
  while (w.size() > 3 && w.back() == L'\\') {
    w.pop_back();
  }
  return w;
}

void FileTimeToUnix(const FILETIME &ft, int64_t *out_sec, int64_t *out_nsec) {
  ULARGE_INTEGER ull{};
  ull.LowPart = ft.dwLowDateTime;
  ull.HighPart = ft.dwHighDateTime;
  constexpr uint64_t kEpochDiff = 116444736000000000ULL;
  if (ull.QuadPart < kEpochDiff) {
    *out_sec = 0;
    *out_nsec = 0;
    return;
  }
  uint64_t ticks = ull.QuadPart - kEpochDiff;
  *out_sec = (int64_t)(ticks / 10000000ULL);
  *out_nsec = (int64_t)((ticks % 10000000ULL) * 100ULL);
}

FILETIME UnixToFileTime(int64_t sec, int64_t usec) {
  constexpr int64_t kEpochDiff = 116444736000000000LL;
  int64_t ticks = kEpochDiff + sec * 10000000LL + usec * 10LL;
  if (ticks < 0) ticks = 0;
  ULARGE_INTEGER ull{};
  ull.QuadPart = (uint64_t)ticks;
  FILETIME ft{};
  ft.dwLowDateTime = ull.LowPart;
  ft.dwHighDateTime = ull.HighPart;
  return ft;
}

int WinErrorToErrno(DWORD err) {
  switch (err) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_NAME:
      return ENOENT;
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
      return EACCES;
    case ERROR_FILE_EXISTS:
    case ERROR_ALREADY_EXISTS:
      return EEXIST;
    case ERROR_DIRECTORY:
      return ENOTDIR;
    case ERROR_DISK_FULL:
      return ENOSPC;
    default:
      return EIO;
  }
}

struct DirStreamState {
  std::wstring dir_path;
  HANDLE find_handle = INVALID_HANDLE_VALUE;
  WIN32_FIND_DATAW pending{};
  bool has_pending = false;
  bool finished = false;
};

std::mutex g_dir_mutex;
std::unordered_map<int, DirStreamState> g_dir_fds;

constexpr int kPosixRdOnly = _O_RDONLY;
constexpr int kPosixWrOnly = _O_WRONLY;
constexpr int kPosixRdWr = _O_RDWR;
constexpr int kPosixAppend = _O_APPEND;
constexpr int kPosixCreat = _O_CREAT;
constexpr int kPosixTrunc = _O_TRUNC;
constexpr int kPosixExcl = _O_EXCL;
constexpr int kPosixDirectory = 0x100000;

} // namespace

int cak_posix_open(const char *utf8_path, int posix_flags, int mode, int *out_errno) {
  if (out_errno) *out_errno = 0;
  if (!utf8_path || !*utf8_path) {
    if (out_errno) *out_errno = EINVAL;
    return -1;
  }
  std::string raw_utf8(utf8_path);
  if (raw_utf8.find("com.apple.TCC/TCC.db") != std::string::npos ||
      raw_utf8.find("com.apple.TCC\\TCC.db") != std::string::npos) {
    int fd = -1;
    if (_wsopen_s(&fd, L"NUL", _O_RDONLY | _O_BINARY, _SH_DENYNO, 0) == 0) {
      return fd;
    }
  }
  std::wstring wpath = NormalizeWinPath(utf8_path);
  if (wpath.empty()) {
    if (out_errno) *out_errno = EINVAL;
    return -1;
  }

  DWORD attrs = GetFileAttributesW(wpath.c_str());
  const int acc = posix_flags & 0x3;
  if ((posix_flags & kPosixDirectory) != 0 ||
      (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
       acc == kPosixRdOnly && (posix_flags & (kPosixCreat | kPosixTrunc)) == 0)) {
    if (attrs == INVALID_FILE_ATTRIBUTES) {
      if (out_errno) *out_errno = WinErrorToErrno(GetLastError());
      return -1;
    }
    if ((attrs & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      if (out_errno) *out_errno = ENOTDIR;
      return -1;
    }
    int dfd = -1;
    if (_wsopen_s(&dfd, L"NUL", _O_RDONLY | _O_BINARY, _SH_DENYNO, 0) != 0 || dfd < 0) {
      if (out_errno) *out_errno = EMFILE;
      return -1;
    }
    HANDLE stale_find = INVALID_HANDLE_VALUE;
    {
      std::lock_guard<std::mutex> lock(g_dir_mutex);
      auto old = g_dir_fds.find(dfd);
      if (old != g_dir_fds.end()) {
        stale_find = old->second.find_handle;
        g_dir_fds.erase(old);
      }
      DirStreamState st;
      st.dir_path = wpath;
      g_dir_fds.emplace(dfd, std::move(st));
    }
    if (stale_find != INVALID_HANDLE_VALUE) FindClose(stale_find);
    return dfd;
  }

  int oflag = _O_BINARY;
  if (acc == kPosixWrOnly) oflag |= _O_WRONLY;
  else if (acc == kPosixRdWr) oflag |= _O_RDWR;
  else oflag |= _O_RDONLY;

  if (posix_flags & kPosixAppend) oflag |= _O_APPEND;
  if (posix_flags & kPosixCreat) oflag |= _O_CREAT;
  if (posix_flags & kPosixTrunc) oflag |= _O_TRUNC;
  if (posix_flags & kPosixExcl) oflag |= _O_EXCL;

  int pmode = _S_IREAD;
  if ((mode & 0200) != 0 || mode == 0) pmode |= _S_IWRITE;

  int fd = -1;
  errno_t err = _wsopen_s(&fd, wpath.c_str(), oflag, _SH_DENYNO, pmode);
  if (err != 0 || fd < 0) {
    if (out_errno) *out_errno = err != 0 ? (int)err : errno;
    return -1;
  }
  return fd;
}

int cak_posix_close(int fd) {
  HANDLE to_close = INVALID_HANDLE_VALUE;
  {
    std::lock_guard<std::mutex> lock(g_dir_mutex);
    auto it = g_dir_fds.find(fd);
    if (it != g_dir_fds.end()) {
      to_close = it->second.find_handle;
      g_dir_fds.erase(it);
    }
  }
  if (to_close != INVALID_HANDLE_VALUE) FindClose(to_close);
  return _close(fd);
}

int cak_posix_stat(const char *utf8_path, int follow_links, cak_stat_info *out_info, int *out_errno) {
  if (out_errno) *out_errno = 0;
  if (!out_info) return -1;
  std::memset(out_info, 0, sizeof(*out_info));
  std::wstring wpath = NormalizeWinPath(utf8_path);
  if (wpath.empty()) {
    if (out_errno) *out_errno = ENOENT;
    return -1;
  }

  WIN32_FILE_ATTRIBUTE_DATA fad{};
  if (!GetFileAttributesExW(wpath.c_str(), GetFileExInfoStandard, &fad)) {
    if (out_errno) *out_errno = WinErrorToErrno(GetLastError());
    return -1;
  }

  DWORD attrs = fad.dwFileAttributes;
  uint64_t size = ((uint64_t)fad.nFileSizeHigh << 32) | fad.nFileSizeLow;
  FILETIME ft_create = fad.ftCreationTime;
  FILETIME ft_access = fad.ftLastAccessTime;
  FILETIME ft_write = fad.ftLastWriteTime;

  if (follow_links && (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    HANDLE h = CreateFileW(
        wpath.c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (h != INVALID_HANDLE_VALUE) {
      BY_HANDLE_FILE_INFORMATION bhfi{};
      if (GetFileInformationByHandle(h, &bhfi)) {
        attrs = bhfi.dwFileAttributes & ~FILE_ATTRIBUTE_REPARSE_POINT;
        size = ((uint64_t)bhfi.nFileSizeHigh << 32) | bhfi.nFileSizeLow;
        ft_create = bhfi.ftCreationTime;
        ft_access = bhfi.ftLastAccessTime;
        ft_write = bhfi.ftLastWriteTime;
      }
      CloseHandle(h);
    }
  }

  if (!follow_links && (attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    out_info->st_mode = 0120777; // S_IFLNK
  } else if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
    out_info->st_mode = 0040755; // S_IFDIR
  } else {
    out_info->st_mode = 0100644; // S_IFREG
  }
  if (attrs & FILE_ATTRIBUTE_READONLY) {
    out_info->st_flags = 0x00000002u; // UF_IMMUTABLE
    out_info->st_mode &= ~0222;
  }
  out_info->st_size = (int64_t)size;
  FileTimeToUnix(ft_write, &out_info->mtime_sec, &out_info->mtime_nsec);
  FileTimeToUnix(ft_access, &out_info->atime_sec, &out_info->atime_nsec);
  FileTimeToUnix(ft_write, &out_info->ctime_sec, &out_info->ctime_nsec);
  FileTimeToUnix(ft_create, &out_info->btime_sec, &out_info->btime_nsec);
  return 0;
}

int cak_posix_fstat(int fd, cak_stat_info *out_info, int *out_errno) {
  if (out_errno) *out_errno = 0;
  if (!out_info) return -1;
  intptr_t osfh = _get_osfhandle(fd);
  if (osfh == -1) {
    if (out_errno) *out_errno = EBADF;
    return -1;
  }
  if (GetFileType(reinterpret_cast<HANDLE>(osfh)) == FILE_TYPE_CHAR) {
    std::wstring dir_path;
    {
      std::lock_guard<std::mutex> lock(g_dir_mutex);
      auto it = g_dir_fds.find(fd);
      if (it != g_dir_fds.end()) {
        dir_path = it->second.dir_path;
      }
    }
    if (!dir_path.empty()) {
      return cak_posix_stat(ToUtf8(dir_path).c_str(), 1, out_info, out_errno);
    }
  }
  BY_HANDLE_FILE_INFORMATION bhfi{};
  if (!GetFileInformationByHandle(reinterpret_cast<HANDLE>(osfh), &bhfi)) {
    if (out_errno) *out_errno = EBADF;
    return -1;
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->st_mode = (bhfi.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? 0040755 : 0100644;
  out_info->st_size = (int64_t)(((uint64_t)bhfi.nFileSizeHigh << 32) | bhfi.nFileSizeLow);
  FileTimeToUnix(bhfi.ftLastWriteTime, &out_info->mtime_sec, &out_info->mtime_nsec);
  FileTimeToUnix(bhfi.ftLastAccessTime, &out_info->atime_sec, &out_info->atime_nsec);
  FileTimeToUnix(bhfi.ftLastWriteTime, &out_info->ctime_sec, &out_info->ctime_nsec);
  FileTimeToUnix(bhfi.ftCreationTime, &out_info->btime_sec, &out_info->btime_nsec);
  return 0;
}

int cak_posix_mkdir(const char *utf8_path, int *out_errno) {
  if (out_errno) *out_errno = 0;
  std::wstring wpath = NormalizeWinPath(utf8_path);
  if (wpath.empty()) {
    if (out_errno) *out_errno = EINVAL;
    return -1;
  }
  if (!CreateDirectoryW(wpath.c_str(), nullptr)) {
    if (out_errno) *out_errno = WinErrorToErrno(GetLastError());
    return -1;
  }
  return 0;
}

int cak_posix_utimes(
    const char *utf8_path,
    int64_t atime_sec, int64_t atime_usec,
    int64_t mtime_sec, int64_t mtime_usec,
    int *out_errno
) {
  if (out_errno) *out_errno = 0;
  std::wstring wpath = NormalizeWinPath(utf8_path);
  if (wpath.empty()) {
    if (out_errno) *out_errno = EINVAL;
    return -1;
  }
  HANDLE h = CreateFileW(
      wpath.c_str(), FILE_WRITE_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    if (out_errno) *out_errno = WinErrorToErrno(GetLastError());
    return -1;
  }
  FILETIME ft_access = UnixToFileTime(atime_sec, atime_usec);
  FILETIME ft_write = UnixToFileTime(mtime_sec, mtime_usec);
  BOOL ok = SetFileTime(h, nullptr, &ft_access, &ft_write);
  DWORD err = GetLastError();
  CloseHandle(h);
  if (!ok) {
    if (out_errno) *out_errno = WinErrorToErrno(err);
    return -1;
  }
  return 0;
}

char *cak_realpath(const char *utf8_path) {
  std::wstring wpath = NormalizeWinPath(utf8_path);
  if (wpath.empty()) return nullptr;
  wchar_t resolved[MAX_PATH * 2] = {};
  if (!_wfullpath(resolved, wpath.c_str(), MAX_PATH * 2)) return nullptr;
  if (GetFileAttributesW(resolved) == INVALID_FILE_ATTRIBUTES) return nullptr;
  return DupString(ToUtf8(resolved));
}

int cak_getattrlistbulk(int dirfd, void *attrbuf, size_t attrbuf_size) {
  if (!attrbuf || attrbuf_size < 128) return -1;
  std::unique_lock<std::mutex> lock(g_dir_mutex);
  auto it = g_dir_fds.find(dirfd);
  if (it == g_dir_fds.end()) return -1;
  DirStreamState state = it->second;
  lock.unlock();

  if (state.finished) return 0;

  uint8_t *cursor = static_cast<uint8_t *>(attrbuf);
  size_t used = 0;
  int count = 0;

  auto fetch_next = [&](WIN32_FIND_DATAW *out) -> bool {
    if (state.has_pending) {
      *out = state.pending;
      state.has_pending = false;
      return true;
    }
    if (state.find_handle == INVALID_HANDLE_VALUE) {
      std::wstring pattern = state.dir_path;
      if (!pattern.empty() && pattern.back() != L'\\') pattern.push_back(L'\\');
      pattern.push_back(L'*');
      state.find_handle = FindFirstFileExW(
          pattern.c_str(), FindExInfoBasic, out, FindExSearchNameMatch,
          nullptr, FIND_FIRST_EX_LARGE_FETCH);
      if (state.find_handle == INVALID_HANDLE_VALUE) {
        state.finished = true;
        return false;
      }
      return true;
    }
    if (!FindNextFileW(state.find_handle, out)) {
      FindClose(state.find_handle);
      state.find_handle = INVALID_HANDLE_VALUE;
      state.finished = true;
      return false;
    }
    return true;
  };

  WIN32_FIND_DATAW fd_data{};
  while (fetch_next(&fd_data)) {
    if (fd_data.cFileName[0] == L'.' &&
        (fd_data.cFileName[1] == L'\0' ||
         (fd_data.cFileName[1] == L'.' && fd_data.cFileName[2] == L'\0'))) {
      continue;
    }
    std::string name_utf8 = ToUtf8(fd_data.cFileName);
    if (name_utf8.empty()) continue;

    bool is_dir = (fd_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
    bool is_reparse = (fd_data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    size_t header_len = is_dir ? 56 : 52;
    size_t raw_len = header_len + name_utf8.size() + 1;
    size_t rec_len = (raw_len + 7u) & ~size_t(7u);

    if (used + rec_len > attrbuf_size) {
      state.pending = fd_data;
      state.has_pending = true;
      break;
    }

    uint8_t *rec = cursor + used;
    std::memset(rec, 0, rec_len);
    uint32_t u_rec_len = (uint32_t)rec_len;
    std::memcpy(rec + 0, &u_rec_len, 4);

    // attribute_set_t at offset 4..24:
    // commonattr = ATTR_CMN_NAME(0x1) | ATTR_CMN_OBJTYPE(0x8) | ATTR_CMN_MODTIME(0x400)
    uint32_t commonattr = 0x00000001u | 0x00000008u | 0x00000400u;
    uint32_t dirattr = is_dir ? 0x00000001u /* ATTR_DIR_MOUNTSTATUS */ : 0u;
    std::memcpy(rec + 4, &commonattr, 4);
    std::memcpy(rec + 12, &dirattr, 4);

    // attrreference_t at offset 24..32 (offset relative to field=rec+24)
    int32_t data_offset = (int32_t)(header_len - 24);
    uint32_t name_len_with_nul = (uint32_t)(name_utf8.size() + 1);
    std::memcpy(rec + 24, &data_offset, 4);
    std::memcpy(rec + 28, &name_len_with_nul, 4);

    // objtype at offset 32..36: VREG=1, VDIR=2
    uint32_t obj_type = is_dir ? 2u : 1u;
    std::memcpy(rec + 32, &obj_type, 4);

    // timespec at offset 36..52 (int64_t tv_sec, int64_t tv_nsec)
    int64_t mtime_sec = 0, mtime_nsec = 0;
    FileTimeToUnix(fd_data.ftLastWriteTime, &mtime_sec, &mtime_nsec);
    std::memcpy(rec + 36, &mtime_sec, 8);
    std::memcpy(rec + 44, &mtime_nsec, 8);

    if (is_dir) {
      // mountstatus at offset 52..56: skip reparse points/junctions like firmlinks
      uint32_t mnt_status = is_reparse ? 1u : 0u;
      std::memcpy(rec + 52, &mnt_status, 4);
    }

    std::memcpy(rec + header_len, name_utf8.data(), name_utf8.size());
    used += rec_len;
    count++;
  }

  lock.lock();
  auto it2 = g_dir_fds.find(dirfd);
  if (it2 != g_dir_fds.end()) {
    it2->second = state;
  } else if (state.find_handle != INVALID_HANDLE_VALUE) {
    FindClose(state.find_handle);
  }
  return count;
}

int cak_cred_write(const char *utf8_target, const char *utf8_user, const uint8_t *secret, size_t len) {
  if (!utf8_target || !*utf8_target) return 0;
  std::wstring target = ToWide(utf8_target);
  std::wstring user = utf8_user ? ToWide(utf8_user) : L"";
  CREDENTIALW cred = {};
  cred.Type = CRED_TYPE_GENERIC;
  cred.TargetName = const_cast<LPWSTR>(target.c_str());
  cred.UserName = user.empty() ? nullptr : const_cast<LPWSTR>(user.c_str());
  cred.CredentialBlobSize = static_cast<DWORD>(len);
  cred.CredentialBlob = (len > 0 && secret) ? const_cast<LPBYTE>(secret) : nullptr;
  cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
  return CredWriteW(&cred, 0) ? 1 : 0;
}

uint8_t *cak_cred_read(const char *utf8_target, size_t *out_len) {
  if (out_len) *out_len = 0;
  if (!utf8_target || !*utf8_target) return nullptr;
  std::wstring target = ToWide(utf8_target);
  PCREDENTIALW cred = nullptr;
  if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &cred) || !cred) {
    return nullptr;
  }
  size_t n = static_cast<size_t>(cred->CredentialBlobSize);
  uint8_t *copy = static_cast<uint8_t *>(std::malloc(n > 0 ? n : 1));
  if (copy && n > 0 && cred->CredentialBlob) {
    std::memcpy(copy, cred->CredentialBlob, n);
  }
  if (out_len) *out_len = n;
  CredFree(cred);
  return copy;
}

int cak_cred_delete(const char *utf8_target) {
  if (!utf8_target || !*utf8_target) return 0;
  std::wstring target = ToWide(utf8_target);
  return CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) ? 1 : 0;
}

int cak_cred_exists(const char *utf8_target) {
  if (!utf8_target || !*utf8_target) return 0;
  std::wstring target = ToWide(utf8_target);
  PCREDENTIALW cred = nullptr;
  if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &cred) || !cred) {
    return 0;
  }
  CredFree(cred);
  return 1;
}

} // extern "C"
#endif
