#if !os(macOS)
import Carbon
import Foundation
import NativeAPI

/// Bridges Carbon's `RegisterEventHotKey` / `UnregisterEventHotKey` C API to `NativeAPI.ShortcutManager`.
enum CarbonHotKeyBridge {
  private final class Registration: @unchecked Sendable {
    let shortcut: NativeAPI.Shortcut
    let hotKeyID: EventHotKeyID

    init(shortcut: NativeAPI.Shortcut, hotKeyID: EventHotKeyID) {
      self.shortcut = shortcut
      self.hotKeyID = hotKeyID
    }
  }

  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var installed = false
    var listenerId: ListenerId?
    var byShortcutId: [ShortcutId: EventHotKeyID] = [:]
  }

  private static let state = State()

  static func install() {
    state.lock.lock()
    defer { state.lock.unlock() }
    guard !state.installed else { return }
    state.installed = true

    _crossswift_carbon_set_hotkey_hooks(
      { keyCode, modifiers, hotKeyID, outHandle in
        CarbonHotKeyBridge.register(
          keyCode: Int(keyCode),
          modifiers: Int(modifiers),
          hotKeyID: hotKeyID,
          outHandle: outHandle
        )
      },
      { handle in
        CarbonHotKeyBridge.unregister(handle: handle)
      }
    )
  }

  private static func installReleaseListenerLocked() {
    guard state.listenerId == nil else { return }
    state.listenerId = ShortcutManager.shared.addListener { event in
      if case .released(let shortcutId, _) = event {
        state.lock.lock()
        let hk = state.byShortcutId[shortcutId]
        state.lock.unlock()
        if let hk {
          Task { @MainActor in
            _crossswift_carbon_dispatch_hotkey(hk.signature, hk.id, kEventHotKeyReleased)
          }
        }
      }
    }
  }

  private static func register(
    keyCode: Int,
    modifiers: Int,
    hotKeyID: EventHotKeyID,
    outHandle: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
  ) -> OSStatus {
    guard let accelerator = acceleratorString(keyCode: keyCode, modifiers: modifiers) else {
      return OSStatus(eventNotHandledErr)
    }
    state.lock.lock()
    installReleaseListenerLocked()
    state.lock.unlock()

    guard let shortcut = ShortcutManager.shared.registerWithAcceleratorAndCallback(
      accelerator,
      callback: {
        Task { @MainActor in
          _crossswift_carbon_dispatch_hotkey(hotKeyID.signature, hotKeyID.id, kEventHotKeyPressed)
        }
      }
    ) else {
      return OSStatus(eventNotHandledErr)
    }

    let reg = Registration(shortcut: shortcut, hotKeyID: hotKeyID)
    state.lock.lock()
    state.byShortcutId[shortcut.id] = hotKeyID
    state.lock.unlock()

    outHandle?.pointee = Unmanaged.passRetained(reg).toOpaque()
    return OSStatus(noErr)
  }

  private static func unregister(handle: UnsafeMutableRawPointer?) -> OSStatus {
    guard let handle else { return OSStatus(noErr) }
    let reg = Unmanaged<Registration>.fromOpaque(handle).takeRetainedValue()
    state.lock.lock()
    state.byShortcutId.removeValue(forKey: reg.shortcut.id)
    state.lock.unlock()
    _ = ShortcutManager.shared.unregisterWithId(reg.shortcut.id)
    reg.shortcut.dispose()
    return OSStatus(noErr)
  }

  private static func acceleratorString(keyCode: Int, modifiers: Int) -> String? {
    guard let keyName = keyToken(for: keyCode) else { return nil }
    var parts: [String] = []
    if modifiers & controlKey != 0 { parts.append("Ctrl") }
    if modifiers & optionKey != 0 { parts.append("Alt") }
    if modifiers & shiftKey != 0 { parts.append("Shift") }
    if modifiers & cmdKey != 0 {
      if modifiers & controlKey == 0 {
        parts.insert("Ctrl", at: 0)
      } else {
        parts.append("Meta")
      }
    }
    parts.append(keyName)
    return parts.joined(separator: "+")
  }

  private static func keyToken(for code: Int) -> String? {
    switch code {
    case kVK_Space: return "Space"
    case kVK_Return, kVK_ANSI_KeypadEnter: return "Enter"
    case kVK_Tab: return "Tab"
    case kVK_Escape: return "Escape"
    case kVK_Delete: return "Backspace"
    case kVK_ForwardDelete: return "Delete"
    case kVK_LeftArrow: return "Left"
    case kVK_RightArrow: return "Right"
    case kVK_UpArrow: return "Up"
    case kVK_DownArrow: return "Down"
    case kVK_Home: return "Home"
    case kVK_End: return "End"
    case kVK_PageUp: return "PageUp"
    case kVK_PageDown: return "PageDown"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_F13: return "F13"
    case kVK_F14: return "F14"
    case kVK_F15: return "F15"
    case kVK_F16: return "F16"
    case kVK_F17: return "F17"
    case kVK_F18: return "F18"
    case kVK_F19: return "F19"
    case kVK_F20: return "F20"
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_ANSI_Minus: return "-"
    case kVK_ANSI_Equal: return "="
    case kVK_ANSI_LeftBracket: return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Backslash: return "\\"
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote: return "'"
    case kVK_ANSI_Comma: return ","
    case kVK_ANSI_Period: return "."
    case kVK_ANSI_Slash: return "/"
    case kVK_ANSI_Grave: return "`"
    default: return nil
    }
  }
}
#endif
