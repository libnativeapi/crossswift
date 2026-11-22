import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public struct Anchor<Value> {
  let value: Value
  init(_ value: Value) { self.value = value }

  public struct Source {
    let resolve: (CGRect) -> Value
    init(_ resolve: @escaping (CGRect) -> Value) { self.resolve = resolve }
  }
}

extension Anchor: Equatable where Value: Equatable {
  public static func == (lhs: Anchor<Value>, rhs: Anchor<Value>) -> Bool {
    lhs.value == rhs.value
  }
}

extension Anchor: @unchecked Sendable where Value: Sendable {}

extension Anchor.Source where Value == CGRect {
  public static var bounds: Anchor<CGRect>.Source { Anchor.Source { $0 } }
  public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source {
    Anchor.Source { base in
      CGRect(x: base.minX + r.minX, y: base.minY + r.minY, width: r.width, height: r.height)
    }
  }
}

extension Anchor.Source where Value == CGPoint {
  public static var topLeading: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.minX, y: $0.minY) } }
  public static var top: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.midX, y: $0.minY) } }
  public static var topTrailing: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.maxX, y: $0.minY) } }
  public static var leading: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.minX, y: $0.midY) } }
  public static var center: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.midX, y: $0.midY) } }
  public static var trailing: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.maxX, y: $0.midY) } }
  public static var bottomLeading: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.minX, y: $0.maxY) } }
  public static var bottom: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.midX, y: $0.maxY) } }
  public static var bottomTrailing: Anchor<CGPoint>.Source { Anchor.Source { CGPoint(x: $0.maxX, y: $0.maxY) } }
  public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source {
    Anchor.Source { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) }
  }
}

extension GeometryProxy {
  public subscript<T>(_ anchor: Anchor<T>) -> T {
    if let rect = anchor.value as? CGRect {
      let local = CGRect(
        x: rect.minX - snapshot.rect.minX,
        y: rect.minY - snapshot.rect.minY,
        width: rect.width,
        height: rect.height
      )
      return local as! T
    }
    if let pt = anchor.value as? CGPoint {
      let local = CGPoint(x: pt.x - snapshot.rect.minX, y: pt.y - snapshot.rect.minY)
      return local as! T
    }
    return anchor.value
  }
}

public protocol PreferenceKey {
  associatedtype Value
  static var defaultValue: Value { get }
  static func reduce(value: inout Value, nextValue: () -> Value)
}
struct PreferenceValue {
  var value: Any
  let reduce: (Any, Any) -> Any
}
struct PreferenceReader<Content: View, Key: PreferenceKey>: View, _PrimitiveView
where Key.Value: Equatable {
  typealias Body = Never
  let content: Content
  let action: (Key.Value) -> Void
  @State private var previous: Key.Value?
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var element = _render(content, path: path)
    let old = element.preferenceAction
    element.preferenceAction = { values in
      old?(values)
      let next = values[ObjectIdentifier(Key.self)]?.value as? Key.Value ?? Key.defaultValue
      if previous != next {
        previous = next
        action(next)
      }
    }
    return element
  }
}
extension View {
  public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
    TransformView(content: self) { node in
      node.preferences[ObjectIdentifier(K.self)] = PreferenceValue(
        value: value,
        reduce: { old, new in
          var value = old as! K.Value
          K.reduce(value: &value, nextValue: { new as! K.Value })
          return value
        })
    }
  }
  public func onPreferenceChange<K: PreferenceKey>(
    _ key: K.Type = K.self, perform action: @escaping (K.Value) -> Void
  ) -> some View where K.Value: Equatable {
    PreferenceReader<Self, K>(content: self, action: action)
  }
  public func transformPreference<K: PreferenceKey>(
    _ key: K.Type, _ transform: @escaping (inout K.Value) -> Void
  ) -> some View {
    TransformView(content: self) { node in
      node.preferenceTransforms.append { preferences in
        let identifier = ObjectIdentifier(K.self)
        var value = preferences[identifier]?.value as? K.Value ?? K.defaultValue
        transform(&value)
        preferences[identifier] = PreferenceValue(
          value: value,
          reduce: { old, new in
            var result = old as! K.Value
            K.reduce(value: &result) { new as! K.Value }
            return result
          })
      }
    }
  }

  public func overlayPreferenceValue<K: PreferenceKey, Overlay: View>(
    _ key: K.Type, @ViewBuilder _ content: @escaping (K.Value) -> Overlay
  ) -> some View where K.Value: Equatable {
    PreferenceOverlay<Overlay, Self, K>(content: self, overlay: content)
  }

  public func anchorPreference<A, K: PreferenceKey>(
    key: K.Type = K.self,
    value source: Anchor<A>.Source,
    transform: @escaping (Anchor<A>) -> K.Value
  ) -> some View {
    self.preference(key: key, value: transform(Anchor(source.resolve(.zero))))
  }

}
func resolvePreferences(_ node: Element) -> [ObjectIdentifier: PreferenceValue] {
  if !node.hasPreferences { return [:] }
  var result = node.preferences
  for child in node.children {
    for (key, value) in resolvePreferences(child) {
      if let old = result[key] {
        result[key] = PreferenceValue(
          value: value.reduce(old.value, value.value), reduce: value.reduce)
      } else {
        result[key] = value
      }
    }
  }
  for transform in node.preferenceTransforms { transform(&result) }
  if let action = node.preferenceAction {
    let values = result
    LifecycleRegistry.shared.enqueue { action(values) }
  }
  return result
}
private struct PreferenceOverlay<Overlay: View, Content: View, Key: PreferenceKey>: View
where Key.Value: Equatable {
  let content: Content
  let overlay: (Key.Value) -> Overlay
  @State private var value = Key.defaultValue

  var body: some View {
    content.onPreferenceChange(Key.self) { value = $0 }.overlay { overlay(value) }
  }
}

public struct GridItem: Sendable {
  public enum Size: Sendable {
    case fixed(CGFloat)
    case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
    case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
  }
  public let size: Size
  public let spacing: CGFloat?
  public let alignment: Alignment?
  public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
    self.size = size
    self.spacing = spacing
    self.alignment = alignment
  }
}
public struct LazyVGrid<Content: View>: View {
  let columns: [GridItem]
  let spacing: CGFloat
  let content: Content
  public init(
    columns: [GridItem],
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat? = nil,
    pinnedViews: PinnedScrollableViews = [],
    @ViewBuilder content: () -> Content
  ) {
    self.columns = columns
    self.spacing = spacing ?? 8
    self.content = content()
  }
  public var body: some View {
    GridContent(layout: GridLayout(columns: columns, spacing: spacing), content: content)
  }
}

private struct GridContent<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let layout: GridLayout
  let content: Content
  var body: Never { fatalError("Grid content is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let stackKey = AnyHashable(path)
    let savedCtx = EnvironmentValues.current.lazyContainerContext
    let colEstimate: Int
    if layout.columns.count == 1, case .adaptive(let minW, _) = layout.columns[0].size {
      let vw = EnvironmentValues.current.scrollViewportContext?.viewportWidth ?? 600
      colEstimate = max(1, Int((vw + Double(layout.spacing)) / (Double(minW) + Double(layout.spacing))))
    } else {
      colEstimate = max(1, layout.columns.count)
    }
    EnvironmentValues.current.lazyContainerContext = LazyContainerContext(
      key: stackKey, axis: .verticalGrid(columns: colEstimate), spacing: Double(layout.spacing))
    defer { EnvironmentValues.current.lazyContainerContext = savedCtx }
    let contentElement = _render(content, path: path)
    let children = flattenChildren(contentElement)
    var props = NodeProps()
    props.isLazyContainer = contentElement.props.isLazyContainer || children.count > 72
    var node = Element(kind: .customLayout, props: props, children: children)
    node.layout = layout
    node.lazyCacheKey = stackKey
    return node
  }
}
private struct GridLayout: _LayoutBridge {
  var translatesWithBounds: Bool { true }
  let columns: [GridItem]
  let spacing: CGFloat
  func widths(_ proposal: ProposedViewSize) -> [CGFloat] {
    let width = proposal.width ?? 500
    if columns.count == 1, case .adaptive(let minimum, let maximum) = columns[0].size {
      let n = max(1, Int((width + spacing) / (minimum + spacing)))
      return Array(
        repeating: min(maximum, (width - CGFloat(n - 1) * spacing) / CGFloat(n)), count: n)
    }
    let flexible = columns.filter {
      if case .fixed = $0.size { return false }
      return true
    }.count
    let fixed = columns.reduce(CGFloat(0)) { sum, column in
      if case .fixed(let w) = column.size { return sum + w }
      return sum
    }
    let remaining =
      max(0, width - fixed - CGFloat(max(0, columns.count - 1)) * spacing)
      / CGFloat(max(1, flexible))
    return columns.map {
      switch $0.size {
      case .fixed(let w): return w
      case .flexible(let min, let max), .adaptive(let min, let max):
        return Swift.min(max, Swift.max(min, remaining))
      }
    }
  }
  func frames(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> [CGRect] {
    let widths = widths(proposal)
    guard !widths.isEmpty else { return [] }
    var frames: [CGRect] = []
    var y: CGFloat = 0
    frames.reserveCapacity(children.count)
    for start in stride(from: 0, to: children.count, by: widths.count) {
      let end = min(start + widths.count, children.count)
      var height: CGFloat = -.infinity
      for i in start..<end {
        let size = engine.sizeThatFits(
          children[i], proposal: ProposedViewSize(width: widths[i - start], height: nil))
        height = max(height, size.height)
      }
      var x: CGFloat = 0
      for i in start..<end {
        let w = widths[i - start]
        frames.append(CGRect(x: x, y: y, width: w, height: height))
        x += w + spacing
      }
      y += height + spacing
    }
    return frames
  }
  func measure(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> CGSize {
    let slots = frames(proposal, children: children, engine: engine)
    guard let first = slots.first else { return .zero }
    var result = CGSize(width: first.maxX, height: first.maxY)
    for frame in slots.dropFirst() {
      result.width = max(result.width, frame.maxX)
      result.height = max(result.height, frame.maxY)
    }
    return result
  }
  func placements(_ bounds: CGRect, children: [Element], engine: LayoutEngine) -> [CGRect] {
    let slots = frames(ProposedViewSize(bounds.size), children: children, engine: engine)
    return children.indices.map { index in
      guard index < slots.count else { return .zero }
      let slot = slots[index]
      let size = engine.sizeThatFits(children[index], proposal: ProposedViewSize(slot.size))
      return CGRect(
        x: bounds.minX + slot.minX, y: bounds.minY + slot.minY,
        width: size.width, height: size.height)
    }
  }
}
public struct Transaction: Equatable, Sendable {
  public var animation: Animation?
  public var disablesAnimations: Bool = false
  public init(animation: Animation? = nil) { self.animation = animation }
}
extension View {
  public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
    TransformView(content: self) { node in
      var transaction = Transaction(animation: node.props.animation)
      transform(&transaction)
      if transaction.disablesAnimations {
        node.props.animation = nil
        node.props.animationDisabled = true
      } else {
        node.props.animation = transaction.animation
      }
    }
  }
}
