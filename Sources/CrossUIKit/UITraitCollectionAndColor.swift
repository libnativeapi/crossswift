import CrossAppKit
import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

internal func _crossUIKitThreadKey() -> UInt64 {
  #if os(Windows)
    return UInt64(cak_current_thread_id())
  #else
    return UInt64(UInt(bitPattern: ObjectIdentifier(Thread.current)))
  #endif
}

// MARK: - UITraitCollection & Trait Environment

public protocol UIMutableTraits: AnyObject {
  var userInterfaceStyle: UIUserInterfaceStyle { get set }
  var userInterfaceIdiom: UIUserInterfaceIdiom { get set }
  var horizontalSizeClass: UIUserInterfaceSizeClass { get set }
  var verticalSizeClass: UIUserInterfaceSizeClass { get set }
  var displayScale: CGFloat { get set }
  var layoutDirection: UIUserInterfaceLayoutDirection { get set }
  var preferredContentSizeCategory: UIContentSizeCategory { get set }
  var accessibilityContrast: UIAccessibilityContrast { get set }
  var legibilityWeight: UILegibilityWeight { get set }
  var userInterfaceLevel: UIUserInterfaceLevel { get set }
  var activeAppearance: UIUserInterfaceActiveAppearance { get set }
  var displayGamut: UIDisplayGamut { get set }
}

private final class _MutableTraitsBox: UIMutableTraits {
  var userInterfaceStyle: UIUserInterfaceStyle
  var userInterfaceIdiom: UIUserInterfaceIdiom
  var horizontalSizeClass: UIUserInterfaceSizeClass
  var verticalSizeClass: UIUserInterfaceSizeClass
  var displayScale: CGFloat
  var layoutDirection: UIUserInterfaceLayoutDirection
  var preferredContentSizeCategory: UIContentSizeCategory
  var accessibilityContrast: UIAccessibilityContrast
  var legibilityWeight: UILegibilityWeight
  var userInterfaceLevel: UIUserInterfaceLevel
  var activeAppearance: UIUserInterfaceActiveAppearance
  var displayGamut: UIDisplayGamut

  init(from base: UITraitCollection) {
    self.userInterfaceStyle = base.userInterfaceStyle
    self.userInterfaceIdiom = base.userInterfaceIdiom
    self.horizontalSizeClass = base.horizontalSizeClass
    self.verticalSizeClass = base.verticalSizeClass
    self.displayScale = base.displayScale
    self.layoutDirection = base.layoutDirection
    self.preferredContentSizeCategory = base.preferredContentSizeCategory
    self.accessibilityContrast = base.accessibilityContrast
    self.legibilityWeight = base.legibilityWeight
    self.userInterfaceLevel = base.userInterfaceLevel
    self.activeAppearance = base.activeAppearance
    self.displayGamut = base.displayGamut
  }
}

open class UITraitCollection: NSObject, NSCopying, @unchecked Sendable {
  public let userInterfaceStyle: UIUserInterfaceStyle
  public let userInterfaceIdiom: UIUserInterfaceIdiom
  public let horizontalSizeClass: UIUserInterfaceSizeClass
  public let verticalSizeClass: UIUserInterfaceSizeClass
  public let displayScale: CGFloat
  public let layoutDirection: UIUserInterfaceLayoutDirection
  public let preferredContentSizeCategory: UIContentSizeCategory
  public let accessibilityContrast: UIAccessibilityContrast
  public let legibilityWeight: UILegibilityWeight
  public let userInterfaceLevel: UIUserInterfaceLevel
  public let activeAppearance: UIUserInterfaceActiveAppearance
  public let displayGamut: UIDisplayGamut

  private static let threadLock = NSLock()
  nonisolated(unsafe) private static var threadTraits: [UInt64: UITraitCollection] = [:]
  nonisolated(unsafe) internal static var _appStyleOverride: UIUserInterfaceStyle = .unspecified

  public static var systemTraitCollection: UITraitCollection {
    let style: UIUserInterfaceStyle
    if _appStyleOverride != .unspecified {
      style = _appStyleOverride
    } else {
      #if !os(macOS)
        let brightness = NativeAPI.Application.shared.getSystemBrightness()
        style = brightness == .dark ? .dark : .light
      #else
        style = .light
      #endif
    }
    return UITraitCollection(
      userInterfaceStyle: style,
      userInterfaceIdiom: .pad,
      horizontalSizeClass: .regular,
      verticalSizeClass: .regular,
      displayScale: 2.0,
      layoutDirection: .leftToRight,
      preferredContentSizeCategory: .large,
      accessibilityContrast: .normal,
      legibilityWeight: .regular,
      userInterfaceLevel: .base,
      activeAppearance: .active,
      displayGamut: .P3
    )
  }

  public static var current: UITraitCollection {
    get {
      let tid = _crossUIKitThreadKey()
      threadLock.lock()
      let found = threadTraits[tid]
      threadLock.unlock()
      return found ?? systemTraitCollection
    }
    set {
      let tid = _crossUIKitThreadKey()
      threadLock.lock()
      threadTraits[tid] = newValue
      threadLock.unlock()
    }
  }

  public init(
    userInterfaceStyle: UIUserInterfaceStyle = .unspecified,
    userInterfaceIdiom: UIUserInterfaceIdiom = .unspecified,
    horizontalSizeClass: UIUserInterfaceSizeClass = .unspecified,
    verticalSizeClass: UIUserInterfaceSizeClass = .unspecified,
    displayScale: CGFloat = 0,
    layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight,
    preferredContentSizeCategory: UIContentSizeCategory = .unspecified,
    accessibilityContrast: UIAccessibilityContrast = .unspecified,
    legibilityWeight: UILegibilityWeight = .unspecified,
    userInterfaceLevel: UIUserInterfaceLevel = .unspecified,
    activeAppearance: UIUserInterfaceActiveAppearance = .unspecified,
    displayGamut: UIDisplayGamut = .unspecified
  ) {
    self.userInterfaceStyle = userInterfaceStyle
    self.userInterfaceIdiom = userInterfaceIdiom
    self.horizontalSizeClass = horizontalSizeClass
    self.verticalSizeClass = verticalSizeClass
    self.displayScale = displayScale
    self.layoutDirection = layoutDirection
    self.preferredContentSizeCategory = preferredContentSizeCategory
    self.accessibilityContrast = accessibilityContrast
    self.legibilityWeight = legibilityWeight
    self.userInterfaceLevel = userInterfaceLevel
    self.activeAppearance = activeAppearance
    self.displayGamut = displayGamut
    super.init()
  }

  public override convenience init() {
    self.init(userInterfaceStyle: .unspecified)
  }

  public convenience init(userInterfaceStyle style: UIUserInterfaceStyle) {
    self.init(userInterfaceStyle: style, userInterfaceIdiom: .unspecified)
  }

  public convenience init(userInterfaceIdiom idiom: UIUserInterfaceIdiom) {
    self.init(userInterfaceStyle: .unspecified, userInterfaceIdiom: idiom)
  }

  public convenience init(horizontalSizeClass sizeClass: UIUserInterfaceSizeClass) {
    self.init(userInterfaceStyle: .unspecified, horizontalSizeClass: sizeClass)
  }

  public convenience init(verticalSizeClass sizeClass: UIUserInterfaceSizeClass) {
    self.init(userInterfaceStyle: .unspecified, verticalSizeClass: sizeClass)
  }

  public convenience init(displayScale scale: CGFloat) {
    self.init(userInterfaceStyle: .unspecified, displayScale: scale)
  }

  public convenience init(preferredContentSizeCategory category: UIContentSizeCategory) {
    self.init(userInterfaceStyle: .unspecified, preferredContentSizeCategory: category)
  }

  public convenience init(userInterfaceLevel level: UIUserInterfaceLevel) {
    self.init(userInterfaceStyle: .unspecified, userInterfaceLevel: level)
  }

  public convenience init(legibilityWeight weight: UILegibilityWeight) {
    self.init(userInterfaceStyle: .unspecified, legibilityWeight: weight)
  }

  public convenience init(accessibilityContrast contrast: UIAccessibilityContrast) {
    self.init(userInterfaceStyle: .unspecified, accessibilityContrast: contrast)
  }

  public convenience init(traitsFrom collections: [UITraitCollection]) {
    var style: UIUserInterfaceStyle = .unspecified
    var idiom: UIUserInterfaceIdiom = .unspecified
    var hSize: UIUserInterfaceSizeClass = .unspecified
    var vSize: UIUserInterfaceSizeClass = .unspecified
    var scale: CGFloat = 0
    var dir: UIUserInterfaceLayoutDirection = .leftToRight
    var category: UIContentSizeCategory = .unspecified
    var contrast: UIAccessibilityContrast = .unspecified
    var legibility: UILegibilityWeight = .unspecified
    var level: UIUserInterfaceLevel = .unspecified
    var active: UIUserInterfaceActiveAppearance = .unspecified
    var gamut: UIDisplayGamut = .unspecified

    for c in collections {
      if c.userInterfaceStyle != .unspecified { style = c.userInterfaceStyle }
      if c.userInterfaceIdiom != .unspecified { idiom = c.userInterfaceIdiom }
      if c.horizontalSizeClass != .unspecified { hSize = c.horizontalSizeClass }
      if c.verticalSizeClass != .unspecified { vSize = c.verticalSizeClass }
      if c.displayScale > 0 { scale = c.displayScale }
      dir = c.layoutDirection
      if c.preferredContentSizeCategory != .unspecified { category = c.preferredContentSizeCategory }
      if c.accessibilityContrast != .unspecified { contrast = c.accessibilityContrast }
      if c.legibilityWeight != .unspecified { legibility = c.legibilityWeight }
      if c.userInterfaceLevel != .unspecified { level = c.userInterfaceLevel }
      if c.activeAppearance != .unspecified { active = c.activeAppearance }
      if c.displayGamut != .unspecified { gamut = c.displayGamut }
    }

    self.init(
      userInterfaceStyle: style,
      userInterfaceIdiom: idiom,
      horizontalSizeClass: hSize,
      verticalSizeClass: vSize,
      displayScale: scale,
      layoutDirection: dir,
      preferredContentSizeCategory: category,
      accessibilityContrast: contrast,
      legibilityWeight: legibility,
      userInterfaceLevel: level,
      activeAppearance: active,
      displayGamut: gamut
    )
  }

  public convenience init(mutations: (any UIMutableTraits) -> Void) {
    let base = UITraitCollection()
    let box = _MutableTraitsBox(from: base)
    mutations(box)
    self.init(
      userInterfaceStyle: box.userInterfaceStyle,
      userInterfaceIdiom: box.userInterfaceIdiom,
      horizontalSizeClass: box.horizontalSizeClass,
      verticalSizeClass: box.verticalSizeClass,
      displayScale: box.displayScale,
      layoutDirection: box.layoutDirection,
      preferredContentSizeCategory: box.preferredContentSizeCategory,
      accessibilityContrast: box.accessibilityContrast,
      legibilityWeight: box.legibilityWeight,
      userInterfaceLevel: box.userInterfaceLevel,
      activeAppearance: box.activeAppearance,
      displayGamut: box.displayGamut
    )
  }

  public func modifyingTraits(_ mutations: (any UIMutableTraits) -> Void) -> UITraitCollection {
    let box = _MutableTraitsBox(from: self)
    mutations(box)
    return UITraitCollection(
      userInterfaceStyle: box.userInterfaceStyle,
      userInterfaceIdiom: box.userInterfaceIdiom,
      horizontalSizeClass: box.horizontalSizeClass,
      verticalSizeClass: box.verticalSizeClass,
      displayScale: box.displayScale,
      layoutDirection: box.layoutDirection,
      preferredContentSizeCategory: box.preferredContentSizeCategory,
      accessibilityContrast: box.accessibilityContrast,
      legibilityWeight: box.legibilityWeight,
      userInterfaceLevel: box.userInterfaceLevel,
      activeAppearance: box.activeAppearance,
      displayGamut: box.displayGamut
    )
  }

  public func performAsCurrent(_ actions: () -> Void) {
    let tid = _crossUIKitThreadKey()
    Self.threadLock.lock()
    let previous = Self.threadTraits[tid]
    Self.threadTraits[tid] = self
    Self.threadLock.unlock()
    defer {
      Self.threadLock.lock()
      if let previous {
        Self.threadTraits[tid] = previous
      } else {
        Self.threadTraits.removeValue(forKey: tid)
      }
      Self.threadLock.unlock()
    }
    actions()
  }

  public func hasDifferentColorAppearance(comparedTo traitCollection: UITraitCollection?) -> Bool {
    guard let other = traitCollection else { return true }
    return userInterfaceStyle != other.userInterfaceStyle
      || accessibilityContrast != other.accessibilityContrast
      || userInterfaceLevel != other.userInterfaceLevel
  }

  open func copy(with zone: NSZone? = nil) -> Any {
    self
  }

  open override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? UITraitCollection else { return false }
    return userInterfaceStyle == other.userInterfaceStyle
      && userInterfaceIdiom == other.userInterfaceIdiom
      && horizontalSizeClass == other.horizontalSizeClass
      && verticalSizeClass == other.verticalSizeClass
      && abs(displayScale - other.displayScale) < 1e-4
      && layoutDirection == other.layoutDirection
      && preferredContentSizeCategory == other.preferredContentSizeCategory
      && accessibilityContrast == other.accessibilityContrast
      && legibilityWeight == other.legibilityWeight
      && userInterfaceLevel == other.userInterfaceLevel
  }
}

@MainActor
public protocol UITraitEnvironment: NSObjectProtocol {
  var traitCollection: UITraitCollection { get }
  func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)
}

public protocol UITraitChangeRegistration: Hashable, Sendable {}

internal struct _TraitRegistrationToken: UITraitChangeRegistration {
  let id = UUID()
}

// MARK: - UIColor

open class UIColor: NSObject, NSCopying, _CrossPackedColorProviding, @unchecked Sendable {
  private let dynamicProvider: (@Sendable (UITraitCollection) -> UIColor)?
  private let fixedRed: CGFloat
  private let fixedGreen: CGFloat
  private let fixedBlue: CGFloat
  private let fixedAlpha: CGFloat

  public var isDynamic: Bool { dynamicProvider != nil }

  public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.dynamicProvider = nil
    self.fixedRed = min(max(red, 0), 1)
    self.fixedGreen = min(max(green, 0), 1)
    self.fixedBlue = min(max(blue, 0), 1)
    self.fixedAlpha = min(max(alpha, 0), 1)
    super.init()
  }

  public convenience init(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  public convenience init(white: CGFloat, alpha: CGFloat) {
    self.init(red: white, green: white, blue: white, alpha: alpha)
  }

  public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
    let h = (hue.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0) * 6.0
    let s = min(max(saturation, 0), 1)
    let v = min(max(brightness, 0), 1)
    let c = v * s
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1))
    let m = v - c
    let (r1, g1, b1): (CGFloat, CGFloat, CGFloat)
    switch Int(floor(h)) % 6 {
    case 0: (r1, g1, b1) = (c, x, 0)
    case 1: (r1, g1, b1) = (x, c, 0)
    case 2: (r1, g1, b1) = (0, c, x)
    case 3: (r1, g1, b1) = (0, x, c)
    case 4: (r1, g1, b1) = (x, 0, c)
    default: (r1, g1, b1) = (c, 0, x)
    }
    self.init(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: alpha)
  }

  public init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) {
    nonisolated(unsafe) let box = dynamicProvider
    self.dynamicProvider = { box($0) }
    self.fixedRed = 0
    self.fixedGreen = 0
    self.fixedBlue = 0
    self.fixedAlpha = 1
    super.init()
  }

  public convenience init(patternImage image: UIImage) {
    self.init(white: 0.5, alpha: 1.0)
  }

  public convenience init?(
    named name: String,
    in bundle: Bundle? = nil,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) {
    guard let parsed = Self.resolveColorSet(named: name, in: bundle) else {
      return nil
    }
    if let explicitTraits = traitCollection, explicitTraits.userInterfaceStyle != .unspecified {
      let c = explicitTraits.userInterfaceStyle == .dark ? parsed.dark : parsed.light
      self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    } else {
      self.init { traits in
        let isDark = traits.userInterfaceStyle == .dark
        let c = isDark ? parsed.dark : parsed.light
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
      }
    }
  }

  #if !os(macOS)
    public convenience init(cgColor: CGColor) {
      self.init(red: cgColor.red, green: cgColor.green, blue: cgColor.blue, alpha: cgColor.alpha)
    }

    public var cgColor: CGColor {
      let c = resolved()
      return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
  #endif

  open func copy(with zone: NSZone? = nil) -> Any { self }

  public func resolved(for traitCollection: UITraitCollection? = nil) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    if let provider = dynamicProvider {
      let base = traitCollection ?? UITraitCollection.current
      let effective: UITraitCollection
      if base.userInterfaceStyle == .unspecified {
        let sysStyle = UITraitCollection.systemTraitCollection.userInterfaceStyle
        effective = base.modifyingTraits { $0.userInterfaceStyle = sysStyle == .dark ? .dark : .light }
      } else {
        effective = base
      }
      return provider(effective).resolved(for: effective)
    }
    return (fixedRed, fixedGreen, fixedBlue, fixedAlpha)
  }

  public func resolvedColor(with traitCollection: UITraitCollection) -> UIColor {
    let c = resolved(for: traitCollection)
    return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
  }

  public func withAlphaComponent(_ alpha: CGFloat) -> UIColor {
    let clamped = min(max(alpha, 0), 1)
    if let provider = dynamicProvider {
      return UIColor { traits in
        provider(traits).withAlphaComponent(clamped)
      }
    }
    return UIColor(red: fixedRed, green: fixedGreen, blue: fixedBlue, alpha: clamped)
  }

  @discardableResult
  public func getRed(
    _ red: UnsafeMutablePointer<CGFloat>?,
    green: UnsafeMutablePointer<CGFloat>?,
    blue: UnsafeMutablePointer<CGFloat>?,
    alpha: UnsafeMutablePointer<CGFloat>?
  ) -> Bool {
    let c = resolved()
    red?.pointee = c.r
    green?.pointee = c.g
    blue?.pointee = c.b
    alpha?.pointee = c.a
    return true
  }

  @discardableResult
  public func getWhite(
    _ white: UnsafeMutablePointer<CGFloat>?,
    alpha: UnsafeMutablePointer<CGFloat>?
  ) -> Bool {
    let c = resolved()
    white?.pointee = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    alpha?.pointee = c.a
    return true
  }

  @discardableResult
  public func getHue(
    _ hue: UnsafeMutablePointer<CGFloat>?,
    saturation: UnsafeMutablePointer<CGFloat>?,
    brightness: UnsafeMutablePointer<CGFloat>?,
    alpha: UnsafeMutablePointer<CGFloat>?
  ) -> Bool {
    let c = resolved()
    let maxC = max(c.r, max(c.g, c.b))
    let minC = min(c.r, min(c.g, c.b))
    let delta = maxC - minC
    var h: CGFloat = 0
    if delta > 1e-6 {
      if maxC == c.r {
        h = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
      } else if maxC == c.g {
        h = ((c.b - c.r) / delta) + 2
      } else {
        h = ((c.r - c.g) / delta) + 4
      }
      h /= 6
      if h < 0 { h += 1 }
    }
    hue?.pointee = h
    saturation?.pointee = maxC > 0 ? (delta / maxC) : 0
    brightness?.pointee = maxC
    alpha?.pointee = c.a
    return true
  }

  public var _packedARGB: UInt32 {
    let c = resolved()
    let a = UInt32(min(max((c.a * 255).rounded(), 0), 255))
    let r = UInt32(min(max((c.r * 255).rounded(), 0), 255))
    let g = UInt32(min(max((c.g * 255).rounded(), 0), 255))
    let b = UInt32(min(max((c.b * 255).rounded(), 0), 255))
    return (a << 24) | (r << 16) | (g << 8) | b
  }

  public func set() {
    guard let ctx = _OffscreenDrawingContext.current else { return }
    let argb = _packedARGB
    ctx.fillARGB = argb
    ctx.strokeARGB = argb
  }

  public func setFill() {
    _OffscreenDrawingContext.current?.fillARGB = _packedARGB
  }

  public func setStroke() {
    _OffscreenDrawingContext.current?.strokeARGB = _packedARGB
  }

  // MARK: - Asset Catalog .colorset Lookup

  internal typealias RGBA = (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

  internal static func resolveColorSet(
    named name: String,
    in bundle: Bundle? = nil
  ) -> (light: RGBA, dark: RGBA)? {
    var roots: [String] = []
    func addRoot(_ path: String?) {
      guard let path, !path.isEmpty, !roots.contains(path) else { return }
      roots.append(path)
    }
    if let bundle {
      addRoot(bundle.resourcePath)
      addRoot(bundle.bundlePath)
    }
    for path in CrossAppKit.NSImage.resourceSearchPaths {
      addRoot(path)
    }
    addRoot(Bundle.main.resourcePath)
    addRoot(Bundle.main.bundlePath)

    let fm = FileManager.default
    for root in roots {
      let base = URL(fileURLWithPath: root)
      var candidates: [URL] = [
        base.appendingPathComponent("\(name).colorset"),
        base.appendingPathComponent("Assets.xcassets/\(name).colorset"),
        base.appendingPathComponent("Resources/Assets.xcassets/\(name).colorset"),
      ]
      for container in [base, base.appendingPathComponent("Resources")] {
        if let items = try? fm.contentsOfDirectory(atPath: container.path) {
          for item in items where item.lowercased().hasSuffix(".xcassets") {
            let candidate = container.appendingPathComponent(item).appendingPathComponent("\(name).colorset")
            if !candidates.contains(candidate) {
              candidates.append(candidate)
            }
          }
        }
      }
      for colorsetURL in candidates {
        let contentsURL = colorsetURL.appendingPathComponent("Contents.json")
        if fm.fileExists(atPath: contentsURL.path),
           let parsed = parseColorSetJSON(at: contentsURL)
        {
          return parsed
        }
      }
    }
    return nil
  }

  private static func parseColorSetJSON(at contentsURL: URL) -> (light: RGBA, dark: RGBA)? {
    guard let data = try? Data(contentsOf: contentsURL),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let entries = json["colors"] as? [[String: Any]]
    else { return nil }

    func parseComp(_ raw: Any?) -> CGFloat? {
      if let d = raw as? Double {
        return CGFloat(min(max(d > 1.0 ? d / 255.0 : d, 0), 1))
      }
      if let n = raw as? NSNumber {
        let d = n.doubleValue
        return CGFloat(min(max(d > 1.0 ? d / 255.0 : d, 0), 1))
      }
      if let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        let lower = s.lowercased()
        if lower.hasPrefix("0x"), let hex = UInt64(lower.dropFirst(2), radix: 16) {
          return CGFloat(min(max(Double(hex) / 255.0, 0), 1))
        }
        if s.contains("."), let d = Double(s) {
          return CGFloat(min(max(d, 0), 1))
        }
        if let d = Double(s) {
          return CGFloat(min(max(d > 1.0 ? d / 255.0 : d, 0), 1))
        }
      }
      return nil
    }

    var light: RGBA?
    var dark: RGBA?
    for entry in entries {
      guard let colorObj = entry["color"] as? [String: Any],
            let comps = colorObj["components"] as? [String: Any],
            let r = parseComp(comps["red"]),
            let g = parseComp(comps["green"]),
            let b = parseComp(comps["blue"])
      else { continue }
      let a = parseComp(comps["alpha"]) ?? 1.0
      let rgba: RGBA = (r, g, b, a)
      let appearances = entry["appearances"] as? [[String: Any]] ?? []
      let isDark = appearances.contains { ($0["value"] as? String)?.lowercased() == "dark" }
      if isDark {
        if dark == nil { dark = rgba }
      } else if light == nil {
        light = rgba
      }
    }
    guard let resolvedLight = light ?? dark else { return nil }
    return (resolvedLight, dark ?? resolvedLight)
  }

  // MARK: - Standard Fixed Colors

  public static let clear = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
  public static let black = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
  public static let white = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
  public static let darkGray = UIColor(white: 1.0 / 3.0, alpha: 1)
  public static let lightGray = UIColor(white: 2.0 / 3.0, alpha: 1)
  public static let gray = UIColor(white: 0.5, alpha: 1)
  public static let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
  public static let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
  public static let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
  public static let cyan = UIColor(red: 0, green: 1, blue: 1, alpha: 1)
  public static let yellow = UIColor(red: 1, green: 1, blue: 0, alpha: 1)
  public static let magenta = UIColor(red: 1, green: 0, blue: 1, alpha: 1)
  public static let orange = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)
  public static let purple = UIColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
  public static let brown = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)

  // MARK: - Adaptive iOS System Palette

  private static func adaptive(
    light: (CGFloat, CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat, CGFloat)
  ) -> UIColor {
    UIColor { traits in
      let c = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
    }
  }

  public static let systemRed = adaptive(light: (1.0, 0.231, 0.188, 1), dark: (1.0, 0.271, 0.227, 1))
  public static let systemGreen = adaptive(light: (0.204, 0.780, 0.349, 1), dark: (0.188, 0.820, 0.345, 1))
  public static let systemBlue = adaptive(light: (0.0, 0.478, 1.0, 1), dark: (0.039, 0.518, 1.0, 1))
  public static let systemOrange = adaptive(light: (1.0, 0.584, 0.0, 1), dark: (1.0, 0.624, 0.039, 1))
  public static let systemYellow = adaptive(light: (1.0, 0.800, 0.0, 1), dark: (1.0, 0.839, 0.039, 1))
  public static let systemPink = adaptive(light: (1.0, 0.176, 0.333, 1), dark: (1.0, 0.216, 0.373, 1))
  public static let systemPurple = adaptive(light: (0.686, 0.322, 0.871, 1), dark: (0.749, 0.353, 0.949, 1))
  public static let systemTeal = adaptive(light: (0.188, 0.690, 0.780, 1), dark: (0.251, 0.784, 0.878, 1))
  public static let systemIndigo = adaptive(light: (0.345, 0.337, 0.839, 1), dark: (0.369, 0.361, 0.902, 1))
  public static let systemBrown = adaptive(light: (0.635, 0.518, 0.369, 1), dark: (0.675, 0.557, 0.408, 1))
  public static let systemMint = adaptive(light: (0.0, 0.780, 0.745, 1), dark: (0.388, 0.902, 0.886, 1))
  public static let systemCyan = adaptive(light: (0.196, 0.678, 0.902, 1), dark: (0.392, 0.824, 1.0, 1))
  public static let tintColor = systemBlue

  public static let systemGray = adaptive(light: (0.557, 0.557, 0.576, 1), dark: (0.557, 0.557, 0.576, 1))
  public static let systemGray2 = adaptive(light: (0.682, 0.682, 0.698, 1), dark: (0.388, 0.388, 0.400, 1))
  public static let systemGray3 = adaptive(light: (0.780, 0.780, 0.800, 1), dark: (0.282, 0.282, 0.290, 1))
  public static let systemGray4 = adaptive(light: (0.820, 0.820, 0.839, 1), dark: (0.227, 0.227, 0.235, 1))
  public static let systemGray5 = adaptive(light: (0.898, 0.898, 0.918, 1), dark: (0.173, 0.173, 0.180, 1))
  public static let systemGray6 = adaptive(light: (0.949, 0.949, 0.969, 1), dark: (0.110, 0.110, 0.118, 1))

  // MARK: - Semantic UI Element Colors

  public static let label = adaptive(light: (0, 0, 0, 1), dark: (1, 1, 1, 1))
  public static let secondaryLabel = adaptive(light: (0.235, 0.235, 0.263, 0.6), dark: (0.922, 0.922, 0.961, 0.6))
  public static let tertiaryLabel = adaptive(light: (0.235, 0.235, 0.263, 0.3), dark: (0.922, 0.922, 0.961, 0.3))
  public static let quaternaryLabel = adaptive(light: (0.235, 0.235, 0.263, 0.18), dark: (0.922, 0.922, 0.961, 0.16))
  public static let link = adaptive(light: (0.0, 0.478, 1.0, 1), dark: (0.039, 0.518, 1.0, 1))
  public static let placeholderText = tertiaryLabel
  public static let separator = adaptive(light: (0.235, 0.235, 0.263, 0.29), dark: (0.329, 0.329, 0.345, 0.6))
  public static let opaqueSeparator = adaptive(light: (0.776, 0.776, 0.784, 1), dark: (0.220, 0.220, 0.227, 1))

  public static let systemBackground = adaptive(light: (1.0, 1.0, 1.0, 1), dark: (0.0, 0.0, 0.0, 1))
  public static let secondarySystemBackground = adaptive(light: (0.949, 0.949, 0.969, 1), dark: (0.110, 0.110, 0.118, 1))
  public static let tertiarySystemBackground = adaptive(light: (1.0, 1.0, 1.0, 1), dark: (0.173, 0.173, 0.180, 1))

  public static let systemGroupedBackground = adaptive(light: (0.949, 0.949, 0.969, 1), dark: (0.0, 0.0, 0.0, 1))
  public static let secondarySystemGroupedBackground = adaptive(light: (1.0, 1.0, 1.0, 1), dark: (0.110, 0.110, 0.118, 1))
  public static let tertiarySystemGroupedBackground = adaptive(light: (0.949, 0.949, 0.969, 1), dark: (0.173, 0.173, 0.180, 1))

  public static let systemFill = adaptive(light: (0.471, 0.471, 0.502, 0.20), dark: (0.471, 0.471, 0.502, 0.36))
  public static let secondarySystemFill = adaptive(light: (0.471, 0.471, 0.502, 0.16), dark: (0.471, 0.471, 0.502, 0.32))
  public static let tertiarySystemFill = adaptive(light: (0.463, 0.463, 0.502, 0.12), dark: (0.463, 0.463, 0.502, 0.24))
  public static let quaternarySystemFill = adaptive(light: (0.455, 0.455, 0.502, 0.08), dark: (0.455, 0.455, 0.502, 0.18))

  public static let lightText = UIColor(white: 1.0, alpha: 0.6)
  public static let darkText = UIColor(white: 0.0, alpha: 1.0)
}
