import CrossAppKit
import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

// MARK: - UIImage

open class UIImage: NSObject, NSCopying, @unchecked Sendable {
  public enum Orientation: Int, Sendable {
    case up = 0
    case down = 1
    case left = 2
    case right = 3
    case upMirrored = 4
    case downMirrored = 5
    case leftMirrored = 6
    case rightMirrored = 7
  }

  public enum RenderingMode: Int, Sendable {
    case automatic = 0
    case alwaysOriginal = 1
    case alwaysTemplate = 2
  }

  public enum ResizingMode: Int, Sendable {
    case tile = 0
    case stretch = 1
  }

  public enum SymbolScale: Int, Sendable {
    case `default` = -1
    case unspecified = 0
    case small = 1
    case medium = 2
    case large = 3

    internal var scaleFactor: CGFloat {
      switch self {
      case .small: return 0.85
      case .large: return 1.2
      default: return 1.0
      }
    }
  }

  public enum SymbolWeight: Int, Sendable {
    case unspecified = 0
    case ultraLight = 1
    case thin = 2
    case light = 3
    case regular = 4
    case medium = 5
    case semibold = 6
    case bold = 7
    case heavy = 8
    case black = 9

    public func fontWeight() -> UIFont.Weight {
      switch self {
      case .ultraLight: return .ultraLight
      case .thin: return .thin
      case .light: return .light
      case .regular, .unspecified: return .regular
      case .medium: return .medium
      case .semibold: return .semibold
      case .bold: return .bold
      case .heavy: return .heavy
      case .black: return .black
      }
    }
  }

  open class Configuration: NSObject, NSCopying, @unchecked Sendable {
    public var traitCollection: UITraitCollection?
    public override init() { super.init() }
    open func copy(with zone: NSZone? = nil) -> Any { self }
    open func applying(_ otherConfiguration: Configuration?) -> Self {
      guard let other = otherConfiguration as? Self else { return self }
      return other
    }
  }

  public final class SymbolConfiguration: Configuration, @unchecked Sendable {
    public static let unspecified = SymbolConfiguration()

    public private(set) var pointSize: CGFloat = 0
    public private(set) var weight: SymbolWeight = .unspecified
    public private(set) var scale: SymbolScale = .default
    public private(set) var paletteColors: [UIColor] = []

    public override init() { super.init() }

    public init(pointSize: CGFloat) {
      self.pointSize = pointSize
      super.init()
    }

    public init(weight: SymbolWeight) {
      self.weight = weight
      super.init()
    }

    public init(pointSize: CGFloat, weight: SymbolWeight) {
      self.pointSize = pointSize
      self.weight = weight
      super.init()
    }

    public init(pointSize: CGFloat, weight: SymbolWeight, scale: SymbolScale) {
      self.pointSize = pointSize
      self.weight = weight
      self.scale = scale
      super.init()
    }

    public init(scale: SymbolScale) {
      self.scale = scale
      super.init()
    }

    public init(textStyle: UIFont.TextStyle) {
      self.pointSize = textStyle.metrics.size
      super.init()
    }

    public init(textStyle: UIFont.TextStyle, scale: SymbolScale) {
      self.pointSize = textStyle.metrics.size
      self.scale = scale
      super.init()
    }

    public init(font: UIFont) {
      self.pointSize = font.pointSize
      super.init()
    }

    public init(font: UIFont, scale: SymbolScale) {
      self.pointSize = font.pointSize
      self.scale = scale
      super.init()
    }

    public init(hierarchicalColor: UIColor) {
      self.paletteColors = [hierarchicalColor]
      super.init()
    }

    public init(paletteColors: [UIColor]) {
      self.paletteColors = paletteColors
      super.init()
    }

    public static func preferringMulticolor() -> SymbolConfiguration {
      SymbolConfiguration()
    }

    public static func preferringMonochrome() -> SymbolConfiguration {
      SymbolConfiguration()
    }

    public override func applying(_ otherConfiguration: Configuration?) -> Self {
      guard let other = otherConfiguration as? SymbolConfiguration else { return self }
      let merged = SymbolConfiguration()
      merged.pointSize = other.pointSize > 0 ? other.pointSize : pointSize
      merged.weight = other.weight != .unspecified ? other.weight : weight
      merged.scale = (other.scale != .default && other.scale != .unspecified) ? other.scale : scale
      merged.paletteColors = !other.paletteColors.isEmpty ? other.paletteColors : paletteColors
      merged.traitCollection = other.traitCollection ?? traitCollection
      return merged as! Self
    }
  }

  /// Registered by CrossSwiftUI so `UIImage(systemName:)` checks `SFSymbolCatalog`.
  nonisolated(unsafe) public static var symbolLookupHandler: (@Sendable (String) -> Bool)?

  /// Registered by CrossSwiftUI to rasterize `UIGraphicsImageRenderer` ops to PNG.
  nonisolated(unsafe) public static var offscreenRenderer: (@Sendable (CGSize, Bool, [_OffscreenDrawOp]) -> Data?)?

  public private(set) var size: CGSize
  public private(set) var scale: CGFloat
  public private(set) var imageOrientation: Orientation
  public private(set) var renderingMode: RenderingMode
  public private(set) var capInsets: UIEdgeInsets = .zero
  public private(set) var resizingMode: ResizingMode = .tile
  public private(set) var symbolName: String?
  public private(set) var symbolConfiguration: SymbolConfiguration?
  public private(set) var tintColorOverride: UIColor?
  public private(set) var filePath: String?
  public internal(set) var imageData: Data?

  public var isSymbolImage: Bool { symbolName != nil }
  public var configuration: Configuration? { symbolConfiguration }

  public override init() {
    self.size = .zero
    self.scale = 1.0
    self.imageOrientation = .up
    self.renderingMode = .automatic
    super.init()
  }

  internal init(
    size: CGSize,
    scale: CGFloat = 1.0,
    orientation: Orientation = .up,
    renderingMode: RenderingMode = .automatic
  ) {
    self.size = size
    self.scale = max(scale, 1.0)
    self.imageOrientation = orientation
    self.renderingMode = renderingMode
    super.init()
  }

  public init?(data: Data, scale: CGFloat) {
    guard !data.isEmpty else { return nil }
    self.imageData = data
    let resolvedScale = max(scale, 1.0)
    self.scale = resolvedScale
    self.imageOrientation = .up
    self.renderingMode = .automatic
    var w: Int32 = 0, h: Int32 = 0
    #if os(Windows)
      if data.withUnsafeBytes({ raw in
        cak_image_dimensions(raw.bindMemory(to: UInt8.self).baseAddress, data.count, &w, &h)
      }) == 0 {
        if let dims = Self.parsePNGHeaderDimensions(data) {
          w = Int32(dims.width)
          h = Int32(dims.height)
        }
      }
    #else
      if let dims = Self.parsePNGHeaderDimensions(data) {
        w = Int32(dims.width)
        h = Int32(dims.height)
      }
    #endif
    if w <= 0 || h <= 0 { w = 32; h = 32 }
    self.size = CGSize(width: CGFloat(w) / resolvedScale, height: CGFloat(h) / resolvedScale)
    super.init()
  }

  public convenience init?(data: Data) {
    self.init(data: data, scale: 1.0)
  }

  public init?(contentsOfFile path: String) {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    self.filePath = path
    let loaded = try? Data(contentsOf: URL(fileURLWithPath: path))
    self.imageData = loaded
    self.scale = 1.0
    self.imageOrientation = .up
    self.renderingMode = .automatic
    var w: Int32 = 0, h: Int32 = 0
    #if os(Windows)
      _ = cak_image_file_dimensions(path, &w, &h)
    #endif
    if (w <= 0 || h <= 0), let loaded, let dims = Self.parsePNGHeaderDimensions(loaded) {
      w = Int32(dims.width)
      h = Int32(dims.height)
    }
    if w <= 0 || h <= 0 { w = 32; h = 32 }
    self.size = CGSize(width: CGFloat(w), height: CGFloat(h))
    super.init()
  }

  public init?(
    systemName name: String,
    withConfiguration configuration: Configuration? = nil
  ) {
    let lookup = Self.symbolLookupHandler ?? CrossAppKit.NSImage.symbolLookupHandler
    if let lookup, !lookup(name) {
      return nil
    }
    let symCfg = configuration as? SymbolConfiguration
    let pt = (symCfg?.pointSize ?? 0) > 0 ? symCfg!.pointSize : 17
    let scaleMult = symCfg?.scale.scaleFactor ?? 1.0
    let boxSide = (pt * scaleMult * 1.18).rounded()
    self.symbolName = name
    self.symbolConfiguration = symCfg
    self.size = CGSize(width: boxSide, height: boxSide)
    self.scale = 2.0
    self.imageOrientation = .up
    self.renderingMode = (symCfg?.paletteColors.isEmpty ?? true) ? .alwaysTemplate : .alwaysOriginal
    super.init()
  }

  public convenience init?(
    systemName name: String,
    compatibleWith traitCollection: UITraitCollection?
  ) {
    let cfg = SymbolConfiguration()
    cfg.traitCollection = traitCollection
    self.init(systemName: name, withConfiguration: cfg)
  }

  public static func resolveAssetPath(named name: String, in bundle: Bundle? = nil) -> String? {
    CrossAppKit.NSImage.resolveAssetPath(named: name, in: bundle)
  }

  public convenience init?(
    named name: String,
    in bundle: Bundle? = nil,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) {
    if let resolved = Self.resolveAssetPath(named: name, in: bundle) {
      self.init(contentsOfFile: resolved)
      return
    }
    return nil
  }

  public convenience init?(
    named name: String,
    in bundle: Bundle?,
    with configuration: Configuration?
  ) {
    if let resolved = CrossAppKit.NSImage.resolveAssetPath(named: name, in: bundle) {
      self.init(contentsOfFile: resolved)
      if let symCfg = configuration as? SymbolConfiguration {
        self.symbolConfiguration = symCfg
      }
      return
    }
    return nil
  }

  #if !os(macOS)
    public convenience init(cgImage: CGImage, scale: CGFloat = 1.0, orientation: Orientation = .up) {
      let s = max(scale, 1.0)
      self.init(
        size: CGSize(width: CGFloat(cgImage.width) / s, height: CGFloat(cgImage.height) / s),
        scale: s,
        orientation: orientation
      )
      self.imageData = cgImage.pngData
    }

    public var cgImage: CGImage? {
      let pxW = max(Int((size.width * scale).rounded()), 1)
      let pxH = max(Int((size.height * scale).rounded()), 1)
      return CGImage(width: pxW, height: pxH, pngData: imageData)
    }
  #endif

  open func copy(with zone: NSZone? = nil) -> Any { self }

  private func cloneImage() -> UIImage {
    let copy = UIImage(size: size, scale: scale, orientation: imageOrientation, renderingMode: renderingMode)
    copy.capInsets = capInsets
    copy.resizingMode = resizingMode
    copy.symbolName = symbolName
    copy.symbolConfiguration = symbolConfiguration
    copy.tintColorOverride = tintColorOverride
    copy.filePath = filePath
    copy.imageData = imageData
    return copy
  }

  public func withRenderingMode(_ renderingMode: RenderingMode) -> UIImage {
    let copy = cloneImage()
    copy.renderingMode = renderingMode
    return copy
  }

  public func withConfiguration(_ configuration: Configuration) -> UIImage {
    guard let symCfg = configuration as? SymbolConfiguration else { return self }
    return applyingSymbolConfiguration(symCfg) ?? self
  }

  public func applyingSymbolConfiguration(_ configuration: SymbolConfiguration) -> UIImage? {
    let base = symbolConfiguration ?? SymbolConfiguration(pointSize: 17, weight: .regular)
    let merged = base.applying(configuration)
    let pt = merged.pointSize > 0 ? merged.pointSize : 17
    let boxSide = (pt * merged.scale.scaleFactor * 1.18).rounded()
    let copy = cloneImage()
    copy.size = CGSize(width: boxSide, height: boxSide)
    copy.symbolConfiguration = merged
    if !merged.paletteColors.isEmpty {
      copy.renderingMode = .alwaysOriginal
    }
    return copy
  }

  public func withTintColor(_ color: UIColor, renderingMode: RenderingMode = .automatic) -> UIImage {
    let copy = cloneImage()
    copy.tintColorOverride = color
    copy.renderingMode = renderingMode == .automatic ? .alwaysOriginal : renderingMode
    if copy.symbolName != nil {
      let cfg = (copy.symbolConfiguration ?? SymbolConfiguration()).applying(SymbolConfiguration(paletteColors: [color]))
      copy.symbolConfiguration = cfg
    }
    return copy
  }

  public func resizableImage(withCapInsets capInsets: UIEdgeInsets, resizingMode: ResizingMode = .tile) -> UIImage {
    let copy = cloneImage()
    copy.capInsets = capInsets
    copy.resizingMode = resizingMode
    return copy
  }

  public func preparingThumbnail(of size: CGSize) -> UIImage? {
    let copy = cloneImage()
    copy.size = size
    return copy
  }

  public func byPreparingThumbnail(ofSize size: CGSize, completionHandler: @escaping @Sendable (UIImage?) -> Void) {
    let thumb = preparingThumbnail(of: size)
    completionHandler(thumb)
  }

  public func pngData() -> Data? {
    if let data = imageData { return data }
    if let path = filePath { return try? Data(contentsOf: URL(fileURLWithPath: path)) }
    return nil
  }

  public func jpegData(compressionQuality: CGFloat) -> Data? {
    pngData()
  }

  public func draw(at point: CGPoint) {
    draw(in: CGRect(origin: point, size: size))
  }

  public func draw(at point: CGPoint, blendMode: Int32, alpha: CGFloat) {
    draw(in: CGRect(origin: point, size: size))
  }

  public func draw(in rect: CGRect) {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    if let sym = symbolName {
      let colorARGB =
        tintColorOverride?._packedARGB
        ?? symbolConfiguration?.paletteColors.first?._packedARGB
        ?? ctx.fillARGB
      let pt = (symbolConfiguration?.pointSize ?? 0) > 0 ? symbolConfiguration!.pointSize : rect.height
      let weight = symbolConfiguration?.weight.fontWeight().cssWeight ?? 400
      ctx.ops.append(.symbol(name: sym, rect: rect, colorARGB: colorARGB, pointSize: pt, weight: weight))
    } else if let data = pngData() {
      ctx.ops.append(.image(pngData: data, rect: rect))
    }
  }

  public func draw(in rect: CGRect, blendMode: Int32, alpha: CGFloat) {
    draw(in: rect)
  }

  public func ensureTemporaryFilePath() -> String? {
    if let filePath, FileManager.default.fileExists(atPath: filePath) {
      return filePath
    }
    guard let data = imageData, !data.isEmpty else { return nil }
    var hash = UInt64(1469598103934665603)
    let step = max(1, data.count / 256)
    data.withUnsafeBytes { raw in
      let bytes = raw.bindMemory(to: UInt8.self)
      var idx = 0
      while idx < bytes.count {
        hash = (hash ^ UInt64(bytes[idx])) &* 1099511628211
        idx += step
      }
      if bytes.count > 1 {
        hash = (hash ^ UInt64(bytes[bytes.count - 1])) &* 1099511628211
      }
    }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CrossUIKitImages", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("uiimg_\(data.count)_\(String(hash, radix: 16)).png")
    if !FileManager.default.fileExists(atPath: file.path) {
      try? data.write(to: file, options: .atomic)
    }
    self.filePath = file.path
    return file.path
  }

  #if !os(macOS)
    public func toNativeImage() -> NativeAPI.Image? {
      if let path = ensureTemporaryFilePath() {
        return NativeAPI.Image.fromFile(path)
      }
      if let data = imageData {
        return NativeAPI.Image.fromBase64(data.base64EncodedString())
      }
      return nil
    }
  #endif

  internal static func parsePNGHeaderDimensions(_ data: Data) -> (width: Int, height: Int)? {
    guard data.count >= 24 else { return nil }
    let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let header = [UInt8](data.prefix(24))
    guard Array(header[0..<8]) == sig,
          header[12] == 0x49, header[13] == 0x48, header[14] == 0x44, header[15] == 0x52
    else { return nil }
    let w = (Int(header[16]) << 24) | (Int(header[17]) << 16) | (Int(header[18]) << 8) | Int(header[19])
    let h = (Int(header[20]) << 24) | (Int(header[21]) << 16) | (Int(header[22]) << 8) | Int(header[23])
    guard w > 0 && h > 0 else { return nil }
    return (w, h)
  }

  internal static func encodeMinimalSolidPNG(width: Int, height: Int, argb: UInt32) -> Data {
    // 1x1 valid RGBA PNG header+IDAT+IEND fallback for headless tests when native rasterizer isn't attached.
    let png1x1: [UInt8] = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]
    _ = (width, height, argb)
    return Data(png1x1)
  }
}

// MARK: - UIBezierPath

open class UIBezierPath: NSObject, NSCopying {
  private enum ShapeStorage {
    case rect(CGRect)
    case roundedRect(CGRect, CGFloat)
    case oval(CGRect)
    case commands([Double], CGRect)
    case empty
  }

  private var storage: ShapeStorage
  private var recordedCommands: [Double] = []
  private var minPoint = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude)
  private var maxPoint = CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude)

  public var lineWidth: CGFloat = 1.0
  public var miterLimit: CGFloat = 10.0
  public var flatness: CGFloat = 0.6
  public var usesEvenOddFillRule: Bool = false
  public private(set) var currentPoint: CGPoint = .zero

  public var isEmpty: Bool {
    switch storage {
    case .empty: return recordedCommands.isEmpty
    default: return false
    }
  }

  public var bounds: CGRect {
    switch storage {
    case .rect(let r), .roundedRect(let r, _), .oval(let r):
      return r
    case .commands(_, let b):
      return b
    case .empty:
      guard minPoint.x <= maxPoint.x && minPoint.y <= maxPoint.y else { return .zero }
      return CGRect(
        x: minPoint.x,
        y: minPoint.y,
        width: max(0, maxPoint.x - minPoint.x),
        height: max(0, maxPoint.y - minPoint.y)
      )
    }
  }

  #if !os(macOS)
    public var cgPath: CGPath {
      switch storage {
      case .commands(let cmds, _):
        return CGPath(commands: cmds)
      default:
        return CGPath(commands: recordedCommands)
      }
    }
  #endif

  public override init() {
    self.storage = .empty
    super.init()
  }

  public init(rect: CGRect) {
    self.storage = .rect(rect)
    super.init()
  }

  public init(ovalIn rect: CGRect) {
    self.storage = .oval(rect)
    super.init()
  }

  public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
    self.storage = .roundedRect(rect, max(0, cornerRadius))
    super.init()
  }

  public init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
    let r = corners.isEmpty ? 0 : max(0, min(cornerRadii.width, cornerRadii.height))
    self.storage = .roundedRect(rect, r)
    super.init()
  }

  public init(
    arcCenter center: CGPoint,
    radius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    clockwise: Bool
  ) {
    self.storage = .empty
    super.init()
    addArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
  }

  #if !os(macOS)
    public init(cgPath: CGPath) {
      self.storage = cgPath.commands.isEmpty ? .empty : .commands(cgPath.commands, .zero)
      self.recordedCommands = cgPath.commands
      super.init()
    }
  #endif

  open func copy(with zone: NSZone? = nil) -> Any {
    let c = UIBezierPath()
    c.storage = storage
    c.recordedCommands = recordedCommands
    c.minPoint = minPoint
    c.maxPoint = maxPoint
    c.lineWidth = lineWidth
    c.miterLimit = miterLimit
    c.flatness = flatness
    c.usesEvenOddFillRule = usesEvenOddFillRule
    c.currentPoint = currentPoint
    return c
  }

  private func trackPoint(_ p: CGPoint) {
    minPoint.x = min(minPoint.x, p.x)
    minPoint.y = min(minPoint.y, p.y)
    maxPoint.x = max(maxPoint.x, p.x)
    maxPoint.y = max(maxPoint.y, p.y)
    currentPoint = p
  }

  public func move(to point: CGPoint) {
    recordedCommands.append(contentsOf: [0, Double(point.x), Double(point.y)])
    trackPoint(point)
  }

  public func addLine(to point: CGPoint) {
    recordedCommands.append(contentsOf: [1, Double(point.x), Double(point.y)])
    trackPoint(point)
  }

  public func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {
    recordedCommands.append(contentsOf: [
      2,
      Double(controlPoint1.x), Double(controlPoint1.y),
      Double(controlPoint2.x), Double(controlPoint2.y),
      Double(endPoint.x), Double(endPoint.y),
    ])
    trackPoint(controlPoint1)
    trackPoint(controlPoint2)
    trackPoint(endPoint)
  }

  public func addQuadCurve(to endPoint: CGPoint, controlPoint: CGPoint) {
    let cp1 = CGPoint(
      x: currentPoint.x + (2.0 / 3.0) * (controlPoint.x - currentPoint.x),
      y: currentPoint.y + (2.0 / 3.0) * (controlPoint.y - currentPoint.y)
    )
    let cp2 = CGPoint(
      x: endPoint.x + (2.0 / 3.0) * (controlPoint.x - endPoint.x),
      y: endPoint.y + (2.0 / 3.0) * (controlPoint.y - endPoint.y)
    )
    addCurve(to: endPoint, controlPoint1: cp1, controlPoint2: cp2)
  }

  public func addArc(
    withCenter center: CGPoint,
    radius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    clockwise: Bool
  ) {
    let steps = 16
    var delta = endAngle - startAngle
    if clockwise && delta < 0 { delta += 2 * .pi }
    if !clockwise && delta > 0 { delta -= 2 * .pi }
    for i in 0...steps {
      let angle = startAngle + delta * CGFloat(i) / CGFloat(steps)
      let pt = CGPoint(
        x: center.x + radius * CGFloat(Foundation.cos(Double(angle))),
        y: center.y + radius * CGFloat(Foundation.sin(Double(angle)))
      )
      if i == 0 && recordedCommands.isEmpty {
        move(to: pt)
      } else {
        addLine(to: pt)
      }
    }
  }

  public func close() {
    recordedCommands.append(3)
  }

  public func removeAllPoints() {
    storage = .empty
    recordedCommands.removeAll()
    minPoint = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude)
    maxPoint = CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude)
    currentPoint = .zero
  }

  public func append(_ bezierPath: UIBezierPath) {
    if !bezierPath.recordedCommands.isEmpty {
      recordedCommands.append(contentsOf: bezierPath.recordedCommands)
      storage = .empty
    }
  }

  public func apply(_ transform: CGAffineTransform) {}

  public func fill() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    switch storage {
    case .rect(let r):
      ctx.ops.append(.shape(rect: r, radius: 0, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .roundedRect(let r, let rad):
      ctx.ops.append(.shape(rect: r, radius: rad, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .oval(let r):
      ctx.ops.append(.shape(rect: r, radius: min(r.width, r.height) / 2, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .commands(let cmds, _):
      ctx.ops.append(.path(commands: cmds, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .empty:
      if !recordedCommands.isEmpty {
        ctx.ops.append(.path(commands: recordedCommands, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
      }
    }
  }

  public func fill(with blendMode: Int32, alpha: CGFloat) { fill() }

  public func stroke() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    let w = max(lineWidth, 0.5)
    switch storage {
    case .rect(let r):
      ctx.ops.append(.shape(rect: r, radius: 0, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .roundedRect(let r, let rad):
      ctx.ops.append(.shape(rect: r, radius: rad, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .oval(let r):
      ctx.ops.append(.shape(rect: r, radius: min(r.width, r.height) / 2, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .commands(let cmds, _):
      ctx.ops.append(.path(commands: cmds, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .empty:
      if !recordedCommands.isEmpty {
        ctx.ops.append(.path(commands: recordedCommands, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
      }
    }
  }

  public func stroke(with blendMode: Int32, alpha: CGFloat) { stroke() }
  public func addClip() {}
}

// MARK: - UIGraphicsImageRenderer & Legacy UIGraphics Image Context

open class UIGraphicsRendererFormat: NSObject, NSCopying {
  public var bounds: CGRect = .zero
  public class func `default`() -> Self { Self() }
  public class func preferred() -> Self { Self() }
  public required override init() { super.init() }
  open func copy(with zone: NSZone? = nil) -> Any { Self() }
}

open class UIGraphicsImageRendererFormat: UIGraphicsRendererFormat {
  public enum Range: Int, Sendable {
    case unspecified = -1
    case automatic = 0
    case extended = 1
    case standard = 2
  }

  public var scale: CGFloat = 2.0
  public var opaque: Bool = false
  public var preferredRange: Range = .automatic

  public required init() {
    super.init()
  }

  open override func copy(with zone: NSZone? = nil) -> Any {
    let f = UIGraphicsImageRendererFormat()
    f.bounds = bounds
    f.scale = scale
    f.opaque = opaque
    f.preferredRange = preferredRange
    return f
  }
}

open class UIGraphicsRendererContext: NSObject {
  public let format: UIGraphicsRendererFormat
  #if !os(macOS)
    public let cgContext = CGContext()
  #endif

  public init(format: UIGraphicsRendererFormat) {
    self.format = format
    super.init()
  }

  public func fill(_ rect: CGRect) {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    ctx.ops.append(.shape(rect: rect, radius: 0, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
  }

  public func stroke(_ rect: CGRect) {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    ctx.ops.append(.shape(rect: rect, radius: 0, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: 1.0))
  }

  public func clip(to rect: CGRect) {}
}

open class UIGraphicsImageRendererContext: UIGraphicsRendererContext {
  public var currentImage: UIImage {
    UIImage(size: format.bounds.size, scale: (format as? UIGraphicsImageRendererFormat)?.scale ?? 2.0)
  }
}

open class UIGraphicsRenderer: NSObject {
  public let bounds: CGRect
  public let format: UIGraphicsRendererFormat

  public init(bounds: CGRect, format: UIGraphicsRendererFormat = .default()) {
    self.bounds = bounds
    let copied = (format.copy() as? UIGraphicsRendererFormat) ?? format
    copied.bounds = bounds
    self.format = copied
    super.init()
  }
}

open class UIGraphicsImageRenderer: UIGraphicsRenderer {
  public typealias DrawingActions = (UIGraphicsImageRendererContext) -> Void

  public convenience init(size: CGSize) {
    self.init(bounds: CGRect(origin: .zero, size: size), format: UIGraphicsImageRendererFormat.default())
  }

  public init(size: CGSize, format: UIGraphicsImageRendererFormat) {
    super.init(bounds: CGRect(origin: .zero, size: size), format: format)
  }

  public override init(bounds: CGRect, format: UIGraphicsRendererFormat = UIGraphicsImageRendererFormat.default()) {
    super.init(bounds: bounds, format: format)
  }

  public func image(actions: DrawingActions) -> UIImage {
    let imgFormat = (format as? UIGraphicsImageRendererFormat) ?? UIGraphicsImageRendererFormat.default()
    let renderScale = max(imgFormat.scale, 1.0)
    let ctx = _OffscreenDrawingContext()
    _OffscreenDrawingContext.push(ctx)
    let rendererCtx = UIGraphicsImageRendererContext(format: imgFormat)
    actions(rendererCtx)
    _OffscreenDrawingContext.pop()

    let rasterizer = UIImage.offscreenRenderer ?? CrossAppKit.NSImage.offscreenRenderer
    let png: Data?
    if !ctx.ops.isEmpty, let r = rasterizer {
      png = r(bounds.size, true, ctx.ops)
    } else if !ctx.ops.isEmpty {
      png = UIImage.encodeMinimalSolidPNG(
        width: max(Int(bounds.width), 1),
        height: max(Int(bounds.height), 1),
        argb: ctx.fillARGB
      )
    } else {
      png = UIImage.encodeMinimalSolidPNG(
        width: max(Int(bounds.width), 1),
        height: max(Int(bounds.height), 1),
        argb: 0
      )
    }

    let result = UIImage(size: bounds.size, scale: renderScale)
    result.imageData = png
    return result
  }

  public func pngData(actions: DrawingActions) -> Data {
    image(actions: actions).pngData() ?? Data()
  }

  public func jpegData(withCompressionQuality compressionQuality: CGFloat, actions: DrawingActions) -> Data {
    pngData(actions: actions)
  }
}

// Legacy UIGraphics image context helpers
private final class _LegacyImageContextEntry {
  let size: CGSize
  let scale: CGFloat
  let drawing: _OffscreenDrawingContext
  init(size: CGSize, scale: CGFloat, drawing: _OffscreenDrawingContext) {
    self.size = size
    self.scale = scale
    self.drawing = drawing
  }
}

private let _legacyCtxLock = NSLock()
nonisolated(unsafe) private var _legacyCtxStacks: [UInt64: [_LegacyImageContextEntry]] = [:]

public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
  let resolvedScale = scale > 0 ? scale : 2.0
  let drawing = _OffscreenDrawingContext()
  _OffscreenDrawingContext.push(drawing)
  let tid = _crossUIKitThreadKey()
  _legacyCtxLock.lock()
  _legacyCtxStacks[tid, default: []].append(_LegacyImageContextEntry(size: size, scale: resolvedScale, drawing: drawing))
  _legacyCtxLock.unlock()
}

public func UIGraphicsBeginImageContext(_ size: CGSize) {
  UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
}

#if !os(macOS)
  public func UIGraphicsGetCurrentContext() -> CGContext? {
    _OffscreenDrawingContext.current != nil ? CGContext() : nil
  }
#endif

public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
  let tid = _crossUIKitThreadKey()
  _legacyCtxLock.lock()
  let entry = _legacyCtxStacks[tid]?.last
  _legacyCtxLock.unlock()
  guard let entry else { return nil }
  let rasterizer = UIImage.offscreenRenderer ?? CrossAppKit.NSImage.offscreenRenderer
  let data = rasterizer?(entry.size, true, entry.drawing.ops)
    ?? UIImage.encodeMinimalSolidPNG(width: max(Int(entry.size.width), 1), height: max(Int(entry.size.height), 1), argb: entry.drawing.fillARGB)
  let img = UIImage(size: entry.size, scale: entry.scale)
  img.imageData = data
  return img
}

public func UIGraphicsEndImageContext() {
  let tid = _crossUIKitThreadKey()
  _legacyCtxLock.lock()
  if var arr = _legacyCtxStacks[tid] {
    _ = arr.popLast()
    if arr.isEmpty {
      _legacyCtxStacks.removeValue(forKey: tid)
    } else {
      _legacyCtxStacks[tid] = arr
    }
  }
  _legacyCtxLock.unlock()
  _OffscreenDrawingContext.pop()
}
