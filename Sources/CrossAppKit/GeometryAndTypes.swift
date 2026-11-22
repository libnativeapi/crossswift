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
  open class DistributedNotificationCenter: NotificationCenter, @unchecked Sendable {
    private static let sharedDistributed = DistributedNotificationCenter()
    public static func `default`() -> DistributedNotificationCenter {
      sharedDistributed
    }
  }

  public final class NSKeyValueObservation: NSObject, @unchecked Sendable {
    private var cancelBlock: (() -> Void)?
    public init(_ cancel: @escaping () -> Void = {}) {
      self.cancelBlock = cancel
    }
    public func invalidate() {
      cancelBlock?()
      cancelBlock = nil
    }
    deinit { invalidate() }
  }

  public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let new = NSKeyValueObservingOptions(rawValue: 1 << 0)
    public static let old = NSKeyValueObservingOptions(rawValue: 1 << 1)
    public static let initial = NSKeyValueObservingOptions(rawValue: 1 << 2)
    public static let prior = NSKeyValueObservingOptions(rawValue: 1 << 3)
  }

  public struct NSKeyValueObservedChange<Value>: @unchecked Sendable {
    public let newValue: Value?
    public let oldValue: Value?
    public init(newValue: Value? = nil, oldValue: Value? = nil) {
      self.newValue = newValue
      self.oldValue = oldValue
    }
  }

  open class NSItemProvider: NSObject, @unchecked Sendable {
    public let url: URL?
    public init?(contentsOf fileURL: URL!) {
      self.url = fileURL
      super.init()
    }
    public override init() {
      self.url = nil
      super.init()
    }
  }

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
