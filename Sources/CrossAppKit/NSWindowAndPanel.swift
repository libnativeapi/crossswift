import Foundation
#if !os(macOS)
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

#if CROSS_SWIFTUI_HARMONY
  @_silgen_name("harmony_host_open_window")
  private func harmony_host_open_window(
    _ surfaceId: Int32,
    _ title: UnsafePointer<CChar>,
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double,
    _ isTransparent: Int32,
    _ isTitled: Int32,
    _ isResizable: Int32,
    _ isFloating: Int32,
    _ focus: Int32
  )

  @_silgen_name("harmony_host_update_bounds")
  private func harmony_host_update_bounds(
    _ surfaceId: Int32,
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
  )

  @_silgen_name("harmony_host_hide_window")
  private func harmony_host_hide_window(_ surfaceId: Int32)

  @_silgen_name("harmony_host_focus_window")
  private func harmony_host_focus_window(_ surfaceId: Int32)

  @_silgen_name("harmony_host_destroy_window")
  private func harmony_host_destroy_window(_ surfaceId: Int32)

  @MainActor
  internal enum HarmonyWindowBridge {
    private struct WeakNSWindow {
      weak var window: NSWindow?
    }

    static let transparentBleed: Double = 24.0
    private static var nextSecondaryId: Int = 1
    private static var windowsBySurface: [Int: WeakNSWindow] = [:]
    private static var nativeWindows: [Int: NativeAPI.Window] = [:]
    private static var listenerIds: [Int: ListenerId] = [:]
    private static var lastBounds: [Int: NativeAPI.Rectangle] = [:]
    private static var lastPresentUptime: [Int: TimeInterval] = [:]
    private static var hideGeneration: UInt64 = 0

    static func surfaceId(for window: NSWindow) -> Int {
      if let existing = window._harmonyAssignedSurfaceId {
        windowsBySurface[existing] = WeakNSWindow(window: window)
        return existing
      }
      let id: Int
      if windowsBySurface[0]?.window == nil && window.parent == nil {
        id = 0
      } else {
        id = nextSecondaryId
        nextSecondaryId += 1
      }
      window._harmonyAssignedSurfaceId = id
      windowsBySurface[id] = WeakNSWindow(window: window)
      return id
    }

    static func window(forSurface id: Int) -> NSWindow? {
      windowsBySurface[id]?.window
    }

    static func isTransparentFrameless(_ window: NSWindow) -> Bool {
      guard !window.styleMask.contains(.titled) else { return false }
      let bg = window.backgroundColor.resolved(for: window.effectiveAppearance)
      return !window.isOpaque || bg.a < 0.05
    }

    private static func targetGeometry(for window: NSWindow) -> (
      rect: NativeAPI.Rectangle,
      isTransparent: Bool,
      bleed: Double,
      contentW: Double,
      contentH: Double
    ) {
      let isTransparent = isTransparentFrameless(window)
      let bleed = isTransparent ? transparentBleed : 0.0
      let contentW = Double(max(1, window.storedFrame.width))
      let contentH = Double(max(1, window.storedFrame.height))
      let top = CrossAppKitCoordinates.rectToNativeTopLeft(window.storedFrame)
      let minW = isTransparent ? 48.0 : 120.0
      let minH = isTransparent ? 48.0 : 80.0
      let rect = NativeAPI.Rectangle(
        x: max(0, top.x - bleed),
        y: max(0, top.y - bleed),
        width: max(minW, top.width + bleed * 2),
        height: max(minH, top.height + bleed * 2)
      )
      return (rect, isTransparent, bleed, contentW, contentH)
    }

    static func ensurePrimaryWindowAttachedIfNeeded() {
      guard nativeWindows[0] == nil else { return }
      guard let primary = NativeAPI.Application.shared.getPrimaryWindow()
        ?? NativeAPI.WindowManager.shared.getAll().first
      else {
        return
      }
      attachNativeWindow(primary, forSurface: 0)
    }

    static func attachNativeWindow(_ nativeWin: NativeAPI.Window, forSurface id: Int) {
      if nativeWindows[id]?.id == nativeWin.id { return }
      detachNativeWindow(forSurface: id)
      nativeWindows[id] = nativeWin
      listenerIds[id] = nativeWin.addListener { event in
        nonisolated(unsafe) let boxEvent = event
        _performOnMainActor {
          handleNativeEvent(boxEvent, forSurface: id)
        }
      }
    }

    static func detachNativeWindow(forSurface id: Int) {
      if let listenerId = listenerIds.removeValue(forKey: id), let nw = nativeWindows[id] {
        _ = nw.removeListener(listenerId)
      }
      nativeWindows.removeValue(forKey: id)
    }

    private static func handleNativeEvent(_ event: NativeAPI.WindowEvent, forSurface id: Int) {
      switch event {
      case .focused:
        if let win = windowsBySurface[id]?.window, win.isVisible {
          win.becomeKey()
        }
      case .blurred:
        let presentTime = lastPresentUptime[id] ?? 0
        guard ProcessInfo.processInfo.systemUptime - presentTime > 0.35 else { return }
        guard let win = windowsBySurface[id]?.window, win.isVisible, win.isKeyWindow,
          NSWindow._suppressResignKeyCount == 0
        else { return }
        if win.parent != nil {
          // Allow a sibling/parent window's .focused callback to arrive before resigning key.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak win] in
            guard let win, win.isVisible, win.isKeyWindow, NSWindow._suppressResignKeyCount == 0
            else { return }
            win.resignKey()
          }
        } else {
          win.resignKey()
        }
      case .moved(_, let newPos):
        guard let win = windowsBySurface[id]?.window, win.isVisible else { return }
        let bleed = isTransparentFrameless(win) ? transparentBleed : 0.0
        win.storedFrame = CrossAppKitCoordinates.rectFromNativeTopLeft(
          x: newPos.x + bleed,
          y: newPos.y + bleed,
          width: Double(win.storedFrame.width),
          height: Double(win.storedFrame.height)
        )
        let note = Notification(name: NSWindow.didMoveNotification, object: win)
        NotificationCenter.default.post(note)
        win.delegate?.windowDidMove(note)
      case .resized(_, let newSize):
        guard let win = windowsBySurface[id]?.window, win.isVisible else { return }
        guard !isTransparentFrameless(win) else { return }
        win.storedFrame.size = NSSize(width: CGFloat(newSize.width), height: CGFloat(newSize.height))
        let note = Notification(name: NSWindow.didResizeNotification, object: win)
        NotificationCenter.default.post(note)
        win.delegate?.windowDidResize(note)
      case .closeRequested(_, let req):
        if let win = windowsBySurface[id]?.window {
          if let should = win.delegate?.windowShouldClose(win), !should {
            _ = req?.cancel()
            return
          }
          _ = req?.cancel()
          win.close()
        } else if NSApplication.shared.delegate?.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false {
          _ = req?.cancel()
          _ = NativeAPI.Application.shared.hide()
        }
      default:
        break
      }
    }

    static func openOrShow(_ window: NSWindow, focus: Bool) {
      hideGeneration &+= 1
      let id = surfaceId(for: window)
      windowsBySurface[id] = WeakNSWindow(window: window)
      lastPresentUptime[id] = ProcessInfo.processInfo.systemUptime
      if id == 0 {
        ensurePrimaryWindowAttachedIfNeeded()
      }

      let geo = targetGeometry(for: window)
      NSWindow._harmonyWindowSurfaceHandler?(
        id,
        geo.isTransparent,
        geo.isTransparent ? geo.contentW : 0,
        geo.isTransparent ? geo.contentH : 0,
        geo.bleed
      )
      lastBounds[id] = geo.rect
      _ = NativeAPI.Application.shared.show()

      let isTitled: Int32 = window.styleMask.contains(.titled) ? 1 : 0
      let isResizable: Int32 = window.styleMask.contains(.resizable) ? 1 : 0
      let isFloating: Int32 = window.level.rawValue >= NSWindow.Level.floating.rawValue ? 1 : 0
      let isTrans: Int32 = geo.isTransparent ? 1 : 0
      window.title.withCString { cTitle in
        harmony_host_open_window(
          Int32(id),
          cTitle,
          geo.rect.x,
          geo.rect.y,
          geo.rect.width,
          geo.rect.height,
          isTrans,
          isTitled,
          isResizable,
          isFloating,
          focus ? 1 : 0
        )
      }
    }

    static func syncFrame(for window: NSWindow) {
      guard let id = window._harmonyAssignedSurfaceId else { return }
      guard window.isVisible || id == 0 else { return }
      guard window.storedFrame.width > 1 && window.storedFrame.height > 1 else { return }
      let geo = targetGeometry(for: window)
      NSWindow._harmonyWindowSurfaceHandler?(
        id,
        geo.isTransparent,
        geo.isTransparent ? geo.contentW : 0,
        geo.isTransparent ? geo.contentH : 0,
        geo.bleed
      )
      if let prev = lastBounds[id],
        abs(prev.x - geo.rect.x) < 0.5,
        abs(prev.y - geo.rect.y) < 0.5,
        abs(prev.width - geo.rect.width) < 0.5,
        abs(prev.height - geo.rect.height) < 0.5
      {
        return
      }
      lastBounds[id] = geo.rect
      harmony_host_update_bounds(
        Int32(id),
        geo.rect.x,
        geo.rect.y,
        geo.rect.width,
        geo.rect.height
      )
    }

    static func focusWindow(_ window: NSWindow) {
      guard let id = window._harmonyAssignedSurfaceId, window.isVisible else { return }
      lastPresentUptime[id] = ProcessInfo.processInfo.systemUptime
      harmony_host_focus_window(Int32(id))
    }

    static func hideWindow(_ window: NSWindow) {
      guard let id = window._harmonyAssignedSurfaceId else { return }
      hideGeneration &+= 1
      let token = hideGeneration
      lastBounds.removeValue(forKey: id)
      harmony_host_hide_window(Int32(id))
      if id != 0 {
        detachNativeWindow(forSurface: id)
      }
      DispatchQueue.main.async {
        guard token == hideGeneration else { return }
        let hasVisible = NSApplication.shared.windows.contains { $0.isVisible }
        guard !hasVisible else { return }
        _ = NativeAPI.Application.shared.hide()
      }
    }

    static func destroyWindowIfSecondary(_ window: NSWindow) {
      guard let id = window._harmonyAssignedSurfaceId, id != 0 else { return }
      lastBounds.removeValue(forKey: id)
      detachNativeWindow(forSurface: id)
      windowsBySurface.removeValue(forKey: id)
      harmony_host_destroy_window(Int32(id))
    }

    static func presentMainWindow() {
      hideGeneration &+= 1
      _ = NativeAPI.Application.shared.show()
      if let primaryWin = windowsBySurface[0]?.window, primaryWin.isVisible {
        lastPresentUptime[0] = ProcessInfo.processInfo.systemUptime
        harmony_host_focus_window(0)
      }
    }

    static func handleKeyEvent(surfaceId: Int, keyCode: Int) -> Bool {
      guard let win = windowsBySurface[surfaceId]?.window, win.isVisible else { return false }
      let carbonCode: UInt16
      let chars: String
      switch keyCode {
      case 27:
        carbonCode = 53
        chars = "\u{1B}"
      case 38:
        carbonCode = 126
        chars = "\u{F700}"
      case 40:
        carbonCode = 125
        chars = "\u{F701}"
      case 9:
        carbonCode = 48
        chars = "\t"
      case 13:
        carbonCode = 36
        chars = "\r"
      default:
        return false
      }
      let ev = NSEvent(
        type: .keyDown,
        modifierFlags: [],
        windowNumber: win.windowNumber,
        window: win,
        characters: chars,
        charactersIgnoringModifiers: chars,
        keyCode: carbonCode
      )
      win._eventReachedBaseSendEvent = false
      win.sendEvent(ev)
      return !win._eventReachedBaseSendEvent
    }
  }

  @MainActor @_cdecl("swift_harmony_window_attached")
  public func swiftHarmonyWindowAttached(_ surfaceId: Int32, _ windowId: UInt32) {
    let id = Int(surfaceId)
    if let nativeWin = NativeAPI.WindowManager.shared.get(WindowId(windowId)) {
      HarmonyWindowBridge.attachNativeWindow(nativeWin, forSurface: id)
    } else if id == 0 {
      HarmonyWindowBridge.ensurePrimaryWindowAttachedIfNeeded()
    }
  }

  @MainActor
  public func _harmonyHandleKeyEvent(surfaceId: Int, keyCode: Int) -> Bool {
    HarmonyWindowBridge.handleKeyEvent(surfaceId: surfaceId, keyCode: keyCode)
  }

  @MainActor
  internal func _harmonyPresentMainWindow() {
    HarmonyWindowBridge.presentMainWindow()
  }
#endif

@MainActor
public protocol NSWindowDelegate: AnyObject {
  func windowDidBecomeKey(_ notification: Notification)
  func windowDidResignKey(_ notification: Notification)
  func windowDidBecomeMain(_ notification: Notification)
  func windowDidResignMain(_ notification: Notification)
  func windowDidMove(_ notification: Notification)
  func windowDidResize(_ notification: Notification)
  func windowWillClose(_ notification: Notification)
  func windowShouldClose(_ sender: NSWindow) -> Bool
  func windowDidChangeOcclusionState(_ notification: Notification)
  func windowDidChangeScreen(_ notification: Notification)
}

extension NSWindowDelegate {
  public func windowDidBecomeKey(_ notification: Notification) {}
  public func windowDidResignKey(_ notification: Notification) {}
  public func windowDidBecomeMain(_ notification: Notification) {}
  public func windowDidResignMain(_ notification: Notification) {}
  public func windowDidMove(_ notification: Notification) {}
  public func windowDidResize(_ notification: Notification) {}
  public func windowWillClose(_ notification: Notification) {}
  public func windowShouldClose(_ sender: NSWindow) -> Bool { true }
  public func windowDidChangeOcclusionState(_ notification: Notification) {}
  public func windowDidChangeScreen(_ notification: Notification) {}
}

open class CAMediaTimingFunction: NSObject {
  public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = Name(rawValue: "linear")
    public static let easeIn = Name(rawValue: "easeIn")
    public static let easeOut = Name(rawValue: "easeOut")
    public static let easeInEaseOut = Name(rawValue: "easeInEaseOut")
    public static let `default` = Name(rawValue: "default")
  }

  public init(name: Name) { super.init() }
  public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) { super.init() }
}

public typealias CAMediaTimingFunctionName = CAMediaTimingFunction.Name

open class NSAnimationContext: NSObject {
  nonisolated(unsafe) public static let current = NSAnimationContext()
  public var duration: TimeInterval = 0.2
  public var timingFunction: CAMediaTimingFunction?
  public var allowsImplicitAnimation: Bool = false

  public static func runAnimationGroup(
    _ changes: (NSAnimationContext) -> Void,
    completionHandler: (() -> Void)? = nil
  ) {
    let ctx = NSAnimationContext()
    changes(ctx)
    completionHandler?()
  }

  public static func beginGrouping() {}
  public static func endGrouping() {}
}

open class NSWindow: NSResponder {
  public struct StyleMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let borderless = StyleMask([])
    public static let titled = StyleMask(rawValue: 1 << 0)
    public static let closable = StyleMask(rawValue: 1 << 1)
    public static let miniaturizable = StyleMask(rawValue: 1 << 2)
    public static let resizable = StyleMask(rawValue: 1 << 3)
    public static let utilityWindow = StyleMask(rawValue: 1 << 4)
    public static let docModalWindow = StyleMask(rawValue: 1 << 6)
    public static let nonactivatingPanel = StyleMask(rawValue: 1 << 7)
    public static let hudWindow = StyleMask(rawValue: 1 << 13)
    public static let fullScreen = StyleMask(rawValue: 1 << 14)
    public static let fullSizeContentView = StyleMask(rawValue: 1 << 15)
  }

  public struct Level: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let normal = Level(rawValue: 0)
    public static let floating = Level(rawValue: 3)
    public static let submenu = Level(rawValue: 3)
    public static let tornOffMenu = Level(rawValue: 3)
    public static let modalPanel = Level(rawValue: 8)
    public static let mainMenu = Level(rawValue: 24)
    public static let statusBar = Level(rawValue: 25)
    public static let popUpMenu = Level(rawValue: 101)
    public static let screenSaver = Level(rawValue: 1000)
  }

  public struct CollectionBehavior: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let `default` = CollectionBehavior([])
    public static let canJoinAllSpaces = CollectionBehavior(rawValue: 1 << 0)
    public static let moveToActiveSpace = CollectionBehavior(rawValue: 1 << 1)
    public static let managed = CollectionBehavior(rawValue: 1 << 2)
    public static let transient = CollectionBehavior(rawValue: 1 << 3)
    public static let stationary = CollectionBehavior(rawValue: 1 << 4)
    public static let participatesInCycle = CollectionBehavior(rawValue: 1 << 5)
    public static let ignoresCycle = CollectionBehavior(rawValue: 1 << 6)
    public static let fullScreenPrimary = CollectionBehavior(rawValue: 1 << 7)
    public static let fullScreenAuxiliary = CollectionBehavior(rawValue: 1 << 8)
    public static let fullScreenNone = CollectionBehavior(rawValue: 1 << 9)
  }

  public enum TitleVisibility: Int, Sendable {
    case visible = 0
    case hidden = 1
  }

  public enum ToolbarStyle: Int, Sendable {
    case automatic = 0
    case expanded = 1
    case preference = 2
    case unified = 3
    case unifiedCompact = 4
  }

  public enum TitlebarSeparatorStyle: Int, Sendable {
    case automatic = 0
    case none = 1
    case line = 2
    case shadow = 3
  }

  public enum AnimationBehavior: Int, Sendable {
    case `default` = 0
    case none = 2
    case documentWindow = 3
    case utilityWindow = 4
    case alertPanel = 5
  }

  public struct OcclusionState: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let visible = OcclusionState(rawValue: 1 << 1)
  }

  public enum ButtonType: UInt, Sendable {
    case closeButton = 0
    case miniaturizeButton = 1
    case zoomButton = 2
  }

  public enum WindowsBackdropKind: Int, Sendable {
    case none = 1
    case mica = 2
    case acrylic = 3
    case micaAlt = 4
  }

  public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
  public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
  public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")
  public static let didResignMainNotification = Notification.Name("NSWindowDidResignMainNotification")
  public static let didMoveNotification = Notification.Name("NSWindowDidMoveNotification")
  public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
  public static let willCloseNotification = Notification.Name("NSWindowWillCloseNotification")
  public static let didChangeOcclusionStateNotification = Notification.Name("NSWindowDidChangeOcclusionStateNotification")
  public static let didChangeScreenNotification = Notification.Name("NSWindowDidChangeScreenNotification")

  public var identifier: NSUserInterfaceItemIdentifier?
  public weak var delegate: (any NSWindowDelegate)?
  public var styleMask: StyleMask {
    didSet { syncStyleToNative() }
  }
  public var title: String = "" {
    didSet {
      #if !os(macOS)
        nativeWindow?.setTitle(title)
      #endif
    }
  }
  public var subtitle: String = ""
  public var level: Level = .normal {
    didSet {
      #if !os(macOS)
        nativeWindow?.setAlwaysOnTop(level.rawValue > Level.normal.rawValue)
      #endif
    }
  }
  public var collectionBehavior: CollectionBehavior = [] {
    didSet {
      #if !os(macOS)
        if collectionBehavior.contains(.canJoinAllSpaces) {
          nativeWindow?.setVisibleOnAllWorkspaces(true)
        }
      #endif
    }
  }
  public var titleVisibility: TitleVisibility = .visible
  public var titlebarAppearsTransparent: Bool = false
  public var toolbarStyle: ToolbarStyle = .automatic
  public var titlebarSeparatorStyle: TitlebarSeparatorStyle = .automatic
  public var toolbar: NSToolbar?
  public var animationBehavior: AnimationBehavior = .default
  public var isOpaque: Bool = true {
    didSet { syncBackgroundToNative() }
  }
  public var backgroundColor: NSColor = .windowBackgroundColor {
    didSet { syncBackgroundToNative() }
  }
  public var hasShadow: Bool = true {
    didSet {
      #if !os(macOS)
        let isFrameless = !styleMask.contains(.titled)
        let isTransparent = !isOpaque || backgroundColor.resolved(for: effectiveAppearance).a < 0.05
        nativeWindow?.setHasShadow(isFrameless && isTransparent ? false : hasShadow)
        contentView?.viewDidChangeEffectiveAppearance()
      #endif
    }
  }
  public var alphaValue: CGFloat = 1.0 {
    didSet {
      #if !os(macOS)
        nativeWindow?.setOpacity(Float(min(max(alphaValue, 0), 1)))
      #endif
    }
  }
  public var ignoresMouseEvents: Bool = false {
    didSet {
      #if !os(macOS)
        _ = nativeWindow?.setIgnoreMouseEvents(ignoresMouseEvents, forward: true)
      #endif
    }
  }
  public var acceptsMouseMovedEvents: Bool = true
  public var isMovable: Bool = true {
    didSet {
      #if !os(macOS)
        nativeWindow?.setMovable(isMovable)
      #endif
    }
  }
  public var isMovableByWindowBackground: Bool = false
  public var isReleasedWhenClosed: Bool = false
  public var isRestorable: Bool = false
  public var hidesOnDeactivate: Bool = false
  public var minSize: NSSize = .zero {
    didSet {
      #if !os(macOS)
        nativeWindow?.setMinimumSize(NativeAPI.Size(width: Double(minSize.width), height: Double(minSize.height)))
      #endif
    }
  }
  public var maxSize: NSSize = NSSize(width: 10000, height: 10000) {
    didSet {
      #if !os(macOS)
        nativeWindow?.setMaximumSize(NativeAPI.Size(width: Double(maxSize.width), height: Double(maxSize.height)))
      #endif
    }
  }
  public var contentMinSize: NSSize {
    get { minSize }
    set { minSize = newValue }
  }
  public var contentMaxSize: NSSize {
    get { maxSize }
    set { maxSize = newValue }
  }
  public private(set) var isMiniaturized: Bool = false

  open func deminiaturize(_ sender: Any?) {
    isMiniaturized = false
    #if !os(macOS)
      nativeWindow?.restore()
    #endif
  }

  open func toggleFullScreen(_ sender: Any?) {
    if styleMask.contains(.fullScreen) {
      styleMask.remove(.fullScreen)
    } else {
      styleMask.insert(.fullScreen)
    }
    zoom(sender)
  }
  public var appearance: NSAppearance? {
    didSet { contentView?.viewDidChangeEffectiveAppearance() }
  }
  public var effectiveAppearance: NSAppearance {
    appearance ?? NSApplication.shared.effectiveAppearance
  }
  public private(set) var childWindows: [NSWindow]? = []
  public private(set) weak var parent: NSWindow?
  private var autosaveName: String?
  private let sharedFieldEditor: NSTextView = {
    let tv = NSTextView(frame: .zero)
    tv.isFieldEditorProxy = true
    tv.isFieldEditor = true
    return tv
  }()
  private weak var explicitFirstResponder: NSResponder?

  public var firstResponder: NSResponder? {
    #if os(Windows)
      if let explicit = explicitFirstResponder { return explicit }
      if let focused = cak_focused_hwnd(), cak_is_edit_hwnd(focused) != 0 {
        return sharedFieldEditor
      }
      return self
    #else
      return explicitFirstResponder ?? sharedFieldEditor
    #endif
  }

  internal func adoptFirstResponderFromNative(_ responder: NSResponder) {
    guard explicitFirstResponder !== responder else { return }
    let previous = explicitFirstResponder
    explicitFirstResponder = responder
    _ = previous?.resignFirstResponder()
    _ = responder.becomeFirstResponder()
  }

  internal func releaseFirstResponderFromNative(_ responder: NSResponder) {
    guard explicitFirstResponder === responder else { return }
    explicitFirstResponder = nil
    _ = responder.resignFirstResponder()
  }

  fileprivate var storedFrame: NSRect
  private var suppressMoveCallbacks = false
  private var hasPendingNativeBounds = false
  private var isCommittingNativeBounds = false
  private var pendingContentSize: NSSize = .zero
  #if os(Windows)
    private static let transparentEnvelopeBleed: Double = 6.0
    private var nativeEnvelopeTopLeft: (x: Double, y: Double, width: Double, height: Double)?
    public private(set) var nativeContentOffset: NSPoint = .zero
  #endif
  public private(set) var isVisible: Bool = false
  public internal(set) var isKeyWindow: Bool = false
  public internal(set) var isMainWindow: Bool = false
  public var occlusionState: OcclusionState { isVisible ? [.visible] : [] }
  public let windowNumber: Int

  nonisolated(unsafe) private static var nextWindowNumber: Int = 100

  #if !os(macOS)
    nonisolated(unsafe) public private(set) var nativeWindow: NativeAPI.Window?
    nonisolated(unsafe) private var nativeListenerId: ListenerId?
  #endif

  /// Hook invoked whenever `contentView` is assigned or resized so `NSHostingView` attaches cleanly.
  public var onContentViewChanged: ((NSView?) -> Void)?
  /// Hook invoked when the window orders to the front (used by surface-hosted backends like HarmonyOS).
  public var onDidOrderFront: (() -> Void)?
  #if CROSS_SWIFTUI_HARMONY
    internal var _harmonyAssignedSurfaceId: Int?
    public var harmonySurfaceId: Int {
      HarmonyWindowBridge.surfaceId(for: self)
    }
    /// Hook notifying SwiftUIHarmony of active window transparency, fixed content dimensions, and shadow bleed.
    public static var _harmonyWindowSurfaceHandler: ((_ surfaceId: Int, _ isTransparent: Bool, _ width: Double, _ height: Double, _ bleed: Double) -> Void)?
  #endif

  public var contentView: NSView? {
    didSet {
      oldValue?.window = nil
      if let view = contentView {
        view.frame = NSRect(origin: .zero, size: contentLayoutRect.size)
        view.window = self
      }
      onContentViewChanged?(contentView)
    }
  }

  public var contentViewController: NSViewController? {
    didSet {
      contentView = contentViewController?.view
    }
  }

  public var frame: NSRect {
    get {
      if hasPendingNativeBounds {
        return storedFrame
      }
      #if os(Windows)
        if nativeEnvelopeTopLeft != nil {
          return storedFrame
        }
      #endif
      #if !os(macOS)
        if let nw = nativeWindow {
          let b = nw.bounds
          if b.width > 0 && b.height > 0 {
            return CrossAppKitCoordinates.rectFromNativeTopLeft(
              x: b.x, y: b.y, width: b.width, height: b.height
            )
          }
        }
      #endif
      return storedFrame
    }
    set {
      setFrame(newValue, display: true)
    }
  }

  public var contentLayoutRect: NSRect {
    if hasPendingNativeBounds && pendingContentSize.width > 0 && pendingContentSize.height > 0 {
      return NSRect(origin: .zero, size: pendingContentSize)
    }
    #if os(Windows)
      if nativeEnvelopeTopLeft != nil {
        let scale = CGFloat(snappedWindowScale())
        let w = max(1.0, (storedFrame.size.width * scale).rounded(.toNearestOrAwayFromZero)) / scale
        let h = max(1.0, (storedFrame.size.height * scale).rounded(.toNearestOrAwayFromZero)) / scale
        return NSRect(origin: .zero, size: NSSize(width: w, height: h))
      }
    #endif
    #if !os(macOS)
      if let nw = nativeWindow {
        let cs = nw.contentSize
        if cs.width > 0 && cs.height > 0 {
          return NSRect(x: 0, y: 0, width: CGFloat(cs.width), height: CGFloat(cs.height))
        }
      }
    #endif
    return NSRect(origin: .zero, size: storedFrame.size)
  }

  public var screen: NSScreen? {
    let center = NSPoint(x: frame.midX, y: frame.midY)
    return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
  }

  open var canBecomeKey: Bool { true }
  open var canBecomeMain: Bool { styleMask.contains(.titled) }

  public init(
    contentRect: NSRect,
    styleMask style: StyleMask,
    backing backingStoreType: NSBackingStoreType,
    defer flag: Bool
  ) {
    self.storedFrame = contentRect
    self.styleMask = style
    Self.nextWindowNumber += 1
    self.windowNumber = Self.nextWindowNumber
    super.init()

    #if !os(macOS) && !CROSS_SWIFTUI_HARMONY
      _ = NativeAPI.Application.shared.isRunning()
      if let nw = NativeAPI.Window.create() {
        self.nativeWindow = nw
        syncStyleToNative()
        let top = CrossAppKitCoordinates.rectToNativeTopLeft(contentRect)
        nw.setBounds(NativeAPI.Rectangle(x: top.x, y: top.y, width: top.width, height: top.height))
        nativeListenerId = nw.addListener { [weak self] event in
          nonisolated(unsafe) let boxSelf = self
          nonisolated(unsafe) let boxEvent = event
          _performOnMainActor {
            boxSelf?.handleNativeWindowEvent(boxEvent)
          }
        }
      }
    #endif
    NSApplication.shared.registerWindow(self)
  }

  public override init?(coder: NSCoder) {
    self.storedFrame = .zero
    self.styleMask = []
    Self.nextWindowNumber += 1
    self.windowNumber = Self.nextWindowNumber
    super.init(coder: coder)
  }

  public convenience override init() {
    self.init(
      contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
  }

  deinit {
    #if !os(macOS)
      if let id = nativeListenerId {
        _ = nativeWindow?.removeListener(id)
      }
    #endif
  }

  private func syncStyleToNative() {
    #if !os(macOS)
      guard let nw = nativeWindow else { return }
      let isFrameless = !styleMask.contains(.titled)
      _ = nw.setFrameless(isFrameless)
      nw.setResizable(styleMask.contains(.resizable))
      nw.setMinimizable(styleMask.contains(.miniaturizable))
      nw.setMaximizable(styleMask.contains(.resizable))
      nw.setClosable(styleMask.contains(.closable))
      let isNonActivating = !canBecomeKey
      nw.setNonActivating(isNonActivating)
      let hideFromTaskbar = isFrameless || styleMask.contains(.nonactivatingPanel)
      let isTransparent = !isOpaque || backgroundColor.resolved(for: effectiveAppearance).a < 0.05
      if hideFromTaskbar {
        nw.setVisibleInTaskbar(false)
        _ = nw.setCornerPreference(isFrameless && isTransparent ? .doNotRound : .round)
      } else {
        nw.setVisibleInTaskbar(true)
      }
      if isFrameless && isTransparent {
        nw.setHasShadow(false)
      }
      #if os(Windows)
        if let hwnd = nw.nativeObject {
          cak_window_apply_frameless(hwnd, isFrameless ? 1 : 0)
          cak_window_set_tool_style(hwnd, hideFromTaskbar ? 1 : 0, isNonActivating ? 1 : 0)
        }
        if isFrameless && isTransparent {
          applyWindowsBackdrop(.none)
        }
      #endif
    #endif
  }

  public func syncBackgroundToNative() {
    #if !os(macOS)
      guard let nw = nativeWindow else { return }
      let c = backgroundColor.resolved(for: effectiveAppearance)
      let isFrameless = !styleMask.contains(.titled)
      let isTransparent = !isOpaque || c.a < 0.05
      if isFrameless && isTransparent {
        nw.setHasShadow(false)
        _ = nw.setCornerPreference(.doNotRound)
        nw.setBackgroundColor(NativeAPI.Color(r: 0, g: 0, b: 0, a: 0))
        #if os(Windows)
          if let hwnd = nw.nativeObject {
            cak_window_apply_frameless(hwnd, 1)
          }
        #endif
        applyWindowsBackdrop(.none)
        return
      }
      nw.setBackgroundColor(NativeAPI.Color(
        r: UInt8(clamping: Int((c.r * 255).rounded())),
        g: UInt8(clamping: Int((c.g * 255).rounded())),
        b: UInt8(clamping: Int((c.b * 255).rounded())),
        a: UInt8(clamping: Int((c.a * 255).rounded()))
      ))
    #endif
  }

  public func applyWindowsBackdrop(_ kind: WindowsBackdropKind) {
    #if os(Windows)
      guard let hwnd = nativeWindow?.nativeObject else { return }
      let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      cak_window_set_backdrop(hwnd, Int32(kind.rawValue), isDark ? 1 : 0)
    #endif
  }

  @MainActor internal static var _suppressResignKeyCount: Int = 0

  #if !os(macOS)
    private func handleNativeWindowEvent(_ event: NativeAPI.WindowEvent) {
      switch event {
      case .focused:
        becomeKey()
      case .blurred:
        #if os(Windows)
          let bgPasting = cak_is_background_pasting() != 0
        #else
          let bgPasting = false
        #endif
        if isKeyWindow && Self._suppressResignKeyCount == 0 && !bgPasting { resignKey() }
      case .moved(_, let newPos):
        let currentSize = storedFrame.size
        #if os(Windows)
          if let env = nativeEnvelopeTopLeft {
            nativeEnvelopeTopLeft = (newPos.x, newPos.y, env.width, env.height)
            storedFrame = CrossAppKitCoordinates.rectFromNativeTopLeft(
              x: newPos.x + Double(nativeContentOffset.x),
              y: newPos.y + Double(nativeContentOffset.y),
              width: Double(currentSize.width),
              height: Double(currentSize.height)
            )
          } else {
            storedFrame = CrossAppKitCoordinates.rectFromNativeTopLeft(
              x: newPos.x, y: newPos.y, width: Double(currentSize.width), height: Double(currentSize.height)
            )
          }
        #else
          storedFrame = CrossAppKitCoordinates.rectFromNativeTopLeft(
            x: newPos.x, y: newPos.y, width: Double(currentSize.width), height: Double(currentSize.height)
          )
        #endif
        if !suppressMoveCallbacks {
          let note = Notification(name: Self.didMoveNotification, object: self)
          NotificationCenter.default.post(note)
          delegate?.windowDidMove(note)
        }
      case .resized(_, let newSize):
        #if os(Windows)
          let usesEnv = nativeEnvelopeTopLeft != nil
        #else
          let usesEnv = false
        #endif
        if !usesEnv {
          storedFrame.size = NSSize(width: CGFloat(newSize.width), height: CGFloat(newSize.height))
          if !isCommittingNativeBounds {
            let cs = contentLayoutRect.size
            contentView?.frame = NSRect(origin: .zero, size: cs)
          }
        }
        let note = Notification(name: Self.didResizeNotification, object: self)
        NotificationCenter.default.post(note)
        delegate?.windowDidResize(note)
      case .closeRequested(_, let req):
        if let should = delegate?.windowShouldClose(self), !should {
          _ = req?.cancel()
          return
        }
        if !isReleasedWhenClosed {
          _ = req?.cancel()
          close()
        }
      case .closed:
        isVisible = false
        isKeyWindow = false
        let note = Notification(name: Self.willCloseNotification, object: self)
        NotificationCenter.default.post(note)
        delegate?.windowWillClose(note)
      case .occlusionChanged:
        let note = Notification(name: Self.didChangeOcclusionStateNotification, object: self)
        NotificationCenter.default.post(note)
        delegate?.windowDidChangeOcclusionState(note)
      default:
        break
      }
    }
  #endif

  #if os(Windows)
    private var usesTransparentNativeEnvelope: Bool {
      guard !styleMask.contains(.titled) else { return false }
      let alpha = backgroundColor.resolved(for: effectiveAppearance).a
      return !isOpaque || alpha < 0.05
    }

    private func snappedWindowScale() -> Double {
      let center = NSPoint(x: storedFrame.midX, y: storedFrame.midY)
      let scr = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
      return Double(max(1.0, scr?.backingScaleFactor ?? 1.0))
    }

    private func computeTransparentEnvelope(
      for frameRect: NSRect,
      pureMove: Bool
    ) -> (env: NativeAPI.Rectangle, contentSize: NSSize, offset: NSPoint) {
      let scale = snappedWindowScale()
      let top = CrossAppKitCoordinates.rectToNativeTopLeft(frameRect)
      let bleed = Self.transparentEnvelopeBleed
      let snappedW = max(1.0, (top.width * scale).rounded(.toNearestOrAwayFromZero)) / scale
      let snappedH = max(1.0, (top.height * scale).rounded(.toNearestOrAwayFromZero)) / scale
      let contentSize = NSSize(width: snappedW, height: snappedH)

      if pureMove, let cur = nativeEnvelopeTopLeft {
        let offX = Double(nativeContentOffset.x)
        let offY = Double(nativeContentOffset.y)
        let envX = ((top.x - offX) * scale).rounded(.toNearestOrAwayFromZero) / scale
        let envY = ((top.y - offY) * scale).rounded(.toNearestOrAwayFromZero) / scale
        let exactOffX = max(0.0, top.x - envX)
        let exactOffY = max(0.0, top.y - envY)
        return (
          NativeAPI.Rectangle(x: envX, y: envY, width: cur.width, height: cur.height),
          contentSize,
          NSPoint(x: exactOffX, y: exactOffY)
        )
      }

      if isVisible, let cur = nativeEnvelopeTopLeft {
        let candOffX = top.x - cur.x
        let candOffY = top.y - cur.y
        if candOffX >= 0.0 && candOffX <= bleed * 3.5
          && candOffY >= 0.0 && candOffY <= bleed * 3.5
        {
          let neededW = ((candOffX + snappedW + bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale
          let envW = max(cur.width, neededW)
          let envH = max(1.0, ((candOffY + snappedH + bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale)
          return (
            NativeAPI.Rectangle(x: cur.x, y: cur.y, width: envW, height: envH),
            contentSize,
            NSPoint(x: candOffX, y: candOffY)
          )
        }
      }

      let envX = ((top.x - bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale
      let envY = ((top.y - bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale
      let offX = max(0.0, top.x - envX)
      let offY = max(0.0, top.y - envY)
      let envW = max(1.0, ((offX + snappedW + bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale)
      let envH = max(1.0, ((offY + snappedH + bleed) * scale).rounded(.toNearestOrAwayFromZero) / scale)
      return (
        NativeAPI.Rectangle(x: envX, y: envY, width: envW, height: envH),
        contentSize,
        NSPoint(x: offX, y: offY)
      )
    }

    private func ensureTransparentEnvelopeBeforeShow() {
      guard usesTransparentNativeEnvelope, nativeEnvelopeTopLeft == nil, let nw = nativeWindow else {
        return
      }
      let prevSuppress = suppressMoveCallbacks
      let prevCommitting = isCommittingNativeBounds
      suppressMoveCallbacks = true
      isCommittingNativeBounds = true
      defer {
        suppressMoveCallbacks = prevSuppress
        isCommittingNativeBounds = prevCommitting
      }
      let calc = computeTransparentEnvelope(for: storedFrame, pureMove: false)
      nativeEnvelopeTopLeft = (calc.env.x, calc.env.y, calc.env.width, calc.env.height)
      nativeContentOffset = calc.offset
      contentView?.applySurfaceContentOffset(x: Double(calc.offset.x), y: Double(calc.offset.y))
      nw.setBounds(calc.env)
      contentView?.frame = NSRect(origin: .zero, size: calc.contentSize)
    }
  #endif

  open func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool = false) {
    let previousFrame = storedFrame
    storedFrame = frameRect
    #if os(Windows)
      if usesTransparentNativeEnvelope, let nw = nativeWindow {
        if hasPendingNativeBounds,
          abs(frameRect.origin.x - previousFrame.origin.x) < 1e-4,
          abs(frameRect.origin.y - previousFrame.origin.y) < 1e-4,
          abs(frameRect.width - previousFrame.width) < 1e-4,
          abs(frameRect.height - previousFrame.height) < 1e-4
        {
          return
        }
        let movedOrigin =
          abs(frameRect.origin.x - previousFrame.origin.x) > 1e-4
          || abs(frameRect.origin.y - previousFrame.origin.y) > 1e-4
        let sameSize =
          abs(frameRect.width - previousFrame.width) < 0.01
          && abs(frameRect.height - previousFrame.height) < 0.01
        let pureMove =
          !hasPendingNativeBounds
          && nativeEnvelopeTopLeft != nil
          && (!flag || (sameSize && movedOrigin))
        let calc = computeTransparentEnvelope(for: frameRect, pureMove: pureMove)
        if flag && isVisible && !animateFlag, let cv = contentView {
          hasPendingNativeBounds = true
          pendingContentSize = calc.contentSize
          let commitBounds = { [weak self] in
            guard let self else { return }
            self.hasPendingNativeBounds = false
            self.nativeEnvelopeTopLeft = (calc.env.x, calc.env.y, calc.env.width, calc.env.height)
            self.nativeContentOffset = calc.offset
            let prevSuppress = self.suppressMoveCallbacks
            let prevCommitting = self.isCommittingNativeBounds
            self.suppressMoveCallbacks = true
            self.isCommittingNativeBounds = true
            defer {
              self.suppressMoveCallbacks = prevSuppress
              self.isCommittingNativeBounds = prevCommitting
            }
            nw.setBounds(calc.env)
            self.contentView?.frame = NSRect(origin: .zero, size: calc.contentSize)
          }
          if cv.applyWindowFrameChange(
            contentSize: calc.contentSize,
            envelopeSize: NSSize(width: calc.env.width, height: calc.env.height),
            contentOffset: calc.offset,
            display: flag,
            commitNativeBounds: commitBounds
          ) {
            return
          }
          hasPendingNativeBounds = false
        }
        let prevSuppress = suppressMoveCallbacks
        let prevCommitting = isCommittingNativeBounds
        suppressMoveCallbacks = true
        isCommittingNativeBounds = true
        defer {
          suppressMoveCallbacks = prevSuppress
          isCommittingNativeBounds = prevCommitting
        }
        nativeEnvelopeTopLeft = (calc.env.x, calc.env.y, calc.env.width, calc.env.height)
        nativeContentOffset = calc.offset
        contentView?.applySurfaceContentOffset(x: Double(calc.offset.x), y: Double(calc.offset.y))
        if !animateFlag || !nw.animateBounds(calc.env) {
          nw.setBounds(calc.env)
        }
        contentView?.frame = NSRect(origin: .zero, size: calc.contentSize)
        if flag && isVisible {
          contentView?.layoutSubtreeIfNeeded()
        }
        return
      }
      nativeEnvelopeTopLeft = nil
      nativeContentOffset = .zero
      if flag && isVisible && !animateFlag, let nw = nativeWindow, let cv = contentView {
        let top = CrossAppKitCoordinates.rectToNativeTopLeft(frameRect)
        let r = NativeAPI.Rectangle(x: top.x, y: top.y, width: max(1, top.width), height: max(1, top.height))
        let targetContentSize: NSSize
        if !styleMask.contains(.titled) {
          let scale = max(1.0, screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0)
          let snappedW = max(1.0, (frameRect.size.width * scale).rounded(.toNearestOrAwayFromZero)) / scale
          let snappedH = max(1.0, (frameRect.size.height * scale).rounded(.toNearestOrAwayFromZero)) / scale
          targetContentSize = NSSize(width: snappedW, height: snappedH)
        } else {
          let currentContent = contentLayoutRect.size
          let borderW = max(0, previousFrame.width - currentContent.width)
          let borderH = max(0, previousFrame.height - currentContent.height)
          targetContentSize = NSSize(
            width: max(1, frameRect.width - borderW),
            height: max(1, frameRect.height - borderH)
          )
        }
        hasPendingNativeBounds = true
        pendingContentSize = targetContentSize
        let commitBounds = { [weak self] in
          guard let self else { return }
          self.hasPendingNativeBounds = false
          let prevSuppress = self.suppressMoveCallbacks
          let prevCommitting = self.isCommittingNativeBounds
          self.suppressMoveCallbacks = true
          self.isCommittingNativeBounds = true
          defer {
            self.suppressMoveCallbacks = prevSuppress
            self.isCommittingNativeBounds = prevCommitting
          }
          nw.setBounds(r)
          self.contentView?.frame = NSRect(origin: .zero, size: self.contentLayoutRect.size)
        }
        if cv.applyWindowFrameChange(
          contentSize: targetContentSize,
          display: flag,
          commitNativeBounds: commitBounds
        ) {
          return
        }
        hasPendingNativeBounds = false
      }
    #endif
    suppressMoveCallbacks = true
    defer { suppressMoveCallbacks = false }
    #if CROSS_SWIFTUI_HARMONY
      HarmonyWindowBridge.syncFrame(for: self)
    #elseif !os(macOS)
      if let nw = nativeWindow {
        let top = CrossAppKitCoordinates.rectToNativeTopLeft(frameRect)
        let r = NativeAPI.Rectangle(x: top.x, y: top.y, width: max(1, top.width), height: max(1, top.height))
        if !animateFlag || !nw.animateBounds(r) {
          nw.setBounds(r)
        }
      }
    #endif
    contentView?.frame = NSRect(origin: .zero, size: contentLayoutRect.size)
    if flag && isVisible {
      contentView?.layoutSubtreeIfNeeded()
    }
  }

  open func setFrameOrigin(_ point: NSPoint) {
    var r = frame
    r.origin = point
    setFrame(r, display: false)
  }

  open func setContentSize(_ size: NSSize) {
    #if os(Windows)
      if usesTransparentNativeEnvelope {
        var f = storedFrame
        f.origin.y -= (size.height - f.size.height)
        f.size = size
        setFrame(f, display: isVisible)
        return
      }
    #endif
    storedFrame.size = size
    #if CROSS_SWIFTUI_HARMONY
      HarmonyWindowBridge.syncFrame(for: self)
    #elseif !os(macOS)
      nativeWindow?.setContentSize(NativeAPI.Size(width: Double(max(1, size.width)), height: Double(max(1, size.height))))
    #endif
    contentView?.frame = NSRect(origin: .zero, size: size)
  }

  open func center() {
    #if !os(macOS)
      nativeWindow?.center()
    #endif
    if let scr = NSScreen.main {
      let vf = scr.visibleFrame
      let origin = NSPoint(
        x: vf.midX - storedFrame.width / 2,
        y: vf.midY - storedFrame.height / 2
      )
      setFrameOrigin(origin)
    }
  }

  open func makeKeyAndOrderFront(_ sender: Any?) {
    let wasVisible = isVisible
    #if os(Windows)
      ensureTransparentEnvelopeBeforeShow()
    #endif
    isVisible = true
    #if CROSS_SWIFTUI_HARMONY
      contentView?.layoutSubtreeIfNeeded()
      onDidOrderFront?()
      HarmonyWindowBridge.openOrShow(self, focus: canBecomeKey)
      becomeKey()
    #else
      #if !os(macOS)
        if canBecomeKey {
          nativeWindow?.setNonActivating(false)
          #if os(Windows)
            if let hwnd = nativeWindow?.nativeObject {
              let isFrameless = !styleMask.contains(.titled)
              let hideFromTaskbar = isFrameless || styleMask.contains(.nonactivatingPanel)
              cak_window_apply_frameless(hwnd, isFrameless ? 1 : 0)
              cak_window_set_tool_style(hwnd, hideFromTaskbar ? 1 : 0, 0)
            }
          #endif
        }
        contentView?.layoutSubtreeIfNeeded()
        nativeWindow?.show()
        #if os(Windows)
          if !wasVisible {
            contentView?.flushNativeWindowPaint()
          }
        #endif
        if canBecomeKey { nativeWindow?.focus() }
      #endif
      becomeKey()
      onDidOrderFront?()
    #endif
    if let name = autosaveName { saveFrame(named: name) }
  }

  open func makeKey() {
    guard canBecomeKey else { return }
    #if CROSS_SWIFTUI_HARMONY
      HarmonyWindowBridge.focusWindow(self)
    #elseif !os(macOS)
      nativeWindow?.focus()
    #endif
    becomeKey()
  }

  open func orderFront(_ sender: Any?) {
    let wasVisible = isVisible
    #if os(Windows)
      ensureTransparentEnvelopeBeforeShow()
    #endif
    isVisible = true
    #if CROSS_SWIFTUI_HARMONY
      contentView?.layoutSubtreeIfNeeded()
      onDidOrderFront?()
      HarmonyWindowBridge.openOrShow(self, focus: false)
    #else
      #if !os(macOS)
        #if os(Windows)
          if let hwnd = nativeWindow?.nativeObject, !styleMask.contains(.titled) {
            cak_window_apply_frameless(hwnd, 1)
          }
        #endif
        contentView?.layoutSubtreeIfNeeded()
        if styleMask.contains(.nonactivatingPanel) {
          nativeWindow?.showInactive()
        } else {
          nativeWindow?.show()
        }
        #if os(Windows)
          if !wasVisible {
            contentView?.flushNativeWindowPaint()
          }
        #endif
      #endif
      onDidOrderFront?()
    #endif
  }

  open func orderFrontRegardless() {
    let wasVisible = isVisible
    #if os(Windows)
      ensureTransparentEnvelopeBeforeShow()
    #endif
    isVisible = true
    #if CROSS_SWIFTUI_HARMONY
      onDidOrderFront?()
      if !wasVisible {
        HarmonyWindowBridge.openOrShow(self, focus: canBecomeKey && isKeyWindow)
      } else {
        HarmonyWindowBridge.syncFrame(for: self)
        if canBecomeKey && isKeyWindow {
          HarmonyWindowBridge.focusWindow(self)
        }
      }
    #else
      #if !os(macOS)
        #if os(Windows)
          if let hwnd = nativeWindow?.nativeObject, !styleMask.contains(.titled) {
            cak_window_apply_frameless(hwnd, 1)
          }
        #endif
        contentView?.layoutSubtreeIfNeeded()
        if canBecomeKey && isKeyWindow {
          nativeWindow?.show()
        } else {
          nativeWindow?.showInactive()
        }
        #if os(Windows)
          if !wasVisible {
            contentView?.flushNativeWindowPaint()
          }
        #endif
      #endif
      onDidOrderFront?()
    #endif
  }

  open func orderOut(_ sender: Any?) {
    isVisible = false
    #if os(Windows)
      nativeEnvelopeTopLeft = nil
      nativeContentOffset = .zero
      if let hwnd = nativeWindow?.nativeObject {
        cak_window_relinquish_focus(hwnd)
      }
    #endif
    if isKeyWindow { resignKey() }
    #if CROSS_SWIFTUI_HARMONY
      HarmonyWindowBridge.hideWindow(self)
    #elseif !os(macOS)
      nativeWindow?.hide()
    #endif
  }

  open func close() {
    let note = Notification(name: Self.willCloseNotification, object: self)
    NotificationCenter.default.post(note)
    delegate?.windowWillClose(note)
    orderOut(nil)
    #if CROSS_SWIFTUI_HARMONY
      HarmonyWindowBridge.destroyWindowIfSecondary(self)
    #endif
    if isReleasedWhenClosed {
      #if !os(macOS)
        _ = nativeWindow?.close()
      #endif
      NSApplication.shared.unregisterWindow(self)
    }
  }

  open func performClose(_ sender: Any?) {
    if let should = delegate?.windowShouldClose(self), !should { return }
    close()
  }

  open func miniaturize(_ sender: Any?) {
    isMiniaturized = true
    #if os(Windows)
      if let hwnd = nativeWindow?.nativeObject {
        _ = cak_control_window(UInt64(UInt(bitPattern: hwnd)), 1)
      }
    #endif
  }

  open func zoom(_ sender: Any?) {
    #if os(Windows)
      if let hwnd = nativeWindow?.nativeObject {
        _ = cak_control_window(UInt64(UInt(bitPattern: hwnd)), 2)
      }
    #endif
  }

  open func becomeKey() {
    guard canBecomeKey, !isKeyWindow else { return }
    for other in NSApplication.shared.windows where other !== self && other.isKeyWindow {
      other.resignKey()
    }
    isKeyWindow = true
    if canBecomeMain { isMainWindow = true }
    let note = Notification(name: Self.didBecomeKeyNotification, object: self)
    NotificationCenter.default.post(note)
    delegate?.windowDidBecomeKey(note)
  }

  open func resignKey() {
    guard isKeyWindow else { return }
    isKeyWindow = false
    let note = Notification(name: Self.didResignKeyNotification, object: self)
    NotificationCenter.default.post(note)
    delegate?.windowDidResignKey(note)
  }

  @discardableResult
  open func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    let target = (responder === self) ? nil : responder
    let previous = explicitFirstResponder
    if previous === target, target != nil {
      #if !os(macOS)
        if let tv = target as? NSTextView, !tv.isFieldEditorProxy {
          tv.focusStandaloneNativeEditor()
        }
      #endif
      return true
    }
    if let prev = previous, !prev.resignFirstResponder() {
      return false
    }
    explicitFirstResponder = target
    if let next = target, !next.becomeFirstResponder() {
      explicitFirstResponder = previous
      return false
    }
    #if !os(macOS)
      if let tv = target as? NSTextView, !tv.isFieldEditorProxy {
        tv.focusStandaloneNativeEditor()
      } else if target == nil {
        #if os(Windows)
          if let hostHwnd = nativeWindow?.contentView?.nativeObject ?? nativeWindow?.nativeObject {
            cak_focus_hwnd(hostHwnd)
          }
        #endif
        if let prevTV = previous as? NSTextView, !prevTV.isFieldEditorProxy {
          prevTV.handleStandaloneFocusLoss()
        }
      }
    #endif
    return true
  }

  public var _eventReachedBaseSendEvent: Bool = false
  public var _suppressLocalMonitorInSendEvent: Bool = false

  open func sendEvent(_ event: NSEvent) {
    _eventReachedBaseSendEvent = true
    let routed: NSEvent
    if _suppressLocalMonitorInSendEvent {
      routed = event
    } else {
      guard let r = NSEvent.dispatchLocalMonitors(event) else { return }
      routed = r
    }
    switch routed.type {
    case .keyDown: firstResponder?.keyDown(with: routed)
    case .keyUp: firstResponder?.keyUp(with: routed)
    case .flagsChanged: firstResponder?.flagsChanged(with: routed)
    case .leftMouseDown: contentView?.mouseDown(with: routed)
    case .leftMouseUp: contentView?.mouseUp(with: routed)
    case .leftMouseDragged: contentView?.mouseDragged(with: routed)
    case .rightMouseDown: contentView?.rightMouseDown(with: routed)
    case .rightMouseUp: contentView?.rightMouseUp(with: routed)
    case .mouseMoved: contentView?.mouseMoved(with: routed)
    case .scrollWheel: contentView?.scrollWheel(with: routed)
    default: break
    }
  }

  open func performDrag(with event: NSEvent) {
    #if !os(macOS)
      nativeWindow?.startDragging()
    #endif
  }

  open func display() {}
  open func displayIfNeeded() {}

  public func trackEvents(
    matching mask: NSEvent.EventTypeMask,
    timeout: TimeInterval,
    mode: RunLoop.Mode,
    handler trackingHandler: (NSEvent?, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {
    #if os(Windows)
      let startTime = Date.timeIntervalSinceReferenceDate
      let deadline = timeout.isFinite && timeout < 1e9 ? (startTime + max(0, timeout)) : Double.greatestFiniteMagnitude
      var stop = ObjCBool(false)
      while !stop.boolValue && Date.timeIntervalSinceReferenceDate < deadline {
        var evKind: Int32 = 0
        var sx: Double = 0
        var sy: Double = 0
        let got = cak_pump_mouse_tracking_step(&evKind, &sx, &sy)
        if got == 0 { continue }
        let screenPt = NSEvent.mouseLocation
        let winPt = convertPoint(fromScreen: screenPt)
        let mods = NSEvent.modifierFlags
        if evKind == 1 {
          if mask.contains(.leftMouseDragged) {
            let ev = NSEvent(
              type: .leftMouseDragged,
              locationInWindow: winPt,
              modifierFlags: mods,
              windowNumber: windowNumber,
              window: self,
              clickCount: 1
            )
            NSApplication.shared.currentEvent = ev
            trackingHandler(ev, &stop)
          }
        } else if evKind == 2 {
          if mask.contains(.leftMouseUp) {
            let ev = NSEvent(
              type: .leftMouseUp,
              locationInWindow: winPt,
              modifierFlags: mods,
              windowNumber: windowNumber,
              window: self,
              clickCount: 1
            )
            NSApplication.shared.currentEvent = ev
            trackingHandler(ev, &stop)
          }
          break
        }
      }
    #elseif !os(macOS)
      nativeWindow?.startDragging()
    #endif
  }

  public func addChildWindow(_ childWin: NSWindow, ordered place: NSWindowOrderingMode) {
    if childWindows?.contains(where: { $0 === childWin }) != true {
      childWindows?.append(childWin)
    }
    childWin.parent = self
    #if !os(macOS)
      _ = childWin.nativeWindow?.setParentWindow(self.nativeWindow)
    #endif
    childWin.orderFront(nil)
  }

  public func removeChildWindow(_ childWin: NSWindow) {
    childWindows?.removeAll { $0 === childWin }
    childWin.parent = nil
    #if !os(macOS)
      _ = childWin.nativeWindow?.setParentWindow(nil)
    #endif
  }

  public func convertToScreen(_ rect: NSRect) -> NSRect {
    let f = frame
    return NSRect(x: f.origin.x + rect.origin.x, y: f.origin.y + rect.origin.y, width: rect.width, height: rect.height)
  }

  public func convertFromScreen(_ rect: NSRect) -> NSRect {
    let f = frame
    return NSRect(x: rect.origin.x - f.origin.x, y: rect.origin.y - f.origin.y, width: rect.width, height: rect.height)
  }

  public func convertPoint(toScreen point: NSPoint) -> NSPoint {
    let f = frame
    return NSPoint(x: f.origin.x + point.x, y: f.origin.y + point.y)
  }

  public func convertPoint(fromScreen point: NSPoint) -> NSPoint {
    let f = frame
    return NSPoint(x: point.x - f.origin.x, y: point.y - f.origin.y)
  }

  public var inLiveResize: Bool = false

  public var mouseLocationOutsideOfEventStream: NSPoint {
    convertPoint(fromScreen: NSEvent.mouseLocation)
  }

  public static func windowNumber(
    at point: NSPoint, belowWindowWithWindowNumber windowNumber: Int
  ) -> Int {
    0
  }

  @discardableResult
  public func setFrameUsingName(_ name: String) -> Bool {
    let key = "NSWindow Frame \(name)"
    guard let str = UserDefaults.standard.string(forKey: key) else { return false }
    let parts = str.split(separator: " ").compactMap { Double($0) }
    guard parts.count == 4 && parts[2] > 50 && parts[3] > 50 else { return false }
    setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: false)
    return true
  }

  @discardableResult
  public func setFrameAutosaveName(_ name: String) -> Bool {
    autosaveName = name
    let key = "NSWindow Frame \(name)"
    if let str = UserDefaults.standard.string(forKey: key) {
      let parts = str.split(separator: " ").compactMap { Double($0) }
      if parts.count == 4 && parts[2] > 50 && parts[3] > 50 {
        setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: false)
      }
    }
    return true
  }

  private func saveFrame(named name: String) {
    let f = frame
    UserDefaults.standard.set("\(f.origin.x) \(f.origin.y) \(f.size.width) \(f.size.height)", forKey: "NSWindow Frame \(name)")
  }

  public func invalidateShadow() {
    if isVisible {
      contentView?.layoutSubtreeIfNeeded()
    }
  }
  public func standardWindowButton(_ b: ButtonType) -> NSButton? { nil }
  public func selectNextKeyView(_ sender: Any?) {
    _ = contentView?.moveKeyViewFocus(from: sender, backward: false)
  }
  public func selectPreviousKeyView(_ sender: Any?) {
    _ = contentView?.moveKeyViewFocus(from: sender, backward: true)
  }
  public func recalculateKeyViewLoop() {}
  public func animator() -> Self { self }
}

open class NSPanel: NSWindow {
  public var isFloatingPanel: Bool = false {
    didSet {
      if isFloatingPanel && level == .normal { level = .floating }
    }
  }
  public var becomesKeyOnlyIfNeeded: Bool = false
  public var worksWhenModal: Bool = false
}

open class NSWindowController: NSResponder {
  public var window: NSWindow?

  public init(window: NSWindow?) {
    self.window = window
    super.init()
  }

  public override init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public convenience override init() {
    self.init(window: nil)
  }

  open func windowWillLoad() {}
  open func windowDidLoad() {}
  open func loadWindow() {}

  open func showWindow(_ sender: Any?) {
    if window == nil {
      windowWillLoad()
      loadWindow()
      windowDidLoad()
    }
    window?.makeKeyAndOrderFront(sender)
  }

  open func close() {
    window?.close()
  }
}

open class NSViewController: NSResponder {
  private var _view: NSView?
  open var view: NSView {
    get {
      if let v = _view { return v }
      loadView()
      viewDidLoad()
      return _view!
    }
    set {
      _view = newValue
    }
  }

  public var title: String?
  public private(set) var children: [NSViewController] = []

  public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    super.init()
  }

  public convenience override init() {
    self.init(nibName: nil, bundle: nil)
  }

  public required override init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  open func loadView() {
    if _view == nil { _view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300)) }
  }

  open func viewDidLoad() {}
  open func viewWillAppear() {}
  open func viewDidAppear() {}
  open func viewWillDisappear() {}
  open func viewDidDisappear() {}

  public func addChild(_ childViewController: NSViewController) {
    children.append(childViewController)
  }

  public func removeFromParent() {}
}

@MainActor
open class NSSplitViewItem: NSObject {
  public let viewController: NSViewController
  public var isCollapsed: Bool = false
  public var canCollapse: Bool = true
  public var minimumThickness: CGFloat = 100
  public var maximumThickness: CGFloat = 1000
  public var holdingPriority: NSLayoutPriority = .defaultLow

  public init(viewController: NSViewController) {
    self.viewController = viewController
    super.init()
  }

  public convenience init(sidebarWithViewController viewController: NSViewController) {
    self.init(viewController: viewController)
  }

  public convenience init(contentListWithViewController viewController: NSViewController) {
    self.init(viewController: viewController)
  }

  public static func sidebar(withViewController viewController: NSViewController) -> NSSplitViewItem {
    NSSplitViewItem(viewController: viewController)
  }

  public static func contentList(withViewController viewController: NSViewController) -> NSSplitViewItem {
    NSSplitViewItem(viewController: viewController)
  }
}

open class NSSplitView: NSView {
  public typealias AutosaveName = String
  public var autosaveName: AutosaveName?
  public var isVertical: Bool = true
}

open class NSSplitViewController: NSViewController {
  public var splitView: NSSplitView = NSSplitView()
  public var splitViewItems: [NSSplitViewItem] = []

  public func addSplitViewItem(_ splitViewItem: NSSplitViewItem) {
    splitViewItems.append(splitViewItem)
    addChild(splitViewItem.viewController)
    view.addSubview(splitViewItem.viewController.view)
  }

  public func removeSplitViewItem(_ splitViewItem: NSSplitViewItem) {
    splitViewItems.removeAll { $0 === splitViewItem }
    splitViewItem.viewController.view.removeFromSuperview()
  }

  open func toggleSidebar(_ sender: Any?) {
    guard let first = splitViewItems.first else { return }
    first.isCollapsed.toggle()
  }
}

@MainActor
public protocol NSToolbarDelegate: NSObjectProtocol {}

@MainActor
open class NSToolbarItem: NSObject {
  public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let flexibleSpace = Identifier("NSToolbarFlexibleSpaceItem")
    public static let space = Identifier("NSToolbarSpaceItem")
    public static let toggleSidebar = Identifier("NSToolbarToggleSidebarItem")
    public static let sidebarTrackingSeparator = Identifier("NSToolbarSidebarTrackingSeparatorItem")
  }

  public let itemIdentifier: Identifier
  public var label: String = ""
  public var toolTip: String?
  public var view: NSView?
  public var image: NSImage?
  public weak var target: AnyObject?
  public var action: Selector?
  public var isBordered: Bool = false
  public var isNavigational: Bool = false

  public init(itemIdentifier: Identifier) {
    self.itemIdentifier = itemIdentifier
    super.init()
  }
}

@MainActor
public protocol NSSearchFieldDelegate: NSTextFieldDelegate {
  func searchFieldDidEndSearching(_ sender: NSSearchField)
}

extension NSSearchFieldDelegate {
  public func searchFieldDidEndSearching(_ sender: NSSearchField) {}
}

open class NSSearchField: NSTextField {}

open class NSSearchToolbarItem: NSToolbarItem {
  public var searchField: NSSearchField = NSSearchField(frame: .zero)
  public var resignsFirstResponderWithCancel: Bool = true
  public var preferredWidthForSearchField: CGFloat = 200
  public func beginSearchInteraction() {}
}

@MainActor
open class NSToolbar: NSObject {
  public enum DisplayMode: UInt, Sendable {
    case `default` = 0
    case iconAndLabel = 1
    case iconOnly = 2
    case labelOnly = 3
  }

  public typealias Identifier = String
  public let identifier: Identifier
  public weak var delegate: (any NSToolbarDelegate)?
  public var displayMode: DisplayMode = .default
  public var showsBaselineSeparator: Bool = false
  public var allowsUserCustomization: Bool = false
  public var allowsDisplayModeCustomization: Bool = false

  public init(identifier: Identifier) {
    self.identifier = identifier
    super.init()
  }
}

open class NSTitlebarAccessoryViewController: NSViewController {
  public enum LayoutAttribute: Int, Sendable {
    case bottom = 4
    case right = 2
    case leading = 5
    case trailing = 6
  }
  public var layoutAttribute: LayoutAttribute = .trailing
}
