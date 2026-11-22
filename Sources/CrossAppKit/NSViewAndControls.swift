import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

public struct CACornerMask: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let layerMinXMinYCorner = CACornerMask(rawValue: 1 << 0)
  public static let layerMaxXMinYCorner = CACornerMask(rawValue: 1 << 1)
  public static let layerMinXMaxYCorner = CACornerMask(rawValue: 1 << 2)
  public static let layerMaxXMaxYCorner = CACornerMask(rawValue: 1 << 3)
}

public struct CALayerCornerCurve: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let circular = CALayerCornerCurve(rawValue: "circular")
  public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

open class CAAnimation: NSObject, NSCopying {
  public var duration: TimeInterval = 0.25
  public var beginTime: TimeInterval = 0
  public var speed: Float = 1.0
  public var timeOffset: TimeInterval = 0
  public var repeatCount: Float = 0
  public var autoreverses: Bool = false
  public var isRemovedOnCompletion: Bool = true
  public var timingFunction: CAMediaTimingFunction?
  public override init() { super.init() }
  open func copy(with zone: NSZone? = nil) -> Any {
    let c = CAAnimation()
    c.duration = duration
    c.beginTime = beginTime
    c.speed = speed
    c.timeOffset = timeOffset
    c.repeatCount = repeatCount
    c.autoreverses = autoreverses
    c.isRemovedOnCompletion = isRemovedOnCompletion
    c.timingFunction = timingFunction
    return c
  }
}

open class CABasicAnimation: CAAnimation {
  public var keyPath: String?
  public var fromValue: Any?
  public var toValue: Any?
  public var byValue: Any?
  public convenience init(keyPath path: String?) {
    self.init()
    self.keyPath = path
  }
}

open class CASpringAnimation: CABasicAnimation {
  public var mass: CGFloat = 1.0
  public var stiffness: CGFloat = 100.0
  public var damping: CGFloat = 10.0
  public var initialVelocity: CGFloat = 0.0
  public var settlingDuration: TimeInterval { max(0.25, duration) }
}

open class CATransaction: NSObject {
  nonisolated(unsafe) private static var disableActionsStack: [Bool] = []
  nonisolated(unsafe) private static var completionStack: [(() -> Void)?] = []
  nonisolated(unsafe) private static var animationDurationValue: TimeInterval = 0.25

  public static func begin() {
    disableActionsStack.append(false)
    completionStack.append(nil)
  }

  public static func commit() {
    _ = disableActionsStack.popLast()
    if let completion = completionStack.popLast() ?? nil {
      completion()
    }
  }

  public static func flush() {}

  public static func disableActions() -> Bool {
    disableActionsStack.last ?? false
  }

  public static func setDisableActions(_ flag: Bool) {
    if disableActionsStack.isEmpty {
      disableActionsStack.append(flag)
    } else {
      disableActionsStack[disableActionsStack.count - 1] = flag
    }
  }

  public static func animationDuration() -> TimeInterval { animationDurationValue }
  public static func setAnimationDuration(_ dur: TimeInterval) { animationDurationValue = dur }

  public static func completionBlock() -> (() -> Void)? {
    completionStack.last ?? nil
  }

  public static func setCompletionBlock(_ block: (() -> Void)?) {
    if completionStack.isEmpty {
      completionStack.append(block)
    } else {
      completionStack[completionStack.count - 1] = block
    }
  }
}

open class CADisplayLink: NSObject {
  public weak var target: AnyObject?
  public let selector: Selector
  public var isPaused: Bool = false
  public var preferredFramesPerSecond: Int = 60
  public var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
  public var duration: TimeInterval { 1.0 / Double(max(preferredFramesPerSecond, 1)) }
  public var targetTimestamp: TimeInterval { timestamp + duration }

  public init(target: Any, selector sel: Selector) {
    self.target = target as AnyObject
    self.selector = sel
    super.init()
  }

  public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {}
  public func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {}
  public func invalidate() { isPaused = true }
}

open class CALayer: NSObject {
  public var frame: CGRect = .zero {
    didSet {
      bounds.size = frame.size
      position = CGPoint(
        x: frame.origin.x + frame.size.width * anchorPoint.x,
        y: frame.origin.y + frame.size.height * anchorPoint.y
      )
    }
  }
  public var bounds: CGRect = .zero
  public var position: CGPoint = .zero
  public var anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
  public var zPosition: CGFloat = 0
  public var isHidden: Bool = false
  public var contents: Any?
  public var contentsScale: CGFloat = 1.0
  public var cornerRadius: CGFloat = 0
  public var maskedCorners: CACornerMask = [
    .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
  ]
  public var cornerCurve: CALayerCornerCurve = .circular
  public var masksToBounds: Bool = false
  public var borderWidth: CGFloat = 0
  public var shadowOpacity: Float = 0
  public var shadowRadius: CGFloat = 3.0
  public var shadowOffset: CGSize = CGSize(width: 0, height: -3)
  public var shouldRasterize: Bool = false
  public var rasterizationScale: CGFloat = 1.0
  #if !os(macOS)
    public var backgroundColor: CGColor?
    public var borderColor: CGColor?
    public var shadowColor: CGColor?
    public var shadowPath: CGPath?
  #endif
  public var opacity: Float = 1.0
  public private(set) weak var superlayer: CALayer?
  public var sublayers: [CALayer]? = []
  private var animations: [String: CAAnimation] = [:]

  public override init() { super.init() }
  public init(layer: Any) { super.init() }

  public func addSublayer(_ layer: CALayer) {
    layer.removeFromSuperlayer()
    if sublayers == nil { sublayers = [] }
    sublayers?.append(layer)
    layer.superlayer = self
  }

  public func insertSublayer(_ layer: CALayer, at idx: UInt32) {
    layer.removeFromSuperlayer()
    if sublayers == nil { sublayers = [] }
    let i = min(Int(idx), sublayers?.count ?? 0)
    sublayers?.insert(layer, at: i)
    layer.superlayer = self
  }

  public func removeFromSuperlayer() {
    superlayer?.sublayers?.removeAll { $0 === self }
    superlayer = nil
  }

  open func setNeedsDisplay() {}
  open func displayIfNeeded() {}
  open func setNeedsLayout() {}
  open func layoutIfNeeded() { layoutSublayers() }
  open func layoutSublayers() {}

  public func add(_ anim: CAAnimation, forKey key: String?) {
    animations[key ?? UUID().uuidString] = anim
  }
  public func removeAnimation(forKey key: String) {
    animations.removeValue(forKey: key)
  }
  public func removeAllAnimations() {
    animations.removeAll()
  }
  public func animation(forKey key: String) -> CAAnimation? {
    animations[key]
  }
}

open class CAShapeLayer: CALayer {
  public struct FillRule: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = FillRule(rawValue: "non-zero")
    public static let evenOdd = FillRule(rawValue: "even-odd")
  }
  public struct LineCap: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = LineCap(rawValue: "butt")
    public static let round = LineCap(rawValue: "round")
    public static let square = LineCap(rawValue: "square")
  }
  public struct LineJoin: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = LineJoin(rawValue: "miter")
    public static let round = LineJoin(rawValue: "round")
    public static let bevel = LineJoin(rawValue: "bevel")
  }
  #if !os(macOS)
    public var path: CGPath?
    public var fillColor: CGColor?
    public var strokeColor: CGColor?
  #endif
  public var fillRule: FillRule = .nonZero
  public var lineWidth: CGFloat = 1.0
  public var miterLimit: CGFloat = 10.0
  public var lineCap: LineCap = .butt
  public var lineJoin: LineJoin = .miter
  public var strokeStart: CGFloat = 0.0
  public var strokeEnd: CGFloat = 1.0
  public var lineDashPhase: CGFloat = 0.0
  public var lineDashPattern: [NSNumber]?
}

open class CAGradientLayer: CALayer {
  public struct GradientType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let axial = GradientType(rawValue: "axial")
    public static let radial = GradientType(rawValue: "radial")
    public static let conic = GradientType(rawValue: "conic")
  }
  public var colors: [Any]?
  public var locations: [NSNumber]?
  public var startPoint: CGPoint = CGPoint(x: 0.5, y: 0.0)
  public var endPoint: CGPoint = CGPoint(x: 0.5, y: 1.0)
  public var type: GradientType = .axial
}

open class CATextLayer: CALayer {
  public var string: Any?
  public var fontSize: CGFloat = 36.0
  public var isWrapped: Bool = false
  #if !os(macOS)
    public var foregroundColor: CGColor?
  #endif
}

open class NSTrackingArea: NSObject {
  public struct Options: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let mouseEnteredAndExited = Options(rawValue: 0x01)
    public static let mouseMoved = Options(rawValue: 0x02)
    public static let cursorUpdate = Options(rawValue: 0x04)
    public static let activeWhenFirstResponder = Options(rawValue: 0x10)
    public static let activeInKeyWindow = Options(rawValue: 0x20)
    public static let activeInActiveApp = Options(rawValue: 0x40)
    public static let activeAlways = Options(rawValue: 0x80)
    public static let assumeInside = Options(rawValue: 0x100)
    public static let inVisibleRect = Options(rawValue: 0x200)
    public static let enabledDuringMouseDrag = Options(rawValue: 0x400)
  }

  public let rect: NSRect
  public let options: Options
  public weak var owner: AnyObject?
  public let userInfo: [AnyHashable: Any]?

  public init(rect: NSRect, options: Options, owner: Any?, userInfo: [AnyHashable: Any]? = nil) {
    self.rect = rect
    self.options = options
    self.owner = owner as AnyObject?
    self.userInfo = userInfo
    super.init()
  }
}

public protocol NSDraggingInfo: AnyObject {
  var draggingPasteboard: NSPasteboard { get }
  var draggingLocation: NSPoint { get }
  var draggingSourceOperationMask: NSDragOperation { get }
}

@MainActor
public protocol NSDraggingSource: NSObjectProtocol {
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation
  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation)
}

extension NSDraggingSource {
  public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {}
}

public enum NSDraggingContext: Int, Sendable {
  case outsideApplication = 0
  case withinApplication = 1
}

open class NSDraggingSession: NSObject {
  public var animatesToStartingPositionsOnCancelOrFail: Bool = true
}

open class NSDraggingItem: NSObject {
  public let pasteboardWriter: any NSPasteboardWriting
  public var draggingFrame: NSRect = .zero
  public private(set) var draggingContents: Any?
  public init(pasteboardWriter: any NSPasteboardWriting) {
    self.pasteboardWriter = pasteboardWriter
    super.init()
  }
  public func setDraggingFrame(_ frame: NSRect, contents: Any?) {
    self.draggingFrame = frame
    self.draggingContents = contents
  }
}

open class NSView: NSResponder {
  public struct AutoresizingMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let none = AutoresizingMask([])
    public static let minXMargin = AutoresizingMask(rawValue: 1)
    public static let width = AutoresizingMask(rawValue: 2)
    public static let maxXMargin = AutoresizingMask(rawValue: 4)
    public static let minYMargin = AutoresizingMask(rawValue: 8)
    public static let height = AutoresizingMask(rawValue: 16)
    public static let maxYMargin = AutoresizingMask(rawValue: 32)
  }

  public static let noIntrinsicMetric: CGFloat = -1
  public static let frameDidChangeNotification = Notification.Name("NSViewFrameDidChangeNotification")
  public static let boundsDidChangeNotification = Notification.Name("NSViewBoundsDidChangeNotification")

  public var frame: NSRect {
    didSet {
      bounds.size = frame.size
      #if !os(macOS)
        if let nv = ownedNativeView {
          nv.setFrame(NativeAPI.Rectangle(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.size.width),
            height: Double(frame.size.height)
          ))
        }
      #endif
      if oldValue.size != frame.size {
        viewDidChangeFrameSize(from: oldValue.size)
      }
      if postsFrameChangedNotifications {
        NotificationCenter.default.post(name: Self.frameDidChangeNotification, object: self)
      }
    }
  }

  public var bounds: NSRect
  public private(set) var subviews: [NSView] = []
  public private(set) weak var superview: NSView?
  public internal(set) weak var window: NSWindow? {
    didSet {
      for child in subviews { child.window = window }
      viewDidMoveToWindow()
    }
  }

  public var wantsLayer: Bool = false {
    didSet {
      if wantsLayer && layer == nil { layer = CALayer() }
    }
  }
  public var layer: CALayer?
  public var clipsToBounds: Bool = false
  public var isHidden: Bool = false {
    didSet {
      #if !os(macOS)
        ownedNativeView?.setVisible(!isHidden)
      #endif
    }
  }
  public var alphaValue: CGFloat = 1.0
  public var needsDisplay: Bool = false
  public var needsLayout: Bool = false
  public var autoresizingMask: AutoresizingMask = []
  public var translatesAutoresizingMaskIntoConstraints: Bool = true
  public var identifier: NSUserInterfaceItemIdentifier?
  public var postsFrameChangedNotifications: Bool = false
  public var postsBoundsChangedNotifications: Bool = false
  public var toolTip: String?
  public var refusesKeyboardFocus: Bool = false
  public var refusesFirstResponder: Bool = false
  public var focusRingType: NSFocusRingType = .default
  private var accessibilityLabelValue: String?
  private var accessibilityRoleValue: NSAccessibility.Role = .unknown
  public private(set) var trackingAreas: [NSTrackingArea] = []
  public var appearance: NSAppearance?

  public struct AlignmentOptions: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let alignMinXNearest = AlignmentOptions(rawValue: 1 << 8)
    public static let alignMinYNearest = AlignmentOptions(rawValue: 1 << 9)
    public static let alignMaxXNearest = AlignmentOptions(rawValue: 1 << 10)
    public static let alignMaxYNearest = AlignmentOptions(rawValue: 1 << 11)
    public static let alignWidthNearest = AlignmentOptions(rawValue: 1 << 12)
    public static let alignHeightNearest = AlignmentOptions(rawValue: 1 << 13)
    public static let alignAllEdgesNearest: AlignmentOptions = [
      .alignMinXNearest, .alignMinYNearest, .alignMaxXNearest, .alignMaxYNearest,
    ]
  }

  public var effectiveAppearance: NSAppearance {
    appearance ?? superview?.effectiveAppearance ?? window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
  }

  open var isFlipped: Bool { false }
  open var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
  open var intrinsicContentSize: NSSize { NSSize(width: Self.noIntrinsicMetric, height: Self.noIntrinsicMetric) }
  open var fittingSize: NSSize {
    let s = intrinsicContentSize
    return NSSize(width: max(0, s.width), height: max(0, s.height))
  }
  public var visibleRect: NSRect { bounds }
  public var enclosingScrollView: NSScrollView? {
    var cur = superview
    while let v = cur {
      if let sv = v as? NSScrollView { return sv }
      cur = v.superview
    }
    return nil
  }

  #if !os(macOS)
    /// Underlying NativeAPI view when this NSView wraps or creates a real native HWND.
    public var ownedNativeView: NativeAPI.View?
    open func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      if let created = NativeAPI.View.create() {
        created.setLayout(.absolute)
        ownedNativeView = created
        return created
      }
      return nil
    }
  #endif

  public init(frame frameRect: NSRect) {
    self.frame = frameRect
    self.bounds = NSRect(origin: .zero, size: frameRect.size)
    super.init()
  }

  public required override init?(coder: NSCoder) {
    self.frame = .zero
    self.bounds = .zero
    super.init(coder: coder)
  }

  public convenience override init() {
    self.init(frame: .zero)
  }

  open func addSubview(_ view: NSView) {
    guard view !== self else { return }
    view.removeFromSuperview()
    subviews.append(view)
    view.superview = self
    view.nextResponder = self
    view.window = self.window
    #if !os(macOS)
      if let parentNV = ownedNativeView, let childNV = view.ownedNativeView {
        parentNV.addSubview(childNV)
      }
    #endif
    view.viewDidMoveToSuperview()
  }

  open func removeFromSuperview() {
    guard let parent = superview else { return }
    #if !os(macOS)
      if let parentNV = parent.ownedNativeView, let childNV = ownedNativeView {
        _ = parentNV.removeSubview(childNV)
      }
    #endif
    parent.subviews.removeAll { $0 === self }
    superview = nil
    window = nil
    viewDidMoveToSuperview()
  }

  open func viewDidMoveToWindow() {}
  open func viewDidMoveToSuperview() {}
  open func viewDidChangeFrameSize(from oldSize: NSSize) {}
  open func viewDidChangeEffectiveAppearance() {
    for sub in subviews { sub.viewDidChangeEffectiveAppearance() }
  }

  open func setFrameSize(_ newSize: NSSize) {
    frame.size = newSize
  }

  open func setFrameOrigin(_ newOrigin: NSPoint) {
    frame.origin = newOrigin
  }

  open func draw(_ dirtyRect: NSRect) {}
  open func scroll(_ point: NSPoint) {}
  open func scrollToVisible(_ rect: NSRect) -> Bool { false }
  open func layout() {}
  open func layoutSubtreeIfNeeded() {
    layout()
    for sub in subviews { sub.layoutSubtreeIfNeeded() }
  }
  open func applySurfaceContentOffset(x: Double, y: Double) {
    if subviews.count == 1 {
      subviews[0].applySurfaceContentOffset(x: x, y: y)
    }
  }
  open func applyWindowFrameChange(
    contentSize: NSSize,
    envelopeSize: NSSize? = nil,
    contentOffset: NSPoint = .zero,
    display: Bool,
    commitNativeBounds: @escaping () -> Void
  ) -> Bool {
    if subviews.count == 1 {
      return subviews[0].applyWindowFrameChange(
        contentSize: contentSize,
        envelopeSize: envelopeSize,
        contentOffset: contentOffset,
        display: display,
        commitNativeBounds: commitNativeBounds
      )
    }
    return false
  }
  open func invalidateIntrinsicContentSize() {}
  open func resetCursorRects() {}
  public func addCursorRect(_ aRect: NSRect, cursor anObj: NSCursor) {}
  open func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
    true
  }

  public func isDescendant(of view: NSView) -> Bool {
    var cur: NSView? = self
    while let v = cur {
      if v === view { return true }
      cur = v.superview
    }
    return false
  }

  public func backingAlignedRect(_ aRect: NSRect, options: AlignmentOptions = .alignAllEdgesNearest) -> NSRect {
    aRect
  }

  public func setAccessibilityLabel(_ label: String?) {
    accessibilityLabelValue = label
  }

  public func accessibilityLabel() -> String? {
    accessibilityLabelValue
  }

  public func setAccessibilityRole(_ role: NSAccessibility.Role) {
    accessibilityRoleValue = role
  }

  open func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, alphaValue > 0.01, frame.contains(point) else { return nil }
    let local = NSPoint(x: point.x - frame.origin.x, y: point.y - frame.origin.y)
    for child in subviews.reversed() {
      if let hit = child.hitTest(local) { return hit }
    }
    return self
  }

  public func convert(_ point: NSPoint, from view: NSView?) -> NSPoint {
    guard let view else {
      var p = point
      var cur: NSView? = self
      var chain: [NSView] = []
      while let c = cur {
        chain.append(c)
        cur = c.superview
      }
      var parentFlipped = false
      for v in chain.reversed() {
        p.x -= v.frame.origin.x
        p.y -= v.frame.origin.y
        if v.isFlipped != parentFlipped {
          p.y = v.frame.height - p.y
        }
        parentFlipped = v.isFlipped
      }
      return p
    }
    let inWin = view.convert(point, to: nil)
    return convert(inWin, from: nil)
  }

  public func convert(_ point: NSPoint, to view: NSView?) -> NSPoint {
    guard let view else {
      var p = point
      var cur: NSView? = self
      while let c = cur {
        let parentFlipped = c.superview?.isFlipped ?? false
        if c.isFlipped != parentFlipped {
          p.y = c.frame.height - p.y
        }
        p.x += c.frame.origin.x
        p.y += c.frame.origin.y
        cur = c.superview
      }
      return p
    }
    let inWin = convert(point, to: nil)
    return view.convert(inWin, from: nil)
  }

  public func convert(_ rect: NSRect, from view: NSView?) -> NSRect {
    NSRect(origin: convert(rect.origin, from: view), size: rect.size)
  }

  public func convert(_ rect: NSRect, to view: NSView?) -> NSRect {
    NSRect(origin: convert(rect.origin, to: view), size: rect.size)
  }

  public func addTrackingArea(_ trackingArea: NSTrackingArea) {
    trackingAreas.append(trackingArea)
  }

  public func removeTrackingArea(_ trackingArea: NSTrackingArea) {
    trackingAreas.removeAll { $0 === trackingArea }
  }

  open func updateTrackingAreas() {}

  public func setContentCompressionResistancePriority(_ priority: NSLayoutPriority, for orientation: NSUserInterfaceLayoutOrientation) {}
  public func setContentHuggingPriority(_ priority: NSLayoutPriority, for orientation: NSUserInterfaceLayoutOrientation) {}

  @discardableResult
  public func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
    let session = NSDraggingSession()
    #if !os(macOS)
      guard !items.isEmpty, let dragSource = NativeAPI.DragSource.create() else {
        return session
      }
      var filePaths: [String] = []
      var texts: [String] = []
      for item in items {
        let writer = item.pasteboardWriter
        if let nsurl = writer as? NSURL, let u = nsurl as URL? {
          if u.isFileURL { filePaths.append(u.path) }
          else { texts.append(u.absoluteString) }
        } else if let nsstr = writer as? NSString {
          texts.append(nsstr as String)
        } else if let pbItem = writer as? NSPasteboardItem {
          if let s = pbItem.string(forType: .string) ?? pbItem.string(forType: .URL) {
            texts.append(s)
          }
          if let f = pbItem.string(forType: .fileURL), let u = URL(string: f), u.isFileURL {
            filePaths.append(u.path)
          }
        }
      }
      if !filePaths.isEmpty {
        dragSource.setFilePaths(filePaths)
      }
      if let firstText = texts.first {
        dragSource.setText(firstText)
      }
      if let img = items.first?.draggingContents as? NSImage, let nativeImg = img.toNativeImage() {
        dragSource.setImage(nativeImg)
      }
      let mask = source.draggingSession(session, sourceOperationMaskFor: .outsideApplication)
      if mask.contains(.copy) {
        dragSource.setDragOperation(.copy)
      } else if mask.contains(.move) {
        dragSource.setDragOperation(.move)
      } else if mask.contains(.link) {
        dragSource.setDragOperation(.link)
      }
      _ = dragSource.addListener { [weak source] dragEvent in
        guard case let .ended(_, _, operation) = dragEvent else { return }
        MainActor.assumeIsolated {
          let nsOp: NSDragOperation
          switch operation {
          case .copy: nsOp = .copy
          case .move: nsOp = .move
          case .link: nsOp = .link
          case .none: nsOp = []
          }
          source?.draggingSession(session, endedAt: NSEvent.mouseLocation, operation: nsOp)
          dragSource.dispose()
        }
      }
      _ = dragSource.startDragging(window?.nativeWindow)
    #endif
    return session
  }

  open func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
  open func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
  open func draggingExited(_ sender: (any NSDraggingInfo)?) {}
  open func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
}

@MainActor
open class NSCell: NSObject {
  public var stringValue: String = ""
  public var font: NSFont?
  public var isEditable: Bool = true
  public var isSelectable: Bool = true
  public var wraps: Bool = false
  public var isScrollable: Bool = true
  public weak var controlView: NSView?

  public override init() {
    super.init()
  }

  public init(textCell string: String) {
    self.stringValue = string
    super.init()
  }
}

open class NSTextFieldCell: NSCell {
  public var placeholderString: String?
  public var placeholderAttributedString: NSAttributedString?
  public var textColor: NSColor?
  public var backgroundColor: NSColor?
  public var drawsBackground: Bool = false
  public var isBezeled: Bool = false

  public override init() {
    super.init()
  }

  public override init(textCell string: String) {
    super.init(textCell: string)
  }

  open func drawingRect(forBounds rect: NSRect) -> NSRect { rect }
  open func titleRect(forBounds rect: NSRect) -> NSRect { rect }
  open func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
  open func edit(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    event: NSEvent?
  ) {}
  open func select(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    start selStart: Int,
    length selLength: Int
  ) {}
}

open class NSControl: NSView {
  public struct StateValue: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let mixed = StateValue(-1)
    public static let off = StateValue(0)
    public static let on = StateValue(1)
  }

  public enum ControlSize: UInt, Sendable {
    case regular = 0
    case small = 1
    case mini = 2
    case large = 3
  }

  public enum ImagePosition: UInt, Sendable {
    case noImage = 0
    case imageOnly = 1
    case imageLeft = 2
    case imageRight = 3
    case imageBelow = 4
    case imageAbove = 5
    case imageOverlaps = 6
    case imageLeading = 7
    case imageTrailing = 8
  }

  public weak var target: AnyObject?
  public var action: Selector?
  public var actionHandler: ((Any?) -> Void)?
  public var isEnabled: Bool = true
  public var controlSize: ControlSize = .regular
  public var font: NSFont? = .systemFont(ofSize: NSFont.systemFontSize)
  public var lineBreakMode: NSLineBreakMode = .byWordWrapping
  public var usesSingleLineMode: Bool = false
  public var stringValue: String = ""
  public var intValue: Int32 {
    get { Int32(stringValue) ?? 0 }
    set { stringValue = String(newValue) }
  }
  public var doubleValue: Double {
    get { Double(stringValue) ?? 0 }
    set { stringValue = String(newValue) }
  }
  public var cell: NSCell? = NSCell() {
    didSet { cell?.controlView = self }
  }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell?.controlView = self
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    cell?.controlView = self
  }

  open func currentEditor() -> NSText? { nil }
  open func sizeToFit() {}
  open func sizeThatFits(_ size: NSSize) -> NSSize { intrinsicContentSize }
  @discardableResult
  public func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    if let handler = actionHandler {
      handler(self)
      return true
    }
    return false
  }
}

open class NSButton: NSControl {
  public enum BezelStyle: UInt, Sendable {
    case automatic = 0
    case push = 1
    case rounded = 2
    case flexiblePush = 3
    case toolbar = 11
    case accessoryBarAction = 12
    case accessoryBar = 13
    case inline = 15
  }

  public var title: String {
    get { stringValue }
    set { stringValue = newValue }
  }
  public var image: NSImage?
  public var imagePosition: ImagePosition = .imageLeading
  public var contentTintColor: NSColor?
  public var state: StateValue = .off
  public var isBordered: Bool = true
  public var bezelStyle: BezelStyle = .rounded
  public var keyEquivalent: String = ""

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public convenience init(title: String, target: AnyObject?, action: Selector?) {
    self.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
  }

  public convenience init(image: NSImage, target: AnyObject?, action: Selector?) {
    self.init(frame: .zero)
    self.image = image
    self.imagePosition = .imageOnly
    self.target = target
    self.action = action
  }

  public convenience init(checkboxWithTitle title: String, target: AnyObject?, action: Selector?) {
    self.init(title: title, target: target, action: action)
  }

  @discardableResult
  public func sendAction(on mask: NSEvent.EventTypeMask) -> Int { 0 }
  public func performClick(_ sender: Any?) { _ = sendAction(action, to: target) }
}

@MainActor
public protocol NSTextFieldDelegate: NSObjectProtocol {
  func controlTextDidChange(_ obj: Notification)
  func controlTextDidEndEditing(_ obj: Notification)
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
}

extension NSTextFieldDelegate {
  public func controlTextDidChange(_ obj: Notification) {}
  public func controlTextDidEndEditing(_ obj: Notification) {}
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    false
  }
}

open class NSTextField: NSControl {
  public static let textDidChangeNotification = Notification.Name("NSControlTextDidChangeNotification")
  public static let textDidEndEditingNotification = Notification.Name("NSControlTextDidEndEditingNotification")

  public weak var delegate: (any NSTextFieldDelegate)?
  public var placeholderString: String?
  public var placeholderAttributedString: NSAttributedString?
  public var isEditable: Bool = true
  public var isSelectable: Bool = true
  public var isBordered: Bool = false
  public var isBezeled: Bool = false
  public var drawsBackground: Bool = false
  public var backgroundColor: NSColor?
  public var textColor: NSColor? = .labelColor
  public var maximumNumberOfLines: Int = 1

  public convenience init(labelWithString stringValue: String) {
    self.init(frame: .zero)
    self.stringValue = stringValue
    self.isEditable = false
    self.isBordered = false
    self.drawsBackground = false
  }
}

open class NSTextInputContext: NSObject {
  public var selectedKeyboardInputSource: String?
  public func discardMarkedText() {}
  public func invalidateCharacterCoordinates() {}
}

@MainActor
public protocol NSTextViewDelegate: NSObjectProtocol {
  func textDidChange(_ notification: Notification)
  func textViewDidChangeSelection(_ notification: Notification)
  func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
}

extension NSTextViewDelegate {
  public func textDidChange(_ notification: Notification) {}
  public func textViewDidChangeSelection(_ notification: Notification) {}
  public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { false }
}

/// Proxies fieldEditor queries (`selectedRange`, `selectAll`, `moveToEndOfDocument`,
/// `hasMarkedText`, `string`) to the currently focused Win32 `EDIT` control when attached,
/// and also serves standalone multiline text views.
open class NSTextView: NSText {
  public static let didChangeSelectionNotification = Notification.Name("NSTextViewDidChangeSelectionNotification")

  public weak var delegate: (any NSTextViewDelegate)?
  public var isFieldEditorProxy: Bool = false
  public var isEditable: Bool = true {
    didSet { syncStandaloneNativeEditor() }
  }
  public var isSelectable: Bool = true
  public var isRichText: Bool = false
  public var importsGraphics: Bool = false
  public var allowsUndo: Bool = true
  public var drawsBackground: Bool = false {
    didSet { syncStandaloneNativeEditor() }
  }
  public var backgroundColor: NSColor = .clear {
    didSet { syncStandaloneNativeEditor() }
  }
  public var textColor: NSColor? = .labelColor {
    didSet { syncStandaloneNativeEditor() }
  }
  public var insertionPointColor: NSColor = .labelColor
  public var font: NSFont? = .systemFont(ofSize: NSFont.systemFontSize) {
    didSet { syncStandaloneNativeEditor() }
  }
  public var textContainerInset: NSSize = .zero
  public var isVerticallyResizable: Bool = true
  public var isHorizontallyResizable: Bool = false
  public var minSize: NSSize = .zero
  public var maxSize: NSSize = NSSize(width: 1e7, height: 1e7)
  public var isAutomaticQuoteSubstitutionEnabled: Bool = false
  public var isAutomaticDashSubstitutionEnabled: Bool = false
  public var isAutomaticTextReplacementEnabled: Bool = false
  public var isAutomaticSpellingCorrectionEnabled: Bool = false
  public var isContinuousSpellCheckingEnabled: Bool = false
  public var smartInsertDeleteEnabled: Bool = false
  public var usesFindBar: Bool = false
  public var writingToolsBehavior: NSWritingToolsBehavior = .default
  public var linkTextAttributes: [NSAttributedString.Key: Any]? = [:]
  public var selectedTextAttributes: [NSAttributedString.Key: Any] = [:]
  public var typingAttributes: [NSAttributedString.Key: Any] = [:]
  public let inputContext: NSTextInputContext? = NSTextInputContext()
  public private(set) var textStorage: NSTextStorage?
  public private(set) var layoutManager: NSLayoutManager?
  public var textContainer: NSTextContainer?
  public private(set) var textContentStorage: NSTextContentStorage?
  public private(set) var textLayoutManager: NSTextLayoutManager?
  private var localSelection: NSRange = NSRange(location: 0, length: 0)
  #if !os(macOS)
    private var standaloneEditor: NativeAPI.TextField?
    private var standaloneEditorListener: NativeAPI.ListenerId?
    private var isSyncingStandaloneText = false

    @discardableResult
    public func ensureStandaloneNativeEditor() -> NativeAPI.View? {
      guard !isFieldEditorProxy else { return nil }
      if let existing = standaloneEditor {
        syncStandaloneNativeEditor()
        return existing
      }
      guard let tf = NativeAPI.TextField.create(textStorage?.string ?? "") else { return nil }
      tf.setMultiline(true)
      tf.setBordered(false)
      standaloneEditor = tf
      ownedNativeView = tf
      syncStandaloneNativeEditor()
      standaloneEditorListener = tf.addListener { [weak self] event in
        guard let self else { return }
        if case let .textFieldChanged(_, rawText) = event {
          let newText = rawText ?? ""
          MainActor.assumeIsolated {
            guard !self.isSyncingStandaloneText else { return }
            let normalized = newText.replacingOccurrences(of: "\r\n", with: "\n")
            if self.textStorage?.string != normalized {
              self.isSyncingStandaloneText = true
              if let storage = self.textStorage {
                storage.replaceCharacters(
                  in: NSRange(location: 0, length: storage.length),
                  with: normalized
                )
              }
              self.didChangeText()
              self.isSyncingStandaloneText = false
            }
          }
        }
      }
      return tf
    }

    internal func syncStandaloneNativeEditor() {
      guard !isFieldEditorProxy, let tf = standaloneEditor else { return }
      tf.setEditable(isEditable)
      if let font {
        tf.setFontSize(Double(font.pointSize))
        if font.fontName.lowercased().contains("mono") || font.fontName.lowercased().contains("consolas") {
          tf.setFontFamily("Consolas")
        }
      }
      let app = window?.effectiveAppearance ?? NSAppearance.systemAppearance
      if let tc = textColor?.resolved(for: app) {
        tf.setTextColor(NativeAPI.Color(
          r: UInt8(clamping: Int((tc.r * 255).rounded())),
          g: UInt8(clamping: Int((tc.g * 255).rounded())),
          b: UInt8(clamping: Int((tc.b * 255).rounded())),
          a: UInt8(clamping: Int((tc.a * 255).rounded()))
        ))
      }
      let isDark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      if drawsBackground {
        let bg = backgroundColor.resolved(for: app)
        tf.setBackgroundColor(NativeAPI.Color(
          r: UInt8(clamping: Int((bg.r * 255).rounded())),
          g: UInt8(clamping: Int((bg.g * 255).rounded())),
          b: UInt8(clamping: Int((bg.b * 255).rounded())),
          a: UInt8(clamping: Int((bg.a * 255).rounded()))
        ))
      } else {
        tf.setBackgroundColor(
          isDark
            ? NativeAPI.Color(r: 36, g: 36, b: 39, a: 255)
            : NativeAPI.Color(r: 244, g: 244, b: 246, a: 255)
        )
      }
    }

    internal func syncStandaloneTextFromStorage() {
      guard !isFieldEditorProxy, !isSyncingStandaloneText, let tf = standaloneEditor else { return }
      let desired = (textStorage?.string ?? "").replacingOccurrences(of: "\n", with: "\r\n")
      if tf.text != desired {
        isSyncingStandaloneText = true
        tf.setText(desired)
        isSyncingStandaloneText = false
      }
    }

    internal func focusStandaloneNativeEditor() {
      _ = ensureStandaloneNativeEditor()
      standaloneEditor?.focus()
    }
  #else
    internal func syncStandaloneNativeEditor() {}
  #endif

  public var textContainerOrigin: NSPoint {
    NSPoint(x: textContainerInset.width, y: textContainerInset.height)
  }

  public var selectedRanges: [NSValue] {
    [NSValue(range: selectedRange())]
  }

  public override init(frame frameRect: NSRect) {
    let storage = NSTextStorage()
    let lm = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: max(frameRect.width, 100), height: 1e7))
    storage.addLayoutManager(lm)
    lm.addTextContainer(container)
    let contentStorage = NSTextContentStorage()
    contentStorage.textStorage = storage
    let tlm = NSTextLayoutManager()
    tlm.textContentStorage = contentStorage
    tlm.textContainer = container
    self.textStorage = storage
    self.layoutManager = lm
    self.textContainer = container
    self.textContentStorage = contentStorage
    self.textLayoutManager = tlm
    super.init(frame: frameRect)
  }

  public init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    let resolvedContainer = container ?? NSTextContainer(size: NSSize(width: max(frameRect.width, 100), height: 1e7))
    let lm = resolvedContainer.layoutManager ?? NSLayoutManager()
    if resolvedContainer.layoutManager == nil { lm.addTextContainer(resolvedContainer) }
    let storage = lm.textStorage ?? NSTextStorage()
    if lm.textStorage == nil { storage.addLayoutManager(lm) }
    let contentStorage = NSTextContentStorage()
    contentStorage.textStorage = storage
    let tlm = NSTextLayoutManager()
    tlm.textContentStorage = contentStorage
    tlm.textContainer = resolvedContainer
    self.textStorage = storage
    self.layoutManager = lm
    self.textContainer = resolvedContainer
    self.textContentStorage = contentStorage
    self.textLayoutManager = tlm
    super.init(frame: frameRect)
  }

  public convenience init(usingTextLayoutManager: Bool) {
    self.init(frame: .zero)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public static func scrollableTextView() -> NSScrollView {
    let sv = NSScrollView(frame: .zero)
    let tv = NSTextView(frame: .zero)
    sv.documentView = tv
    return sv
  }

  public var string: String {
    get {
      #if os(Windows)
        if isFieldEditorProxy, let hwnd = cak_focused_hwnd(), let cstr = cak_hwnd_get_text(hwnd) {
          defer { cak_free(cstr) }
          return String(cString: cstr)
        }
      #endif
      #if !os(macOS)
        if !isFieldEditorProxy, let raw = standaloneEditor?.text {
          return raw.replacingOccurrences(of: "\r\n", with: "\n")
        }
      #endif
      return textStorage?.string ?? ""
    }
    set {
      if let storage = textStorage {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: newValue)
      }
      #if !os(macOS)
        syncStandaloneTextFromStorage()
      #endif
    }
  }

  public func selectedRange() -> NSRange {
    #if !os(macOS)
      if let editor = standaloneEditor {
        let range = editor.selection
        return NSRange(location: Int(range.start), length: Int(range.length))
      }
    #endif
    #if os(Windows)
      if isFieldEditorProxy, let hwnd = cak_focused_hwnd() {
        var start: Int32 = 0
        var length: Int32 = 0
        cak_edit_get_selection(hwnd, &start, &length)
        return NSRange(location: max(0, Int(start)), length: max(0, Int(length)))
      }
    #endif
    return localSelection
  }

  public func setSelectedRange(_ charRange: NSRange) {
    localSelection = charRange
    #if !os(macOS)
      if let editor = standaloneEditor {
        editor.setSelection(NativeAPI.TextRange(
          start: CUnsignedLong(max(0, charRange.location)),
          length: CUnsignedLong(max(0, charRange.length))
        ))
        return
      }
    #endif
    #if os(Windows)
      if isFieldEditorProxy, let hwnd = cak_focused_hwnd() {
        cak_edit_set_selection(hwnd, Int32(charRange.location), Int32(charRange.length))
      }
    #endif
  }

  public func selectAll(_ sender: Any?) {
    #if !os(macOS)
      if let editor = standaloneEditor {
        let len = ((editor.text ?? "") as NSString).length
        editor.setSelection(NativeAPI.TextRange(start: 0, length: CUnsignedLong(len)))
        localSelection = NSRange(location: 0, length: len)
        return
      }
    #endif
    #if os(Windows)
      if isFieldEditorProxy, let hwnd = cak_focused_hwnd() {
        cak_edit_set_selection(hwnd, 0, -1)
        return
      }
    #endif
    let len = (string as NSString).length
    localSelection = NSRange(location: 0, length: len)
  }

  public func moveToEndOfDocument(_ sender: Any?) {
    let len = (string as NSString).length
    setSelectedRange(NSRange(location: len, length: 0))
  }

  public func scrollToEndOfDocument(_ sender: Any?) {}

  open func scrollRangeToVisible(_ range: NSRange) {}

  public func hasMarkedText() -> Bool {
    #if !os(macOS)
      if let editor = standaloneEditor {
        return editor.isComposing
      }
    #endif
    #if os(Windows)
      if isFieldEditorProxy, let hwnd = cak_focused_hwnd() {
        return cak_edit_has_ime_composition(hwnd) != 0
      }
    #endif
    return false
  }

  public func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {}

  open func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    true
  }

  open func didChangeText() {
    #if !os(macOS)
      syncStandaloneTextFromStorage()
    #endif
    let note = Notification(name: Self.didChangeNotification, object: self)
    delegate?.textDidChange(note)
    NotificationCenter.default.post(note)
  }

  open func breakUndoCoalescing() {}

  open func drawBackground(in rect: NSRect) {}

  open func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
    let sel = selectedRange()
    let ns = string as NSString
    guard sel.location >= 0 && sel.location + sel.length <= ns.length && sel.length > 0 else {
      return false
    }
    pboard.clearContents()
    return pboard.setString(ns.substring(with: sel), forType: .string)
  }

  open func performTextFinderAction(_ sender: Any?) {}

  open func insertText(_ string: Any, replacementRange: NSRange) {
    guard let s = string as? String ?? (string as? NSAttributedString)?.string else { return }
    let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    textStorage?.replaceCharacters(in: target, with: s)
    setSelectedRange(NSRange(location: target.location + (s as NSString).length, length: 0))
    didChangeText()
  }

  open func paste(_ sender: Any?) {
    if let s = NSPasteboard.general.string(forType: .string) {
      insertText(s, replacementRange: selectedRange())
    }
  }
}

open class NSClipView: NSView {
  public var documentView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let doc = documentView { addSubview(doc) }
    }
  }
  public var drawsBackground: Bool = false
  public var backgroundColor: NSColor = .clear

  open func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect { proposedBounds }
  public func scroll(to newOrigin: NSPoint) {
    bounds.origin = newOrigin
    if postsBoundsChangedNotifications {
      NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self)
    }
  }
}

open class NSScroller: NSControl {
  public enum Style: Int, Sendable {
    case legacy = 0
    case overlay = 1
  }
  public static let preferredScrollerStyleDidChangeNotification = Notification.Name(
    "NSPreferredScrollerStyleDidChangeNotification"
  )
  public static var preferredScrollerStyle: Style { .overlay }
}

open class NSScrollView: NSView {
  public var contentView: NSClipView = NSClipView(frame: .zero)
  public var documentView: NSView? {
    get { contentView.documentView }
    set { contentView.documentView = newValue }
  }
  public var hasVerticalScroller: Bool = true
  public var hasHorizontalScroller: Bool = false
  public var autohidesScrollers: Bool = true
  public var automaticallyAdjustsContentInsets: Bool = true
  public var isFindBarVisible: Bool = false
  public var scrollerStyle: NSScroller.Style = .overlay
  public var drawsBackground: Bool = false
  public var backgroundColor: NSColor = .clear
  public var borderType: NSBorderType = .noBorder
  public var verticalScroller: NSScroller? = NSScroller(frame: .zero)

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    contentView.frame = NSRect(origin: .zero, size: frameRect.size)
    addSubview(contentView)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    addSubview(contentView)
  }

  open func tile() {}
  public func reflectScrolledClipView(_ cView: NSClipView) {}
}

open class NSTableColumn: NSObject {
  public struct ResizingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let noResizing = ResizingOptions([])
    public static let autoresizingMask = ResizingOptions(rawValue: 1 << 0)
    public static let userResizingMask = ResizingOptions(rawValue: 1 << 1)
  }

  public var identifier: NSUserInterfaceItemIdentifier
  public var title: String = ""
  public var width: CGFloat = 100
  public var minWidth: CGFloat = 10
  public var maxWidth: CGFloat = 10000
  public var resizingMask: ResizingOptions = [.autoresizingMask, .userResizingMask]

  public init(identifier: NSUserInterfaceItemIdentifier) {
    self.identifier = identifier
    super.init()
  }
}

open class NSTableCellView: NSView {
  public var textField: NSTextField?
  public var imageView: NSImageView?
}

@MainActor
public protocol NSTableViewDataSource: NSObjectProtocol {
  func numberOfRows(in tableView: NSTableView) -> Int
}

extension NSTableViewDataSource {
  public func numberOfRows(in tableView: NSTableView) -> Int { 0 }
}

@MainActor
public protocol NSTableViewDelegate: NSObjectProtocol {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool
}

extension NSTableViewDelegate {
  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    nil
  }
  public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

open class NSTableView: NSControl {
  public enum Style: Int, Sendable {
    case automatic = 0
    case fullWidth = 1
    case inset = 2
    case sourceList = 3
    case plain = 4
  }

  public enum SelectionHighlightStyle: Int, Sendable {
    case none = -1
    case regular = 0
    case sourceList = 1
  }

  public enum ColumnAutoresizingStyle: UInt, Sendable {
    case noColumnAutoresizing = 0
    case uniformColumnAutoresizingStyle = 1
    case sequentialColumnAutoresizingStyle = 2
    case reverseSequentialColumnAutoresizingStyle = 3
    case lastColumnOnlyAutoresizingStyle = 4
    case firstColumnOnlyAutoresizingStyle = 5
  }

  public weak var dataSource: (any NSTableViewDataSource)?
  public weak var delegate: (any NSTableViewDelegate)?
  public private(set) var tableColumns: [NSTableColumn] = []
  public var headerView: NSView? = nil
  public var style: Style = .automatic
  public var columnAutoresizingStyle: ColumnAutoresizingStyle = .uniformColumnAutoresizingStyle
  public var rowHeight: CGFloat = 28
  public var intercellSpacing: NSSize = .zero
  public var selectionHighlightStyle: SelectionHighlightStyle = .regular
  public var usesAlternatingRowBackgroundColors: Bool = false
  public var backgroundColor: NSColor = .clear
  public var selectedRow: Int = -1
  public var clickedRow: Int = -1
  private var rowViews: [Int: NSView] = [:]

  public var numberOfRows: Int {
    dataSource?.numberOfRows(in: self) ?? 0
  }

  public func addTableColumn(_ column: NSTableColumn) { tableColumns.append(column) }

  public func reloadData() {
    for (_, v) in rowViews { v.removeFromSuperview() }
    rowViews.removeAll()
  }

  public func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    selectedRow = indexes.first ?? -1
  }
  public func deselectAll(_ sender: Any?) { selectedRow = -1 }
  public func scrollRowToVisible(_ row: Int) {}
  public func row(at point: NSPoint) -> Int {
    guard rowHeight > 0 else { return -1 }
    let idx = Int(floor(point.y / rowHeight))
    return idx >= 0 && idx < numberOfRows ? idx : -1
  }
  public func row(for view: NSView) -> Int {
    for (r, v) in rowViews where view === v || view.isDescendant(of: v) {
      return r
    }
    return -1
  }
  public func rows(in rect: NSRect) -> NSRange {
    let total = numberOfRows
    guard total > 0 && rowHeight > 0 else { return NSRange(location: 0, length: 0) }
    let first = max(0, min(total - 1, Int(floor(max(0, rect.minY) / rowHeight))))
    let lastExclusive = max(first, min(total, Int(ceil(max(0, rect.maxY) / rowHeight))))
    return NSRange(location: first, length: max(0, lastExclusive - first))
  }
  public func view(atColumn column: Int, row: Int, makeIfNecessary: Bool) -> NSView? {
    if let existing = rowViews[row] { return existing }
    guard makeIfNecessary, row >= 0 && row < numberOfRows else { return nil }
    let col = column >= 0 && column < tableColumns.count ? tableColumns[column] : nil
    guard let created = delegate?.tableView(self, viewFor: col, row: row) else { return nil }
    created.frame = NSRect(x: 0, y: CGFloat(row) * rowHeight, width: bounds.width, height: rowHeight)
    rowViews[row] = created
    addSubview(created)
    return created
  }
  public func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? { nil }
}

open class NSSegmentedControl: NSControl {
  public enum SwitchTracking: UInt, Sendable {
    case selectOne = 0
    case selectAny = 1
    case momentary = 2
  }

  public var segmentCount: Int = 0 {
    didSet {
      while labels.count < segmentCount { labels.append("") }
      while widths.count < segmentCount { widths.append(0) }
    }
  }
  public var selectedSegment: Int = 0
  public var trackingMode: SwitchTracking = .selectOne
  public var segmentStyle: Int = 0
  private var labels: [String] = []
  private var widths: [CGFloat] = []

  public convenience init(labels: [String], trackingMode: SwitchTracking, target: AnyObject?, action: Selector?) {
    self.init(frame: .zero)
    self.segmentCount = labels.count
    self.labels = labels
    self.widths = Array(repeating: 0, count: labels.count)
    self.trackingMode = trackingMode
    self.target = target
    self.action = action
  }

  public func setLabel(_ label: String, forSegment segment: Int) {
    guard segment >= 0 && segment < labels.count else { return }
    labels[segment] = label
  }

  public func label(forSegment segment: Int) -> String? {
    guard segment >= 0 && segment < labels.count else { return nil }
    return labels[segment]
  }

  public func setWidth(_ width: CGFloat, forSegment segment: Int) {
    guard segment >= 0 && segment < widths.count else { return }
    widths[segment] = width
  }

  public func width(forSegment segment: Int) -> CGFloat {
    guard segment >= 0 && segment < widths.count else { return 0 }
    return widths[segment]
  }
}

public enum NSImageScaling: UInt, Sendable {
  case scaleProportionallyDown = 0
  case scaleAxesIndependently = 1
  case scaleNone = 2
  case scaleProportionallyUpOrDown = 3
}

open class NSImageView: NSControl {
  public var image: NSImage?
  public var animates: Bool = false
  public var imageScaling: NSImageScaling = .scaleProportionallyDown
  public var contentTintColor: NSColor?
}

open class NSBox: NSView {
  public enum BoxType: UInt, Sendable {
    case primary = 0
    case secondary = 1
    case separator = 2
    case oldStyle = 3
    case custom = 4
  }

  public var boxType: BoxType = .primary
  public var fillColor: NSColor = .clear
  public var borderColor: NSColor = .separatorColor
  public var borderWidth: CGFloat = 1
  public var cornerRadius: CGFloat = 0
}

open class NSVisualEffectView: NSView {
  public enum Material: Int, Sendable {
    case appearanceBased = 0
    case titlebar = 3
    case selection = 4
    case menu = 5
    case popover = 6
    case sidebar = 7
    case headerView = 10
    case sheet = 11
    case windowBackground = 12
    case hudWindow = 13
    case fullScreenUI = 15
    case toolTip = 17
    case contentBackground = 18
    case underWindowBackground = 21
    case underPageBackground = 22
  }

  public enum BlendingMode: Int, Sendable {
    case behindWindow = 0
    case withinWindow = 1
  }

  public enum State: Int, Sendable {
    case followsWindowActiveState = 0
    case active = 1
    case inactive = 2
  }

  public var material: Material = .hudWindow
  public var blendingMode: BlendingMode = .behindWindow
  public var state: State = .active
  public var isEmphasized: Bool = false

  open override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.applyWindowsBackdrop(.acrylic)
  }
}

open class NSGlassEffectView: NSView {
  public enum Style: Int, Sendable {
    case regular = 0
    case clear = 1
  }

  public var style: Style = .regular
  public var cornerRadius: CGFloat = 0
  public var tintColor: NSColor?
  public var contentView: NSView? {
    didSet {
      oldValue?.removeFromSuperview()
      if let content = contentView {
        content.frame = bounds
        addSubview(content)
      }
    }
  }

  open override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.applyWindowsBackdrop(.acrylic)
  }
}
