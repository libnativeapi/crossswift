import CrossAppKit
import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

// MARK: - UILayoutGuide

@MainActor
open class UILayoutGuide: NSObject {
  public var identifier: String = ""
  public internal(set) weak var owningView: UIView?
  internal var guideKind: Kind = .custom
  public internal(set) var layoutFrame: CGRect = .zero

  internal enum Kind {
    case custom
    case safeArea
    case margins
    case readable
    case keyboard
  }

  public override init() {
    super.init()
  }

  internal init(kind: Kind, owningView: UIView) {
    self.guideKind = kind
    self.owningView = owningView
    super.init()
  }

  internal func resolvedFrame(in containerBounds: CGRect) -> CGRect {
    guard let owner = owningView else { return layoutFrame }
    switch guideKind {
    case .safeArea:
      let f = containerBounds.inset(by: owner.safeAreaInsets)
      layoutFrame = f
      return f
    case .margins, .readable:
      let f = containerBounds.inset(by: owner.layoutMargins)
      layoutFrame = f
      return f
    case .keyboard:
      let f = CGRect(x: 0, y: containerBounds.maxY, width: containerBounds.width, height: 0)
      layoutFrame = f
      return f
    case .custom:
      return layoutFrame
    }
  }

  public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .leading) }
  public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .trailing) }
  public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .left) }
  public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .right) }
  public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .top) }
  public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .bottom) }
  public var widthAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .width) }
  public var heightAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .height) }
  public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .centerX) }
  public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .centerY) }
}

// MARK: - UIView

@MainActor
open class UIView: UIResponder, UICoordinateSpace, UITraitEnvironment {
  public enum ContentMode: Int, Sendable {
    case scaleToFill = 0
    case scaleAspectFit = 1
    case scaleAspectFill = 2
    case redraw = 3
    case center = 4
    case top = 5
    case bottom = 6
    case left = 7
    case right = 8
    case topLeft = 9
    case topRight = 10
    case bottomLeft = 11
    case bottomRight = 12
  }

  public struct AutoresizingMask: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let flexibleLeftMargin = AutoresizingMask(rawValue: 1 << 0)
    public static let flexibleWidth = AutoresizingMask(rawValue: 1 << 1)
    public static let flexibleRightMargin = AutoresizingMask(rawValue: 1 << 2)
    public static let flexibleTopMargin = AutoresizingMask(rawValue: 1 << 3)
    public static let flexibleHeight = AutoresizingMask(rawValue: 1 << 4)
    public static let flexibleBottomMargin = AutoresizingMask(rawValue: 1 << 5)
  }

  public struct AnimationOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let layoutSubviews = AnimationOptions(rawValue: 1 << 0)
    public static let allowUserInteraction = AnimationOptions(rawValue: 1 << 1)
    public static let beginFromCurrentState = AnimationOptions(rawValue: 1 << 2)
    public static let `repeat` = AnimationOptions(rawValue: 1 << 3)
    public static let autoreverse = AnimationOptions(rawValue: 1 << 4)
    public static let overrideInheritedDuration = AnimationOptions(rawValue: 1 << 5)
    public static let overrideInheritedCurve = AnimationOptions(rawValue: 1 << 6)
    public static let allowAnimatedContent = AnimationOptions(rawValue: 1 << 7)
    public static let showHideTransitionViews = AnimationOptions(rawValue: 1 << 8)
    public static let overrideInheritedOptions = AnimationOptions(rawValue: 1 << 9)
    public static let curveEaseInOut = AnimationOptions([])
    public static let curveEaseIn = AnimationOptions(rawValue: 1 << 16)
    public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16)
    public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
    public static let transitionNone = AnimationOptions([])
    public static let transitionFlipFromLeft = AnimationOptions(rawValue: 1 << 20)
    public static let transitionFlipFromRight = AnimationOptions(rawValue: 2 << 20)
    public static let transitionCurlUp = AnimationOptions(rawValue: 3 << 20)
    public static let transitionCurlDown = AnimationOptions(rawValue: 4 << 20)
    public static let transitionCrossDissolve = AnimationOptions(rawValue: 5 << 20)
    public static let transitionFlipFromTop = AnimationOptions(rawValue: 6 << 20)
    public static let transitionFlipFromBottom = AnimationOptions(rawValue: 7 << 20)
  }

  public enum AnimationCurve: Int, Sendable {
    case easeInOut = 0
    case easeIn = 1
    case easeOut = 2
    case linear = 3
  }

  public enum TintAdjustmentMode: Int, Sendable {
    case automatic = 0
    case normal = 1
    case dimmed = 2
  }

  public enum ContentInsetAdjustmentBehavior: Int, Sendable {
    case automatic = 0
    case scrollableAxes = 1
    case never = 2
    case always = 3
  }

  public static let noIntrinsicMetric: CGFloat = -1
  public static let layoutFittingCompressedSize = CGSize(width: 0, height: 0)
  public static let layoutFittingExpandedSize = CGSize(width: 10000, height: 10000)

  private var isSyncingGeometry = false

  open var frame: CGRect {
    didSet {
      guard !isSyncingGeometry else { return }
      isSyncingGeometry = true
      let oldSize = bounds.size
      bounds.size = frame.size
      layer.frame = frame
      isSyncingGeometry = false
      syncNativeFrame()
      if oldSize != frame.size {
        applyAutoresizingToSubviews(from: oldSize, to: frame.size)
        setNeedsLayout()
        viewDidChangeBoundsSize(from: oldSize)
      }
    }
  }

  open var bounds: CGRect {
    didSet {
      guard !isSyncingGeometry else { return }
      isSyncingGeometry = true
      let oldSize = oldValue.size
      frame.size = bounds.size
      layer.bounds = bounds
      isSyncingGeometry = false
      syncNativeFrame()
      if oldSize != bounds.size {
        applyAutoresizingToSubviews(from: oldSize, to: bounds.size)
        setNeedsLayout()
        viewDidChangeBoundsSize(from: oldSize)
      }
    }
  }

  open var center: CGPoint {
    get { CGPoint(x: frame.midX, y: frame.midY) }
    set {
      frame.origin = CGPoint(
        x: newValue.x - frame.width * 0.5,
        y: newValue.y - frame.height * 0.5
      )
    }
  }

  public var transform: CGAffineTransform = .identity
  public let layer: CALayer = CALayer()

  open var backgroundColor: UIColor? {
    didSet {
      #if !os(macOS)
        layer.backgroundColor = backgroundColor?.cgColor
      #endif
      syncNativeAppearance()
    }
  }

  open var isHidden: Bool = false {
    didSet {
      layer.isHidden = isHidden
      #if !os(macOS)
        ownedNativeView?.setVisible(!isHidden)
      #endif
    }
  }

  open var alpha: CGFloat = 1.0 {
    didSet {
      layer.opacity = Float(min(max(alpha, 0), 1))
    }
  }

  public var isOpaque: Bool = true
  public var clearsContextBeforeDrawing: Bool = true
  public var clipsToBounds: Bool = false {
    didSet { layer.masksToBounds = clipsToBounds }
  }
  public var isUserInteractionEnabled: Bool = true
  public var isMultipleTouchEnabled: Bool = false
  public var isExclusiveTouch: Bool = false
  public var tag: Int = 0
  public var contentMode: ContentMode = .scaleToFill
  public var autoresizingMask: AutoresizingMask = []
  public var translatesAutoresizingMaskIntoConstraints: Bool = true
  public var semanticContentAttribute: Int = 0

  private var explicitTintColor: UIColor?
  open var tintColor: UIColor! {
    get { explicitTintColor ?? superview?.tintColor ?? .systemBlue }
    set {
      explicitTintColor = newValue
      propagateTintColorDidChange()
    }
  }
  public var tintAdjustmentMode: TintAdjustmentMode = .automatic

  public var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified {
    didSet {
      guard oldValue != overrideUserInterfaceStyle else { return }
      notifyTraitCollectionChanged(from: nil)
    }
  }

  public private(set) var subviews: [UIView] = []
  public private(set) weak var superview: UIView?
  internal weak var owningViewController: UIViewController?

  private weak var explicitWindow: UIWindow?
  open var window: UIWindow? {
    if let selfWin = self as? UIWindow { return selfWin }
    return explicitWindow ?? superview?.window
  }

  internal func _propagateWindow(_ win: UIWindow?) {
    willMove(toWindow: win)
    explicitWindow = win
    for child in subviews {
      child._propagateWindow(win)
    }
    syncNativeAppearance()
    didMoveToWindow()
  }

  open override var next: UIResponder? {
    owningViewController ?? superview ?? nextResponderOverride
  }

  public var safeAreaInsets: UIEdgeInsets = .zero {
    didSet {
      guard oldValue != safeAreaInsets else { return }
      safeAreaInsetsDidChange()
      setNeedsLayout()
    }
  }

  public var layoutMargins: UIEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) {
    didSet {
      directionalLayoutMargins = NSDirectionalEdgeInsets(
        top: layoutMargins.top,
        leading: layoutMargins.left,
        bottom: layoutMargins.bottom,
        trailing: layoutMargins.right
      )
      layoutMarginsDidChange()
    }
  }

  public var directionalLayoutMargins: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(
    top: 8, leading: 8, bottom: 8, trailing: 8
  )
  public var preservesSuperviewLayoutMargins: Bool = false
  public var insetsLayoutMarginsFromSafeArea: Bool = true

  private lazy var _safeAreaGuide = UILayoutGuide(kind: .safeArea, owningView: self)
  private lazy var _marginsGuide = UILayoutGuide(kind: .margins, owningView: self)
  private lazy var _readableGuide = UILayoutGuide(kind: .readable, owningView: self)
  private lazy var _keyboardGuide = UILayoutGuide(kind: .keyboard, owningView: self)

  public var safeAreaLayoutGuide: UILayoutGuide { _safeAreaGuide }
  public var layoutMarginsGuide: UILayoutGuide { _marginsGuide }
  public var readableContentGuide: UILayoutGuide { _readableGuide }
  public var keyboardLayoutGuide: UILayoutGuide { _keyboardGuide }

  public private(set) var layoutGuides: [UILayoutGuide] = []
  public private(set) var constraints: [NSLayoutConstraint] = []
  public var gestureRecognizers: [UIGestureRecognizer]? = []

  public var accessibilityIdentifier: String?
  public var accessibilityLabel: String? {
    didSet {
      #if !os(macOS)
        ownedNativeView?.setAccessibilityLabel(accessibilityLabel)
      #endif
    }
  }
  public var accessibilityValue: String?
  public var accessibilityHint: String?
  public var isAccessibilityElement: Bool = false

  private var huggingPriorities: [NSLayoutConstraint.Axis: UILayoutPriority] = [
    .horizontal: .defaultLow,
    .vertical: .defaultLow,
  ]
  private var compressionPriorities: [NSLayoutConstraint.Axis: UILayoutPriority] = [
    .horizontal: .defaultHigh,
    .vertical: .defaultHigh,
  ]
  private var needsLayoutFlag = true
  private var traitObservers: [UUID: (UIView, UITraitCollection) -> Void] = [:]

  #if !os(macOS)
    public var ownedNativeView: NativeAPI.View?

    open var prefersNativeBacking: Bool {
      ownedNativeView != nil || backgroundColor != nil || subviews.contains(where: { $0.prefersNativeBacking })
    }

    @discardableResult
    open func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      guard let created = NativeAPI.View.create() else { return nil }
      created.setLayout(.absolute)
      ownedNativeView = created
      syncNativeFrame()
      syncNativeAppearance()
      created.setVisible(!isHidden)
      if let label = accessibilityLabel {
        created.setAccessibilityLabel(label)
      }
      return created
    }

    /// Recursively materializes NativeAPI views for this subtree when hosted inside SwiftUI or UIWindow.
    @discardableResult
    public func ensureNativeSubtree() -> NativeAPI.View? {
      guard let rootNV = ensureNativeView() else { return nil }
      for child in subviews {
        if let childNV = child.ensureNativeSubtree() {
          if childNV.parent?.nativeHandle != rootNV.nativeHandle {
            rootNV.addSubview(childNV)
          }
          child.syncNativeFrame()
          child.syncNativeAppearance()
        }
      }
      return rootNV
    }
  #endif

  internal func syncNativeFrame() {
    #if !os(macOS)
      guard !(self is UIWindow), let nv = ownedNativeView else { return }
      nv.setFrame(NativeAPI.Rectangle(
        x: Double(frame.origin.x),
        y: Double(frame.origin.y),
        width: Double(max(0, frame.size.width)),
        height: Double(max(0, frame.size.height))
      ))
    #endif
  }

  internal func syncNativeAppearance() {
    #if !os(macOS)
      guard let nv = ownedNativeView else { return }
      if let bg = backgroundColor {
        let c = bg.resolved(for: traitCollection)
        nv.setBackgroundColor(NativeAPI.Color(
          r: UInt8(clamping: Int((c.r * 255).rounded())),
          g: UInt8(clamping: Int((c.g * 255).rounded())),
          b: UInt8(clamping: Int((c.b * 255).rounded())),
          a: UInt8(clamping: Int((c.a * 255).rounded()))
        ))
      } else {
        nv.setBackgroundColor(.transparent)
      }
    #endif
  }

  // MARK: - Initializers

  public init(frame: CGRect) {
    self.frame = frame
    self.bounds = CGRect(origin: .zero, size: frame.size)
    super.init()
    self.layer.frame = frame
  }

  public convenience override init() {
    self.init(frame: .zero)
  }

  public required override init?(coder: NSCoder) {
    self.frame = .zero
    self.bounds = .zero
    super.init(coder: coder)
  }

  // MARK: - Trait Collection

  open var traitCollection: UITraitCollection {
    let base = superview?.traitCollection
      ?? window?.windowScene?.traitCollection
      ?? UITraitCollection.systemTraitCollection
    guard overrideUserInterfaceStyle != .unspecified else { return base }
    let style = overrideUserInterfaceStyle
    return base.modifyingTraits { $0.userInterfaceStyle = style }
  }

  open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}

  internal func notifyTraitCollectionChanged(from previous: UITraitCollection?) {
    syncNativeAppearance()
    traitCollectionDidChange(previous)
    let prev = previous ?? traitCollection
    for obs in Array(traitObservers.values) {
      obs(self, prev)
    }
    for sub in subviews {
      sub.notifyTraitCollectionChanged(from: prev)
    }
  }

  @discardableResult
  public func registerForTraitChanges(
    _ traits: [Any],
    handler: @escaping (Self, UITraitCollection) -> Void
  ) -> any UITraitChangeRegistration {
    let token = _TraitRegistrationToken()
    traitObservers[token.id] = { view, prev in
      if let typed = view as? Self {
        handler(typed, prev)
      }
    }
    return token
  }

  public func unregisterForTraitChanges(_ registration: any UITraitChangeRegistration) {
    if let token = registration as? _TraitRegistrationToken {
      traitObservers.removeValue(forKey: token.id)
    }
  }

  open func tintColorDidChange() {}

  private func propagateTintColorDidChange() {
    tintColorDidChange()
    for sub in subviews {
      if sub.explicitTintColor == nil {
        sub.propagateTintColorDidChange()
      }
    }
  }

  open func safeAreaInsetsDidChange() {}
  open func layoutMarginsDidChange() {}
  internal func viewDidChangeBoundsSize(from oldSize: CGSize) {}

  // MARK: - View Hierarchy

  open func addSubview(_ view: UIView) {
    guard view !== self else { return }
    view.willMove(toSuperview: self)
    view.removeFromSuperview()
    subviews.append(view)
    view.superview = self
    layer.addSublayer(view.layer)
    if let w = self.window {
      view._propagateWindow(w)
    }
    #if !os(macOS)
      if let parentNV = ownedNativeView, let childNV = view.ownedNativeView ?? view.ensureNativeSubtree() {
        parentNV.addSubview(childNV)
      }
    #endif
    didAddSubview(view)
    view.didMoveToSuperview()
    setNeedsLayout()
  }

  open func insertSubview(_ view: UIView, at index: Int) {
    guard view !== self else { return }
    view.willMove(toSuperview: self)
    view.removeFromSuperview()
    let clamped = min(max(0, index), subviews.count)
    subviews.insert(view, at: clamped)
    view.superview = self
    layer.insertSublayer(view.layer, at: UInt32(clamped))
    if let w = self.window {
      view._propagateWindow(w)
    }
    #if !os(macOS)
      if let parentNV = ownedNativeView, let childNV = view.ownedNativeView ?? view.ensureNativeSubtree() {
        parentNV.insertSubview(CUnsignedLong(clamped), subview: childNV)
      }
    #endif
    didAddSubview(view)
    view.didMoveToSuperview()
    setNeedsLayout()
  }

  open func insertSubview(_ view: UIView, belowSubview siblingSubview: UIView) {
    if let idx = subviews.firstIndex(where: { $0 === siblingSubview }) {
      insertSubview(view, at: idx)
    } else {
      addSubview(view)
    }
  }

  open func insertSubview(_ view: UIView, aboveSubview siblingSubview: UIView) {
    if let idx = subviews.firstIndex(where: { $0 === siblingSubview }) {
      insertSubview(view, at: idx + 1)
    } else {
      addSubview(view)
    }
  }

  open func exchangeSubview(at index1: Int, withSubviewAt index2: Int) {
    guard subviews.indices.contains(index1), subviews.indices.contains(index2), index1 != index2 else { return }
    subviews.swapAt(index1, index2)
    setNeedsLayout()
  }

  open func bringSubviewToFront(_ view: UIView) {
    guard let idx = subviews.firstIndex(where: { $0 === view }) else { return }
    subviews.remove(at: idx)
    subviews.append(view)
  }

  open func sendSubviewToBack(_ view: UIView) {
    guard let idx = subviews.firstIndex(where: { $0 === view }) else { return }
    subviews.remove(at: idx)
    subviews.insert(view, at: 0)
  }

  open func removeFromSuperview() {
    guard let parent = superview else { return }
    willMove(toSuperview: nil)
    parent.willRemoveSubview(self)
    #if !os(macOS)
      if let parentNV = parent.ownedNativeView, let childNV = ownedNativeView {
        _ = parentNV.removeSubview(childNV)
      }
    #endif
    layer.removeFromSuperlayer()
    parent.subviews.removeAll { $0 === self }
    superview = nil
    if explicitWindow != nil {
      _propagateWindow(nil)
    }
    didMoveToSuperview()
    parent.setNeedsLayout()
  }

  open func didAddSubview(_ subview: UIView) {}
  open func willRemoveSubview(_ subview: UIView) {}
  open func willMove(toSuperview newSuperview: UIView?) {}
  open func didMoveToSuperview() {}
  open func willMove(toWindow newWindow: UIWindow?) {}
  open func didMoveToWindow() {}

  public func isDescendant(of view: UIView) -> Bool {
    var cur: UIView? = self
    while let v = cur {
      if v === view { return true }
      cur = v.superview
    }
    return false
  }

  open func viewWithTag(_ tag: Int) -> UIView? {
    if self.tag == tag { return self }
    for sub in subviews {
      if let hit = sub.viewWithTag(tag) { return hit }
    }
    return nil
  }

  // MARK: - Gestures & Layout Guides

  open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
    gestureRecognizer.view?.removeGestureRecognizer(gestureRecognizer)
    if gestureRecognizers == nil { gestureRecognizers = [] }
    gestureRecognizers?.append(gestureRecognizer)
    gestureRecognizer.view = self
  }

  open func removeGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
    gestureRecognizers?.removeAll { $0 === gestureRecognizer }
    if gestureRecognizer.view === self {
      gestureRecognizer.view = nil
    }
  }

  public func addLayoutGuide(_ layoutGuide: UILayoutGuide) {
    layoutGuide.owningView?.removeLayoutGuide(layoutGuide)
    layoutGuides.append(layoutGuide)
    layoutGuide.owningView = self
  }

  public func removeLayoutGuide(_ layoutGuide: UILayoutGuide) {
    layoutGuides.removeAll { $0 === layoutGuide }
    if layoutGuide.owningView === self {
      layoutGuide.owningView = nil
    }
  }

  // MARK: - Constraints & Auto Layout Anchors

  public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .leading) }
  public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .trailing) }
  public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .left) }
  public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .right) }
  public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .top) }
  public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .bottom) }
  public var widthAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .width) }
  public var heightAnchor: NSLayoutDimension { NSLayoutDimension(_ownerItem: self, _attribute: .height) }
  public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(_ownerItem: self, _attribute: .centerX) }
  public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .centerY) }
  public var firstBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .firstBaseline) }
  public var lastBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(_ownerItem: self, _attribute: .lastBaseline) }

  public func addConstraint(_ constraint: NSLayoutConstraint) {
    if !constraints.contains(where: { $0 === constraint }) {
      constraints.append(constraint)
    }
    constraint.isActive = true
  }

  public func addConstraints(_ newConstraints: [NSLayoutConstraint]) {
    for c in newConstraints { addConstraint(c) }
  }

  public func removeConstraint(_ constraint: NSLayoutConstraint) {
    constraint.isActive = false
    constraints.removeAll { $0 === constraint }
  }

  public func removeConstraints(_ oldConstraints: [NSLayoutConstraint]) {
    for c in oldConstraints { removeConstraint(c) }
  }

  public func contentHuggingPriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority {
    huggingPriorities[axis] ?? .defaultLow
  }

  public func setContentHuggingPriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) {
    huggingPriorities[axis] = priority
  }

  public func contentCompressionResistancePriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority {
    compressionPriorities[axis] ?? .defaultHigh
  }

  public func setContentCompressionResistancePriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) {
    compressionPriorities[axis] = priority
  }

  // MARK: - Sizing & Layout Pass

  open var intrinsicContentSize: CGSize {
    CGSize(width: Self.noIntrinsicMetric, height: Self.noIntrinsicMetric)
  }

  open func invalidateIntrinsicContentSize() {
    superview?.setNeedsLayout()
  }

  open func sizeThatFits(_ size: CGSize) -> CGSize {
    let intrinsic = intrinsicContentSize
    return CGSize(
      width: intrinsic.width >= 0 ? intrinsic.width : frame.width,
      height: intrinsic.height >= 0 ? intrinsic.height : frame.height
    )
  }

  open func sizeToFit() {
    let fitted = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    frame.size = fitted
  }

  open func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
    systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .fittingSizeLevel,
      verticalFittingPriority: .fittingSizeLevel
    )
  }

  open func systemLayoutSizeFitting(
    _ targetSize: CGSize,
    withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
    verticalFittingPriority: UILayoutPriority
  ) -> CGSize {
    let probeW = horizontalFittingPriority == .required && targetSize.width > 0 ? targetSize.width : max(bounds.width, 320)
    let probeH = verticalFittingPriority == .required && targetSize.height > 0 ? targetSize.height : max(bounds.height, 240)
    let saved = frame
    if bounds.width <= 0 || bounds.height <= 0 {
      frame.size = CGSize(width: probeW, height: probeH)
    }
    layoutIfNeeded()
    let intrinsic = intrinsicContentSize
    var maxSubX: CGFloat = intrinsic.width >= 0 ? intrinsic.width : 0
    var maxSubY: CGFloat = intrinsic.height >= 0 ? intrinsic.height : 0
    for sub in subviews where !sub.isHidden {
      maxSubX = max(maxSubX, sub.frame.maxX)
      maxSubY = max(maxSubY, sub.frame.maxY)
    }
    if saved.size != frame.size && (saved.width == 0 && saved.height == 0) {
      frame = saved
    }
    return CGSize(
      width: horizontalFittingPriority == .required ? targetSize.width : max(maxSubX, 0),
      height: verticalFittingPriority == .required ? targetSize.height : max(maxSubY, 0)
    )
  }

  open func setNeedsLayout() {
    needsLayoutFlag = true
  }

  open func layoutIfNeeded() {
    owningViewController?.viewWillLayoutSubviews()
    solveChildAutoLayoutConstraints()
    layoutSubviews()
    needsLayoutFlag = false
    owningViewController?.viewDidLayoutSubviews()
    for sub in subviews {
      sub.layoutIfNeeded()
    }
  }

  open func layoutSubviews() {}

  open func setNeedsDisplay() {}
  open func setNeedsDisplay(_ rect: CGRect) {}
  open func draw(_ rect: CGRect) {}

  private func applyAutoresizingToSubviews(from oldSize: CGSize, to newSize: CGSize) {
    guard oldSize.width > 0 && oldSize.height > 0 else { return }
    let dw = newSize.width - oldSize.width
    let dh = newSize.height - oldSize.height
    guard abs(dw) > 1e-4 || abs(dh) > 1e-4 else { return }

    for sub in subviews where sub.translatesAutoresizingMaskIntoConstraints && !sub.autoresizingMask.isEmpty {
      var f = sub.frame
      let mask = sub.autoresizingMask
      let flexL = mask.contains(.flexibleLeftMargin)
      let flexW = mask.contains(.flexibleWidth)
      let flexR = mask.contains(.flexibleRightMargin)
      let hFlexCount = (flexL ? 1 : 0) + (flexW ? 1 : 0) + (flexR ? 1 : 0)
      if hFlexCount > 0 {
        let share = dw / CGFloat(hFlexCount)
        if flexL { f.origin.x += share }
        if flexW { f.size.width = max(0, f.size.width + share) }
      }

      let flexT = mask.contains(.flexibleTopMargin)
      let flexH = mask.contains(.flexibleHeight)
      let flexB = mask.contains(.flexibleBottomMargin)
      let vFlexCount = (flexT ? 1 : 0) + (flexH ? 1 : 0) + (flexB ? 1 : 0)
      if vFlexCount > 0 {
        let share = dh / CGFloat(vFlexCount)
        if flexT { f.origin.y += share }
        if flexH { f.size.height = max(0, f.size.height + share) }
      }
      sub.frame = f
    }
  }

  /// Resolves common programmatic Auto Layout constraints for direct `UIView` children
  /// with `translatesAutoresizingMaskIntoConstraints == false`.
  private func solveChildAutoLayoutConstraints() {
    let managedChildren = subviews.filter { !$0.translatesAutoresizingMaskIntoConstraints }
    guard !managedChildren.isEmpty else { return }

    let active = NSLayoutConstraint._allActiveConstraints
    guard !active.isEmpty else { return }

    let childSet = Set(managedChildren.map(ObjectIdentifier.init))
    let relevant = active.filter { c in
      guard let first = c.firstItem else { return false }
      if childSet.contains(ObjectIdentifier(first)) { return true }
      if let second = c.secondItem, childSet.contains(ObjectIdentifier(second)) { return true }
      return false
    }
    guard !relevant.isEmpty else { return }

    struct BoxEdges {
      var minX: CGFloat?
      var maxX: CGFloat?
      var centerX: CGFloat?
      var width: CGFloat?
      var minY: CGFloat?
      var maxY: CGFloat?
      var centerY: CGFloat?
      var height: CGFloat?
    }

    var boxes: [ObjectIdentifier: BoxEdges] = [:]
    for child in managedChildren {
      boxes[ObjectIdentifier(child)] = BoxEdges()
    }

    func resolveKnownFrame(of item: AnyObject) -> CGRect? {
      if item === self {
        return bounds
      }
      if let guide = item as? UILayoutGuide, guide.owningView === self {
        return guide.resolvedFrame(in: bounds)
      }
      if let view = item as? UIView, let b = boxes[ObjectIdentifier(view)] {
        let intrinsic = view.intrinsicContentSize
        let w: CGFloat
        if let explicitW = b.width {
          w = explicitW
        } else if let minX = b.minX, let maxX = b.maxX {
          w = max(0, maxX - minX)
        } else if intrinsic.width >= 0 {
          w = intrinsic.width
        } else {
          w = view.frame.width
        }

        let h: CGFloat
        if let explicitH = b.height {
          h = explicitH
        } else if let minY = b.minY, let maxY = b.maxY {
          h = max(0, maxY - minY)
        } else if intrinsic.height >= 0 {
          h = intrinsic.height
        } else {
          h = view.frame.height
        }

        let x: CGFloat
        if let minX = b.minX { x = minX }
        else if let maxX = b.maxX { x = maxX - w }
        else if let cx = b.centerX { x = cx - w * 0.5 }
        else { x = view.frame.minX }
        let y: CGFloat
        if let minY = b.minY { y = minY }
        else if let maxY = b.maxY { y = maxY - h }
        else if let cy = b.centerY { y = cy - h * 0.5 }
        else { y = view.frame.minY }
        return CGRect(x: x, y: y, width: w, height: h)
      }
      return nil
    }

    func metricValue(of item: AnyObject, attr: NSLayoutConstraint.Attribute) -> CGFloat? {
      guard let r = resolveKnownFrame(of: item) else { return nil }
      switch attr {
      case .left, .leading: return r.minX
      case .right, .trailing: return r.maxX
      case .top, .firstBaseline: return r.minY
      case .bottom, .lastBaseline: return r.maxY
      case .width: return r.width
      case .height: return r.height
      case .centerX, .centerXWithinMargins: return r.midX
      case .centerY, .centerYWithinMargins: return r.midY
      case .leftMargin, .leadingMargin: return r.minX + layoutMargins.left
      case .rightMargin, .trailingMargin: return r.maxX - layoutMargins.right
      case .topMargin: return r.minY + layoutMargins.top
      case .bottomMargin: return r.maxY - layoutMargins.bottom
      case .notAnAttribute: return 0
      }
    }

    func assignMetric(on childID: ObjectIdentifier, attr: NSLayoutConstraint.Attribute, value: CGFloat) {
      var b = boxes[childID] ?? BoxEdges()
      switch attr {
      case .left, .leading, .leftMargin, .leadingMargin: b.minX = value
      case .right, .trailing, .rightMargin, .trailingMargin: b.maxX = value
      case .top, .firstBaseline, .topMargin: b.minY = value
      case .bottom, .lastBaseline, .bottomMargin: b.maxY = value
      case .width: b.width = max(0, value)
      case .height: b.height = max(0, value)
      case .centerX, .centerXWithinMargins: b.centerX = value
      case .centerY, .centerYWithinMargins: b.centerY = value
      case .notAnAttribute: break
      }
      boxes[childID] = b
    }

    for _ in 0..<4 {
      for c in relevant {
        guard let first = c.firstItem else { continue }
        let firstID = ObjectIdentifier(first)
        if childSet.contains(firstID) {
          if let second = c.secondItem {
            if let rhs = metricValue(of: second, attr: c.secondAttribute) {
              assignMetric(on: firstID, attr: c.firstAttribute, value: rhs * c.multiplier + c.constant)
            }
          } else {
            assignMetric(on: firstID, attr: c.firstAttribute, value: c.constant)
          }
        } else if let second = c.secondItem {
          let secondID = ObjectIdentifier(second)
          if childSet.contains(secondID), c.multiplier != 0,
             let lhs = metricValue(of: first, attr: c.firstAttribute)
          {
            assignMetric(on: secondID, attr: c.secondAttribute, value: (lhs - c.constant) / c.multiplier)
          }
        }
      }
    }

    for child in managedChildren {
      if let resolved = resolveKnownFrame(of: child), child.frame != resolved {
        child.frame = resolved
      }
    }
  }

  // MARK: - Coordinate Conversion & Hit Testing

  private func _convertPointToView(_ point: CGPoint, target: UIView?) -> CGPoint {
    guard let target else {
      var p = point
      var cur: UIView? = self
      while let v = cur {
        if v is UIWindow { break }
        p.x += v.frame.origin.x - v.bounds.origin.x
        p.y += v.frame.origin.y - v.bounds.origin.y
        cur = v.superview
      }
      return p
    }
    if target === self { return point }
    let inWin = _convertPointToView(point, target: nil)
    return target._convertPointFromView(inWin, source: nil)
  }

  private func _convertPointFromView(_ point: CGPoint, source: UIView?) -> CGPoint {
    guard let source else {
      var p = point
      var chain: [UIView] = []
      var cur: UIView? = self
      while let v = cur {
        if v is UIWindow { break }
        chain.append(v)
        cur = v.superview
      }
      for v in chain.reversed() {
        p.x -= v.frame.origin.x - v.bounds.origin.x
        p.y -= v.frame.origin.y - v.bounds.origin.y
      }
      return p
    }
    if source === self { return point }
    let inWin = source._convertPointToView(point, target: nil)
    return _convertPointFromView(inWin, source: nil)
  }

  public func convert(_ point: CGPoint, to view: UIView?) -> CGPoint {
    _convertPointToView(point, target: view)
  }

  public func convert(_ point: CGPoint, from view: UIView?) -> CGPoint {
    _convertPointFromView(point, source: view)
  }

  public func convert(_ rect: CGRect, to view: UIView?) -> CGRect {
    CGRect(origin: _convertPointToView(rect.origin, target: view), size: rect.size)
  }

  public func convert(_ rect: CGRect, from view: UIView?) -> CGRect {
    CGRect(origin: _convertPointFromView(rect.origin, source: view), size: rect.size)
  }

  public func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint {
    _convertPointToView(point, target: coordinateSpace as? UIView)
  }

  public func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint {
    _convertPointFromView(point, source: coordinateSpace as? UIView)
  }

  public func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect {
    CGRect(origin: convert(rect.origin, to: coordinateSpace), size: rect.size)
  }

  public func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect {
    CGRect(origin: convert(rect.origin, from: coordinateSpace), size: rect.size)
  }

  open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.contains(point)
  }

  open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
    guard self.point(inside: point, with: event) else { return nil }
    for sub in subviews.reversed() {
      let local = sub.convert(point, from: self)
      if let hit = sub.hitTest(local, with: event) {
        return hit
      }
    }
    return self
  }

  @discardableResult
  open func endEditing(_ force: Bool) -> Bool {
    if isFirstResponder {
      _ = resignFirstResponder()
      return true
    }
    for sub in subviews {
      if sub.endEditing(force) { return true }
    }
    return false
  }

  // MARK: - UIView Class Animation Helpers

  nonisolated(unsafe) private static var animationsEnabledFlag = true
  public static var areAnimationsEnabled: Bool { animationsEnabledFlag }

  public static func setAnimationsEnabled(_ enabled: Bool) {
    animationsEnabledFlag = enabled
  }

  public static func performWithoutAnimation(_ actionsWithoutAnimation: () -> Void) {
    let prev = animationsEnabledFlag
    animationsEnabledFlag = false
    defer { animationsEnabledFlag = prev }
    actionsWithoutAnimation()
  }

  public static func animate(
    withDuration duration: TimeInterval,
    animations: @escaping () -> Void
  ) {
    animations()
  }

  public static func animate(
    withDuration duration: TimeInterval,
    animations: @escaping () -> Void,
    completion: ((Bool) -> Void)? = nil
  ) {
    animations()
    completion?(true)
  }

  public static func animate(
    withDuration duration: TimeInterval,
    delay: TimeInterval,
    options: AnimationOptions = [],
    animations: @escaping () -> Void,
    completion: ((Bool) -> Void)? = nil
  ) {
    animations()
    completion?(true)
  }

  public static func animate(
    withDuration duration: TimeInterval,
    delay: TimeInterval,
    usingSpringWithDamping dampingRatio: CGFloat,
    initialSpringVelocity velocity: CGFloat,
    options: AnimationOptions = [],
    animations: @escaping () -> Void,
    completion: ((Bool) -> Void)? = nil
  ) {
    animations()
    completion?(true)
  }

  public static func transition(
    with view: UIView,
    duration: TimeInterval,
    options: AnimationOptions = [],
    animations: (() -> Void)?,
    completion: ((Bool) -> Void)? = nil
  ) {
    animations?()
    completion?(true)
  }
}

// MARK: - UIViewPropertyAnimator

@MainActor
open class UIViewPropertyAnimator: NSObject {
  public enum State: Int, Sendable {
    case inactive = 0
    case active = 1
    case stopped = 2
  }

  public let duration: TimeInterval
  public private(set) var state: State = .inactive
  public var isRunning: Bool = false
  public var isReversed: Bool = false
  public var fractionComplete: CGFloat = 0
  private var animationBlocks: [() -> Void] = []
  private var completionBlocks: [(Int) -> Void] = []

  public init(duration: TimeInterval, curve: UIView.AnimationCurve, animations: (() -> Void)? = nil) {
    self.duration = duration
    if let animations { self.animationBlocks = [animations] }
    super.init()
  }

  public init(duration: TimeInterval, dampingRatio ratio: CGFloat, animations: (() -> Void)? = nil) {
    self.duration = duration
    if let animations { self.animationBlocks = [animations] }
    super.init()
  }

  public func addAnimations(_ animation: @escaping () -> Void, delayFactor: CGFloat = 0) {
    animationBlocks.append(animation)
  }

  public func addCompletion(_ completion: @escaping (Int) -> Void) {
    completionBlocks.append(completion)
  }

  public func startAnimation() {
    state = .active
    isRunning = true
    for block in animationBlocks { block() }
    fractionComplete = 1.0
    isRunning = false
    state = .inactive
    for done in completionBlocks { done(0) }
  }

  public func pauseAnimation() {
    isRunning = false
  }

  public func stopAnimation(_ withoutFinishing: Bool) {
    isRunning = false
    state = withoutFinishing ? .stopped : .inactive
  }

  public func finishAnimation(at finalPosition: Int) {
    state = .inactive
    for done in completionBlocks { done(finalPosition) }
  }
}

// MARK: - UIVisualEffectView

open class UIVisualEffect: NSObject, NSCopying, @unchecked Sendable {
  public override init() { super.init() }
  open func copy(with zone: NSZone? = nil) -> Any { self }
}

open class UIBlurEffect: UIVisualEffect, @unchecked Sendable {
  public enum Style: Int, Sendable {
    case extraLight = 0
    case light = 1
    case dark = 2
    case regular = 4
    case prominent = 5
    case systemUltraThinMaterial = 6
    case systemThinMaterial = 7
    case systemMaterial = 8
    case systemThickMaterial = 9
    case systemChromeMaterial = 10
    case systemUltraThinMaterialLight = 11
    case systemThinMaterialLight = 12
    case systemMaterialLight = 13
    case systemThickMaterialLight = 14
    case systemChromeMaterialLight = 15
    case systemUltraThinMaterialDark = 16
    case systemThinMaterialDark = 17
    case systemMaterialDark = 18
    case systemThickMaterialDark = 19
    case systemChromeMaterialDark = 20
  }

  public let style: Style

  public init(style: Style) {
    self.style = style
    super.init()
  }
}

open class UIVibrancyEffect: UIVisualEffect, @unchecked Sendable {
  public let blurEffect: UIBlurEffect
  public init(blurEffect: UIBlurEffect) {
    self.blurEffect = blurEffect
    super.init()
  }
}

@MainActor
open class UIVisualEffectView: UIView {
  public var effect: UIVisualEffect?
  public let contentView: UIView = UIView(frame: .zero)

  public init(effect: UIVisualEffect?) {
    self.effect = effect
    super.init(frame: .zero)
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(contentView)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(contentView)
  }

  open override func layoutSubviews() {
    super.layoutSubviews()
    contentView.frame = bounds
  }
}

// MARK: - UIStackView

@MainActor
open class UIStackView: UIView {
  public enum Distribution: Int, Sendable {
    case fill = 0
    case fillEqually = 1
    case fillProportionally = 2
    case equalSpacing = 3
    case equalCentering = 4
  }

  public enum Alignment: Int, Sendable {
    case fill = 0
    case leading = 1
    case top = 1_001
    case firstBaseline = 2
    case center = 3
    case trailing = 4
    case bottom = 4_001
    case lastBaseline = 5
  }

  public static let spacingUseDefault: CGFloat = .greatestFiniteMagnitude
  public static let spacingUseSystem: CGFloat = -.greatestFiniteMagnitude

  public var axis: NSLayoutConstraint.Axis = .horizontal {
    didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
  }
  public var distribution: Distribution = .fill {
    didSet { setNeedsLayout() }
  }
  public var alignment: Alignment = .fill {
    didSet { setNeedsLayout() }
  }
  public var spacing: CGFloat = 0 {
    didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
  }
  public var isBaselineRelativeArrangement: Bool = false
  public var isLayoutMarginsRelativeArrangement: Bool = false {
    didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
  }

  public private(set) var arrangedSubviews: [UIView] = []
  private var customSpacings: [ObjectIdentifier: CGFloat] = [:]

  public init(arrangedSubviews views: [UIView]) {
    super.init(frame: .zero)
    for v in views {
      addArrangedSubview(v)
    }
  }

  public override init(frame: CGRect) {
    super.init(frame: frame)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public func addArrangedSubview(_ view: UIView) {
    if !arrangedSubviews.contains(where: { $0 === view }) {
      arrangedSubviews.append(view)
    }
    if view.superview !== self {
      addSubview(view)
    }
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  public func insertArrangedSubview(_ view: UIView, at stackIndex: Int) {
    arrangedSubviews.removeAll { $0 === view }
    let idx = min(max(0, stackIndex), arrangedSubviews.count)
    arrangedSubviews.insert(view, at: idx)
    if view.superview !== self {
      addSubview(view)
    }
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  public func removeArrangedSubview(_ view: UIView) {
    arrangedSubviews.removeAll { $0 === view }
    customSpacings.removeValue(forKey: ObjectIdentifier(view))
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  public func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) {
    if spacing == Self.spacingUseDefault {
      customSpacings.removeValue(forKey: ObjectIdentifier(arrangedSubview))
    } else {
      customSpacings[ObjectIdentifier(arrangedSubview)] = spacing
    }
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  public func customSpacing(after arrangedSubview: UIView) -> CGFloat {
    customSpacings[ObjectIdentifier(arrangedSubview)] ?? Self.spacingUseDefault
  }

  private func gap(after view: UIView) -> CGFloat {
    if let custom = customSpacings[ObjectIdentifier(view)] {
      return custom == Self.spacingUseSystem ? 8 : custom
    }
    return spacing == Self.spacingUseSystem ? 8 : spacing
  }

  open override var intrinsicContentSize: CGSize {
    let visible = arrangedSubviews.filter { !$0.isHidden }
    guard !visible.isEmpty else { return .zero }
    let insets = isLayoutMarginsRelativeArrangement ? layoutMargins : .zero
    var mainTotal: CGFloat = 0
    var crossMax: CGFloat = 0

    for (idx, v) in visible.enumerated() {
      let sz = v.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
      let w = max(0, sz.width)
      let h = max(0, sz.height)
      if axis == .horizontal {
        mainTotal += w
        crossMax = max(crossMax, h)
      } else {
        mainTotal += h
        crossMax = max(crossMax, w)
      }
      if idx + 1 < visible.count {
        mainTotal += gap(after: v)
      }
    }

    if axis == .horizontal {
      return CGSize(
        width: mainTotal + insets.left + insets.right,
        height: crossMax + insets.top + insets.bottom
      )
    } else {
      return CGSize(
        width: crossMax + insets.left + insets.right,
        height: mainTotal + insets.top + insets.bottom
      )
    }
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    intrinsicContentSize
  }

  open override func layoutSubviews() {
    super.layoutSubviews()
    let visible = arrangedSubviews.filter { !$0.isHidden }
    guard !visible.isEmpty else { return }

    let area = isLayoutMarginsRelativeArrangement ? bounds.inset(by: layoutMargins) : bounds
    let mainAvailable = axis == .horizontal ? area.width : area.height
    let crossAvailable = axis == .horizontal ? area.height : area.width

    var gaps: [CGFloat] = []
    var totalGaps: CGFloat = 0
    for idx in 0..<(visible.count - 1) {
      let g = gap(after: visible[idx])
      gaps.append(g)
      totalGaps += g
    }

    let naturalSizes: [CGSize] = visible.map { v in
      let proposal = axis == .horizontal
        ? CGSize(width: CGFloat.greatestFiniteMagnitude, height: crossAvailable)
        : CGSize(width: crossAvailable, height: CGFloat.greatestFiniteMagnitude)
      let fitted = v.sizeThatFits(proposal)
      return CGSize(
        width: max(0, fitted.width > 0 ? fitted.width : v.frame.width),
        height: max(0, fitted.height > 0 ? fitted.height : v.frame.height)
      )
    }

    var mainLengths: [CGFloat] = naturalSizes.map { axis == .horizontal ? $0.width : $0.height }
    let naturalSum = mainLengths.reduce(0, +)
    let remaining = mainAvailable - totalGaps

    switch distribution {
    case .fillEqually:
      let each = max(0, remaining / CGFloat(visible.count))
      mainLengths = Array(repeating: each, count: visible.count)
    case .fillProportionally:
      if naturalSum > 0 {
        mainLengths = mainLengths.map { max(0, remaining * ($0 / naturalSum)) }
      }
    case .fill:
      let delta = remaining - naturalSum
      if abs(delta) > 0.5 {
        // Stretch the view with the lowest hugging priority (last tie-breaker).
        var targetIdx = visible.count - 1
        var lowestPriority: Float = .greatestFiniteMagnitude
        for (idx, v) in visible.enumerated() {
          let p = v.contentHuggingPriority(for: axis).rawValue
          if p <= lowestPriority {
            lowestPriority = p
            targetIdx = idx
          }
        }
        mainLengths[targetIdx] = max(0, mainLengths[targetIdx] + delta)
      }
    case .equalSpacing, .equalCentering:
      if visible.count > 1 && remaining > naturalSum {
        let evenGap = (mainAvailable - naturalSum) / CGFloat(visible.count - 1)
        gaps = Array(repeating: evenGap, count: visible.count - 1)
      }
    }

    var cursor = axis == .horizontal ? area.minX : area.minY
    for (idx, v) in visible.enumerated() {
      let mainLen = mainLengths[idx]
      let naturalCross = axis == .horizontal ? naturalSizes[idx].height : naturalSizes[idx].width
      let crossLen: CGFloat
      let crossPos: CGFloat
      switch alignment {
      case .fill:
        crossLen = crossAvailable
        crossPos = axis == .horizontal ? area.minY : area.minX
      case .leading, .top, .firstBaseline:
        crossLen = min(crossAvailable, naturalCross)
        crossPos = axis == .horizontal ? area.minY : area.minX
      case .trailing, .bottom, .lastBaseline:
        crossLen = min(crossAvailable, naturalCross)
        crossPos = (axis == .horizontal ? area.maxY : area.maxX) - crossLen
      case .center:
        crossLen = min(crossAvailable, naturalCross)
        crossPos = (axis == .horizontal ? area.minY : area.minX) + (crossAvailable - crossLen) * 0.5
      }

      if axis == .horizontal {
        v.frame = CGRect(x: cursor, y: crossPos, width: mainLen, height: crossLen)
      } else {
        v.frame = CGRect(x: crossPos, y: cursor, width: crossLen, height: mainLen)
      }
      cursor += mainLen + (idx < gaps.count ? gaps[idx] : 0)
    }
  }
}
