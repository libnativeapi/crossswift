import Foundation

// Lightweight pure-Swift AppKit font & attributed-string shims for WebAssembly (`os(WASI)`).

open class NSFontDescriptor: NSObject, @unchecked Sendable {
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
    familyName: String = NSFont.defaultFamilyName,
    pointSize: CGFloat = 14,
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
    let family: String
    switch design {
    case .monospaced: family = NSFont.monospacedFamilyName
    case .serif: family = NSFont.serifFamilyName
    default: family = familyName
    }
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
      case .headline: return (14, .bold)
      case .body: return (14, .regular)
      case .callout: return (13, .regular)
      case .subheadline: return (12, .regular)
      case .footnote: return (11, .regular)
      case .caption1: return (11, .regular)
      case .caption2: return (10, .medium)
      default: return (14, .regular)
      }
    }
  }

  public static let defaultFamilyName = "system-ui"
  public static let monospacedFamilyName = "ui-monospace"
  public static let serifFamilyName = "Georgia"

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

  public static var systemFontSize: CGFloat { 14 }
  public static var smallSystemFontSize: CGFloat { 12 }
  public static var labelFontSize: CGFloat { 11 }

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

  public var ascender: CGFloat { pointSize * 0.85 }
  public var descender: CGFloat { -pointSize * 0.20 }
  public var capHeight: CGFloat { pointSize * 0.70 }
  public var xHeight: CGFloat { pointSize * 0.50 }
  public var leading: CGFloat { pointSize * 0.15 }
}

extension NSAttributedString.Key {
  public static let font = NSAttributedString.Key("NSFont")
  public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
  public static let foregroundColor = NSAttributedString.Key("NSColor")
  public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
  public static let kern = NSAttributedString.Key("NSKern")
  public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
  public static let underlineStyle = NSAttributedString.Key("NSUnderline")
  public static let strokeColor = NSAttributedString.Key("NSStrokeColor")
  public static let strokeWidth = NSAttributedString.Key("NSStrokeWidth")
  public static let link = NSAttributedString.Key("NSLink")
  public static let baselineOffset = NSAttributedString.Key("NSBaselineOffset")
  public static let underlineColor = NSAttributedString.Key("NSUnderlineColor")
  public static let strikethroughColor = NSAttributedString.Key("NSStrikethroughColor")
  public static let cursor = NSAttributedString.Key("NSCursor")
  public static let toolTip = NSAttributedString.Key("NSToolTip")
  public static let attachment = NSAttributedString.Key("NSAttachment")
}

extension NSAttributedString {
  public struct DocumentAttributeKey: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let documentType = DocumentAttributeKey(rawValue: "DocumentType")
    public static let characterEncoding = DocumentAttributeKey(rawValue: "CharacterEncoding")
  }

  public typealias DocumentReadingOptionKey = DocumentAttributeKey

  public struct DocumentType: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let plain = DocumentType(rawValue: "NSPlainText")
    public static let rtf = DocumentType(rawValue: "NSRTFText")
    public static let html = DocumentType(rawValue: "NSHTMLText")
  }

  public convenience init(
    data: Data,
    options: [DocumentReadingOptionKey: Any] = [:],
    documentAttributes dict: UnsafeMutablePointer<NSDictionary?>? = nil
  ) throws {
    let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    let docType = options[.documentType] as? DocumentType
    let plain = (docType == .html) ? Self._stripHTML(raw) : raw
    self.init(string: plain)
  }

  private static func _stripHTML(_ html: String) -> String {
    var out = ""
    var inTag = false
    for ch in html {
      if ch == "<" { inTag = true; continue }
      if ch == ">" { inTag = false; continue }
      if !inTag { out.append(ch) }
    }
    return out
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
  }
}

extension AttributedString {
  public init(_ nsStr: NSAttributedString) {
    self.init(nsStr.string)
  }
}

open class NSAppearance: NSObject, @unchecked Sendable {
  public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let aqua = Name(rawValue: "NSAppearanceNameAqua")
    public static let darkAqua = Name(rawValue: "NSAppearanceNameDarkAqua")
  }

  public let name: Name
  public init(name: Name = .aqua) {
    self.name = name
    super.init()
  }

  public func bestMatch(from appearances: [Name]) -> Name? {
    appearances.contains(name) ? name : appearances.first
  }
}

open class NSColor: NSObject, @unchecked Sendable {
  public let redComponent: CGFloat
  public let greenComponent: CGFloat
  public let blueComponent: CGFloat
  public let alphaComponent: CGFloat

  public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    self.redComponent = red
    self.greenComponent = green
    self.blueComponent = blue
    self.alphaComponent = alpha
    super.init()
  }

  public convenience init(
    name: String?,
    dynamicProvider: @escaping (NSAppearance) -> NSColor
  ) {
    let resolved = dynamicProvider(NSAppearance(name: .aqua))
    self.init(
      srgbRed: resolved.redComponent,
      green: resolved.greenComponent,
      blue: resolved.blueComponent,
      alpha: resolved.alphaComponent
    )
  }
}

public typealias NSSize = CGSize

open class NSImage: NSObject, @unchecked Sendable {
  public var size: NSSize
  public let filePath: String?
  public let data: Data?

  public init(size: NSSize) {
    self.size = size
    self.filePath = nil
    self.data = nil
    super.init()
  }

  public init?(contentsOfFile fileName: String) {
    guard let raw = try? Data(contentsOf: URL(fileURLWithPath: fileName)), !raw.isEmpty else {
      return nil
    }
    self.size = .zero
    self.filePath = fileName
    self.data = raw
    super.init()
  }

  public init?(data: Data) {
    guard !data.isEmpty else { return nil }
    self.size = .zero
    self.filePath = nil
    self.data = data
    super.init()
  }

  public static func resolveAssetPath(named name: String, in bundle: Bundle? = nil) -> String? {
    nil
  }
}

open class NSPasteboard: NSObject, @unchecked Sendable {
  public struct PasteboardType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let string = PasteboardType(rawValue: "public.utf8-plain-text")
    public static let rtf = PasteboardType(rawValue: "public.rtf")
    public static let html = PasteboardType(rawValue: "public.html")
    public static let fileURL = PasteboardType(rawValue: "public.file-url")
    public static let png = PasteboardType(rawValue: "public.png")
    public static let tiff = PasteboardType(rawValue: "public.tiff")
    public static let pdf = PasteboardType(rawValue: "com.adobe.pdf")
  }

  public static let general = NSPasteboard()
  public static var writeStringHandler: ((String) -> Void)?

  private var strings: [PasteboardType: String] = [:]
  public private(set) var changeCount: Int = 0

  @discardableResult
  public func clearContents() -> Int {
    strings.removeAll()
    changeCount += 1
    return changeCount
  }

  @discardableResult
  public func setString(_ string: String, forType dataType: PasteboardType) -> Bool {
    strings[dataType] = string
    changeCount += 1
    if dataType == .string {
      Self.writeStringHandler?(string)
    }
    return true
  }

  public func string(forType dataType: PasteboardType) -> String? {
    strings[dataType]
  }
}
