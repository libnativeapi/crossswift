import CrossAppKit
import CrossUIKit
import Foundation
import NativeAPI
import Observation
import SwiftUIRuntime
#if !os(macOS)
  import Combine
#endif
#if os(Windows)
  import CSwiftUIWindows
#endif

// MARK: - Hosted NSView / UIView Bridge Protocols

protocol _HostedViewMount: AnyObject {
  func dismantle()
}

protocol _HostedViewBackendBridge: AnyObject {
  func createMount(frame: CGRect) -> (mount: any _HostedViewMount, nativeView: NativeAPI.View?)
  func updateMount(_ mount: any _HostedViewMount, frame: CGRect)
}

// MARK: - Color / Font / Image AppKit Interop

extension SwiftUIRuntime.Color {
  public init(nsColor: CrossAppKit.NSColor) {
    if nsColor.isDynamic {
      self.init { scheme in
        let app = CrossAppKit.NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let c = nsColor.resolved(for: app)
        return (Double(c.r), Double(c.g), Double(c.b), Double(c.a))
      }
    } else {
      let c = nsColor.resolved()
      self.init(red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
    }
  }

  public init(_ nsColor: CrossAppKit.NSColor) {
    self.init(nsColor: nsColor)
  }
}

extension CrossAppKit.NSColor {
  public convenience init(_ color: SwiftUIRuntime.Color) {
    self.init(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      let resolved = color.resolved(in: isDark ? .dark : .light)
      return CrossAppKit.NSColor(
        srgbRed: CGFloat(resolved.red),
        green: CGFloat(resolved.green),
        blue: CGFloat(resolved.blue),
        alpha: CGFloat(resolved.opacity)
      )
    }
  }
}

extension SwiftUIRuntime.Font {
  public init(_ font: CrossAppKit.NSFont) {
    self.init(
      size: font.pointSize,
      weight: Weight(font.fontDescriptor.weight.cssWeight),
      family: font.fontName
    )
  }
}

extension SwiftUIRuntime.Image {
  public init(nsImage: CrossAppKit.NSImage) {
    if let sym = nsImage.symbolName {
      self.init(systemName: sym)
    } else {
      let path = nsImage.ensureTemporaryFilePath() ?? ""
      let sz = SwiftUIRuntime.Size(width: Double(nsImage.size.width), height: Double(nsImage.size.height))
      self.init(filePath: path, size: sz, isTemplate: nsImage.isTemplate)
    }
  }
}

// MARK: - NSViewRepresentable

public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
  public let coordinator: Representable.Coordinator
  public let environment: EnvironmentValues
}

@MainActor @preconcurrency
public protocol NSViewRepresentable: SwiftUIRuntime.View where Body == _HostedViewPrimitive {
  associatedtype NSViewType: CrossAppKit.NSView
  associatedtype Coordinator = Void
  typealias Context = NSViewRepresentableContext<Self>

  func makeCoordinator() -> Coordinator
  func makeNSView(context: NSViewRepresentableContext<Self>) -> NSViewType
  func updateNSView(_ nsView: NSViewType, context: NSViewRepresentableContext<Self>)
  static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
  func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsView: NSViewType,
    context: NSViewRepresentableContext<Self>
  ) -> CGSize?
}

extension NSViewRepresentable where Coordinator == Void {
  public func makeCoordinator() -> Void { () }
}

extension NSViewRepresentable {
  public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}

  public func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsView: NSViewType,
    context: NSViewRepresentableContext<Self>
  ) -> CGSize? {
    nil
  }
}

private struct WeakHostingView {
  weak var view: NSView?
}

private enum HostingViewEnvironmentKey: EnvironmentKey {
  static let defaultValue = WeakHostingView(view: nil)
}

extension EnvironmentValues {
  fileprivate var _currentHostingView: WeakHostingView {
    get { self[HostingViewEnvironmentKey.self] }
    set { self[HostingViewEnvironmentKey.self] = newValue }
  }
}

private enum ActiveHostingContext {
  nonisolated(unsafe) static weak var currentHostingView: NSView?
  @MainActor static var mountsByHost: [ObjectIdentifier: [AnyHashable: any _HostedViewMount]] = [:]

  @MainActor static func mount(for host: NSView?, key: AnyHashable?) -> (any _HostedViewMount)? {
    guard let host, let key else { return nil }
    return mountsByHost[ObjectIdentifier(host)]?[key]
  }

  @MainActor static func setMount(_ mount: any _HostedViewMount, for host: NSView?, key: AnyHashable?) {
    guard let host, let key else { return }
    mountsByHost[ObjectIdentifier(host), default: [:]][key] = mount
  }

  @MainActor static func removeMount(for host: NSView?, key: AnyHashable?) {
    guard let host, let key else { return }
    let id = ObjectIdentifier(host)
    mountsByHost[id]?.removeValue(forKey: key)
    if mountsByHost[id]?.isEmpty == true {
      mountsByHost.removeValue(forKey: id)
    }
  }
}

private final class HostedMountInstance<R: NSViewRepresentable>: _HostedViewMount {
  let typedView: R.NSViewType
  let coordinator: R.Coordinator
  weak var hostContainer: NSView?
  let key: AnyHashable?
  var nsView: NSView { typedView }

  init(typedView: R.NSViewType, coordinator: R.Coordinator, hostContainer: NSView?, key: AnyHashable?) {
    self.typedView = typedView
    self.coordinator = coordinator
    self.hostContainer = hostContainer
    self.key = key
  }

  func dismantle() {
    MainActor.assumeIsolated {
      ActiveHostingContext.removeMount(for: hostContainer, key: key)
      R.dismantleNSView(typedView, coordinator: coordinator)
      typedView.removeFromSuperview()
    }
  }
}

private final class HostedViewBridge<R: NSViewRepresentable>: _HostedViewBackendBridge {
  let representable: R
  let environment: EnvironmentValues
  weak var hostContainer: NSView?
  var viewKey: AnyHashable?
  private var fallbackInstance: HostedMountInstance<R>?

  init(representable: R, environment: EnvironmentValues, hostContainer: NSView?) {
    self.representable = representable
    self.environment = environment
    self.hostContainer = hostContainer
  }

  @MainActor
  private func lookupInstance(key: AnyHashable?) -> HostedMountInstance<R>? {
    let resolvedKey = key ?? viewKey
    if let existing = ActiveHostingContext.mount(for: hostContainer, key: resolvedKey) as? HostedMountInstance<R> {
      return existing
    }
    return fallbackInstance
  }

  @MainActor
  private func ensureInstance(key: AnyHashable?) -> HostedMountInstance<R> {
    let resolvedKey = key ?? viewKey
    if let existing = lookupInstance(key: resolvedKey) {
      if let container = hostContainer, existing.typedView.superview !== container {
        container.addSubview(existing.typedView)
      }
      return existing
    }
    let coordinator = representable.makeCoordinator()
    let ctx = NSViewRepresentableContext<R>(coordinator: coordinator, environment: environment)
    let view = representable.makeNSView(context: ctx)
    if let container = hostContainer {
      container.addSubview(view)
    }
    let instance = HostedMountInstance<R>(
      typedView: view, coordinator: coordinator, hostContainer: hostContainer, key: resolvedKey
    )
    if hostContainer != nil {
      ActiveHostingContext.setMount(instance, for: hostContainer, key: resolvedKey)
    } else {
      fallbackInstance = instance
    }
    return instance
  }

  func measure(key: AnyHashable, proposal: ProposedViewSize) -> SwiftUIRuntime.Size {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: key)
      let ctx = NSViewRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      if let custom = representable.sizeThatFits(proposal, nsView: instance.typedView, context: ctx) {
        return SwiftUIRuntime.Size(width: Double(custom.width), height: Double(custom.height))
      }
      let intrinsic = instance.typedView.intrinsicContentSize
      let w = intrinsic.width >= 0 ? Double(intrinsic.width) : Double(proposal.width ?? 0)
      let h = intrinsic.height >= 0 ? Double(intrinsic.height) : Double(proposal.height ?? 0)
      return SwiftUIRuntime.Size(width: max(0, w), height: max(0, h))
    }
  }

  func createMount(frame: CGRect) -> (mount: any _HostedViewMount, nativeView: NativeAPI.View?) {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: viewKey)
      instance.typedView.frame = frame
      #if !os(macOS)
        if let tv = instance.typedView as? NSTextView, !tv.isFieldEditorProxy {
          _ = tv.ensureStandaloneNativeEditor()
        }
      #endif
      let ctx = NSViewRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      representable.updateNSView(instance.typedView, context: ctx)
      return (instance, instance.typedView.ownedNativeView)
    }
  }

  func updateMount(_ mount: any _HostedViewMount, frame: CGRect) {
    MainActor.assumeIsolated {
      guard let typed = mount as? HostedMountInstance<R> else { return }
      if typed.typedView.frame != frame {
        typed.typedView.frame = frame
      }
      if let container = hostContainer, typed.typedView.superview !== container {
        container.addSubview(typed.typedView)
      }
      let ctx = NSViewRepresentableContext<R>(coordinator: typed.coordinator, environment: environment)
      representable.updateNSView(typed.typedView, context: ctx)
    }
  }

  @MainActor
  private static func makeMouseNSEvent(
    event: Int,
    rootPoint: CGPoint,
    modifiers: EventModifiers,
    window: NSWindow?
  ) -> NSEvent? {
    let type: NSEvent.EventType
    let button: Int
    let clickCount: Int
    switch event {
    case 2:
      type = .leftMouseDown
      button = 0
      clickCount = 1
    case 3:
      type = .leftMouseUp
      button = 0
      clickCount = 1
    case 4:
      type = .leftMouseDown
      button = 0
      clickCount = 2
    case 9:
      type = .rightMouseDown
      button = 1
      clickCount = 1
    default:
      return nil
    }
    var flags: NSEvent.ModifierFlags = []
    if modifiers.contains(.shift) { flags.insert(.shift) }
    if modifiers.contains(.control) { flags.insert(.command) }
    if modifiers.contains(.option) { flags.insert(.option) }
    if modifiers.contains(.command) { flags.insert(.command) }
    let winHeight = window?.contentLayoutRect.height ?? 0
    let appKitLoc = NSPoint(x: rootPoint.x, y: max(0, winHeight - rootPoint.y))
    return NSEvent(
      type: type,
      locationInWindow: appKitLoc,
      modifierFlags: flags,
      windowNumber: window?.windowNumber ?? 0,
      window: window,
      buttonNumber: button,
      clickCount: clickCount
    )
  }

  func hitTest(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 3 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else {
        return false
      }
      if instance.typedView.ownedNativeView != nil {
        return false
      }
      let win = instance.typedView.window ?? hostContainer?.window
      guard let nsEv = Self.makeMouseNSEvent(event: event, rootPoint: rootPoint, modifiers: modifiers, window: win) else {
        return false
      }
      let prevEvent = NSApplication.shared.currentEvent
      NSApplication.shared.currentEvent = nsEv
      defer { NSApplication.shared.currentEvent = prevEvent }
      return instance.typedView.hitTest(NSPoint(x: rootPoint.x, y: rootPoint.y)) != nil
    }
  }

  func handleMouseInput(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else {
        return false
      }
      if instance.typedView.ownedNativeView != nil {
        return false
      }
      let win = instance.typedView.window ?? hostContainer?.window
      guard let nsEv = Self.makeMouseNSEvent(event: event, rootPoint: rootPoint, modifiers: modifiers, window: win) else {
        return false
      }
      let prevEvent = NSApplication.shared.currentEvent
      NSApplication.shared.currentEvent = nsEv
      defer { NSApplication.shared.currentEvent = prevEvent }
      guard let hit = instance.typedView.hitTest(NSPoint(x: rootPoint.x, y: rootPoint.y)) else {
        return false
      }
      if event == 9 {
        hit.rightMouseDown(with: nsEv)
      } else {
        hit.mouseDown(with: nsEv)
      }
      return true
    }
  }
}

extension NSViewRepresentable {
  public var body: _HostedViewPrimitive {
    let env = EnvironmentValues.current
    let host = env._currentHostingView.view ?? ActiveHostingContext.currentHostingView
    let bridge = HostedViewBridge(representable: self, environment: env, hostContainer: host)
    return _HostedViewPrimitive(
      adapter: bridge,
      bindPath: { key in bridge.viewKey = key },
      measure: { key, proposal in bridge.measure(key: key, proposal: proposal) },
      hitTest: { key, ev, pt, mods in bridge.hitTest(key: key, event: ev, rootPoint: pt, modifiers: mods) },
      mouseInput: { key, ev, pt, mods in bridge.handleMouseInput(key: key, event: ev, rootPoint: pt, modifiers: mods) }
    )
  }
}

internal final class _HeadlessRenderBackend: RenderBackend {
  var tapHandler: ((NodeID) -> Void)?
  var transactionHandler: ((() -> Void) -> Void)?
  var animationTickHandler: (() -> Bool)?
  var environment = EnvironmentValues()
  var needsRenderCommands: Bool { false }
  func perform(_ commands: [RenderCommand]) {}
  func didRender(_ root: Element) {}
}

// MARK: - NSHostingView & NSHostingController

public struct NSHostingSizingOptions: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let minSize = NSHostingSizingOptions(rawValue: 1 << 0)
  public static let intrinsicContentSize = NSHostingSizingOptions(rawValue: 1 << 1)
  public static let maxSize = NSHostingSizingOptions(rawValue: 1 << 2)
  public static let preferredContentSize = NSHostingSizingOptions(rawValue: 1 << 3)
  public static let standardBounds: NSHostingSizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
}

@MainActor
open class NSHostingView<Content: SwiftUIRuntime.View>: NSView {
  public typealias SizingOptions = NSHostingSizingOptions

  open override var isFlipped: Bool { true }

  public var sizingOptions: SizingOptions = .standardBounds
  public var rootView: Content {
    didSet {
      rebuildOrUpdateRenderer(forceRemount: true)
    }
  }

  #if os(Windows)
    private var backend: WindowsDrawingBackend?
    private var keyWindowObserver: NSObjectProtocol?
    private var isApplyingWindowResize = false
    private var isCommittingPendingWindowBounds = false
    private var pendingWindowBoundsCommit: (() -> Void)?
    private var surfaceContentOffset: NSPoint = .zero
    private var usesEnvelopeSizing = false
  #elseif os(Linux)
    private var backend: LinuxDrawingBackend?
  #else
    private var backend: NativeViewBackend?
  #endif
  public private(set) var renderer: Renderer?

  public init(rootView: Content) {
    self.rootView = rootView
    super.init(frame: .zero)
    installAssetResolversOnce()
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  open override var intrinsicContentSize: NSSize {
    if let renderer {
      let measured = renderer.sizeThatFits(
        ProposedViewSize(
          width: frame.width > 0 ? frame.width : nil,
          height: nil
        )
      )
      return NSSize(width: CGFloat(measured.width), height: CGFloat(measured.height))
    }
    return measureDetached(proposal: ProposedViewSize(width: frame.width > 0 ? frame.width : nil, height: nil))
  }

  private func measureDetached(proposal: ProposedViewSize) -> NSSize {
    #if os(Windows)
      let engine = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
    #elseif os(Linux)
      let pango = LinuxDrawing()
      let engine = LayoutEngine(textMeasurer: pango.measure)
    #else
      let engine = LayoutEngine()
    #endif
    let dummy = _HeadlessRenderBackend()
    let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    dummy.environment.colorScheme = isDark ? SwiftUIRuntime.ColorScheme.dark : SwiftUIRuntime.ColorScheme.light
    let temp = Renderer(backend: dummy, root: AnyView(rootView), size: SwiftUIRuntime.Size(width: Double(proposal.width ?? 420), height: Double(proposal.height ?? 800)), layoutEngine: engine)
    let sz = temp.sizeThatFits(proposal)
    return NSSize(width: CGFloat(sz.width), height: CGFloat(sz.height))
  }

  open override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      attachIfPossible()
    } else {
      teardownRenderer()
    }
  }

  private var isFlushingLayout = false

  open override func layout() {
    super.layout()
    guard !isFlushingLayout else { return }
    if renderer?.isRendering == true { return }
    isFlushingLayout = true
    defer { isFlushingLayout = false }
    renderer?.renderIfNeeded()
    #if os(Windows)
      if !isApplyingWindowResize && pendingWindowBoundsCommit == nil {
        backend?.flushSyncPaint()
      }
    #endif
  }

  open override func applySurfaceContentOffset(x: Double, y: Double) {
    #if os(Windows)
      surfaceContentOffset = NSPoint(x: x, y: y)
      if x != 0 || y != 0 {
        usesEnvelopeSizing = true
      }
      backend?.setContentOffset(x: x, y: y)
    #endif
  }

  open override func applyWindowFrameChange(
    contentSize: NSSize,
    envelopeSize: NSSize? = nil,
    contentOffset: NSPoint = .zero,
    display: Bool,
    commitNativeBounds: @escaping () -> Void
  ) -> Bool {
    #if os(Windows)
      guard let renderer, let backend, ownedNativeView != nil else { return false }
      let w = Double(max(1, contentSize.width))
      let h = Double(max(1, contentSize.height))
      let envSize = envelopeSize ?? contentSize
      let surfW = Double(max(1, envSize.width))
      let surfH = Double(max(1, envSize.height))
      let hasEnv = envelopeSize != nil
      if hasEnv {
        usesEnvelopeSizing = true
      }
      let offsetChanged =
        abs(Double(surfaceContentOffset.x) - Double(contentOffset.x)) > 1e-4
        || abs(Double(surfaceContentOffset.y) - Double(contentOffset.y)) > 1e-4
      surfaceContentOffset = contentOffset
      let sizeChanged =
        abs(Double(frame.width) - w) > 0.5 || abs(Double(frame.height) - h) > 0.5 || offsetChanged

      if renderer.isRendering || isApplyingWindowResize {
        pendingWindowBoundsCommit = commitNativeBounds
        if sizeChanged || pendingWindowBoundsCommit != nil {
          backend.beginPendingResize(width: surfW, height: surfH)
          if hasEnv || offsetChanged {
            backend.setPendingContentOffset(x: Double(contentOffset.x), y: Double(contentOffset.y))
          }
        }
        if superview === window?.contentView, superview !== self {
          superview?.frame = NSRect(origin: .zero, size: contentSize)
        }
        self.frame = NSRect(origin: .zero, size: contentSize)
        renderer.resize(to: SwiftUIRuntime.Size(width: w, height: h))
        return true
      }

      guard sizeChanged else {
        commitNativeBounds()
        if display {
          renderer.renderIfNeeded()
          backend.flushSyncPaint()
        }
        return true
      }

      isApplyingWindowResize = true
      defer { isApplyingWindowResize = false }
      pendingWindowBoundsCommit = commitNativeBounds

      backend.beginPendingResize(width: surfW, height: surfH)
      if hasEnv || offsetChanged {
        backend.setPendingContentOffset(x: Double(contentOffset.x), y: Double(contentOffset.y))
      }
      if superview === window?.contentView, superview !== self {
        superview?.frame = NSRect(origin: .zero, size: contentSize)
      }
      self.frame = NSRect(origin: .zero, size: contentSize)
      renderer.resize(to: SwiftUIRuntime.Size(width: w, height: h))
      renderer.renderIfNeeded()

      let finalCommit = pendingWindowBoundsCommit ?? commitNativeBounds
      pendingWindowBoundsCommit = nil
      backend.prerenderPendingResize()
      isCommittingPendingWindowBounds = true
      finalCommit()
      isCommittingPendingWindowBounds = false
      backend.commitPendingResize()
      return true
    #else
      return false
    #endif
  }

  open override func viewDidChangeFrameSize(from oldSize: NSSize) {
    super.viewDidChangeFrameSize(from: oldSize)
    guard frame.width > 0 && frame.height > 0 else { return }
    renderer?.resize(to: SwiftUIRuntime.Size(width: Double(frame.width), height: Double(frame.height)))
  }

  open override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    syncAppearanceAndBackground()
    renderer?.setNeedsRender()
  }

  private func syncAppearanceAndBackground() {
    guard let win = window else { return }
    let isDark = win.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    #if os(Windows)
      backend?.environmentTransform = { env in
        env.colorScheme = isDark ? SwiftUIRuntime.ColorScheme.dark : SwiftUIRuntime.ColorScheme.light
      }
      let bg = win.backgroundColor.resolved(for: win.effectiveAppearance)
      let isFrameless = !win.styleMask.contains(.titled)
      if !win.isOpaque || bg.a < 0.05 {
        // Transparent borderless panels clear to per-pixel alpha=0 so outer margins stay hollow
        backend?.setBackgroundColor(.clear)
        backend?.setWindowShadow(enabled: isFrameless && win.hasShadow, isDark: isDark)
        win.syncBackgroundToNative()
      } else {
        backend?.setWindowShadow(enabled: false, isDark: isDark)
        backend?.setBackgroundColor(SwiftUIRuntime.Color(
          red: Double(bg.r), green: Double(bg.g), blue: Double(bg.b), opacity: Double(bg.a)
        ))
      }
    #elseif os(Linux)
      backend?.environmentTransform = { env in
        env.colorScheme = isDark ? SwiftUIRuntime.ColorScheme.dark : SwiftUIRuntime.ColorScheme.light
      }
    #endif
  }

  private func attachIfPossible() {
    guard renderer == nil, let win = window, let nativeWin = win.nativeWindow else { return }
    let targetView: NativeAPI.View
    let isWindowRootHost = (win.contentView === self)
      || (superview === win.contentView && superview?.ownedNativeView == nil && superview?.subviews.count == 1)
    if isWindowRootHost, let cv = nativeWin.contentView {
      self.ownedNativeView = cv
      targetView = cv
    } else if let subNV = ensureNativeView() {
      if let parentNV = superview?.ownedNativeView ?? nativeWin.contentView {
        parentNV.addSubview(subNV)
      }
      targetView = subNV
    } else {
      return
    }

    let initialSize = frame.width > 0 && frame.height > 0 ? frame.size : win.contentLayoutRect.size
    let w = Double(max(1, initialSize.width))
    let h = Double(max(1, initialSize.height))

    #if os(Windows)
      WindowsDrawingBackend.prepareApplication()
      guard let createdBackend = WindowsDrawingBackend(view: targetView, window: nativeWin, schedulesUpdates: true) else {
        return
      }
      self.backend = createdBackend
      let initOffset = win.nativeContentOffset
      if initOffset.x != 0 || initOffset.y != 0 {
        surfaceContentOffset = initOffset
        usesEnvelopeSizing = true
        createdBackend.setContentOffset(x: Double(initOffset.x), y: Double(initOffset.y))
      }
      syncAppearanceAndBackground()

      createdBackend.onTextSelectionOrCompositionChanged = { [weak self] in
        guard let responder = self?.window?.firstResponder else { return }
        NotificationCenter.default.post(
          name: NSTextView.didChangeSelectionNotification,
          object: responder
        )
      }

      createdBackend.onPreInput = { [weak self] event, point, value, modifiers in
        guard let self, let nsWin = self.window else { return false }
        return self.forwardToNSWindowIfIntercepted(
          nsWin: nsWin, event: event, point: point, value: value, modifiers: modifiers
        )
      }
      createdBackend.canAcquireControlFocus = { [weak self] in
        self?.window?.isKeyWindow ?? true
      }
      if let obs = keyWindowObserver {
        NotificationCenter.default.removeObserver(obs)
      }
      keyWindowObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: win, queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.backend?.applyPendingFocusIfNeeded()
        }
      }

      let layout = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
      ActiveHostingContext.currentHostingView = self
      let createdRenderer = Renderer(
        backend: createdBackend,
        root: AnyView(HostingScopeView(host: self, content: rootView)),
        size: SwiftUIRuntime.Size(width: w, height: h),
        layoutEngine: layout
      )
      self.renderer = createdRenderer

      createdRenderer.onDidFinishRenderPasses = { [weak self] in
        guard let self, !self.isApplyingWindowResize, !self.isCommittingPendingWindowBounds,
          let commit = self.pendingWindowBoundsCommit
        else {
          return
        }
        self.pendingWindowBoundsCommit = nil
        self.backend?.prerenderPendingResize()
        self.isCommittingPendingWindowBounds = true
        commit()
        self.isCommittingPendingWindowBounds = false
        self.backend?.commitPendingResize()
      }
      createdBackend.onResize = { [weak self, weak createdRenderer] newSize in
        guard let self, let createdRenderer else { return }
        if self.usesEnvelopeSizing {
          return
        }
        if self.isCommittingPendingWindowBounds || self.isApplyingWindowResize || self.pendingWindowBoundsCommit != nil {
          if abs(Double(self.frame.width) - newSize.width) < 1.0
            && abs(Double(self.frame.height) - newSize.height) < 1.0
          {
            return
          }
        }
        createdRenderer.resize(to: newSize)
      }
      createdBackend.inputHandler = { [weak self, weak createdRenderer] id, event, point, value, modifiers, text in
        guard let self, let createdRenderer else { return false }
        ActiveHostingContext.currentHostingView = self
        if event == 6 {
          let resolvedText = !text.isEmpty ? text : Self.keyCharacter(forWin32VK: value)
          if modifiers.contains(.control) && !modifiers.contains(.command) {
            var cmdMods = modifiers
            cmdMods.remove(.control)
            cmdMods.insert(.command)
            if createdRenderer.input(
              id: id, event: event, point: point, value: value, modifiers: cmdMods,
              text: resolvedText, updatesPressedState: false
            ) {
              return true
            }
            if value == 0x58,
              let editor = self.window?.firstResponder as? NSTextView,
              editor.selectedRange().length > 0
            {
              return false
            }
          }
          return createdRenderer.input(
            id: id, event: event, point: point, value: value, modifiers: modifiers,
            text: resolvedText, updatesPressedState: false
          )
        }
        return createdRenderer.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text,
          updatesPressedState: false
        )
      }
      createdBackend.interactionHandler = { [weak createdRenderer] id, interaction in
        createdRenderer?.interact(id, interaction)
      }
      createdRenderer.mount()
      ActiveHostingContext.currentHostingView = nil
    #elseif os(Linux)
      guard let createdBackend = LinuxDrawingBackend(window: nativeWin) else { return }
      self.backend = createdBackend
      let layout = LayoutEngine(textMeasurer: createdBackend.measureText)
      let createdRenderer = Renderer(
        backend: createdBackend,
        root: AnyView(HostingScopeView(host: self, content: rootView)),
        size: SwiftUIRuntime.Size(width: w, height: h),
        layoutEngine: layout
      )
      self.renderer = createdRenderer
      createdBackend.onResize = { [weak createdRenderer] newSize in
        createdRenderer?.resize(to: newSize)
      }
      createdBackend.inputHandler = { [weak createdRenderer] id, event, point, value, modifiers, text in
        createdRenderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text,
          updatesPressedState: true
        ) ?? false
      }
      createdBackend.interactionHandler = { [weak createdRenderer] id, interaction in
        createdRenderer?.interact(id, interaction)
      }
      createdRenderer.mount()
    #endif
  }

  private func rebuildOrUpdateRenderer(forceRemount: Bool) {
    guard renderer != nil else {
      attachIfPossible()
      return
    }
    if forceRemount {
      teardownRenderer()
      attachIfPossible()
    } else {
      renderer?.setNeedsRender()
    }
  }

  private func teardownRenderer() {
    #if os(Windows)
      if let obs = keyWindowObserver {
        NotificationCenter.default.removeObserver(obs)
        keyWindowObserver = nil
      }
    #endif
    ActiveHostingContext.mountsByHost.removeValue(forKey: ObjectIdentifier(self))
    renderer = nil
    backend = nil
  }

  internal static func keyCharacter(forWin32VK value: Int) -> String {
    if (0x30...0x5A).contains(value), let scalar = UnicodeScalar(value) {
      return String(scalar).lowercased()
    }
    switch value {
    case 0xBC: return ","
    case 0xBE: return "."
    case 0xBD: return "-"
    case 0xBB: return "="
    case 0xDB: return "["
    case 0xDD: return "]"
    case 0xDC: return "\\"
    case 0xBA: return ";"
    case 0xDE: return "'"
    case 0xBF: return "/"
    case 0xC0: return "`"
    case 0x1B: return "\u{1B}"
    case 0x0D: return "\r"
    case 0x08: return "\u{7F}"
    case 0x09: return "\t"
    case 0x26: return "\u{F700}"
    case 0x28: return "\u{F701}"
    case 0x25: return "\u{F702}"
    case 0x27: return "\u{F703}"
    case 0x2E: return "\u{F728}"
    case 0x24: return "\u{F729}"
    case 0x23: return "\u{F72B}"
    case 0x21: return "\u{F72C}"
    case 0x22: return "\u{F72D}"
    default: return ""
    }
  }

  /// Translates low-level surface key/mouse events into `CrossAppKit.NSEvent` and lets
  /// subclasses like `PalettePanel` or `DialogPanel` run their `sendEvent` hooks!
  private func forwardToNSWindowIfIntercepted(
    nsWin: NSWindow, event: Int, point: CGPoint, value: Int, modifiers: EventModifiers
  ) -> Bool {
    var flags: NSEvent.ModifierFlags = []
    if modifiers.contains(.shift) { flags.insert(.shift) }
    if modifiers.contains(.control) {
      // On Windows, Ctrl acts as Command for app shortcuts (Ctrl+K, Ctrl+W, Ctrl+,)
      flags.insert(.command)
    }
    if modifiers.contains(.option) { flags.insert(.option) }
    if modifiers.contains(.command) { flags.insert(.command) }

    let winHeight = nsWin.contentLayoutRect.height
    let appKitLoc = NSPoint(x: point.x, y: max(0, winHeight - point.y))

    if event == 1 || event == 2 || event == 3 || event == 4 || event == 5 || event == 9 {
      let evType: NSEvent.EventType
      let btn: Int
      let clicks: Int
      switch event {
      case 1:
        evType = .mouseMoved
        btn = 0
        clicks = 0
      case 2:
        evType = .leftMouseDown
        btn = 0
        clicks = 1
      case 3:
        evType = .leftMouseUp
        btn = 0
        clicks = 1
      case 4:
        evType = .leftMouseDown
        btn = 0
        clicks = 2
      case 5:
        evType = .scrollWheel
        btn = 0
        clicks = 0
      default:
        evType = .rightMouseDown
        btn = 1
        clicks = 1
      }
      let mouseEv = NSEvent(
        type: evType,
        locationInWindow: appKitLoc,
        modifierFlags: flags,
        windowNumber: nsWin.windowNumber,
        window: nsWin,
        buttonNumber: btn,
        clickCount: clicks,
        scrollingDeltaY: event == 5 ? CGFloat(value) : 0
      )
      let prevEvent = NSApplication.shared.currentEvent
      NSApplication.shared.currentEvent = mouseEv
      defer { NSApplication.shared.currentEvent = prevEvent }
      nsWin._eventReachedBaseSendEvent = false
      nsWin._suppressLocalMonitorInSendEvent = true
      nsWin.sendEvent(mouseEv)
      nsWin._suppressLocalMonitorInSendEvent = false
      if !nsWin._eventReachedBaseSendEvent {
        return true
      }
      return false
    }

    if event == 6 {
      // KeyDown: value is Win32 VK code
      let carbonCode = NSEvent.carbonKeyCode(fromWin32VK: value)
      let ch = Self.keyCharacter(forWin32VK: value)
      let nsEv = NSEvent(
        type: .keyDown,
        locationInWindow: appKitLoc,
        modifierFlags: flags,
        windowNumber: nsWin.windowNumber,
        window: nsWin,
        characters: ch,
        charactersIgnoringModifiers: ch,
        keyCode: carbonCode
      )
      guard NSEvent.dispatchLocalMonitors(nsEv) != nil else {
        return true // Swallowed by local monitor (e.g., Paste monitor)!
      }
      nsWin._eventReachedBaseSendEvent = false
      nsWin._suppressLocalMonitorInSendEvent = true
      nsWin.sendEvent(nsEv)
      nsWin._suppressLocalMonitorInSendEvent = false
      if !nsWin._eventReachedBaseSendEvent {
        return true // Swallowed by NSWindow subclass (PalettePanel, MenuPanel, DialogPanel)!
      }
    }
    return false
  }
}

private struct HostingScopeView<Content: SwiftUIRuntime.View>: SwiftUIRuntime.View {
  weak var host: NSView?
  let content: Content

  var body: some SwiftUIRuntime.View {
    let _ = { ActiveHostingContext.currentHostingView = host }()
    content.environment(\._currentHostingView, WeakHostingView(view: host))
  }
}

public struct NSHostingSceneBridgingOptions: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let toolbars = NSHostingSceneBridgingOptions(rawValue: 1 << 0)
  public static let title = NSHostingSceneBridgingOptions(rawValue: 1 << 1)
  public static let all: NSHostingSceneBridgingOptions = [.toolbars, .title]
}

@MainActor
open class NSHostingController<Content: SwiftUIRuntime.View>: NSViewController {
  public typealias SizingOptions = NSHostingSizingOptions

  public var sizingOptions: SizingOptions = .standardBounds {
    didSet { hostingView.sizingOptions = sizingOptions }
  }
  public var sceneBridgingOptions: NSHostingSceneBridgingOptions = .all

  public var rootView: Content {
    get { hostingView.rootView }
    set { hostingView.rootView = newValue }
  }

  private let hostingView: NSHostingView<Content>

  public init(rootView: Content) {
    self.hostingView = NSHostingView(rootView: rootView)
    super.init(nibName: nil, bundle: nil)
    self.view = hostingView
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - @NSApplicationDelegateAdaptor

public protocol _ApplicationDelegateProvider {
  @MainActor func _installDelegate()
}

@MainActor
@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate>: _ApplicationDelegateProvider {
  public let wrappedValue: DelegateType

  public init(_ delegateType: DelegateType.Type = DelegateType.self) {
    self.wrappedValue = delegateType.init()
  }

  public init(_ makeDelegate: @autoclosure @escaping () -> DelegateType) {
    self.wrappedValue = makeDelegate()
  }

  public func _installDelegate() {
    installAssetResolversOnce()
    NSApplication.shared.delegate = wrappedValue
  }
}

nonisolated(unsafe) private var didInstallAssetResolvers = false

internal func installAssetResolversOnce() {
  guard !didInstallAssetResolvers else { return }
  didInstallAssetResolvers = true
  #if !os(macOS)
    bootstrapAppResources()
  #endif
  _ = VectorImage.hasSymbol("circle")
  SwiftUIRuntime.Image.assetPathResolver = { name, bundle in
    CrossAppKit.NSImage.resolveAssetPath(named: name, in: bundle)
  }
  CrossAppKit.NSImage.symbolLookupHandler = { symbolName in
    VectorImage.hasSymbol(symbolName)
  }
  CrossUIKit.UIImage.symbolLookupHandler = { symbolName in
    VectorImage.hasSymbol(symbolName)
  }
  CrossUIKit.UIApplication._hostBootstrapHook = {
    installAssetResolversOnce()
  }
  #if os(Windows)
    CrossAppKit.NSImage.offscreenRenderer = { size, flipped, ops in
      let scale = 2.0
      let pxW = Int32(max(1, Int(ceil(Double(size.width) * scale))))
      let pxH = Int32(max(1, Int(ceil(Double(size.height) * scale))))
      guard let canvas = sui_offscreen_create(pxW, pxH) else { return nil }

      func mapRect(_ r: NSRect) -> CGRect {
        let y = flipped ? Double(r.origin.y) : Double(size.height - r.origin.y - r.size.height)
        return CGRect(
          x: Double(r.origin.x) * scale,
          y: y * scale,
          width: Double(r.size.width) * scale,
          height: Double(r.size.height) * scale
        )
      }

      func mapCommands(_ cmds: [Double]) -> [Double] {
        var out = cmds
        var i = 0
        while i < cmds.count {
          let n = cmds[i] == 2 ? 6 : cmds[i] == 3 ? 0 : 2
          for j in stride(from: 1, through: n, by: 2) where i + j + 1 < cmds.count {
            let x = cmds[i + j]
            let y = cmds[i + j + 1]
            out[i + j] = x * scale
            out[i + j + 1] = (flipped ? y : (Double(size.height) - y)) * scale
          }
          i += n + 1
        }
        return out
      }

      for op in ops {
        switch op {
        case .shape(let rect, let radius, let fillARGB, let strokeARGB, let strokeWidth):
          let mr = mapRect(rect)
          sui_offscreen_shape(
            canvas, mr.minX, mr.minY, mr.width, mr.height,
            Double(radius) * scale, fillARGB, strokeARGB, Double(strokeWidth) * scale
          )
        case .path(let commands, let fillARGB, let strokeARGB, let strokeWidth):
          let mapped = mapCommands(commands)
          mapped.withUnsafeBufferPointer { buf in
            sui_offscreen_path(
              canvas, buf.baseAddress, Int32(buf.count),
              fillARGB, strokeARGB, Double(strokeWidth) * scale
            )
          }
        case .symbol(let name, let rect, let colorARGB, _, let weight):
          guard let vec = VectorImage.loadSymbol(name), vec.bounds.width > 0, vec.bounds.height > 0
          else { continue }
          let mr = mapRect(rect)
          let s = min(mr.width / vec.bounds.width, mr.height / vec.bounds.height)
          let weightBoost = (weight - 400.0) / 500.0 * 0.45
          let sw = vec.strokeWidth > 0 ? max(1.1 * scale, (vec.strokeWidth + weightBoost) * s) : 0
          let tx = mr.minX + (mr.width - vec.bounds.width * s) / 2 - vec.bounds.minX * s
          let ty = mr.minY + (mr.height - vec.bounds.height * s) / 2 - vec.bounds.minY * s
          for p in vec.paths {
            let tp = p.transformed(x: tx, y: ty, sx: s, sy: s)
            tp.commands.withUnsafeBufferPointer { buf in
              sui_offscreen_path(
                canvas, buf.baseAddress, Int32(buf.count),
                sw > 0 ? 0 : colorARGB, sw > 0 ? colorARGB : 0, sw
              )
            }
          }
        case .image:
          break
        case .text(let string, let rect, let fontSize, let colorARGB):
          let mr = mapRect(rect)
          sui_offscreen_text(
            canvas, mr.minX, mr.minY, mr.width, mr.height,
            string, Double(fontSize) * scale, colorARGB
          )
        }
      }

      var outLen: Int32 = 0
      guard let ptr = sui_offscreen_finish_png(canvas, &outLen), outLen > 0 else { return nil }
      let data = Data(bytes: ptr, count: Int(outLen))
      sui_free_bytes(ptr)
      return data
    }
    CrossUIKit.UIImage.offscreenRenderer = CrossAppKit.NSImage.offscreenRenderer
    CrossAppKit.NSImage.vectorRasterizer = { spec, size in
      guard let vec = VectorImage.load(spec), vec.bounds.width > 0, vec.bounds.height > 0 else {
        return nil
      }
      let pxSide = Int32(max(64, Int(ceil(Double(max(size.width, size.height)) * 2.0))))
      guard let canvas = sui_offscreen_create(pxSide, pxSide) else { return nil }
      let box = Double(pxSide)
      let pad = box * 0.08
      let avail = max(1.0, box - pad * 2.0)
      let s = min(avail / vec.bounds.width, avail / vec.bounds.height)
      let tx = pad + (avail - vec.bounds.width * s) * 0.5 - vec.bounds.minX * s
      let ty = pad + (avail - vec.bounds.height * s) * 0.5 - vec.bounds.minY * s
      func packARGB(_ c: SwiftUIRuntime.Color) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (byte(c.opacity) << 24) | (byte(c.red) << 16) | (byte(c.green) << 8) | byte(c.blue)
      }
      for layer in vec.layers {
        let tp = layer.path.transformed(x: tx, y: ty, sx: s, sy: s)
        let fillARGB: UInt32
        if let f = layer.fill, f.opacity > 0 {
          fillARGB = packARGB(f)
        } else if layer.stroke == nil && vec.strokeWidth == 0 {
          fillARGB = 0xFF000000
        } else {
          fillARGB = 0
        }
        let strokeARGB: UInt32
        let strokeW: Double
        if let st = layer.stroke, st.opacity > 0 {
          strokeARGB = packARGB(st)
          strokeW = max(1.5, layer.strokeWidth * s)
        } else if vec.strokeWidth > 0 && fillARGB == 0 {
          strokeARGB = 0xFF000000
          strokeW = max(1.5, vec.strokeWidth * s)
        } else {
          strokeARGB = 0
          strokeW = 0
        }
        tp.commands.withUnsafeBufferPointer { buf in
          sui_offscreen_path(canvas, buf.baseAddress, Int32(buf.count), fillARGB, strokeARGB, strokeW)
        }
      }
      var outLen: Int32 = 0
      guard let ptr = sui_offscreen_finish_png(canvas, &outLen), outLen > 0 else { return nil }
      let data = Data(bytes: ptr, count: Int(outLen))
      sui_free_bytes(ptr)
      return data
    }
  #endif
}

#if !os(macOS)
  private func bootstrapAppResources() {
    let fm = FileManager.default
    let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
    var candidates: [URL] = [exeDir, cwd]
    var cursor = exeDir
    for _ in 0..<5 {
      cursor = cursor.deletingLastPathComponent()
      candidates.append(cursor)
    }
    var searchPaths = CrossAppKit.NSImage.resourceSearchPaths
    var didLoadStringsCatalog = false
    var didConfigureAppIcon = false
    if XCStringsCatalog.shared.systemLanguagesProvider == nil {
      XCStringsCatalog.shared.systemLanguagesProvider = { NSApplication._systemPreferredLanguages }
    }
    for root in candidates {
      var bases: [URL] = [root]
      if let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
        for child in children {
          if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            bases.append(child)
          }
        }
      }
      for base in bases {
        let hasCatalog: Bool = {
          if fm.fileExists(atPath: base.appendingPathComponent("Assets.xcassets").path) {
            return true
          }
          if let items = try? fm.contentsOfDirectory(atPath: base.path) {
            return items.contains { $0.lowercased().hasSuffix(".xcassets") }
          }
          return false
        }()
        if hasCatalog, !searchPaths.contains(base.path) {
          searchPaths.append(base.path)
        }
        if !didLoadStringsCatalog {
          let infoStrings = base.appendingPathComponent("Resources/InfoPlist.xcstrings")
          let mainStrings = base.appendingPathComponent("Resources/Localizable.xcstrings")
          var loadedHere = false
          if fm.fileExists(atPath: infoStrings.path), let data = try? Data(contentsOf: infoStrings) {
            loadedHere = XCStringsCatalog.shared.load(data: data, merge: true) || loadedHere
          }
          if fm.fileExists(atPath: mainStrings.path), let data = try? Data(contentsOf: mainStrings) {
            loadedHere = XCStringsCatalog.shared.load(data: data, merge: true) || loadedHere
          }
          if loadedHere {
            didLoadStringsCatalog = true
          }
        }
        if !didConfigureAppIcon {
          let pngURL = base.appendingPathComponent("Resources/AppIcon.png")
          let icoURL = base.appendingPathComponent("Resources/AppIcon.ico")
          if fm.fileExists(atPath: pngURL.path), let nsImg = CrossAppKit.NSImage(contentsOf: pngURL) {
            didConfigureAppIcon = true
            MainActor.assumeIsolated {
              CrossAppKit.NSApplication.shared.applicationIconImage = nsImg
            }
            #if os(Windows)
              if fm.fileExists(atPath: icoURL.path) {
                _ = NativeAPI.Application.shared.setIcon(icoURL.path)
              }
            #else
              _ = NativeAPI.Application.shared.setIcon(pngURL.path)
            #endif
          } else if fm.fileExists(atPath: icoURL.path) {
            didConfigureAppIcon = true
            _ = NativeAPI.Application.shared.setIcon(icoURL.path)
          }
        }
      }
    }
    XCStringsCatalog.shared.latchLaunchLanguageIfNeeded()
    CrossAppKit.NSImage.resourceSearchPaths = searchPaths
  }
#endif

#if !os(macOS)
  private final class _WinCombineCancellableBox {
    var cancellable: AnyCancellable?
  }

  private struct _WinOnReceiveView<Content: SwiftUIRuntime.View, P: Combine.Publisher>: SwiftUIRuntime.View
  where P.Failure == Never {
    let content: Content
    let publisher: P
    let action: (P.Output) -> Void
    @State private var box = _WinCombineCancellableBox()

    var body: some SwiftUIRuntime.View {
      content
        .onAppear {
          box.cancellable = publisher.sink(receiveValue: action)
        }
        .onDisappear {
          box.cancellable?.cancel()
          box.cancellable = nil
        }
    }
  }

  extension SwiftUIRuntime.View {
    public func onReceive<P: Combine.Publisher>(
      _ publisher: P,
      perform action: @escaping (P.Output) -> Void
    ) -> some SwiftUIRuntime.View where P.Failure == Never {
      _WinOnReceiveView(content: self, publisher: publisher, action: action)
    }
  }

  extension SwiftUIRuntime.Published.Publisher: Combine.Publisher {
    public typealias Output = Value
    public typealias Failure = Never

    public func sink(
      receiveCompletion: @escaping (Subscribers.Completion<Never>) -> Void,
      receiveValue: @escaping (Value) -> Void
    ) -> AnyCancellable {
      AnyCancellable(_subscribe(receiveValue))
    }
  }

  extension SwiftUIRuntime.ObservableObjectPublisher: Combine.Publisher {
    public typealias Output = Void
    public typealias Failure = Never

    public func sink(
      receiveCompletion: @escaping (Subscribers.Completion<Never>) -> Void,
      receiveValue: @escaping (()) -> Void
    ) -> AnyCancellable {
      AnyCancellable(_subscribe { receiveValue(()) })
    }
  }
#endif
