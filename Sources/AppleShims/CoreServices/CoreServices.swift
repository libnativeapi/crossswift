import Foundation
@_exported import CoreFoundation
@_exported import Carbon

#if !os(macOS)
  public typealias DCSDictionary = AnyObject

  public func DCSCopyTextDefinition(_ dictionary: AnyObject?, _ textString: CFString, _ range: CFRange) -> Unmanaged<CFString>? {
    nil
  }

  public typealias FSEventStreamRef = OpaquePointer
  public typealias FSEventStreamEventId = UInt64
  public typealias FSEventStreamEventFlags = UInt32
  public typealias FSEventStreamCreateFlags = UInt32
  public let kFSEventStreamEventIdSinceNow: FSEventStreamEventId = 0xFFFFFFFFFFFFFFFF
  public let kFSEventStreamCreateFlagNone: Int = 0
  public let kFSEventStreamCreateFlagUseCFTypes: Int = 1
  public let kFSEventStreamCreateFlagNoDefer: Int = 2
  public let kFSEventStreamCreateFlagWatchRoot: Int = 4
  public let kFSEventStreamCreateFlagFileEvents: Int = 0x10
  public let kFSEventStreamEventFlagMustScanSubDirs: Int = 1
  public let kFSEventStreamEventFlagEventIdsWrapped: Int = 8
  public let kFSEventStreamEventFlagHistoryDone: Int = 0x10
  public let kFSEventStreamEventFlagRootChanged: Int = 0x20
  public let kFSEventStreamEventFlagItemCreated: Int = 0x100
  public let kFSEventStreamEventFlagItemRemoved: Int = 0x200
  public let kFSEventStreamEventFlagItemRenamed: Int = 0x800
  public let kFSEventStreamEventFlagItemModified: Int = 0x1000

  public struct FSEventStreamContext {
    public var version: CFIndex
    public var info: UnsafeMutableRawPointer?
    public var retain: ((UnsafeRawPointer?) -> UnsafeRawPointer?)?
    public var release: ((UnsafeRawPointer?) -> Void)?
    public var copyDescription: ((UnsafeRawPointer?) -> Unmanaged<CFString>?)?
    public init(
      version: CFIndex = 0,
      info: UnsafeMutableRawPointer? = nil,
      retain: ((UnsafeRawPointer?) -> UnsafeRawPointer?)? = nil,
      release: ((UnsafeRawPointer?) -> Void)? = nil,
      copyDescription: ((UnsafeRawPointer?) -> Unmanaged<CFString>?)? = nil
    ) {
      self.version = version
      self.info = info
      self.retain = retain
      self.release = release
      self.copyDescription = copyDescription
    }
  }

  public typealias FSEventStreamCallback = (
    FSEventStreamRef,
    UnsafeMutableRawPointer?,
    Int,
    UnsafeMutableRawPointer,
    UnsafePointer<FSEventStreamEventFlags>,
    UnsafePointer<FSEventStreamEventId>
  ) -> Void

  public func FSEventStreamCreate(
    _ allocator: CFAllocator?,
    _ callback: FSEventStreamCallback,
    _ context: UnsafeMutablePointer<FSEventStreamContext>?,
    _ pathsToWatch: CFArray,
    _ sinceWhen: FSEventStreamEventId,
    _ latency: CFTimeInterval,
    _ flags: FSEventStreamCreateFlags
  ) -> FSEventStreamRef? {
    nil
  }
  public func FSEventStreamSetDispatchQueue(_ streamRef: FSEventStreamRef, _ q: DispatchQueue?) {}
  @discardableResult
  public func FSEventStreamStart(_ streamRef: FSEventStreamRef) -> Bool { false }
  public func FSEventStreamStop(_ streamRef: FSEventStreamRef) {}
  public func FSEventStreamInvalidate(_ streamRef: FSEventStreamRef) {}
  public func FSEventStreamRelease(_ streamRef: FSEventStreamRef) {}
#endif
