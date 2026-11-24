import CrossAppKit
import CrossUIKit
import Foundation
import NativeAPI
import Observation
import SwiftUIRuntime
#if os(Windows)
  import CSwiftUIWindows
#elseif CROSS_SWIFTUI_HARMONY
  import SwiftUIHarmony
#endif

/// Ensures CrossSwiftUI's SF Symbol catalog, `.xcassets` search paths, and offscreen
/// PNG rasterizer are installed before UIKit delegates or asset symbols run.
public func _installCrossSwiftUIBootstrap() {
  installAssetResolversOnce()
}

// MARK: - Color / Font / Image / EdgeInsets UIKit Interop

extension SwiftUIRuntime.Color {
  public init(uiColor: CrossUIKit.UIColor) {
    installAssetResolversOnce()
    if uiColor.isDynamic {
      self.init { scheme in
        let tc = CrossUIKit.UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let c = uiColor.resolved(for: tc)
        return (Double(c.r), Double(c.g), Double(c.b), Double(c.a))
      }
    } else {
      let c = uiColor.resolved()
      self.init(red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: Double(c.a))
    }
  }

  public init(_ uiColor: CrossUIKit.UIColor) {
    self.init(uiColor: uiColor)
  }
}

extension CrossUIKit.UIColor {
  public convenience init(_ color: SwiftUIRuntime.Color) {
    installAssetResolversOnce()
    self.init { traits in
      let isDark = traits.userInterfaceStyle == .dark
      let resolved = color.resolved(in: isDark ? .dark : .light)
      return CrossUIKit.UIColor(
        red: CGFloat(resolved.red),
        green: CGFloat(resolved.green),
        blue: CGFloat(resolved.blue),
        alpha: CGFloat(resolved.opacity)
      )
    }
  }
}

extension SwiftUIRuntime.Font {
  public init(_ font: CrossUIKit.UIFont) {
    self.init(
      size: font.pointSize,
      weight: Weight(font.fontDescriptor.weight.cssWeight),
      family: font.fontName
    )
  }
}

extension SwiftUIRuntime.Image {
  public init(uiImage: CrossUIKit.UIImage) {
    installAssetResolversOnce()
    if let sym = uiImage.symbolName, uiImage.tintColorOverride == nil {
      self.init(systemName: sym)
    } else {
      let path = uiImage.ensureTemporaryFilePath() ?? ""
      let sz = SwiftUIRuntime.Size(width: Double(uiImage.size.width), height: Double(uiImage.size.height))
      self.init(
        filePath: path,
        size: sz,
        isTemplate: uiImage.renderingMode == .alwaysTemplate
      )
    }
  }
}

extension SwiftUIRuntime.EdgeInsets {
  public init(_ insets: CrossUIKit.UIEdgeInsets) {
    self.init(
      top: Double(insets.top),
      leading: Double(insets.left),
      bottom: Double(insets.bottom),
      trailing: Double(insets.right)
    )
  }

  public init(_ insets: CrossUIKit.NSDirectionalEdgeInsets) {
    self.init(
      top: Double(insets.top),
      leading: Double(insets.leading),
      bottom: Double(insets.bottom),
      trailing: Double(insets.trailing)
    )
  }
}

// MARK: - Active UIKit Hosting Scope

private struct WeakUIHostingView {
  weak var view: UIView?
}

private enum UIHostingViewEnvironmentKey: EnvironmentKey {
  static let defaultValue = WeakUIHostingView(view: nil)
}

extension EnvironmentValues {
  fileprivate var _currentUIHostingView: WeakUIHostingView {
    get { self[UIHostingViewEnvironmentKey.self] }
    set { self[UIHostingViewEnvironmentKey.self] = newValue }
  }
}

private enum ActiveUIHostingContext {
  nonisolated(unsafe) static weak var currentHostingView: UIView?
  @MainActor static var mountsByHost: [ObjectIdentifier: [AnyHashable: any _HostedViewMount]] = [:]

  @MainActor static func mount(for host: UIView?, key: AnyHashable?) -> (any _HostedViewMount)? {
    guard let host, let key else { return nil }
    return mountsByHost[ObjectIdentifier(host)]?[key]
  }

  @MainActor static func setMount(_ mount: any _HostedViewMount, for host: UIView?, key: AnyHashable?) {
    guard let host, let key else { return }
    mountsByHost[ObjectIdentifier(host), default: [:]][key] = mount
  }

  @MainActor static func removeMount(for host: UIView?, key: AnyHashable?) {
    guard let host, let key else { return }
    let id = ObjectIdentifier(host)
    mountsByHost[id]?.removeValue(forKey: key)
    if mountsByHost[id]?.isEmpty == true {
      mountsByHost.removeValue(forKey: id)
    }
  }
}

@MainActor
private func _syncTraitCollection(_ view: UIView, environment: EnvironmentValues) {
  let desired: UIUserInterfaceStyle = environment.colorScheme == .dark ? .dark : .light
  if view.overrideUserInterfaceStyle != desired {
    view.overrideUserInterfaceStyle = desired
  }
}

@MainActor
private func _dispatchHostedUIViewMouse(
  rootView: UIView,
  event: Int,
  rootPoint: CGPoint,
  modifiers: EventModifiers
) -> Bool {
  let localPt = CGPoint(x: rootPoint.x - rootView.frame.minX, y: rootPoint.y - rootView.frame.minY)
  var keyFlags: UIKeyModifierFlags = []
  if modifiers.contains(.shift) { keyFlags.insert(.shift) }
  if modifiers.contains(.control) { keyFlags.insert(.control) }
  if modifiers.contains(.option) { keyFlags.insert(.alternate) }
  if modifiers.contains(.command) { keyFlags.insert(.command) }

  let buttonMask: UIEvent.ButtonMask = (event == 9) ? .secondary : .primary
  let tapCount = (event == 4) ? 2 : 1
  let dummyEvent = UIEvent(type: .touches, modifierFlags: keyFlags, buttonMask: buttonMask)
  guard let hit = rootView.hitTest(localPt, with: dummyEvent) else {
    return false
  }

  // Dispatch gesture recognizers up the view hierarchy
  var recognizedGesture = false
  var cursor: UIView? = hit
  while let v = cursor {
    for gr in v.gestureRecognizers ?? [] where gr.isEnabled {
      if let tap = gr as? UITapGestureRecognizer {
        if tap.buttonMaskRequired == buttonMask && tapCount >= tap.numberOfTapsRequired {
          tap._fireRecognized(at: rootPoint, state: .ended)
          recognizedGesture = true
        }
      } else if event == 9, let lp = gr as? UILongPressGestureRecognizer {
        lp._fireRecognized(at: rootPoint, state: .ended)
        recognizedGesture = true
      }
    }
    if v === rootView { break }
    cursor = v.superview
  }

  if let control = hit as? UIControl, control.isEnabled, event != 9 {
    control.sendActions(for: [.touchUpInside, .primaryActionTriggered])
    return true
  }

  let beganTouch = UITouch(
    locationInWindow: rootPoint,
    phase: .began,
    tapCount: tapCount,
    window: rootView.window,
    view: hit
  )
  let beganEv = UIEvent(type: .touches, touches: [beganTouch], modifierFlags: keyFlags, buttonMask: buttonMask)
  hit.touchesBegan([beganTouch], with: beganEv)

  let endedTouch = UITouch(
    locationInWindow: rootPoint,
    phase: .ended,
    tapCount: tapCount,
    window: rootView.window,
    view: hit
  )
  let endedEv = UIEvent(type: .touches, touches: [endedTouch], modifierFlags: keyFlags, buttonMask: buttonMask)
  hit.touchesEnded([endedTouch], with: endedEv)

  return recognizedGesture || true
}

// MARK: - UIViewRepresentable

public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
  public let coordinator: Representable.Coordinator
  public let transaction: Transaction
  public let environment: EnvironmentValues

  public init(
    coordinator: Representable.Coordinator,
    transaction: Transaction = Transaction(),
    environment: EnvironmentValues
  ) {
    self.coordinator = coordinator
    self.transaction = transaction
    self.environment = environment
  }
}

@MainActor @preconcurrency
public protocol UIViewRepresentable: SwiftUIRuntime.View where Body == _HostedViewPrimitive {
  associatedtype UIViewType: CrossUIKit.UIView
  associatedtype Coordinator = Void
  typealias Context = UIViewRepresentableContext<Self>

  func makeCoordinator() -> Coordinator
  func makeUIView(context: UIViewRepresentableContext<Self>) -> UIViewType
  func updateUIView(_ uiView: UIViewType, context: UIViewRepresentableContext<Self>)
  static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UIViewType,
    context: UIViewRepresentableContext<Self>
  ) -> CGSize?
}

extension UIViewRepresentable where Coordinator == Void {
  public func makeCoordinator() -> Void { () }
}

extension UIViewRepresentable {
  public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}

  public func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: UIViewType,
    context: UIViewRepresentableContext<Self>
  ) -> CGSize? {
    nil
  }
}

private final class HostedUIMountInstance<R: UIViewRepresentable>: _HostedViewMount {
  let typedView: R.UIViewType
  let coordinator: R.Coordinator
  weak var hostContainer: UIView?
  let key: AnyHashable?

  init(typedView: R.UIViewType, coordinator: R.Coordinator, hostContainer: UIView?, key: AnyHashable?) {
    self.typedView = typedView
    self.coordinator = coordinator
    self.hostContainer = hostContainer
    self.key = key
  }

  func dismantle() {
    MainActor.assumeIsolated {
      ActiveUIHostingContext.removeMount(for: hostContainer, key: key)
      R.dismantleUIView(typedView, coordinator: coordinator)
      typedView.removeFromSuperview()
    }
  }
}

private final class HostedUIViewBridge<R: UIViewRepresentable>: _HostedViewBackendBridge {
  let representable: R
  let environment: EnvironmentValues
  weak var hostContainer: UIView?
  var viewKey: AnyHashable?
  private var fallbackInstance: HostedUIMountInstance<R>?

  init(representable: R, environment: EnvironmentValues, hostContainer: UIView?) {
    self.representable = representable
    self.environment = environment
    self.hostContainer = hostContainer
  }

  @MainActor
  private func lookupInstance(key: AnyHashable?) -> HostedUIMountInstance<R>? {
    let resolvedKey = key ?? viewKey
    if let existing = ActiveUIHostingContext.mount(for: hostContainer, key: resolvedKey) as? HostedUIMountInstance<R> {
      return existing
    }
    return fallbackInstance
  }

  @MainActor
  private func ensureInstance(key: AnyHashable?) -> HostedUIMountInstance<R> {
    let resolvedKey = key ?? viewKey
    if let existing = lookupInstance(key: resolvedKey) {
      if let container = hostContainer, existing.typedView.superview !== container {
        container.addSubview(existing.typedView)
      }
      return existing
    }
    let coordinator = representable.makeCoordinator()
    let ctx = UIViewRepresentableContext<R>(coordinator: coordinator, environment: environment)
    let view = representable.makeUIView(context: ctx)
    _syncTraitCollection(view, environment: environment)
    if let container = hostContainer {
      container.addSubview(view)
    }
    let instance = HostedUIMountInstance<R>(
      typedView: view,
      coordinator: coordinator,
      hostContainer: hostContainer,
      key: resolvedKey
    )
    if hostContainer != nil {
      ActiveUIHostingContext.setMount(instance, for: hostContainer, key: resolvedKey)
    } else {
      fallbackInstance = instance
    }
    return instance
  }

  func measure(key: AnyHashable, proposal: ProposedViewSize) -> SwiftUIRuntime.Size {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: key)
      _syncTraitCollection(instance.typedView, environment: environment)
      let ctx = UIViewRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      if let custom = representable.sizeThatFits(proposal, uiView: instance.typedView, context: ctx) {
        return SwiftUIRuntime.Size(width: max(0, Double(custom.width)), height: max(0, Double(custom.height)))
      }
      let intrinsic = instance.typedView.intrinsicContentSize
      let targetSize = CGSize(
        width: proposal.width ?? (intrinsic.width >= 0 ? intrinsic.width : 0),
        height: proposal.height ?? (intrinsic.height >= 0 ? intrinsic.height : 0)
      )
      let fitted = instance.typedView.sizeThatFits(targetSize)
      let w: Double
      if let pw = proposal.width {
        w = Double(pw)
      } else if intrinsic.width >= 0 {
        w = Double(intrinsic.width)
      } else {
        w = Double(max(0, fitted.width))
      }
      let h: Double
      if let ph = proposal.height {
        h = Double(ph)
      } else if intrinsic.height >= 0 {
        h = Double(intrinsic.height)
      } else {
        h = Double(max(0, fitted.height))
      }
      return SwiftUIRuntime.Size(width: max(0, w), height: max(0, h))
    }
  }

  func createMount(frame: CGRect) -> (mount: any _HostedViewMount, nativeView: NativeAPI.View?) {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: viewKey)
      _syncTraitCollection(instance.typedView, environment: environment)
      instance.typedView.frame = frame
      let ctx = UIViewRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      representable.updateUIView(instance.typedView, context: ctx)
      instance.typedView.layoutIfNeeded()
      let native: NativeAPI.View?
      if instance.typedView.prefersNativeBacking {
        native = instance.typedView.ensureNativeSubtree()
        instance.typedView.layoutIfNeeded()
      } else {
        native = instance.typedView.ownedNativeView
      }
      return (instance, native)
    }
  }

  func updateMount(_ mount: any _HostedViewMount, frame: CGRect) {
    MainActor.assumeIsolated {
      guard let typed = mount as? HostedUIMountInstance<R> else { return }
      _syncTraitCollection(typed.typedView, environment: environment)
      if typed.typedView.frame != frame {
        typed.typedView.frame = frame
      }
      if let container = hostContainer, typed.typedView.superview !== container {
        container.addSubview(typed.typedView)
      }
      let ctx = UIViewRepresentableContext<R>(coordinator: typed.coordinator, environment: environment)
      representable.updateUIView(typed.typedView, context: ctx)
      if typed.typedView.prefersNativeBacking {
        _ = typed.typedView.ensureNativeSubtree()
      }
      typed.typedView.layoutIfNeeded()
    }
  }

  func hitTest(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 3 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else { return false }
      if instance.typedView.ownedNativeView != nil {
        return false
      }
      let localPt = CGPoint(
        x: rootPoint.x - instance.typedView.frame.minX,
        y: rootPoint.y - instance.typedView.frame.minY
      )
      return instance.typedView.hitTest(localPt, with: nil) != nil
    }
  }

  func handleMouseInput(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else { return false }
      if instance.typedView.ownedNativeView != nil {
        return false
      }
      return _dispatchHostedUIViewMouse(
        rootView: instance.typedView,
        event: event,
        rootPoint: rootPoint,
        modifiers: modifiers
      )
    }
  }
}

extension UIViewRepresentable {
  public var body: _HostedViewPrimitive {
    installAssetResolversOnce()
    let env = EnvironmentValues.current
    let host = env._currentUIHostingView.view ?? ActiveUIHostingContext.currentHostingView
    let bridge = HostedUIViewBridge(representable: self, environment: env, hostContainer: host)
    return _HostedViewPrimitive(
      adapter: bridge,
      bindPath: { key in bridge.viewKey = key },
      measure: { key, proposal in bridge.measure(key: key, proposal: proposal) },
      hitTest: { key, ev, pt, mods in bridge.hitTest(key: key, event: ev, rootPoint: pt, modifiers: mods) },
      mouseInput: { key, ev, pt, mods in bridge.handleMouseInput(key: key, event: ev, rootPoint: pt, modifiers: mods) }
    )
  }
}

// MARK: - UIViewControllerRepresentable

public struct UIViewControllerRepresentableContext<Representable: UIViewControllerRepresentable> {
  public let coordinator: Representable.Coordinator
  public let transaction: Transaction
  public let environment: EnvironmentValues

  public init(
    coordinator: Representable.Coordinator,
    transaction: Transaction = Transaction(),
    environment: EnvironmentValues
  ) {
    self.coordinator = coordinator
    self.transaction = transaction
    self.environment = environment
  }
}

@MainActor @preconcurrency
public protocol UIViewControllerRepresentable: SwiftUIRuntime.View where Body == _HostedViewPrimitive {
  associatedtype UIViewControllerType: CrossUIKit.UIViewController
  associatedtype Coordinator = Void
  typealias Context = UIViewControllerRepresentableContext<Self>

  func makeCoordinator() -> Coordinator
  func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> UIViewControllerType
  func updateUIViewController(_ uiViewController: UIViewControllerType, context: UIViewControllerRepresentableContext<Self>)
  static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator)
  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiViewController: UIViewControllerType,
    context: UIViewControllerRepresentableContext<Self>
  ) -> CGSize?
}

extension UIViewControllerRepresentable where Coordinator == Void {
  public func makeCoordinator() -> Void { () }
}

extension UIViewControllerRepresentable {
  public static func dismantleUIViewController(_ uiViewController: UIViewControllerType, coordinator: Coordinator) {}

  public func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiViewController: UIViewControllerType,
    context: UIViewControllerRepresentableContext<Self>
  ) -> CGSize? {
    nil
  }
}

private final class HostedUIVCMountInstance<R: UIViewControllerRepresentable>: _HostedViewMount {
  let viewController: R.UIViewControllerType
  let coordinator: R.Coordinator
  weak var hostContainer: UIView?
  let key: AnyHashable?
  var didAppear = false

  init(
    viewController: R.UIViewControllerType,
    coordinator: R.Coordinator,
    hostContainer: UIView?,
    key: AnyHashable?
  ) {
    self.viewController = viewController
    self.coordinator = coordinator
    self.hostContainer = hostContainer
    self.key = key
  }

  func dismantle() {
    MainActor.assumeIsolated {
      ActiveUIHostingContext.removeMount(for: hostContainer, key: key)
      if didAppear {
        viewController.viewWillDisappear(false)
      }
      R.dismantleUIViewController(viewController, coordinator: coordinator)
      viewController.viewIfLoaded?.removeFromSuperview()
      if didAppear {
        viewController.viewDidDisappear(false)
        didAppear = false
      }
    }
  }
}

private final class HostedUIViewControllerBridge<R: UIViewControllerRepresentable>: _HostedViewBackendBridge {
  let representable: R
  let environment: EnvironmentValues
  weak var hostContainer: UIView?
  var viewKey: AnyHashable?
  private var fallbackInstance: HostedUIVCMountInstance<R>?

  init(representable: R, environment: EnvironmentValues, hostContainer: UIView?) {
    self.representable = representable
    self.environment = environment
    self.hostContainer = hostContainer
  }

  @MainActor
  private func lookupInstance(key: AnyHashable?) -> HostedUIVCMountInstance<R>? {
    let resolvedKey = key ?? viewKey
    if let existing = ActiveUIHostingContext.mount(for: hostContainer, key: resolvedKey) as? HostedUIVCMountInstance<R> {
      return existing
    }
    return fallbackInstance
  }

  @MainActor
  private func ensureInstance(key: AnyHashable?) -> HostedUIVCMountInstance<R> {
    let resolvedKey = key ?? viewKey
    if let existing = lookupInstance(key: resolvedKey) {
      if let container = hostContainer, existing.viewController.view.superview !== container {
        container.addSubview(existing.viewController.view)
      }
      return existing
    }
    let coordinator = representable.makeCoordinator()
    let ctx = UIViewControllerRepresentableContext<R>(coordinator: coordinator, environment: environment)
    let vc = representable.makeUIViewController(context: ctx)
    vc.loadViewIfNeeded()
    _syncTraitCollection(vc.view, environment: environment)
    if let container = hostContainer {
      container.addSubview(vc.view)
    }
    let instance = HostedUIVCMountInstance<R>(
      viewController: vc,
      coordinator: coordinator,
      hostContainer: hostContainer,
      key: resolvedKey
    )
    if hostContainer != nil {
      ActiveUIHostingContext.setMount(instance, for: hostContainer, key: resolvedKey)
    } else {
      fallbackInstance = instance
    }
    return instance
  }

  func measure(key: AnyHashable, proposal: ProposedViewSize) -> SwiftUIRuntime.Size {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: key)
      _syncTraitCollection(instance.viewController.view, environment: environment)
      let ctx = UIViewControllerRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      if let custom = representable.sizeThatFits(proposal, uiViewController: instance.viewController, context: ctx) {
        return SwiftUIRuntime.Size(width: max(0, Double(custom.width)), height: max(0, Double(custom.height)))
      }
      let pref = instance.viewController.preferredContentSize
      let w = proposal.width.map(Double.init) ?? (pref.width > 0 ? Double(pref.width) : 240.0)
      let h = proposal.height.map(Double.init) ?? (pref.height > 0 ? Double(pref.height) : 140.0)
      return SwiftUIRuntime.Size(width: max(0, w), height: max(0, h))
    }
  }

  func createMount(frame: CGRect) -> (mount: any _HostedViewMount, nativeView: NativeAPI.View?) {
    MainActor.assumeIsolated {
      let instance = ensureInstance(key: viewKey)
      let vc = instance.viewController
      _syncTraitCollection(vc.view, environment: environment)
      if !instance.didAppear {
        vc.viewWillAppear(false)
      }
      vc.view.frame = frame
      let ctx = UIViewControllerRepresentableContext<R>(coordinator: instance.coordinator, environment: environment)
      representable.updateUIViewController(vc, context: ctx)
      vc.view.layoutIfNeeded()
      let native: NativeAPI.View?
      if vc.view.prefersNativeBacking {
        native = vc.view.ensureNativeSubtree()
        vc.view.layoutIfNeeded()
      } else {
        native = vc.view.ownedNativeView
      }
      if !instance.didAppear {
        instance.didAppear = true
        vc.viewDidAppear(false)
      }
      return (instance, native)
    }
  }

  func updateMount(_ mount: any _HostedViewMount, frame: CGRect) {
    MainActor.assumeIsolated {
      guard let typed = mount as? HostedUIVCMountInstance<R> else { return }
      let vc = typed.viewController
      _syncTraitCollection(vc.view, environment: environment)
      if vc.view.frame != frame {
        vc.view.frame = frame
      }
      if let container = hostContainer, vc.view.superview !== container {
        container.addSubview(vc.view)
      }
      let ctx = UIViewControllerRepresentableContext<R>(coordinator: typed.coordinator, environment: environment)
      representable.updateUIViewController(vc, context: ctx)
      if vc.view.prefersNativeBacking {
        _ = vc.view.ensureNativeSubtree()
      }
      vc.view.layoutIfNeeded()
    }
  }

  func hitTest(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 3 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else { return false }
      let rootView = instance.viewController.view!
      if rootView.ownedNativeView != nil {
        return false
      }
      let localPt = CGPoint(x: rootPoint.x - rootView.frame.minX, y: rootPoint.y - rootView.frame.minY)
      return rootView.hitTest(localPt, with: nil) != nil
    }
  }

  func handleMouseInput(key: AnyHashable, event: Int, rootPoint: CGPoint, modifiers: EventModifiers) -> Bool {
    guard event == 2 || event == 4 || event == 9 else { return false }
    return MainActor.assumeIsolated {
      guard let instance = lookupInstance(key: key) else { return false }
      let rootView = instance.viewController.view!
      if rootView.ownedNativeView != nil {
        return false
      }
      return _dispatchHostedUIViewMouse(
        rootView: rootView,
        event: event,
        rootPoint: rootPoint,
        modifiers: modifiers
      )
    }
  }
}

extension UIViewControllerRepresentable {
  public var body: _HostedViewPrimitive {
    installAssetResolversOnce()
    let env = EnvironmentValues.current
    let host = env._currentUIHostingView.view ?? ActiveUIHostingContext.currentHostingView
    let bridge = HostedUIViewControllerBridge(representable: self, environment: env, hostContainer: host)
    return _HostedViewPrimitive(
      adapter: bridge,
      bindPath: { key in bridge.viewKey = key },
      measure: { key, proposal in bridge.measure(key: key, proposal: proposal) },
      hitTest: { key, ev, pt, mods in bridge.hitTest(key: key, event: ev, rootPoint: pt, modifiers: mods) },
      mouseInput: { key, ev, pt, mods in bridge.handleMouseInput(key: key, event: ev, rootPoint: pt, modifiers: mods) }
    )
  }
}

// MARK: - UIHostingSizingOptions, _UIHostingView & UIHostingController

public struct UIHostingSizingOptions: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let intrinsicContentSize = UIHostingSizingOptions(rawValue: 1 << 0)
  public static let preferredContentSize = UIHostingSizingOptions(rawValue: 1 << 1)
}

private struct UIHostingScopeView<Content: SwiftUIRuntime.View>: SwiftUIRuntime.View {
  weak var host: UIView?
  let content: Content

  var body: some SwiftUIRuntime.View {
    let _ = { ActiveUIHostingContext.currentHostingView = host }()
    content.environment(\._currentUIHostingView, WeakUIHostingView(view: host))
  }
}

@MainActor
open class _UIHostingView<Content: SwiftUIRuntime.View>: UIView {
  public var sizingOptions: UIHostingSizingOptions = []
  public var safeAreaRegions: SafeAreaRegions = .all
  public var rootView: Content {
    didSet {
      rebuildOrUpdateRenderer(forceRemount: true)
    }
  }

  #if os(Windows)
    private var backend: WindowsDrawingBackend?
    private var keyWindowObserver: NSObjectProtocol?
  #elseif os(Linux) && !CROSS_SWIFTUI_HARMONY
    private var backend: LinuxDrawingBackend?
  #else
    private var backend: NativeViewBackend?
  #endif
  public private(set) var renderer: Renderer?
  private var isFlushingLayout = false

  #if !os(macOS)
    open override var prefersNativeBacking: Bool { true }
  #endif

  public init(rootView: Content) {
    self.rootView = rootView
    super.init(frame: .zero)
    installAssetResolversOnce()
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  open override var intrinsicContentSize: CGSize {
    let proposal = ProposedViewSize(width: bounds.width > 0 ? bounds.width : nil, height: nil)
    if let renderer {
      let measured = renderer.sizeThatFits(proposal)
      return CGSize(width: CGFloat(measured.width), height: CGFloat(measured.height))
    }
    return measureDetached(proposal: proposal)
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    let proposal = ProposedViewSize(
      width: size.width.isFinite && size.width > 0 ? size.width : nil,
      height: size.height.isFinite && size.height > 0 ? size.height : nil
    )
    if let renderer {
      let measured = renderer.sizeThatFits(proposal)
      return CGSize(width: CGFloat(measured.width), height: CGFloat(measured.height))
    }
    return measureDetached(proposal: proposal)
  }

  private func measureDetached(proposal: ProposedViewSize) -> CGSize {
    #if os(Windows)
      let engine = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
    #else
      let engine = LayoutEngine()
    #endif
    let dummy = _HeadlessRenderBackend()
    let isDark = traitCollection.userInterfaceStyle == .dark
    dummy.environment.colorScheme = isDark ? .dark : .light
    let temp = Renderer(
      backend: dummy,
      root: AnyView(rootView),
      size: SwiftUIRuntime.Size(width: Double(proposal.width ?? 420), height: Double(proposal.height ?? 800)),
      layoutEngine: engine
    )
    let sz = temp.sizeThatFits(proposal)
    return CGSize(width: CGFloat(sz.width), height: CGFloat(sz.height))
  }

  open override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      attachIfPossible()
    } else {
      teardownRenderer()
    }
  }

  open override func layoutSubviews() {
    super.layoutSubviews()
    guard !isFlushingLayout else { return }
    if renderer == nil && window != nil {
      attachIfPossible()
    }
    if bounds.width > 0 && bounds.height > 0 {
      renderer?.resize(to: SwiftUIRuntime.Size(width: Double(bounds.width), height: Double(bounds.height)))
    }
    if renderer?.isRendering == true { return }
    isFlushingLayout = true
    defer { isFlushingLayout = false }
    renderer?.renderIfNeeded()
    #if os(Windows)
      backend?.flushSyncPaint()
    #endif
  }

  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    syncAppearanceAndBackground()
    renderer?.setNeedsRender()
  }

  private func syncAppearanceAndBackground() {
    let isDark = traitCollection.userInterfaceStyle == .dark
    #if os(Windows)
      backend?.environmentTransform = { env in
        env.colorScheme = isDark ? .dark : .light
      }
      let bgUIColor = backgroundColor ?? window?.backgroundColor ?? .systemBackground
      let bg = bgUIColor.resolved(for: traitCollection)
      if !isOpaque || bg.a < 0.05 {
        backend?.setBackgroundColor(.clear)
      } else {
        backend?.setBackgroundColor(SwiftUIRuntime.Color(
          red: Double(bg.r), green: Double(bg.g), blue: Double(bg.b), opacity: Double(bg.a)
        ))
      }
    #endif
  }

  private func attachIfPossible() {
    #if CROSS_SWIFTUI_HARMONY
      guard window != nil else { return }
      HarmonyHost.mountRootView(AnyView(UIHostingScopeView(host: self, content: rootView)))
      return
    #else
    guard renderer == nil, let win = window, let nativeWin = win.nativeWindow else { return }
    let targetView: NativeAPI.View
    let isWindowRootHost = (win.rootViewController?.viewIfLoaded === self)
      || (superview === win && win.subviews.count == 1)
    if isWindowRootHost, let cv = nativeWin.contentView {
      self.ownedNativeView = cv
      targetView = cv
    } else if let subNV = ensureNativeView() {
      if let parentNV = superview?.ownedNativeView ?? nativeWin.contentView {
        if subNV.parent?.nativeHandle != parentNV.nativeHandle {
          parentNV.addSubview(subNV)
        }
      }
      targetView = subNV
    } else {
      return
    }

    let initialSize = bounds.width > 0 && bounds.height > 0 ? bounds.size : win.bounds.size
    let w = Double(max(1, initialSize.width))
    let h = Double(max(1, initialSize.height))

    #if os(Windows)
      WindowsDrawingBackend.prepareApplication()
      guard let createdBackend = WindowsDrawingBackend(view: targetView, window: nativeWin, schedulesUpdates: true) else {
        return
      }
      self.backend = createdBackend
      syncAppearanceAndBackground()
      createdBackend.canAcquireControlFocus = { [weak self] in
        self?.window?.isKeyWindow ?? true
      }
      if let obs = keyWindowObserver {
        NotificationCenter.default.removeObserver(obs)
      }
      keyWindowObserver = NotificationCenter.default.addObserver(
        forName: UIWindow.didBecomeKeyNotification, object: win, queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.backend?.applyPendingFocusIfNeeded()
        }
      }

      let layout = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
      ActiveUIHostingContext.currentHostingView = self
      let createdRenderer = Renderer(
        backend: createdBackend,
        root: AnyView(UIHostingScopeView(host: self, content: rootView)),
        size: SwiftUIRuntime.Size(width: w, height: h),
        layoutEngine: layout
      )
      self.renderer = createdRenderer

      createdBackend.onResize = { [weak self, weak createdRenderer] newSize in
        guard let self, let createdRenderer else { return }
        if isWindowRootHost {
          self.frame = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        }
        createdRenderer.resize(to: newSize)
      }
      createdBackend.inputHandler = { [weak self, weak createdRenderer] id, event, point, value, modifiers, text in
        guard let self, let createdRenderer else { return false }
        ActiveUIHostingContext.currentHostingView = self
        if event == 6 {
          let resolvedText = !text.isEmpty ? text : NSHostingView<EmptyView>.keyCharacter(forWin32VK: value)
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
      ActiveUIHostingContext.currentHostingView = nil
    #elseif os(Linux) && !CROSS_SWIFTUI_HARMONY
      guard let createdBackend = LinuxDrawingBackend(window: nativeWin) else { return }
      self.backend = createdBackend
      let layout = LayoutEngine(textMeasurer: createdBackend.measureText)
      ActiveUIHostingContext.currentHostingView = self
      let createdRenderer = Renderer(
        backend: createdBackend,
        root: AnyView(UIHostingScopeView(host: self, content: rootView)),
        size: SwiftUIRuntime.Size(width: w, height: h),
        layoutEngine: layout
      )
      self.renderer = createdRenderer
      createdBackend.onResize = { [weak createdRenderer] newSize in
        createdRenderer?.resize(to: newSize)
      }
      createdBackend.inputHandler = { [weak self, weak createdRenderer] id, event, point, value, modifiers, text in
        ActiveUIHostingContext.currentHostingView = self
        return createdRenderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text,
          updatesPressedState: true
        ) ?? false
      }
      createdBackend.interactionHandler = { [weak createdRenderer] id, interaction in
        createdRenderer?.interact(id, interaction)
      }
      createdRenderer.mount()
      ActiveUIHostingContext.currentHostingView = nil
    #endif
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
    ActiveUIHostingContext.mountsByHost.removeValue(forKey: ObjectIdentifier(self))
    renderer = nil
    backend = nil
  }
}

@MainActor
open class UIHostingController<Content: SwiftUIRuntime.View>: UIViewController {
  public var sizingOptions: UIHostingSizingOptions = [] {
    didSet {
      hostingView.sizingOptions = sizingOptions
      syncPreferredContentSizeIfNeeded()
    }
  }

  public var safeAreaRegions: SafeAreaRegions = .all {
    didSet { hostingView.safeAreaRegions = safeAreaRegions }
  }

  public var rootView: Content {
    get { hostingView.rootView }
    set {
      hostingView.rootView = newValue
      syncPreferredContentSizeIfNeeded()
    }
  }

  public let hostingView: _UIHostingView<Content>

  public init(rootView: Content) {
    installAssetResolversOnce()
    self.hostingView = _UIHostingView(rootView: rootView)
    super.init(nibName: nil, bundle: nil)
    self.view = hostingView
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public func sizeThatFits(in size: CGSize) -> CGSize {
    hostingView.sizeThatFits(size)
  }

  private func syncPreferredContentSizeIfNeeded() {
    if sizingOptions.contains(.preferredContentSize) {
      preferredContentSize = hostingView.intrinsicContentSize
    }
  }
}

// MARK: - UIHostingConfiguration

@MainActor
private final class _UIHostingCellContentView: UIView, UIContentView {
  var configuration: any UIContentConfiguration {
    didSet { applyConfiguration() }
  }

  private var hostedView: UIView?

  init(configuration: any UIContentConfiguration, makeHosted: () -> UIView) {
    self.configuration = configuration
    super.init(frame: .zero)
    let hv = makeHosted()
    hv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(hv)
    self.hostedView = hv
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hostedView?.frame = bounds
  }

  private func applyConfiguration() {
    if let updater = configuration as? any _UIHostingConfigurationUpdating {
      updater._apply(to: &hostedView, in: self)
    }
  }
}

@MainActor
private protocol _UIHostingConfigurationUpdating {
  func _apply(to hostedView: inout UIView?, in container: UIView)
}

@MainActor
public struct UIHostingConfiguration<
  Content: SwiftUIRuntime.View,
  Background: SwiftUIRuntime.View
>: UIContentConfiguration, _UIHostingConfigurationUpdating {
  fileprivate let content: Content
  fileprivate let backgroundView: Background
  fileprivate var edgeInsets: SwiftUIRuntime.EdgeInsets = SwiftUIRuntime.EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
  fileprivate var minWidth: CGFloat?
  fileprivate var minHeight: CGFloat?

  public init(@ViewBuilder content: () -> Content) where Background == EmptyView {
    installAssetResolversOnce()
    self.content = content()
    self.backgroundView = EmptyView()
  }

  fileprivate init(
    content: Content,
    backgroundView: Background,
    edgeInsets: SwiftUIRuntime.EdgeInsets,
    minWidth: CGFloat?,
    minHeight: CGFloat?
  ) {
    self.content = content
    self.backgroundView = backgroundView
    self.edgeInsets = edgeInsets
    self.minWidth = minWidth
    self.minHeight = minHeight
  }

  public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> Self {
    var copy = self
    let v = Double(length)
    if edges.contains(.top) { copy.edgeInsets.top = v }
    if edges.contains(.leading) { copy.edgeInsets.leading = v }
    if edges.contains(.bottom) { copy.edgeInsets.bottom = v }
    if edges.contains(.trailing) { copy.edgeInsets.trailing = v }
    return copy
  }

  public func margins(_ edges: Edge.Set = .all, _ insets: SwiftUIRuntime.EdgeInsets) -> Self {
    var copy = self
    if edges.contains(.top) { copy.edgeInsets.top = insets.top }
    if edges.contains(.leading) { copy.edgeInsets.leading = insets.leading }
    if edges.contains(.bottom) { copy.edgeInsets.bottom = insets.bottom }
    if edges.contains(.trailing) { copy.edgeInsets.trailing = insets.trailing }
    return copy
  }

  public func margins(_ edges: Edge.Set = .all, _ insets: NSDirectionalEdgeInsets) -> Self {
    margins(edges, SwiftUIRuntime.EdgeInsets(insets))
  }

  public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    var copy = self
    if let width { copy.minWidth = width }
    if let height { copy.minHeight = height }
    return copy
  }

  public func background<B: SwiftUIRuntime.View>(
    @ViewBuilder _ background: () -> B
  ) -> UIHostingConfiguration<Content, B> {
    UIHostingConfiguration<Content, B>(
      content: content,
      backgroundView: background(),
      edgeInsets: edgeInsets,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  private func composedRootView() -> AnyView {
    let padded = content
      .padding(edgeInsets)
      .frame(minWidth: minWidth, minHeight: minHeight, alignment: .leading)
      .background { backgroundView }
    return AnyView(padded)
  }

  public func makeContentView() -> any UIView & UIContentView {
    let root = composedRootView()
    return _UIHostingCellContentView(configuration: self) {
      _UIHostingView(rootView: root)
    }
  }

  public func updated(for state: any UIConfigurationState) -> Self {
    self
  }

  fileprivate func _apply(to hostedView: inout UIView?, in container: UIView) {
    let root = composedRootView()
    if let existing = hostedView as? _UIHostingView<AnyView> {
      existing.rootView = root
    } else {
      hostedView?.removeFromSuperview()
      let created = _UIHostingView(rootView: root)
      created.frame = container.bounds
      created.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(created)
      hostedView = created
    }
  }
}

// MARK: - @UIApplicationDelegateAdaptor

@MainActor
@propertyWrapper
public struct UIApplicationDelegateAdaptor<
  DelegateType: NSObject & UIApplicationDelegate
>: _ApplicationDelegateProvider {
  public let wrappedValue: DelegateType

  public init(_ delegateType: DelegateType.Type = DelegateType.self) {
    installAssetResolversOnce()
    self.wrappedValue = delegateType.init()
  }

  public init(_ makeDelegate: @autoclosure @escaping () -> DelegateType) {
    installAssetResolversOnce()
    self.wrappedValue = makeDelegate()
  }

  public func _installDelegate() {
    installAssetResolversOnce()
    UIApplication.shared._installRetainedDelegate(wrappedValue)
  }
}
