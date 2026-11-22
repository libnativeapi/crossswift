import Foundation
import JavaScriptEventLoop
import JavaScriptKit
import SwiftUIRuntime

@MainActor private var browserRenderer: Renderer?

@MainActor private func installWebResources() {
  if let navigator = JSObject.global.navigator.object,
     let lang = navigator.language.string, !lang.isEmpty
  {
    XCStringsCatalog.shared.preferredLanguage = lang
  }

  guard let manifest = JSObject.global.__crossSwiftUIResources.object else {
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
    }
  }
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
  installWebResources()
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
  browserRenderer = renderer
  backend.connect(renderer)
  renderer.mount()
}

extension App {
  public static func main() {
    runApp(Self())
  }
}
