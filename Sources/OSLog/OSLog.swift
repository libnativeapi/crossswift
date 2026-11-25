import Foundation

public enum OSLogPrivacy: Sendable {
  case auto, `public`, `private`, sensitive
}

public enum OSLogFloatFormatting: Sendable {
  case fixed(precision: Int), exponential(precision: Int), hex, hybrid
  public static var fixed: OSLogFloatFormatting { .fixed(precision: 6) }
}

public enum OSLogIntegerFormatting: Sendable {
  case decimal, hex, octal
}

public struct OSLogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
  public struct StringInterpolation: StringInterpolationProtocol, Sendable {
    var value: String = ""
    public init(literalCapacity: Int, interpolationCount: Int) {
      value.reserveCapacity(literalCapacity)
    }
    public mutating func appendLiteral(_ literal: String) {
      value.append(literal)
    }
    public mutating func appendInterpolation<T>(
      _ argument: @autoclosure () -> T,
      privacy: OSLogPrivacy = .auto
    ) {
      value.append(String(describing: argument()))
    }
    public mutating func appendInterpolation<T: FloatingPoint>(
      _ number: @autoclosure () -> T,
      format: OSLogFloatFormatting = .fixed,
      privacy: OSLogPrivacy = .auto
    ) {
      value.append(String(describing: number()))
    }
    public mutating func appendInterpolation<T: BinaryInteger>(
      _ number: @autoclosure () -> T,
      format: OSLogIntegerFormatting = .decimal,
      privacy: OSLogPrivacy = .auto
    ) {
      value.append(String(describing: number()))
    }
  }

  public let text: String
  public init(stringLiteral value: String) { self.text = value }
  public init(stringInterpolation: StringInterpolation) { self.text = stringInterpolation.value }
}

public struct OSLogType: RawRepresentable, Equatable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  public static let `default` = OSLogType(rawValue: 0x00)
  public static let info = OSLogType(rawValue: 0x01)
  public static let debug = OSLogType(rawValue: 0x02)
  public static let error = OSLogType(rawValue: 0x10)
  public static let fault = OSLogType(rawValue: 0x11)
}

public final class OSLog: @unchecked Sendable {
  public let subsystem: String
  public let category: String
  public static let `default` = OSLog(subsystem: "", category: "")
  public static let disabled = OSLog(subsystem: "", category: "disabled")

  public init(subsystem: String, category: String) {
    self.subsystem = subsystem
    self.category = category
  }
}

public struct Logger: Sendable {
  public let subsystem: String
  public let category: String

  public init() {
    self.subsystem = ""
    self.category = ""
  }

  public init(subsystem: String, category: String) {
    self.subsystem = subsystem
    self.category = category
  }

  public init(_ logObj: OSLog) {
    self.subsystem = logObj.subsystem
    self.category = logObj.category
  }

  public func log(_ message: OSLogMessage) {}
  public func log(level: OSLogType, _ message: OSLogMessage) {}
  public func trace(_ message: OSLogMessage) {}
  public func debug(_ message: OSLogMessage) {}
  public func info(_ message: OSLogMessage) {}
  public func notice(_ message: OSLogMessage) {}
  public func warning(_ message: OSLogMessage) {}
  public func error(_ message: OSLogMessage) {}
  public func critical(_ message: OSLogMessage) {}
  public func fault(_ message: OSLogMessage) {}
}

public struct OSSignpostID: Equatable, Hashable, Sendable {
  public let rawValue: UInt64
  public init(_ rawValue: UInt64) { self.rawValue = rawValue }
  public static let exclusive = OSSignpostID(0xEEEEB0B5B2B2EEEE)
  public static let invalid = OSSignpostID(0)
  public static let null = OSSignpostID(0)
}

public struct OSSignpostIntervalState: Sendable {
  public let id: OSSignpostID
  public init(id: OSSignpostID = .exclusive) { self.id = id }
}

public struct OSSignposter: Sendable {
  public init() {}
  public init(subsystem: String, category: String) {}
  public init(logger: Logger) {}
  public init(logHandle: OSLog) {}

  public func makeSignpostID() -> OSSignpostID { .exclusive }
  public func makeSignpostID(from object: AnyObject) -> OSSignpostID {
    OSSignpostID(UInt64(UInt(bitPattern: ObjectIdentifier(object))))
  }

  public func beginInterval(
    _ name: StaticString,
    id: OSSignpostID = .exclusive
  ) -> OSSignpostIntervalState {
    OSSignpostIntervalState(id: id)
  }

  public func beginInterval(
    _ name: StaticString,
    id: OSSignpostID = .exclusive,
    _ message: OSLogMessage
  ) -> OSSignpostIntervalState {
    OSSignpostIntervalState(id: id)
  }

  public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {}
  public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: OSLogMessage) {}
  public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {}
  public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) {}

  public func withIntervalSignpost<T>(
    _ name: StaticString,
    id: OSSignpostID = .exclusive,
    around task: () throws -> T
  ) rethrows -> T {
    try task()
  }
}

public func os_log(
  _ type: OSLogType,
  dso: UnsafeRawPointer? = nil,
  log: OSLog = .default,
  _ message: StaticString,
  _ args: Any...
) {}

public func os_log(
  _ message: StaticString,
  dso: UnsafeRawPointer? = nil,
  log: OSLog = .default,
  type: OSLogType = .default,
  _ args: Any...
) {}
