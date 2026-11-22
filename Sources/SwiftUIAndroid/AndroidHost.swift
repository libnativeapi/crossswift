import CSwiftUIAndroid
import Foundation
import SwiftUIRuntime

private func encodeARGB(_ color: Color) -> UInt32 {
  func byte(_ value: Double) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
  return byte(color.opacity) << 24 | byte(color.red) << 16 | byte(color.green) << 8 | byte(color.blue)
}

private struct EncodedVectorLayer: Encodable {
  let commands: [Double]
  let fill: UInt32?
  let stroke: UInt32?
  let strokeWidth: Double
}

private struct EncodedAlertAction: Encodable {
  let title: String
  let role: String
  let enabled: Bool
}

private struct SnapshotEnvelope: Encodable {
  let nodes: [RenderNode]
  let hasActiveAnimations: Bool
}

private struct RenderNode: Encodable {
  let id: Int
  let kind: String
  let button: Bool
  let text: String
  let placeholder: String?
  let secure: Bool
  let multiline: Bool
  let imagePath: String?
  let vectorBounds: [Double]?
  let vectorLayers: [EncodedVectorLayer]?
  let x, y, width, height: Double
  let fontSize: Double
  let fontFamily: String
  let fontWeight: Int
  let alignment: String
  let lineSpacing: Double
  let lineLimit: Int?
  let enabled: Bool
  let opacity: Double
  let rotation: Double
  let scaleX: Double
  let scaleY: Double
  let clipCommands: [Double]?
  let shadowColor: UInt32?
  let shadowRadius: Double
  let shadowX: Double
  let shadowY: Double
  let foreground: UInt32?
  let background: UInt32?
  let borderColor: UInt32?
  let borderWidth: Double
  let cornerRadius: Double
  let accessibilityLabel: String
  let accessibilityHidden: Bool
  let draggable: Bool
  // Scroll & clip container properties
  let scrollVertical: Bool
  let scrollHorizontal: Bool
  let scrollOffsetX: Double
  let scrollOffsetY: Double
  let contentWidth: Double
  let contentHeight: Double
  let children: [RenderNode]?
  // Gradient properties
  let gradientKind: String?
  let gradientColors: [UInt32]?
  let gradientStops: [Double]?
  let gradientStartX: Double
  let gradientStartY: Double
  let gradientEndX: Double
  let gradientEndY: Double
  // Semantic control properties (dual-style Android Native M3 / iOS-like)
  let boolValue: Bool
  let doubleValue: Double
  let minValue: Double
  let maxValue: Double
  let stepValue: Double
  let intValue: Int
  let items: [String]?
  let itemIcons: [String]?
  let title: String?
  let subtitle: String?
  let styleName: String?
  let tint: UInt32?
  let canGoBack: Bool
  let isIndeterminate: Bool
  let alertActions: [EncodedAlertAction]?

  init(
    _ element: Element,
    originX: Double,
    originY: Double,
    inheritedEnabled: Bool = true,
    kindOverride: String? = nil,
    children: [RenderNode]? = nil,
    contentWidth: Double = 0,
    contentHeight: Double = 0
  ) {
    let props = element.props
    let font = props.font ?? .body
    let sem = props.semanticControl
    id = element.id.rawValue

    var resolvedKind: String
    var resolvedImagePath: String? = nil
    var resolvedVectorBounds: [Double]? = nil
    var resolvedVectorLayers: [EncodedVectorLayer]? = nil
    var resolvedGradKind: String? = nil
    var resolvedGradColors: [UInt32]? = nil
    var resolvedGradStops: [Double]? = nil
    var gSX = 0.0, gSY = 0.0, gEX = 0.0, gEY = 1.0

    if let kindOverride {
      resolvedKind = kindOverride
    } else if let sem {
      resolvedKind = sem.kind == "button" ? "semanticButton" : sem.kind
    } else {
      switch element.kind {
      case .button: resolvedKind = "button"
      case .styledButton: resolvedKind = "hitArea"
      case .textField: resolvedKind = "textField"
      case .shape: resolvedKind = "shape"
      case .gradient:
        resolvedKind = "gradient"
        if let grad = props.gradient {
          resolvedGradKind = "linear"
          resolvedGradColors = grad.colors.map(encodeARGB)
          resolvedGradStops = nil
          gSX = Double(grad.start.x)
          gSY = Double(grad.start.y)
          gEX = Double(grad.end.x)
          gEY = Double(grad.end.y)
        }
      case .path:
        resolvedKind = "vector"
        let b = element.frame
        resolvedVectorBounds = [0, 0, b.width, b.height]
        resolvedVectorLayers = [
          EncodedVectorLayer(
            commands: props.path.commands,
            fill: props.foreground.map(encodeARGB),
            stroke: props.borderWidth > 0 ? encodeARGB(props.borderColor) : nil,
            strokeWidth: props.borderWidth
          )
        ]
      case .image:
        let rawPath = props.imagePath
        if !rawPath.isEmpty, let vec = VectorImage.load(rawPath) {
          resolvedKind = "vector"
          resolvedVectorBounds = [vec.bounds.minX, vec.bounds.minY, vec.bounds.width, vec.bounds.height]
          let isTemplate = rawPath.hasPrefix("sf://") || props.imageTemplate
          let tintARGB = props.foreground.map(encodeARGB)
          resolvedVectorLayers = vec.layers.map { layer in
            let fillColor: UInt32?
            if let fill = layer.fill {
              fillColor = isTemplate ? (tintARGB ?? encodeARGB(fill)) : encodeARGB(fill)
            } else {
              fillColor = nil
            }
            let strokeColor: UInt32?
            if let stroke = layer.stroke {
              strokeColor = isTemplate ? (tintARGB ?? encodeARGB(stroke)) : encodeARGB(stroke)
            } else {
              strokeColor = nil
            }
            return EncodedVectorLayer(
              commands: layer.path.commands,
              fill: fillColor,
              stroke: strokeColor,
              strokeWidth: layer.strokeWidth
            )
          }
        } else {
          resolvedKind = "image"
          resolvedImagePath = rawPath.isEmpty ? nil : rawPath
        }
      default:
        resolvedKind = "text"
      }
    }

    kind = resolvedKind
    button = resolvedKind == "button"
    text = props.renderedText ?? props.text
    placeholder = element.kind == .textField ? props.placeholder : nil
    secure = props.secure
    multiline = props.multiline
    imagePath = resolvedImagePath
    vectorBounds = resolvedVectorBounds
    vectorLayers = resolvedVectorLayers
    x = element.frame.minX - originX
    y = element.frame.minY - originY
    width = element.frame.width
    height = element.frame.height
    (fontSize, fontFamily, fontWeight) = (font.size, font.family, Int(font.weight.value))
    switch props.textAlignment {
    case .leading: alignment = "leading"
    case .center: alignment = "center"
    case .trailing: alignment = "trailing"
    }
    lineSpacing = props.lineSpacing
    lineLimit = props.lineLimit
    enabled = inheritedEnabled && props.enabled && props.hitTesting
    opacity = props.opacity
    rotation = props.rotation
    scaleX = props.scaleX
    scaleY = props.scaleY
    if let clipBuilder = element.clipPathBuilder {
      let cmds = clipBuilder(CGRect(x: 0, y: 0, width: element.frame.width, height: element.frame.height)).commands
      clipCommands = cmds.isEmpty ? nil : cmds
    } else {
      clipCommands = nil
    }
    if let firstShadow = props.shadows.first, firstShadow.color.opacity > 0 {
      shadowColor = encodeARGB(firstShadow.color)
      shadowRadius = firstShadow.radius
      shadowX = firstShadow.x
      shadowY = firstShadow.y
    } else {
      shadowColor = nil
      shadowRadius = 0
      shadowX = 0
      shadowY = 0
    }
    foreground = props.foreground.map(encodeARGB)
    background = props.background.map(encodeARGB)
    borderColor = props.borderWidth > 0 ? encodeARGB(props.borderColor) : nil
    borderWidth = props.borderWidth
    cornerRadius = props.cornerRadius
    accessibilityLabel = props.accessibilityLabel
    accessibilityHidden = props.accessibilityHidden
    draggable = element.handlesPointerInput && kindOverride == "dragArea"

    scrollVertical = resolvedKind == "scroll" && props.scrollAxes.contains(.vertical)
    scrollHorizontal = resolvedKind == "scroll" && props.scrollAxes.contains(.horizontal)
    scrollOffsetX = resolvedKind == "scroll" ? props.scrollOffset.x : 0
    scrollOffsetY = resolvedKind == "scroll" ? props.scrollOffset.y : 0
    self.contentWidth = contentWidth
    self.contentHeight = contentHeight
    self.children = children

    gradientKind = resolvedGradKind
    gradientColors = resolvedGradColors
    gradientStops = resolvedGradStops
    gradientStartX = gSX
    gradientStartY = gSY
    gradientEndX = gEX
    gradientEndY = gEY

    boolValue = sem?.boolValue ?? false
    doubleValue = sem?.doubleValue ?? 0
    minValue = sem?.minValue ?? 0
    maxValue = sem?.maxValue ?? 1
    stepValue = sem?.stepValue ?? 0
    intValue = sem?.intValue ?? 0
    items = sem.flatMap { $0.items.isEmpty ? nil : $0.items }
    itemIcons = sem.flatMap { $0.itemIcons.isEmpty ? nil : $0.itemIcons }
    title = sem.flatMap { $0.title.isEmpty ? nil : $0.title }
    subtitle = sem.flatMap { $0.subtitle.isEmpty ? nil : $0.subtitle }
    styleName = sem.flatMap { $0.styleName.isEmpty ? nil : $0.styleName }
    tint = sem?.tint.flatMap { color in
      // Treat SwiftUIRuntime's placeholder default accent (#0000FF) as unset so each Android style uses its native accent.
      encodeARGB(color) == 0xFF0000FF ? nil : encodeARGB(color)
    }
    canGoBack = sem?.canGoBack ?? false
    isIndeterminate = sem?.isIndeterminate ?? false
    alertActions = sem.flatMap { s in
      s.alertActions.isEmpty
        ? nil
        : s.alertActions.map { EncodedAlertAction(title: $0.title, role: $0.role, enabled: $0.enabled) }
    }
  }
}

private final class AndroidBackend: RenderBackend {
  var tapHandler: ((NodeID) -> Void)?
  var animationTickHandler: (() -> Bool)?
  var environment = EnvironmentValues()
  let needsRenderCommands = false
  private(set) var nodes: [RenderNode] = []
  var isInSynchronousUpdate = false
  var pendingAsyncRender: (() -> Void)?
  var onScheduleAsyncRender: (() -> Void)?

  func requestRender(_ render: @escaping () -> Void) -> Bool {
    if isInSynchronousUpdate {
      return false
    }
    pendingAsyncRender = render
    onScheduleAsyncRender?()
    return true
  }

  func perform(_ commands: [RenderCommand]) {}

  func didRender(_ root: Element) {
    nodes.removeAll(keepingCapacity: true)
    collect(root, originX: 0, originY: 0, inheritedEnabled: true, into: &nodes)
  }

  private func collect(
    _ element: Element,
    originX: Double,
    originY: Double,
    inheritedEnabled: Bool,
    into out: inout [RenderNode]
  ) {
    guard element.props.visible else { return }
    let effectiveEnabled = inheritedEnabled && element.props.enabled && (element.props.disabledOverride.map { !$0 } ?? true)
    let hasSize = !element.frame.size.isEmpty

    // Semantic dual-style controls render natively in Compose (Material 3 or iOS-like)
    if let sem = element.props.semanticControl {
      if sem.kind == "sheet" || sem.kind == "navStack" || sem.kind == "listItem" {
        var childNodes: [RenderNode] = []
        element.children.forEach {
          collect($0, originX: element.frame.minX, originY: element.frame.minY, inheritedEnabled: effectiveEnabled, into: &childNodes)
        }
        out.append(
          RenderNode(
            element,
            originX: originX,
            originY: originY,
            inheritedEnabled: effectiveEnabled,
            children: childNodes,
            contentWidth: element.frame.width,
            contentHeight: element.frame.height
          )
        )
        return
      }
      if sem.kind == "alert" || hasSize {
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled))
      }
      return
    }

    switch element.kind {
    case .text, .button, .image, .shape, .path, .textField, .gradient:
      if hasSize {
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled))
        if element.kind != .button && element.kind != .textField && element.handlesPointerInput {
          let hitKind = element.action != nil ? "hitArea" : "dragArea"
          out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: hitKind))
        }
      }
    case .styledButton:
      element.children.forEach { collect($0, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out) }
      if hasSize {
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: "hitArea"))
      }
    case .scroll:
      guard hasSize else { return }
      var childNodes: [RenderNode] = []
      var maxRight = element.frame.width
      var maxBottom = element.frame.height
      for child in element.children {
        maxRight = max(maxRight, child.frame.maxX - element.frame.minX)
        maxBottom = max(maxBottom, child.frame.maxY - element.frame.minY)
        collect(child, originX: element.frame.minX, originY: element.frame.minY, inheritedEnabled: effectiveEnabled, into: &childNodes)
      }
      if element.props.background != nil || element.props.borderWidth > 0 {
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: "shape"))
      }
      out.append(
        RenderNode(
          element,
          originX: originX,
          originY: originY,
          inheritedEnabled: effectiveEnabled,
          kindOverride: "scroll",
          children: childNodes,
          contentWidth: maxRight,
          contentHeight: maxBottom
        )
      )
    case .layer:
      if element.children.count >= 2 {
        let base = element.children[0]
        let layer = element.children[1]
        if element.props.layerBehind {
          collect(layer, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out)
          collect(base, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out)
        } else {
          collect(base, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out)
          collect(layer, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out)
        }
      } else {
        element.children.forEach { collect($0, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out) }
      }
      if hasSize && element.handlesPointerInput {
        let hitKind = element.action != nil ? "hitArea" : "dragArea"
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: hitKind))
      }
    case .fragment, .container, .padding, .frame, .grid, .zStack, .geometry, .customLayout:
      if hasSize && element.props.clipped {
        var childNodes: [RenderNode] = []
        if element.props.background != nil || element.props.borderWidth > 0 {
          childNodes.append(
            RenderNode(
              element,
              originX: element.frame.minX,
              originY: element.frame.minY,
              inheritedEnabled: effectiveEnabled,
              kindOverride: "shape"
            )
          )
        }
        element.children.forEach {
          collect($0, originX: element.frame.minX, originY: element.frame.minY, inheritedEnabled: effectiveEnabled, into: &childNodes)
        }
        out.append(
          RenderNode(
            element,
            originX: originX,
            originY: originY,
            inheritedEnabled: effectiveEnabled,
            kindOverride: "clip",
            children: childNodes
          )
        )
      } else {
        if hasSize && (element.props.background != nil || element.props.borderWidth > 0) {
          out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: "shape"))
        }
        element.children.forEach { collect($0, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out) }
      }
      if hasSize && element.handlesPointerInput {
        let hitKind = element.action != nil ? "hitArea" : "dragArea"
        out.append(RenderNode(element, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, kindOverride: hitKind))
      }
    case .presentation:
      if let base = element.children.first {
        collect(base, originX: originX, originY: originY, inheritedEnabled: effectiveEnabled, into: &out)
      }
    default:
      break
    }
  }
}

private func javaString(_ value: String, in env: SwiftUIJNIEnvironment) -> jstring? {
  Array(value.utf16).withUnsafeBufferPointer {
    swiftui_android_string(env, $0.baseAddress, Int32($0.count))
  }
}

private final class TextMeasurer {
  struct Context {
    let env: SwiftUIJNIEnvironment
    let host: jobject
    let method: jmethodID
  }

  // JNIEnv and the host reference belong to the current JNI call.
  var context: Context?
  var method: jmethodID?

  func measure(_ text: String, font: Font) -> Size {
    guard let context else {
      return Size(width: Double(text.count) * 8, height: Double(font.size))
    }
    let env = context.env
    let packed = UInt64(bitPattern: swiftui_android_measure_text(
      env, context.host, context.method, javaString(text, in: env), Double(font.size),
      javaString(font.family, in: env), Int32(font.weight.value)))
    return Size(
      width: Double(Float(bitPattern: UInt32(packed >> 32))),
      height: Double(Float(bitPattern: UInt32(truncatingIfNeeded: packed))))
  }
}

/// Owns one Android Activity's renderer. SwiftUIComposeHost takes ownership
/// of the handle and releases it on the Android UI thread when closed.
@MainActor
public final class AndroidHost {
  private let renderer: Renderer
  private let backend: AndroidBackend
  private let textMeasurer: TextMeasurer
  private var bridge: OpaquePointer?

  private init(root: AnyView) {
    let backend = AndroidBackend()
    let textMeasurer = TextMeasurer()
    self.backend = backend
    self.textMeasurer = textMeasurer
    renderer = Renderer(
      backend: backend, root: root, size: .zero,
      layoutEngine: LayoutEngine(
        metrics: TextMetrics(buttonHorizontalPadding: 16, buttonVerticalPadding: 16),
        textMeasurer: textMeasurer.measure))
    backend.onScheduleAsyncRender = { [weak self] in
      guard let self, let bridge = self.bridge else { return }
      swiftui_android_bridge_schedule_render(bridge)
    }
    backend.environment.openURL = OpenURLAction { [weak self] url in
      guard let self, let bridge = self.bridge else { return .discarded }
      url.absoluteString.withCString { cStr in
        swiftui_android_bridge_open_url(bridge, cStr)
      }
      return .handled
    }
  }

  public static func retain(root: AnyView) -> Int64 {
    let host = Unmanaged.passRetained(AndroidHost(root: root)).toOpaque()
    return Int64(Int(bitPattern: host))
  }

  /// Installs extracted Android app resources (`*.xcstrings` catalogs and `*.xcassets` imagesets)
  /// and preferred device language before mounting the root SwiftUI view tree.
  public static func configureResources(directory: String, preferredLanguage: String? = nil) {
    if let preferredLanguage, !preferredLanguage.isEmpty {
      XCStringsCatalog.shared.preferredLanguage = preferredLanguage
    }
    let fm = FileManager.default
    let rootURL = URL(fileURLWithPath: directory)
    guard fm.fileExists(atPath: rootURL.path) else { return }

    var exactImages: [String: String] = [:]
    var lowerImages: [String: String] = [:]

    func registerImage(name: String, path: String) {
      if exactImages[name] == nil { exactImages[name] = path }
      let lower = name.lowercased()
      if lowerImages[lower] == nil { lowerImages[lower] = path }
    }

    let supportedImageExts: Set<String> = ["svg", "pdf", "png", "jpg", "jpeg", "webp"]

    if let enumerator = fm.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let fileURL as URL in enumerator {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "xcstrings" {
          if let data = try? Data(contentsOf: fileURL) {
            _ = XCStringsCatalog.shared.load(data: data, merge: true)
          }
        } else if ext == "imageset" {
          let assetName = fileURL.deletingPathExtension().lastPathComponent
          if let bestImage = resolveImagesetFile(in: fileURL, allowedExtensions: supportedImageExts) {
            registerImage(name: assetName, path: bestImage.path)
          }
          enumerator.skipDescendants()
        } else if supportedImageExts.contains(ext) {
          let stem = fileURL.deletingPathExtension().lastPathComponent
          registerImage(name: stem, path: fileURL.path)
        }
      }
    }

    if !exactImages.isEmpty {
      SwiftUIRuntime.Image.assetPathResolver = { name, _ in
        exactImages[name] ?? lowerImages[name.lowercased()]
      }
    }
  }

  private static func resolveImagesetFile(
    in imagesetDir: URL,
    allowedExtensions: Set<String>
  ) -> URL? {
    let fm = FileManager.default
    let contentsURL = imagesetDir.appendingPathComponent("Contents.json")
    if let data = try? Data(contentsOf: contentsURL),
       let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let images = root["images"] as? [[String: Any]]
    {
      var ranked: [(score: Int, url: URL)] = []
      for item in images {
        guard let filename = item["filename"] as? String, !filename.isEmpty else { continue }
        let candidate = imagesetDir.appendingPathComponent(filename)
        guard fm.fileExists(atPath: candidate.path) else { continue }
        let ext = candidate.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { continue }
        let scaleStr = (item["scale"] as? String) ?? ""
        let score: Int
        if ext == "svg" || ext == "pdf" { score = 4 }
        else if scaleStr == "3x" { score = 3 }
        else if scaleStr == "2x" { score = 2 }
        else if scaleStr == "1x" { score = 1 }
        else { score = 2 }
        ranked.append((score, candidate))
      }
      if let best = ranked.max(by: { $0.score < $1.score }) {
        return best.url
      }
    }
    if let children = try? fm.contentsOfDirectory(at: imagesetDir, includingPropertiesForKeys: nil) {
      return children.first { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }
    return nil
  }

  fileprivate static func fromHandle(_ handle: jlong) -> Unmanaged<AndroidHost> {
    Unmanaged.fromOpaque(UnsafeRawPointer(bitPattern: Int(handle))!)
  }

  fileprivate func ensureBridge(env: SwiftUIJNIEnvironment, host: jobject) {
    if bridge == nil {
      bridge = swiftui_android_bridge_create(env, host)
    }
  }

  fileprivate func destroyBridge(env: SwiftUIJNIEnvironment) {
    if let bridge {
      self.bridge = nil
      swiftui_android_bridge_destroy(env, bridge)
    }
  }

  fileprivate func update(
    env: SwiftUIJNIEnvironment, host: jobject, change: (Renderer) -> Void
  ) -> jstring? {
    ensureBridge(env: env, host: host)
    if textMeasurer.method == nil {
      textMeasurer.method = swiftui_android_text_measurer(env, host)
    }
    guard let method = textMeasurer.method else { return nil }
    textMeasurer.context = TextMeasurer.Context(env: env, host: host, method: method)
    backend.isInSynchronousUpdate = true
    defer {
      backend.isInSynchronousUpdate = false
      textMeasurer.context = nil
    }
    change(renderer)
    if let pending = backend.pendingAsyncRender {
      backend.pendingAsyncRender = nil
      pending()
    }
    let hasAnimations = renderer.hasActiveAnimations || (renderer.tree?.hasLayoutAnimation ?? false)
    let envelope = SnapshotEnvelope(nodes: backend.nodes, hasActiveAnimations: hasAnimations)
    guard let data = try? JSONEncoder().encode(envelope) else { return nil }
    return javaString(String(decoding: data, as: UTF8.self), in: env)
  }

  fileprivate func flushAsyncRender(env: SwiftUIJNIEnvironment, host: jobject) -> jstring? {
    update(env: env, host: host) { renderer in
      if let pending = backend.pendingAsyncRender {
        backend.pendingAsyncRender = nil
        pending()
      } else {
        renderer.renderIfNeeded()
      }
    }
  }

  fileprivate func tickAnimation(env: SwiftUIJNIEnvironment, host: jobject) -> jstring? {
    update(env: env, host: host) { renderer in
      _ = renderer.stepAnimations()
    }
  }

  fileprivate func setColorScheme(
    env: SwiftUIJNIEnvironment, host: jobject, isDark: Bool
  ) -> jstring? {
    let target: ColorScheme = isDark ? .dark : .light
    guard backend.environment.colorScheme != target else {
      return nil
    }
    backend.environment.colorScheme = target
    return update(env: env, host: host) { renderer in
      renderer.setNeedsRender()
      renderer.renderIfNeeded()
    }
  }
}

// SwiftUIComposeHost calls these synchronously on the Android UI thread.
@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeResize")
public func androidResize(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ width: jdouble, _ height: jdouble,
  _ invalidateMeasurements: jboolean
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.resize(to: Size(width: width, height: height), invalidateMeasurements: invalidateMeasurements != 0)
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeTap")
public func androidTap(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performTap(NodeID(rawValue: Int(id)))
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeTextInput")
public func androidTextInput(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong, _ text: jstring?
) -> jstring? {
  let swiftText: String
  if let text, let cStr = swiftui_android_get_utf8(env, text) {
    swiftText = String(cString: cStr)
    swiftui_android_release_utf8(env, text, cStr)
  } else {
    swiftText = ""
  }
  return AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.input(id: NodeID(rawValue: Int(id)), event: 7, text: swiftText)
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeBoolInput")
public func androidBoolInput(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong, _ value: jboolean
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performBoolInput(NodeID(rawValue: Int(id)), value: value != 0)
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeDoubleInput")
public func androidDoubleInput(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong,
  _ value: jdouble, _ ended: jboolean
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performDoubleInput(NodeID(rawValue: Int(id)), value: value, ended: ended != 0)
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeIntInput")
public func androidIntInput(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong, _ value: jint
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performIntInput(NodeID(rawValue: Int(id)), value: Int(value))
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeStepInput")
public func androidStepInput(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong, _ delta: jint
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performStepInput(NodeID(rawValue: Int(id)), delta: Int(delta))
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeBack")
public func androidBack(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.performBackInput(NodeID(rawValue: Int(id)))
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeDrag")
public func androidDrag(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong,
  _ phase: jint, _ x: jdouble, _ y: jdouble
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.input(id: NodeID(rawValue: Int(id)), event: Int(phase), point: CGPoint(x: x, y: y))
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeDismissPresentation")
public func androidDismissPresentation(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    $0.dismissActivePresentation()
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeFlushRender")
public func androidFlushRender(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().flushAsyncRender(env: env, host: host)
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeTickAnimation")
public func androidTickAnimation(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().tickAnimation(env: env, host: host)
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeSetColorScheme")
public func androidSetColorScheme(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ isDark: jboolean
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().setColorScheme(
    env: env, host: host, isDark: isDark != 0
  )
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeSubmit")
public func androidSubmit(
  _ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong, _ id: jlong
) -> jstring? {
  AndroidHost.fromHandle(handle).takeUnretainedValue().update(env: env, host: host) {
    _ = $0.input(id: NodeID(rawValue: Int(id)), event: 6, value: 13)
  }
}

@MainActor @_cdecl("Java_dev_crossswiftui_android_SwiftUIComposeHost_nativeDestroy")
public func androidDestroy(_ env: SwiftUIJNIEnvironment, _ host: jobject, _ handle: jlong) {
  let unmanaged = AndroidHost.fromHandle(handle)
  unmanaged.takeUnretainedValue().destroyBridge(env: env)
  unmanaged.release()
}
