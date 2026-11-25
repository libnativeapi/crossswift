import CrossAppKit
import Foundation
#if canImport(CoreGraphics)
  @_exported import CoreGraphics
#endif

// Re-export shared QuartzCore, Auto Layout, and text-alignment primitives from CrossAppKit
// so files importing both AppKit/SwiftUI and UIKit see identical nominal declarations.
public typealias CALayer = CrossAppKit.CALayer
public typealias CAShapeLayer = CrossAppKit.CAShapeLayer
public typealias CAGradientLayer = CrossAppKit.CAGradientLayer
public typealias CATextLayer = CrossAppKit.CATextLayer
public typealias CAAnimation = CrossAppKit.CAAnimation
public typealias CABasicAnimation = CrossAppKit.CABasicAnimation
public typealias CASpringAnimation = CrossAppKit.CASpringAnimation
public typealias CATransaction = CrossAppKit.CATransaction
public typealias CADisplayLink = CrossAppKit.CADisplayLink
public typealias CAMediaTimingFunction = CrossAppKit.CAMediaTimingFunction
public typealias CAMediaTimingFunctionName = CrossAppKit.CAMediaTimingFunctionName
public typealias CACornerMask = CrossAppKit.CACornerMask
public typealias CALayerCornerCurve = CrossAppKit.CALayerCornerCurve

@_exported import class CrossAppKit.NSLayoutConstraint
public typealias NSLayoutAnchor = CrossAppKit.NSLayoutAnchor
public typealias NSLayoutXAxisAnchor = CrossAppKit.NSLayoutXAxisAnchor
public typealias NSLayoutYAxisAnchor = CrossAppKit.NSLayoutYAxisAnchor
public typealias NSLayoutDimension = CrossAppKit.NSLayoutDimension
public typealias UILayoutPriority = CrossAppKit.NSLayoutPriority
public typealias UILayoutConstraintAxis = CrossAppKit.NSUserInterfaceLayoutOrientation

public typealias NSTextAlignment = CrossAppKit.NSTextAlignment
public typealias NSLineBreakMode = CrossAppKit.NSLineBreakMode
public typealias NSUnderlineStyle = CrossAppKit.NSUnderlineStyle
public typealias NSTextStorage = CrossAppKit.NSTextStorage
public typealias NSLayoutManager = CrossAppKit.NSLayoutManager
public typealias NSTextContainer = CrossAppKit.NSTextContainer

#if !os(macOS)
  public typealias UndoManager = CrossAppKit.UndoManager

  open class NSUserActivity: NSObject {
    public let activityType: String
    public var title: String?
    public var userInfo: [AnyHashable: Any]? = [:]
    public var webpageURL: URL?
    public var targetContentIdentifier: String?

    public init(activityType: String) {
      self.activityType = activityType
      super.init()
    }

    open func becomeCurrent() {}
    open func resignCurrent() {}
    open func invalidate() {}
  }
#endif
public typealias NSTextContentStorage = CrossAppKit.NSTextContentStorage
public typealias NSTextLayoutManager = CrossAppKit.NSTextLayoutManager
#if !os(macOS)
  public typealias NSParagraphStyle = CrossAppKit.NSParagraphStyle
  public typealias NSMutableParagraphStyle = CrossAppKit.NSMutableParagraphStyle
  public typealias NSTextAttachment = CrossAppKit.NSTextAttachment
#endif

// MARK: - Core UIKit Geometry Value Types

public struct UIEdgeInsets: Equatable, Hashable, Codable, Sendable {
  public var top: CGFloat
  public var left: CGFloat
  public var bottom: CGFloat
  public var right: CGFloat

  public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }

  public static let zero = UIEdgeInsets()
}

extension CGRect {
  public func inset(by insets: UIEdgeInsets) -> CGRect {
    CGRect(
      x: origin.x + insets.left,
      y: origin.y + insets.top,
      width: max(0, size.width - insets.left - insets.right),
      height: max(0, size.height - insets.top - insets.bottom)
    )
  }
}

public struct NSDirectionalEdgeInsets: Equatable, Hashable, Codable, Sendable {
  public var top: CGFloat
  public var leading: CGFloat
  public var bottom: CGFloat
  public var trailing: CGFloat

  public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public static let zero = NSDirectionalEdgeInsets()
}

public struct UIOffset: Equatable, Hashable, Codable, Sendable {
  public var horizontal: CGFloat
  public var vertical: CGFloat

  public init(horizontal: CGFloat = 0, vertical: CGFloat = 0) {
    self.horizontal = horizontal
    self.vertical = vertical
  }

  public static let zero = UIOffset()
}

public struct UIRectEdge: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let top = UIRectEdge(rawValue: 1 << 0)
  public static let left = UIRectEdge(rawValue: 1 << 1)
  public static let bottom = UIRectEdge(rawValue: 1 << 2)
  public static let right = UIRectEdge(rawValue: 1 << 3)
  public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}

public struct NSDirectionalRectEdge: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let none = NSDirectionalRectEdge([])
  public static let top = NSDirectionalRectEdge(rawValue: 1 << 0)
  public static let leading = NSDirectionalRectEdge(rawValue: 1 << 1)
  public static let bottom = NSDirectionalRectEdge(rawValue: 1 << 2)
  public static let trailing = NSDirectionalRectEdge(rawValue: 1 << 3)
  public static let all: NSDirectionalRectEdge = [.top, .leading, .bottom, .trailing]
}

public struct UIRectCorner: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let topLeft = UIRectCorner(rawValue: 1 << 0)
  public static let topRight = UIRectCorner(rawValue: 1 << 1)
  public static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
  public static let bottomRight = UIRectCorner(rawValue: 1 << 3)
  public static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

public struct UIAxis: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let neither = UIAxis([])
  public static let horizontal = UIAxis(rawValue: 1 << 0)
  public static let vertical = UIAxis(rawValue: 1 << 1)
  public static let both: UIAxis = [.horizontal, .vertical]
}

// MARK: - Interface Environment Enums

public enum UIUserInterfaceStyle: Int, Hashable, Sendable {
  case unspecified = 0
  case light = 1
  case dark = 2
}

public enum UIUserInterfaceSizeClass: Int, Hashable, Sendable {
  case unspecified = 0
  case compact = 1
  case regular = 2
}

public enum UIUserInterfaceIdiom: Int, Hashable, Sendable {
  case unspecified = -1
  case phone = 0
  case pad = 1
  case tv = 2
  case carPlay = 3
  case mac = 5
  case vision = 6
}

public enum UIUserInterfaceLayoutDirection: Int, Hashable, Sendable {
  case leftToRight = 0
  case rightToLeft = 1
}

public enum UIUserInterfaceLevel: Int, Hashable, Sendable {
  case unspecified = -1
  case base = 0
  case elevated = 1
}

public enum UIDisplayGamut: Int, Hashable, Sendable {
  case unspecified = -1
  case SRGB = 0
  case P3 = 1
}

public enum UIAccessibilityContrast: Int, Hashable, Sendable {
  case unspecified = -1
  case normal = 0
  case high = 1
}

public enum UILegibilityWeight: Int, Hashable, Sendable {
  case unspecified = -1
  case regular = 0
  case bold = 1
}

public enum UIUserInterfaceActiveAppearance: Int, Hashable, Sendable {
  case unspecified = -1
  case inactive = 0
  case active = 1
}

public struct UIContentSizeCategory: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let unspecified = UIContentSizeCategory(rawValue: "_UICTContentSizeCategoryUnspecified")
  public static let extraSmall = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXS")
  public static let small = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryS")
  public static let medium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryM")
  public static let large = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryL")
  public static let extraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXL")
  public static let extraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXL")
  public static let extraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXXL")
  public static let accessibilityMedium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityM")
  public static let accessibilityLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityL")
  public static let accessibilityExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXL")
  public static let accessibilityExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXL")
  public static let accessibilityExtraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXXL")

  private static let orderedRanks: [UIContentSizeCategory] = [
    .unspecified, .extraSmall, .small, .medium, .large,
    .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
    .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
    .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
  ]

  internal var rank: Int {
    Self.orderedRanks.firstIndex(of: self) ?? 4
  }

  public var isAccessibilityCategory: Bool {
    rank >= Self.orderedRanks.firstIndex(of: .accessibilityMedium)!
  }

  internal var scaleMultiplier: CGFloat {
    switch self {
    case .extraSmall: return 0.82
    case .small: return 0.88
    case .medium: return 0.94
    case .large, .unspecified: return 1.0
    case .extraLarge: return 1.12
    case .extraExtraLarge: return 1.24
    case .extraExtraExtraLarge: return 1.35
    case .accessibilityMedium: return 1.60
    case .accessibilityLarge: return 1.90
    case .accessibilityExtraLarge: return 2.35
    case .accessibilityExtraExtraLarge: return 2.75
    case .accessibilityExtraExtraExtraLarge: return 3.10
    default: return 1.0
    }
  }

  public static func < (lhs: UIContentSizeCategory, rhs: UIContentSizeCategory) -> Bool {
    lhs.rank < rhs.rank
  }
}

public enum UIInterfaceOrientation: Int, Hashable, Sendable {
  case unknown = 0
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeLeft = 4
  case landscapeRight = 3

  public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
  public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}

public struct UIInterfaceOrientationMask: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let portrait = UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.portrait.rawValue)
  public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.landscapeLeft.rawValue)
  public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.landscapeRight.rawValue)
  public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 1 << UIInterfaceOrientation.portraitUpsideDown.rawValue)
  public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
  public static let all: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown]
  public static let allButUpsideDown: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
}

public enum UIDeviceOrientation: Int, Hashable, Sendable {
  case unknown = 0
  case portrait = 1
  case portraitUpsideDown = 2
  case landscapeLeft = 3
  case landscapeRight = 4
  case faceUp = 5
  case faceDown = 6

  public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
  public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
  public var isFlat: Bool { self == .faceUp || self == .faceDown }
  public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
}

public enum UIStatusBarStyle: Int, Hashable, Sendable {
  case `default` = 0
  case lightContent = 1
  case darkContent = 3
}

public enum UIStatusBarAnimation: Int, Hashable, Sendable {
  case none = 0
  case fade = 1
  case slide = 2
}

public enum UIBackgroundFetchResult: UInt, Hashable, Sendable {
  case newData = 0
  case noData = 1
  case failed = 2
}

public struct UIBackgroundTaskIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}

// MARK: - IndexPath UIKit Extensions (row / section / item)

extension IndexPath {
  public init(row: Int, section: Int) {
    self.init(indexes: [section, row])
  }

  public init(item: Int, section: Int) {
    self.init(indexes: [section, item])
  }

  public var section: Int {
    count > 0 ? self[0] : 0
  }

  public var row: Int {
    count > 1 ? self[1] : 0
  }

  public var item: Int {
    count > 1 ? self[1] : 0
  }
}
