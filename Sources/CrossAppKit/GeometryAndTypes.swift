import Foundation
#if canImport(CoreGraphics)
  @_exported import CoreGraphics
#endif
#if !os(macOS)
  import NativeAPI
#endif
#if !canImport(ObjectiveC)
  public struct ObjCBool: ExpressibleByBooleanLiteral, Sendable {
    public var boolValue: Bool
    public init(_ value: Bool) { self.boolValue = value }
    public init(booleanLiteral value: Bool) { self.boolValue = value }
  }

  public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
  }
#endif

public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public typealias NSRect = CGRect

public struct NSUserInterfaceItemIdentifier: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(rawValue: String) { self.rawValue = rawValue }
}

public struct NSDeviceDescriptionKey: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(rawValue: String) { self.rawValue = rawValue }
}

public struct NSModalResponse: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let OK = NSModalResponse(rawValue: 1)
  public static let cancel = NSModalResponse(rawValue: 0)
  public static let continueResponse = NSModalResponse(rawValue: -1002)
  public static let stop = NSModalResponse(rawValue: -1000)
  public static let abort = NSModalResponse(rawValue: -1001)
  public static let alertFirstButtonReturn = NSModalResponse(rawValue: 1000)
  public static let alertSecondButtonReturn = NSModalResponse(rawValue: 1001)
  public static let alertThirdButtonReturn = NSModalResponse(rawValue: 1002)
}

public enum NSBackingStoreType: UInt, Sendable {
  case retained = 0
  case nonretained = 1
  case buffered = 2
}

public enum NSWindowOrderingMode: Int, Sendable {
  case above = 1
  case below = -1
  case out = 0
}

public enum NSUserInterfaceLayoutOrientation: Int, Sendable {
  case horizontal = 0
  case vertical = 1
}

public struct NSLayoutPriority: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
  public let rawValue: Float
  public init(_ rawValue: Float) { self.rawValue = rawValue }
  public init(rawValue: Float) { self.rawValue = rawValue }
  public static func < (lhs: NSLayoutPriority, rhs: NSLayoutPriority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
  public static let required = NSLayoutPriority(1000)
  public static let defaultHigh = NSLayoutPriority(750)
  public static let dragThatCanResizeWindow = NSLayoutPriority(510)
  public static let windowSizeStayPut = NSLayoutPriority(500)
  public static let dragThatCannotResizeWindow = NSLayoutPriority(490)
  public static let defaultLow = NSLayoutPriority(250)
  public static let fittingSizeCompression = NSLayoutPriority(50)
  public static let fittingSizeLevel = NSLayoutPriority(50)
}

public struct NSDragOperation: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let copy = NSDragOperation(rawValue: 1)
  public static let link = NSDragOperation(rawValue: 2)
  public static let generic = NSDragOperation(rawValue: 4)
  public static let `private` = NSDragOperation(rawValue: 8)
  public static let move = NSDragOperation(rawValue: 16)
  public static let delete = NSDragOperation(rawValue: 32)
  public static let every = NSDragOperation(rawValue: UInt.max)
}

public enum CrossAppKitCoordinates {
  /// Primary display height in logical points, used to convert between AppKit's
  /// bottom-left Y-up screen coordinates and NativeAPI/Win32 top-left Y-down coordinates.
  public static var primaryScreenHeight: CGFloat {
    #if !os(macOS)
      if let primary = NativeAPI.DisplayManager.shared.getPrimary() {
        return CGFloat(primary.size.height)
      }
      if let first = NativeAPI.DisplayManager.shared.getAll().first {
        return CGFloat(first.size.height)
      }
    #endif
    return 1080
  }

  public static func rectFromNativeTopLeft(
    x: Double, y: Double, width: Double, height: Double, primaryHeight: CGFloat? = nil
  ) -> NSRect {
    let ph = primaryHeight ?? primaryScreenHeight
    return NSRect(
      x: CGFloat(x),
      y: ph - CGFloat(y) - CGFloat(height),
      width: CGFloat(width),
      height: CGFloat(height)
    )
  }

  public static func rectToNativeTopLeft(
    _ rect: NSRect, primaryHeight: CGFloat? = nil
  ) -> (x: Double, y: Double, width: Double, height: Double) {
    let ph = primaryHeight ?? primaryScreenHeight
    return (
      x: Double(rect.origin.x),
      y: Double(ph - rect.origin.y - rect.size.height),
      width: Double(rect.size.width),
      height: Double(rect.size.height)
    )
  }

  public static func pointFromNativeTopLeft(
    x: Double, y: Double, primaryHeight: CGFloat? = nil
  ) -> NSPoint {
    let ph = primaryHeight ?? primaryScreenHeight
    return NSPoint(x: CGFloat(x), y: ph - CGFloat(y))
  }

  public static func pointToNativeTopLeft(
    _ point: NSPoint, primaryHeight: CGFloat? = nil
  ) -> (x: Double, y: Double) {
    let ph = primaryHeight ?? primaryScreenHeight
    return (x: Double(point.x), y: Double(ph - point.y))
  }
}

#if !os(macOS)
  @_exported import CrossFoundation

  // Standard AppKit key character constants (NSEvent.h / NSText.h)
  public let NSNewlineCharacter: Int = 0x000A
  public let NSCarriageReturnCharacter: Int = 0x000D
  public let NSTabCharacter: Int = 0x0009
  public let NSBackTabCharacter: Int = 0x0019
  public let NSBackspaceCharacter: Int = 0x0008
  public let NSDeleteCharacter: Int = 0x007F
  public let NSEnterCharacter: Int = 0x0003
  public let NSFormFeedCharacter: Int = 0x000C

  public let NSUpArrowFunctionKey: Int = 0xF700
  public let NSDownArrowFunctionKey: Int = 0xF701
  public let NSLeftArrowFunctionKey: Int = 0xF702
  public let NSRightArrowFunctionKey: Int = 0xF703
  public let NSF1FunctionKey: Int = 0xF704
  public let NSF2FunctionKey: Int = 0xF705
  public let NSF3FunctionKey: Int = 0xF706
  public let NSF4FunctionKey: Int = 0xF707
  public let NSF5FunctionKey: Int = 0xF708
  public let NSF6FunctionKey: Int = 0xF709
  public let NSF7FunctionKey: Int = 0xF70A
  public let NSF8FunctionKey: Int = 0xF70B
  public let NSF9FunctionKey: Int = 0xF70C
  public let NSF10FunctionKey: Int = 0xF70D
  public let NSF11FunctionKey: Int = 0xF70E
  public let NSF12FunctionKey: Int = 0xF70F
  public let NSF13FunctionKey: Int = 0xF710
  public let NSF14FunctionKey: Int = 0xF711
  public let NSF15FunctionKey: Int = 0xF712
  public let NSF16FunctionKey: Int = 0xF713
  public let NSF17FunctionKey: Int = 0xF714
  public let NSF18FunctionKey: Int = 0xF715
  public let NSF19FunctionKey: Int = 0xF716
  public let NSF20FunctionKey: Int = 0xF717
  public let NSF21FunctionKey: Int = 0xF718
  public let NSF22FunctionKey: Int = 0xF719
  public let NSF23FunctionKey: Int = 0xF71A
  public let NSF24FunctionKey: Int = 0xF71B
  public let NSF25FunctionKey: Int = 0xF71C
  public let NSF26FunctionKey: Int = 0xF71D
  public let NSF27FunctionKey: Int = 0xF71E
  public let NSF28FunctionKey: Int = 0xF71F
  public let NSF29FunctionKey: Int = 0xF720
  public let NSF30FunctionKey: Int = 0xF721
  public let NSF31FunctionKey: Int = 0xF722
  public let NSF32FunctionKey: Int = 0xF723
  public let NSF33FunctionKey: Int = 0xF724
  public let NSF34FunctionKey: Int = 0xF725
  public let NSF35FunctionKey: Int = 0xF726
  public let NSInsertFunctionKey: Int = 0xF727
  public let NSDeleteFunctionKey: Int = 0xF728
  public let NSHomeFunctionKey: Int = 0xF729
  public let NSBeginFunctionKey: Int = 0xF72A
  public let NSEndFunctionKey: Int = 0xF72B
  public let NSPageUpFunctionKey: Int = 0xF72C
  public let NSPageDownFunctionKey: Int = 0xF72D
  public let NSPrintScreenFunctionKey: Int = 0xF72E
  public let NSScrollLockFunctionKey: Int = 0xF72F
  public let NSPauseFunctionKey: Int = 0xF730
  public let NSSysReqFunctionKey: Int = 0xF731
  public let NSBreakFunctionKey: Int = 0xF732
  public let NSResetFunctionKey: Int = 0xF733
  public let NSStopFunctionKey: Int = 0xF734
  public let NSMenuFunctionKey: Int = 0xF735
  public let NSUserFunctionKey: Int = 0xF736
  public let NSSystemFunctionKey: Int = 0xF737
  public let NSPrintFunctionKey: Int = 0xF738
  public let NSClearLineFunctionKey: Int = 0xF739
  public let NSClearDisplayFunctionKey: Int = 0xF73A
  public let NSInsertLineFunctionKey: Int = 0xF73B
  public let NSDeleteLineFunctionKey: Int = 0xF73C
  public let NSInsertCharFunctionKey: Int = 0xF73D
  public let NSDeleteCharFunctionKey: Int = 0xF73E
  public let NSPrevFunctionKey: Int = 0xF73F
  public let NSNextFunctionKey: Int = 0xF740
  public let NSSelectFunctionKey: Int = 0xF741
  public let NSExecuteFunctionKey: Int = 0xF742
  public let NSUndoFunctionKey: Int = 0xF743
  public let NSRedoFunctionKey: Int = 0xF744
  public let NSFindFunctionKey: Int = 0xF745
  public let NSHelpFunctionKey: Int = 0xF746
  public let NSModeSwitchFunctionKey: Int = 0xF747

  public enum NSCompositingOperation: UInt, Sendable {
    case clear = 0
    case copy = 1
    case sourceOver = 2
    case sourceIn = 3
    case sourceOut = 4
    case sourceAtop = 5
    case destinationOver = 6
    case destinationIn = 7
    case destinationOut = 8
    case destinationAtop = 9
    case xor = 10
    case plusDarker = 11
    case plusLighter = 13
    case multiply = 14
    case screen = 15
    case overlay = 16
  }

  extension CGRect {
    public func fill(using operation: NSCompositingOperation = .sourceOver) {
      guard let ctx = _OffscreenDrawingContext.current else { return }
      ctx.ops.append(.shape(rect: self, radius: 0, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    }
  }

  extension RunLoop.Mode {
    public static let eventTracking = RunLoop.Mode("NSEventTrackingRunLoopMode")
    public static let modalPanel = RunLoop.Mode("NSModalPanelRunLoopMode")
  }

  open class RelativeDateTimeFormatter: Formatter, @unchecked Sendable {
    public enum DateTimeStyle: Int, Sendable {
      case numeric = 0
      case named = 1
    }

    public enum UnitsStyle: Int, Sendable {
      case full = 0
      case spellOut = 1
      case short = 2
      case abbreviated = 3
    }

    public var dateTimeStyle: DateTimeStyle = .numeric
    public var unitsStyle: UnitsStyle = .full
    public var locale: Locale! = .current

    public func localizedString(for date: Date, relativeTo referenceDate: Date) -> String {
      date.formatted(.relative(presentation: dateTimeStyle == .named ? .named : .numeric))
    }

    public func localizedString(fromTimeInterval timeInterval: TimeInterval) -> String {
      let target = Date().addingTimeInterval(timeInterval)
      return localizedString(for: target, relativeTo: Date())
    }
  }

  open class ListFormatter: Formatter, @unchecked Sendable {
    public var locale: Locale! = .current

    public static func localizedString(byJoining strings: [String]) -> String {
      strings.formatted(.list(type: .and))
    }

    public func string(from items: [Any]) -> String? {
      Self.localizedString(byJoining: items.map { String(describing: $0) })
    }
  }
#endif
