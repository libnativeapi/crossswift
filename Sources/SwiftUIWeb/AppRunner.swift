import Foundation
import JavaScriptEventLoop
import JavaScriptKit
import SwiftUIRuntime

private struct HotReloadEnvelope: Codable {
  let version: Int
  let state: String
  let dom: DOMHotReloadState?
}

@MainActor private var browserRenderer: Renderer?
@MainActor private var browserBackend: WebBackend?
@MainActor private var hotReloadClosures: [JSClosure] = []
@MainActor private var isUnmounted = false

@MainActor private func installWebResources(
  manifest overrideManifest: JSObject? = nil,
  resetCatalog: Bool = false
) {
  if let navigator = JSObject.global.navigator.object,
     let lang = navigator.language.string, !lang.isEmpty
  {
    XCStringsCatalog.shared.preferredLanguage = lang
  }

  if let overrideManifest {
    JSObject.global.__crossSwiftUIResources = .object(overrideManifest)
  }

  if resetCatalog {
    XCStringsCatalog.shared.reset()
  }

  guard let manifest = overrideManifest ?? JSObject.global.__crossSwiftUIResources.object else {
    if resetCatalog {
      SwiftUIRuntime.Image.assetPathResolver = nil
    }
    return
  }

  if let xcstrings = manifest.xcstrings.object,
     let length = xcstrings.length.number
  {
    for i in 0..<Int(length) {
      if let text = xcstrings[i].string, let data = text.data(using: .utf8) {
        _ = XCStringsCatalog.shared.load(data: data, merge: true)
      }
    }
  }

  if let imagesObj = manifest.images.object,
     let objectCtor = JSObject.global.Object.object,
     let keys = objectCtor.keys!(imagesObj).object,
     let length = keys.length.number
  {
    var exactMap: [String: String] = [:]
    var lowerMap: [String: String] = [:]
    for i in 0..<Int(length) {
      guard let key = keys[i].string, let value = imagesObj[key].string else { continue }
      exactMap[key] = value
      lowerMap[key.lowercased()] = value
    }
    if !exactMap.isEmpty {
      SwiftUIRuntime.Image.assetPathResolver = { name, _ in
        exactMap[name] ?? lowerMap[name.lowercased()]
      }
    } else if resetCatalog {
      SwiftUIRuntime.Image.assetPathResolver = nil
    }
  } else if resetCatalog {
    SwiftUIRuntime.Image.assetPathResolver = nil
  }
}

@MainActor private func teardownBrowserApp() {
  guard !isUnmounted else { return }
  isUnmounted = true

  if let renderer = browserRenderer {
    renderer.unmount()
    browserRenderer = nil
  }
  if let backend = browserBackend {
    backend.disconnect()
    browserBackend = nil
  }
  JSObject.global.__crossSwiftUIHotReload = .undefined
  hotReloadClosures.removeAll()
}

@MainActor private func installHotReloadBridge() {
  let exportState = JSClosure { _ in
    guard !isUnmounted else { return .string("") }
    let swiftState = StateRegistry.shared.exportHotReloadSnapshotJSON()
    let domState = browserBackend?.captureDOMState()
    let envelope = HotReloadEnvelope(version: 1, state: swiftState, dom: domState)
    if let data = try? JSONEncoder().encode(envelope),
       let json = String(data: data, encoding: .utf8)
    {
      return .string(json)
    }
    return .string(swiftState)
  }

  let unmount = JSClosure { _ in
    teardownBrowserApp()
    return .undefined
  }

  let reloadResources = JSClosure { args in
    guard !isUnmounted else { return .undefined }
    let manifest = args.first?.object
    installWebResources(manifest: manifest, resetCatalog: true)
    browserRenderer?.reloadResources()
    browserRenderer?.renderIfNeeded()
    return .undefined
  }

  hotReloadClosures = [exportState, unmount, reloadResources]
  let bridge: JSObject = [
    "exportState": exportState.jsValue,
    "unmount": unmount.jsValue,
    "reloadResources": reloadResources.jsValue,
  ]
  JSObject.global.__crossSwiftUIHotReload = .object(bridge)
}

@MainActor
private func _webFlattenScenes(_ scene: any Scene) -> [any Scene] {
  if let composite = scene as? any _CompositeScene {
    return composite._childScenes.flatMap { _webFlattenScenes($0) }
  }
  if scene is EmptyScene || scene is any _WindowScene || scene is any _MenuBarExtraScene {
    return [scene]
  }
  let body = scene.body
  if body is EmptyScene { return [scene] }
  return _webFlattenScenes(body)
}

@MainActor public func runApp<A: App>(_ app: A) {
  JavaScriptEventLoop.installGlobalExecutor()
  isUnmounted = false
  installWebResources()

  var pendingDOMState: DOMHotReloadState?
  var didImportHotState = false
  if let rawHotState = JSObject.global.__crossSwiftUIHotState.string, !rawHotState.isEmpty {
    JSObject.global.__crossSwiftUIHotState = .undefined
    if let data = rawHotState.data(using: .utf8),
       let envelope = try? JSONDecoder().decode(HotReloadEnvelope.self, from: data)
    {
      didImportHotState = StateRegistry.shared.importHotReloadSnapshot(envelope.state)
      pendingDOMState = envelope.dom
    } else {
      didImportHotState = StateRegistry.shared.importHotReloadSnapshot(rawHotState)
    }
  }

  let scenes = _webFlattenScenes(app.body)
  guard let scene = scenes.first(where: { ($0 as? any _WindowScene)?._opensAtLaunch == true }) as? any _WindowScene
    ?? scenes.first(where: { $0 is any _WindowScene }) as? any _WindowScene
  else {
    fatalError("CrossSwiftUI requires WindowGroup as the top-level Scene")
  }
  let document = JSObject.global.document.object!
  guard let host = document.getElementById!("swiftui-root").object else {
    fatalError("CrossSwiftUI requires a #swiftui-root element")
  }
  document.title = .string(scene._windowTitle.isEmpty ? "CrossSwiftUI" : scene._windowTitle)

  let backend = WebBackend(document: document, host: host)
  backend.environment.openURL = OpenURLAction { url in
    _ = JSObject.global.window.object?.open!(url.absoluteString, "_blank", "noopener")
    return .handled
  }
  let renderer = Renderer(
    backend: backend,
    root: scene._makeRootView(),
    size: backend.size,
    layoutEngine: LayoutEngine(textMeasurer: backend.measureText)
  )
  renderer.usesCustomScrollIndicators = false
  browserBackend = backend
  browserRenderer = renderer
  backend.connect(renderer)
  installHotReloadBridge()
  renderer.mount()

  if didImportHotState {
    StateRegistry.shared.finishHotReloadRestore()
  }
  if let domState = pendingDOMState {
    backend.restoreDOMState(domState, renderer: renderer)
    renderer.renderIfNeeded()
  }
}

extension App {
  public static func main() {
    runApp(Self())
  }
}
