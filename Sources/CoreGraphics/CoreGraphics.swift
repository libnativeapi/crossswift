@_exported import Foundation
@_exported import CoreFoundation
#if !os(macOS)
  import Carbon
#endif
#if os(Windows)
  import CAppKitWindows
#endif

#if !os(macOS)
  public typealias CGDirectDisplayID = UInt32
  public typealias CGKeyCode = UInt16
  public typealias UniChar = UInt16

  extension CGRect {
    public func equalTo(_ rect2: CGRect) -> Bool {
      self == rect2
    }
  }

  public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent = 0
    case absoluteColorimetric = 1
    case relativeColorimetric = 2
    case perceptual = 3
    case saturation = 4
  }

  public final class CGColorSpace: @unchecked Sendable {
    public static let sRGB: NSString = "kCGColorSpaceSRGB"
    public static let extendedSRGB: NSString = "kCGColorSpaceExtendedSRGB"
    public static let displayP3: NSString = "kCGColorSpaceDisplayP3"
    public init?(name: NSString) {}
    public init?(name: String) {}
  }

  public final class CGColor: @unchecked Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
      self.red = red
      self.green = green
      self.blue = blue
      self.alpha = alpha
    }

    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
      self.red = red
      self.green = green
      self.blue = blue
      self.alpha = alpha
    }

    public init(gray: CGFloat, alpha: CGFloat) {
      self.red = gray
      self.green = gray
      self.blue = gray
      self.alpha = alpha
    }

    public var components: [CGFloat]? { [red, green, blue, alpha] }
    public var numberOfComponents: Int { 4 }

    public func copy(alpha: CGFloat) -> CGColor? {
      CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public func converted(
      to space: CGColorSpace,
      intent: CGColorRenderingIntent,
      options: NSDictionary?
    ) -> CGColor? {
      self
    }

    public static let clear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
  }

  public final class CGImage: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let pngData: Data?
    public var bytesPerRow: Int { width * 4 }

    public init(width: Int, height: Int, pngData: Data? = nil) {
      self.width = width
      self.height = height
      self.pngData = pngData
    }
  }

  public struct CGAffineTransform: Equatable, Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
      self.a = a
      self.b = b
      self.c = c
      self.d = d
      self.tx = tx
      self.ty = ty
    }

    public init(scaleX sx: CGFloat, y sy: CGFloat) {
      self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public init(translationX tx: CGFloat, y ty: CGFloat) {
      self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    public init(rotationAngle angle: CGFloat) {
      let c = Foundation.cos(Double(angle))
      let s = Foundation.sin(Double(angle))
      self.init(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }

    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
  }

  public enum CGLineCap: Int32, Sendable {
    case butt = 0
    case round = 1
    case square = 2
  }

  public enum CGLineJoin: Int32, Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
  }

  public enum CGBlendMode: Int32, Sendable {
    case normal = 0
    case multiply = 1
    case screen = 2
    case overlay = 3
    case darken = 4
    case lighten = 5
    case clear = 16
    case copy = 17
    case sourceIn = 18
    case sourceOut = 19
    case sourceAtop = 20
    case destinationOver = 21
    case destinationIn = 22
    case destinationOut = 23
    case destinationAtop = 24
    case xor = 25
    case plusDarker = 26
    case plusLighter = 27
  }

  open class CGPath: @unchecked Sendable {
    public var commands: [Double] = []
    public init() {}
    public init(commands: [Double]) { self.commands = commands }
    public init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>?) {}
    public init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {}
    public init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {}
  }

  public final class CGMutablePath: CGPath, @unchecked Sendable {
    public override init() { super.init() }
    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) {}
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) {}
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {}
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {}
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {}
    public func closeSubpath() {}
  }

  public final class CGContext: @unchecked Sendable {
    public var textMatrix: CGAffineTransform = .identity
    public var textPosition: CGPoint = .zero
    public init() {}
    public func saveGState() {}
    public func restoreGState() {}
    public func setFillColor(_ color: CGColor) {}
    public func setStrokeColor(_ color: CGColor) {}
    public func setLineWidth(_ width: CGFloat) {}
    public func setLineCap(_ cap: CGLineCap) {}
    public func setLineJoin(_ join: CGLineJoin) {}
    public func setBlendMode(_ mode: CGBlendMode) {}
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addPath(_ path: Any) {}
    public func fillPath() {}
    public func strokePath() {}
    public func fill(_ rect: CGRect) {}
    public func fillEllipse(in rect: CGRect) {}
    public func stroke(_ rect: CGRect) {}
    public func strokeEllipse(in rect: CGRect) {}
  }

  public struct CGEventFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let maskAlphaShift = CGEventFlags(rawValue: 0x00010000)
    public static let maskShift = CGEventFlags(rawValue: 0x00020000)
    public static let maskControl = CGEventFlags(rawValue: 0x00040000)
    public static let maskAlternate = CGEventFlags(rawValue: 0x00080000)
    public static let maskCommand = CGEventFlags(rawValue: 0x00100000)
    public static let maskNumericPad = CGEventFlags(rawValue: 0x00200000)
    public static let maskHelp = CGEventFlags(rawValue: 0x00400000)
    public static let maskSecondaryFn = CGEventFlags(rawValue: 0x00800000)
    public static let maskNonCoalesced = CGEventFlags(rawValue: 0x00000100)
  }

  public enum CGEventType: UInt32, Sendable {
    case null = 0
    case leftMouseDown = 1
    case leftMouseUp = 2
    case rightMouseDown = 3
    case rightMouseUp = 4
    case mouseMoved = 5
    case leftMouseDragged = 6
    case rightMouseDragged = 7
    case keyDown = 10
    case keyUp = 11
    case flagsChanged = 12
    case scrollWheel = 22
    case otherMouseDown = 25
    case otherMouseUp = 26
    case otherMouseDragged = 27
    case tapDisabledByTimeout = 0xFFFFFFFE
    case tapDisabledByUserInput = 0xFFFFFFFF
  }

  public enum CGEventSourceStateID: Int32, Sendable {
    case privateState = -1
    case combinedSessionState = 0
    case hidSystemState = 1
  }

  public final class CGEventSource: @unchecked Sendable {
    public let stateID: CGEventSourceStateID
    public init?(stateID: CGEventSourceStateID) {
      self.stateID = stateID
    }
    public static func secondsSinceLastEventType(
      _ stateID: CGEventSourceStateID,
      eventType: CGEventType
    ) -> TimeInterval { 0 }
  }

  public typealias CGEventMask = UInt64
  public typealias CGEventTapProxy = OpaquePointer

  public enum CGEventTapLocation: UInt32, Sendable {
    case cghidEventTap = 0
    case cgSessionEventTap = 1
    case cgAnnotatedSessionEventTap = 2
  }

  public enum CGEventTapPlacement: UInt32, Sendable {
    case headInsertEventTap = 0
    case tailAppendEventTap = 1
  }

  public enum CGEventTapOptions: UInt32, Sendable {
    case defaultTap = 0
    case listenOnly = 1
  }

  public struct CGEventField: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32
    public init?(rawValue: UInt32) { self.rawValue = rawValue }
    public static let keyboardEventAutorepeat = CGEventField(rawValue: 8)!
    public static let keyboardEventKeycode = CGEventField(rawValue: 9)!
    public static let keyboardEventKeyboardType = CGEventField(rawValue: 10)!
    public static let eventSourceUserData = CGEventField(rawValue: 42)!
  }

  public typealias CGEventTapCallBack = (
    CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?
  ) -> Unmanaged<CGEvent>?

  public nonisolated(unsafe) var _cgPostToPidHook: ((_ pid: Int32, _ sendAction: @escaping () -> Void) -> Bool)?

  public final class CGEvent: @unchecked Sendable {
    public var flags: CGEventFlags = []
    public var type: CGEventType = .null
    public var timestamp: UInt64 = 0
    private var virtualKey: CGKeyCode = 0
    private var keyDown: Bool = false
    private var integerFields: [CGEventField: Int64] = [:]
    private var unicodeChars: [UniChar] = []
    public var data: CFData? { nil }
    public func __data(allocator: CFAllocator?) -> CFData? { nil }

    public init?(source: CGEventSource?) {}
    public init?(keyboardEventSource source: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {
      self.virtualKey = virtualKey
      self.keyDown = keyDown
      self.type = keyDown ? .keyDown : .keyUp
      self.integerFields[.keyboardEventKeycode] = Int64(virtualKey)
    }
    public init?(withDataAllocator allocator: CFAllocator?, data: CFData) { nil }

    public func getIntegerValueField(_ field: CGEventField) -> Int64 {
      integerFields[field] ?? 0
    }
    public func setIntegerValueField(_ field: CGEventField, value: Int64) {
      integerFields[field] = value
      if field == .keyboardEventKeycode {
        virtualKey = CGKeyCode(truncatingIfNeeded: value)
      }
    }
    public func setDoubleValueField(_ field: CGEventField, value: Double) {}
    public func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UniChar>?) {
      guard stringLength > 0, let unicodeString else {
        unicodeChars = []
        return
      }
      unicodeChars = Array(UnsafeBufferPointer(start: unicodeString, count: stringLength))
    }
    public func keyboardGetUnicodeString(
      maxStringLength: Int,
      actualStringLength: UnsafeMutablePointer<Int>?,
      unicodeString: UnsafeMutablePointer<UniChar>?
    ) {
      let count = min(max(0, maxStringLength), unicodeChars.count)
      actualStringLength?.pointee = count
      if count > 0, let unicodeString {
        for i in 0..<count { unicodeString[i] = unicodeChars[i] }
      }
    }
    public func post(tap: CGEventTapLocation) {
      dispatchSyntheticKeyboardEvent(targetPid: nil)
    }
    public func postToPid(_ pid: Int32) {
      dispatchSyntheticKeyboardEvent(targetPid: pid)
    }

    private func dispatchSyntheticKeyboardEvent(targetPid: Int32?) {
      #if os(Windows)
        guard keyDown || type == .keyDown else { return }
        let performSend = { [unicodeChars, virtualKey, flags] in
          if !unicodeChars.isEmpty {
            let text = String(utf16CodeUnits: unicodeChars, count: unicodeChars.count)
            _ = cak_send_unicode_text(text)
            return
          }
          let code = Int(virtualKey)
          if flags.contains(.maskCommand) {
            if code == Int(kVK_ANSI_V) {
              if let pid = targetPid, pid > 0 {
                _ = cak_send_paste_chord_to_pid(UInt32(pid))
              } else {
                _ = cak_send_paste_chord()
              }
            } else if code == Int(kVK_ANSI_C) {
              _ = cak_send_copy_chord()
            }
            return
          }
          switch code {
          case Int(kVK_Delete):
            _ = cak_send_backspaces(1)
          case Int(kVK_ForwardDelete):
            _ = cak_send_vk_key(0x2E)
          case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            _ = cak_send_vk_key(0x0D)
          case Int(kVK_Tab):
            _ = cak_send_vk_key(0x09)
          case Int(kVK_Escape):
            _ = cak_send_vk_key(0x1B)
          case Int(kVK_Space):
            _ = cak_send_vk_key(0x20)
          case Int(kVK_LeftArrow):
            _ = cak_send_vk_key(0x25)
          case Int(kVK_UpArrow):
            _ = cak_send_vk_key(0x26)
          case Int(kVK_RightArrow):
            _ = cak_send_vk_key(0x27)
          case Int(kVK_DownArrow):
            _ = cak_send_vk_key(0x28)
          default:
            break
          }
        }
        if let pid = targetPid, pid > 0 {
          if _cgPostToPidHook?(pid, performSend) == true {
            return
          }
          _ = cak_activate_pid(UInt32(bitPattern: pid))
        }
        performSend()
      #endif
    }

    public static func tapCreate(
      tap: CGEventTapLocation,
      place: CGEventTapPlacement,
      options: CGEventTapOptions,
      eventsOfInterest: CGEventMask,
      callback: CGEventTapCallBack,
      userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
      nil
    }

    public static func tapEnable(tap: CFMachPort, enable: Bool) {}
    public static func tapIsEnabled(tap: CFMachPort) -> Bool { false }
  }

  public enum CGError: Int32, Sendable {
    case success = 0
    case failure = 1000
  }

  public struct CGEventTapInformation: Sendable {
    public var eventTapID: UInt32 = 0
    public var tapPoint: CGEventTapLocation = .cghidEventTap
    public var options: CGEventTapOptions = .defaultTap
    public var eventsOfInterest: CGEventMask = 0
    public var tappingProcess: Int32 = 0
    public var processBeingTapped: Int32 = 0
    public var enabled: Bool = false
    public var minUsecLatency: Float = 0
    public var avgUsecLatency: Float = 0
    public var maxUsecLatency: Float = 0
    public init() {}
  }

  public func CGGetEventTapList(
    _ maxNumberOfTaps: UInt32,
    _ tapList: UnsafeMutablePointer<CGEventTapInformation>?,
    _ eventTapCount: UnsafeMutablePointer<UInt32>?
  ) -> CGError {
    eventTapCount?.pointee = 0
    return .success
  }

  public func CGDisplayCreateUUIDFromDisplayID(_ display: CGDirectDisplayID) -> Unmanaged<CFUUID>? {
    let hex = String(format: "%08X", display)
    return Unmanaged.passRetained(CFUUID("00000000-0000-0000-0000-0000\(hex)"))
  }

  public func CGMainDisplayID() -> CGDirectDisplayID { 1 }

  public typealias CGWindowID = UInt32
  public let kCGNullWindowID: CGWindowID = 0

  public struct CGWindowListOption: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let optionAll = CGWindowListOption([])
    public static let optionOnScreenOnly = CGWindowListOption(rawValue: 1 << 0)
    public static let optionOnScreenAboveWindow = CGWindowListOption(rawValue: 1 << 1)
    public static let optionOnScreenBelowWindow = CGWindowListOption(rawValue: 1 << 2)
    public static let optionIncludingWindow = CGWindowListOption(rawValue: 1 << 3)
    public static let excludeDesktopElements = CGWindowListOption(rawValue: 1 << 4)
  }

  public let kCGWindowNumber: CFString = "kCGWindowNumber" as NSString
  public let kCGWindowLayer: CFString = "kCGWindowLayer" as NSString
  public let kCGWindowOwnerPID: CFString = "kCGWindowOwnerPID" as NSString
  public let kCGWindowOwnerName: CFString = "kCGWindowOwnerName" as NSString
  public let kCGWindowName: CFString = "kCGWindowName" as NSString
  public let kCGWindowBounds: CFString = "kCGWindowBounds" as NSString
  public let kCGWindowIsOnscreen: CFString = "kCGWindowIsOnscreen" as NSString
  public let kCGWindowAlpha: CFString = "kCGWindowAlpha" as NSString

  public func CGWindowListCopyWindowInfo(
    _ option: CGWindowListOption,
    _ relativeToWindow: CGWindowID
  ) -> CFArray? {
    #if os(Windows)
      var count: Int32 = 0
      guard let entries = cak_enum_top_windows(&count), count > 0 else {
        return [] as NSArray
      }
      defer { cak_free(entries) }
      var result: [[String: Any]] = []
      result.reserveCapacity(Int(count))
      for i in 0..<Int(count) {
        let entry = entries[i]
        if option.contains(.optionOnScreenOnly) && entry.is_minimized != 0 {
          continue
        }
        let winID = UInt32(truncatingIfNeeded: entry.hwnd)
        result.append([
          kCGWindowNumber as String: winID,
          kCGWindowOwnerPID as String: Int32(bitPattern: entry.pid),
          kCGWindowLayer as String: 0,
          kCGWindowIsOnscreen as String: entry.is_minimized == 0,
          kCGWindowAlpha as String: 1.0,
        ])
      }
      return result as NSArray
    #else
      return nil
    #endif
  }

  public enum CGWindowLevelKey: Int32, Sendable {
    case baseWindow = 0
    case minimumWindow = 1
    case desktopWindow = 2
    case backstopMenu = 3
    case normalWindow = 4
    case floatingWindow = 5
    case tornOffMenuWindow = 6
    case dockWindow = 7
    case mainMenuWindow = 8
    case statusWindow = 9
    case modalPanelWindow = 10
    case popUpMenuWindow = 11
    case draggingWindow = 12
    case screenSaverWindow = 13
    case maximumWindow = 14
    case overlayWindow = 15
    case helpWindow = 16
    case utilityWindow = 17
    case desktopIconWindow = 18
    case cursorWindow = 19
    case assistiveTechHighWindow = 20
  }

  public func CGWindowLevelForKey(_ key: CGWindowLevelKey) -> Int32 {
    switch key {
    case .normalWindow: 0
    case .floatingWindow: 3
    case .dockWindow: 20
    case .mainMenuWindow: 24
    case .statusWindow: 25
    case .popUpMenuWindow: 101
    default: key.rawValue
    }
  }
#endif
