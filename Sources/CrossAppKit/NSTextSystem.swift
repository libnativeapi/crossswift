import Foundation

public struct NSAccessibility {
  public struct Role: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let unknown = Role(rawValue: "AXUnknown")
    public static let button = Role(rawValue: "AXButton")
    public static let image = Role(rawValue: "AXImage")
    public static let staticText = Role(rawValue: "AXStaticText")
    public static let textField = Role(rawValue: "AXTextField")
    public static let textArea = Role(rawValue: "AXTextArea")
    public static let group = Role(rawValue: "AXGroup")
  }
}

public enum NSWritingToolsBehavior: Int, Sendable {
  case none = -1
  case `default` = 0
  case complete = 1
  case limited = 2
}

public enum NSFocusRingType: UInt, Sendable {
  case `default` = 0
  case none = 1
  case exterior = 2
}

public enum NSBorderType: UInt, Sendable {
  case noBorder = 0
  case lineBorder = 1
  case bezelBorder = 2
  case grooveBorder = 3
}

@MainActor
open class NSTextAttachmentCell: NSCell {
  private var accessibilityRoleValue: NSAccessibility.Role = .unknown
  private var accessibilityLabelValue: String?

  public override init() {
    super.init()
  }

  public required init(coder: NSCoder) {
    super.init()
  }

  public func setAccessibilityRole(_ role: NSAccessibility.Role) {
    accessibilityRoleValue = role
  }

  public func setAccessibilityLabel(_ label: String?) {
    accessibilityLabelValue = label
  }

  open func cellSize() -> NSSize { .zero }
  open func cellBaselineOffset() -> NSPoint { .zero }
  open func cellFrame(
    for textContainer: NSTextContainer,
    proposedLineFragment lineFrag: NSRect,
    glyphPosition position: NSPoint,
    characterIndex charIndex: Int
  ) -> NSRect {
    NSRect(origin: .zero, size: cellSize())
  }
  open func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
  open func wantsToTrackMouse() -> Bool { false }
}

#if !os(macOS)
  open class NSTextAttachment: NSObject, @unchecked Sendable {
    public var attachmentCell: NSTextAttachmentCell?
    public var image: NSImage?
    public var bounds: CGRect = .zero

    public override init() {
      super.init()
    }
  }
#endif

public struct NSTextStorageEditActions: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let editedAttributes = NSTextStorageEditActions(rawValue: 1 << 0)
  public static let editedCharacters = NSTextStorageEditActions(rawValue: 1 << 1)
}

public protocol NSTextStorageDelegate: NSObjectProtocol {
  func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  )
}

extension NSTextStorageDelegate {
  public func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  ) {}
}

open class NSTextStorage: NSMutableAttributedString {
  public static let didProcessEditingNotification = Notification.Name(
    "NSTextStorageDidProcessEditingNotification"
  )

  private let backing = NSMutableAttributedString(string: "")
  public weak var delegate: (any NSTextStorageDelegate)?
  public private(set) var layoutManagers: [NSLayoutManager] = []
  private var editingDepth: Int = 0

  #if os(macOS)
    public override init() {
      super.init()
    }
  #endif

  public override init(string str: String) {
    super.init(string: str)
    backing.replaceCharacters(in: NSRange(location: 0, length: 0), with: str)
  }

  #if os(macOS)
    public override init(string str: String, attributes attrs: [NSAttributedString.Key: Any]? = nil) {
      super.init()
      backing.setAttributedString(NSAttributedString(string: str, attributes: attrs))
    }

    public override init(attributedString attrStr: NSAttributedString) {
      super.init()
      backing.setAttributedString(attrStr)
    }
  #endif

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  open override var string: String {
    backing.string
  }

  open override var mutableString: NSMutableString {
    NSMutableString(string: backing.string)
  }

  open override func attributes(
    at location: Int,
    effectiveRange range: NSRangePointer?
  ) -> [NSAttributedString.Key: Any] {
    guard location >= 0 && location < backing.length else {
      range?.pointee = NSRange(location: 0, length: 0)
      return [:]
    }
    return backing.attributes(at: location, effectiveRange: range)
  }

  open override func replaceCharacters(in range: NSRange, with str: String) {
    let clampedLoc = max(0, min(range.location, backing.length))
    let clampedLen = max(0, min(range.length, backing.length - clampedLoc))
    let safeRange = NSRange(location: clampedLoc, length: clampedLen)
    let newLen = (str as NSString).length
    let delta = newLen - safeRange.length
    backing.replaceCharacters(in: safeRange, with: str)
    let editedRange = NSRange(location: safeRange.location, length: newLen)
    notifyEdited(.editedCharacters, range: editedRange, changeInLength: delta)
  }

  open override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
    let clampedLoc = max(0, min(range.location, backing.length))
    let clampedLen = max(0, min(range.length, backing.length - clampedLoc))
    let safeRange = NSRange(location: clampedLoc, length: clampedLen)
    guard safeRange.length > 0 || backing.length == 0 else { return }
    if safeRange.length > 0 {
      backing.setAttributes(attrs, range: safeRange)
    }
    notifyEdited(.editedAttributes, range: safeRange, changeInLength: 0)
  }

  open override func beginEditing() {
    editingDepth += 1
  }

  open override func endEditing() {
    editingDepth = max(0, editingDepth - 1)
  }

  public func addLayoutManager(_ aLayoutManager: NSLayoutManager) {
    aLayoutManager.textStorage = self
    layoutManagers.append(aLayoutManager)
  }

  private func notifyEdited(
    _ actions: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int
  ) {
    delegate?.textStorage(self, didProcessEditing: actions, range: range, changeInLength: delta)
    NotificationCenter.default.post(name: Self.didProcessEditingNotification, object: self)
  }
}

open class NSTextContainer: NSObject {
  public var size: NSSize
  public var widthTracksTextView: Bool = false
  public var heightTracksTextView: Bool = false
  public var lineFragmentPadding: CGFloat = 5.0
  public var maximumNumberOfLines: Int = 0
  public var lineBreakMode: NSLineBreakMode = .byWordWrapping
  public weak var layoutManager: NSLayoutManager?

  public init(size: NSSize = NSSize(width: 1e7, height: 1e7)) {
    self.size = size
    super.init()
  }
}

open class NSLayoutManager: NSObject {
  public weak var textStorage: NSTextStorage?
  public private(set) var textContainers: [NSTextContainer] = []

  public override init() {
    super.init()
  }

  public func addTextContainer(_ container: NSTextContainer) {
    container.layoutManager = self
    textContainers.append(container)
  }

  public func ensureLayout(for container: NSTextContainer) {}

  public func usedRect(for container: NSTextContainer) -> NSRect {
    guard let storage = textStorage, storage.length > 0 else { return .zero }
    let font = (storage.attribute(NSAttributedString.Key("NSFont"), at: 0, effectiveRange: nil) as? NSFont)
      ?? .systemFont(ofSize: NSFont.systemFontSize)
    let lineH = max(16, ceil(font.ascender - font.descender + font.leading))
    let availW = container.size.width.isFinite && container.size.width > 0
      ? max(1, container.size.width - container.lineFragmentPadding * 2)
      : 1e6
    let charW = max(5, font.pointSize * 0.56)
    var totalLines: CGFloat = 0
    var maxLineW: CGFloat = 0
    for para in storage.string.split(separator: "\n", omittingEmptySubsequences: false) {
      let paraW = CGFloat(para.count) * charW
      maxLineW = max(maxLineW, min(paraW, availW))
      let wrapped = paraW > 0 ? max(1, ceil(paraW / availW)) : 1
      totalLines += wrapped
    }
    return NSRect(x: 0, y: 0, width: maxLineW, height: totalLines * lineH)
  }

  public func glyphRange(
    forCharacterRange charRange: NSRange,
    actualCharacterRange actualCharRange: NSRangePointer?
  ) -> NSRange {
    actualCharRange?.pointee = charRange
    return charRange
  }

  public func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> NSRect {
    usedRect(for: container)
  }

  #if !os(macOS)
    public func boundsRect(for block: NSTextBlock, glyphRange: NSRange) -> NSRect {
      guard let first = textContainers.first else { return .zero }
      return NSRect(x: 0, y: 0, width: max(0, first.size.width), height: 40)
    }
  #endif
}

public protocol NSTextLocation: AnyObject {
  func compare(_ location: any NSTextLocation) -> ComparisonResult
}

public final class _CrossTextLocation: NSObject, NSTextLocation {
  public let offset: Int
  public init(_ offset: Int) { self.offset = offset }
  public func compare(_ location: any NSTextLocation) -> ComparisonResult {
    let other = (location as? _CrossTextLocation)?.offset ?? 0
    if offset < other { return .orderedAscending }
    if offset > other { return .orderedDescending }
    return .orderedSame
  }
}

open class NSTextRange: NSObject {
  public let location: any NSTextLocation
  public let endLocation: any NSTextLocation

  public var isEmpty: Bool {
    location.compare(endLocation) == .orderedSame
  }

  public init?(location: any NSTextLocation, end: (any NSTextLocation)?) {
    let resolvedEnd = end ?? location
    if location.compare(resolvedEnd) == .orderedDescending { return nil }
    self.location = location
    self.endLocation = resolvedEnd
    super.init()
  }

  public convenience init(location: any NSTextLocation) {
    self.init(location: location, end: location)!
  }
}

open class NSTextElement: NSObject {
  public var elementRange: NSTextRange?
  public override init() { super.init() }
}

open class NSTextParagraph: NSTextElement {
  public let attributedString: NSAttributedString
  public init(attributedString: NSAttributedString = NSAttributedString(string: "")) {
    self.attributedString = attributedString
    super.init()
  }
}

open class NSTextLineFragment: NSObject {
  public var typographicBounds: CGRect = CGRect(x: 0, y: 0, width: 100, height: 18)
  public var glyphOrigin: CGPoint = CGPoint(x: 0, y: 14)
}

open class NSTextLayoutFragment: NSObject {
  public weak var textLayoutManager: NSTextLayoutManager?
  public let textElement: NSTextElement?
  public let rangeInElement: NSTextRange
  public var layoutFragmentFrame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 20)
  open var renderingSurfaceBounds: CGRect { layoutFragmentFrame }
  public var textLineFragments: [NSTextLineFragment] = [NSTextLineFragment()]

  public init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
    self.textElement = textElement
    self.rangeInElement = rangeInElement ?? NSTextRange(location: _CrossTextLocation(0))
    super.init()
  }

  public required init?(coder: NSCoder) {
    nil
  }

  open func draw(at point: CGPoint, in context: CGContext) {}
}

@MainActor
public protocol NSTextLayoutManagerDelegate: NSObjectProtocol {
  func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment
}

extension NSTextLayoutManagerDelegate {
  public func textLayoutManager(
    _ textLayoutManager: NSTextLayoutManager,
    textLayoutFragmentFor location: any NSTextLocation,
    in textElement: NSTextElement
  ) -> NSTextLayoutFragment {
    NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
  }
}

open class NSTextContentStorage: NSObject {
  public weak var textStorage: NSTextStorage?

  public var documentRange: NSTextRange {
    let len = textStorage?.length ?? 0
    return NSTextRange(location: _CrossTextLocation(0), end: _CrossTextLocation(len))
      ?? NSTextRange(location: _CrossTextLocation(0))
  }

  public func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
    let base = (location as? _CrossTextLocation)?.offset ?? 0
    let target = base + offset
    let len = textStorage?.length ?? 0
    guard target >= 0 && target <= len else { return nil }
    return _CrossTextLocation(target)
  }

  public func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
    let a = (from as? _CrossTextLocation)?.offset ?? 0
    let b = (to as? _CrossTextLocation)?.offset ?? 0
    return b - a
  }
}

open class NSTextLayoutManager: NSObject {
  public struct SegmentType: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let standard = SegmentType(rawValue: 0)
    public static let selection = SegmentType(rawValue: 1)
    public static let highlight = SegmentType(rawValue: 2)
  }

  public struct SegmentOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let rangeNotRequired = SegmentOptions(rawValue: 1 << 0)
    public static let middleFragmentsExcluded = SegmentOptions(rawValue: 1 << 1)
    public static let headSegmentExtended = SegmentOptions(rawValue: 1 << 2)
    public static let tailSegmentExtended = SegmentOptions(rawValue: 1 << 3)
    public static let upstreamAffinity = SegmentOptions(rawValue: 1 << 4)
  }

  public weak var delegate: (any NSTextLayoutManagerDelegate)?
  public weak var textContentStorage: NSTextContentStorage?
  public weak var textContainer: NSTextContainer?

  public var documentRange: NSTextRange {
    textContentStorage?.documentRange ?? NSTextRange(location: _CrossTextLocation(0))
  }

  @discardableResult
  public func enumerateTextLayoutFragments(
    from location: (any NSTextLocation)?,
    options: NSTextLayoutFragment.EnumerationOptions = [],
    using block: (NSTextLayoutFragment) -> Bool
  ) -> (any NSTextLocation)? {
    guard let storage = textContentStorage?.textStorage else { return nil }
    let font = (storage.length > 0 ? storage.attribute(NSAttributedString.Key("NSFont"), at: 0, effectiveRange: nil) as? NSFont : nil)
      ?? .systemFont(ofSize: NSFont.systemFontSize)
    let lineH = max(18, ceil(font.ascender - font.descender + font.leading))
    let lines = max(1, storage.string.split(separator: "\n", omittingEmptySubsequences: false).count)
    let elem = NSTextParagraph(attributedString: storage)
    let frag = NSTextLayoutFragment(textElement: elem, range: documentRange)
    frag.layoutFragmentFrame = CGRect(x: 0, y: 0, width: max(100, textContainer?.size.width ?? 200), height: CGFloat(lines) * lineH)
    _ = block(frag)
    return documentRange.endLocation
  }

  public func textLayoutFragment(for position: CGPoint) -> NSTextLayoutFragment? {
    nil
  }

  public func invalidateLayout(for range: NSTextRange) {}

  public func enumerateTextSegments(
    in textRange: NSTextRange,
    type: SegmentType,
    options: SegmentOptions = [],
    using block: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool
  ) {
    if let container = textContainer {
      _ = block(textRange, CGRect(x: 0, y: 0, width: 8, height: 16), 13, container)
    }
  }
}

extension NSTextLayoutFragment {
  public struct EnumerationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let reverse = EnumerationOptions(rawValue: 1 << 0)
    public static let estimatesSize = EnumerationOptions(rawValue: 1 << 1)
    public static let ensuresLayout = EnumerationOptions(rawValue: 1 << 2)
    public static let ensuresExtraLineFragment = EnumerationOptions(rawValue: 1 << 3)
  }
}

open class NSTextFinder: NSObject {
  public enum Action: Int, Sendable {
    case showFindInterface = 1
    case nextMatch = 2
    case previousMatch = 3
    case replaceAll = 4
    case replace = 5
    case replaceAndFind = 6
    case setSearchString = 7
    case replaceAllInSelection = 8
    case selectAll = 9
    case selectAllInSelection = 10
    case hideFindInterface = 11
    case showReplaceInterface = 12
    case hideReplaceInterface = 13
  }
}

open class NSText: NSView {
  public static let didChangeNotification = Notification.Name("NSTextDidChangeNotification")
  public static let didBeginEditingNotification = Notification.Name("NSTextDidBeginEditingNotification")
  public static let didEndEditingNotification = Notification.Name("NSTextDidEndEditingNotification")

  open var isFieldEditor: Bool = false
}

#if !os(macOS)
  open class UndoManager: NSObject {
    public static let didUndoChangeNotification = Notification.Name("NSUndoManagerDidUndoChangeNotification")
    public static let didRedoChangeNotification = Notification.Name("NSUndoManagerDidRedoChangeNotification")

    public struct DidUndoChangeMessage: NotificationCenter.MainActorMessage {
      public typealias Subject = UndoManager
      public static var name: Notification.Name { UndoManager.didUndoChangeNotification }
      public init() {}
      @MainActor public static func makeMessage(_ notification: borrowing Notification) -> Self? { .init() }
      @MainActor public static func makeNotification(_ message: Self, object: UndoManager?) -> Notification {
        Notification(name: name, object: object)
      }
    }

    public struct DidRedoChangeMessage: NotificationCenter.MainActorMessage {
      public typealias Subject = UndoManager
      public static var name: Notification.Name { UndoManager.didRedoChangeNotification }
      public init() {}
      @MainActor public static func makeMessage(_ notification: borrowing Notification) -> Self? { .init() }
      @MainActor public static func makeNotification(_ message: Self, object: UndoManager?) -> Notification {
        Notification(name: name, object: object)
      }
    }

    private var undoStack: [() -> Void] = []
    private var redoStack: [() -> Void] = []
    private var isUndoingFlag = false
    private var isRedoingFlag = false

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isUndoing: Bool { isUndoingFlag }
    public var isRedoing: Bool { isRedoingFlag }

    public override init() { super.init() }

    public func registerUndo<TargetType: AnyObject>(
      withTarget target: TargetType,
      handler: @escaping (TargetType) -> Void
    ) {
      let action: () -> Void = { [weak target] in
        if let target { handler(target) }
      }
      if isUndoingFlag {
        redoStack.append(action)
      } else {
        if !isRedoingFlag { redoStack.removeAll() }
        undoStack.append(action)
      }
    }

    public func undo() {
      guard let action = undoStack.popLast() else { return }
      isUndoingFlag = true
      action()
      isUndoingFlag = false
      NotificationCenter.default.post(name: Self.didUndoChangeNotification, object: self)
    }

    public func redo() {
      guard let action = redoStack.popLast() else { return }
      isRedoingFlag = true
      action()
      isRedoingFlag = false
      NotificationCenter.default.post(name: Self.didRedoChangeNotification, object: self)
    }

    public func removeAllActions() {
      undoStack.removeAll()
      redoStack.removeAll()
    }
  }

  public struct _UndoDidUndoIdentifier: NotificationCenter.MessageIdentifier {
    public typealias MessageType = UndoManager.DidUndoChangeMessage
    public init() {}
  }

  public struct _UndoDidRedoIdentifier: NotificationCenter.MessageIdentifier {
    public typealias MessageType = UndoManager.DidRedoChangeMessage
    public init() {}
  }

  extension NotificationCenter.MessageIdentifier where Self == _UndoDidUndoIdentifier {
    public static var didUndoChange: Self { .init() }
  }

  extension NotificationCenter.MessageIdentifier where Self == _UndoDidRedoIdentifier {
    public static var didRedoChange: Self { .init() }
  }

  extension NSWorkspace {
    public struct DidTerminateApplicationMessage: NotificationCenter.MainActorMessage {
      public typealias Subject = NSWorkspace
      public static var name: Notification.Name { NSWorkspace.didTerminateApplicationNotification }
      public let application: NSRunningApplication

      @MainActor public static func makeMessage(_ notification: borrowing Notification) -> Self? {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return nil }
        return Self(application: app)
      }

      @MainActor public static func makeNotification(_ message: Self, object: NSWorkspace?) -> Notification {
        Notification(
          name: name,
          object: object,
          userInfo: [NSWorkspace.applicationUserInfoKey: message.application]
        )
      }
    }
  }

  extension NotificationCenter {
    public func notifications(
      named name: Notification.Name,
      object: AnyObject? = nil
    ) -> AsyncStream<Notification> {
      AsyncStream { continuation in
        let token = self.addObserver(forName: name, object: object, queue: nil) { note in
          continuation.yield(note)
        }
        nonisolated(unsafe) let boxToken = token
        let center = self
        continuation.onTermination = { _ in
          center.removeObserver(boxToken)
        }
      }
    }
  }
#endif
