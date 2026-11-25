import Foundation
#if !os(macOS)
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

@MainActor
open class NSResponder: NSObject {
  public weak var nextResponder: NSResponder?

  public override init() {
    super.init()
  }

  public init?(coder: NSCoder) {
    super.init()
  }

  open var acceptsFirstResponder: Bool { false }
  open func becomeFirstResponder() -> Bool { true }
  open func resignFirstResponder() -> Bool { true }
  open var undoManager: UndoManager? { nextResponder?.undoManager }
  open func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? { nil }
  open func responds(to aSelector: Selector!) -> Bool { false }

  open func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
  open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
  open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
  open func performKeyEquivalent(with event: NSEvent) -> Bool {
    for sub in (self as? NSView)?.subviews ?? [] {
      if sub.performKeyEquivalent(with: event) { return true }
    }
    return false
  }
  open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
  open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
  open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
  open func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
  open func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
  open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
  open func mouseEntered(with event: NSEvent) { nextResponder?.mouseEntered(with: event) }
  open func mouseExited(with event: NSEvent) { nextResponder?.mouseExited(with: event) }
  open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
  open func cursorUpdate(with event: NSEvent) { nextResponder?.cursorUpdate(with: event) }

  open func doCommand(by selector: Selector) {}
  open func insertText(_ insertString: Any) {}
  open func insertNewline(_ sender: Any?) {}
  open func insertLineBreak(_ sender: Any?) {}
  open func insertNewlineIgnoringFieldEditor(_ sender: Any?) {}
  open func insertParagraphSeparator(_ sender: Any?) {}
  open func insertTab(_ sender: Any?) {}
  open func insertBacktab(_ sender: Any?) {}
  open func insertTabIgnoringFieldEditor(_ sender: Any?) {}
  open func deleteBackward(_ sender: Any?) {}
  open func deleteForward(_ sender: Any?) {}
  open func cancelOperation(_ sender: Any?) {}
}

open class NSEvent: NSObject, @unchecked Sendable {
  public enum EventType: UInt, Sendable {
    case leftMouseDown = 1
    case leftMouseUp = 2
    case rightMouseDown = 3
    case rightMouseUp = 4
    case mouseMoved = 5
    case leftMouseDragged = 6
    case rightMouseDragged = 7
    case mouseEntered = 8
    case mouseExited = 9
    case keyDown = 10
    case keyUp = 11
    case flagsChanged = 12
    case appKitDefined = 13
    case systemDefined = 14
    case applicationDefined = 15
    case periodic = 16
    case cursorUpdate = 17
    case scrollWheel = 22
    case tabletPoint = 23
    case tabletProximity = 24
    case otherMouseDown = 25
    case otherMouseUp = 26
    case otherMouseDragged = 27
    case gesture = 29
    case magnify = 30
    case swipe = 31
    case rotate = 18
    case beginGesture = 19
    case endGesture = 20
    case smartMagnify = 32
    case quickLook = 33
    case pressure = 34
    case directTouch = 37
  }

  public static let foreverDuration: TimeInterval = .greatestFiniteMagnitude
  public static let keyRepeatDelay: TimeInterval = 0.5
  public static let keyRepeatInterval: TimeInterval = 0.05

  public struct EventTypeMask: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public init(type: EventType) { self.rawValue = 1 << UInt64(type.rawValue) }

    public static let leftMouseDown = EventTypeMask(type: .leftMouseDown)
    public static let leftMouseUp = EventTypeMask(type: .leftMouseUp)
    public static let rightMouseDown = EventTypeMask(type: .rightMouseDown)
    public static let rightMouseUp = EventTypeMask(type: .rightMouseUp)
    public static let mouseMoved = EventTypeMask(type: .mouseMoved)
    public static let leftMouseDragged = EventTypeMask(type: .leftMouseDragged)
    public static let rightMouseDragged = EventTypeMask(type: .rightMouseDragged)
    public static let mouseEntered = EventTypeMask(type: .mouseEntered)
    public static let mouseExited = EventTypeMask(type: .mouseExited)
    public static let keyDown = EventTypeMask(type: .keyDown)
    public static let keyUp = EventTypeMask(type: .keyUp)
    public static let flagsChanged = EventTypeMask(type: .flagsChanged)
    public static let cursorUpdate = EventTypeMask(type: .cursorUpdate)
    public static let scrollWheel = EventTypeMask(type: .scrollWheel)
    public static let otherMouseDown = EventTypeMask(type: .otherMouseDown)
    public static let otherMouseUp = EventTypeMask(type: .otherMouseUp)
    public static let otherMouseDragged = EventTypeMask(type: .otherMouseDragged)
    public static let any = EventTypeMask(rawValue: UInt64.max)

    public func matches(_ type: EventType) -> Bool {
      contains(EventTypeMask(type: type))
    }
  }

  public struct ModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let capsLock = ModifierFlags(rawValue: 1 << 16)
    public static let shift = ModifierFlags(rawValue: 1 << 17)
    public static let control = ModifierFlags(rawValue: 1 << 18)
    public static let option = ModifierFlags(rawValue: 1 << 19)
    public static let command = ModifierFlags(rawValue: 1 << 20)
    public static let numericPad = ModifierFlags(rawValue: 1 << 21)
    public static let help = ModifierFlags(rawValue: 1 << 22)
    public static let function = ModifierFlags(rawValue: 1 << 23)
    public static let deviceIndependentFlagsMask = ModifierFlags(rawValue: 0xffff0000)
  }

  public struct SpecialKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public var unicodeScalar: UnicodeScalar { UnicodeScalar(rawValue) ?? UnicodeScalar(0)! }

    public static let upArrow = SpecialKey(rawValue: 0xF700)
    public static let downArrow = SpecialKey(rawValue: 0xF701)
    public static let leftArrow = SpecialKey(rawValue: 0xF702)
    public static let rightArrow = SpecialKey(rawValue: 0xF703)
    public static let delete = SpecialKey(rawValue: 0x007F)
    public static let backspace = SpecialKey(rawValue: 0x0008)
    public static let deleteForward = SpecialKey(rawValue: 0xF728)
    public static let home = SpecialKey(rawValue: 0xF729)
    public static let end = SpecialKey(rawValue: 0xF72B)
    public static let pageUp = SpecialKey(rawValue: 0xF72C)
    public static let pageDown = SpecialKey(rawValue: 0xF72D)
    public static let carriageReturn = SpecialKey(rawValue: 0x000D)
    public static let enter = SpecialKey(rawValue: 0x0003)
    public static let tab = SpecialKey(rawValue: 0x0009)
    public static let backTab = SpecialKey(rawValue: 0x0019)
    public static let f1 = SpecialKey(rawValue: 0xF704)
    public static let f2 = SpecialKey(rawValue: 0xF705)
    public static let f3 = SpecialKey(rawValue: 0xF706)
    public static let f4 = SpecialKey(rawValue: 0xF707)
    public static let f5 = SpecialKey(rawValue: 0xF708)
    public static let f6 = SpecialKey(rawValue: 0xF709)
    public static let f7 = SpecialKey(rawValue: 0xF70A)
    public static let f8 = SpecialKey(rawValue: 0xF70B)
    public static let f9 = SpecialKey(rawValue: 0xF70C)
    public static let f10 = SpecialKey(rawValue: 0xF70D)
    public static let f11 = SpecialKey(rawValue: 0xF70E)
    public static let f12 = SpecialKey(rawValue: 0xF70F)
    public static let f13 = SpecialKey(rawValue: 0xF710)
    public static let f14 = SpecialKey(rawValue: 0xF711)
    public static let f15 = SpecialKey(rawValue: 0xF712)
    public static let f16 = SpecialKey(rawValue: 0xF713)
    public static let f17 = SpecialKey(rawValue: 0xF714)
    public static let f18 = SpecialKey(rawValue: 0xF715)
    public static let f19 = SpecialKey(rawValue: 0xF716)
    public static let f20 = SpecialKey(rawValue: 0xF717)
    public static let f21 = SpecialKey(rawValue: 0xF718)
    public static let f22 = SpecialKey(rawValue: 0xF719)
    public static let f23 = SpecialKey(rawValue: 0xF71A)
    public static let f24 = SpecialKey(rawValue: 0xF71B)
    public static let f25 = SpecialKey(rawValue: 0xF71C)
    public static let f26 = SpecialKey(rawValue: 0xF71D)
    public static let f27 = SpecialKey(rawValue: 0xF71E)
    public static let f28 = SpecialKey(rawValue: 0xF71F)
    public static let f29 = SpecialKey(rawValue: 0xF720)
    public static let f30 = SpecialKey(rawValue: 0xF721)
    public static let f31 = SpecialKey(rawValue: 0xF722)
    public static let f32 = SpecialKey(rawValue: 0xF723)
    public static let f33 = SpecialKey(rawValue: 0xF724)
    public static let f34 = SpecialKey(rawValue: 0xF725)
    public static let f35 = SpecialKey(rawValue: 0xF726)
  }

  public let type: EventType
  public let locationInWindow: NSPoint
  public let modifierFlags: ModifierFlags
  public let timestamp: TimeInterval
  public let windowNumber: Int
  public weak var window: NSWindow?
  public let characters: String?
  public let charactersIgnoringModifiers: String?
  public let isARepeat: Bool
  public let keyCode: UInt16
  public let buttonNumber: Int
  public let clickCount: Int
  public let scrollingDeltaX: CGFloat
  public let scrollingDeltaY: CGFloat
  public let data1: Int
  public let data2: Int
  #if !os(macOS)
    public var cgEvent: CGEvent? { nil }
  #endif

  public var specialKey: SpecialKey? {
    guard let scalar = charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
    let v = Int(scalar.value)
    if (0xF700...0xF8FF).contains(v) || v == 0x7F || v == 0x0D || v == 0x03 || v == 0x09 || v == 0x19 {
      return SpecialKey(rawValue: v)
    }
    return nil
  }

  public init(
    type: EventType,
    locationInWindow: NSPoint = .zero,
    modifierFlags: ModifierFlags = [],
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
    windowNumber: Int = 0,
    window: NSWindow? = nil,
    characters: String? = nil,
    charactersIgnoringModifiers: String? = nil,
    isARepeat: Bool = false,
    keyCode: UInt16 = 0,
    buttonNumber: Int = 0,
    clickCount: Int = 1,
    scrollingDeltaX: CGFloat = 0,
    scrollingDeltaY: CGFloat = 0,
    data1: Int = 0,
    data2: Int = 0
  ) {
    self.type = type
    self.locationInWindow = locationInWindow
    self.modifierFlags = modifierFlags
    self.timestamp = timestamp
    self.windowNumber = windowNumber
    self.window = window
    self.characters = characters
    self.charactersIgnoringModifiers = charactersIgnoringModifiers
    self.isARepeat = isARepeat
    self.keyCode = keyCode
    self.buttonNumber = buttonNumber
    self.clickCount = clickCount
    self.scrollingDeltaX = scrollingDeltaX
    self.scrollingDeltaY = scrollingDeltaY
    self.data1 = data1
    self.data2 = data2
    super.init()
  }

  public static func keyEvent(
    with type: EventType,
    location: NSPoint,
    modifierFlags flags: ModifierFlags,
    timestamp time: TimeInterval,
    windowNumber wNum: Int,
    context unusedPassNil: NSGraphicsContext?,
    characters keys: String,
    charactersIgnoringModifiers ukeys: String,
    isARepeat flag: Bool,
    keyCode code: UInt16
  ) -> NSEvent? {
    NSEvent(
      type: type,
      locationInWindow: location,
      modifierFlags: flags,
      timestamp: time,
      windowNumber: wNum,
      characters: keys,
      charactersIgnoringModifiers: ukeys,
      isARepeat: flag,
      keyCode: code
    )
  }

  public static func otherEvent(
    with type: EventType,
    location: NSPoint,
    modifierFlags flags: ModifierFlags,
    timestamp time: TimeInterval,
    windowNumber wNum: Int,
    context unusedPassNil: NSGraphicsContext?,
    subtype: Int16,
    data1 d1: Int,
    data2 d2: Int
  ) -> NSEvent? {
    NSEvent(
      type: type,
      locationInWindow: location,
      modifierFlags: flags,
      timestamp: time,
      windowNumber: wNum,
      data1: d1,
      data2: d2
    )
  }

  public static var mouseLocation: NSPoint {
    #if !os(macOS)
      let pt = NativeAPI.DisplayManager.shared.getCursorPosition()
      return CrossAppKitCoordinates.pointFromNativeTopLeft(x: pt.x, y: pt.y)
    #else
      return .zero
    #endif
  }

  public static var modifierFlags: ModifierFlags {
    #if os(Windows)
      return ModifierFlags(rawValue: UInt(cak_modifier_flags()))
    #else
      return []
    #endif
  }

  public static var doubleClickInterval: TimeInterval { 0.5 }

  private final class MonitorToken {
    let id = UUID()
    let isGlobal: Bool
    init(isGlobal: Bool) { self.isGlobal = isGlobal }
  }

  nonisolated(unsafe) private static var localMonitors: [(id: UUID, mask: EventTypeMask, handler: (NSEvent) -> NSEvent?)] = []
  nonisolated(unsafe) private static var globalMonitors: [(id: UUID, mask: EventTypeMask, handler: (NSEvent) -> Void)] = []

  public static func addLocalMonitorForEvents(
    matching mask: EventTypeMask,
    handler block: @escaping (NSEvent) -> NSEvent?
  ) -> Any? {
    let token = MonitorToken(isGlobal: false)
    localMonitors.append((token.id, mask, block))
    return token
  }

  public static func addGlobalMonitorForEvents(
    matching mask: EventTypeMask,
    handler block: @escaping (NSEvent) -> Void
  ) -> Any? {
    let token = MonitorToken(isGlobal: true)
    globalMonitors.append((token.id, mask, block))
    return token
  }

  public static func removeMonitor(_ eventMonitor: Any) {
    guard let token = eventMonitor as? MonitorToken else { return }
    if token.isGlobal {
      globalMonitors.removeAll { $0.id == token.id }
    } else {
      localMonitors.removeAll { $0.id == token.id }
    }
  }

  public static func dispatchLocalMonitors(_ event: NSEvent) -> NSEvent? {
    var current: NSEvent? = event
    for entry in localMonitors where entry.mask.matches(event.type) {
      guard let ev = current else { return nil }
      current = entry.handler(ev)
    }
    return current
  }

  public static func dispatchGlobalMonitors(_ event: NSEvent) {
    for entry in globalMonitors where entry.mask.matches(event.type) {
      entry.handler(event)
    }
  }

  /// Translates a Win32 virtual keycode (`VK_*`) and optional AT Set 1 scan code
  /// (`MapVirtualKeyExW` / `WM_KEYDOWN` lParam) into macOS HIToolbox `kVK_*`.
  public static func carbonKeyCode(fromWin32VK vk: Int, scanCode: UInt32 = 0) -> UInt16 {
    if scanCode != 0, let fromScan = carbonKeyCode(fromATScanCode: scanCode) {
      return fromScan
    }
    switch vk {
    case 0x0D: return 0x24 // Return
    case 0x09: return 0x30 // Tab
    case 0x20: return 0x31 // Space
    case 0x08: return 0x33 // Backspace -> kVK_Delete
    case 0x1B: return 0x35 // Escape
    case 0x0C: return 0x47 // VK_CLEAR -> kVK_ANSI_KeypadClear
    case 0x2E: return 0x75 // Delete -> kVK_ForwardDelete
    case 0x2F: return 0x72 // VK_HELP -> kVK_Help
    case 0x25: return 0x7B // Left
    case 0x27: return 0x7C // Right
    case 0x28: return 0x7D // Down
    case 0x26: return 0x7E // Up
    case 0x24: return 0x73 // Home
    case 0x23: return 0x77 // End
    case 0x21: return 0x74 // PageUp
    case 0x22: return 0x79 // PageDown
    case 0x41: return 0x00 // A
    case 0x42: return 0x0B // B
    case 0x43: return 0x08 // C
    case 0x44: return 0x02 // D
    case 0x45: return 0x0E // E
    case 0x46: return 0x03 // F
    case 0x47: return 0x05 // G
    case 0x48: return 0x04 // H
    case 0x49: return 0x22 // I
    case 0x4A: return 0x26 // J
    case 0x4B: return 0x28 // K
    case 0x4C: return 0x25 // L
    case 0x4D: return 0x2E // M
    case 0x4E: return 0x2D // N
    case 0x4F: return 0x1F // O
    case 0x50: return 0x23 // P
    case 0x51: return 0x0C // Q
    case 0x52: return 0x0F // R
    case 0x53: return 0x01 // S
    case 0x54: return 0x11 // T
    case 0x55: return 0x20 // U
    case 0x56: return 0x09 // V
    case 0x57: return 0x0D // W
    case 0x58: return 0x07 // X
    case 0x59: return 0x10 // Y
    case 0x5A: return 0x06 // Z
    case 0x30: return 0x1D // 0
    case 0x31: return 0x12 // 1
    case 0x32: return 0x13 // 2
    case 0x33: return 0x14 // 3
    case 0x34: return 0x15 // 4
    case 0x35: return 0x17 // 5
    case 0x36: return 0x16 // 6
    case 0x37: return 0x1A // 7
    case 0x38: return 0x1C // 8
    case 0x39: return 0x19 // 9
    case 0xBA: return 0x29 // VK_OEM_1 (;)
    case 0xBB: return 0x18 // VK_OEM_PLUS (=)
    case 0xBC: return 0x2B // VK_OEM_COMMA (,)
    case 0xBD: return 0x1B // VK_OEM_MINUS (-)
    case 0xBE: return 0x2F // VK_OEM_PERIOD (.)
    case 0xBF: return 0x2C // VK_OEM_2 (/)
    case 0xC0: return 0x32 // VK_OEM_3 (`)
    case 0xDB: return 0x21 // VK_OEM_4 ([)
    case 0xDC: return 0x2A // VK_OEM_5 (\)
    case 0xDD: return 0x1E // VK_OEM_6 (])
    case 0xDE: return 0x27 // VK_OEM_7 (')
    case 0xE2: return 0x0A // VK_OEM_102 -> kVK_ISO_Section
    case 0x60: return 0x52 // VK_NUMPAD0
    case 0x61: return 0x53 // VK_NUMPAD1
    case 0x62: return 0x54 // VK_NUMPAD2
    case 0x63: return 0x55 // VK_NUMPAD3
    case 0x64: return 0x56 // VK_NUMPAD4
    case 0x65: return 0x57 // VK_NUMPAD5
    case 0x66: return 0x58 // VK_NUMPAD6
    case 0x67: return 0x59 // VK_NUMPAD7
    case 0x68: return 0x5B // VK_NUMPAD8
    case 0x69: return 0x5C // VK_NUMPAD9
    case 0x6A: return 0x43 // VK_MULTIPLY
    case 0x6B: return 0x45 // VK_ADD
    case 0x6D: return 0x4E // VK_SUBTRACT
    case 0x6E: return 0x41 // VK_DECIMAL
    case 0x6F: return 0x4B // VK_DIVIDE
    case 0x70: return 0x7A // F1
    case 0x71: return 0x78 // F2
    case 0x72: return 0x63 // F3
    case 0x73: return 0x76 // F4
    case 0x74: return 0x60 // F5
    case 0x75: return 0x61 // F6
    case 0x76: return 0x62 // F7
    case 0x77: return 0x64 // F8
    case 0x78: return 0x65 // F9
    case 0x79: return 0x6D // F10
    case 0x7A: return 0x67 // F11
    case 0x7B: return 0x6F // F12
    case 0x7C: return 0x69 // F13
    case 0x7D: return 0x6B // F14
    case 0x7E: return 0x71 // F15
    case 0x7F: return 0x6A // F16
    case 0x80: return 0x40 // F17
    case 0x81: return 0x4F // F18
    case 0x82: return 0x50 // F19
    case 0x83: return 0x5A // F20
    case 0x10, 0xA0: return 0x38 // Shift / LShift
    case 0xA1: return 0x3C       // RShift
    case 0x11, 0xA2: return 0x3B // Control / LControl
    case 0xA3: return 0x3E       // RControl
    case 0x12, 0xA4: return 0x3A // Alt / LAlt -> Option
    case 0xA5: return 0x3D       // RAlt -> RightOption
    case 0x5B: return 0x37       // LWin -> Command
    case 0x5C: return 0x36       // RWin -> RightCommand
    case 0x14: return 0x39       // CapsLock
    case 0x5D: return 0x6E       // VK_APPS -> ContextualMenu
    default: return UInt16(vk & 0xFF)
    }
  }

  /// Translates an AT Set 1 hardware scan code (with `0xE000` prefix for extended keys)
  /// to the physical macOS HIToolbox `kVK_*` position.
  public static func carbonKeyCode(fromATScanCode scanCode: UInt32) -> UInt16? {
    switch scanCode {
    case 0x1E: return 0x00 // A
    case 0x1F: return 0x01 // S
    case 0x20: return 0x02 // D
    case 0x21: return 0x03 // F
    case 0x23: return 0x04 // H
    case 0x22: return 0x05 // G
    case 0x2C: return 0x06 // Z
    case 0x2D: return 0x07 // X
    case 0x2E: return 0x08 // C
    case 0x2F: return 0x09 // V
    case 0x56: return 0x0A // ISO Section
    case 0x30: return 0x0B // B
    case 0x10: return 0x0C // Q
    case 0x11: return 0x0D // W
    case 0x12: return 0x0E // E
    case 0x13: return 0x0F // R
    case 0x15: return 0x10 // Y
    case 0x14: return 0x11 // T
    case 0x02: return 0x12 // 1
    case 0x03: return 0x13 // 2
    case 0x04: return 0x14 // 3
    case 0x05: return 0x15 // 4
    case 0x07: return 0x16 // 6
    case 0x06: return 0x17 // 5
    case 0x0D: return 0x18 // =
    case 0x0A: return 0x19 // 9
    case 0x08: return 0x1A // 7
    case 0x0C: return 0x1B // -
    case 0x09: return 0x1C // 8
    case 0x0B: return 0x1D // 0
    case 0x1B: return 0x1E // ]
    case 0x18: return 0x1F // O
    case 0x16: return 0x20 // U
    case 0x1A: return 0x21 // [
    case 0x17: return 0x22 // I
    case 0x19: return 0x23 // P
    case 0x1C: return 0x24 // Return
    case 0x26: return 0x25 // L
    case 0x24: return 0x26 // J
    case 0x28: return 0x27 // '
    case 0x25: return 0x28 // K
    case 0x27: return 0x29 // ;
    case 0x2B: return 0x2A // \
    case 0x33: return 0x2B // ,
    case 0x35: return 0x2C // /
    case 0x31: return 0x2D // N
    case 0x32: return 0x2E // M
    case 0x34: return 0x2F // .
    case 0x0F: return 0x30 // Tab
    case 0x39: return 0x31 // Space
    case 0x29: return 0x32 // `
    case 0x0E: return 0x33 // Backspace
    case 0x01: return 0x35 // Escape
    case 0xE05C: return 0x36 // RightCommand
    case 0xE05B: return 0x37 // Command
    case 0x2A: return 0x38 // Shift
    case 0x3A: return 0x39 // CapsLock
    case 0x38: return 0x3A // Option
    case 0x1D: return 0x3B // Control
    case 0x36: return 0x3C // RightShift
    case 0xE038: return 0x3D // RightOption
    case 0xE01D: return 0x3E // RightControl
    case 0xE035: return 0x4B // KeypadDivide
    case 0xE01C: return 0x4C // KeypadEnter
    default: return nil
    }
  }

  /// Translates a macOS HIToolbox `kVK_*` keycode back into a Win32 virtual keycode (`VK_*`).
  public static func win32VirtualKey(fromCarbonKeyCode keyCode: UInt16) -> Int? {
    switch keyCode {
    case 0x00: return 0x41 // A
    case 0x01: return 0x53 // S
    case 0x02: return 0x44 // D
    case 0x03: return 0x46 // F
    case 0x04: return 0x48 // H
    case 0x05: return 0x47 // G
    case 0x06: return 0x5A // Z
    case 0x07: return 0x58 // X
    case 0x08: return 0x43 // C
    case 0x09: return 0x56 // V
    case 0x0A: return 0xE2 // ISO Section
    case 0x0B: return 0x42 // B
    case 0x0C: return 0x51 // Q
    case 0x0D: return 0x57 // W
    case 0x0E: return 0x45 // E
    case 0x0F: return 0x52 // R
    case 0x10: return 0x59 // Y
    case 0x11: return 0x54 // T
    case 0x12: return 0x31 // 1
    case 0x13: return 0x32 // 2
    case 0x14: return 0x33 // 3
    case 0x15: return 0x34 // 4
    case 0x16: return 0x36 // 6
    case 0x17: return 0x35 // 5
    case 0x18: return 0xBB // =
    case 0x19: return 0x39 // 9
    case 0x1A: return 0x37 // 7
    case 0x1B: return 0xBD // -
    case 0x1C: return 0x38 // 8
    case 0x1D: return 0x30 // 0
    case 0x1E: return 0xDD // ]
    case 0x1F: return 0x4F // O
    case 0x20: return 0x55 // U
    case 0x21: return 0xDB // [
    case 0x22: return 0x49 // I
    case 0x23: return 0x50 // P
    case 0x24, 0x4C: return 0x0D // Return / KeypadEnter
    case 0x25: return 0x4C // L
    case 0x26: return 0x4A // J
    case 0x27: return 0xDE // '
    case 0x28: return 0x4B // K
    case 0x29: return 0xBA // ;
    case 0x2A: return 0xDC // \
    case 0x2B: return 0xBC // ,
    case 0x2C: return 0xBF // /
    case 0x2D: return 0x4E // N
    case 0x2E: return 0x4D // M
    case 0x2F: return 0xBE // .
    case 0x30: return 0x09 // Tab
    case 0x31: return 0x20 // Space
    case 0x32: return 0xC0 // `
    case 0x33: return 0x08 // Backspace
    case 0x35: return 0x1B // Escape
    case 0x36: return 0x5C // RWin
    case 0x37: return 0x5B // LWin
    case 0x38: return 0xA0 // LShift
    case 0x39: return 0x14 // CapsLock
    case 0x3A: return 0xA4 // LAlt
    case 0x3B: return 0xA2 // LCtrl
    case 0x3C: return 0xA1 // RShift
    case 0x3D: return 0xA5 // RAlt
    case 0x3E: return 0xA3 // RCtrl
    case 0x40: return 0x80 // F17
    case 0x41: return 0x6E // KeypadDecimal
    case 0x43: return 0x6A // KeypadMultiply
    case 0x45: return 0x6B // KeypadPlus
    case 0x47: return 0x0C // KeypadClear
    case 0x4B: return 0x6F // KeypadDivide
    case 0x4E: return 0x6D // KeypadMinus
    case 0x4F: return 0x81 // F18
    case 0x50: return 0x82 // F19
    case 0x52: return 0x60 // Keypad0
    case 0x53: return 0x61 // Keypad1
    case 0x54: return 0x62 // Keypad2
    case 0x55: return 0x63 // Keypad3
    case 0x56: return 0x64 // Keypad4
    case 0x57: return 0x65 // Keypad5
    case 0x58: return 0x66 // Keypad6
    case 0x59: return 0x67 // Keypad7
    case 0x5A: return 0x83 // F20
    case 0x5B: return 0x68 // Keypad8
    case 0x5C: return 0x69 // Keypad9
    case 0x60: return 0x74 // F5
    case 0x61: return 0x75 // F6
    case 0x62: return 0x76 // F7
    case 0x63: return 0x72 // F3
    case 0x64: return 0x77 // F8
    case 0x65: return 0x78 // F9
    case 0x67: return 0x7A // F11
    case 0x69: return 0x7C // F13
    case 0x6A: return 0x7F // F16
    case 0x6B: return 0x7D // F14
    case 0x6D: return 0x79 // F10
    case 0x6E: return 0x5D // ContextualMenu
    case 0x6F: return 0x7B // F12
    case 0x71: return 0x7E // F15
    case 0x72: return 0x2F // Help
    case 0x73: return 0x24 // Home
    case 0x74: return 0x21 // PageUp
    case 0x75: return 0x2E // ForwardDelete
    case 0x76: return 0x73 // F4
    case 0x77: return 0x23 // End
    case 0x78: return 0x71 // F2
    case 0x79: return 0x22 // PageDown
    case 0x7A: return 0x70 // F1
    case 0x7B: return 0x25 // Left
    case 0x7C: return 0x27 // Right
    case 0x7D: return 0x28 // Down
    case 0x7E: return 0x26 // Up
    default: return nil
    }
  }

  /// AppKit special Unicode scalar string for non-printable navigation, function, and editing keys.
  public static func specialKeyCharacter(
    forWin32VK vk: Int,
    scanCode: UInt32 = 0,
    modifierFlags: ModifierFlags = []
  ) -> String? {
    switch vk {
    case 0x26: return "\u{F700}" // Up
    case 0x28: return "\u{F701}" // Down
    case 0x25: return "\u{F702}" // Left
    case 0x27: return "\u{F703}" // Right
    case 0x70...0x83:
      if let scalar = UnicodeScalar(0xF704 + (vk - 0x70)) {
        return String(scalar)
      }
      return ""
    case 0x2E: return "\u{F728}" // ForwardDelete
    case 0x24: return "\u{F729}" // Home
    case 0x23: return "\u{F72B}" // End
    case 0x21: return "\u{F72C}" // PageUp
    case 0x22: return "\u{F72D}" // PageDown
    case 0x2F: return "\u{F746}" // Help
    case 0x0C: return "\u{F739}" // Clear
    case 0x08: return "\u{007F}" // Backspace -> AppKit Delete
    case 0x0D: return (scanCode & 0xE000) == 0xE000 ? "\u{0003}" : "\r"
    case 0x09: return modifierFlags.contains(.shift) ? "\u{0019}" : "\t"
    case 0x1B: return "\u{001B}" // Escape
    case 0x10...0x14, 0x5B, 0x5C, 0x90, 0x91, 0xA0...0xA5:
      return "" // Modifier-only keys emit no characters
    default:
      return nil
    }
  }

  /// Translates a Win32 virtual key into AppKit `characters` and `charactersIgnoringModifiers`
  /// using Win32 `ToUnicodeEx` (with dead-key-safe flag `0x0004`) and `MapVirtualKeyExW`.
  ///
  /// Matches AppKit semantics:
  /// - `characters` reflects active modifiers (`shift`, `capsLock`, `control`, `option`/AltGr),
  ///   while keeping `.command` neutral and returning `""` on dead keys.
  /// - `charactersIgnoringModifiers` applies `shift` only (ignoring `command`/`option`/`control`/`capsLock`)
  ///   and preserves the spacing character for dead keys.
  public static func translateWin32Key(
    vk: Int,
    scanCode: UInt32 = 0,
    modifierFlags: ModifierFlags = [],
    keyboardLayout: UInt64 = 0
  ) -> (characters: String, charactersIgnoringModifiers: String, isDeadKey: Bool) {
    if let special = specialKeyCharacter(
      forWin32VK: vk,
      scanCode: scanCode,
      modifierFlags: modifierFlags
    ) {
      return (special, special, false)
    }

    #if os(Windows)
      let modBits = UInt32(modifierFlags.rawValue & 0xFFFFFFFF)
      var buf = [CChar](repeating: 0, count: 64)
      var deadChars: Int32 = 0
      let lenChars = cak_translate_vk_to_utf8(
        UInt32(clamping: vk),
        scanCode,
        modBits,
        keyboardLayout,
        0,
        &buf,
        Int32(buf.count),
        &deadChars
      )
      let rawChars = lenChars > 0 ? String(cString: buf) : ""
      let isDead = deadChars != 0
      let chars = isDead ? "" : rawChars

      var ignBuf = [CChar](repeating: 0, count: 64)
      var deadIgn: Int32 = 0
      let lenIgn = cak_translate_vk_to_utf8(
        UInt32(clamping: vk),
        scanCode,
        modBits,
        keyboardLayout,
        1,
        &ignBuf,
        Int32(ignBuf.count),
        &deadIgn
      )
      let ignChars = lenIgn > 0 ? String(cString: ignBuf) : rawChars
      if !chars.isEmpty || !ignChars.isEmpty || isDead || deadIgn != 0 {
        return (chars, ignChars, isDead || deadIgn != 0)
      }
    #endif

    let fallback = fallbackUSCharacter(forWin32VK: vk, shift: modifierFlags.contains(.shift))
    let capsXorShift = modifierFlags.contains(.shift) != modifierFlags.contains(.capsLock)
    let fallbackWithMods: String
    if modifierFlags.contains(.control) && !modifierFlags.contains(.option),
      let scalar = fallback.unicodeScalars.first,
      (0x61...0x7A).contains(scalar.value) || (0x41...0x5A).contains(scalar.value)
    {
      let ctrlCode = (scalar.value & 0x1F)
      fallbackWithMods = UnicodeScalar(ctrlCode).map { String($0) } ?? fallback
    } else if (0x41...0x5A).contains(vk) {
      fallbackWithMods = capsXorShift ? fallback.uppercased() : fallback.lowercased()
    } else {
      fallbackWithMods = fallback
    }
    return (fallbackWithMods, fallback, false)
  }

  /// Constructs an `NSEvent` from a Win32 keyboard message using layout-aware `ToUnicodeEx`
  /// character mapping and physical keycode translation.
  public static func win32KeyEvent(
    type: EventType = .keyDown,
    vk: Int,
    scanCode: UInt32 = 0,
    modifierFlags: ModifierFlags = [],
    location: NSPoint = .zero,
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
    windowNumber: Int = 0,
    window: NSWindow? = nil,
    isARepeat: Bool = false,
    keyboardLayout: UInt64 = 0
  ) -> NSEvent {
    let code = carbonKeyCode(fromWin32VK: vk, scanCode: scanCode)
    if type == .flagsChanged {
      return NSEvent(
        type: .flagsChanged,
        locationInWindow: location,
        modifierFlags: modifierFlags,
        timestamp: timestamp,
        windowNumber: windowNumber,
        window: window,
        characters: nil,
        charactersIgnoringModifiers: nil,
        isARepeat: false,
        keyCode: code
      )
    }
    let translated = translateWin32Key(
      vk: vk,
      scanCode: scanCode,
      modifierFlags: modifierFlags,
      keyboardLayout: keyboardLayout
    )
    return NSEvent(
      type: type,
      locationInWindow: location,
      modifierFlags: modifierFlags,
      timestamp: timestamp,
      windowNumber: windowNumber,
      window: window,
      characters: translated.characters,
      charactersIgnoringModifiers: translated.charactersIgnoringModifiers,
      isARepeat: isARepeat,
      keyCode: code
    )
  }

  /// Returns the characters generated by this key event as if the specified modifier flags
  /// were applied under the current keyboard layout (macOS 10.15+ AppKit API).
  public func characters(byApplyingModifiers modifiers: ModifierFlags) -> String? {
    guard type == .keyDown || type == .keyUp else { return nil }
    guard let vk = Self.win32VirtualKey(fromCarbonKeyCode: keyCode) else {
      return modifiers.contains(.shift)
        ? charactersIgnoringModifiers?.uppercased()
        : charactersIgnoringModifiers?.lowercased()
    }
    let scan: UInt32 = keyCode == 0x4C ? 0xE01C : 0
    return Self.translateWin32Key(vk: vk, scanCode: scan, modifierFlags: modifiers).characters
  }

  /// Matches this key event against an AppKit `keyEquivalent` string and modifier mask.
  ///
  /// Follows AppKit shortcut rules:
  /// - An uppercase alphabetic `keyEquivalent` (e.g. `"Z"`) implicitly requires `.shift`.
  /// - A non-alphabetic shifted symbol `keyEquivalent` (e.g. `"?"`, `"+"`, `"!"`) matches when
  ///   produced with `.shift` even if `modifierMask` did not explicitly list `.shift`.
  public func matchesKeyEquivalent(_ keyEquivalent: String, modifierMask: ModifierFlags) -> Bool {
    guard type == .keyDown, !keyEquivalent.isEmpty else { return false }
    let shortcutMask: ModifierFlags = [.command, .option, .control, .shift]
    let eventMods = modifierFlags.intersection(shortcutMask)
    var requiredMods = modifierMask.intersection(shortcutMask)

    let lowerEq = keyEquivalent.lowercased()
    let upperEq = keyEquivalent.uppercased()
    let isCaseSensitiveLetter = lowerEq != upperEq
    if isCaseSensitiveLetter && keyEquivalent == upperEq {
      requiredMods.insert(.shift)
    }

    let ign = charactersIgnoringModifiers ?? ""
    let ch = characters ?? ""

    if eventMods == requiredMods {
      if isCaseSensitiveLetter {
        return ign.lowercased() == lowerEq
      }
      return ign == keyEquivalent || ch == keyEquivalent
    }

    // Allow Shift used solely to type a non-letter layout symbol (e.g. Cmd+? via Shift+/).
    if !isCaseSensitiveLetter,
      !requiredMods.contains(.shift),
      eventMods == requiredMods.union(.shift)
    {
      return ign == keyEquivalent || ch == keyEquivalent
    }
    return false
  }

  private static func fallbackUSCharacter(forWin32VK vk: Int, shift: Bool) -> String {
    if (0x41...0x5A).contains(vk), let scalar = UnicodeScalar(vk) {
      let s = String(scalar)
      return shift ? s.uppercased() : s.lowercased()
    }
    if (0x30...0x39).contains(vk) {
      let unshifted = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
      let shifted = [")", "!", "@", "#", "$", "%", "^", "&", "*", "("]
      let idx = vk - 0x30
      return shift ? shifted[idx] : unshifted[idx]
    }
    switch vk {
    case 0x20: return " "
    case 0xBA: return shift ? ":" : ";"
    case 0xBB: return shift ? "+" : "="
    case 0xBC: return shift ? "<" : ","
    case 0xBD: return shift ? "_" : "-"
    case 0xBE: return shift ? ">" : "."
    case 0xBF: return shift ? "?" : "/"
    case 0xC0: return shift ? "~" : "`"
    case 0xDB: return shift ? "{" : "["
    case 0xDC: return shift ? "|" : "\\"
    case 0xDD: return shift ? "}" : "]"
    case 0xDE: return shift ? "\"" : "'"
    case 0x60...0x69: return String(vk - 0x60)
    case 0x6A: return "*"
    case 0x6B: return "+"
    case 0x6D: return "-"
    case 0x6E: return "."
    case 0x6F: return "/"
    default: return ""
    }
  }
}

open class NSCursor: NSObject, @unchecked Sendable {
  private let kind: Int
  nonisolated(unsafe) public private(set) static var current: NSCursor = .arrow

  private init(kind: Int) {
    self.kind = kind
    super.init()
  }

  public static let arrow = NSCursor(kind: 0)
  public static let iBeam = NSCursor(kind: 1)
  public static let pointingHand = NSCursor(kind: 2)
  public static let crosshair = NSCursor(kind: 3)
  public static let resizeLeftRight = NSCursor(kind: 4)
  public static let resizeUpDown = NSCursor(kind: 5)
  public static let columnResize = NSCursor(kind: 4)
  public static let rowResize = NSCursor(kind: 5)
  public static let openHand = NSCursor(kind: 2)
  public static let closedHand = NSCursor(kind: 2)

  public func set() {
    Self.current = self
    #if os(Windows)
      cak_set_cursor(Int32(kind))
    #endif
  }

  public func push() { set() }
  public static func pop() { arrow.set() }
}

public protocol NSHapticFeedbackPerformer {
  func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern, performanceTime: NSHapticFeedbackManager.PerformanceTime)
}

public final class NSHapticFeedbackManager: NSObject, @unchecked Sendable {
  public enum FeedbackPattern: Int, Sendable {
    case generic = 0
    case alignment = 1
    case levelChange = 2
  }

  public enum PerformanceTime: UInt, Sendable {
    case `default` = 0
    case now = 1
    case drawCompleted = 2
  }

  private struct DefaultPerformer: NSHapticFeedbackPerformer {
    func perform(_ pattern: FeedbackPattern, performanceTime: PerformanceTime) {}
  }

  public static var defaultPerformer: any NSHapticFeedbackPerformer { DefaultPerformer() }
}
