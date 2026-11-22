import CrossAppKit
import Foundation
#if os(Windows)
  import CAppKitWindows
#endif

open class UIFontDescriptor: NSObject, NSCopying, @unchecked Sendable {
  public struct SystemDesign: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let `default` = SystemDesign(rawValue: "default")
    public static let rounded = SystemDesign(rawValue: "rounded")
    public static let serif = SystemDesign(rawValue: "serif")
    public static let monospaced = SystemDesign(rawValue: "monospaced")
  }

  public struct SymbolicTraits: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let traitItalic = SymbolicTraits(rawValue: 1 << 0)
    public static let traitBold = SymbolicTraits(rawValue: 1 << 1)
    public static let traitExpanded = SymbolicTraits(rawValue: 1 << 5)
    public static let traitCondensed = SymbolicTraits(rawValue: 1 << 6)
    public static let traitMonoSpace = SymbolicTraits(rawValue: 1 << 10)
    public static let traitVertical = SymbolicTraits(rawValue: 1 << 11)
    public static let traitUIOptimized = SymbolicTraits(rawValue: 1 << 12)
    public static let traitTightLeading = SymbolicTraits(rawValue: 1 << 15)
    public static let traitLooseLeading = SymbolicTraits(rawValue: 1 << 16)
  }

  public struct AttributeName: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let family = AttributeName(rawValue: "NSFontFamilyAttribute")
    public static let name = AttributeName(rawValue: "NSFontNameAttribute")
    public static let face = AttributeName(rawValue: "NSFontFaceAttribute")
    public static let size = AttributeName(rawValue: "NSFontSizeAttribute")
    public static let visibleName = AttributeName(rawValue: "NSFontVisibleNameAttribute")
    public static let traits = AttributeName(rawValue: "NSFontTraitsAttribute")
    public static let featureSettings = AttributeName(rawValue: "NSFontFeatureSettingsAttribute")
  }

  public struct TraitKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let symbolic = TraitKey(rawValue: "NSCTFontSymbolicTrait")
    public static let weight = TraitKey(rawValue: "NSCTFontWeightTrait")
    public static let width = TraitKey(rawValue: "NSCTFontWidthTrait")
    public static let slant = TraitKey(rawValue: "NSCTFontSlantTrait")
  }

  public let familyName: String
  public let pointSize: CGFloat
  public let weight: UIFont.Weight
  public let design: SystemDesign
  public let symbolicTraits: SymbolicTraits
  public var postscriptName: String { familyName }

  public var fontAttributes: [AttributeName: Any] {
    [
      .family: familyName,
      .name: familyName,
      .size: pointSize,
      .traits: [
        TraitKey.symbolic: symbolicTraits.rawValue,
        TraitKey.weight: weight.rawValue,
      ],
    ]
  }

  public init(
    familyName: String = UIFont.defaultFamilyName,
    pointSize: CGFloat = 17,
    weight: UIFont.Weight = .regular,
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

  public convenience init(name fontName: String, size: CGFloat) {
    self.init(familyName: fontName, pointSize: size)
  }

  public convenience init(fontAttributes attributes: [AttributeName: Any] = [:]) {
    let family = (attributes[.family] as? String)
      ?? (attributes[.name] as? String)
      ?? UIFont.defaultFamilyName
    let size = (attributes[.size] as? CGFloat)
      ?? (attributes[.size] as? Double).map { CGFloat($0) }
      ?? 17
    var resolvedWeight: UIFont.Weight = .regular
    var resolvedTraits: SymbolicTraits = []
    if let traitsDict = attributes[.traits] as? [TraitKey: Any] {
      if let w = traitsDict[.weight] as? UIFont.Weight {
        resolvedWeight = w
      } else if let rawW = traitsDict[.weight] as? CGFloat {
        resolvedWeight = UIFont.Weight(rawValue: rawW)
      }
      if let rawS = traitsDict[.symbolic] as? UInt32 {
        resolvedTraits = SymbolicTraits(rawValue: rawS)
      }
    }
    self.init(familyName: family, pointSize: size, weight: resolvedWeight, symbolicTraits: resolvedTraits)
  }

  open func copy(with zone: NSZone? = nil) -> Any { self }

  public static func preferredFontDescriptor(
    withTextStyle style: UIFont.TextStyle,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) -> UIFontDescriptor {
    let base = style.metrics
    let scale = (traitCollection ?? UITraitCollection.current).preferredContentSizeCategory.scaleMultiplier
    let scaledSize = (base.size * scale).rounded()
    var traits: SymbolicTraits = []
    if base.weight >= .semibold { traits.insert(.traitBold) }
    return UIFontDescriptor(
      familyName: UIFont.defaultFamilyName,
      pointSize: scaledSize,
      weight: base.weight,
      design: .default,
      symbolicTraits: traits
    )
  }

  public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
    let family: String
    switch design {
    case .monospaced: family = UIFont.monospacedFamilyName
    case .serif: family = UIFont.serifFamilyName
    default: family = familyName
    }
    var traits = symbolicTraits
    if design == .monospaced { traits.insert(.traitMonoSpace) }
    return UIFontDescriptor(
      familyName: family, pointSize: pointSize, weight: weight, design: design, symbolicTraits: traits
    )
  }

  public func withSymbolicTraits(_ symbolicTraits: SymbolicTraits) -> UIFontDescriptor? {
    let w: UIFont.Weight = symbolicTraits.contains(.traitBold) ? max(weight, .bold) : weight
    return UIFontDescriptor(
      familyName: familyName, pointSize: pointSize, weight: w, design: design, symbolicTraits: symbolicTraits
    )
  }

  public func withSize(_ newPointSize: CGFloat) -> UIFontDescriptor {
    UIFontDescriptor(
      familyName: familyName, pointSize: newPointSize, weight: weight, design: design, symbolicTraits: symbolicTraits
    )
  }

  public func withFamily(_ family: String) -> UIFontDescriptor {
    UIFontDescriptor(
      familyName: family, pointSize: pointSize, weight: weight, design: design, symbolicTraits: symbolicTraits
    )
  }

  public func addingAttributes(_ attributes: [AttributeName: Any] = [:]) -> UIFontDescriptor {
    let newFamily = (attributes[.family] as? String) ?? (attributes[.name] as? String) ?? familyName
    let newSize = (attributes[.size] as? CGFloat) ?? pointSize
    var newWeight = weight
    var newTraits = symbolicTraits
    if let traitsDict = attributes[.traits] as? [TraitKey: Any] {
      if let w = traitsDict[.weight] as? UIFont.Weight { newWeight = w }
      else if let rawW = traitsDict[.weight] as? CGFloat { newWeight = UIFont.Weight(rawValue: rawW) }
      if let rawS = traitsDict[.symbolic] as? UInt32 { newTraits = SymbolicTraits(rawValue: rawS) }
    }
    return UIFontDescriptor(
      familyName: newFamily, pointSize: newSize, weight: newWeight, design: design, symbolicTraits: newTraits
    )
  }
}

open class UIFont: NSObject, NSCopying, _CrossFontPointSizeProviding, @unchecked Sendable {
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

  public struct TextStyle: RawRepresentable, Equatable, Hashable, CaseIterable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let extraLargeTitle = TextStyle(rawValue: "UICTFontTextStyleEmphasizedTitle0")
    public static let extraLargeTitle2 = TextStyle(rawValue: "UICTFontTextStyleTitle0_2")
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

    public static var allCases: [TextStyle] {
      [
        .extraLargeTitle, .extraLargeTitle2, .largeTitle,
        .title1, .title2, .title3,
        .headline, .body, .callout, .subheadline, .footnote,
        .caption1, .caption2,
      ]
    }

    public var metrics: (size: CGFloat, weight: Weight) {
      switch self {
      case .extraLargeTitle: return (36, .bold)
      case .extraLargeTitle2: return (28, .bold)
      case .largeTitle: return (34, .regular)
      case .title1: return (28, .regular)
      case .title2: return (22, .regular)
      case .title3: return (20, .regular)
      case .headline: return (17, .semibold)
      case .body: return (17, .regular)
      case .callout: return (16, .regular)
      case .subheadline: return (15, .regular)
      case .footnote: return (13, .regular)
      case .caption1: return (12, .regular)
      case .caption2: return (11, .regular)
      default: return (17, .regular)
      }
    }
  }

  #if os(Windows)
    public static let defaultFamilyName = "Segoe UI"
    public static let monospacedFamilyName = "Cascadia Mono"
    public static let serifFamilyName = "Georgia"
  #else
    public static let defaultFamilyName = "Sans"
    public static let monospacedFamilyName = "Monospace"
    public static let serifFamilyName = "Serif"
  #endif

  public static var labelFontSize: CGFloat { 17 }
  public static var buttonFontSize: CGFloat { 18 }
  public static var smallSystemFontSize: CGFloat { 12 }
  public static var systemFontSize: CGFloat { 14 }

  public static var familyNames: [String] {
    [defaultFamilyName, monospacedFamilyName, serifFamilyName]
  }

  public static func fontNames(forFamilyName familyName: String) -> [String] {
    [familyName]
  }

  public let fontDescriptor: UIFontDescriptor
  public var pointSize: CGFloat { fontDescriptor.pointSize }
  public var fontName: String { fontDescriptor.familyName }
  public var familyName: String { fontDescriptor.familyName }

  public init(descriptor: UIFontDescriptor, size pointSize: CGFloat) {
    let resolvedSize = pointSize > 0 ? pointSize : descriptor.pointSize
    self.fontDescriptor = descriptor.withSize(resolvedSize)
    super.init()
  }

  public convenience init?(name fontName: String, size fontSize: CGFloat) {
    guard !fontName.isEmpty else { return nil }
    let sz = fontSize > 0 ? fontSize : UIFont.systemFontSize
    self.init(descriptor: UIFontDescriptor(familyName: fontName, pointSize: sz), size: sz)
  }

  open func copy(with zone: NSZone? = nil) -> Any { self }

  public func withSize(_ fontSize: CGFloat) -> UIFont {
    UIFont(descriptor: fontDescriptor, size: fontSize)
  }

  public static func systemFont(ofSize fontSize: CGFloat, weight: Weight = .regular) -> UIFont {
    let sz = fontSize > 0 ? fontSize : systemFontSize
    var traits: UIFontDescriptor.SymbolicTraits = []
    if weight >= .semibold { traits.insert(.traitBold) }
    let desc = UIFontDescriptor(
      familyName: defaultFamilyName, pointSize: sz, weight: weight, design: .default, symbolicTraits: traits
    )
    return UIFont(descriptor: desc, size: sz)
  }

  public static func boldSystemFont(ofSize fontSize: CGFloat) -> UIFont {
    systemFont(ofSize: fontSize, weight: .bold)
  }

  public static func italicSystemFont(ofSize fontSize: CGFloat) -> UIFont {
    let sz = fontSize > 0 ? fontSize : systemFontSize
    let desc = UIFontDescriptor(
      familyName: defaultFamilyName, pointSize: sz, weight: .regular, design: .default, symbolicTraits: [.traitItalic]
    )
    return UIFont(descriptor: desc, size: sz)
  }

  public static func monospacedSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> UIFont {
    let sz = fontSize > 0 ? fontSize : systemFontSize
    var traits: UIFontDescriptor.SymbolicTraits = [.traitMonoSpace]
    if weight >= .semibold { traits.insert(.traitBold) }
    let desc = UIFontDescriptor(
      familyName: monospacedFamilyName, pointSize: sz, weight: weight, design: .monospaced, symbolicTraits: traits
    )
    return UIFont(descriptor: desc, size: sz)
  }

  public static func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> UIFont {
    systemFont(ofSize: fontSize, weight: weight)
  }

  public static func preferredFont(
    forTextStyle style: TextStyle,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) -> UIFont {
    let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traitCollection)
    return UIFont(descriptor: desc, size: desc.pointSize)
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
  public var lineHeight: CGFloat {
    let m = computedMetrics
    return ceil(m.ascender - m.descender + m.leading)
  }
}

open class UIFontMetrics: NSObject, @unchecked Sendable {
  public static let `default` = UIFontMetrics(forTextStyle: .body)

  public let textStyle: UIFont.TextStyle

  public init(forTextStyle textStyle: UIFont.TextStyle) {
    self.textStyle = textStyle
    super.init()
  }

  public func scaledFont(
    for font: UIFont,
    maximumPointSize: CGFloat = 0,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) -> UIFont {
    let scaled = scaledValue(for: font.pointSize, compatibleWith: traitCollection)
    let clamped = maximumPointSize > 0 ? min(scaled, maximumPointSize) : scaled
    return font.withSize(clamped.rounded())
  }

  public func scaledValue(
    for value: CGFloat,
    compatibleWith traitCollection: UITraitCollection? = nil
  ) -> CGFloat {
    let mult = (traitCollection ?? UITraitCollection.current).preferredContentSizeCategory.scaleMultiplier
    return value * mult
  }
}
