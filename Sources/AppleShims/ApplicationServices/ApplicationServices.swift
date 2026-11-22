import Foundation
import CoreFoundation
import CoreGraphics
#if os(Windows)
  import CAppKitWindows
#endif

#if !os(macOS)
  private let _axUIElementTypeID: CFTypeID = 101
  private let _axValueTypeID: CFTypeID = 102
  private let _axTextMarkerRangeTypeID: CFTypeID = 103

  public final class AXUIElement: NSObject, _CrossCFTypeIDProvider, _CrossAXWindowIDProvider, @unchecked Sendable {
    public let pid: Int32
    public let hwnd: Int64
    public var _crossCFTypeID: CFTypeID { _axUIElementTypeID }
    public var _crossWindowID: UInt32 {
      hwnd != 0 ? UInt32(truncatingIfNeeded: UInt64(bitPattern: hwnd)) : 0
    }

    public init(pid: Int32 = 0, hwnd: Int64 = 0) {
      self.pid = pid
      self.hwnd = hwnd
      super.init()
    }

    public override func isEqual(_ object: Any?) -> Bool {
      guard let other = object as? AXUIElement else { return false }
      return pid == other.pid && hwnd == other.hwnd
    }

    public override var hash: Int {
      var hasher = Hasher()
      hasher.combine(pid)
      hasher.combine(hwnd)
      return hasher.finalize()
    }
  }

  public enum AXError: Int32, Sendable, Equatable {
    case success = 0
    case failure = -25200
    case illegalArgument = -25201
    case invalidUIElement = -25202
    case invalidUIElementObserver = -25203
    case cannotComplete = -25204
    case attributeUnsupported = -25205
    case actionUnsupported = -25206
    case notificationUnsupported = -25207
    case notImplemented = -25208
    case notificationAlreadyRegistered = -25209
    case notificationNotRegistered = -25210
    case apiDisabled = -25211
    case noValue = -25212
    case parameterizedAttributeUnsupported = -25213
    case notEnoughPrecision = -25214
  }

  public enum AXValueType: UInt32, Sendable {
    case illegal = 0
    case cgPoint = 1
    case cgSize = 2
    case cgRect = 3
    case cfRange = 4
    case axError = 5
  }

  public final class AXValue: NSObject, _CrossCFTypeIDProvider, @unchecked Sendable {
    public let valueType: AXValueType
    fileprivate var point: CGPoint = .zero
    fileprivate var size: CGSize = .zero
    fileprivate var rect: CGRect = .zero
    fileprivate var range: CFRange = CFRange()
    fileprivate var error: AXError = .success
    public var _crossCFTypeID: CFTypeID { _axValueTypeID }

    public init(type: AXValueType = .illegal) {
      self.valueType = type
      super.init()
    }
  }

  public func AXUIElementGetTypeID() -> CFTypeID { _axUIElementTypeID }
  public func AXValueGetTypeID() -> CFTypeID { _axValueTypeID }
  public func AXTextMarkerRangeGetTypeID() -> CFTypeID { _axTextMarkerRangeTypeID }

  public func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ id: UnsafeMutablePointer<CGWindowID>
  ) -> AXError {
    guard element.hwnd != 0 else {
      id.pointee = 0
      return .invalidUIElement
    }
    id.pointee = element._crossWindowID
    return id.pointee != 0 ? .success : .invalidUIElement
  }

  public let kAXTrustedCheckOptionPrompt: Unmanaged<CFString> = Unmanaged.passRetained("AXTrustedCheckOptionPrompt" as NSString)
  public let kAXWindowsAttribute = "AXWindows"
  public let kAXFrontmostAttribute = "AXFrontmost"
  public let kAXHiddenAttribute = "AXHidden"
  public let kAXMinimizeButtonAttribute = "AXMinimizeButton"
  public let kAXSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
  public let kAXStringForTextMarkerRangeParameterizedAttribute = "AXStringForTextMarkerRange"
  public let kAXFocusedWindowAttribute = "AXFocusedWindow"
  public let kAXMainWindowAttribute = "AXMainWindow"
  public let kAXFocusedUIElementAttribute = "AXFocusedUIElement"
  public let kAXPositionAttribute = "AXPosition"
  public let kAXSizeAttribute = "AXSize"
  public let kAXTitleAttribute = "AXTitle"
  public let kAXRoleAttribute = "AXRole"
  public let kAXSubroleAttribute = "AXSubrole"
  public let kAXMinimizedAttribute = "AXMinimized"
  public let kAXChildrenAttribute = "AXChildren"
  public let kAXMenuBarAttribute = "AXMenuBar"
  public let kAXEnabledAttribute = "AXEnabled"
  public let kAXValueAttribute = "AXValue"
  public let kAXSelectedTextAttribute = "AXSelectedText"
  public let kAXSelectedTextRangeAttribute = "AXSelectedTextRange"
  public let kAXNumberOfCharactersAttribute = "AXNumberOfCharacters"
  public let kAXCloseButtonAttribute = "AXCloseButton"
  public let kAXFullScreenButtonAttribute = "AXFullScreenButton"
  public let kAXRaiseAction = "AXRaise"
  public let kAXPressAction = "AXPress"
  public let kAXStandardWindowSubrole = "AXStandardWindow"
  public let kAXDialogSubrole = "AXDialog"
  public let kAXWindowRole = "AXWindow"
  public let kAXMenuBarItemRole = "AXMenuBarItem"
  public let kAXMenuItemRole = "AXMenuItem"
  public let kAXMenuRole = "AXMenu"
  public let kAXMenuItemCmdCharAttribute = "AXMenuItemCmdChar"
  public let kAXMenuItemCmdModifiersAttribute = "AXMenuItemCmdModifiers"
  public let kAXMenuItemCmdVirtualKeyAttribute = "AXMenuItemCmdVirtualKey"
  public let kAXMenuItemMarkCharAttribute = "AXMenuItemMarkChar"

  public func AXIsProcessTrusted() -> Bool { true }
  public func AXIsProcessTrustedWithOptions(_ options: CFDictionary?) -> Bool { true }
  public func AXUIElementCreateApplication(_ pid: Int32) -> AXUIElement { AXUIElement(pid: pid, hwnd: 0) }
  public func AXUIElementCreateSystemWide() -> AXUIElement { AXUIElement(pid: 0, hwnd: 0) }

  #if os(Windows)
    private func findWindowEntry(hwnd: Int64) -> cak_win_entry? {
      guard hwnd != 0 else { return nil }
      var count: Int32 = 0
      guard let ptr = cak_enum_top_windows(&count), count > 0 else { return nil }
      defer { cak_free(ptr) }
      let target = UInt64(bitPattern: hwnd)
      for i in 0..<Int(count) where ptr[i].hwnd == target {
        return ptr[i]
      }
      return nil
    }
  #endif

  public func AXUIElementCopyAttributeValue(
    _ element: AXUIElement,
    _ attribute: CFString,
    _ value: UnsafeMutablePointer<CFTypeRef?>
  ) -> AXError {
    value.pointee = nil
    #if os(Windows)
      let attr = attribute as String
      if element.hwnd == 0 {
        guard element.pid > 0 else { return .noValue }
        let targetPID = UInt32(bitPattern: element.pid)
        switch attr {
        case kAXWindowsAttribute:
          var count: Int32 = 0
          guard let ptr = cak_enum_top_windows(&count), count > 0 else {
            value.pointee = [] as NSArray
            return .success
          }
          defer { cak_free(ptr) }
          var windows: [AXUIElement] = []
          for i in 0..<Int(count) where ptr[i].pid == targetPID {
            windows.append(AXUIElement(pid: element.pid, hwnd: Int64(bitPattern: ptr[i].hwnd)))
          }
          value.pointee = windows as NSArray
          return .success
        case kAXFocusedWindowAttribute, kAXMainWindowAttribute:
          var count: Int32 = 0
          guard let ptr = cak_enum_top_windows(&count), count > 0 else { return .noValue }
          defer { cak_free(ptr) }
          for i in 0..<Int(count) where ptr[i].pid == targetPID && ptr[i].is_minimized == 0 {
            value.pointee = AXUIElement(pid: element.pid, hwnd: Int64(bitPattern: ptr[i].hwnd))
            return .success
          }
          return .noValue
        default:
          return .noValue
        }
      }

      switch attr {
      case kAXRoleAttribute:
        value.pointee = kAXWindowRole as NSString
        return .success
      case kAXSubroleAttribute:
        value.pointee = kAXStandardWindowSubrole as NSString
        return .success
      case "AXFullScreen":
        value.pointee = kCFBooleanFalse
        return .success
      case kAXMinimizeButtonAttribute:
        value.pointee = element
        return .success
      case kAXTitleAttribute:
        if let raw = cak_hwnd_title(UInt64(bitPattern: element.hwnd)) {
          defer { cak_free(raw) }
          value.pointee = String(cString: raw) as NSString
          return .success
        }
        return .noValue
      case kAXMinimizedAttribute:
        guard let entry = findWindowEntry(hwnd: element.hwnd) else { return .invalidUIElement }
        value.pointee = (entry.is_minimized != 0) ? kCFBooleanTrue : kCFBooleanFalse
        return .success
      case kAXPositionAttribute:
        guard let entry = findWindowEntry(hwnd: element.hwnd) else { return .invalidUIElement }
        var pt = CGPoint(x: CGFloat(entry.x), y: CGFloat(entry.y))
        value.pointee = AXValueCreate(.cgPoint, &pt)
        return .success
      case kAXSizeAttribute:
        guard let entry = findWindowEntry(hwnd: element.hwnd) else { return .invalidUIElement }
        var sz = CGSize(width: CGFloat(entry.width), height: CGFloat(entry.height))
        value.pointee = AXValueCreate(.cgSize, &sz)
        return .success
      default:
        return .attributeUnsupported
      }
    #else
      return .notImplemented
    #endif
  }

  public func AXUIElementCopyAttributeNames(_ element: AXUIElement, _ names: UnsafeMutablePointer<CFArray?>) -> AXError {
    names.pointee = nil
    return .notImplemented
  }

  public struct AXCopyMultipleAttributeOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let stopOnError = AXCopyMultipleAttributeOptions(rawValue: 1 << 0)
  }

  public func AXUIElementCopyMultipleAttributeValues(
    _ element: AXUIElement,
    _ attributes: CFArray,
    _ options: AXCopyMultipleAttributeOptions,
    _ values: UnsafeMutablePointer<CFArray?>
  ) -> AXError {
    values.pointee = nil
    return .notImplemented
  }

  public func AXUIElementCopyParameterizedAttributeValue(
    _ element: AXUIElement,
    _ parameterizedAttribute: CFString,
    _ parameter: CFTypeRef,
    _ result: UnsafeMutablePointer<CFTypeRef?>
  ) -> AXError {
    result.pointee = nil
    return .notImplemented
  }

  public func AXUIElementCopyActionNames(_ element: AXUIElement, _ names: UnsafeMutablePointer<CFArray?>) -> AXError {
    names.pointee = nil
    return .notImplemented
  }

  public func AXUIElementIsAttributeSettable(
    _ element: AXUIElement,
    _ attribute: CFString,
    _ settable: UnsafeMutablePointer<DarwinBoolean>
  ) -> AXError {
    #if os(Windows)
      let attr = attribute as String
      if element.hwnd != 0 && (attr == kAXPositionAttribute || attr == kAXSizeAttribute || attr == kAXMinimizedAttribute) {
        settable.pointee = DarwinBoolean(true)
        return .success
      }
      settable.pointee = DarwinBoolean(false)
      return .attributeUnsupported
    #else
      settable.pointee = DarwinBoolean(false)
      return .notImplemented
    #endif
  }

  @discardableResult
  public func AXUIElementSetAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
    #if os(Windows)
      let attr = attribute as String
      if element.hwnd == 0 {
        guard element.pid > 0 else { return .invalidUIElement }
        let targetPID = UInt32(bitPattern: element.pid)
        switch attr {
        case kAXFrontmostAttribute:
          if (value as? NSNumber)?.boolValue == true {
            return cak_activate_pid(targetPID) != 0 ? .success : .cannotComplete
          }
          return .success
        case kAXHiddenAttribute:
          let hidden = (value as? NSNumber)?.boolValue ?? false
          let ok = hidden ? cak_hide_pid(targetPID) : cak_activate_pid(targetPID)
          return ok != 0 ? .success : .cannotComplete
        case "AXManualAccessibility", "AXEnhancedUserInterface":
          return .success
        default:
          return .attributeUnsupported
        }
      }

      let rawHWND = UInt64(bitPattern: element.hwnd)
      switch attr {
      case kAXMinimizedAttribute:
        let minimized = (value as? NSNumber)?.boolValue ?? false
        return cak_control_window(rawHWND, minimized ? 1 : 3) != 0 ? .success : .cannotComplete
      case kAXPositionAttribute:
        guard let axVal = value as? AXValue, axVal.valueType == .cgPoint,
          let current = findWindowEntry(hwnd: element.hwnd)
        else { return .illegalArgument }
        let ok = cak_set_window_rect(
          rawHWND,
          Int32(axVal.point.x.rounded()),
          Int32(axVal.point.y.rounded()),
          current.width,
          current.height)
        return ok != 0 ? .success : .cannotComplete
      case kAXSizeAttribute:
        guard let axVal = value as? AXValue, axVal.valueType == .cgSize,
          let current = findWindowEntry(hwnd: element.hwnd)
        else { return .illegalArgument }
        let ok = cak_set_window_rect(
          rawHWND,
          current.x,
          current.y,
          Int32(axVal.size.width.rounded()),
          Int32(axVal.size.height.rounded()))
        return ok != 0 ? .success : .cannotComplete
      default:
        return .attributeUnsupported
      }
    #else
      return .notImplemented
    #endif
  }

  @discardableResult
  public func AXUIElementPerformAction(_ element: AXUIElement, _ action: CFString) -> AXError {
    #if os(Windows)
      if element.hwnd != 0 && (action as String) == kAXRaiseAction {
        return cak_control_window(UInt64(bitPattern: element.hwnd), 5) != 0 ? .success : .cannotComplete
      }
      return .actionUnsupported
    #else
      return .notImplemented
    #endif
  }

  public func AXUIElementGetPid(_ element: AXUIElement, _ pid: UnsafeMutablePointer<Int32>) -> AXError {
    guard element.pid > 0 else {
      pid.pointee = 0
      return .invalidUIElement
    }
    pid.pointee = element.pid
    return .success
  }

  @discardableResult
  public func AXUIElementSetMessagingTimeout(_ element: AXUIElement, _ timeoutInSeconds: Float) -> AXError {
    .success
  }

  public func AXValueCreate(_ theType: AXValueType, _ valuePtr: UnsafeRawPointer) -> AXValue? {
    let box = AXValue(type: theType)
    switch theType {
    case .cgPoint:
      box.point = valuePtr.loadUnaligned(as: CGPoint.self)
    case .cgSize:
      box.size = valuePtr.loadUnaligned(as: CGSize.self)
    case .cgRect:
      box.rect = valuePtr.loadUnaligned(as: CGRect.self)
    case .cfRange:
      box.range = valuePtr.loadUnaligned(as: CFRange.self)
    case .axError:
      box.error = valuePtr.loadUnaligned(as: AXError.self)
    case .illegal:
      return nil
    }
    return box
  }

  public func AXValueGetValue(_ value: AXValue, _ theType: AXValueType, _ valuePtr: UnsafeMutableRawPointer) -> Bool {
    guard value.valueType == theType else { return false }
    switch theType {
    case .cgPoint:
      valuePtr.storeBytes(of: value.point, as: CGPoint.self)
    case .cgSize:
      valuePtr.storeBytes(of: value.size, as: CGSize.self)
    case .cgRect:
      valuePtr.storeBytes(of: value.rect, as: CGRect.self)
    case .cfRange:
      valuePtr.storeBytes(of: value.range, as: CFRange.self)
    case .axError:
      valuePtr.storeBytes(of: value.error, as: AXError.self)
    case .illegal:
      return false
    }
    return true
  }

  public func AXValueGetType(_ value: AXValue) -> AXValueType { value.valueType }

  // Carbon HIToolbox Text Input Sources (TIS) shims
  public final class TISInputSource: NSObject, @unchecked Sendable {}
  public let kTISNotifyEnabledKeyboardInputSourcesChanged: CFString = "com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged" as NSString
  public let kTISPropertyInputSourceIsASCIICapable: CFString = "TISPropertyInputSourceIsASCIICapable" as NSString
  public let kTISPropertyInputModeID: CFString = "TISPropertyInputModeID" as NSString
  public let kTISPropertyLocalizedName: CFString = "TISPropertyLocalizedName" as NSString
  public let kTISPropertyInputSourceID: CFString = "TISPropertyInputSourceID" as NSString
  public let kTISPropertyInputSourceCategory: CFString = "TISPropertyInputSourceCategory" as NSString
  public let kTISCategoryKeyboardInputSource: CFString = "TISCategoryKeyboardInputSource" as NSString
  public let kTISPropertyInputSourceIsSelectCapable: CFString = "TISPropertyInputSourceIsSelectCapable" as NSString
  public let kTISPropertyUnicodeKeyLayoutData: CFString = "TISPropertyUnicodeKeyLayoutData" as NSString

  @discardableResult
  public func TISSelectInputSource(_ inputSource: TISInputSource) -> Int32 { 0 }
  public func TISCopyCurrentASCIICapableKeyboardInputSource() -> Unmanaged<TISInputSource>? { nil }
  public func TISCopyCurrentASCIICapableKeyboardLayoutInputSource() -> Unmanaged<TISInputSource>? { nil }
  public func TISCopyCurrentKeyboardInputSource() -> Unmanaged<TISInputSource>? { nil }
  public func TISCreateInputSourceList(_ properties: CFDictionary?, _ includeAllInstalled: Bool) -> Unmanaged<CFArray>? { nil }
  public func TISGetInputSourceProperty(_ inputSource: TISInputSource, _ propertyKey: CFString) -> UnsafeMutableRawPointer? { nil }
#endif
