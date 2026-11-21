@_exported import Foundation
@_exported import CoreFoundation
@_exported import Darwin
@_exported import Observation
import CoreGraphics
import Carbon
#if canImport(FoundationNetworking)
  @_exported import FoundationNetworking
#endif
#if canImport(FoundationXML)
  @_exported import FoundationXML
#endif
#if canImport(Dispatch)
  @_exported import Dispatch
#endif
#if os(Windows)
  import CAppKitWindows
#endif
#if !os(macOS)
  import SwiftUIRuntime

  public typealias LocalizedStringResource = SwiftUIRuntime.LocalizedStringResource

  // MARK: - DateFormatter.FormattingContext

  extension DateFormatter {
    public enum FormattingContext: Int, Sendable {
      case unknown = 0
      case dynamic = 1
      case standalone = 2
      case listItem = 3
      case beginningOfSentence = 4
      case middleOfSentence = 5
    }

    public var formattingContext: FormattingContext {
      get { .unknown }
      set {}
    }
  }

  // MARK: - URLSession.bytes(for:)

  extension URLSession {
    public struct AsyncBytes: AsyncSequence, Sendable {
      public typealias Element = UInt8
      private let data: Data

      public init(data: Data) {
        self.data = data
      }

      public struct Lines: AsyncSequence, Sendable {
        public typealias Element = String
        private let lines: [String]

        init(data: Data) {
          let text = String(decoding: data, as: UTF8.self)
          self.lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
          private var index = 0
          private let lines: [String]
          init(lines: [String]) { self.lines = lines }
          public mutating func next() async throws -> String? {
            guard index < lines.count else { return nil }
            let line = lines[index]
            index += 1
            return line
          }
        }

        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(lines: lines) }
      }

      public var lines: Lines { Lines(data: data) }

      public struct AsyncIterator: AsyncIteratorProtocol {
        private var index: Data.Index
        private let data: Data
        init(data: Data) {
          self.data = data
          self.index = data.startIndex
        }
        public mutating func next() async throws -> UInt8? {
          guard index < data.endIndex else { return nil }
          let b = data[index]
          index = data.index(after: index)
          return b
        }
      }

      public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(data: data) }
    }

    public func bytes(for request: URLRequest) async throws -> (AsyncBytes, URLResponse) {
      let (data, response) = try await data(for: request)
      return (AsyncBytes(data: data), response)
    }

    public func bytes(from url: URL) async throws -> (AsyncBytes, URLResponse) {
      try await bytes(for: URLRequest(url: url))
    }
  }

  // MARK: - FileManager.trashItem & NSFileCoordinator

  public typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?

  extension FileManager {
    public func trashItem(at url: URL, resultingItemURL outResultURL: UnsafeMutablePointer<NSURL?>?) throws {
      try removeItem(at: url)
    }
  }

  public protocol NSFilePresenter: AnyObject {
    var presentedItemURL: URL? { get }
  }

  open class NSFileCoordinator: NSObject, @unchecked Sendable {
    public struct ReadingOptions: OptionSet, Sendable {
      public let rawValue: UInt
      public init(rawValue: UInt) { self.rawValue = rawValue }
      public static let withoutChanges = ReadingOptions(rawValue: 1 << 0)
      public static let resolvesSymbolicLink = ReadingOptions(rawValue: 1 << 1)
      public static let immediatelyAvailableMetadataOnly = ReadingOptions(rawValue: 1 << 2)
      public static let forUploading = ReadingOptions(rawValue: 1 << 3)
    }

    public struct WritingOptions: OptionSet, Sendable {
      public let rawValue: UInt
      public init(rawValue: UInt) { self.rawValue = rawValue }
      public static let forDeleting = WritingOptions(rawValue: 1 << 0)
      public static let forMoving = WritingOptions(rawValue: 1 << 1)
      public static let forMerging = WritingOptions(rawValue: 1 << 2)
      public static let forReplacing = WritingOptions(rawValue: 1 << 3)
      public static let contentIndependentMetadataOnly = WritingOptions(rawValue: 1 << 4)
    }

    public init(filePresenter filePresenterOrNil: (any NSFilePresenter)? = nil) {
      super.init()
    }

    public func coordinate(
      readingItemAt url: URL,
      options: ReadingOptions = [],
      error outError: NSErrorPointer,
      byAccessor reader: (URL) -> Void
    ) {
      reader(url)
    }

    public func coordinate(
      writingItemAt url: URL,
      options: WritingOptions = [],
      error outError: NSErrorPointer,
      byAccessor writer: (URL) -> Void
    ) {
      writer(url)
    }
  }

  // MARK: - DispatchSourceFileSystemObject shim

  public protocol DispatchSourceFileSystemObject: AnyObject {
    func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (() -> Void)?)
    func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (() -> Void)?)
    func resume()
    func cancel()
  }

  extension DispatchSourceFileSystemObject {
    public func setEventHandler(handler: (() -> Void)?) {
      setEventHandler(qos: .unspecified, flags: [], handler: handler)
    }
    public func setCancelHandler(handler: (() -> Void)?) {
      setCancelHandler(qos: .unspecified, flags: [], handler: handler)
    }
  }

  public final class _StubFileSystemObjectSource: DispatchSourceFileSystemObject, @unchecked Sendable {
    private var cancelHandler: (() -> Void)?
    private var cancelled = false
    public func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (() -> Void)?) {}
    public func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (() -> Void)?) {
      cancelHandler = handler
    }
    public func resume() {}
    public func cancel() {
      guard !cancelled else { return }
      cancelled = true
      cancelHandler?()
      cancelHandler = nil
    }
  }

  extension DispatchSource {
    public static func makeFileSystemObjectSource(
      fileDescriptor: Int32,
      eventMask: DispatchSource.FileSystemEvent,
      queue: DispatchQueue? = nil
    ) -> any DispatchSourceFileSystemObject {
      _StubFileSystemObjectSource()
    }
  }

  #if os(Windows)
    public final class _CrossDispatchSourceTimer: @unchecked Sendable {
      private let raw: any Dispatch.DispatchSourceTimer
      public init(_ raw: any Dispatch.DispatchSourceTimer) { self.raw = raw }

      public func schedule(
        deadline: DispatchTime,
        repeating interval: DispatchTimeInterval = .never,
        leeway: DispatchTimeInterval = .nanoseconds(0)
      ) {
        raw.schedule(deadline: deadline, repeating: interval, leeway: leeway)
      }

      public func schedule(
        deadline: DispatchTime,
        repeating interval: Double,
        leeway: DispatchTimeInterval = .nanoseconds(0)
      ) {
        raw.schedule(deadline: deadline, repeating: interval, leeway: leeway)
      }

      public func setEventHandler(
        qos: DispatchQoS = .unspecified,
        flags: DispatchWorkItemFlags = [],
        handler: (@Sendable () -> Void)?
      ) {
        raw.setEventHandler(qos: qos, flags: flags, handler: handler)
      }

      public func resume() { raw.resume() }
      public func cancel() { raw.cancel() }
    }

    extension DispatchSource {
      public static func makeTimerSource(queue: DispatchQueue?) -> _CrossDispatchSourceTimer {
        let raw: any Dispatch.DispatchSourceTimer = Dispatch.DispatchSource.makeTimerSource(
          flags: [], queue: queue)
        return _CrossDispatchSourceTimer(raw)
      }
    }
  #endif

  // MARK: - InlinePresentationIntent & AttributedString Markdown parsing

  public struct InlinePresentationIntent: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
    public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
    public static let code = InlinePresentationIntent(rawValue: 1 << 2)
    public static let strikethrough = InlinePresentationIntent(rawValue: 1 << 3)
    public static let softBreak = InlinePresentationIntent(rawValue: 1 << 4)
    public static let lineBreak = InlinePresentationIntent(rawValue: 1 << 5)
    public static let inlineHTML = InlinePresentationIntent(rawValue: 1 << 6)
    public static let blockHTML = InlinePresentationIntent(rawValue: 1 << 7)
  }

  public struct InlinePresentationIntentAttribute: CodableAttributedStringKey, Hashable, Sendable {
    public typealias Value = InlinePresentationIntent
    public static let name = "NSInlinePresentationIntent"
    public init() {}
  }

  extension AttributeDynamicLookup {
    public subscript(dynamicMember keyPath: KeyPath<AttributeScopes.FoundationAttributes, InlinePresentationIntentAttribute>) -> InlinePresentationIntentAttribute {
      self[InlinePresentationIntentAttribute.self]
    }
  }

  extension AttributeScopes.FoundationAttributes {
    public var inlinePresentationIntent: InlinePresentationIntentAttribute {
      InlinePresentationIntentAttribute()
    }
  }

  extension AttributedString.Runs.Run {
    public var inlinePresentationIntent: InlinePresentationIntent? {
      self[InlinePresentationIntentAttribute.self]
    }
  }

  extension Notification.Name {
    public static let NSSystemClockDidChange = Notification.Name("NSSystemClockDidChangeNotification")
  }

  public final class _CarbonCGEventProxy: @unchecked Sendable {
    public let flags = CGEventFlags(rawValue: 0)
  }

  public func CopyEventCGEvent(_ inEvent: EventRef?) -> Unmanaged<_CarbonCGEventProxy>? {
    nil
  }

  extension AttributedString {
    public struct MarkdownParsingOptions: Sendable {
      public enum InterpretedSyntax: Int, Sendable {
        case full = 0
        case inlineOnly = 1
        case inlineOnlyPreservingWhitespace = 2
      }
      public enum FailurePolicy: Int, Sendable {
        case returnPartiallyParsedIfPossible = 0
        case throwError = 1
      }
      public var allowsExtendedAttributes: Bool
      public var interpretedSyntax: InterpretedSyntax
      public var failurePolicy: FailurePolicy
      public var languageCode: String?

      public init(
        allowsExtendedAttributes: Bool = false,
        interpretedSyntax: InterpretedSyntax = .full,
        failurePolicy: FailurePolicy = .returnPartiallyParsedIfPossible,
        languageCode: String? = nil
      ) {
        self.allowsExtendedAttributes = allowsExtendedAttributes
        self.interpretedSyntax = interpretedSyntax
        self.failurePolicy = failurePolicy
        self.languageCode = languageCode
      }
    }

    public init(markdown: String, options: MarkdownParsingOptions = MarkdownParsingOptions()) throws {
      self.init(markdown)
    }
  }

  // MARK: - String.EnumerationOptions.byWords & NSMutableAttributedString convenience

  extension NSString.EnumerationOptions {
    public static let byWords = NSString.EnumerationOptions(rawValue: 3)
  }

  extension NSAttributedString {
    public convenience init(_empty: Void = ()) {
      self.init(string: "")
    }
  }

  extension NSMutableAttributedString {
    public convenience init() {
      self.init(string: "")
    }
  }

  extension URLSessionWebSocketDelegate {
    public func urlSession(
      _ session: URLSession,
      webSocketTask: URLSessionWebSocketTask,
      didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
      reason: Data?
    ) {}
  }

  extension DispatchSourceFileSystemObject {
    public var data: DispatchSource.FileSystemEvent { [] }
  }

  extension Locale {
    public struct CurrentLocaleDidChangeMessage: NotificationCenter.MainActorMessage {
      public typealias Subject = Locale
      public init() {}
    }
  }

  extension NotificationCenter.MessageIdentifier
  where Self == NotificationCenter.BaseMessageIdentifier<Locale.CurrentLocaleDidChangeMessage> {
    public static var currentLocaleDidChange: Self { .init() }
  }

  // MARK: - URLSessionConfiguration KVC / Selector & Windows FileHandle compatibility

  #if os(Windows)
    extension FileHandle {
      public var fileDescriptor: Int32 { -1 }
    }
  #endif

  extension URLSessionConfiguration {
    public func responds(to aSelector: Selector) -> Bool { false }
    public func setValue(_ value: Any?, forKey key: String) {}
  }

  #if os(Linux)
    // swift-corelibs-foundation's Bundle.urls(forResourcesWithExtension:subdirectory:)
    // returns `[NSURL]?` instead of `[URL]?` like Darwin Foundation.
    extension NSURL {
      public func deletingPathExtension() -> URL {
        (self as URL).deletingPathExtension()
      }
    }

    extension String {
      public init(contentsOf url: NSURL, encoding enc: String.Encoding) throws {
        try self.init(contentsOf: url as URL, encoding: enc)
      }
    }
  #endif

  extension NotificationCenter {
    public func addObserver(
      _ observer: Any,
      selector aSelector: Selector,
      name aName: NSNotification.Name?,
      object anObject: Any?
    ) {}
  }

  #if os(Windows)
    open class NSCache<KeyType: AnyObject, ObjectType: AnyObject>: NSObject {
      private let backing = Foundation.NSCache<KeyType, ObjectType>()

      public override init() { super.init() }

      open var name: String {
        get { backing.name }
        set { backing.name = newValue }
      }

      open var totalCostLimit: Int {
        get { backing.totalCostLimit }
        set { backing.totalCostLimit = newValue }
      }

      open var countLimit: Int {
        get { backing.countLimit }
        set { backing.countLimit = newValue }
      }

      open var evictsObjectsWithDiscardedContent: Bool {
        get { backing.evictsObjectsWithDiscardedContent }
        set { backing.evictsObjectsWithDiscardedContent = newValue }
      }

      open func object(forKey key: KeyType) -> ObjectType? {
        backing.object(forKey: key)
      }

      open func setObject(_ obj: ObjectType, forKey key: KeyType) {
        backing.setObject(obj, forKey: key)
      }

      open func setObject(_ obj: ObjectType, forKey key: KeyType, cost g: Int) {
        backing.setObject(obj, forKey: key, cost: g)
      }

      open func removeObject(forKey key: KeyType) {
        backing.removeObject(forKey: key)
      }

      open func removeAllObjects() {
        backing.removeAllObjects()
      }
    }
  #endif
#endif
