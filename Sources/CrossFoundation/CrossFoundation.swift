@_exported import Foundation
@_exported import CoreFoundation
@_exported import CoreServices
@_exported import ApplicationServices
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
  import WinSDK
  import ucrt
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

  #if os(Windows) || CROSS_SWIFTUI_HARMONY
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

    public init(_ nsStr: NSAttributedString) {
      self.init(nsStr.string)
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

    extension Pipe {
      /// Creates stdin/stdout pipe pairs for a child `Process` where ONLY the child's
      /// two ends are inheritable (`HANDLE_FLAG_INHERIT`), preventing sibling processes
      /// spawned later with `bInheritHandles = TRUE` from leaking the parent's pipe ends.
      public static func _makeChildStdioPipes() throws -> (
        childInput: FileHandle,
        parentWriting: FileHandle,
        parentReading: FileHandle,
        childOutput: FileHandle
      ) {
        var sa = SECURITY_ATTRIBUTES(
          nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
          lpSecurityDescriptor: nil,
          bInheritHandle: true
        )
        var inRead: HANDLE?
        var inWrite: HANDLE?
        guard CreatePipe(&inRead, &inWrite, &sa, 0),
          let validInRead = inRead, let validInWrite = inWrite
        else {
          throw CocoaError(.fileReadUnknown)
        }
        var outRead: HANDLE?
        var outWrite: HANDLE?
        guard CreatePipe(&outRead, &outWrite, &sa, 0),
          let validOutRead = outRead, let validOutWrite = outWrite
        else {
          CloseHandle(validInRead)
          CloseHandle(validInWrite)
          throw CocoaError(.fileReadUnknown)
        }
        _ = SetHandleInformation(validInWrite, DWORD(HANDLE_FLAG_INHERIT), 0)
        _ = SetHandleInformation(validOutRead, DWORD(HANDLE_FLAG_INHERIT), 0)

        let inReadFd = _open_osfhandle(intptr_t(bitPattern: validInRead), _O_RDONLY | _O_BINARY)
        let inWriteFd = _open_osfhandle(intptr_t(bitPattern: validInWrite), _O_WRONLY | _O_BINARY)
        let outReadFd = _open_osfhandle(intptr_t(bitPattern: validOutRead), _O_RDONLY | _O_BINARY)
        let outWriteFd = _open_osfhandle(intptr_t(bitPattern: validOutWrite), _O_WRONLY | _O_BINARY)
        guard inReadFd >= 0, inWriteFd >= 0, outReadFd >= 0, outWriteFd >= 0 else {
          if inReadFd >= 0 { _close(inReadFd) } else { CloseHandle(validInRead) }
          if inWriteFd >= 0 { _close(inWriteFd) } else { CloseHandle(validInWrite) }
          if outReadFd >= 0 { _close(outReadFd) } else { CloseHandle(validOutRead) }
          if outWriteFd >= 0 { _close(outWriteFd) } else { CloseHandle(validOutWrite) }
          throw CocoaError(.fileReadUnknown)
        }
        return (
          childInput: FileHandle(fileDescriptor: inReadFd, closeOnDealloc: true),
          parentWriting: FileHandle(fileDescriptor: inWriteFd, closeOnDealloc: true),
          parentReading: FileHandle(fileDescriptor: outReadFd, closeOnDealloc: true),
          childOutput: FileHandle(fileDescriptor: outWriteFd, closeOnDealloc: true)
        )
      }
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

  #if os(Windows) || CROSS_SWIFTUI_HARMONY
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

  // MARK: - Localization & UserDefaults Domain Helpers on Non-Darwin

  extension Locale {
    public static var crossSystemPreferredLanguages: [String] {
      #if os(Windows)
        if let raw = cak_preferred_ui_languages_newline() {
          defer { cak_free(raw) }
          let list = String(cString: raw)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
          if !list.isEmpty {
            return list
          }
        }
      #endif
      var languages = Locale.preferredLanguages
      if let hostLang = XCStringsCatalog.shared.preferredLanguage, !hostLang.isEmpty {
        if !languages.contains(hostLang) {
          languages.insert(hostLang, at: 0)
        }
      }
      return languages
    }
  }

  extension Bundle {
    public static func crossPreferredLocalizations(
      from possibleLocalizations: [String],
      forPreferences preferencesArray: [String]?
    ) -> [String] {
      if XCStringsCatalog.shared.systemLanguagesProvider == nil {
        XCStringsCatalog.shared.systemLanguagesProvider = { Locale.crossSystemPreferredLanguages }
      }
      return XCStringsCatalog.preferredLocalizations(
        from: possibleLocalizations,
        forPreferences: preferencesArray
      )
    }

    public var crossPreferredLocalizations: [String] {
      if XCStringsCatalog.shared.systemLanguagesProvider == nil {
        XCStringsCatalog.shared.systemLanguagesProvider = { Locale.crossSystemPreferredLanguages }
      }
      if self == Bundle.main {
        return [XCStringsCatalog.shared.activeLaunchLanguage]
      }
      let locs = self.localizations.isEmpty ? XCStringsCatalog.shared.localizations : self.localizations
      return Self.crossPreferredLocalizations(from: locs, forPreferences: nil)
    }
  }

  extension UserDefaults {
    public func crossStringArray(inPersistentDomain domainName: String, forKey key: String) -> [String]? {
      func extract(from domain: [String: Any]?) -> [String]? {
        guard let raw = domain?[key] else { return nil }
        if let arr = raw as? [String], !arr.isEmpty {
          return arr
        }
        if let arr = raw as? [Any] {
          let strs = arr.compactMap { $0 as? String }
          if !strs.isEmpty { return strs }
        }
        return nil
      }
      if !domainName.isEmpty, let found = extract(from: persistentDomain(forName: domainName)) {
        return found
      }
      let procName = ProcessInfo.processInfo.processName
      if !procName.isEmpty, procName != domainName,
        let found = extract(from: persistentDomain(forName: procName))
      {
        return found
      }
      return nil
    }
  }

  // MARK: - os_unfair_lock & Objective-C Associated Objects Shims

  public struct os_unfair_lock: @unchecked Sendable {
    public var _os_unfair_lock_opaque: UInt32 = 0
    public init() {}
  }

  public typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock>

  private final class _UnfairLockTable: @unchecked Sendable {
    static let shared = _UnfairLockTable()
    private let tableLock = NSLock()
    private var locks: [UnsafeMutableRawPointer: NSLock] = [:]

    func lock(for ptr: UnsafeMutableRawPointer) -> NSLock {
      tableLock.lock()
      defer { tableLock.unlock() }
      if let existing = locks[ptr] { return existing }
      let created = NSLock()
      locks[ptr] = created
      return created
    }
  }

  public func os_unfair_lock_lock(_ lock: os_unfair_lock_t) {
    _UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).lock()
  }

  public func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) {
    _UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).unlock()
  }

  public func os_unfair_lock_trylock(_ lock: os_unfair_lock_t) -> Bool {
    _UnfairLockTable.shared.lock(for: UnsafeMutableRawPointer(lock)).try()
  }

  public enum objc_AssociationPolicy: UInt, Sendable {
    case OBJC_ASSOCIATION_ASSIGN = 0
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    case OBJC_ASSOCIATION_RETAIN = 0o1401
    case OBJC_ASSOCIATION_COPY = 0o1403
  }

  private final class _AssociatedObjectsStore: @unchecked Sendable {
    static let shared = _AssociatedObjectsStore()
    private let lock = NSLock()
    private var table: [ObjectIdentifier: [UnsafeRawPointer: Any]] = [:]

    func get(_ object: Any, key: UnsafeRawPointer) -> Any? {
      let id = ObjectIdentifier(object as AnyObject)
      lock.lock()
      defer { lock.unlock() }
      return table[id]?[key]
    }

    func set(_ object: Any, key: UnsafeRawPointer, value: Any?) {
      let id = ObjectIdentifier(object as AnyObject)
      lock.lock()
      defer { lock.unlock() }
      if let value {
        var dict = table[id] ?? [:]
        dict[key] = value
        table[id] = dict
      } else {
        table[id]?.removeValue(forKey: key)
        if table[id]?.isEmpty == true {
          table.removeValue(forKey: id)
        }
      }
    }
  }

  public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? {
    _AssociatedObjectsStore.shared.get(object, key: key)
  }

  public func objc_setAssociatedObject(
    _ object: Any,
    _ key: UnsafeRawPointer,
    _ value: Any?,
    _ policy: objc_AssociationPolicy
  ) {
    _AssociatedObjectsStore.shared.set(object, key: key, value: value)
  }

  // MARK: - Key-Value Observing (KVO) Compatibility Shim

  public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let new = NSKeyValueObservingOptions(rawValue: 0x01)
    public static let old = NSKeyValueObservingOptions(rawValue: 0x02)
    public static let initial = NSKeyValueObservingOptions(rawValue: 0x04)
    public static let prior = NSKeyValueObservingOptions(rawValue: 0x08)
  }

  public enum NSKeyValueChange: UInt, Sendable {
    case setting = 1
    case insertion = 2
    case removal = 3
    case replacement = 4
  }

  public struct NSKeyValueChangeKey: Hashable, Equatable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let kindKey = NSKeyValueChangeKey(rawValue: "kind")
    public static let newKey = NSKeyValueChangeKey(rawValue: "new")
    public static let oldKey = NSKeyValueChangeKey(rawValue: "old")
    public static let indexesKey = NSKeyValueChangeKey(rawValue: "indexes")
    public static let notificationIsPriorKey = NSKeyValueChangeKey(rawValue: "notificationIsPrior")
  }

  public struct NSKeyValueObservedChange<Value> {
    public let kind: NSKeyValueChange
    public let newValue: Value?
    public let oldValue: Value?
    public let indexes: IndexSet?
    public let isPrior: Bool

    public init(
      kind: NSKeyValueChange = .setting,
      newValue: Value? = nil,
      oldValue: Value? = nil,
      indexes: IndexSet? = nil,
      isPrior: Bool = false
    ) {
      self.kind = kind
      self.newValue = newValue
      self.oldValue = oldValue
      self.indexes = indexes
      self.isPrior = isPrior
    }
  }

  public final class NSKeyValueObservation: NSObject, @unchecked Sendable {
    private var invalidator: (() -> Void)?

    public init(_ cancel: @escaping () -> Void = {}) {
      self.invalidator = cancel
      super.init()
    }

    public func invalidate() {
      invalidator?()
      invalidator = nil
    }

    deinit {
      invalidate()
    }
  }

  open class CrossKVOObject: NSObject, @unchecked Sendable {
    open func observeValue(
      forKeyPath keyPath: String?,
      of object: Any?,
      change: [NSKeyValueChangeKey: Any]?,
      context: UnsafeMutableRawPointer?
    ) {}
  }

  private final class _UserDefaultsKVOHub: @unchecked Sendable {
    static let shared = _UserDefaultsKVOHub()

    private struct Entry {
      let id: Foundation.UUID
      weak var suite: UserDefaults?
      weak var observer: NSObject?
      let keyPath: String
      let options: NSKeyValueObservingOptions
      let context: UnsafeMutableRawPointer?
      var lastValue: Any?
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var isListening = false

    private func ensureListeningLocked() {
      guard !isListening else { return }
      isListening = true
      _ = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.handleDidChange()
      }
    }

    func add(
      suite: UserDefaults,
      observer: NSObject,
      keyPath: String,
      options: NSKeyValueObservingOptions,
      context: UnsafeMutableRawPointer?
    ) {
      let current = suite.object(forKey: keyPath)
      lock.lock()
      ensureListeningLocked()
      entries.append(Entry(
        id: Foundation.UUID(),
        suite: suite,
        observer: observer,
        keyPath: keyPath,
        options: options,
        context: context,
        lastValue: current
      ))
      lock.unlock()

      if options.contains(.initial) {
        var change: [NSKeyValueChangeKey: Any] = [
          .kindKey: NSKeyValueChange.setting.rawValue
        ]
        if options.contains(.new) {
          change[.newKey] = current ?? NSNull()
        }
        (observer as? CrossKVOObject)?.observeValue(
          forKeyPath: keyPath,
          of: suite,
          change: change,
          context: context
        )
      }
    }

    func remove(
      suite: UserDefaults,
      observer: NSObject,
      keyPath: String,
      context: UnsafeMutableRawPointer? = nil,
      matchContext: Bool = false
    ) {
      lock.lock()
      entries.removeAll { entry in
        guard let s = entry.suite, let o = entry.observer else { return true }
        let matchesObj = (s === suite) && (o === observer) && entry.keyPath == keyPath
        if !matchesObj { return false }
        return !matchContext || entry.context == context
      }
      lock.unlock()
    }

    private static func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
      if a == nil && b == nil { return true }
      guard let a, let b else { return false }
      if let x = a as? NSObject, let y = b as? NSObject {
        return x.isEqual(y)
      }
      return String(describing: a) == String(describing: b)
    }

    private func handleDidChange() {
      var deliveries: [(CrossKVOObject, String, UserDefaults, [NSKeyValueChangeKey: Any], UnsafeMutableRawPointer?)] = []
      lock.lock()
      entries.removeAll { $0.suite == nil || $0.observer == nil }
      for i in entries.indices {
        guard let suite = entries[i].suite, let obs = entries[i].observer else { continue }
        let keyPath = entries[i].keyPath
        let newVal = suite.object(forKey: keyPath)
        let oldVal = entries[i].lastValue
        if !Self.valuesEqual(oldVal, newVal) {
          entries[i].lastValue = newVal
          if let kvoObs = obs as? CrossKVOObject {
            var change: [NSKeyValueChangeKey: Any] = [
              .kindKey: NSKeyValueChange.setting.rawValue
            ]
            if entries[i].options.contains(.old) {
              change[.oldKey] = oldVal ?? NSNull()
            }
            if entries[i].options.contains(.new) {
              change[.newKey] = newVal ?? NSNull()
            }
            deliveries.append((kvoObs, keyPath, suite, change, entries[i].context))
          }
        }
      }
      lock.unlock()

      for (obs, keyPath, suite, change, ctx) in deliveries {
        obs.observeValue(forKeyPath: keyPath, of: suite, change: change, context: ctx)
      }
    }
  }

  public protocol _KeyValueCodingAndObserving {}
  extension NSObject: _KeyValueCodingAndObserving {}

  public extension _KeyValueCodingAndObserving where Self: NSObject {
    func observe<Value>(
      _ keyPath: KeyPath<Self, Value>,
      options: NSKeyValueObservingOptions = [],
      changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
      if options.contains(.initial) {
        let val = self[keyPath: keyPath]
        let change = NSKeyValueObservedChange<Value>(
          kind: .setting,
          newValue: options.contains(.new) ? val : nil,
          oldValue: nil
        )
        changeHandler(self, change)
      }
      return NSKeyValueObservation()
    }
  }

  public extension NSObject {
    func addObserver(
      _ observer: NSObject,
      forKeyPath keyPath: String,
      options: NSKeyValueObservingOptions = [],
      context: UnsafeMutableRawPointer?
    ) {
      if let defaults = self as? UserDefaults {
        _UserDefaultsKVOHub.shared.add(
          suite: defaults,
          observer: observer,
          keyPath: keyPath,
          options: options,
          context: context
        )
      }
    }

    func removeObserver(
      _ observer: NSObject,
      forKeyPath keyPath: String,
      context: UnsafeMutableRawPointer?
    ) {
      if let defaults = self as? UserDefaults {
        _UserDefaultsKVOHub.shared.remove(
          suite: defaults,
          observer: observer,
          keyPath: keyPath,
          context: context,
          matchContext: true
        )
      }
    }

    func removeObserver(_ observer: NSObject, forKeyPath keyPath: String) {
      if let defaults = self as? UserDefaults {
        _UserDefaultsKVOHub.shared.remove(
          suite: defaults,
          observer: observer,
          keyPath: keyPath
        )
      }
    }
  }

  public extension Data.WritingOptions {
    static let completeFileProtection: Data.WritingOptions = []
    static let completeFileProtectionUnlessOpen: Data.WritingOptions = []
    static let completeFileProtectionUntilFirstUserAuthentication: Data.WritingOptions = []
    static let noFileProtection: Data.WritingOptions = []
  }

  // MARK: - DistributedNotificationCenter & Carbon TIS / CGKeyCode Shims

  public typealias CGKeyCode = CoreGraphics.CGKeyCode

  open class DistributedNotificationCenter: NotificationCenter, @unchecked Sendable {
    public enum SuspensionBehavior: UInt, Sendable {
      case drop = 1
      case coalesce = 2
      case hold = 3
      case deliverImmediately = 4
    }

    private static let sharedDistributed = DistributedNotificationCenter()

    public static func `default`() -> DistributedNotificationCenter {
      sharedDistributed
    }

    public func addObserver(
      _ observer: Any,
      selector aSelector: Selector,
      name aName: NSNotification.Name?,
      object anObject: String?,
      suspensionBehavior: SuspensionBehavior = .coalesce
    ) {}
  }

  // MARK: - NSUbiquitousKeyValueStore & dyld Shims

  public let NSUbiquitousKeyValueStoreChangeReasonKey: String = "NSUbiquitousKeyValueStoreChangeReasonKey"
  public let NSUbiquitousKeyValueStoreChangedKeysKey: String = "NSUbiquitousKeyValueStoreChangedKeysKey"

  open class NSUbiquitousKeyValueStore: NSObject, @unchecked Sendable {
    public static let `default` = NSUbiquitousKeyValueStore()
    public static let didChangeExternallyNotification = Notification.Name("NSUbiquitousKeyValueStoreDidChangeExternallyNotification")

    private let lock = NSLock()
    private var values: [String: Any] = [:]

    open var dictionaryRepresentation: [String: Any] {
      lock.lock()
      defer { lock.unlock() }
      return values
    }

    open func object(forKey aKey: String) -> Any? {
      lock.lock()
      defer { lock.unlock() }
      return values[aKey]
    }

    open func set(_ anObject: Any?, forKey aKey: String) {
      lock.lock()
      if let anObject {
        values[aKey] = anObject
      } else {
        values.removeValue(forKey: aKey)
      }
      lock.unlock()
    }

    open func removeObject(forKey aKey: String) {
      lock.lock()
      values.removeValue(forKey: aKey)
      lock.unlock()
    }

    open func string(forKey aKey: String) -> String? { object(forKey: aKey) as? String }
    open func array(forKey aKey: String) -> [Any]? { object(forKey: aKey) as? [Any] }
    open func dictionary(forKey aKey: String) -> [String: Any]? { object(forKey: aKey) as? [String: Any] }
    open func data(forKey aKey: String) -> Data? { object(forKey: aKey) as? Data }
    open func longLong(forKey aKey: String) -> Int64 { (object(forKey: aKey) as? NSNumber)?.int64Value ?? 0 }
    open func double(forKey aKey: String) -> Double { (object(forKey: aKey) as? NSNumber)?.doubleValue ?? 0 }
    open func bool(forKey aKey: String) -> Bool { (object(forKey: aKey) as? NSNumber)?.boolValue ?? false }

    open func set(_ aString: String?, forKey aKey: String) { set(aString as Any?, forKey: aKey) }
    open func set(_ aData: Data?, forKey aKey: String) { set(aData as Any?, forKey: aKey) }
    open func set(_ anArray: [Any]?, forKey aKey: String) { set(anArray as Any?, forKey: aKey) }
    open func set(_ aDictionary: [String: Any]?, forKey aKey: String) { set(aDictionary as Any?, forKey: aKey) }
    open func set(_ value: Int64, forKey aKey: String) { set(NSNumber(value: value), forKey: aKey) }
    open func set(_ value: Double, forKey aKey: String) { set(NSNumber(value: value), forKey: aKey) }
    open func set(_ value: Bool, forKey aKey: String) { set(NSNumber(value: value), forKey: aKey) }

    @discardableResult
    open func synchronize() -> Bool { true }
  }

  public func _dyld_image_count() -> UInt32 { 0 }
  public func _dyld_get_image_name(_ imageIndex: UInt32) -> UnsafePointer<CChar>? { nil }
  public func _dyld_get_image_header(_ imageIndex: UInt32) -> UnsafeRawPointer? { nil }

  // MARK: - URL Standard Directories, CustomLocalizedStringResourceConvertible, Timer & Undo Notifications

  public protocol CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { get }
  }

  public extension URL {
    static var applicationSupportDirectory: URL {
      #if os(Windows)
        if let appData = ProcessInfo.processInfo.environment["APPDATA"], !appData.isEmpty {
          return URL(fileURLWithPath: appData, isDirectory: true)
        }
      #endif
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("AppData/Roaming", isDirectory: true)
    }

    static var documentsDirectory: URL {
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
    }

    func startAccessingSecurityScopedResource() -> Bool { true }
    func stopAccessingSecurityScopedResource() {}
  }

  public extension Notification.Name {
    static let NSUndoManagerDidUndoChange = Notification.Name("NSUndoManagerDidUndoChangeNotification")
    static let NSUndoManagerDidRedoChange = Notification.Name("NSUndoManagerDidRedoChangeNotification")
  }

  public extension Timer {
    @discardableResult
    class func scheduledTimer(
      timeInterval ti: TimeInterval,
      target aTarget: Any,
      selector aSelector: Selector,
      userInfo: Any?,
      repeats yesOrNo: Bool
    ) -> Timer {
      Timer.scheduledTimer(withTimeInterval: ti, repeats: yesOrNo) { _ in }
    }
  }

  public enum NSItemProviderRepresentationVisibility: Int, Sendable {
    case all = 0
    case team = 1
    case group = 2
    case ownProcess = 3
  }

  public extension NSItemProvider {
    func registerDataRepresentation(
      forTypeIdentifier typeIdentifier: String,
      visibility: NSItemProviderRepresentationVisibility,
      loadHandler: @escaping (@escaping (Data?, (any Error)?) -> Void) -> Progress?
    ) {}
  }
#endif
