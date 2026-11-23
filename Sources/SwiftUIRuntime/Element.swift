/// A stable handle to one mounted element.
///
/// IDs are allocated by the renderer and survive re-evaluation when an element
/// keeps its identity. The native backend uses them as keys into its view map.

/// What an element is.
///
/// Kind is part of an element's diff identity: changing a `Text` into a
/// `Button` replaces the native control.

/// Everything about an element that can change without replacing the native
/// view. The native backend diffs these values; `.id(_:)` and `.onTapGesture`
/// are carried separately.

/// The engine's render tree node.

/// Structural identity used by the diff.
///
/// Keys are scoped to a sibling list. An explicit `.id` wins; otherwise the
/// child's position and kind determine identity. NodeID is the global handle.

/// Removes fragments and empty views from the tree and gives every child a
/// contiguous sibling index.

/// Assigns diff keys top-down and children left-to-right.

/// Resolves inherited `.foregroundColor` and `.disabled` values.
///
/// Foreground is inherited by every descendant; a value set on a descendant
/// wins. Disabled has the same shape, with `.disabled(false)` re-enabling a
/// subtree. This happens before diffing so the backend only sees effective
/// values.

/// Collects the current tap handlers keyed by node id.
import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public struct NodeID: Hashable, Comparable, CustomStringConvertible {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func < (lhs: NodeID, rhs: NodeID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var description: String { "#\(rawValue)" }
}
public enum ElementKind: Hashable, CustomStringConvertible {
  /// A transparent fragment produced by a multi-child builder block. It never
  /// reaches a backend; containers flatten it away.
  case fragment
  /// A native container with `row` or `column` layout.
  case container(Axis)
  /// The element created by `.padding(...)`. It is a plain native container
  /// with padding and one stretched child.
  case padding
  case frame, layer, shape, styledButton
  case presentation, grid, zStack, scroll, geometry, customLayout, textField, image, path, gradient
  case hostedView
  case text
  case button
  case spacer
  case empty

  var identityName: String {
    switch self {
    case .fragment: return "Fragment"
    case .container(.horizontal): return "HStack"
    case .container(.vertical): return "VStack"
    case .padding: return "Padding"
    case .presentation: return "Popover"
    case .grid: return "Grid"
    case .zStack: return "ZStack"
    case .scroll: return "ScrollView"
    case .geometry: return "GeometryReader"
    case .customLayout: return "Layout"
    case .textField: return "TextField"
    case .image: return "Image"
    case .path: return "Path"
    case .gradient: return "Gradient"
    case .hostedView: return "HostedView"
    case .frame: return "Frame"
    case .layer: return "Layer"
    case .shape: return "Shape"
    case .styledButton: return "StyledButton"
    case .text: return "Text"
    case .button: return "Button"
    case .spacer: return "Spacer"
    case .empty: return "Empty"
    }
  }

  public var description: String { identityName }
}
public struct SemanticControl: Equatable {
  public struct AlertActionItem: Equatable {
    public var title: String
    public var role: String // "default", "cancel", "destructive"
    public var enabled: Bool

    public init(title: String, role: String = "default", enabled: Bool = true) {
      self.title = title
      self.role = role
      self.enabled = enabled
    }
  }

  public var kind: String
  public var boolValue: Bool = false
  public var doubleValue: Double = 0
  public var minValue: Double = 0
  public var maxValue: Double = 1
  public var stepValue: Double = 0
  public var intValue: Int = 0
  public var items: [String] = []
  public var itemIcons: [String] = []
  public var title: String = ""
  public var subtitle: String = ""
  public var styleName: String = ""
  public var tint: Color? = nil
  public var canGoBack: Bool = false
  public var isIndeterminate: Bool = false
  public var disabledIndices: [Int] = []
  public var alertActions: [AlertActionItem] = []

  public init(
    kind: String,
    boolValue: Bool = false,
    doubleValue: Double = 0,
    minValue: Double = 0,
    maxValue: Double = 1,
    stepValue: Double = 0,
    intValue: Int = 0,
    items: [String] = [],
    itemIcons: [String] = [],
    title: String = "",
    subtitle: String = "",
    styleName: String = "",
    tint: Color? = nil,
    canGoBack: Bool = false,
    isIndeterminate: Bool = false,
    disabledIndices: [Int] = [],
    alertActions: [AlertActionItem] = []
  ) {
    self.kind = kind
    self.boolValue = boolValue
    self.doubleValue = doubleValue
    self.minValue = minValue
    self.maxValue = maxValue
    self.stepValue = stepValue
    self.intValue = intValue
    self.items = items
    self.itemIcons = itemIcons
    self.title = title
    self.subtitle = subtitle
    self.styleName = styleName
    self.tint = tint
    self.canGoBack = canGoBack
    self.isIndeterminate = isIndeterminate
    self.disabledIndices = disabledIndices
    self.alertActions = alertActions
  }
}

public struct NodeProps: Equatable {
  public var text: String = ""
  public var renderedText: String? = nil
  public var idealWidth: Double? = nil, idealHeight: Double? = nil
  public var tracking: Double = 0
  public var textAlignment: TextAlignment = .leading
  public var truncationMode: Text.TruncationMode = .tail
  public var dash: [Double] = []
  public var offsetX: Double = 0, offsetY: Double = 0
  public var scaleX: Double = 1, scaleY: Double = 1, rotation: Double = 0
  public var zIndex: Double = 0
  public var underline = false, aspectFit = false, hasAspectConstraint = false
  public var selectableText = false
  public var aspectRatio: Double? = nil
  package var intrinsicImageWidth: Double? = nil, intrinsicImageHeight: Double? = nil
  public var transition: AnyTransition? = nil
  public var hitTesting = true
  public var fixedWidth = false, fixedHeight = false
  public var showsScrollIndicators = true
  public var gridUnsizedAxes: Axis.Set = []
  public var scrollAxes: Axis.Set = .vertical
  public var scrollOffset = Point.zero
  public var scrollContentInsets: EdgeInsets = .zero
  package var isLazyContainer = false
  public var placeholder = ""
  public var secure = false, multiline = false
  package var plainTextField = false
  public var imagePath = ""
  public var imageTemplate = false
  public var path = Path()
  public var gradient: LinearGradient.Data? = nil
  public var accessibilityLabel = "", accessibilityValue = "", accessibilityHidden = false
  public var keyboardShortcut: KeyboardShortcut? = nil
  public var coordinateSpace: AnyHashable? = nil
  public var focusable = false
  public var accessibilityTraits = 0
  public var accessibilityIdentifier = ""

  public var font: Font? = nil
  public var lineLimit: Int? = nil
  public var lineSpacing: Double = 0
  public var minWidth: Double? = nil
  public var minHeight: Double? = nil
  public var maxWidth: Double? = nil
  public var maxHeight: Double? = nil
  public var fillWidth = false
  public var fillHeight = false
  public var alignment: Alignment = .center
  public var layerBehind = false
  public var cornerRadius: Double = 0
  public var hitRadius: Double = 0
  public var clipped = false
  public var borderColor: Color = .clear
  public var borderWidth: Double = 0
  public var opacity: Double = 1
  public var blurRadius: Double = 0
  public var brightness: Double = 0
  public var contrast: Double = 1
  public var compositingGroup: Bool = false
  public var layoutPriority: Double = 0
  public var shadows: [Shadow] = []
  public var animation: Animation? = nil
  package var animationDisabled = false
  package var animationPass = 0
  public var presentationBackgroundEnabled = false
  public var focusRequested = false
  public var help = ""
  /// Effective visibility. `.hidden()` sets this to false.
  public var visible: Bool = true
  /// Effective enabled state, after `.disabled(...)` inheritance is resolved.
  public var enabled: Bool = true
  /// The explicit value from `.disabled(...)`, kept so environment resolution
  /// can distinguish "not set" from "set to false".
  public var disabledOverride: Bool? = nil
  /// Optional color scheme override set by `.preferredColorScheme` / `.colorScheme`.
  public var colorSchemeOverride: ColorScheme? = nil
  public var background: Color? = nil
  /// Effective foreground color, after environment inheritance is resolved.
  public var foreground: Color? = nil
  public var padding: EdgeInsets = .zero
  public var frameWidth: Double? = nil
  public var frameHeight: Double? = nil
  public var spacing: Double = 0
  public var horizontalAlignment: HorizontalAlignment = .center
  public var verticalAlignment: VerticalAlignment = .center
  /// Main-axis share for `Spacer`; 0 means fixed.
  public var flex: Double = 0
  /// Minimum main-axis length for `Spacer(minLength:)`.
  public var spacerMinLength: Double = 0
  /// Optional semantic control metadata used by native platform hosts (e.g. Android Compose).
  public var semanticControl: SemanticControl? = nil
  public var isLazyPlaceholder: Bool = false

  /// Compares only properties that affect visual rendering, ignoring metadata
  /// such as `animationPass`, accessibility labels, tooltips, and focus flags
  /// that can differ across passes without changing pixels.
  public func visualEquals(_ other: NodeProps) -> Bool {
    if self == other { return true }
    var lhs = self
    var rhs = other
    lhs.animationPass = 0
    rhs.animationPass = 0
    lhs.animation = nil
    rhs.animation = nil
    lhs.animationDisabled = false
    rhs.animationDisabled = false
    lhs.focusRequested = false
    rhs.focusRequested = false
    lhs.focusable = false
    rhs.focusable = false
    lhs.hitTesting = true
    rhs.hitTesting = true
    lhs.help = ""
    rhs.help = ""
    lhs.accessibilityLabel = ""
    rhs.accessibilityLabel = ""
    lhs.accessibilityValue = ""
    rhs.accessibilityValue = ""
    lhs.accessibilityHidden = false
    rhs.accessibilityHidden = false
    lhs.accessibilityTraits = 0
    rhs.accessibilityTraits = 0
    lhs.accessibilityIdentifier = ""
    rhs.accessibilityIdentifier = ""
    lhs.keyboardShortcut = nil
    rhs.keyboardShortcut = nil
    lhs.coordinateSpace = nil
    rhs.coordinateSpace = nil
    lhs.disabledOverride = nil
    rhs.disabledOverride = nil
    lhs.colorSchemeOverride = nil
    rhs.colorSchemeOverride = nil
    lhs.semanticControl = nil
    rhs.semanticControl = nil
    lhs.transition = nil
    rhs.transition = nil
    return lhs == rhs
  }

  public init() {}
}
public struct Element {
  public internal(set) var id: NodeID
  public var kind: ElementKind
  public var props: NodeProps
  public var children: [Element]
  public internal(set) var frame: Rect

  /// Diff identity, assigned after evaluation.
  var key: ElementKey = .root
  /// Assigned only within one layout pass, including dynamically built geometry.
  var layoutID: Int = 0
  var evaluationID: Int = 0
  var evaluationRevision: Int = 0
  package var reusesLayout = false
  package var hasOverflow = false
  var hasDynamicLayout = false
  var hasPresentation = false
  package var hasActivePresentation = false
  package var hasLayoutAnimation = false
  var hasScopedAnimation = false
  var hasPreferences = false
  var layoutContext: [AnyHashable: CGPoint] = [:]
  var customLayoutFrames: [CGRect] = []
  var geometrySnapshot: GeometrySnapshot?
  /// The value from `.id(_:)`, if any.
  var explicitID: AnyHashable? = nil
  /// The action of a `Button`, or of `.onTapGesture` on a Button.
  package var action: (() -> Void)? = nil
  var hoverAction: ((Bool) -> Void)? = nil
  var focusAction: ((Bool) -> Void)? = nil
  public var pathBuilder: ((CGRect) -> Path)? = nil
  public var clipPathBuilder: ((CGRect) -> Path)? = nil
  var horizontalGuide: ((ViewDimensions) -> CGFloat)? = nil
  var verticalGuide: ((ViewDimensions) -> CGFloat)? = nil
  var preferences: [ObjectIdentifier: PreferenceValue] = [:]
  var anchorPreferences: [(CGRect, inout [ObjectIdentifier: PreferenceValue]) -> Void] = []
  var preferenceTransforms: [(inout [ObjectIdentifier: PreferenceValue]) -> Void] = []
  var preferenceAction: (([ObjectIdentifier: PreferenceValue]) -> Void)? = nil
  var geometryBuilder: ((CGRect) -> Element)? = nil
  var layout: (any _LayoutBridge)? = nil
  package var hostedViewAdapter: (any AnyObject)? = nil
  package var hostedViewMeasure: ((ProposedViewSize) -> Size)? = nil
  package var hostedViewHitTest: ((Int, CGPoint, EventModifiers) -> Bool)? = nil
  package var hostedViewMouseInput: ((Int, CGPoint, EventModifiers) -> Bool)? = nil
  var textAction: ((String) -> Void)? = nil
  var submitAction: (() -> Void)? = nil
  var dragAction: ((DragGesture.Value, Bool) -> Void)? = nil
  var highPriorityAction: (() -> Void)? = nil
  var simultaneousActions: [() -> Void] = []
  var highPriorityDragAction: ((DragGesture.Value, Bool) -> Void)? = nil
  var simultaneousDragActions: [(DragGesture.Value, Bool) -> Void] = []
  struct LongPressConfig {
    let minimumDuration: Double
    let maximumDistance: Double
    let onPressingChanged: ((Bool) -> Void)?
    let onEnded: () -> Void
  }
  var longPressAction: LongPressConfig? = nil
  var tapLocationAction: ((CGPoint) -> Void)?
  var doubleTapLocationAction: ((CGPoint) -> Void)?
  var doubleTapAction: (() -> Void)? = nil
  var continuousHoverAction: ((HoverPhase) -> Void)? = nil
  var continuousHoverGlobal = false
  var keyAction: ((KeyPress) -> KeyPress.Result)? = nil
  var scrollTarget: ScrollTarget?
  var completeScrollTarget: (() -> Void)?
  var scrollAction: ((Point) -> Void)? = nil
  var scrollGeometryHandlers: [(ScrollGeometry) -> Void] = []
  var scrollPhaseHandlers: [(ScrollPhase, ScrollPhase) -> Void] = []
  var geometryChangeHandlers: [(GeometryProxy) -> Void] = []
  var lazyCacheKey: AnyHashable? = nil
  package var tagValue: AnyHashable? = nil
  // Only ScrollView's private offset can use the geometry-only update path.
  var scrollStateKey: StateKey? = nil
  var secondaryAction: ((CGPoint) -> Void)? = nil
  var dismissOnAction = false
  var presentationCentered = false
  var presentationPoint: CGPoint? = nil
  var presentationEdge: Edge? = nil
  var presentationPopoverChrome = false
  var presentationColorScheme: ColorScheme = .light
  var dismissPresentation: (() -> Void)? = nil
  var pressedAction: ((Bool) -> Void)? = nil
  package var semanticBoolAction: ((Bool) -> Void)? = nil
  package var semanticDoubleAction: ((Double, Bool) -> Void)? = nil
  package var semanticIntAction: ((Int) -> Void)? = nil
  package var semanticIncrementAction: (() -> Void)? = nil
  package var semanticDecrementAction: (() -> Void)? = nil
  package var semanticBackAction: (() -> Void)? = nil
  package var semanticAlertActions: [() -> Void] = []
  package var tabItemTitle: String? = nil
  package var tabItemIcon: String? = nil
  package var tabItemContent: AnyView? = nil

  package init(
    id: NodeID = NodeID(rawValue: 0),
    kind: ElementKind,
    props: NodeProps = NodeProps(),
    children: [Element] = [],
    frame: Rect = .zero,
    explicitID: AnyHashable? = nil,
    action: (() -> Void)? = nil
  ) {
    self.id = id
    self.kind = kind
    self.props = props
    self.children = children
    self.frame = frame
    self.explicitID = explicitID
    self.action = action
  }

  public var needsNativeFocus: Bool { props.focusable || focusAction != nil }

  /// Effective silhouette corner radius for `.shadow(...)`, walking through
  /// transparent `.background`, `.overlay`, and `.frame` wrappers whose filled,
  /// stroked, or clipped shape lives on a coextensive child.
  public var shadowCornerRadius: Double {
    silhouetteCornerRadius(matching: frame) ?? props.cornerRadius
  }

  private func silhouetteCornerRadius(matching bounds: Rect) -> Double? {
    guard props.visible, props.opacity > 0,
      abs(frame.minX - bounds.minX) < 0.5,
      abs(frame.minY - bounds.minY) < 0.5,
      abs(frame.width - bounds.width) < 0.5,
      abs(frame.height - bounds.height) < 0.5
    else { return nil }
    if props.clipped { return props.cornerRadius }
    let hasFill = (props.background?.opacity ?? 0) > 0
    let hasStroke = props.borderWidth > 0 && props.borderColor.opacity > 0
    if hasFill || hasStroke { return props.cornerRadius }
    var resolved: Double?
    for child in children {
      if let candidate = child.silhouetteCornerRadius(matching: bounds) {
        resolved = resolved.map { min($0, candidate) } ?? candidate
      }
    }
    return resolved
  }

  public var acceptsPointerInput: Bool { handlesPointerInput }

  package var handlesPointerInput: Bool {
    action != nil || doubleTapAction != nil || dragAction != nil || secondaryAction != nil
  }

  package var supportsTranslation: Bool {
    if !hasDynamicLayout { return true }
    if (kind == .presentation && children.count > 1) || layout?.translatesWithBounds == false
      || geometrySnapshot?.dependsOnPosition == true
    {
      return false
    }
    return children.allSatisfy(\.supportsTranslation)
  }

  mutating func updateOverflow() {
    if props.clipped {
      hasOverflow = false
      return
    }
    if kind == .scroll {
      hasOverflow = true
      return
    }
    if children.isEmpty {
      hasOverflow = false
      return
    }
    let r = frame
    hasOverflow = children.contains { child in
      guard child.props.visible else { return false }
      if child.hasOverflow { return true }
      let c = child.frame
      return c.minX < r.minX || c.minY < r.minY || c.maxX > r.maxX || c.maxY > r.maxY
    }
  }

  public var isContainer: Bool {
    switch kind {
    case .container, .padding, .frame, .layer, .styledButton, .presentation, .grid, .zStack,
      .scroll, .geometry, .customLayout:
      return true
    default:
      return false
    }
  }
}
enum ElementKey: Hashable {
  case root
  case explicit(AnyHashable)
  case structural(ElementKind, Int)
}
func normalize(_ element: Element, previous: Element? = nil) -> Element {
  if let previous, element.scrollTarget == nil, element.evaluationID != 0,
    element.evaluationID == previous.evaluationID,
    element.evaluationRevision == previous.evaluationRevision,
    element.kind == previous.kind
  {
    return previous
  }
  var result = element
  if element.kind == .layer {
    result.children = element.children.enumerated().map { index, child in
      normalize(
        child, previous: previous.flatMap { index < $0.children.count ? $0.children[index] : nil })
    }
    return result
  }
  if result.children.isEmpty && element.kind != .fragment { return result }
  var children: [Element] = []
  children.reserveCapacity(element.children.count)
  for (index, child) in element.children.enumerated() {
    let normalized = normalize(
      child, previous: previous.flatMap { index < $0.children.count ? $0.children[index] : nil })
    switch normalized.kind {
    case .fragment: children.append(contentsOf: normalized.children)
    case .empty: break
    default: children.append(normalized)
    }
  }
  result.children = children
  if result.kind == .fragment {
    switch result.children.count {
    case 0:
      return Element(kind: .empty)
    case 1:
      var single = result.children[0]
      if single.props.lineLimit == nil, let limit = result.props.lineLimit {
        single.props.lineLimit = limit
      }
      if single.props.lineSpacing == 0, result.props.lineSpacing != 0 {
        single.props.lineSpacing = result.props.lineSpacing
      }
      if single.props.foreground == nil, let fg = result.props.foreground {
        single.props.foreground = fg
      }
      if single.props.font == nil, let font = result.props.font {
        single.props.font = font
      }
      if single.props.truncationMode == .tail, result.props.truncationMode != .tail {
        single.props.truncationMode = result.props.truncationMode
      }
      if result.props.opacity != 1 { single.props.opacity *= result.props.opacity }
      if single.props.disabledOverride == nil, let disabled = result.props.disabledOverride {
        single.props.disabledOverride = disabled
      }
      if single.props.colorSchemeOverride == nil, let scheme = result.props.colorSchemeOverride {
        single.props.colorSchemeOverride = scheme
      }
      if result.props.fixedWidth { single.props.fixedWidth = true }
      if result.props.fixedHeight { single.props.fixedHeight = true }
      if single.props.layoutPriority == 0, result.props.layoutPriority != 0 {
        single.props.layoutPriority = result.props.layoutPriority
      }
      if single.props.zIndex == 0, result.props.zIndex != 0 {
        single.props.zIndex = result.props.zIndex
      }
      if !result.props.hitTesting { single.props.hitTesting = false }
      if single.props.help.isEmpty, !result.props.help.isEmpty {
        single.props.help = result.props.help
      }
      if single.explicitID == nil { single.explicitID = result.explicitID }
      if single.tagValue == nil { single.tagValue = result.tagValue }
      for (k, v) in result.preferences {
        if let existing = single.preferences[k] {
          single.preferences[k] = PreferenceValue(value: v.reduce(existing.value, v.value), reduce: v.reduce)
        } else {
          single.preferences[k] = v
        }
      }
      single.anchorPreferences.append(contentsOf: result.anchorPreferences)
      single.preferenceTransforms.append(contentsOf: result.preferenceTransforms)
      if let outerAction = result.preferenceAction {
        let innerAction = single.preferenceAction
        single.preferenceAction = { values in
          innerAction?(values)
          outerAction(values)
        }
      }
      return single
    default:
      var props = result.props
      props.spacing = 0
      var box = Element(kind: .container(.vertical), props: props, children: result.children)
      box.preferences = result.preferences
      box.anchorPreferences = result.anchorPreferences
      box.preferenceTransforms = result.preferenceTransforms
      box.preferenceAction = result.preferenceAction
      return box
    }
  }
  return result
}
func assignKeys(_ element: inout Element, index: Int = 0) {
  let expected: ElementKey =
    element.explicitID.map(ElementKey.explicit)
    ?? .structural(element.kind, index)
  if element.reusesLayout && element.key == expected { return }
  element.key = expected
  for childIndex in element.children.indices {
    assignKeys(&element.children[childIndex], index: childIndex)
  }
}
func resolveEnvironment(
  _ element: inout Element,
  colorScheme: ColorScheme = EnvironmentValues.current.colorScheme,
  inheritedForeground: Color? = nil,
  inheritedDisabled: Bool = false,
  inheritedOpacity: Double = 1,
  inheritedBlurRadius: Double = 0,
  inheritedVisible: Bool = true,
  inheritedLineLimit: Int? = nil,
  inheritedLineSpacing: Double = 0,
  previous: Element? = nil
) {
  let effectiveScheme = element.props.colorSchemeOverride ?? colorScheme
  let baseInheritedForeground: Color?
  if let overrideScheme = element.props.colorSchemeOverride {
    baseInheritedForeground = overrideScheme == .dark ? Color.primary.resolved(in: .dark) : nil
  } else {
    baseInheritedForeground =
      inheritedForeground ?? (effectiveScheme == .dark ? Color.primary.resolved(in: .dark) : nil)
  }
  let foreground = (element.props.foreground ?? baseInheritedForeground)?.resolved(in: effectiveScheme)
  let disabled = element.props.disabledOverride ?? inheritedDisabled

  element.props.foreground = foreground
  element.props.background = element.props.background?.resolved(in: effectiveScheme)
  element.props.borderColor = element.props.borderColor.resolved(in: effectiveScheme)
  if let grad = element.props.gradient {
    element.props.gradient = LinearGradient.Data(
      kind: grad.kind,
      colors: grad.colors.map { $0.resolved(in: effectiveScheme) },
      locations: grad.locations,
      start: grad.start,
      end: grad.end,
      startRadius: grad.startRadius,
      endRadius: grad.endRadius,
      startAngle: grad.startAngle,
      endAngle: grad.endAngle
    )
  }
  element.props.enabled = !disabled
  element.props.visible = element.props.visible && inheritedVisible
  element.props.opacity *= inheritedOpacity
  element.props.blurRadius = max(element.props.blurRadius, inheritedBlurRadius)
  element.props.lineLimit = element.props.lineLimit ?? inheritedLineLimit
  if element.props.lineSpacing == 0 { element.props.lineSpacing = inheritedLineSpacing }

  if let previous, element.scrollTarget == nil, element.evaluationID != 0,
    element.evaluationID == previous.evaluationID,
    element.evaluationRevision == previous.evaluationRevision,
    !previous.hasPresentation, !previous.hasLayoutAnimation, !previous.hasScopedAnimation
  {
    var oldProps = previous.props
    oldProps.renderedText = element.props.renderedText
    oldProps.animation = nil
    oldProps.animationDisabled = false
    oldProps.animationPass = 0
    var candidateProps = element.props
    if candidateProps.animationPass != AnimationContext.renderPass {
      candidateProps.animation = nil
      candidateProps.animationDisabled = false
      candidateProps.animationPass = 0
    }
    if oldProps == candidateProps {
      element = previous
      element.props.animation = nil
      element.props.animationDisabled = false
      element.props.animationPass = 0
      element.reusesLayout = true
      return
    }
  }

  for index in element.children.indices {
    resolveEnvironment(
      &element.children[index],
      colorScheme: effectiveScheme,
      inheritedForeground: foreground,
      inheritedDisabled: disabled,
      inheritedOpacity: element.props.opacity,
      inheritedBlurRadius: element.props.blurRadius,
      inheritedVisible: element.props.visible,
      inheritedLineLimit: element.props.lineLimit,
      inheritedLineSpacing: element.props.lineSpacing,
      previous: previous.flatMap { index < $0.children.count ? $0.children[index] : nil }
    )
  }
}
func collectActions(_ element: Element, into actions: inout [NodeID: () -> Void]) {
  if let action = element.action {
    actions[element.id] = action
  }
  for child in element.children {
    collectActions(child, into: &actions)
  }
}
