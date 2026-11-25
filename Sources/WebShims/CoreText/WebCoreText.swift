import Foundation
@_exported import AppKit

// Lightweight pure-Swift CoreText font shims for WebAssembly (`os(WASI)`).

public struct CGAffineTransform: Equatable, Hashable, Sendable {
  public var a: CGFloat
  public var b: CGFloat
  public var c: CGFloat
  public var d: CGFloat
  public var tx: CGFloat
  public var ty: CGFloat

  public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

  public init(a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1, tx: CGFloat = 0, ty: CGFloat = 0) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }
}

public typealias CTFont = NSFont
public final class CTFontDescriptor: @unchecked Sendable {}

public struct CTFontSymbolicTraits: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let traitItalic = CTFontSymbolicTraits(rawValue: 1 << 0)
  public static let traitBold = CTFontSymbolicTraits(rawValue: 1 << 1)
  public static let traitExpanded = CTFontSymbolicTraits(rawValue: 1 << 5)
  public static let traitCondensed = CTFontSymbolicTraits(rawValue: 1 << 6)
  public static let traitMonoSpace = CTFontSymbolicTraits(rawValue: 1 << 10)
  public static let traitVertical = CTFontSymbolicTraits(rawValue: 1 << 11)
  public static let traitUIOptimized = CTFontSymbolicTraits(rawValue: 1 << 12)
  public static let traitColorGlyphs = CTFontSymbolicTraits(rawValue: 1 << 13)
  public static let traitComposite = CTFontSymbolicTraits(rawValue: 1 << 14)
}

public func CTFontCreateCopyWithSymbolicTraits(
  _ font: CTFont,
  _ size: CGFloat,
  _ matrix: UnsafePointer<CGAffineTransform>?,
  _ symTraitValue: CTFontSymbolicTraits,
  _ symTraitMask: CTFontSymbolicTraits
) -> CTFont? {
  let targetSize = size > 0 ? size : font.pointSize
  var traits = font.fontDescriptor.symbolicTraits
  if symTraitMask.contains(.traitBold) {
    if symTraitValue.contains(.traitBold) { traits.insert(.bold) } else { traits.remove(.bold) }
  }
  if symTraitMask.contains(.traitItalic) {
    if symTraitValue.contains(.traitItalic) { traits.insert(.italic) } else { traits.remove(.italic) }
  }
  if symTraitMask.contains(.traitMonoSpace) {
    if symTraitValue.contains(.traitMonoSpace) {
      traits.insert(.monoSpace)
      let desc = font.fontDescriptor.withDesign(.monospaced)?.withSymbolicTraits(traits)
        ?? font.fontDescriptor.withSymbolicTraits(traits)
      return NSFont(descriptor: desc, size: targetSize)
        ?? NSFont.monospacedSystemFont(
          ofSize: targetSize,
          weight: traits.contains(.bold) ? .bold : font.fontDescriptor.weight
        )
    } else {
      traits.remove(.monoSpace)
    }
  }
  let desc = font.fontDescriptor.withSymbolicTraits(traits)
  return NSFont(descriptor: desc, size: targetSize) ?? font
}

public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.pointSize }
public func CTFontGetAscent(_ font: CTFont) -> CGFloat { font.ascender }
public func CTFontGetDescent(_ font: CTFont) -> CGFloat { abs(font.descender) }
public func CTFontGetLeading(_ font: CTFont) -> CGFloat { font.leading }
public func CTFontGetXHeight(_ font: CTFont) -> CGFloat { font.xHeight }
public func CTFontGetCapHeight(_ font: CTFont) -> CGFloat { font.capHeight }
