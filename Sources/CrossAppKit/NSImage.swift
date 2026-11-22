import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

public struct NSColorSpaceName: RawRepresentable, Equatable, Hashable, ExpressibleByStringLiteral, Sendable {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public static let calibratedWhite = NSColorSpaceName("NSCalibratedWhiteColorSpace")
  public static let calibratedRGB = NSColorSpaceName("NSCalibratedRGBColorSpace")
  public static let deviceWhite = NSColorSpaceName("NSDeviceWhiteColorSpace")
  public static let deviceRGB = NSColorSpaceName("NSDeviceRGBColorSpace")
  public static let deviceCMYK = NSColorSpaceName("NSDeviceCMYKColorSpace")
}

open class NSImageRep: NSObject, @unchecked Sendable {
  public var size: NSSize
  public var pixelsWide: Int
  public var pixelsHigh: Int

  public init(size: NSSize = .zero, pixelsWide: Int = 0, pixelsHigh: Int = 0) {
    self.size = size
    self.pixelsWide = pixelsWide
    self.pixelsHigh = pixelsHigh
    super.init()
  }
}

open class NSBitmapImageRep: NSImageRep, @unchecked Sendable {
  public enum FileType: UInt, Sendable {
    case tiff = 0
    case bmp = 1
    case gif = 2
    case jpeg = 3
    case png = 4
    case jpeg2000 = 5
  }

  public struct PropertyKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let compressionFactor = PropertyKey("NSImageCompressionFactor")
    public static let frameCount = PropertyKey("NSImageFrameCount")
    public static let currentFrame = PropertyKey("NSImageCurrentFrame")
    public static let currentFrameDuration = PropertyKey("NSImageCurrentFrameDuration")
  }

  public struct Format: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let alphaFirst = Format(rawValue: 1 << 0)
    public static let alphaNonpremultiplied = Format(rawValue: 1 << 1)
    public static let floatingPointSamples = Format(rawValue: 1 << 2)
    public static let sixteenBitLittleEndian = Format(rawValue: 1 << 8)
    public static let thirtyTwoBitLittleEndian = Format(rawValue: 1 << 9)
    public static let sixteenBitBigEndian = Format(rawValue: 1 << 10)
    public static let thirtyTwoBitBigEndian = Format(rawValue: 1 << 11)
  }

  public private(set) var pngData: Data?
  public private(set) var bytesPerRow: Int = 0
  private var pixelBuffer: UnsafeMutableBufferPointer<UInt8>?
  public var bitmapData: UnsafeMutablePointer<UInt8>? { pixelBuffer?.baseAddress }

  deinit {
    pixelBuffer?.deallocate()
  }

  public init?(data: Data) {
    self.pngData = data
    var w: Int32 = 0, h: Int32 = 0
    #if os(Windows)
      _ = data.withUnsafeBytes { raw in
        cak_image_dimensions(raw.bindMemory(to: UInt8.self).baseAddress, data.count, &w, &h)
      }
    #endif
    let width = max(Int(w), 1)
    let height = max(Int(h), 1)
    self.bytesPerRow = width * 4
    let sz = NSSize(width: CGFloat(width), height: CGFloat(height))
    super.init(size: sz, pixelsWide: width, pixelsHigh: height)
  }

  #if !os(macOS)
    public init(cgImage: CGImage) {
      self.pngData = cgImage.pngData
      self.bytesPerRow = max(cgImage.width, 1) * 4
      super.init(
        size: NSSize(width: cgImage.width, height: cgImage.height),
        pixelsWide: cgImage.width,
        pixelsHigh: cgImage.height
      )
    }
  #endif

  public init?(
    bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    pixelsWide width: Int,
    pixelsHigh height: Int,
    bitsPerSample bps: Int,
    samplesPerPixel spp: Int,
    hasAlpha alpha: Bool,
    isPlanar: Bool,
    colorSpaceName: NSColorSpaceName,
    bytesPerRow rowBytes: Int,
    bitsPerPixel pixelBits: Int
  ) {
    self.pngData = nil
    let bpr = rowBytes > 0 ? rowBytes : max(width, 1) * max(spp, 4)
    self.bytesPerRow = bpr
    let total = max(bpr * max(height, 1), 1)
    let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: total)
    buf.initialize(repeating: 0)
    self.pixelBuffer = buf
    super.init(
      size: NSSize(width: width, height: height),
      pixelsWide: width,
      pixelsHigh: height
    )
  }

  public init?(
    bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    pixelsWide width: Int,
    pixelsHigh height: Int,
    bitsPerSample bps: Int,
    samplesPerPixel spp: Int,
    hasAlpha alpha: Bool,
    isPlanar: Bool,
    colorSpaceName: NSColorSpaceName,
    bitmapFormat: Format,
    bytesPerRow rowBytes: Int,
    bitsPerPixel pixelBits: Int
  ) {
    self.pngData = nil
    let bpr = rowBytes > 0 ? rowBytes : max(width, 1) * max(spp, 4)
    self.bytesPerRow = bpr
    let total = max(bpr * max(height, 1), 1)
    let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: total)
    buf.initialize(repeating: 0)
    self.pixelBuffer = buf
    super.init(
      size: NSSize(width: width, height: height),
      pixelsWide: width,
      pixelsHigh: height
    )
  }

  public func draw(in rect: NSRect) {}

  public func representation(using storageType: FileType, properties: [PropertyKey: Any] = [:]) -> Data? {
    pngData
  }

  public func value(forProperty property: PropertyKey) -> Any? {
    if property == .frameCount { return NSNumber(value: 1) }
    return nil
  }
}

open class NSGraphicsContext: NSObject, @unchecked Sendable {
  public enum ImageInterpolation: UInt, Sendable {
    case `default` = 0
    case none = 1
    case low = 2
    case medium = 4
    case high = 3
  }

  nonisolated(unsafe) public static var current: NSGraphicsContext? = NSGraphicsContext()
  public var imageInterpolation: ImageInterpolation = .high
  #if !os(macOS)
    public let cgContext = CGContext()
  #endif

  public init?(bitmapImageRep: NSBitmapImageRep) {
    #if !os(macOS)
      return nil
    #else
      super.init()
    #endif
  }

  public override init() {
    super.init()
  }

  public static func saveGraphicsState() {}
  public static func restoreGraphicsState() {}
}

public enum _OffscreenDrawOp: Sendable {
  case shape(rect: NSRect, radius: CGFloat, fillARGB: UInt32, strokeARGB: UInt32, strokeWidth: CGFloat)
  case path(commands: [Double], fillARGB: UInt32, strokeARGB: UInt32, strokeWidth: CGFloat)
  case symbol(name: String, rect: NSRect, colorARGB: UInt32, pointSize: CGFloat, weight: Double)
  case image(pngData: Data, rect: NSRect)
  case text(string: String, rect: NSRect, fontSize: CGFloat, colorARGB: UInt32)
}

public protocol _CrossFontPointSizeProviding: AnyObject {
  var pointSize: CGFloat { get }
}

public protocol _CrossPackedColorProviding: AnyObject {
  var _packedARGB: UInt32 { get }
}

extension NSFont: _CrossFontPointSizeProviding {}
extension NSColor: _CrossPackedColorProviding {
  public var _packedARGB: UInt32 { packedARGB }
}

public final class _OffscreenDrawingContext {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var stacks: [UInt64: [_OffscreenDrawingContext]] = [:]

  public var fillARGB: UInt32 = 0xFF000000
  public var strokeARGB: UInt32 = 0xFF000000
  public var ops: [_OffscreenDrawOp] = []

  public init() {}

  public static var current: _OffscreenDrawingContext? {
    let tid = _crossAppKitThreadKey()
    lock.lock()
    defer { lock.unlock() }
    return stacks[tid]?.last
  }

  public static func push(_ ctx: _OffscreenDrawingContext) {
    let tid = _crossAppKitThreadKey()
    lock.lock()
    stacks[tid, default: []].append(ctx)
    lock.unlock()
  }

  public static func pop() {
    let tid = _crossAppKitThreadKey()
    lock.lock()
    if var arr = stacks[tid] {
      _ = arr.popLast()
      if arr.isEmpty {
        stacks.removeValue(forKey: tid)
      } else {
        stacks[tid] = arr
      }
    }
    lock.unlock()
  }
}

open class NSBezierPath: NSObject {
  internal enum Kind {
    case rect(NSRect)
    case roundedRect(NSRect, CGFloat)
    case oval(NSRect)
    case commands([Double])
    case empty
  }

  public let rect: NSRect
  internal let kind: Kind
  public var lineWidth: CGFloat = 1.0

  public init(rect: NSRect) {
    self.rect = rect
    self.kind = .rect(rect)
    super.init()
  }
  public init(roundedRect rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {
    self.rect = rect
    self.kind = .roundedRect(rect, min(xRadius, yRadius))
    super.init()
  }
  public init(ovalIn rect: NSRect) {
    self.rect = rect
    self.kind = .oval(rect)
    super.init()
  }
  #if !os(macOS)
    public init(cgPath: CGPath) {
      self.rect = .zero
      self.kind = cgPath.commands.isEmpty ? .empty : .commands(cgPath.commands)
      super.init()
    }
  #endif
  public override init() {
    self.rect = .zero
    self.kind = .empty
    super.init()
  }

  public func fill() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    switch kind {
    case .rect(let r):
      ctx.ops.append(.shape(rect: r, radius: 0, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .roundedRect(let r, let rad):
      ctx.ops.append(.shape(rect: r, radius: rad, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .oval(let r):
      ctx.ops.append(.shape(rect: r, radius: min(r.width, r.height) / 2, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .commands(let cmds):
      ctx.ops.append(.path(commands: cmds, fillARGB: ctx.fillARGB, strokeARGB: 0, strokeWidth: 0))
    case .empty:
      break
    }
  }

  public func stroke() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    let w = max(lineWidth, 0.5)
    switch kind {
    case .rect(let r):
      ctx.ops.append(.shape(rect: r, radius: 0, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .roundedRect(let r, let rad):
      ctx.ops.append(.shape(rect: r, radius: rad, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .oval(let r):
      ctx.ops.append(.shape(rect: r, radius: min(r.width, r.height) / 2, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .commands(let cmds):
      ctx.ops.append(.path(commands: cmds, fillARGB: 0, strokeARGB: ctx.strokeARGB, strokeWidth: w))
    case .empty:
      break
    }
  }

  public func addClip() {}
}

open class NSImage: NSObject, @unchecked Sendable {
  public typealias Name = String

  public struct SymbolConfiguration: Equatable, Sendable {
    public var pointSize: CGFloat
    public var weight: NSFont.Weight
    public var paletteColors: [NSColor]

    public init(pointSize: CGFloat = 14, weight: NSFont.Weight = .regular) {
      self.pointSize = pointSize
      self.weight = weight
      self.paletteColors = []
    }

    public init(textStyle: NSFont.TextStyle) {
      let m = textStyle.metrics
      self.pointSize = m.size
      self.weight = m.weight
      self.paletteColors = []
    }

    public init(paletteColors: [NSColor]) {
      self.pointSize = 0
      self.weight = .regular
      self.paletteColors = paletteColors
    }

    public init(hierarchicalColor: NSColor) {
      self.pointSize = 0
      self.weight = .regular
      self.paletteColors = [hierarchicalColor]
    }

    public func applying(_ other: SymbolConfiguration) -> SymbolConfiguration {
      var copy = self
      if other.pointSize > 0 { copy.pointSize = other.pointSize }
      if other.weight != .regular { copy.weight = other.weight }
      if !other.paletteColors.isEmpty { copy.paletteColors = other.paletteColors }
      return copy
    }
  }

  public enum CapInsetsMode: Int, Sendable {
    case stretch = 0
    case tile = 1
  }

  /// Registered by CrossSwiftUI's SF Symbol SVG catalog so `NSImage(systemSymbolName:)`
  /// returns non-nil for every known symbol and carries its symbol name for rendering.
  nonisolated(unsafe) public static var symbolLookupHandler: (@Sendable (String) -> Bool)?

  /// Registered by CrossSwiftUI to rasterize `NSImage(size:flipped:drawingHandler:)` to PNG.
  nonisolated(unsafe) public static var offscreenRenderer: (@Sendable (NSSize, Bool, [_OffscreenDrawOp]) -> Data?)?

  /// Registered by CrossSwiftUI to rasterize `.svg`, `.pdf`, and `sf://` vector assets to PNG.
  nonisolated(unsafe) public static var vectorRasterizer: (@Sendable (String, NSSize) -> Data?)?

  /// Optional resource directory paths searched by `NSImage(named:)` for `.imageset` / PNG / SVG files.
  nonisolated(unsafe) public static var resourceSearchPaths: [String] = []

  public var size: NSSize
  public var isTemplate: Bool = false
  public private(set) var symbolName: String?
  public private(set) var symbolConfiguration: SymbolConfiguration?
  public private(set) var filePath: String?
  public private(set) var imageData: Data?
  public var representations: [NSImageRep] = []

  public init(size: NSSize) {
    self.size = size
    super.init()
  }

  public convenience override init() {
    self.init(size: .zero)
  }

  public convenience init(size: NSSize, flipped drawingHandlerShouldBeCalledWithFlippedContext: Bool, drawingHandler: @escaping (NSRect) -> Bool) {
    self.init(size: size)
    let ctx = _OffscreenDrawingContext()
    _OffscreenDrawingContext.push(ctx)
    _ = drawingHandler(NSRect(origin: .zero, size: size))
    _OffscreenDrawingContext.pop()
    if !ctx.ops.isEmpty,
      let png = Self.offscreenRenderer?(size, drawingHandlerShouldBeCalledWithFlippedContext, ctx.ops),
      !png.isEmpty
    {
      self.imageData = png
      if let rep = NSBitmapImageRep(data: png) {
        rep.size = size
        self.representations = [rep]
      }
    }
  }

  public init?(data: Data) {
    guard !data.isEmpty else { return nil }
    self.imageData = data
    var w: Int32 = 0, h: Int32 = 0
    #if os(Windows)
      let ok = data.withUnsafeBytes { raw in
        cak_image_dimensions(raw.bindMemory(to: UInt8.self).baseAddress, data.count, &w, &h)
      }
      if ok == 0 {
        w = 32; h = 32
      }
    #else
      w = 32; h = 32
    #endif
    self.size = NSSize(width: CGFloat(max(Int(w), 1)), height: CGFloat(max(Int(h), 1)))
    super.init()
    if let rep = NSBitmapImageRep(data: data) {
      self.representations = [rep]
    }
  }

  public convenience init?(contentsOf url: URL) {
    self.init(contentsOfFile: url.path)
  }

  public init?(contentsOfFile fileName: String) {
    guard FileManager.default.fileExists(atPath: fileName) else { return nil }
    self.filePath = fileName
    let lower = fileName.lowercased()
    let isVectorFile = lower.hasSuffix(".svg") || lower.hasSuffix(".pdf")
    if !isVectorFile {
      self.imageData = try? Data(contentsOf: URL(fileURLWithPath: fileName))
    }
    var w: Int32 = 0, h: Int32 = 0
    #if os(Windows)
      if !isVectorFile {
        _ = cak_image_file_dimensions(fileName, &w, &h)
      }
    #endif
    if w <= 0 || h <= 0 { w = 32; h = 32 }
    self.size = NSSize(width: CGFloat(w), height: CGFloat(h))
    let parentURL = URL(fileURLWithPath: fileName).deletingLastPathComponent()
    if parentURL.pathExtension.lowercased() == "imageset" {
      let contentsURL = parentURL.appendingPathComponent("Contents.json")
      if let cData = try? Data(contentsOf: contentsURL),
         let json = try? JSONSerialization.jsonObject(with: cData) as? [String: Any],
         let props = json["properties"] as? [String: Any],
         (props["template-rendering-intent"] as? String) == "template"
      {
        self.isTemplate = true
      }
    }
    super.init()
    if let data = imageData, let rep = NSBitmapImageRep(data: data) {
      self.representations = [rep]
    }
  }

  public init?(systemSymbolName symbolName: String, accessibilityDescription description: String?) {
    if let lookup = Self.symbolLookupHandler, !lookup(symbolName) {
      return nil
    }
    self.symbolName = symbolName
    self.isTemplate = true
    self.size = NSSize(width: 16, height: 16)
    super.init()
  }

  public convenience init?(named name: Name) {
    if let resolved = Self.resolveAssetPath(named: name) {
      self.init(contentsOfFile: resolved)
      return
    }
    return nil
  }

  #if !os(macOS)
    public convenience init(cgImage: CGImage, size: NSSize) {
      if let data = cgImage.pngData, let decoded = NSImage(data: data) {
        self.init(size: size.width > 0 ? size : decoded.size)
        self.imageData = data
        self.representations = decoded.representations
      } else {
        self.init(size: size)
      }
    }

    public func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context referenceContext: NSGraphicsContext?, hints: [String: Any]?) -> CGImage? {
      CGImage(width: max(Int(size.width), 1), height: max(Int(size.height), 1), pngData: imageData)
    }
  #endif

  public func withSymbolConfiguration(_ configuration: SymbolConfiguration) -> NSImage? {
    let base = symbolConfiguration ?? SymbolConfiguration(pointSize: 16, weight: .regular)
    let merged = base.applying(configuration)
    let pt = merged.pointSize > 0 ? merged.pointSize : 16
    let boxSide = (pt * 1.15).rounded()
    let copy = NSImage(size: NSSize(width: boxSide, height: boxSide))
    copy.symbolName = symbolName
    copy.symbolConfiguration = merged
    copy.filePath = filePath
    copy.imageData = imageData
    copy.isTemplate = merged.paletteColors.isEmpty ? isTemplate : false
    return copy
  }

  public var tiffRepresentation: Data? {
    imageData
  }

  public func addRepresentation(_ imageRep: NSImageRep) {
    representations.append(imageRep)
    if let bmp = imageRep as? NSBitmapImageRep, imageData == nil {
      imageData = bmp.pngData
    }
  }

  public func draw(in rect: NSRect) {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    if let sym = symbolName {
      let colorARGB = symbolConfiguration?.paletteColors.first?.packedARGB ?? ctx.fillARGB
      let pt = (symbolConfiguration?.pointSize ?? 0) > 0 ? symbolConfiguration!.pointSize : rect.height
      let weight = symbolConfiguration?.weight.cssWeight ?? 400
      ctx.ops.append(.symbol(name: sym, rect: rect, colorARGB: colorARGB, pointSize: pt, weight: weight))
    } else if let data = imageData {
      ctx.ops.append(.image(pngData: data, rect: rect))
    }
  }
  public func draw(in dstSpacePortionRect: NSRect, from srcSpacePortionRect: NSRect, operation op: UInt, fraction requestedAlpha: CGFloat) {}
  public func lockFocus() {}
  public func unlockFocus() {}

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
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CrossAppKitImages", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("img_\(data.count)_\(String(hash, radix: 16)).png")
    if !FileManager.default.fileExists(atPath: file.path) {
      try? data.write(to: file, options: .atomic)
    }
    self.filePath = file.path
    return file.path
  }

  private nonisolated(unsafe) static var externalCatalogCache: [String: [String]] = [:]

  private static func loadExternalCatalogPaths(in root: URL) -> [String] {
    let manifestURL = root.appendingPathComponent("crossswift-assets.json")
    let key = manifestURL.path
    if let cached = externalCatalogCache[key] {
      return cached
    }
    guard let data = try? Data(contentsOf: manifestURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let paths = json["catalogPaths"] as? [String]
    else {
      externalCatalogCache[key] = []
      return []
    }
    externalCatalogCache[key] = paths
    return paths
  }

  public static func resolveAssetPath(named name: String, in bundle: Bundle? = nil) -> String? {
    var roots: [String] = []
    func appendRoot(_ path: String?) {
      guard let path, !path.isEmpty, !roots.contains(path) else { return }
      roots.append(path)
    }
    if let bundle {
      appendRoot(bundle.resourcePath)
      appendRoot(bundle.bundlePath)
    }
    for path in resourceSearchPaths {
      appendRoot(path)
    }
    appendRoot(Bundle.main.bundlePath)
    appendRoot(Bundle.main.resourcePath)

    let fm = FileManager.default
    for root in roots {
      let base = URL(fileURLWithPath: root)
      var candidates: [URL] = []
      // Support external catalog pointers synthesized for large *.xcassets directories.
      for extCatalog in loadExternalCatalogPaths(in: base) {
        candidates.append(URL(fileURLWithPath: extCatalog).appendingPathComponent("\(name).imageset"))
      }
      candidates.append(contentsOf: [
        base.appendingPathComponent("\(name).imageset"),
        base.appendingPathComponent("Assets.xcassets/\(name).imageset"),
      ])
      if let appFolder = (Bundle.main.infoDictionary?["CFBundleName"] as? String)
        ?? Bundle.main.executableURL?.deletingPathExtension().lastPathComponent,
        !appFolder.isEmpty
      {
        candidates.append(base.appendingPathComponent("\(appFolder)/Assets.xcassets/\(name).imageset"))
      }
      // Discover any *.xcassets catalog (e.g. FluentIcons.xcassets, IconAssets.xcassets)
      // directly in `root` or `root/Resources` without enumerating inside the catalogs.
      for container in [base, base.appendingPathComponent("Resources")] {
        if let items = try? fm.contentsOfDirectory(atPath: container.path) {
          for item in items where item.lowercased().hasSuffix(".xcassets") {
            let candidate = container.appendingPathComponent(item).appendingPathComponent("\(name).imageset")
            if !candidates.contains(candidate) {
              candidates.append(candidate)
            }
          }
        }
      }

      for imageset in candidates where fm.fileExists(atPath: imageset.path) {
        if let resolved = resolveImageInImageSet(imageset) {
          return resolved
        }
      }
      for container in [base, base.appendingPathComponent("Resources")] {
        for ext in ["svg", "pdf", "png", "jpg", "jpeg", "ico"] {
          let direct = container.appendingPathComponent("\(name).\(ext)")
          if fm.fileExists(atPath: direct.path) { return direct.path }
        }
      }
    }
    return nil
  }

  private static func resolveImageInImageSet(_ imageset: URL) -> String? {
    let fm = FileManager.default
    let priority = [".svg", ".pdf", ".png", ".jpg", ".jpeg"]
    func rank(_ filename: String) -> Int {
      let lower = filename.lowercased()
      for (idx, ext) in priority.enumerated() where lower.hasSuffix(ext) {
        return idx
      }
      return priority.count
    }

    // Prefer filenames declared in Contents.json when present.
    let contentsURL = imageset.appendingPathComponent("Contents.json")
    if let data = try? Data(contentsOf: contentsURL),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let images = json["images"] as? [[String: Any]]
    {
      let declared = images.compactMap { entry -> String? in
        guard let filename = entry["filename"] as? String, !filename.isEmpty else { return nil }
        let full = imageset.appendingPathComponent(filename)
        return fm.fileExists(atPath: full.path) ? filename : nil
      }
      if let best = declared.min(by: { rank($0) < rank($1) }), rank(best) < priority.count {
        return imageset.appendingPathComponent(best).path
      }
    }

    if let files = try? fm.contentsOfDirectory(atPath: imageset.path) {
      let matching = files.filter { rank($0) < priority.count }
      if let best = matching.min(by: { rank($0) < rank($1) }) {
        return imageset.appendingPathComponent(best).path
      }
    }
    return nil
  }

  #if !os(macOS)
    private var cachedRasterizedPNG: Data?

    public func toNativeImage() -> NativeAPI.Image? {
      if let cached = cachedRasterizedPNG {
        return NativeAPI.Image.fromBase64(cached.base64EncodedString())
      }
      if let sym = symbolName {
        let targetSide = max(32.0, max(size.width, size.height))
        if let png = Self.vectorRasterizer?(
          "sf://" + sym, NSSize(width: targetSide, height: targetSide)),
          !png.isEmpty
        {
          cachedRasterizedPNG = png
          return NativeAPI.Image.fromBase64(png.base64EncodedString())
        }
      }
      if let fp = filePath {
        let lower = fp.lowercased()
        if lower.hasSuffix(".svg") || lower.hasSuffix(".pdf") {
          let targetSide = max(32.0, max(size.width, size.height))
          if let png = Self.vectorRasterizer?(
            fp, NSSize(width: targetSide, height: targetSide)),
            !png.isEmpty
          {
            cachedRasterizedPNG = png
            return NativeAPI.Image.fromBase64(png.base64EncodedString())
          }
          #if os(Linux)
            if lower.hasSuffix(".svg"), FileManager.default.fileExists(atPath: fp) {
              return NativeAPI.Image.fromFile(fp)
            }
          #endif
          return nil
        }
      }
      if let path = ensureTemporaryFilePath() {
        return NativeAPI.Image.fromFile(path)
      }
      if let data = imageData {
        return NativeAPI.Image.fromBase64(data.base64EncodedString())
      }
      return nil
    }
  #endif
}

public extension Bundle {
  func image(forResource name: NSImage.Name) -> NSImage? {
    if let resolved = NSImage.resolveAssetPath(named: name, in: self) {
      return NSImage(contentsOfFile: resolved)
    }
    return nil
  }
}
