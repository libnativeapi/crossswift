import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

internal func _crossAppKitThreadKey() -> UInt64 {
  #if os(Windows)
    return UInt64(cak_current_thread_id())
  #else
    return UInt64(UInt(bitPattern: ObjectIdentifier(Thread.current)))
  #endif
}

open class NSAppearance: NSObject, @unchecked Sendable {
  public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let aqua = Name("NSAppearanceNameAqua")
    public static let darkAqua = Name("NSAppearanceNameDarkAqua")
    public static let vibrantLight = Name("NSAppearanceNameVibrantLight")
    public static let vibrantDark = Name("NSAppearanceNameVibrantDark")
  }

  public let name: Name

  private static let threadAppearanceLock = NSLock()
  nonisolated(unsafe) private static var threadAppearances: [UInt64: NSAppearance] = [:]
  nonisolated(unsafe) internal static var _appAppearanceOverride: NSAppearance?

  private static var _currentDrawingAppearance: NSAppearance? {
    get {
      let tid = _crossAppKitThreadKey()
      threadAppearanceLock.lock()
      defer { threadAppearanceLock.unlock() }
      return threadAppearances[tid]
    }
    set {
      let tid = _crossAppKitThreadKey()
      threadAppearanceLock.lock()
      defer { threadAppearanceLock.unlock() }
      threadAppearances[tid] = newValue
    }
  }

  public static func currentDrawing() -> NSAppearance {
    if let current = _currentDrawingAppearance { return current }
    if let appOverride = _appAppearanceOverride { return appOverride }
    return systemAppearance
  }

  public init?(named name: Name) {
    self.name = name
    super.init()
  }

  public func bestMatch(from appearances: [Name]) -> Name? {
    let prefersDark = (name == .darkAqua || name == .vibrantDark)
    if prefersDark {
      if appearances.contains(.darkAqua) { return .darkAqua }
      if appearances.contains(.vibrantDark) { return .vibrantDark }
    } else {
      if appearances.contains(.aqua) { return .aqua }
      if appearances.contains(.vibrantLight) { return .vibrantLight }
    }
    return appearances.first
  }

  public func performAsCurrentDrawingAppearance(_ block: () -> Void) {
    let previous = Self._currentDrawingAppearance
    Self._currentDrawingAppearance = self
    defer { Self._currentDrawingAppearance = previous }
    block()
  }

  public static var systemAppearance: NSAppearance {
    #if !os(macOS)
      let brightness = NativeAPI.Application.shared.getSystemBrightness()
      return NSAppearance(named: brightness == .light ? .aqua : .darkAqua)!
    #else
      return NSAppearance(named: .darkAqua)!
    #endif
  }
}

open class NSColorSpace: NSObject, @unchecked Sendable {
  public static let sRGB = NSColorSpace()
  public static let deviceRGB = NSColorSpace()
}

open class NSColor: NSObject, NSSecureCoding, @unchecked Sendable {
  public static var supportsSecureCoding: Bool { true }

  public required convenience init?(coder: NSCoder) {
    let r = coder.decodeDouble(forKey: "r")
    let g = coder.decodeDouble(forKey: "g")
    let b = coder.decodeDouble(forKey: "b")
    let a = coder.decodeDouble(forKey: "a")
    self.init(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
  }

  open func encode(with coder: NSCoder) {
    let c = resolved()
    coder.encode(Double(c.r), forKey: "r")
    coder.encode(Double(c.g), forKey: "g")
    coder.encode(Double(c.b), forKey: "b")
    coder.encode(Double(c.a), forKey: "a")
  }

  public typealias Name = String

  private let dynamicProvider: (@Sendable (NSAppearance) -> NSColor)?
  private let fixedRed: CGFloat
  private let fixedGreen: CGFloat
  private let fixedBlue: CGFloat
  private let fixedAlpha: CGFloat

  public var isDynamic: Bool { dynamicProvider != nil }

  public convenience override init() {
    self.init(srgbRed: 0, green: 0, blue: 0, alpha: 1)
  }

  public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.dynamicProvider = nil
    self.fixedRed = min(max(red, 0), 1)
    self.fixedGreen = min(max(green, 0), 1)
    self.fixedBlue = min(max(blue, 0), 1)
    self.fixedAlpha = min(max(alpha, 0), 1)
    super.init()
  }

  public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  public convenience init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  public convenience init(deviceRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }

  public convenience init(white: CGFloat, alpha: CGFloat) {
    self.init(srgbRed: white, green: white, blue: white, alpha: alpha)
  }

  public convenience init(calibratedWhite white: CGFloat, alpha: CGFloat) {
    self.init(srgbRed: white, green: white, blue: white, alpha: alpha)
  }

  public init(name: Name? = nil, dynamicProvider: @escaping (NSAppearance) -> NSColor) {
    nonisolated(unsafe) let box = dynamicProvider
    self.dynamicProvider = { box($0) }
    self.fixedRed = 0
    self.fixedGreen = 0
    self.fixedBlue = 0
    self.fixedAlpha = 1
    super.init()
  }

  public func resolved(for appearance: NSAppearance? = nil) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    if let provider = dynamicProvider {
      let target = appearance ?? NSAppearance.currentDrawing()
      let c = provider(target)
      return c.resolved(for: target)
    }
    return (fixedRed, fixedGreen, fixedBlue, fixedAlpha)
  }

  public var redComponent: CGFloat { resolved().r }
  public var greenComponent: CGFloat { resolved().g }
  public var blueComponent: CGFloat { resolved().b }
  public var alphaComponent: CGFloat { resolved().a }

  public func usingColorSpace(_ space: NSColorSpace) -> NSColor? {
    let c = resolved()
    return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
  }

  public func getRed(
    _ red: UnsafeMutablePointer<CGFloat>?,
    green: UnsafeMutablePointer<CGFloat>?,
    blue: UnsafeMutablePointer<CGFloat>?,
    alpha: UnsafeMutablePointer<CGFloat>?
  ) {
    let c = resolved()
    red?.pointee = c.r
    green?.pointee = c.g
    blue?.pointee = c.b
    alpha?.pointee = c.a
  }

  public func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
    let clamped = min(max(alpha, 0), 1)
    if let provider = dynamicProvider {
      return NSColor(name: nil) { appearance in
        provider(appearance).withAlphaComponent(clamped)
      }
    }
    return NSColor(srgbRed: fixedRed, green: fixedGreen, blue: fixedBlue, alpha: clamped)
  }

  internal var packedARGB: UInt32 {
    let c = resolved()
    let a = UInt32(min(max((c.a * 255).rounded(), 0), 255))
    let r = UInt32(min(max((c.r * 255).rounded(), 0), 255))
    let g = UInt32(min(max((c.g * 255).rounded(), 0), 255))
    let b = UInt32(min(max((c.b * 255).rounded(), 0), 255))
    return (a << 24) | (r << 16) | (g << 8) | b
  }

  public func set() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    let argb = packedARGB
    ctx.fillARGB = argb
    ctx.strokeARGB = argb
  }

  public func setFill() {
    _OffscreenDrawingContext.current?.fillARGB = packedARGB
  }

  public func setStroke() {
    _OffscreenDrawingContext.current?.strokeARGB = packedARGB
  }

  #if !os(macOS)
    public convenience init?(cgColor: CGColor) {
      self.init(srgbRed: cgColor.red, green: cgColor.green, blue: cgColor.blue, alpha: cgColor.alpha)
    }

    public var cgColor: CGColor {
      let c = resolved()
      return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
  #endif

  public static let clear = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
  public static let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
  public static let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
  public static let gray = NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
  public static let darkGray = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.33, alpha: 1)
  public static let lightGray = NSColor(srgbRed: 0.67, green: 0.67, blue: 0.67, alpha: 1)
  public static let red = NSColor(srgbRed: 1.0, green: 0.231, blue: 0.188, alpha: 1)
  public static let green = NSColor(srgbRed: 0.196, green: 0.843, blue: 0.294, alpha: 1)
  public static let blue = NSColor(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 1)
  public static let orange = NSColor(srgbRed: 1.0, green: 0.584, blue: 0.0, alpha: 1)
  public static let yellow = NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: 1)
  public static let cyan = NSColor(srgbRed: 0.353, green: 0.784, blue: 0.980, alpha: 1)
  public static let magenta = NSColor(srgbRed: 1.0, green: 0.176, blue: 0.333, alpha: 1)
  public static let purple = NSColor(srgbRed: 0.749, green: 0.353, blue: 0.949, alpha: 1)
  public static let brown = NSColor(srgbRed: 0.635, green: 0.518, blue: 0.369, alpha: 1)

  public static let systemRed = red
  public static let systemGreen = green
  public static let systemBlue = blue
  public static let systemOrange = orange
  public static let systemYellow = yellow
  public static let systemPink = NSColor(srgbRed: 1.0, green: 0.216, blue: 0.373, alpha: 1)
  public static let systemPurple = purple
  public static let systemTeal = NSColor(srgbRed: 0.251, green: 0.784, blue: 0.878, alpha: 1)
  public static let systemIndigo = NSColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1)
  public static let systemMint = NSColor(srgbRed: 0.388, green: 0.902, blue: 0.886, alpha: 1)
  public static let systemCyan = cyan
  public static let systemBrown = brown
  public static let systemGray = gray

  public static let controlAccentColor = systemBlue
  public static let linkColor = systemBlue

  public static let labelColor = NSColor(name: "labelColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
  }

  public static let secondaryLabelColor = NSColor(name: "secondaryLabelColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.50)
  }

  public static let tertiaryLabelColor = NSColor(name: "tertiaryLabelColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25)
  }

  public static let quaternaryLabelColor = NSColor(name: "quaternaryLabelColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
  }

  public static let windowBackgroundColor = NSColor(name: "windowBackgroundColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.125, alpha: 1)
      : NSColor(srgbRed: 0.965, green: 0.965, blue: 0.969, alpha: 1)
  }

  public static let textBackgroundColor = windowBackgroundColor
  public static let controlBackgroundColor = NSColor(name: "controlBackgroundColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
      : NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
  }

  public static let separatorColor = NSColor(name: "separatorColor") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
  }

  public static let selectedContentBackgroundColor = systemBlue
  public static let findHighlightColor = systemYellow
  public static let tertiarySystemFill = NSColor(name: "tertiarySystemFill") {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05)
  }
  public static let disabledControlTextColor = tertiaryLabelColor
  public static let textColor = labelColor
  public static let unemphasizedSelectedContentBackgroundColor = NSColor(name: nil) {
    $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
      : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
  }

  public func drawSwatch(in rect: NSRect) {
    setFill()
    NSBezierPath(rect: rect).fill()
  }
}
