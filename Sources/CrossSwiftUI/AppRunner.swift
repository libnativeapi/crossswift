import CrossAppKit
import Foundation
import NativeAPI
import Observation
import SwiftUIRuntime

#if os(Linux)
  import CGTK3
#endif

/// Collects leaf scenes recursively from `@SceneBuilder` trees (`TupleScene`, custom `Scene`s).
@MainActor
private func flattenScenes(_ scene: any Scene) -> [any Scene] {
  if let composite = scene as? any _CompositeScene {
    return composite._childScenes.flatMap { flattenScenes($0) }
  }
  if scene is EmptyScene || scene is any _WindowScene || scene is any _MenuBarExtraScene {
    return [scene]
  }
  let body = scene.body
  if body is EmptyScene { return [scene] }
  return flattenScenes(body)
}

/// Hosts a SwiftUI `MenuBarExtra` scene on a `CrossAppKit.NSStatusItem` (`NativeAPI.TrayIcon`).
@MainActor
private final class MenuBarExtraHost<A: App>: NSMenuDelegate {
  private let app: A
  private let index: Int
  private var statusItem: NSStatusItem?

  init(app: A, index: Int) {
    self.app = app
    self.index = index
    refresh()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let extra = currentExtra() else { return }
    menu.removeAllItems()
    populateMenu(menu, from: extra._makeContentView())
  }

  private func currentExtra() -> (any _MenuBarExtraScene)? {
    let scenes = flattenScenes(app.body).compactMap { $0 as? any _MenuBarExtraScene }
    guard index < scenes.count else { return nil }
    return scenes[index]
  }

  func refresh() {
    var inserted = true
    var extraSnapshot: (any _MenuBarExtraScene)?
    withObservationTracking {
      if let extra = currentExtra() {
        extraSnapshot = extra
        inserted = extra._isInserted?.wrappedValue ?? true
      } else {
        inserted = false
      }
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.refresh()
      }
    }

    guard inserted, let extra = extraSnapshot else {
      statusItem?.isVisible = false
      return
    }

    if statusItem == nil {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
    guard let item = statusItem else { return }
    item.isVisible = true

    // Evaluate label view to extract icon or text
    let labelTree = evaluateDetachedTree(extra._makeLabelView())
    if let imgPath = findFirstImagePath(in: labelTree), !imgPath.isEmpty, !imgPath.hasPrefix("sf://") {
      if let nsImg = NSImage(contentsOfFile: imgPath) {
        item.button?.image = nsImg
      }
    }
    let labelText = findFirstText(in: labelTree)
    if !labelText.isEmpty {
      item.button?.title = labelText
    } else if !extra._title.isEmpty {
      item.button?.toolTip = extra._title
    }
    item.syncButtonAppearance()

    // Rebuild context menu on open so dynamic labels/states stay fresh
    let menu = NSMenu(title: extra._title)
    menu.delegate = self
    populateMenu(menu, from: extra._makeContentView())
    item.menu = menu
  }

  private func evaluateDetachedTree(_ root: AnyView) -> Element? {
    let renderer = Renderer(
      backend: _HeadlessRenderBackend(),
      root: root,
      size: SwiftUIRuntime.Size(width: 240, height: 400)
    )
    renderer.mount()
    return renderer.tree
  }

  private func findFirstImagePath(in node: Element?) -> String? {
    guard let node else { return nil }
    if node.kind == .image && !node.props.imagePath.isEmpty {
      return node.props.imagePath
    }
    for child in node.children {
      if let p = findFirstImagePath(in: child) { return p }
    }
    return nil
  }

  private func findFirstText(in node: Element?) -> String {
    guard let node else { return "" }
    if node.kind == .text && !node.props.text.isEmpty { return node.props.text }
    if !node.props.accessibilityLabel.isEmpty { return node.props.accessibilityLabel }
    for child in node.children {
      let t = findFirstText(in: child)
      if !t.isEmpty { return t }
    }
    return ""
  }

  private func populateMenu(_ menu: NSMenu, from content: AnyView) {
    guard let tree = evaluateDetachedTree(content) else { return }
    func walk(_ node: Element) {
      if node.kind == .button || node.kind == .styledButton {
        let title = !node.props.text.isEmpty ? node.props.text : findFirstText(in: node)
        let keyEq = node.props.keyboardShortcut.map { String($0.key.character) } ?? ""
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: keyEq)
        mi.isEnabled = node.props.enabled
        if let act = node.action {
          mi.actionClosure = act
        }
        menu.addItem(mi)
        return
      }
      if node.props.accessibilityIdentifier == "SwiftUI.Divider" {
        menu.addItem(.separator())
        return
      }
      for child in node.children {
        walk(child)
      }
    }
    walk(tree)
  }
}

@MainActor
public func runApp<A: App>(_ app: A) {
  installAssetResolversOnce()

  let scenes = flattenScenes(app.body)
  let primaryWindowScene = scenes.first(where: { $0 is any _WindowScene }) as? any _WindowScene
  #if os(Windows)
    if let identifier = primaryWindowScene?._applicationIdentifier {
      WindowsDrawingBackend.setApplicationIdentifier(identifier)
    }
  #endif

  let application = NativeAPI.Application.shared
  _ = application.isRunning()
  #if os(Linux)
    if let identifier = primaryWindowScene?._applicationIdentifier,
      let gtkApplication = g_application_get_default()
    {
      precondition(g_application_id_is_valid(identifier) != 0, "Invalid application identifier")
      g_application_set_application_id(gtkApplication, identifier)
    }
  #endif

  // Install @NSApplicationDelegateAdaptor if present on `app`
  for child in Mirror(reflecting: app).children {
    if let provider = child.value as? any _ApplicationDelegateProvider {
      provider._installDelegate()
    }
  }

  let menuExtras = scenes.enumerated().compactMap { _, s in s as? any _MenuBarExtraScene }
  var menuHosts: [MenuBarExtraHost<A>] = []
  for idx in menuExtras.indices {
    menuHosts.append(MenuBarExtraHost(app: app, index: idx))
  }

  if let windowScene = scenes.first(where: { $0 is any _WindowScene }) as? any _WindowScene {
    guard let window = NativeAPI.Window.create() else {
      fatalError("nativeapi failed to create a window")
    }

    let title = windowScene._windowTitle
    window.setTitle(title.isEmpty ? "CrossSwiftUI" : title)

    var initialWidth = windowScene._defaultSize.width
    var initialHeight = windowScene._defaultSize.height
    let position = window.position
    let display =
      NativeAPI.DisplayManager.shared.getAll().first {
        let area = $0.workArea
        return position.x >= area.x && position.x < area.x + area.width
          && position.y >= area.y && position.y < area.y + area.height
      } ?? NativeAPI.DisplayManager.shared.getPrimary()
    if let display {
      let available = display.workArea
      if available.width > 0 && available.height > 0 {
        initialWidth = min(initialWidth, max(1, available.width - 32))
        initialHeight = min(initialHeight, max(1, available.height - 80))
      }
    }
    window.setContentSize(NativeAPI.Size(width: initialWidth, height: initialHeight))
    window.center()

    #if os(Windows)
      guard let backend = WindowsDrawingBackend(window: window, schedulesUpdates: true) else {
        fatalError("Could not attach the Windows drawing backend")
      }
      let layout = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
    #elseif os(Linux)
      guard let backend = LinuxDrawingBackend(window: window) else {
        fatalError("Could not attach the Linux drawing backend")
      }
      let layout = LayoutEngine(textMeasurer: backend.measureText)
    #else
      guard let backend = NativeViewBackend(window: window) else {
        fatalError("nativeapi window has no content view")
      }
      let layout = LayoutEngine()
    #endif

    let renderer = Renderer(
      backend: backend,
      root: windowScene._makeRootView(),
      size: SwiftUIRuntime.Size(width: initialWidth, height: initialHeight),
      layoutEngine: layout
    )
    backend.onResize = { [weak renderer] size in
      renderer?.resize(to: size)
    }
    #if os(Windows) || os(Linux)
      #if os(Linux)
        let usesCanvasPressState = true
      #else
        let usesCanvasPressState = false
      #endif
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text,
          updatesPressedState: usesCanvasPressState) ?? false
      }
      backend.interactionHandler = { [weak renderer] id, interaction in
        renderer?.interact(id, interaction)
      }
    #endif
    renderer.mount()
    if let path = ProcessInfo.processInfo.environment["CROSS_SWIFTUI_TREE_PATH"],
      let tree = renderer.tree
    {
      func encode(_ node: Element) -> [String: Any] {
        [
          "kind": node.kind.description, "text": node.props.text, "id": node.id.rawValue,
          "x": node.frame.minX, "y": node.frame.minY, "width": node.frame.width,
          "height": node.frame.height, "children": node.children.map(encode),
        ]
      }
      if let data = try? JSONSerialization.data(
        withJSONObject: encode(tree), options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: URL(fileURLWithPath: path))
      }
    }
    window.show()
    #if os(Windows) || os(Linux)
      backend.focusInitialControl()
    #endif

    let shownSize = window.contentSize
    if shownSize.width > 0, shownSize.height > 0 {
      renderer.resize(
        to: SwiftUIRuntime.Size(width: shownSize.width, height: shownSize.height)
      )
    }

    if CommandLine.arguments.contains("--smoke") {
      startSmokeTimer()
    }

    if NSApplication.shared.delegate != nil {
      NSApplication.shared.finishLaunching()
    }
    withExtendedLifetime((renderer, menuHosts)) {
      _ = application.runWithWindow(window)
    }
    return
  }

  // Accessory / MenuBarExtra-only app (such as Tinycast): run via NSApplication.shared.run()
  if CommandLine.arguments.contains("--smoke") {
    startSmokeTimer()
  }
  withExtendedLifetime(menuHosts) {
    NSApplication.shared.run()
  }
}

private func startSmokeTimer() {
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    NativeAPI.Application.shared.quit(0)
  }
}

extension App {
  /// The `@main` entry point. `SwiftUI` re-exports this extension, so an app
  /// only needs `import SwiftUI`.
  public static func main() {
    runApp(Self())
  }
}
