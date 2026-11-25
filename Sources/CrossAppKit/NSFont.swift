import Foundation
#if os(Windows)
  import CAppKitWindows
#endif

open class NSFontDescriptor: NSObject, NSSecureCoding, @unchecked Sendable {
  public static var supportsSecureCoding: Bool { true }

  public required convenience init?(coder: NSCoder) {
    let family = (coder.decodeObject(forKey: "familyName") as? String) ?? "Segoe UI"
    let size = CGFloat(coder.decodeDouble(forKey: "pointSize"))
    self.init(familyName: family, pointSize: size > 0 ? size : 13)
  }

  open func encode(with coder: NSCoder) {
    coder.encode(familyName as NSString, forKey: "familyName")
    coder.encode(Double(pointSize), forKey: "pointSize")
  }

  public struct SystemDesign: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let `default` = SystemDesign(rawValue: "default")
    public static let serif = SystemDesign(rawValue: "serif")
    public static let monospaced = SystemDesign(rawValue: "monospaced")
    public static let rounded = SystemDesign(rawValue: "rounded")
  }

  public struct SymbolicTraits: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let italic = SymbolicTraits(rawValue: 1 << 0)
    public static let bold = SymbolicTraits(rawValue: 1 << 1)
    public static let monoSpace = SymbolicTraits(rawValue: 1 << 10)
  }

  public let familyName: String
  public let pointSize: CGFloat
  public let weight: NSFont.Weight
  public let design: SystemDesign
  public let symbolicTraits: SymbolicTraits

  public init(
    familyName: String = "Segoe UI",
    pointSize: CGFloat = 13,
    weight: NSFont.Weight = .regular,
    design: SystemDesign = .default,
    symbolicTraits: SymbolicTraits = []
  ) {
    self.familyName = familyName
    self.pointSize = pointSize
    self.weight = weight
    self.design = design
    self.symbolicTraits = symbolicTraits
    super.init()
  }

  public func withDesign(_ design: SystemDesign) -> NSFontDescriptor? {
    let family = design == .monospaced ? NSFont.monospacedFamilyName : familyName
    var traits = symbolicTraits
    if design == .monospaced { traits.insert(.monoSpace) }
    return NSFontDescriptor(
      familyName: family, pointSize: pointSize, weight: weight, design: design, symbolicTraits: traits
    )
  }

  public func withSymbolicTraits(_ traits: SymbolicTraits) -> NSFontDescriptor {
    let w: NSFont.Weight = traits.contains(.bold) ? .bold : weight
    return NSFontDescriptor(
      familyName: familyName, pointSize: pointSize, weight: w, design: design, symbolicTraits: traits
    )
  }

  public func addingAttributes(_ attributes: [String: Any]) -> NSFontDescriptor {
    self
  }
}

open class NSFont: NSObject, @unchecked Sendable {
  public struct Weight: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: CGFloat
    public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
    public init(rawValue: CGFloat) { self.rawValue = rawValue }
    public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let ultraLight = Weight(-0.8)
    public static let thin = Weight(-0.6)
    public static let light = Weight(-0.4)
    public static let regular = Weight(0.0)
    public static let medium = Weight(0.23)
    public static let semibold = Weight(0.3)
    public static let bold = Weight(0.4)
    public static let heavy = Weight(0.56)
    public static let black = Weight(0.62)

    public var cssWeight: Double {
      switch rawValue {
      case ..<(-0.7): return 100
      case ..<(-0.5): return 200
      case ..<(-0.2): return 300
      case ..<0.15: return 400
      case ..<0.27: return 500
      case ..<0.35: return 600
      case ..<0.50: return 700
      case ..<0.60: return 800
      default: return 900
      }
    }
  }

  public struct TextStyle: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let largeTitle = TextStyle(rawValue: "UICTFontTextStyleTitle0")
    public static let title1 = TextStyle(rawValue: "UICTFontTextStyleTitle1")
    public static let title2 = TextStyle(rawValue: "UICTFontTextStyleTitle2")
    public static let title3 = TextStyle(rawValue: "UICTFontTextStyleTitle3")
    public static let headline = TextStyle(rawValue: "UICTFontTextStyleHeadline")
    public static let subheadline = TextStyle(rawValue: "UICTFontTextStyleSubhead")
    public static let body = TextStyle(rawValue: "UICTFontTextStyleBody")
    public static let callout = TextStyle(rawValue: "UICTFontTextStyleCallout")
    public static let footnote = TextStyle(rawValue: "UICTFontTextStyleFootnote")
    public static let caption1 = TextStyle(rawValue: "UICTFontTextStyleCaption1")
    public static let caption2 = TextStyle(rawValue: "UICTFontTextStyleCaption2")

    public var metrics: (size: CGFloat, weight: Weight) {
      switch self {
      case .largeTitle: return (26, .regular)
      case .title1: return (22, .regular)
      case .title2: return (17, .regular)
      case .title3: return (15, .regular)
      case .headline: return (13, .bold)
      case .body: return (13, .regular)
      case .callout: return (12, .regular)
      case .subheadline: return (11, .regular)
      case .footnote: return (10, .regular)
      case .caption1: return (10, .regular)
      case .caption2: return (10, .medium)
      default: return (13, .regular)
      }
    }
  }

  #if os(Windows)
    public static let defaultFamilyName = "Segoe UI"
    public static let monospacedFamilyName = "Cascadia Mono"
  #else
    public static let defaultFamilyName = "Sans"
    public static let monospacedFamilyName = "Monospace"
  #endif

  public let fontDescriptor: NSFontDescriptor
  public var pointSize: CGFloat { fontDescriptor.pointSize }
  public var fontName: String { fontDescriptor.familyName }
  public var familyName: String? { fontDescriptor.familyName }
  public var isFixedPitch: Bool {
    fontDescriptor.design == .monospaced || fontDescriptor.symbolicTraits.contains(.monoSpace)
  }

  public init?(descriptor: NSFontDescriptor, size: CGFloat) {
    let resolvedSize = size > 0 ? size : descriptor.pointSize
    self.fontDescriptor = NSFontDescriptor(
      familyName: descriptor.familyName,
      pointSize: resolvedSize,
      weight: descriptor.weight,
      design: descriptor.design,
      symbolicTraits: descriptor.symbolicTraits
    )
    super.init()
  }

  public convenience init?(name fontName: String, size fontSize: CGFloat) {
    let sz = fontSize > 0 ? fontSize : NSFont.systemFontSize
    self.init(descriptor: NSFontDescriptor(familyName: fontName, pointSize: sz), size: sz)
  }

  public static var systemFontSize: CGFloat { 13 }
  public static var smallSystemFontSize: CGFloat { 11 }
  public static var labelFontSize: CGFloat { 10 }

  public static func systemFontSize(for controlSize: NSControl.ControlSize) -> CGFloat {
    switch controlSize {
    case .regular: return 13
    case .small: return 11
    case .mini: return 9
    case .large: return 15
    }
  }

  public static func systemFont(ofSize fontSize: CGFloat, weight: Weight = .regular) -> NSFont {
    let sz = fontSize > 0 ? fontSize : systemFontSize
    var traits: NSFontDescriptor.SymbolicTraits = []
    if weight >= .semibold { traits.insert(.bold) }
    let desc = NSFontDescriptor(
      familyName: defaultFamilyName, pointSize: sz, weight: weight, design: .default, symbolicTraits: traits
    )
    return NSFont(descriptor: desc, size: sz)!
  }

  public static func boldSystemFont(ofSize fontSize: CGFloat) -> NSFont {
    systemFont(ofSize: fontSize, weight: .bold)
  }

  public static func userFixedPitchFont(ofSize fontSize: CGFloat) -> NSFont {
    monospacedSystemFont(ofSize: fontSize, weight: .regular)
  }

  public static func menuFont(ofSize fontSize: CGFloat) -> NSFont {
    systemFont(ofSize: fontSize > 0 ? fontSize : systemFontSize, weight: .regular)
  }

  public static func menuBarFont(ofSize fontSize: CGFloat) -> NSFont {
    systemFont(ofSize: fontSize > 0 ? fontSize : systemFontSize, weight: .regular)
  }

  public static func toolTipsFont(ofSize fontSize: CGFloat) -> NSFont {
    systemFont(ofSize: fontSize > 0 ? fontSize : smallSystemFontSize, weight: .regular)
  }

  public static func monospacedSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> NSFont {
    let sz = fontSize > 0 ? fontSize : systemFontSize
    var traits: NSFontDescriptor.SymbolicTraits = [.monoSpace]
    if weight >= .semibold { traits.insert(.bold) }
    let desc = NSFontDescriptor(
      familyName: monospacedFamilyName, pointSize: sz, weight: weight, design: .monospaced, symbolicTraits: traits
    )
    return NSFont(descriptor: desc, size: sz)!
  }

  public static func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> NSFont {
    systemFont(ofSize: fontSize, weight: weight)
  }

  public static func preferredFont(forTextStyle style: TextStyle, options: [String: Any] = [:]) -> NSFont {
    let m = style.metrics
    return systemFont(ofSize: m.size, weight: m.weight)
  }

  private var computedMetrics: (ascender: CGFloat, descender: CGFloat, cap: CGFloat, x: CGFloat, leading: CGFloat) {
    #if os(Windows)
      var asc = 0.0, desc = 0.0, cap = 0.0, xh = 0.0, lead = 0.0
      cak_font_metrics(
        fontDescriptor.familyName,
        Double(pointSize),
        fontDescriptor.weight.cssWeight,
        &asc, &desc, &cap, &xh, &lead
      )
      return (CGFloat(asc), CGFloat(desc), CGFloat(cap), CGFloat(xh), CGFloat(lead))
    #else
      return (pointSize * 0.85, -pointSize * 0.20, pointSize * 0.70, pointSize * 0.50, pointSize * 0.15)
    #endif
  }

  public var ascender: CGFloat { computedMetrics.ascender }
  public var descender: CGFloat { computedMetrics.descender }
  public var capHeight: CGFloat { computedMetrics.cap }
  public var xHeight: CGFloat { computedMetrics.x }
  public var leading: CGFloat { computedMetrics.leading }
  public var boundingRectForFont: NSRect {
    let m = computedMetrics
    return NSRect(x: 0, y: m.descender, width: pointSize, height: m.ascender - m.descender)
  }
}

public struct NSFontTraitMask: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let italicFontMask = NSFontTraitMask(rawValue: 1)
  public static let boldFontMask = NSFontTraitMask(rawValue: 2)
  public static let fixedPitchFontMask = NSFontTraitMask(rawValue: 0x400)
}

open class NSFontManager: NSObject, @unchecked Sendable {
  public static let shared = NSFontManager()

  public func convert(_ fontObj: NSFont, toHaveTrait trait: NSFontTraitMask) -> NSFont {
    var traits = fontObj.fontDescriptor.symbolicTraits
    if trait.contains(.italicFontMask) { traits.insert(.italic) }
    if trait.contains(.boldFontMask) { traits.insert(.bold) }
    if trait.contains(.fixedPitchFontMask) { traits.insert(.monoSpace) }
    let desc = fontObj.fontDescriptor.withSymbolicTraits(traits)
    return NSFont(descriptor: desc, size: fontObj.pointSize) ?? fontObj
  }
}
