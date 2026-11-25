import Foundation

open class NSLayoutConstraint: NSObject {
  public enum Relation: Int, Sendable {
    case lessThanOrEqual = -1
    case equal = 0
    case greaterThanOrEqual = 1
  }

  public enum Attribute: Int, Sendable {
    case notAnAttribute = 0
    case left = 1
    case right = 2
    case top = 3
    case bottom = 4
    case leading = 5
    case trailing = 6
    case width = 7
    case height = 8
    case centerX = 9
    case centerY = 10
    case lastBaseline = 11
    case firstBaseline = 12
    case leftMargin = 13
    case rightMargin = 14
    case topMargin = 15
    case bottomMargin = 16
    case leadingMargin = 17
    case trailingMargin = 18
    case centerXWithinMargins = 19
    case centerYWithinMargins = 20
  }

  public struct FormatOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let alignAllLeft = FormatOptions(rawValue: 1 << Attribute.left.rawValue)
    public static let alignAllRight = FormatOptions(rawValue: 1 << Attribute.right.rawValue)
    public static let alignAllTop = FormatOptions(rawValue: 1 << Attribute.top.rawValue)
    public static let alignAllBottom = FormatOptions(rawValue: 1 << Attribute.bottom.rawValue)
    public static let alignAllLeading = FormatOptions(rawValue: 1 << Attribute.leading.rawValue)
    public static let alignAllTrailing = FormatOptions(rawValue: 1 << Attribute.trailing.rawValue)
    public static let alignAllCenterX = FormatOptions(rawValue: 1 << Attribute.centerX.rawValue)
    public static let alignAllCenterY = FormatOptions(rawValue: 1 << Attribute.centerY.rawValue)
    public static let directionLeadingToTrailing = FormatOptions([])
  }

  public typealias Axis = NSUserInterfaceLayoutOrientation

  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var activeRegistry: [ObjectIdentifier: NSLayoutConstraint] = [:]

  public static var _allActiveConstraints: [NSLayoutConstraint] {
    registryLock.lock()
    defer { registryLock.unlock() }
    return Array(activeRegistry.values)
  }

  public class func constraints(
    withVisualFormat format: String,
    options opts: FormatOptions = [],
    metrics: [String: Any]? = nil,
    views: [String: Any]
  ) -> [NSLayoutConstraint] {
    []
  }

  public weak var firstItem: AnyObject?
  public let firstAttribute: Attribute
  public let relation: Relation
  public weak var secondItem: AnyObject?
  public let secondAttribute: Attribute
  public let multiplier: CGFloat
  public var constant: CGFloat = 0
  public var priority: NSLayoutPriority = .required
  public var identifier: String?

  public var isActive: Bool = false {
    didSet {
      guard isActive != oldValue else { return }
      let key = ObjectIdentifier(self)
      Self.registryLock.lock()
      if isActive {
        Self.activeRegistry[key] = self
      } else {
        Self.activeRegistry.removeValue(forKey: key)
      }
      Self.registryLock.unlock()
    }
  }

  public override init() {
    self.firstItem = nil
    self.firstAttribute = .notAnAttribute
    self.relation = .equal
    self.secondItem = nil
    self.secondAttribute = .notAnAttribute
    self.multiplier = 1.0
    self.constant = 0
    super.init()
  }

  public init(
    item view1: Any,
    attribute attr1: Attribute,
    relatedBy relation: Relation,
    toItem view2: Any?,
    attribute attr2: Attribute,
    multiplier: CGFloat,
    constant c: CGFloat
  ) {
    self.firstItem = view1 as AnyObject
    self.firstAttribute = attr1
    self.relation = relation
    self.secondItem = view2 as AnyObject?
    self.secondAttribute = attr2
    self.multiplier = multiplier
    self.constant = c
    super.init()
  }

  deinit {
    let key = ObjectIdentifier(self)
    Self.registryLock.lock()
    Self.activeRegistry.removeValue(forKey: key)
    Self.registryLock.unlock()
  }

  public static func activate(_ constraints: [NSLayoutConstraint]) {
    for constraint in constraints { constraint.isActive = true }
  }

  public static func deactivate(_ constraints: [NSLayoutConstraint]) {
    for constraint in constraints { constraint.isActive = false }
  }

  public func withPriority(_ priority: NSLayoutPriority) -> NSLayoutConstraint {
    self.priority = priority
    return self
  }
}

open class NSLayoutAnchor<AnchorType: AnyObject>: NSObject {
  public weak var _ownerItem: AnyObject?
  public let _attribute: NSLayoutConstraint.Attribute

  public override init() {
    self._ownerItem = nil
    self._attribute = .notAnAttribute
    super.init()
  }

  public init(_ownerItem: AnyObject?, _attribute: NSLayoutConstraint.Attribute) {
    self._ownerItem = _ownerItem
    self._attribute = _attribute
    super.init()
  }

  public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .equal,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: 1,
      constant: c
    )
  }

  public func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .greaterThanOrEqual,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: 1,
      constant: c
    )
  }

  public func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .lessThanOrEqual,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: 1,
      constant: c
    )
  }
}

public final class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
public final class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}

public final class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
  public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .equal,
      toItem: nil,
      attribute: .notAnAttribute,
      multiplier: 1,
      constant: c
    )
  }

  public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .greaterThanOrEqual,
      toItem: nil,
      attribute: .notAnAttribute,
      multiplier: 1,
      constant: c
    )
  }

  public func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .lessThanOrEqual,
      toItem: nil,
      attribute: .notAnAttribute,
      multiplier: 1,
      constant: c
    )
  }

  public func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .equal,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: m,
      constant: c
    )
  }

  public func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .greaterThanOrEqual,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: m,
      constant: c
    )
  }

  public func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat = 0) -> NSLayoutConstraint {
    guard let first = _ownerItem else {
      let fallback = NSLayoutConstraint()
      fallback.constant = c
      return fallback
    }
    return NSLayoutConstraint(
      item: first,
      attribute: _attribute,
      relatedBy: .lessThanOrEqual,
      toItem: anchor._ownerItem,
      attribute: anchor._attribute,
      multiplier: m,
      constant: c
    )
  }
}

extension NSView {
  public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .leading) }
  public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .trailing) }
  public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .left) }
  public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .right) }
  public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .top) }
  public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .bottom) }
  public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .centerX) }
  public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .centerY) }
  public var firstBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .firstBaseline) }
  public var lastBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .lastBaseline) }
  public var widthAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .width) }
  public var heightAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .height) }
}
