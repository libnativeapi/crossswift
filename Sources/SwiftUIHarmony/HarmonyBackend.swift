import Dispatch
import Foundation
import SwiftUIRuntime

public typealias HarmonyUpdate = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void

@_silgen_name("harmony_measure_text")
private func harmonyMeasureText(
  _ text: UnsafePointer<CChar>, _ family: UnsafePointer<CChar>, _ fontSize: Double,
  _ weight: Int32, _ width: UnsafeMutablePointer<Double>, _ height: UnsafeMutablePointer<Double>
) -> Bool

public enum HarmonyHost {
  public struct SurfaceConfig {
    public var isTransparent: Bool = false
    public var fixedContentSize: Size? = nil
    public var shadowBleed: Double = 0
  }

  @MainActor public private(set) static var resourcesDirectory: String?
  @MainActor public static var keyEventHandler: ((_ surfaceId: Int, _ keyCode: Int) -> Bool)?

  @MainActor private static var surfaceConfigs: [Int: SurfaceConfig] = [:]
  @MainActor private static var pendingRootViews: [Int: AnyView] = [:]
  @MainActor private static var mountHandlers: [Int: (AnyView) -> Void] = [:]
  @MainActor private static var sizeHandlers: [Int: (Size) -> Void] = [:]

  @MainActor public static var pendingRootView: AnyView? {
    get { pendingRootViews[0] }
    set {
      if let newValue { pendingRootViews[0] = newValue } else { pendingRootViews.removeValue(forKey: 0) }
    }
  }
  @MainActor public static var activeHostMountHandler: ((AnyView) -> Void)? {
    get { mountHandlers[0] }
    set { setMountHandler(forSurface: 0, newValue) }
  }
  @MainActor public static var onFixedContentSizeChanged: ((Size) -> Void)? {
    get { sizeHandlers[0] }
    set { setSizeHandler(forSurface: 0, newValue) }
  }
  @MainActor public static var isWindowTransparent: Bool { surfaceConfigs[0]?.isTransparent ?? false }
  @MainActor public static var fixedContentSize: Size? { surfaceConfigs[0]?.fixedContentSize }
  @MainActor public static var windowShadowBleed: Double { surfaceConfigs[0]?.shadowBleed ?? 0 }

  @MainActor
  public static func surfaceConfig(for surfaceId: Int) -> SurfaceConfig {
    surfaceConfigs[surfaceId] ?? SurfaceConfig()
  }

  @MainActor
  public static func configureWindowSurface(
    forSurface surfaceId: Int = 0,
    isTransparent: Bool,
    contentSize: Size?,
    shadowBleed: Double
  ) {
    surfaceConfigs[surfaceId] = SurfaceConfig(
      isTransparent: isTransparent,
      fixedContentSize: contentSize,
      shadowBleed: max(0, shadowBleed)
    )
    if let contentSize, contentSize.width > 0, contentSize.height > 0 {
      sizeHandlers[surfaceId]?(contentSize)
    }
  }

  @MainActor
  public static func mountRootView(_ view: AnyView, forSurface surfaceId: Int = 0) {
    pendingRootViews[surfaceId] = view
    mountHandlers[surfaceId]?(view)
  }

  @MainActor
  public static func pendingRootView(forSurface surfaceId: Int) -> AnyView? {
    pendingRootViews[surfaceId]
  }

  @MainActor
  public static func setMountHandler(forSurface surfaceId: Int, _ handler: ((AnyView) -> Void)?) {
    if let handler {
      mountHandlers[surfaceId] = handler
    } else {
      mountHandlers.removeValue(forKey: surfaceId)
    }
  }

  @MainActor
  public static func setSizeHandler(forSurface surfaceId: Int, _ handler: ((Size) -> Void)?) {
    if let handler {
      sizeHandlers[surfaceId] = handler
    } else {
      sizeHandlers.removeValue(forKey: surfaceId)
    }
  }

  @MainActor
  public static func clearSurface(_ surfaceId: Int) {
    mountHandlers.removeValue(forKey: surfaceId)
    sizeHandlers.removeValue(forKey: surfaceId)
  }

  @MainActor
  public static func resetMountedRoot() {
    pendingRootViews.removeAll()
    mountHandlers.removeAll()
    sizeHandlers.removeAll()
    surfaceConfigs.removeAll()
  }

  public static func measureText(_ text: String, _ font: Font) -> Size {
    var width = 0.0
    var height = 0.0
    let family: String
    switch font.family {
    case "Segoe UI", "-apple-system", "system-ui": family = ""
    case "Consolas": family = "monospace"
    case "Georgia": family = "serif"
    default: family = font.family
    }
    let weightValue = font.weight.value.isFinite
      ? Int((min(900, max(100, font.weight.value)) / 100).rounded()) * 100
      : 400
    let measured = text.withCString { string in
      family.withCString { fam in
        harmonyMeasureText(string, fam, font.size, Int32(weightValue / 100 - 1), &width, &height)
      }
    }
    if measured {
      return Size(width: width.rounded(.up) + 3, height: height.rounded(.up))
    }
    return Size(width: Double(text.count) * font.size * 0.6 + 3, height: font.size)
  }

  /// Installs extracted HarmonyOS app resources (`*.xcstrings` catalogs and `*.xcassets` imagesets)
  /// and preferred device language before mounting the root SwiftUI view tree.
  @MainActor
  public static func configureResources(directory: String, preferredLanguage: String? = nil) {
    resourcesDirectory = directory
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
}

public final class HarmonyBackend: RenderBackend {
  public var tapHandler: ((NodeID) -> Void)?
  public var animationTickHandler: (() -> Bool)?
  public var environment = EnvironmentValues()
  public var needsRenderCommands: Bool { false }

  public let surfaceId: Int
  private let context: UnsafeMutableRawPointer
  private let update: HarmonyUpdate
  private let pixelsPerPoint: Double
  private var renderScheduled = false
  private var animationTimer: DispatchSourceTimer?

  private struct TextKey: Hashable {
    var text: String
    var font: Font
  }
  private var textSizes: [TextKey: Size] = [:]

  public init(
    context: UnsafeMutableRawPointer,
    update: @escaping HarmonyUpdate,
    pixelsPerPoint: Double,
    surfaceId: Int = 0
  ) {
    self.surfaceId = surfaceId
    self.context = context
    self.update = update
    self.pixelsPerPoint = pixelsPerPoint
  }

  deinit {
    stopAnimationTimer()
  }

  public func requestRender(_ render: @escaping () -> Void) -> Bool {
    if !renderScheduled {
      renderScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.renderScheduled = false
        render()
      }
    }
    return true
  }

  private func ensureAnimationTimer() {
    guard animationTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16))
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let keepRunning = self.animationTickHandler?() ?? false
      if !keepRunning {
        self.stopAnimationTimer()
      }
    }
    animationTimer = timer
    timer.resume()
  }

  private func stopAnimationTimer() {
    animationTimer?.cancel()
    animationTimer = nil
  }

  public func measureText(_ text: String, _ font: Font) -> Size {
    let key = TextKey(text: text, font: font)
    if let cached = textSizes[key] { return cached }
    var width = 0.0
    var height = 0.0
    let measured = text.withCString { string in
      fontFamily(font).withCString { family in
        harmonyMeasureText(
          string, family, font.size * pixelsPerPoint,
          Int32(fontWeight(font) / 100 - 1), &width, &height)
      }
    }
    let size = measured
      ? Size(width: (width / pixelsPerPoint).rounded(.up) + 3, height: (height / pixelsPerPoint).rounded(.up))
      : Size(width: Double(text.count) * font.size * 0.6 + 3, height: font.size)
    if textSizes.count >= 8192 { textSizes.removeAll(keepingCapacity: true) }
    textSizes[key] = size
    return size
  }

  private func fontFamily(_ font: Font) -> String {
    switch font.family {
    case "Segoe UI", "-apple-system", "system-ui": return ""
    case "Consolas": return "monospace"
    case "Georgia": return "serif"
    default: return font.family
    }
  }

  private func fontWeight(_ font: Font) -> Int {
    guard font.weight.value.isFinite else { return 400 }
    return Int((min(900, max(100, font.weight.value)) / 100).rounded()) * 100
  }

  public func perform(_ commands: [RenderCommand]) {}

  private func hasClipPathDescendant(_ element: Element) -> Bool {
    if element.clipPathBuilder != nil { return true }
    return element.children.contains(where: hasClipPathDescendant)
  }

  public func didRender(_ root: Element) {
    var tree = snapshot(root)
    tree.isDark = environment.colorScheme == .dark
    let cfg = MainActor.assumeIsolated { HarmonyHost.surfaceConfig(for: surfaceId) }
    if cfg.isTransparent {
      tree.windowTransparent = true
      if cfg.shadowBleed > 0 { tree.windowBleed = cfg.shadowBleed }
      let maxR = min(root.frame.width, root.frame.height) / 2
      let corner = root.shadowCornerRadius
      if root.frame.height >= 72, corner > 0, maxR > 0 {
        tree.windowCornerRadius = min(corner, maxR)
      } else if root.frame.height >= 72, maxR > 0, hasClipPathDescendant(root) {
        tree.windowCornerRadius = min(14, maxR)
      }
    }
    guard let data = try? JSONEncoder().encode(tree) else { return }
    String(decoding: data, as: UTF8.self).withCString { update(context, $0) }
    if root.hasLayoutAnimation {
      ensureAnimationTimer()
    } else {
      stopAnimationTimer()
    }
  }

  private struct AlertActionNode: Encodable {
    var title: String
    var role: String
    var enabled: Bool
  }

  private struct Node: Encodable {
    var id: Int
    var kind: String
    var x, y, width, height: Double
    var text: String
    var label: String
    var placeholder: String
    var secure: Bool
    var multiline: Bool
    var plainTextField: Bool?
    var image: String
    var imageTemplate: Bool?
    var fontSize: Double
    var fontWeight: Int
    var fontFamily: String
    var textAlignment: String
    var lineSpacing: Double
    var tracking: Double
    var underline: Bool
    var lineLimit: Int
    var path: String
    var clipPath: String?
    var rotation, scaleX, scaleY: Double
    var dash: [Double]
    var foreground: UInt32?
    var background: UInt32?
    var border: UInt32?
    var borderWidth: Double
    var radius: Double
    var opacity: Double
    var blurRadius: Double
    var backdropBlurRadius: Double?
    var grayscale: Double?
    var isDark: Bool?
    var shadowColor: UInt32?
    var shadowRadius: Double?
    var shadowX: Double?
    var shadowY: Double?
    var windowTransparent: Bool?
    var windowBleed: Double?
    var windowCornerRadius: Double?
    var clip: Bool
    var scrollIndicators: Bool
    var scrollDirection: String
    var scrollOffsetX: Double
    var scrollOffsetY: Double
    var selected: Bool
    var enabled: Bool
    var hitTesting: Bool
    var gradientKind: String?
    var gradientAngle: Double?
    var gradientColors: [UInt32]?
    var boolValue: Bool
    var doubleValue: Double
    var minValue: Double
    var maxValue: Double
    var stepValue: Double
    var intValue: Int
    var items: [String]?
    var title: String?
    var subtitle: String?
    var styleName: String?
    var canGoBack: Bool
    var tint: UInt32?
    var alertActions: [AlertActionNode]?
    var children: [Node]
  }

  private func snapshot(_ element: Element) -> Node {
    let props = element.props
    let font = props.font ?? .body
    let frame = element.frame
    let localFrame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    let children = element.children.enumerated().sorted {
      if $0.element.props.zIndex != $1.element.props.zIndex {
        return $0.element.props.zIndex < $1.element.props.zIndex
      }
      return props.layerBehind ? $0.offset > $1.offset : $0.offset < $1.offset
    }.map(\.element)
    func number(_ value: Double) -> Double { value.isFinite ? value : 0 }
    func color(_ value: Color?) -> UInt32? {
      value.map { color in
        [color.opacity, color.red, color.green, color.blue].reduce(0) {
          ($0 << 8) | UInt32((max(0, min(1, number($1))) * 255).rounded())
        }
      }
    }
    let sem = props.semanticControl
    #if CROSS_SWIFTUI_HARMONY_DESKTOP
    let nativeSemanticKinds: Set<String> = ["progressCircular"]
    #else
    let nativeSemanticKinds: Set<String> = [
      "switch", "checkbox", "slider", "segmented", "stepper",
      "progressLinear", "progressCircular", "button",
      "navBar", "tabBar", "alert", "menu", "divider",
    ]
    #endif
    var kind: String
    var path = ""
    var resolvedBorder = color(props.borderColor)
    var resolvedBorderWidth = number(props.borderWidth)
    var resolvedBg = color(props.background)
    var resolvedGradientKind: String? = nil
    var resolvedGradientAngle: Double? = nil
    var resolvedGradient: [UInt32]? = nil
    var includeChildren = true

    if let sem, sem.kind == "navStack" {
      kind = "navStack"
      includeChildren = true
    } else if let sem, nativeSemanticKinds.contains(sem.kind) {
      kind = sem.kind == "button" ? "semanticButton" : sem.kind
      includeChildren = false
    } else {
      switch element.kind {
      case .text: kind = "text"
      case .button, .styledButton: kind = "button"
      case .textField: kind = "editor"
      case .gradient:
        kind = "gradient"
        if let grad = props.gradient {
          switch grad.kind {
          case .linear:
            resolvedGradientKind = "linear"
            let dx = Double(grad.end.x - grad.start.x)
            let dy = Double(grad.end.y - grad.start.y)
            if abs(dx) > 1e-6 || abs(dy) > 1e-6 {
              var deg = atan2(dx, -dy) * 180.0 / .pi
              if deg < 0 { deg += 360.0 }
              resolvedGradientAngle = deg
            }
          case .radial: resolvedGradientKind = "radial"
          case .angular: resolvedGradientKind = "angular"
          }
          resolvedGradient = grad.colors.compactMap { color($0) }
        }
      case .image:
        let rawPath = props.imagePath
        let isVector =
          rawPath.hasPrefix("sf://")
          || rawPath.lowercased().hasSuffix(".svg")
          || rawPath.lowercased().hasSuffix(".pdf")
        if isVector, let vec = VectorImage.load(rawPath), !vec.layers.isEmpty {
          let vbW = max(0.001, vec.bounds.width)
          let vbH = max(0.001, vec.bounds.height)
          let scale = min(frame.width / vbW, frame.height / vbH)
          let tx = (frame.width - vbW * scale) / 2 - vec.bounds.minX * scale
          let ty = (frame.height - vbH * scale) / 2 - vec.bounds.minY * scale
          path = vec.layers.map { scaledCommands($0.path, scale: scale, tx: tx, ty: ty) }.joined(separator: " ")
          let isTemplate = rawPath.hasPrefix("sf://") || props.imageTemplate
          let tintCol = color(props.foreground) ?? 0xFF000000
          if let firstStroke = vec.layers.first?.stroke {
            resolvedBorder = isTemplate ? tintCol : (color(firstStroke) ?? tintCol)
            resolvedBorderWidth = max(1.0, (vec.layers.first?.strokeWidth ?? 2.0) * scale)
            resolvedBg = nil
          } else {
            let firstFill = vec.layers.first?.fill
            resolvedBg = isTemplate ? tintCol : (color(firstFill) ?? tintCol)
            resolvedBorder = nil
            resolvedBorderWidth = 0
          }
          kind = path.isEmpty ? "image" : "path"
        } else {
          kind = "image"
        }
      case .scroll: kind = "scroll"
      case .path, .shape:
        if let builder = element.pathBuilder {
          path = commands(builder(localFrame))
        } else if element.kind == .path {
          path = commands(props.path)
        }
        kind = path.isEmpty ? "group" : "path"
      default: kind = "group"
      }
      if kind == "group" && element.acceptsPointerInput { kind = "button" }
    }
    let effectiveCorner =
      props.shadows.isEmpty ? props.cornerRadius : max(props.cornerRadius, element.shadowCornerRadius)
    return Node(
      id: element.id.rawValue, kind: kind,
      x: number(frame.minX), y: number(frame.minY), width: number(frame.width), height: number(frame.height),
      text: props.renderedText ?? props.text,
      label: kind == "button" ? buttonLabel(element) : props.accessibilityLabel,
      placeholder: props.placeholder,
      secure: props.secure,
      multiline: props.multiline,
      plainTextField: props.plainTextField ? true : nil,
      image: props.imagePath,
      imageTemplate: props.imageTemplate ? true : nil,
      fontSize: number(font.size), fontWeight: fontWeight(font), fontFamily: fontFamily(font),
      textAlignment: props.textAlignment == .center ? "center" : props.textAlignment == .trailing ? "end" : "start",
      lineSpacing: number(props.lineSpacing), tracking: number(props.tracking), underline: props.underline,
      lineLimit: props.lineLimit ?? 0, path: path,
      clipPath: element.clipPathBuilder.map { commands($0(localFrame)) },
      rotation: number(props.rotation), scaleX: number(props.scaleX), scaleY: number(props.scaleY),
      dash: props.dash.map(number),
      foreground: color(props.foreground),
      background: resolvedBg, border: resolvedBorder,
      borderWidth: resolvedBorderWidth,
      radius: number(max(0, min(effectiveCorner, frame.width / 2, frame.height / 2))),
      opacity: number(props.opacity), blurRadius: number(props.blurRadius),
      backdropBlurRadius: props.backdropBlurRadius > 0 ? number(props.backdropBlurRadius) : nil,
      grayscale: props.saturation < 0.99 ? number(max(0, min(1, 1.0 - props.saturation))) : nil,
      isDark: nil,
      shadowColor: props.shadows.first.flatMap { $0.radius > 0 ? color($0.color) : nil },
      shadowRadius: props.shadows.first.flatMap { $0.radius > 0 ? number($0.radius * pixelsPerPoint) : nil },
      shadowX: props.shadows.first.flatMap { $0.radius > 0 ? number($0.x * pixelsPerPoint) : nil },
      shadowY: props.shadows.first.flatMap { $0.radius > 0 ? number($0.y * pixelsPerPoint) : nil },
      windowTransparent: nil,
      windowBleed: nil,
      windowCornerRadius: nil,
      clip: props.clipped,
      scrollIndicators: props.showsScrollIndicators,
      scrollDirection: props.scrollAxes.contains(.horizontal)
        ? (props.scrollAxes.contains(.vertical) ? "both" : "horizontal") : "vertical",
      scrollOffsetX: number(props.scrollOffset.x),
      scrollOffsetY: number(props.scrollOffset.y),
      selected: AccessibilityTraits(rawValue: props.accessibilityTraits).contains(.isSelected),
      enabled: props.enabled, hitTesting: props.hitTesting,
      gradientKind: resolvedGradientKind,
      gradientAngle: resolvedGradientAngle,
      gradientColors: resolvedGradient,
      boolValue: sem?.boolValue ?? false,
      doubleValue: number(sem?.doubleValue ?? 0),
      minValue: number(sem?.minValue ?? 0),
      maxValue: number(sem?.maxValue ?? 1),
      stepValue: number(sem?.stepValue ?? 0),
      intValue: sem?.intValue ?? 0,
      items: sem.flatMap { $0.items.isEmpty ? nil : $0.items },
      title: sem.flatMap { $0.title.isEmpty ? nil : $0.title },
      subtitle: sem.flatMap { $0.subtitle.isEmpty ? nil : $0.subtitle },
      styleName: sem.flatMap { $0.styleName.isEmpty ? nil : $0.styleName },
      canGoBack: sem?.canGoBack ?? false,
      tint: sem?.tint.flatMap { c in
        let encoded = color(c)
        return encoded == 0xFF0000FF ? nil : encoded
      },
      alertActions: sem.flatMap { s in
        s.alertActions.isEmpty
          ? nil
          : s.alertActions.map { AlertActionNode(title: $0.title, role: $0.role, enabled: $0.enabled) }
      },
      children: includeChildren ? children.filter { $0.props.visible }.map(snapshot) : [])
  }

  private func scaledCommands(_ path: Path, scale: Double, tx: Double, ty: Double) -> String {
    var parts: [String] = []
    var index = 0
    while index < path.commands.count {
      let command: String, points: Int
      switch path.commands[index] {
      case 0: (command, points) = ("M", 2)
      case 1: (command, points) = ("L", 2)
      case 2: (command, points) = ("C", 6)
      case 3: (command, points) = ("Z", 0)
      default: return ""
      }
      let end = index + 1 + points
      guard end <= path.commands.count else { return "" }
      var values: [Double] = []
      values.reserveCapacity(points)
      for i in 0..<points {
        let raw = path.commands[index + 1 + i]
        let transformed = (i % 2 == 0 ? raw * scale + tx : raw * scale + ty) * pixelsPerPoint
        guard transformed.isFinite else { return "" }
        values.append(transformed)
      }
      parts.append(command + values.map { String($0) }.joined(separator: " "))
      index = end
    }
    return parts.joined(separator: " ")
  }

  private func buttonLabel(_ element: Element) -> String {
    if !element.props.accessibilityLabel.isEmpty { return element.props.accessibilityLabel }
    if !element.props.text.isEmpty { return element.props.text }
    return element.children.map(buttonLabel).filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func commands(_ path: Path) -> String {
    var parts: [String] = []
    var index = 0
    while index < path.commands.count {
      let command: String, points: Int
      switch path.commands[index] {
      case 0: (command, points) = ("M", 2)
      case 1: (command, points) = ("L", 2)
      case 2: (command, points) = ("C", 6)
      case 3: (command, points) = ("Z", 0)
      default: return ""
      }
      let end = index + 1 + points
      guard end <= path.commands.count else { return "" }
      let values = path.commands[(index + 1)..<end].map { $0 * pixelsPerPoint }
      guard values.allSatisfy(\.isFinite) else { return "" }
      parts.append(command + values.map { String($0) }.joined(separator: " "))
      index = end
    }
    return parts.joined(separator: " ")
  }
}
