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

/// Collects `.commands { ... }` providers attached anywhere in the scene hierarchy.
@MainActor
private func collectCommandSections(_ scene: any Scene) -> [_ResolvedCommandSection] {
  var result: [_ResolvedCommandSection] = []
  if let provider = scene as? any _CommandsProvidingScene {
    result.append(contentsOf: provider._makeCommandSections())
    result.append(contentsOf: collectCommandSections(provider._baseScene))
    return result
  }
  if let composite = scene as? any _CompositeScene {
    for child in composite._childScenes {
      result.append(contentsOf: collectCommandSections(child))
    }
    return result
  }
  let body = scene.body
  if !(body is EmptyScene) {
    result.append(contentsOf: collectCommandSections(body))
  }
  return result
}

@MainActor
private func evaluateDetachedTree(_ root: AnyView) -> Element? {
  let renderer = Renderer(
    backend: _HeadlessRenderBackend(),
    root: root,
    size: SwiftUIRuntime.Size(width: 240, height: 400)
  )
  renderer.mount()
  return renderer.tree
}

@MainActor
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

@MainActor
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

@MainActor
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

/// Manages primary and secondary desktop windows (`WindowGroup`, `Window`, `Settings`)
/// and provides `@Environment(\.openWindow)` / `@Environment(\.dismissWindow)`.
@MainActor
private final class DesktopSceneCoordinator {
  final class ManagedWindow {
    let id: String
    let window: NativeAPI.Window
    let renderer: Renderer
    let retainBackend: AnyObject
    var closeListener: ListenerId?

    init(id: String, window: NativeAPI.Window, renderer: Renderer, backend: AnyObject) {
      self.id = id
      self.window = window
      self.renderer = renderer
      self.retainBackend = backend
    }
  }

  private let windowScenes: [any _WindowScene]
  private var openWindows: [String: ManagedWindow] = [:]
  private var instanceCounter = 0

  init(windowScenes: [any _WindowScene]) {
    self.windowScenes = windowScenes
  }

  func open(id: String?, value: Any?) {
    let scene: (any _WindowScene)?
    if let id {
      scene = windowScenes.first(where: { $0._windowID == id })
    } else {
      scene = windowScenes.first(where: { $0._opensAtLaunch }) ?? windowScenes.first
    }
    guard let scene else { return }

    let instanceKey: String
    if scene._isSingleInstanceWindow, let wid = scene._windowID {
      instanceKey = wid
      if let existing = openWindows[instanceKey] {
        existing.window.show()
        existing.window.focus()
        return
      }
    } else {
      instanceCounter += 1
      instanceKey = "\(scene._windowID ?? "window")-\(instanceCounter)"
    }

    let rootView = value.flatMap { scene._makeRootView(for: $0) } ?? scene._makeRootView()
    _ = createAndMountWindow(scene: scene, key: instanceKey, rootView: rootView, dumpTree: false)
  }

  func dismiss(id: String?, fallbackKey: String) {
    let key = id ?? fallbackKey
    if let managed = openWindows.removeValue(forKey: key) {
      if let listener = managed.closeListener {
        _ = managed.window.removeListener(listener)
      }
      _ = managed.window.close()
    } else if let id, let match = openWindows.first(where: { $0.key == id || $0.key.hasPrefix("\(id)-") }) {
      openWindows.removeValue(forKey: match.key)
      if let listener = match.value.closeListener {
        _ = match.value.window.removeListener(listener)
      }
      _ = match.value.window.close()
    }
  }

  @discardableResult
  func createAndMountWindow(
    scene: any _WindowScene,
    key: String,
    rootView: AnyView,
    dumpTree: Bool
  ) -> ManagedWindow {
    guard let window = NativeAPI.Window.create() else {
      fatalError("nativeapi failed to create a window")
    }

    let title = scene._windowTitle
    window.setTitle(title.isEmpty ? "CrossSwiftUI" : title)

    var initialWidth = scene._defaultSize.width
    var initialHeight = scene._defaultSize.height
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

    let openAction = OpenWindowAction { [weak self] targetID, targetValue in
      self?.open(id: targetID, value: targetValue)
    }
    let dismissAction = DismissWindowAction { [weak self] targetID in
      self?.dismiss(id: targetID, fallbackKey: key)
    }

    #if os(Windows)
      guard let backend = WindowsDrawingBackend(window: window, schedulesUpdates: true) else {
        fatalError("Could not attach the Windows drawing backend")
      }
      backend.environmentTransform = { env in
        env.openWindow = openAction
        env.dismissWindow = dismissAction
      }
      let layout = LayoutEngine(textMeasurer: WindowsDrawingBackend.measureText)
    #elseif os(Linux)
      guard let backend = LinuxDrawingBackend(window: window) else {
        fatalError("Could not attach the Linux drawing backend")
      }
      backend.environmentTransform = { env in
        env.openWindow = openAction
        env.dismissWindow = dismissAction
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
      root: rootView,
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

    if dumpTree,
      let path = ProcessInfo.processInfo.environment["CROSS_SWIFTUI_TREE_PATH"],
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

    let managed = ManagedWindow(id: key, window: window, renderer: renderer, backend: backend)
    managed.closeListener = window.addListener { [weak self] event in
      if case .closed = event {
        Task { @MainActor in
          self?.openWindows.removeValue(forKey: key)
        }
      }
    }
    openWindows[key] = managed
    return managed
  }
}

/// Installs `.commands { ... }` sections into `NSApplication.shared.mainMenu`.
@MainActor
private func installMainMenuCommands(
  sections: [_ResolvedCommandSection],
  coordinator: DesktopSceneCoordinator,
  hasSettingsScene: Bool
) {
  guard !sections.isEmpty || hasSettingsScene else { return }
  let mainMenu = NSApplication.shared.mainMenu ?? NSMenu(title: "MainMenu")
  var submenusByTitle: [String: NSMenu] = [:]

  func submenu(titled title: String) -> NSMenu {
    if let existing = submenusByTitle[title] { return existing }
    let menu = NSMenu(title: title)
    let topItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    topItem.submenu = menu
    mainMenu.addItem(topItem)
    submenusByTitle[title] = menu
    return menu
  }

  if hasSettingsScene {
    let appMenu = submenu(titled: "App")
    let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
    settingsItem.actionClosure = { [weak coordinator] in
      coordinator?.open(id: Settings<EmptyView>.windowID, value: nil)
    }
    appMenu.addItem(settingsItem)
  }

  for section in sections {
    let menu = submenu(titled: section.title)
    if !menu.items.isEmpty {
      menu.addItem(.separator())
    }
    populateMenu(menu, from: section.content())
  }
  NSApplication.shared.mainMenu = mainMenu
}

/// Hosts a SwiftUI `MenuBarExtra` scene on a `CrossAppKit.NSStatusItem` (`NativeAPI.TrayIcon`).
@MainActor
private final class MenuBarExtraHost<A: App>: NSMenuDelegate {
  private let app: A
  private let index: Int
  private var statusItem: NSStatusItem?
  private var popoverPanel: NSPanel?

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

  private func togglePopoverWindow(for extra: any _MenuBarExtraScene) {
    if let panel = popoverPanel, panel.isVisible {
      panel.orderOut(nil)
      return
    }
    let hosting = NSHostingView(rootView: extra._makeContentView())
    let intrinsic = hosting.intrinsicContentSize
    let width = max(240, min(520, intrinsic.width > 10 ? Double(intrinsic.width) : 320))
    let height = max(140, min(640, intrinsic.height > 10 ? Double(intrinsic.height) : 280))
    let panel = popoverPanel ?? NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = extra._title
    panel.level = .floating
    panel.contentView = hosting
    panel.setContentSize(NSSize(width: width, height: height))
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    popoverPanel = panel
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
      popoverPanel?.orderOut(nil)
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

    if extra._style == .window {
      item.menu = nil
      item.onLeftClick = { [weak self] in
        guard let self, let latest = self.currentExtra() else { return }
        self.togglePopoverWindow(for: latest)
      }
    } else {
      item.onLeftClick = nil
      let menu = NSMenu(title: extra._title)
      menu.delegate = self
      populateMenu(menu, from: extra._makeContentView())
      item.menu = menu
    }
  }
}

@MainActor
public func runApp<A: App>(_ app: A) {
  installAssetResolversOnce()
  NSApplication.shared.ensureSingleInstance()

  let rootScene = app.body
  let scenes = flattenScenes(rootScene)
  let allWindowScenes = scenes.compactMap { $0 as? any _WindowScene }
  let primaryWindowScene = allWindowScenes.first(where: { $0._opensAtLaunch }) ?? allWindowScenes.first
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

  let coordinator = DesktopSceneCoordinator(windowScenes: allWindowScenes)
  let commandSections = collectCommandSections(rootScene)
  let hasSettings = allWindowScenes.contains(where: { $0._windowID == Settings<EmptyView>.windowID })
  installMainMenuCommands(sections: commandSections, coordinator: coordinator, hasSettingsScene: hasSettings)

  let menuExtras = scenes.enumerated().compactMap { _, s in s as? any _MenuBarExtraScene }
  var menuHosts: [MenuBarExtraHost<A>] = []
  for idx in menuExtras.indices {
    menuHosts.append(MenuBarExtraHost(app: app, index: idx))
  }

  if let windowScene = primaryWindowScene, windowScene._opensAtLaunch {
    let primaryKey = windowScene._windowID ?? "primary"
    let primary = coordinator.createAndMountWindow(
      scene: windowScene,
      key: primaryKey,
      rootView: windowScene._makeRootView(),
      dumpTree: true
    )
    NSApplication.shared._primarySceneWindow = primary.window

    if CommandLine.arguments.contains("--smoke") {
      startSmokeTimer()
    }

    NSApplication.shared.finishLaunching()
    withExtendedLifetime((coordinator, primary, menuHosts)) {
      _ = application.runWithWindow(primary.window)
    }
    return
  }

  // Accessory / MenuBarExtra-only app: run via NSApplication.shared.run()
  if CommandLine.arguments.contains("--smoke") {
    startSmokeTimer()
  }
  withExtendedLifetime((coordinator, menuHosts)) {
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
    installAssetResolversOnce()
    NSApplication.shared.ensureSingleInstance()
    runApp(Self())
  }
}
