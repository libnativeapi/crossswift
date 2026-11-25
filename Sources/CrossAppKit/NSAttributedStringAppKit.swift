import Foundation

public enum NSLineBreakMode: UInt, Sendable {
  case byWordWrapping = 0
  case byCharWrapping = 1
  case byClipping = 2
  case byTruncatingHead = 3
  case byTruncatingTail = 4
  case byTruncatingMiddle = 5
}

public struct NSUnderlineStyle: OptionSet, Sendable, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let single = NSUnderlineStyle(rawValue: 0x01)
  public static let thick = NSUnderlineStyle(rawValue: 0x02)
  public static let double = NSUnderlineStyle(rawValue: 0x09)
}

public enum NSTextAlignment: Int, Sendable {
  case left = 0
  case center = 1
  case right = 2
  case justified = 3
  case natural = 4
}

#if !os(macOS)
  open class NSTextTab: NSObject, @unchecked Sendable {
    public let alignment: NSTextAlignment
    public let location: CGFloat
    public init(textAlignment alignment: NSTextAlignment, location loc: CGFloat, options: [String: Any] = [:]) {
      self.alignment = alignment
      self.location = loc
      super.init()
    }
  }

  open class NSTextBlock: NSObject, @unchecked Sendable {
    public enum ValueType: UInt, Sendable {
      case absoluteValueType = 0
      case percentageValueType = 1
    }

    public enum Dimension: UInt, Sendable {
      case width = 0
      case minimumWidth = 1
      case maximumWidth = 2
      case height = 4
      case minimumHeight = 5
      case maximumHeight = 6
    }

    public enum Layer: Int, Sendable {
      case padding = -1
      case border = 0
      case margin = 1
    }

    public var backgroundColor: NSColor?
    private var widths: [String: CGFloat] = [:]

    public override init() { super.init() }

    public func setValue(_ val: CGFloat, type: ValueType, for dimension: Dimension) {}

    public func setWidth(_ val: CGFloat, type: ValueType, for layer: Layer) {
      for edge: NSRectEdge in [.minX, .minY, .maxX, .maxY] {
        widths["\(layer.rawValue):\(edge.rawValue)"] = val
      }
    }

    public func setWidth(_ val: CGFloat, type: ValueType, for layer: Layer, edge: NSRectEdge) {
      widths["\(layer.rawValue):\(edge.rawValue)"] = val
    }

    public func width(for layer: Layer, edge: NSRectEdge) -> CGFloat {
      widths["\(layer.rawValue):\(edge.rawValue)"] ?? 0
    }

    public func setBorderColor(_ color: NSColor?) {}
    public func setBorderColor(_ color: NSColor?, for edge: NSRectEdge) {}
  }

  open class NSTextTable: NSTextBlock, @unchecked Sendable {
    public enum LayoutAlgorithm: UInt, Sendable {
      case automaticLayoutAlgorithm = 0
      case fixedLayoutAlgorithm = 1
    }

    public var numberOfColumns: Int = 1
    public var layoutAlgorithm: LayoutAlgorithm = .automaticLayoutAlgorithm
    public var collapsesBorders: Bool = false
    public var hidesEmptyCells: Bool = false
  }

  open class NSTextTableBlock: NSTextBlock, @unchecked Sendable {
    public let table: NSTextTable
    public let startingRow: Int
    public let rowSpan: Int
    public let startingColumn: Int
    public let columnSpan: Int

    public init(
      table: NSTextTable,
      startingRow row: Int,
      rowSpan rspan: Int,
      startingColumn col: Int,
      columnSpan cspan: Int
    ) {
      self.table = table
      self.startingRow = row
      self.rowSpan = rspan
      self.startingColumn = col
      self.columnSpan = cspan
      super.init()
    }
  }

  open class NSParagraphStyle: NSObject, NSCopying, NSMutableCopying, @unchecked Sendable {
    public static let `default` = NSParagraphStyle()
    open var lineSpacing: CGFloat = 0
    open var paragraphSpacing: CGFloat = 0
    open var paragraphSpacingBefore: CGFloat = 0
    open var alignment: NSTextAlignment = .natural
    open var firstLineHeadIndent: CGFloat = 0
    open var headIndent: CGFloat = 0
    open var tailIndent: CGFloat = 0
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping
    open var minimumLineHeight: CGFloat = 0
    open var maximumLineHeight: CGFloat = 0
    open var lineHeightMultiple: CGFloat = 0
    open var textBlocks: [NSTextBlock] = []
    open var tabStops: [NSTextTab] = []

    public override init() { super.init() }

    public func copy(with zone: NSZone? = nil) -> Any {
      let copy = NSParagraphStyle()
      copy.lineSpacing = lineSpacing
      copy.paragraphSpacing = paragraphSpacing
      copy.paragraphSpacingBefore = paragraphSpacingBefore
      copy.alignment = alignment
      copy.firstLineHeadIndent = firstLineHeadIndent
      copy.headIndent = headIndent
      copy.tailIndent = tailIndent
      copy.lineBreakMode = lineBreakMode
      copy.minimumLineHeight = minimumLineHeight
      copy.maximumLineHeight = maximumLineHeight
      copy.lineHeightMultiple = lineHeightMultiple
      copy.textBlocks = textBlocks
      copy.tabStops = tabStops
      return copy
    }

    public func mutableCopy(with zone: NSZone? = nil) -> Any {
      let copy = NSMutableParagraphStyle()
      copy.lineSpacing = lineSpacing
      copy.paragraphSpacing = paragraphSpacing
      copy.paragraphSpacingBefore = paragraphSpacingBefore
      copy.alignment = alignment
      copy.firstLineHeadIndent = firstLineHeadIndent
      copy.headIndent = headIndent
      copy.tailIndent = tailIndent
      copy.lineBreakMode = lineBreakMode
      copy.minimumLineHeight = minimumLineHeight
      copy.maximumLineHeight = maximumLineHeight
      copy.lineHeightMultiple = lineHeightMultiple
      copy.textBlocks = textBlocks
      copy.tabStops = tabStops
      return copy
    }
  }

  open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    public override init() { super.init() }
  }

  extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let ligature = NSAttributedString.Key("NSLigature")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let tracking = NSAttributedString.Key("NSTracking")
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

  extension NSAttributedString: NSPasteboardWriting {}

  extension NSAttributedString {
    public convenience init(attachment: NSTextAttachment) {
      self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }

    public func draw(at point: NSPoint) {
      let sz = size()
      draw(in: NSRect(origin: point, size: sz))
    }

    public func draw(in rect: NSRect) {
      guard let ctx = _OffscreenDrawingContext.current, !string.isEmpty else { return }
      let fontPt = (length > 0 ? (attribute(.font, at: 0, effectiveRange: nil) as? any _CrossFontPointSizeProviding)?.pointSize : nil)
        ?? NSFont.systemFontSize
      let color = length > 0 ? attribute(.foregroundColor, at: 0, effectiveRange: nil) as? any _CrossPackedColorProviding : nil
      let argb = color?._packedARGB ?? ctx.fillARGB
      ctx.ops.append(.text(string: string, rect: rect, fontSize: fontPt, colorARGB: argb))
    }

    public func size() -> NSSize {
      let fontPt = (length > 0 ? (attribute(.font, at: 0, effectiveRange: nil) as? any _CrossFontPointSizeProviding)?.pointSize : nil)
        ?? NSFont.systemFontSize
      let font = (length > 0 ? attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)
        ?? .systemFont(ofSize: fontPt)
      let lines = max(1, string.split(separator: "\n", omittingEmptySubsequences: false).count)
      let maxChars = string.split(separator: "\n", omittingEmptySubsequences: false)
        .map(\.count).max() ?? 0
      return NSSize(
        width: CGFloat(maxChars) * font.pointSize * 0.56,
        height: CGFloat(lines) * ceil(font.ascender - font.descender + font.leading)
      )
    }
  }

  extension NSString {
    public struct DrawingOptions: OptionSet, Sendable {
      public let rawValue: Int
      public init(rawValue: Int) { self.rawValue = rawValue }
      public static let usesLineFragmentOrigin = DrawingOptions(rawValue: 1 << 0)
      public static let usesFontLeading = DrawingOptions(rawValue: 1 << 1)
      public static let usesDeviceMetrics = DrawingOptions(rawValue: 1 << 3)
      public static let truncatesLastVisibleLine = DrawingOptions(rawValue: 1 << 5)
    }

    public func boundingRect(
      with size: NSSize,
      options: DrawingOptions = [],
      attributes attrs: [NSAttributedString.Key: Any]? = nil,
      context: Any? = nil
    ) -> NSRect {
      let fontPt = (attrs?[.font] as? any _CrossFontPointSizeProviding)?.pointSize ?? NSFont.systemFontSize
      let font = (attrs?[.font] as? NSFont) ?? .systemFont(ofSize: fontPt)
      let lineH = max(14, ceil(font.ascender - font.descender + font.leading))
      let charW = max(5, font.pointSize * 0.56)
      let availW = size.width.isFinite && size.width > 0 ? size.width : 1e6
      let str = self as String
      var totalLines: CGFloat = 0
      var maxW: CGFloat = 0
      for para in str.split(separator: "\n", omittingEmptySubsequences: false) {
        let pw = CGFloat(para.count) * charW
        maxW = max(maxW, min(pw, availW))
        totalLines += pw > 0 ? max(1, ceil(pw / availW)) : 1
      }
      return NSRect(x: 0, y: 0, width: maxW, height: max(lineH, totalLines * lineH))
    }

    public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize {
      let fontPt = (attrs?[.font] as? any _CrossFontPointSizeProviding)?.pointSize ?? NSFont.systemFontSize
      let font = (attrs?[.font] as? NSFont) ?? .systemFont(ofSize: fontPt)
      let str = self as String
      let lines = max(1, str.split(separator: "\n", omittingEmptySubsequences: false).count)
      let maxChars = str.split(separator: "\n", omittingEmptySubsequences: false)
        .map(\.count).max() ?? 0
      return NSSize(
        width: CGFloat(maxChars) * font.pointSize * 0.56,
        height: CGFloat(lines) * ceil(font.ascender - font.descender + font.leading)
      )
    }

    public func draw(at point: NSPoint, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
      let sz = size(withAttributes: attrs)
      draw(in: NSRect(origin: point, size: sz), withAttributes: attrs)
    }

    public func draw(in rect: NSRect, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
      guard let ctx = _OffscreenDrawingContext.current else { return }
      let str = self as String
      guard !str.isEmpty else { return }
      let fontPt = (attrs?[.font] as? any _CrossFontPointSizeProviding)?.pointSize ?? NSFont.systemFontSize
      let color = attrs?[.foregroundColor] as? any _CrossPackedColorProviding
      let argb = color?._packedARGB ?? ctx.fillARGB
      ctx.ops.append(.text(string: str, rect: rect, fontSize: fontPt, colorARGB: argb))
    }

    public var abbreviatingWithTildeInPath: String {
      var raw = self as String
      #if os(Windows)
        if raw.count >= 3, raw.first == "/",
          raw[raw.index(raw.startIndex, offsetBy: 2)] == ":"
        {
          raw.removeFirst()
        }
      #endif
      let home = NSHomeDirectory()
      guard !home.isEmpty else { return raw }
      #if os(Windows)
        var normHome = home.replacingOccurrences(of: "\\", with: "/")
        while normHome.count > 1 && normHome.hasSuffix("/") { normHome.removeLast() }
        var normRaw = raw.replacingOccurrences(of: "\\", with: "/")
        while normRaw.count > 3 && normRaw.hasSuffix("/") { normRaw.removeLast() }
        if normRaw.caseInsensitiveCompare(normHome) == .orderedSame { return "~" }
        if normRaw.lowercased().hasPrefix(normHome.lowercased() + "/") {
          return "~/" + normRaw.dropFirst(normHome.count + 1)
        }
        return raw.replacingOccurrences(of: "/", with: "\\")
      #else
        if raw == home { return "~" }
        let slashHome = home.hasSuffix("/") ? home : home + "/"
        if raw.hasPrefix(slashHome) {
          return "~/" + raw.dropFirst(slashHome.count)
        }
        return raw
      #endif
    }
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
      documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?
    ) throws {
      let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
      let docType = options[.documentType] as? DocumentType
      let plain: String
      if docType == .html {
        plain = Self._stripHTML(raw)
      } else if docType == .rtf {
        plain = Self._stripRTF(raw)
      } else {
        plain = raw
      }
      self.init(string: plain)
    }

    public convenience init?(
      rtf data: Data,
      documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?
    ) {
      guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
      else { return nil }
      let plain = Self._stripRTF(raw)
      self.init(string: plain)
    }

    public convenience init?(
      html data: Data,
      documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?
    ) {
      guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
      else { return nil }
      let plain = Self._stripHTML(raw)
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

    private static func _stripRTF(_ rtf: String) -> String {
      guard rtf.hasPrefix("{\\rtf") else { return rtf }
      var out = ""
      var depth = 0
      var skipGroupDepth: Int?
      var i = rtf.startIndex
      while i < rtf.endIndex {
        let ch = rtf[i]
        if ch == "{" {
          depth += 1
          let next = rtf.index(after: i)
          if skipGroupDepth == nil && next < rtf.endIndex && rtf[next] == "\\" {
            let rest = rtf[next...]
            if rest.hasPrefix("\\fonttbl") || rest.hasPrefix("\\colortbl")
              || rest.hasPrefix("\\stylesheet") || rest.hasPrefix("\\*")
            {
              skipGroupDepth = depth
            }
          }
          i = next
          continue
        }
        if ch == "}" {
          if skipGroupDepth == depth { skipGroupDepth = nil }
          depth = max(0, depth - 1)
          i = rtf.index(after: i)
          continue
        }
        if skipGroupDepth != nil {
          i = rtf.index(after: i)
          continue
        }
        if ch == "\\" {
          let next = rtf.index(after: i)
          guard next < rtf.endIndex else { break }
          let c2 = rtf[next]
          if c2 == "\\" || c2 == "{" || c2 == "}" {
            out.append(c2)
            i = rtf.index(after: next)
            continue
          }
          var wordEnd = next
          while wordEnd < rtf.endIndex && rtf[wordEnd].isLetter {
            wordEnd = rtf.index(after: wordEnd)
          }
          let word = String(rtf[next..<wordEnd])
          if word == "par" || word == "line" { out.append("\n") }
          else if word == "tab" { out.append("\t") }
          while wordEnd < rtf.endIndex && (rtf[wordEnd].isNumber || rtf[wordEnd] == "-") {
            wordEnd = rtf.index(after: wordEnd)
          }
          if wordEnd < rtf.endIndex && rtf[wordEnd] == " " {
            wordEnd = rtf.index(after: wordEnd)
          }
          i = wordEnd
          continue
        }
        if ch != "\r" && ch != "\n" { out.append(ch) }
        i = rtf.index(after: i)
      }
      return out
    }
  }
#endif
