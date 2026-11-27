#include "DrawingProbe.h"
#include "SwiftUIWindows.h"
#include <windows.h>
#include <commctrl.h>

namespace {
struct Probe {
  void *surface{};
  HWND peer{};
  bool edit{};
  int remainingID{};
  int inputCalls{};
  int nativeKeys{};
};

LRESULT CALLBACK Observe(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR,
                         DWORD_PTR data) {
  auto *probe = reinterpret_cast<Probe *>(data);
  if (msg == WM_KEYDOWN && wp == 'A')
    ++probe->nativeKeys;
  return DefSubclassProc(hwnd, msg, wp, lp);
}

void Attach(Probe &p, int id) {
  if (p.edit)
    sui_surface_edit(p.surface, p.peer, id, 0);
  else
    sui_surface_button(p.surface, p.peer, id, 0, 0);
}

int ReplaceDuringKey(void *context, int64_t id, int event, double, double,
                     int value, int) {
  auto &p = *static_cast<Probe *>(context);
  if (event != 6 || value != 'A' || id != 1) return 0;
  ++p.inputCalls;
  if (p.edit)
    sui_surface_remove_edit(p.surface, p.peer);
  else
    sui_surface_remove_button(p.surface, p.peer);
  if (p.remainingID) Attach(p, p.remainingID);
  // An unhandled key would ordinarily continue into the original control.
  return 0;
}

int Run(bool edit, int remainingID) {
  HWND host = CreateWindowExW(0, L"STATIC", L"", WS_OVERLAPPEDWINDOW, 0, 0,
                              240, 160, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!host) return 1;
  Probe p{};
  p.edit = edit;
  p.remainingID = remainingID;
  p.surface = sui_surface_create(host, nullptr, &p, 0);
  p.peer = CreateWindowExW(0, edit ? L"EDIT" : L"BUTTON", L"", WS_CHILD, 0, 0,
                           100, 32, host, nullptr, GetModuleHandleW(nullptr), nullptr);
  int errors = 1;
  if (p.surface && p.peer &&
      SetWindowSubclass(p.peer, Observe, 1, reinterpret_cast<DWORD_PTR>(&p))) {
    Attach(p, 1);
    sui_surface_input(p.surface, ReplaceDuringKey);
    SendMessageW(p.peer, WM_KEYDOWN, 'A', 0);
    errors = p.inputCalls != 1 || p.nativeKeys != 0;
    if (remainingID) {
      // The replacement remains usable when it receives its own input.
      SendMessageW(p.peer, WM_KEYDOWN, 'A', 0);
      if (p.nativeKeys != 1) ++errors;
    }
    RemoveWindowSubclass(p.peer, Observe, 1);
  }
  if (p.surface) sui_surface_destroy(p.surface);
  DestroyWindow(host);
  return errors;
}
} // namespace

int input_reentry_probe(void) {
  return Run(false, 0) + Run(false, 2) + Run(true, 0) + Run(true, 2);
}
