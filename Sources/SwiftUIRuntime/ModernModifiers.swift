import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(Combine)
  import Combine
#endif

// MARK: - Visibility & Edges

public enum Visibility: Hashable, CaseIterable, Sendable {
  case automatic
  case visible
  case hidden
}

public enum VerticalEdge: Int8, CaseIterable, Hashable, Sendable {
  case top
  case bottom
  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let top = Set(rawValue: 1 << 0)
    public static let bottom = Set(rawValue: 1 << 1)
    public static let all: Set = [.top, .bottom]
  }
}

public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
  case leading
  case trailing
  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let leading = Set(rawValue: 1 << 0)
    public static let trailing = Set(rawValue: 1 << 1)
    public static let all: Set = [.leading, .trailing]
  }
}

// MARK: - ScrollGeometry & ScrollPhase

public struct ScrollGeometry: Equatable, Sendable {
  public var contentOffset: CGPoint
  public var contentSize: CGSize
  public var contentInsets: EdgeInsets
  public var containerSize: CGSize

  public init(
    contentOffset: CGPoint,
    contentSize: CGSize,
    contentInsets: EdgeInsets,
    containerSize: CGSize
  ) {
    self.contentOffset = contentOffset
    self.contentSize = contentSize
    self.contentInsets = contentInsets
    self.containerSize = containerSize
  }

  public var visibleRect: CGRect {
    CGRect(origin: contentOffset, size: containerSize)
  }

  public var bounds: CGRect {
    CGRect(origin: contentOffset, size: containerSize)
  }
}

public enum ScrollPhase: Hashable, Sendable {
  case idle
  case tracking
  case interacting
  case decelerating
  case animating

  public var isScrolling: Bool {
    self != .idle
  }
}

public struct ScrollPhaseChangeContext: Sendable {
  public let geometry: ScrollGeometry
  public let velocity: CGSize?
}

public enum ScrollIndicatorVisibility: Equatable, Sendable {
  case automatic
  case visible
  case hidden
  case never
}

public enum ScrollBounceBehavior: Equatable, Sendable {
  case automatic
  case always
  case basedOnSize
}

public struct ContentMarginPlacement: Equatable, Sendable {
  public static let automatic = ContentMarginPlacement()
  public static let scrollContent = ContentMarginPlacement()
  public static let scrollIndicators = ContentMarginPlacement()
}

private final class ValueHistoryBox<T> {
  var last: T?
}

private struct OnScrollGeometryChangeView<Content: View, T: Equatable>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let transform: (ScrollGeometry) -> T
  let action: (T, T) -> Void
  @State private var box = ValueHistoryBox<T>()

  var body: Never { fatalError("OnScrollGeometryChangeView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var el = _render(content, path: path)
    let boxRef = box
    let transformFn = transform
    let actionFn = action
    attachScrollGeometryHandler(&el) { geo in
      let next = transformFn(geo)
      if let prev = boxRef.last {
        guard prev != next else { return }
        boxRef.last = next
        actionFn(prev, next)
      } else {
        boxRef.last = next
        actionFn(next, next)
      }
    }
    return el
  }
}

private func attachScrollGeometryHandler(
  _ element: inout Element,
  _ handler: @escaping (ScrollGeometry) -> Void
) {
  if element.kind == .scroll {
    element.scrollGeometryHandlers.append(handler)
    return
  }
  for i in element.children.indices {
    if containsScrollNode(element.children[i]) {
      attachScrollGeometryHandler(&element.children[i], handler)
      return
    }
  }
}

private func attachScrollPhaseHandler(
  _ element: inout Element,
  _ handler: @escaping (ScrollPhase, ScrollPhase) -> Void
) {
  if element.kind == .scroll {
    element.scrollPhaseHandlers.append(handler)
    return
  }
  for i in element.children.indices {
    if containsScrollNode(element.children[i]) {
      attachScrollPhaseHandler(&element.children[i], handler)
      return
    }
  }
}

private func containsScrollNode(_ element: Element) -> Bool {
  if element.kind == .scroll { return true }
  return element.children.contains { containsScrollNode($0) }
}

extension View {
  public func onScrollGeometryChange<T: Equatable>(
    for type: T.Type,
    of transform: @escaping (ScrollGeometry) -> T,
    action: @escaping (T, T) -> Void
  ) -> some View {
    OnScrollGeometryChangeView(content: self, transform: transform, action: action)
  }

  public func onScrollPhaseChange(
    _ action: @escaping (ScrollPhase, ScrollPhase) -> Void
  ) -> some View {
    TransformView(content: self) { el in
      attachScrollPhaseHandler(&el, action)
    }
  }

  public func onScrollPhaseChange(
    _ action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void
  ) -> some View {
    onScrollPhaseChange { old, new in
      let ctx = ScrollPhaseChangeContext(
        geometry: ScrollGeometry(contentOffset: .zero, contentSize: .zero, contentInsets: .zero, containerSize: .zero),
        velocity: nil
      )
      action(old, new, ctx)
    }
  }

  public func scrollIndicators(
    _ visibility: ScrollIndicatorVisibility,
    axes: Axis.Set = [.vertical, .horizontal]
  ) -> some View {
    TransformView(content: self) { el in
      func apply(_ node: inout Element) {
        if node.kind == .scroll {
          node.props.showsScrollIndicators = (visibility == .visible || visibility == .automatic)
          return
        }
        for i in node.children.indices { apply(&node.children[i]) }
      }
      apply(&el)
    }
  }

  public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
    self
  }

  public func scrollContentBackground(_ visibility: Visibility) -> some View {
    self
  }

  public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
    TransformView(content: self) { el in
      if el.kind == .scroll { el.props.clipped = !disabled }
    }
  }

  public func scrollDisabled(_ disabled: Bool) -> some View {
    self
  }

  public func contentMargins(
    _ edges: Edge.Set = .all,
    _ length: CGFloat?,
    for placement: ContentMarginPlacement = .automatic
  ) -> some View {
    let val = Double(length ?? 0)
    var ins = EdgeInsets.zero
    if edges.contains(.top) { ins.top = val }
    if edges.contains(.leading) { ins.leading = val }
    if edges.contains(.bottom) { ins.bottom = val }
    if edges.contains(.trailing) { ins.trailing = val }
    return contentMargins(edges, ins, for: placement)
  }

  public func contentMargins(
    _ edges: Edge.Set = .all,
    _ insets: EdgeInsets,
    for placement: ContentMarginPlacement = .automatic
  ) -> some View {
    TransformView(content: self) { el in
      func apply(_ node: inout Element) {
        if node.kind == .scroll {
          node.props.scrollContentInsets = node.props.scrollContentInsets + insets
          return
        }
        for i in node.children.indices { apply(&node.children[i]) }
      }
      apply(&el)
    }
  }
}

// MARK: - onGeometryChange & safeAreaInset

private struct OnGeometryChangeView<Content: View, T: Equatable>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let transform: (GeometryProxy) -> T
  let action: (T, T) -> Void
  @State private var box = ValueHistoryBox<T>()

  var body: Never { fatalError("OnGeometryChangeView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var el = _render(content, path: path)
    let boxRef = box
    let transformFn = transform
    let actionFn = action
    el.geometryChangeHandlers.append { proxy in
      let next = transformFn(proxy)
      if let prev = boxRef.last {
        guard prev != next else { return }
        boxRef.last = next
        actionFn(prev, next)
      } else {
        boxRef.last = next
        actionFn(next, next)
      }
    }
    return el
  }
}

private func isSingleScrollWrapperChain(_ node: Element) -> Bool {
  switch node.kind {
  case .scroll:
    return true
  case .padding, .frame, .fragment, .geometry:
    return node.children.count == 1 && isSingleScrollWrapperChain(node.children[0])
  case .layer:
    return !node.children.isEmpty && isSingleScrollWrapperChain(node.children[0])
  default:
    return false
  }
}

private func isThinVerticalRule(_ node: Element) -> Bool {
  if node.kind == .shape, let fw = node.props.frameWidth, fw <= 2 { return true }
  if node.kind == .frame, let fw = node.props.frameWidth, fw <= 2,
    node.children.count == 1, node.children[0].kind == .shape
  {
    return true
  }
  return false
}

private func isThinHorizontalRule(_ node: Element) -> Bool {
  if node.kind == .shape, let fh = node.props.frameHeight, fh <= 2 { return true }
  if node.kind == .frame, let fh = node.props.frameHeight, fh <= 2,
    node.children.count == 1, node.children[0].kind == .shape
  {
    return true
  }
  return false
}

private func canPropagateVerticalSafeArea(_ node: Element) -> Bool {
  if isSingleScrollWrapperChain(node) { return true }
  switch node.kind {
  case .container(.horizontal):
    return true
  case .padding, .frame, .fragment, .geometry:
    return node.children.count == 1 && canPropagateVerticalSafeArea(node.children[0])
  case .layer:
    return !node.children.isEmpty && canPropagateVerticalSafeArea(node.children[0])
  default:
    return false
  }
}

private func canPropagateHorizontalSafeArea(_ node: Element) -> Bool {
  if isSingleScrollWrapperChain(node) { return true }
  switch node.kind {
  case .container(.vertical):
    return true
  case .padding, .frame, .fragment, .geometry:
    return node.children.count == 1 && canPropagateHorizontalSafeArea(node.children[0])
  case .layer:
    return !node.children.isEmpty && canPropagateHorizontalSafeArea(node.children[0])
  default:
    return false
  }
}

private func applyVerticalSafeArea(_ node: inout Element, edge: VerticalEdge, amount: Double) {
  if isSingleScrollWrapperChain(node) {
    func updateScroll(_ cur: inout Element) -> Bool {
      if cur.kind == .scroll {
        if edge == .top {
          let oldTop = cur.props.scrollContentInsets.top
          cur.props.scrollContentInsets.top += amount
          if abs(cur.props.scrollOffset.y - (-oldTop)) < 0.5 {
            cur.props.scrollOffset.y = -cur.props.scrollContentInsets.top
          }
        } else {
          cur.props.scrollContentInsets.bottom += amount
        }
        return true
      }
      if !cur.children.isEmpty {
        return updateScroll(&cur.children[0])
      }
      return false
    }
    _ = updateScroll(&node)
    return
  }
  switch node.kind {
  case .fragment, .frame, .geometry:
    if node.children.count == 1 {
      applyVerticalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
  case .layer:
    if !node.children.isEmpty {
      applyVerticalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
  case .padding:
    if node.children.count == 1 && canPropagateVerticalSafeArea(node.children[0]) {
      applyVerticalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
    if edge == .top {
      node.props.padding.top += amount
    } else {
      node.props.padding.bottom += amount
    }
    return
  case .container(.horizontal):
    for i in node.children.indices {
      if isThinVerticalRule(node.children[i]) { continue }
      applyVerticalSafeArea(&node.children[i], edge: edge, amount: amount)
    }
    return
  default:
    break
  }
  var p = NodeProps()
  if edge == .top {
    p.padding = EdgeInsets(top: amount, leading: 0, bottom: 0, trailing: 0)
  } else {
    p.padding = EdgeInsets(top: 0, leading: 0, bottom: amount, trailing: 0)
  }
  node = Element(kind: .padding, props: p, children: [node])
}

private func applyHorizontalSafeArea(_ node: inout Element, edge: HorizontalEdge, amount: Double) {
  if isSingleScrollWrapperChain(node) {
    func updateScroll(_ cur: inout Element) -> Bool {
      if cur.kind == .scroll {
        if edge == .leading {
          cur.props.scrollContentInsets.leading += amount
        } else {
          cur.props.scrollContentInsets.trailing += amount
        }
        return true
      }
      if !cur.children.isEmpty {
        return updateScroll(&cur.children[0])
      }
      return false
    }
    _ = updateScroll(&node)
    return
  }
  switch node.kind {
  case .fragment, .frame, .geometry:
    if node.children.count == 1 {
      applyHorizontalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
  case .layer:
    if !node.children.isEmpty {
      applyHorizontalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
  case .padding:
    if node.children.count == 1 && canPropagateHorizontalSafeArea(node.children[0]) {
      applyHorizontalSafeArea(&node.children[0], edge: edge, amount: amount)
      return
    }
    if edge == .leading {
      node.props.padding.leading += amount
    } else {
      node.props.padding.trailing += amount
    }
    return
  case .container(.vertical):
    for i in node.children.indices {
      if isThinHorizontalRule(node.children[i]) { continue }
      applyHorizontalSafeArea(&node.children[i], edge: edge, amount: amount)
    }
    return
  default:
    break
  }
  var p = NodeProps()
  if edge == .leading {
    p.padding = EdgeInsets(top: 0, leading: amount, bottom: 0, trailing: 0)
  } else {
    p.padding = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: amount)
  }
  node = Element(kind: .padding, props: p, children: [node])
}

private struct SafeAreaInsetVerticalView<Content: View, Bar: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let edge: VerticalEdge
  let alignment: HorizontalAlignment
  let spacing: CGFloat
  let bar: Bar

  nonisolated init(
    content: Content,
    edge: VerticalEdge,
    alignment: HorizontalAlignment,
    spacing: CGFloat,
    bar: Bar
  ) {
    self.content = content
    self.edge = edge
    self.alignment = alignment
    self.spacing = spacing
    self.bar = bar
  }

  var body: Never { fatalError("SafeAreaInsetVerticalView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var base = _render(content, path: path.appending(index: 0))
    let barEl = _render(bar, path: path.appending(index: 1))
    let padProps = NodeProps()
    if barEl.kind != .empty {
      let measuredBar = LayoutEngine().measuredSize(of: barEl)
      let insetAmount = measuredBar.height + Double(spacing)
      if insetAmount > 0 {
        applyVerticalSafeArea(&base, edge: edge, amount: insetAmount)
      }
    }
    // Keep a single `.layer -> [.padding(base), bar]` shape across empty/non-empty
    // bars and scrolling/non-scrolling content so controls inside `bar` or `base`
    // retain their NodeID and native focus when siblings swap.
    let paddedBase = Element(kind: .padding, props: padProps, children: [base])
    var layerProps = NodeProps()
    layerProps.alignment = Alignment(horizontal: alignment, vertical: edge == .top ? .top : .bottom)
    layerProps.layerBehind = false
    return Element(kind: .layer, props: layerProps, children: [paddedBase, barEl])
  }
}

private struct SafeAreaInsetHorizontalView<Content: View, Bar: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let edge: HorizontalEdge
  let alignment: VerticalAlignment
  let spacing: CGFloat
  let bar: Bar

  nonisolated init(
    content: Content,
    edge: HorizontalEdge,
    alignment: VerticalAlignment,
    spacing: CGFloat,
    bar: Bar
  ) {
    self.content = content
    self.edge = edge
    self.alignment = alignment
    self.spacing = spacing
    self.bar = bar
  }

  var body: Never { fatalError("SafeAreaInsetHorizontalView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var base = _render(content, path: path.appending(index: 0))
    let barEl = _render(bar, path: path.appending(index: 1))
    let padProps = NodeProps()
    if barEl.kind != .empty {
      let measuredBar = LayoutEngine().measuredSize(of: barEl)
      let insetAmount = measuredBar.width + Double(spacing)
      if insetAmount > 0 {
        applyHorizontalSafeArea(&base, edge: edge, amount: insetAmount)
      }
    }
    let paddedBase = Element(kind: .padding, props: padProps, children: [base])
    var layerProps = NodeProps()
    layerProps.alignment = Alignment(horizontal: edge == .leading ? .leading : .trailing, vertical: alignment)
    layerProps.layerBehind = false
    return Element(kind: .layer, props: layerProps, children: [paddedBase, barEl])
  }
}

private func flattenChildrenList(_ elements: [Element]) -> [Element] {
  elements.flatMap { flattenChildren($0) }
}

extension View {
  public func onGeometryChange<T: Equatable>(
    for type: T.Type,
    of transform: @escaping (GeometryProxy) -> T,
    action: @escaping (T) -> Void
  ) -> some View {
    OnGeometryChangeView(content: self, transform: transform) { _, new in
      action(new)
    }
  }

  public func onGeometryChange<T: Equatable>(
    for type: T.Type,
    of transform: @escaping (GeometryProxy) -> T,
    action: @escaping (T, T) -> Void
  ) -> some View {
    OnGeometryChangeView(content: self, transform: transform, action: action)
  }

  nonisolated public func safeAreaInset<V: View>(
    edge: VerticalEdge,
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat? = nil,
    @ViewBuilder content: () -> V
  ) -> some View {
    SafeAreaInsetVerticalView(
      content: self, edge: edge, alignment: alignment, spacing: spacing ?? 0, bar: content()
    )
  }

  nonisolated public func safeAreaInset<V: View>(
    edge: HorizontalEdge,
    alignment: VerticalAlignment = .center,
    spacing: CGFloat? = nil,
    @ViewBuilder content: () -> V
  ) -> some View {
    SafeAreaInsetHorizontalView(
      content: self, edge: edge, alignment: alignment, spacing: spacing ?? 0, bar: content()
    )
  }
}

// MARK: - Liquid Glass & Namespace

public struct Glass: Equatable, Sendable {
  public enum Variant: Equatable, Sendable {
    case regular
    case clear
    case identity
  }

  public var variant: Variant
  public var isInteractive: Bool = false
  public var tintColor: Color?

  public static let regular = Glass(variant: .regular)
  public static let clear = Glass(variant: .clear)
  public static let identity = Glass(variant: .identity)

  public func interactive(_ isEnabled: Bool = true) -> Glass {
    var copy = self
    copy.isInteractive = isEnabled
    return copy
  }

  public func tint(_ color: Color?) -> Glass {
    var copy = self
    copy.tintColor = color
    return copy
  }
}

public struct GlassEffectContainer<Content: View>: View {
  let spacing: CGFloat?
  let content: Content

  public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    content
  }
}

@propertyWrapper
public struct Namespace: _StateProperty {
  public struct ID: Hashable, Sendable {
    let raw: UUID
    init(_ raw: UUID = UUID()) { self.raw = raw }
  }

  private var state = State(wrappedValue: ID())
  public init() {}
  public var wrappedValue: ID { state.wrappedValue }
  func install(_ key: StateKey) { state.install(key) }
}

extension View {
  func _backdropBlur(radius: CGFloat) -> some View {
    TransformView(content: self) { el in
      el.props.backdropBlurRadius = max(el.props.backdropBlurRadius, max(0, Double(radius)))
      el.props.clipped = true
    }
  }

  public func glassEffect<S: Shape>(
    _ glass: Glass = .regular,
    in shape: S = Capsule(),
    isEnabled: Bool = true
  ) -> some View {
    guard isEnabled, glass.variant != .identity else {
      return AnyView(self)
    }
    #if CROSS_SWIFTUI_HARMONY_DESKTOP
      let fill = Color { scheme in
        if let tint = glass.tintColor {
          let r = tint.resolved(in: scheme)
          return (r.red, r.green, r.blue, max(0.20, r.opacity * 0.40))
        }
        if glass.variant == .clear {
          return scheme == .dark ? (1.0, 1.0, 1.0, 0.08) : (1.0, 1.0, 1.0, 0.40)
        }
        return scheme == .dark ? (0.12, 0.12, 0.15, 0.62) : (0.97, 0.97, 0.99, 0.68)
      }
      let border = Color { scheme in
        scheme == .dark ? (1.0, 1.0, 1.0, 0.18) : (0.0, 0.0, 0.0, 0.11)
      }
      let blurRadius: CGFloat = glass.variant == .clear ? 18 : 30
      if shape.cornerRadius > 0 {
        let shadowColor = Color { scheme in
          scheme == .dark ? (0.0, 0.0, 0.0, 0.42) : (0.0, 0.0, 0.0, 0.14)
        }
        return AnyView(
          self
            .background {
              shape.fill(fill)
                ._backdropBlur(radius: blurRadius)
            }
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .shadow(color: shadowColor, radius: 14, x: 0, y: 4)
        )
      }
      return AnyView(
        self
          .background {
            shape.fill(fill)
              ._backdropBlur(radius: blurRadius)
          }
          .overlay { shape.strokeBorder(border, lineWidth: 1) }
      )
    #else
      let fill = Color { scheme in
        if let tint = glass.tintColor {
          let r = tint.resolved(in: scheme)
          return (r.red, r.green, r.blue, max(0.18, r.opacity * 0.35))
        }
        if glass.variant == .clear {
          return scheme == .dark ? (1.0, 1.0, 1.0, 0.05) : (1.0, 1.0, 1.0, 0.35)
        }
        return scheme == .dark ? (0.15, 0.15, 0.17, 0.94) : (0.96, 0.96, 0.98, 0.95)
      }
      let border = Color { scheme in
        scheme == .dark ? (1.0, 1.0, 1.0, 0.14) : (0.0, 0.0, 0.0, 0.10)
      }
      #if CROSS_SWIFTUI_HARMONY
        if shape.cornerRadius > 0 {
          let shadowColor = Color { scheme in
            scheme == .dark ? (0.0, 0.0, 0.0, 0.42) : (0.0, 0.0, 0.0, 0.14)
          }
          return AnyView(
            self
              .background(fill, in: shape)
              .overlay { shape.strokeBorder(border, lineWidth: 1) }
              .shadow(color: shadowColor, radius: 14, x: 0, y: 4)
          )
        }
        return AnyView(
          self
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
        )
      #else
        return AnyView(
          self
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
        )
      #endif
    #endif
  }

  public func glassEffectID(_ id: (some Hashable)?, in namespace: Namespace.ID) -> some View {
    self
  }
}

// MARK: - Presentations: confirmationDialog, sheet, alert overloads

internal struct _ModalDialogActionButtonStyle: ButtonStyle {
  let role: ButtonRole?

  func makeBody(configuration: Configuration) -> some View {
    BodyView(configuration: configuration, role: role)
  }

  private struct BodyView: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let role: ButtonRole?
    @State private var hovered = false

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: role == .cancel ? .regular : .medium))
        .foregroundStyle(labelColor)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .contentShape(Capsule())
        .background(Capsule().fill(fillColor))
        .animation(.easeOut(duration: 0.12), value: hovered)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovered = $0 }
    }

    private var fillColor: Color {
      let isPressed = configuration.isPressed
      let isHovered = hovered
      switch role {
      case .destructive:
        return Color.red.opacity(accentOpacity)
      case .cancel:
        return Color { scheme in
          if isPressed {
            return scheme == .dark ? (1, 1, 1, 0.24) : (0, 0, 0, 0.18)
          } else if isHovered {
            return scheme == .dark ? (1, 1, 1, 0.16) : (0, 0, 0, 0.12)
          } else {
            return scheme == .dark ? (1, 1, 1, 0.10) : (0, 0, 0, 0.07)
          }
        }
      case nil:
        return Color.blue.opacity(accentOpacity)
      }
    }

    private var accentOpacity: Double {
      if configuration.isPressed { return 0.36 }
      if hovered { return 0.28 }
      return 0.20
    }

    private var labelColor: Color {
      switch role {
      case .destructive: return .red
      case .cancel: return .secondary
      case nil: return .blue
      }
    }
  }
}

internal struct _PreparedElementsView: View, _PrimitiveView {
  typealias Body = Never
  let element: Element
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element { element }
}

@MainActor
internal func _renderModalDialogCard<Actions: View, Message: View>(
  title: String,
  titleVisibility: Visibility,
  scheme: ColorScheme,
  actions: Actions,
  message: Message,
  path: ViewPath
) -> Element {
  let actionsTree = _render(
    actions.environment(\.inheritedButtonStyle) { label, role, btnPath, action in
      let btn = Button(role: role, action: action) { label }
      return _render(
        StyledButton(button: btn, style: _ModalDialogActionButtonStyle(role: role)),
        path: btnPath
      )
    },
    path: path.appending(index: 99)
  )
  var actionItems = flattenChildren(actionsTree)
  var assignedDefault = false
  for idx in actionItems.indices {
    if actionItems[idx].props.keyboardShortcut == nil && !assignedDefault {
      actionItems[idx].props.keyboardShortcut = .defaultAction
      assignedDefault = true
    }
  }
  if actionItems.count == 2 {
    actionItems.sort { a, b in
      let rankA = a.props.keyboardShortcut == .cancelAction ? 0 : 1
      let rankB = b.props.keyboardShortcut == .cancelAction ? 0 : 1
      return rankA < rankB
    }
  } else if actionItems.count > 2 {
    actionItems.sort { a, b in
      let rankA = a.props.keyboardShortcut == .cancelAction ? 1 : 0
      let rankB = b.props.keyboardShortcut == .cancelAction ? 1 : 0
      return rankA < rankB
    }
  }
  var actionsContainerProps = NodeProps()
  actionsContainerProps.spacing = 8
  let actionsAxis: Axis = actionItems.count <= 2 ? .horizontal : .vertical
  let actionsRow = Element(
    kind: .container(actionsAxis),
    props: actionsContainerProps,
    children: actionItems
  )

  let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
  let panel = VStack(alignment: .leading, spacing: 18) {
    VStack(alignment: .leading, spacing: 6) {
      if titleVisibility != .hidden && !title.isEmpty {
        Text(verbatim: title).font(.system(size: 15, weight: .semibold))
      }
      message
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 2)
    _PreparedElementsView(element: actionsRow)
  }
  .padding(18)
  .frame(width: 340, alignment: .leading)
  .foregroundStyle(scheme == .dark ? Color.white : Color.black)
  .background(
    scheme == .dark ? Color(hex: 0x1c1d22, opacity: 0.98) : Color(hex: 0xf9f9fb, opacity: 0.98),
    in: shape
  )
  .overlay {
    shape.strokeBorder(
      scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 1)
  }
  .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.20), radius: 24, x: 0, y: 10)
  return _render(panel, path: path)
}

private struct ModalCardPresentation<Content: View, Actions: View, Message: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let title: String
  let titleVisibility: Visibility
  let isPresented: Binding<Bool>
  let actions: Actions
  let message: Message
  @Environment(\.colorScheme) private var scheme

  var body: Never { fatalError("ModalCardPresentation is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var children = [_render(content, path: path.appending(index: 0))]
    if isPresented.wrappedValue {
      children.append(
        _renderModalDialogCard(
          title: title,
          titleVisibility: titleVisibility,
          scheme: scheme,
          actions: actions,
          message: message,
          path: path.appending(index: 1)
        )
      )
    }
    var element = Element(kind: .presentation, children: children)
    element.presentationCentered = true
    element.dismissOnAction = true
    element.dismissPresentation = { isPresented.wrappedValue = false }
    return element
  }
}

private struct SheetPresentation<Content: View, SheetContent: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let isPresented: Binding<Bool>
  let onDismiss: (() -> Void)?
  let sheetContent: () -> SheetContent
  @Environment(\.colorScheme) private var scheme

  var body: Never { fatalError("SheetPresentation is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var children = [_render(content, path: path.appending(index: 0))]
    let dismiss = DismissAction {
      if isPresented.wrappedValue {
        isPresented.wrappedValue = false
        onDismiss?()
      }
    }
    if isPresented.wrappedValue {
      let wrapped = sheetContent()
        .environment(\.dismiss, dismiss)
        .background(
          scheme == .dark ? Color(hex: 0x1e1f24) : Color(hex: 0xf6f6f8),
          in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 1)
        }
      var sheetEl = _render(wrapped, path: path.appending(index: 1))
      sheetEl.props.semanticControl = SemanticControl(kind: "sheet")
      sheetEl.dismissPresentation = {
        if isPresented.wrappedValue {
          isPresented.wrappedValue = false
          onDismiss?()
        }
      }
      children.append(sheetEl)
    }
    var element = Element(kind: .presentation, children: children)
    element.presentationCentered = true
    element.dismissPresentation = {
      isPresented.wrappedValue = false
      onDismiss?()
    }
    return element
  }
}

extension View {
  public func confirmationDialog<A: View, M: View>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    @ViewBuilder actions: () -> A,
    @ViewBuilder message: () -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: titleKey.resolved(),
      titleVisibility: titleVisibility,
      isPresented: isPresented,
      actions: actions(),
      message: message()
    )
  }

  public func confirmationDialog<A: View>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    @ViewBuilder actions: () -> A
  ) -> some View {
    confirmationDialog(titleKey, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) {
      EmptyView()
    }
  }

  @_disfavoredOverload
  public func confirmationDialog<S: StringProtocol, A: View, M: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    @ViewBuilder actions: () -> A,
    @ViewBuilder message: () -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: String(title),
      titleVisibility: titleVisibility,
      isPresented: isPresented,
      actions: actions(),
      message: message()
    )
  }

  @_disfavoredOverload
  public func confirmationDialog<S: StringProtocol, A: View>(
    _ title: S,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    @ViewBuilder actions: () -> A
  ) -> some View {
    confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions) {
      EmptyView()
    }
  }

  public func confirmationDialog<A: View, M: View, T>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A,
    @ViewBuilder message: (T) -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: titleKey.resolved(),
      titleVisibility: titleVisibility,
      isPresented: Binding(
        get: { isPresented.wrappedValue && data != nil },
        set: { isPresented.wrappedValue = $0 }
      ),
      actions: Group { if let data { actions(data) } },
      message: Group { if let data { message(data) } }
    )
  }

  public func confirmationDialog<A: View, T>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A
  ) -> some View {
    confirmationDialog(
      titleKey, isPresented: isPresented, titleVisibility: titleVisibility,
      presenting: data, actions: actions
    ) { _ in EmptyView() }
  }

  @_disfavoredOverload
  public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(
    _ title: S,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A,
    @ViewBuilder message: (T) -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: String(title),
      titleVisibility: titleVisibility,
      isPresented: Binding(
        get: { isPresented.wrappedValue && data != nil },
        set: { isPresented.wrappedValue = $0 }
      ),
      actions: Group { if let data { actions(data) } },
      message: Group { if let data { message(data) } }
    )
  }

  @_disfavoredOverload
  public func confirmationDialog<S: StringProtocol, A: View, T>(
    _ title: S,
    isPresented: Binding<Bool>,
    titleVisibility: Visibility = .automatic,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A
  ) -> some View {
    confirmationDialog(
      title, isPresented: isPresented, titleVisibility: titleVisibility,
      presenting: data, actions: actions
    ) { _ in EmptyView() }
  }

  public func alert<A: View>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> A
  ) -> some View {
    alert(titleKey.resolved(), isPresented: isPresented, actions: actions) { EmptyView() }
  }

  public func alert<A: View, M: View>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    @ViewBuilder actions: () -> A,
    @ViewBuilder message: () -> M
  ) -> some View {
    alert(titleKey.resolved(), isPresented: isPresented, actions: actions, message: message)
  }

  public func alert<A: View, M: View, T>(
    _ titleKey: LocalizedStringKey,
    isPresented: Binding<Bool>,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A,
    @ViewBuilder message: (T) -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: titleKey.resolved(),
      titleVisibility: .visible,
      isPresented: Binding(
        get: { isPresented.wrappedValue && data != nil },
        set: { isPresented.wrappedValue = $0 }
      ),
      actions: Group { if let data { actions(data) } },
      message: Group { if let data { message(data) } }
    )
  }

  @_disfavoredOverload
  public func alert<S: StringProtocol, A: View, M: View, T>(
    _ title: S,
    isPresented: Binding<Bool>,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A,
    @ViewBuilder message: (T) -> M
  ) -> some View {
    ModalCardPresentation(
      content: self,
      title: String(title),
      titleVisibility: .visible,
      isPresented: Binding(
        get: { isPresented.wrappedValue && data != nil },
        set: { isPresented.wrappedValue = $0 }
      ),
      actions: Group { if let data { actions(data) } },
      message: Group { if let data { message(data) } }
    )
  }

  @_disfavoredOverload
  public func alert<S: StringProtocol, A: View, T>(
    _ title: S,
    isPresented: Binding<Bool>,
    presenting data: T?,
    @ViewBuilder actions: (T) -> A
  ) -> some View {
    alert(title, isPresented: isPresented, presenting: data, actions: actions) { _ in EmptyView() }
  }

  public func alert<Item: Identifiable>(
    item: Binding<Item?>,
    content: (Item) -> Alert
  ) -> some View {
    let current = item.wrappedValue.map(content)
    return ModalCardPresentation(
      content: self,
      title: current?.title.content ?? "",
      titleVisibility: .visible,
      isPresented: Binding(
        get: { item.wrappedValue != nil },
        set: { if !$0 { item.wrappedValue = nil } }
      ),
      actions: Group {
        if let primary = current?.primaryButton {
          Button(primary.label.content, role: primary.role) {
            primary.action?()
            item.wrappedValue = nil
          }
        }
        if let secondary = current?.secondaryButton {
          Button(secondary.label.content, role: secondary.role) {
            secondary.action?()
            item.wrappedValue = nil
          }
        }
      },
      message: Group {
        if let msg = current?.message { msg }
      }
    )
  }

  public func alert(
    isPresented: Binding<Bool>,
    content: () -> Alert
  ) -> some View {
    let current = isPresented.wrappedValue ? content() : nil
    return ModalCardPresentation(
      content: self,
      title: current?.title.content ?? "",
      titleVisibility: .visible,
      isPresented: isPresented,
      actions: Group {
        if let primary = current?.primaryButton {
          Button(primary.label.content, role: primary.role) {
            primary.action?()
            isPresented.wrappedValue = false
          }
        }
        if let secondary = current?.secondaryButton {
          Button(secondary.label.content, role: secondary.role) {
            secondary.action?()
            isPresented.wrappedValue = false
          }
        }
      },
      message: Group {
        if let msg = current?.message { msg }
      }
    )
  }

  public func buttonBorderShape(_ shape: ButtonBorderShape) -> some View {
    self
  }

  public func contextMenu<I: Hashable, M: View>(
    forSelectionType itemType: I.Type = I.self,
    @ViewBuilder menu: @escaping (Set<I>) -> M,
    primaryAction: ((Set<I>) -> Void)? = nil
  ) -> some View {
    self
  }

  public func sheet<SheetContent: View>(
    isPresented: Binding<Bool>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping () -> SheetContent
  ) -> some View {
    SheetPresentation(content: self, isPresented: isPresented, onDismiss: onDismiss, sheetContent: content)
  }

  public func sheet<Item: Identifiable, SheetContent: View>(
    item: Binding<Item?>,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (Item) -> SheetContent
  ) -> some View {
    SheetPresentation(
      content: self,
      isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
      onDismiss: onDismiss,
      sheetContent: {
        Group {
          if let current = item.wrappedValue {
            content(current)
          }
        }
      }
    )
  }
}

// MARK: - Visual, Symbol, Pointer, Gesture & Accessibility Modifiers

public struct SymbolRenderingMode: Equatable, Sendable {
  public enum Kind: Sendable { case monochrome, hierarchical, palette, multicolor }
  let kind: Kind
  public static let monochrome = SymbolRenderingMode(kind: .monochrome)
  public static let hierarchical = SymbolRenderingMode(kind: .hierarchical)
  public static let palette = SymbolRenderingMode(kind: .palette)
  public static let multicolor = SymbolRenderingMode(kind: .multicolor)
}

public struct SymbolVariants: Hashable, Sendable {
  let raw: Int
  public static let none = SymbolVariants(raw: 0)
  public static let circle = SymbolVariants(raw: 1)
  public static let square = SymbolVariants(raw: 2)
  public static let rectangle = SymbolVariants(raw: 3)
  public static let fill = SymbolVariants(raw: 4)
  public static let slash = SymbolVariants(raw: 5)
}

private enum SymbolVariantsEnvironmentKey: EnvironmentKey {
  static let defaultValue = SymbolVariants.none
}

extension EnvironmentValues {
  public var symbolVariants: SymbolVariants {
    get { self[SymbolVariantsEnvironmentKey.self] }
    set { self[SymbolVariantsEnvironmentKey.self] = newValue }
  }
}

public protocol SymbolEffect: Sendable {}
public protocol DiscreteSymbolEffect: SymbolEffect {}
public protocol IndefiniteSymbolEffect: SymbolEffect {}
public protocol ContentTransitionSymbolEffect: SymbolEffect {}

public struct BounceSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, Sendable {
  public init() {}
  public var up: BounceSymbolEffect { self }
  public var down: BounceSymbolEffect { self }
  public var byLayer: BounceSymbolEffect { self }
  public var wholeSymbol: BounceSymbolEffect { self }
}

public struct PulseSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, Sendable {
  public init() {}
  public var byLayer: PulseSymbolEffect { self }
  public var wholeSymbol: PulseSymbolEffect { self }
}

public struct VariableColorSymbolEffect: IndefiniteSymbolEffect, Sendable {
  public init() {}
  public var iterative: VariableColorSymbolEffect { self }
  public var cumulative: VariableColorSymbolEffect { self }
  public var reversing: VariableColorSymbolEffect { self }
  public var nonReversing: VariableColorSymbolEffect { self }
  public var dimInactiveLayers: VariableColorSymbolEffect { self }
  public var hideInactiveLayers: VariableColorSymbolEffect { self }
}

public struct ReplaceSymbolEffect: ContentTransitionSymbolEffect, Sendable {
  public init() {}
  public var downUp: ReplaceSymbolEffect { self }
  public var upUp: ReplaceSymbolEffect { self }
  public var offUp: ReplaceSymbolEffect { self }
}

public struct RotateSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, Sendable {
  public init() {}
}

public struct WiggleSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, Sendable {
  public init() {}
}

public struct BreatheSymbolEffect: IndefiniteSymbolEffect, Sendable {
  public init() {}
}

public struct DrawOnSymbolEffect: DiscreteSymbolEffect, IndefiniteSymbolEffect, Sendable {
  public init() {}
  public var byLayer: DrawOnSymbolEffect { self }
  public var wholeSymbol: DrawOnSymbolEffect { self }
  public var individually: DrawOnSymbolEffect { self }
}

extension SymbolEffect where Self == DrawOnSymbolEffect {
  public static var drawOn: DrawOnSymbolEffect { DrawOnSymbolEffect() }
}

@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint> {
  public var wrappedValue: Value
  public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
    self.wrappedValue = wrappedValue
  }
  public init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }
}

extension ScaledMetric: Sendable where Value: Sendable {}

public enum AccessibilityHeadingLevel: UInt, Equatable, Hashable, Sendable {
  case unspecified = 0
  case h1 = 1
  case h2 = 2
  case h3 = 3
  case h4 = 4
  case h5 = 5
  case h6 = 6
}

extension View {
  public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> some View {
    self
  }

  public func containerRelativeFrame(
    _ axes: Axis.Set,
    alignment: Alignment = .center
  ) -> some View {
    self
  }

  public func containerRelativeFrame(
    _ axes: Axis.Set,
    count: Int,
    span: Int = 1,
    spacing: CGFloat,
    alignment: Alignment = .center
  ) -> some View {
    self
  }

  public func containerRelativeFrame(
    _ axes: Axis.Set,
    alignment: Alignment = .center,
    _ length: @escaping (CGFloat, Axis) -> CGFloat
  ) -> some View {
    self
  }
}

extension SymbolEffect where Self == BounceSymbolEffect {
  public static var bounce: BounceSymbolEffect { BounceSymbolEffect() }
}
extension SymbolEffect where Self == PulseSymbolEffect {
  public static var pulse: PulseSymbolEffect { PulseSymbolEffect() }
}
extension SymbolEffect where Self == VariableColorSymbolEffect {
  public static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() }
}
extension SymbolEffect where Self == ReplaceSymbolEffect {
  public static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() }
}
extension SymbolEffect where Self == RotateSymbolEffect {
  public static var rotate: RotateSymbolEffect { RotateSymbolEffect() }
}
extension SymbolEffect where Self == WiggleSymbolEffect {
  public static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() }
}
extension SymbolEffect where Self == BreatheSymbolEffect {
  public static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() }
}

public struct ButtonBorderShape: Equatable, Sendable {
  public static let automatic = ButtonBorderShape()
  public static let capsule = ButtonBorderShape()
  public static let circle = ButtonBorderShape()
  public static let roundedRectangle = ButtonBorderShape()
  public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { ButtonBorderShape() }
}

public struct Alert {
  public struct Button {
    let label: Text
    let role: ButtonRole?
    let action: (() -> Void)?

    public static func `default`(_ label: Text, action: (() -> Void)? = nil) -> Button {
      Button(label: label, role: nil, action: action)
    }
    public static func cancel(_ label: Text, action: (() -> Void)? = nil) -> Button {
      Button(label: label, role: .cancel, action: action)
    }
    public static func cancel(_ action: (() -> Void)? = nil) -> Button {
      Button(label: Text("Cancel"), role: .cancel, action: action)
    }
    public static func destructive(_ label: Text, action: (() -> Void)? = nil) -> Button {
      Button(label: label, role: .destructive, action: action)
    }
  }

  let title: Text
  let message: Text?
  let primaryButton: Button
  let secondaryButton: Button?

  public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
    self.title = title
    self.message = message
    self.primaryButton = dismissButton ?? .default(Text("OK"))
    self.secondaryButton = nil
  }

  public init(title: Text, message: Text? = nil, primaryButton: Button, secondaryButton: Button) {
    self.title = title
    self.message = message
    self.primaryButton = primaryButton
    self.secondaryButton = secondaryButton
  }
}

public struct SymbolEffectOptions: Sendable {
  public struct RepeatBehavior: Sendable {
    public static let continuous = RepeatBehavior()
    public static func periodic(_ count: Int? = nil, delay: Double? = nil) -> RepeatBehavior { RepeatBehavior() }
  }
  public static let `default` = SymbolEffectOptions()
  public static let repeating = SymbolEffectOptions()
  public static let nonRepeating = SymbolEffectOptions()
  public static func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions() }
  public static func `repeat`(_ count: Int?) -> SymbolEffectOptions { SymbolEffectOptions() }
  public static func `repeat`(_ behavior: RepeatBehavior) -> SymbolEffectOptions { SymbolEffectOptions() }
}

public struct ContentTransition: Equatable, Sendable {
  public static let identity = ContentTransition()
  public static let opacity = ContentTransition()
  public static let interpolate = ContentTransition()
  public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition() }
  public static func numericText(value: Double) -> ContentTransition { ContentTransition() }
  public static func symbolEffect<T: ContentTransitionSymbolEffect>(
    _ effect: T = .replace,
    options: SymbolEffectOptions = .default
  ) -> ContentTransition {
    ContentTransition()
  }
  public static var symbolEffect: ContentTransition { ContentTransition() }
}

public struct PointerStyle: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case `default`, link, horizontalText, verticalText, rectSelection
    case rowResize, columnResize, frameResize, grabIdle, grabActive, zoomIn, zoomOut
  }
  let kind: Kind
  public static let `default` = PointerStyle(kind: .default)
  public static let link = PointerStyle(kind: .link)
  public static let horizontalText = PointerStyle(kind: .horizontalText)
  public static let verticalText = PointerStyle(kind: .verticalText)
  public static let rectSelection = PointerStyle(kind: .rectSelection)
  public static let rowResize = PointerStyle(kind: .rowResize)
  public static let columnResize = PointerStyle(kind: .columnResize)
  public static let grabIdle = PointerStyle(kind: .grabIdle)
  public static let grabActive = PointerStyle(kind: .grabActive)
  public static let zoomIn = PointerStyle(kind: .zoomIn)
  public static let zoomOut = PointerStyle(kind: .zoomOut)
}

public enum HoverPhase: Equatable, Sendable {
  case active(CGPoint)
  case ended
}

public enum ColorRenderingMode: Sendable {
  case nonLinear, linear, extendedLinear
}

public struct WritingToolsBehavior: Equatable, Sendable {
  public static let automatic = WritingToolsBehavior()
  public static let complete = WritingToolsBehavior()
  public static let limited = WritingToolsBehavior()
  public static let disabled = WritingToolsBehavior()
}

public struct SubmitLabel: Equatable, Sendable {
  public static let done = SubmitLabel()
  public static let go = SubmitLabel()
  public static let send = SubmitLabel()
  public static let join = SubmitLabel()
  public static let route = SubmitLabel()
  public static let search = SubmitLabel()
  public static let `return` = SubmitLabel()
  public static let next = SubmitLabel()
  public static let `continue` = SubmitLabel()
}

public struct TapGesture: Gesture {
  public let count: Int
  public var changed: ((DragGesture.Value) -> Void)? { nil }
  public var ended: ((DragGesture.Value) -> Void)?
  var tapCallback: (() -> Void)?

  public init(count: Int = 1) {
    self.count = count
  }

  public func onEnded(_ action: @escaping () -> Void) -> TapGesture {
    var copy = self
    copy.tapCallback = action
    copy.ended = { _ in action() }
    return copy
  }
}

public struct SpatialTapGesture: Gesture {
  public struct Value {
    public let location: CGPoint
  }
  public let count: Int
  public var changed: ((DragGesture.Value) -> Void)? { nil }
  public var ended: ((DragGesture.Value) -> Void)?

  public init(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local) {
    self.count = count
  }

  public func onEnded(_ action: @escaping (Value) -> Void) -> SpatialTapGesture {
    var copy = self
    copy.ended = { dragVal in action(Value(location: dragVal.location)) }
    return copy
  }
}

public struct LongPressGesture: Gesture {
  public let minimumDuration: Double
  public let maximumDistance: CGFloat
  public var changed: ((DragGesture.Value) -> Void)? { nil }
  public var ended: ((DragGesture.Value) -> Void)?
  var pressingChanged: ((Bool) -> Void)?

  public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
    self.minimumDuration = max(0, minimumDuration)
    self.maximumDistance = max(0, maximumDistance)
  }

  public func onChanged(_ action: @escaping (Bool) -> Void) -> LongPressGesture {
    var copy = self
    copy.pressingChanged = action
    return copy
  }

  public func onEnded(_ action: @escaping (Bool) -> Void) -> LongPressGesture {
    var copy = self
    copy.ended = { _ in action(true) }
    return copy
  }
}

public struct AccessibilityActionKind: Equatable, Sendable {
  public static let `default` = AccessibilityActionKind()
  public static let escape = AccessibilityActionKind()
  public static let magicTap = AccessibilityActionKind()
}

@propertyWrapper
public struct AccessibilityFocusState<Value: Hashable>: _StateProperty {
  public typealias Binding = FocusState<Value>.Binding
  private var inner: FocusState<Value>
  public init() where Value == Bool { inner = FocusState() }
  public init<T>() where Value == T? { inner = FocusState() }
  public var wrappedValue: Value {
    get { inner.wrappedValue }
    nonmutating set { inner.wrappedValue = newValue }
  }
  public var projectedValue: Binding { inner.projectedValue }
  func install(_ key: StateKey) { inner.install(key) }
}

private struct MaskView<Content: View, Mask: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let alignment: Alignment
  let maskContent: Mask

  var body: Never { fatalError("MaskView is primitive") }

  private static func collectMaskPaths(_ node: Element, parentOpacity: Double, into out: inout Path) {
    let effOpacity = parentOpacity * node.props.opacity
    guard node.props.visible, effOpacity > 0.01 else { return }
    let sx = node.props.scaleX
    let sy = node.props.scaleY
    let hasTransform = sx != 1.0 || sy != 1.0

    var local = Path()
    let r = CGRect(x: node.frame.minX, y: node.frame.minY, width: node.frame.width, height: node.frame.height)
    if r.width > 0.01 && r.height > 0.01 {
      if node.kind == .gradient {
        if let clip = node.clipPathBuilder {
          local.addPath(clip(CGRect(origin: .zero, size: r.size)).transformed(x: r.minX, y: r.minY))
        } else {
          local.addRect(r)
        }
      } else if let pb = node.pathBuilder {
        let bw = node.props.borderWidth
        if bw > 0 && (node.props.background?.opacity ?? 0) <= 0.001 {
          local.addPath(pb(r.insetBy(dx: -bw / 2, dy: -bw / 2)))
          let inner = r.insetBy(dx: bw / 2, dy: bw / 2)
          if inner.width > 0.1 && inner.height > 0.1 {
            local.addPath(pb(inner).reversed())
          }
        } else {
          local.addPath(pb(r))
        }
      } else if node.kind == .path {
        local.addPath(node.props.path.transformed(x: r.minX, y: r.minY))
      } else if node.kind == .shape {
        local.addPath(Path(roundedRect: r, cornerRadius: node.props.cornerRadius))
      } else if (node.props.background?.opacity ?? 0) > 0.01 {
        local.addPath(Path(roundedRect: r, cornerRadius: node.props.cornerRadius))
      }
    }

    for child in node.children {
      collectMaskPaths(child, parentOpacity: effOpacity, into: &local)
    }

    if hasTransform {
      let cx = node.frame.minX + node.frame.width * 0.5
      let cy = node.frame.minY + node.frame.height * 0.5
      out.addPath(local.transformed(x: cx - cx * sx, y: cy - cy * sy, sx: sx, sy: sy))
    } else {
      out.addPath(local)
    }
  }

  private final class MaskClipCache {
    var lastSize: CGSize = .zero
    var cachedPath = Path()
  }

  func _makeElement(path: ViewPath) -> Element {
    let saved = EnvironmentValues.current
    var base = _render(content, path: path.appending(index: 0))
    EnvironmentValues.current = saved
    let alignedMask = ZStack(alignment: alignment) { maskContent }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    var maskTemplate = normalize(_render(alignedMask, path: path.appending(id: "Mask")))
    EnvironmentValues.current = saved
    resolveEnvironment(
      &maskTemplate,
      inheritedForeground: saved.foregroundColor ?? .white,
      inheritedDisabled: !saved.isEnabled,
      inheritedOpacity: 1.0,
      inheritedVisible: true,
      inheritedLineLimit: nil,
      inheritedLineSpacing: 0
    )

    let probeSize = CGSize(width: 100, height: 100)
    var probeCopy = maskTemplate
    LayoutEngine().layout(root: &probeCopy, in: Size(width: probeSize.width, height: probeSize.height))
    var probePath = Path()
    Self.collectMaskPaths(probeCopy, parentOpacity: 1.0, into: &probePath)
    if probePath == Path(CGRect(origin: .zero, size: probeSize)) {
      base.props.clipped = true
      return base
    }

    let cache = MaskClipCache()
    cache.lastSize = probeSize
    cache.cachedPath = probePath
    let buildClip: (CGRect) -> Path = { [maskTemplate, cache] bounds in
      guard bounds.width > 0.01, bounds.height > 0.01 else { return Path() }
      let local: Path
      if cache.lastSize == bounds.size {
        local = cache.cachedPath
      } else {
        var copy = maskTemplate
        let engine = LayoutEngine()
        engine.layout(root: &copy, in: Size(width: bounds.width, height: bounds.height))
        var combined = Path()
        Self.collectMaskPaths(copy, parentOpacity: 1.0, into: &combined)
        cache.lastSize = bounds.size
        cache.cachedPath = combined
        local = combined
      }
      if bounds.minX != 0 || bounds.minY != 0 {
        return local.transformed(x: bounds.minX, y: bounds.minY)
      }
      return local
    }

    if base.clipPathBuilder != nil || base.kind == .scroll {
      var wrapperProps = NodeProps()
      wrapperProps.fillWidth = base.props.fillWidth
      wrapperProps.fillHeight = base.props.fillHeight
      wrapperProps.clipped = true
      var wrapper = Element(kind: .frame, props: wrapperProps, children: [base])
      wrapper.clipPathBuilder = buildClip
      return wrapper
    }
    base.props.clipped = true
    base.clipPathBuilder = buildClip
    return base
  }
}

extension View {
  public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
    MaskView(content: self, alignment: alignment, maskContent: mask())
  }

  public func mask<Mask: View>(_ mask: Mask) -> some View {
    MaskView(content: self, alignment: .center, maskContent: mask)
  }

  public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
    TransformView(content: self) { el in
      el.props.blurRadius = max(el.props.blurRadius, max(0, Double(radius)))
    }
  }

  public func brightness(_ amount: Double) -> some View {
    TransformView(content: self) { el in
      el.props.brightness = amount
    }
  }

  public func contrast(_ amount: Double) -> some View {
    TransformView(content: self) { el in
      el.props.contrast = amount
    }
  }

  public func grayscale(_ amount: Double) -> some View {
    saturation(max(0, 1.0 - amount))
  }

  public func colorScheme(_ colorScheme: ColorScheme) -> some View {
    environment(\.colorScheme, colorScheme)
  }

  public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
    if let colorScheme {
      return AnyView(environment(\.colorScheme, colorScheme))
    }
    return AnyView(self)
  }

  public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
    TransformView(content: self) { el in
      el.props.compositingGroup = true
    }
  }

  public func compositingGroup() -> some View {
    TransformView(content: self) { el in
      el.props.compositingGroup = true
    }
  }

  public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View {
    self
  }

  public func symbolVariant(_ variant: SymbolVariants) -> some View {
    self
  }

  public func symbolEffect<T: DiscreteSymbolEffect & SymbolEffect>(
    _ effect: T,
    options: SymbolEffectOptions = .default,
    value: some Equatable
  ) -> some View {
    self
  }

  public func symbolEffect<T: IndefiniteSymbolEffect & SymbolEffect>(
    _ effect: T,
    options: SymbolEffectOptions = .default,
    isActive: Bool = true
  ) -> some View {
    self
  }

  public func contentTransition(_ transition: ContentTransition) -> some View {
    self
  }

  public func pointerStyle(_ style: PointerStyle?) -> some View {
    self
  }

  public func onContinuousHover(
    coordinateSpace: some CoordinateSpaceProtocol = .local,
    perform action: @escaping (HoverPhase) -> Void
  ) -> some View {
    let isGlobal = (coordinateSpace.coordinateSpace == .global)
    return TransformView(content: self) { el in
      let prev = el.continuousHoverAction
      el.continuousHoverGlobal = isGlobal
      el.continuousHoverAction = { phase in
        action(phase)
        prev?(phase)
      }
    }
  }

  public func layoutPriority(_ value: Double) -> some View {
    TransformView(content: self) { el in
      el.props.layoutPriority = value
    }
  }

  public func position(x: CGFloat = 0, y: CGFloat = 0) -> some View {
    GeometryReader { proxy in
      self
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .offset(x: x - proxy.size.width / 2, y: y - proxy.size.height / 2)
    }
  }

  public func position(_ position: CGPoint) -> some View {
    self.position(x: position.x, y: position.y)
  }

  public func badge(_ count: Int) -> some View { self }
  public func badge(_ label: Text?) -> some View { self }
  public func badge(_ key: LocalizedStringKey?) -> some View { self }
  @_disfavoredOverload
  public func badge<S: StringProtocol>(_ label: S?) -> some View { self }

  public func writingToolsBehavior(_ behavior: WritingToolsBehavior) -> some View { self }
  public func autocorrectionDisabled(_ disable: Bool = true) -> some View { self }
  public func submitLabel(_ submitLabel: SubmitLabel) -> some View { self }

  public func simultaneousGesture<T: Gesture>(_ gesture: T, isEnabled: Bool = true) -> some View {
    TransformView(content: self) { el in
      guard isEnabled else { return }
      if let lp = gesture as? LongPressGesture {
        el.longPressAction = Element.LongPressConfig(
          minimumDuration: lp.minimumDuration,
          maximumDistance: Double(lp.maximumDistance),
          onPressingChanged: lp.pressingChanged,
          onEnded: { lp.ended?(DragGesture.Value(location: .zero, startLocation: .zero, translation: .zero, time: Date())) }
        )
      } else if let tap = gesture as? TapGesture, let cb = tap.tapCallback {
        if tap.count == 2 {
          let prev = el.doubleTapAction
          el.doubleTapAction = {
            cb()
            prev?()
          }
        } else {
          el.simultaneousActions.append(cb)
        }
      } else if let spatial = gesture as? SpatialTapGesture, spatial.count == 2 {
        let prev = el.doubleTapLocationAction
        el.doubleTapLocationAction = { pt in
          spatial.ended?(
            DragGesture.Value(location: pt, startLocation: pt, translation: .zero, time: Date()))
          prev?(pt)
        }
      } else {
        el.simultaneousDragActions.append { val, ended in
          if ended { gesture.ended?(val) } else { gesture.changed?(val) }
        }
      }
    }
  }

  public func highPriorityGesture<T: Gesture>(_ gesture: T, isEnabled: Bool = true) -> some View {
    TransformView(content: self) { el in
      guard isEnabled else { return }
      if let lp = gesture as? LongPressGesture {
        el.longPressAction = Element.LongPressConfig(
          minimumDuration: lp.minimumDuration,
          maximumDistance: Double(lp.maximumDistance),
          onPressingChanged: lp.pressingChanged,
          onEnded: { lp.ended?(DragGesture.Value(location: .zero, startLocation: .zero, translation: .zero, time: Date())) }
        )
      } else if let tap = gesture as? TapGesture, let cb = tap.tapCallback {
        if tap.count == 2 {
          el.doubleTapAction = cb
        } else {
          el.highPriorityAction = cb
        }
      } else {
        el.highPriorityDragMinimumDistance = Double((gesture as? DragGesture)?.minimumDistance ?? 0)
        el.highPriorityDragAction = { val, ended in
          if ended { gesture.ended?(val) } else { gesture.changed?(val) }
        }
      }
    }
  }

  public func dropDestination<T>(
    for payloadType: T.Type = T.self,
    action: @escaping ([T], CGPoint) -> Bool,
    isTargeted: @escaping (Bool) -> Void = { _ in }
  ) -> some View {
    self
  }

  public func onDrop(
    of supportedTypes: [Any],
    isTargeted: Binding<Bool>?,
    perform action: @escaping ([NSItemProvider]) -> Bool
  ) -> some View {
    self
  }

  public func onDrop(
    of supportedTypes: [Any],
    isTargeted: Binding<Bool>?,
    perform action: @escaping ([NSItemProvider], CGPoint) -> Bool
  ) -> some View {
    self
  }

  public func onDrop(
    of supportedContentTypes: [Any],
    delegate: any DropDelegate
  ) -> some View {
    self
  }

  public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View { self }

  public func onDrag<V: View>(
    _ data: @escaping () -> NSItemProvider,
    @ViewBuilder preview: () -> V
  ) -> some View {
    self
  }

  public func dragConfiguration(_ configuration: DragConfiguration) -> some View { self }

  public func onDragSessionUpdated(_ action: @escaping (DragSession) -> Void) -> some View { self }

  public func onDropSessionUpdated(_ action: @escaping (DropSession) -> Void) -> some View { self }

  public func disableAutocorrection(_ disable: Bool?) -> some View { self }

  public func fileDialogDefaultDirectory(_ defaultDirectory: URL?) -> some View { self }

  public func dialogSuppressionToggle(isSuppressed: Binding<Bool>) -> some View { self }
  public func dialogSuppressionToggle(_ label: Text, isSuppressed: Binding<Bool>) -> some View { self }
  public func dialogSuppressionToggle(_ titleKey: LocalizedStringKey, isSuppressed: Binding<Bool>) -> some View { self }
  @_disfavoredOverload
  public func dialogSuppressionToggle<S: StringProtocol>(_ label: S, isSuppressed: Binding<Bool>) -> some View { self }

  public func accessibilityHint(_ hint: Text) -> some View { self }
  public func accessibilityHint(_ hintKey: LocalizedStringKey) -> some View { self }
  @_disfavoredOverload
  public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { self }

  public func accessibilityAction(
    _ actionKind: AccessibilityActionKind = .default,
    _ handler: @escaping () -> Void
  ) -> some View {
    self
  }

  public func accessibilityAction(
    named name: Text,
    _ handler: @escaping () -> Void
  ) -> some View {
    self
  }

  public func accessibilityAction(
    named nameKey: LocalizedStringKey,
    _ handler: @escaping () -> Void
  ) -> some View {
    self
  }

  @_disfavoredOverload
  public func accessibilityAction<S: StringProtocol>(
    named name: S,
    _ handler: @escaping () -> Void
  ) -> some View {
    self
  }
}

public enum DropOperation: Sendable, Hashable {
  case cancel
  case forbidden
  case copy
  case move
}

public struct DropProposal: Sendable, Hashable {
  public let operation: DropOperation
  public init(operation: DropOperation) {
    self.operation = operation
  }
}

public struct DropInfo: Sendable {
  public let location: CGPoint
  public init(location: CGPoint = .zero) {
    self.location = location
  }
  public func hasItemsConforming(to contentTypes: [Any]) -> Bool { false }
  public func itemProviders(for contentTypes: [Any]) -> [NSItemProvider] { [] }
}

public protocol DropDelegate {
  func validateDrop(info: DropInfo) -> Bool
  func performDrop(info: DropInfo) -> Bool
  func dropEntered(info: DropInfo)
  func dropUpdated(info: DropInfo) -> DropProposal?
  func dropExited(info: DropInfo)
}

public extension DropDelegate {
  func validateDrop(info: DropInfo) -> Bool { true }
  func dropEntered(info: DropInfo) {}
  func dropUpdated(info: DropInfo) -> DropProposal? { nil }
  func dropExited(info: DropInfo) {}
}

public struct DragConfiguration: Sendable, Hashable {
  public struct Operations: Sendable, Hashable {
    public var allowCopy: Bool
    public var allowMove: Bool
    public var allowDelete: Bool
    public init(allowCopy: Bool = true, allowMove: Bool = true, allowDelete: Bool = false) {
      self.allowCopy = allowCopy
      self.allowMove = allowMove
      self.allowDelete = allowDelete
    }
  }
  public var operationsWithinApp: Operations
  public var operationsOutsideApp: Operations
  public init(
    operationsWithinApp: Operations = Operations(),
    operationsOutsideApp: Operations = Operations()
  ) {
    self.operationsWithinApp = operationsWithinApp
    self.operationsOutsideApp = operationsOutsideApp
  }
}

public struct DragSession: Sendable {
  public enum Phase: Sendable, Hashable {
    case initial
    case active
    case ended
  }
  public let phase: Phase
  public let location: CGPoint
  public init(phase: Phase = .ended, location: CGPoint = .zero) {
    self.phase = phase
    self.location = location
  }
}

public struct DropSession: Sendable {
  public enum Phase: Sendable, Hashable {
    case entering
    case active
    case exiting
    case ended
  }
  public let phase: Phase
  public let location: CGPoint
  public let size: CGSize
  public init(phase: Phase = .ended, location: CGPoint = .zero, size: CGSize = .zero) {
    self.phase = phase
    self.location = location
    self.size = size
  }
}

extension View {

  public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { self }
  public func accessibilityFocused(_ condition: AccessibilityFocusState<Bool>.Binding) -> some View { self }
  public func accessibilityFocused<Value: Hashable>(
    _ binding: AccessibilityFocusState<Value?>.Binding,
    equals value: Value
  ) -> some View { self }
  public func accessibilityInputLabels(_ inputLabels: [LocalizedStringKey]) -> some View { self }
  public func accessibilityInputLabels<S: StringProtocol>(_ inputLabels: [S]) -> some View { self }
  public func accessibilityRespondsToUserInteraction(_ respondsToUserInteraction: Bool = true) -> some View { self }
  public func accessibilitySortPriority(_ sortPriority: Double) -> some View { self }
  public func accessibilityRepresentation<V: View>(@ViewBuilder representation: () -> V) -> some View { self }

  public func tag<V: Hashable>(_ tag: V) -> some View {
    TransformView(content: self) { el in
      el.tagValue = AnyHashable(tag)
    }
  }
}

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  open class NSItemProvider: NSObject, @unchecked Sendable {}
#endif

// MARK: - Additional Environment Values (DismissAction, ControlActiveState, DisplayScale, etc.)

public struct DismissAction: Sendable {
  private let handler: @Sendable () -> Void

  public init(_ handler: @escaping () -> Void = {}) {
    nonisolated(unsafe) let fn = handler
    self.handler = { fn() }
  }

  public func callAsFunction() {
    handler()
  }
}

public enum ControlActiveState: Equatable, Hashable, Sendable {
  case key
  case active
  case inactive
}

public enum DynamicTypeSize: Hashable, Comparable, CaseIterable, Sendable {
  case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
}

private enum DismissKey: EnvironmentKey {
  static let defaultValue = DismissAction()
}

private enum IsSearchingKey: EnvironmentKey {
  static let defaultValue = false
}

private enum DismissSearchKey: EnvironmentKey {
  static let defaultValue = DismissAction()
}

private enum ControlActiveStateKey: EnvironmentKey {
  static let defaultValue: ControlActiveState = .key
}

private enum AppearsActiveKey: EnvironmentKey {
  static let defaultValue = true
}

private enum DisplayScaleKey: EnvironmentKey {
  static let defaultValue: CGFloat = 1.0
}

private enum PixelLengthKey: EnvironmentKey {
  static let defaultValue: CGFloat = 1.0
}

private enum LabelsHiddenKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  public var dismiss: DismissAction {
    get { self[DismissKey.self] }
    set { self[DismissKey.self] = newValue }
  }
  public var isSearching: Bool {
    get { self[IsSearchingKey.self] }
    set { self[IsSearchingKey.self] = newValue }
  }
  public var dismissSearch: DismissAction {
    get { self[DismissSearchKey.self] }
    set { self[DismissSearchKey.self] = newValue }
  }
  public var controlActiveState: ControlActiveState {
    get { self[ControlActiveStateKey.self] }
    set { self[ControlActiveStateKey.self] = newValue }
  }
  public var appearsActive: Bool {
    get { self[AppearsActiveKey.self] }
    set { self[AppearsActiveKey.self] = newValue }
  }
  public var displayScale: CGFloat {
    get { self[DisplayScaleKey.self] }
    set { self[DisplayScaleKey.self] = newValue }
  }
  public var pixelLength: CGFloat {
    get { self[PixelLengthKey.self] }
    set { self[PixelLengthKey.self] = newValue }
  }
  package var labelsHidden: Bool {
    get { self[LabelsHiddenKey.self] }
    set { self[LabelsHiddenKey.self] = newValue }
  }
}

extension View {
  public func labelsHidden() -> some View {
    environment(\.labelsHidden, true)
  }

  public func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
    self
  }
}

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(Combine)
  extension View {
    public func onReceive<P: Combine.Publisher>(
      _ publisher: P,
      perform action: @escaping (P.Output) -> Void
    ) -> some View where P.Failure == Never {
      OnReceiveCombineView(content: self, publisher: publisher, action: action)
    }
  }

  private final class CancellableBox {
    var cancellable: AnyCancellable?
  }

  private struct OnReceiveCombineView<Content: View, P: Combine.Publisher>: View where P.Failure == Never {
    let content: Content
    let publisher: P
    let action: (P.Output) -> Void
    @State private var box = CancellableBox()

    var body: some View {
      content
        .onAppear {
          box.cancellable = publisher.sink(receiveValue: action)
        }
        .onDisappear {
          box.cancellable?.cancel()
          box.cancellable = nil
        }
    }
  }
#endif
