import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public struct ZStack<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  let content: Content
  let alignment: Alignment
  public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.content = content()
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var props = NodeProps()
    props.alignment = alignment
    return Element(
      kind: .zStack, props: props, children: flattenChildren(_render(content, path: path)))
  }
}
/// Consecutive offscreen rows share one layout element. Keep unknown heights
/// separate so the first measurement of the visible rows also sizes the gap.
private struct LazyRowGap: Hashable {
  var firstID: AnyHashable?
  var measuredExtent: Double = 0
  var estimatedCount: Int = 0
  var count: Int = 0
  let spacing: Double

  mutating func include(_ id: AnyHashable, measuredHeight: Double?) {
    if count == 0 { firstID = id }
    count += 1
    if let measuredHeight {
      measuredExtent += measuredHeight
    } else {
      estimatedCount += 1
    }
  }

  func height(average: Double) -> Double {
    measuredExtent + Double(estimatedCount) * average + Double(count - 1) * spacing
  }
}

/// Under a uniform estimate, any contiguous gap has an analytic extent.
/// If a newly visible row reveals a different height during this layout pass,
/// resolve the same gap by the actual IDs in the collection being laid out.
private final class UniformLazyRowGap: Hashable {
  let firstID: AnyHashable
  let count: Int
  let spacing: Double
  let mixedHeight: (LazyHeightCache, AnyHashable) -> Double

  init(firstID: AnyHashable, count: Int, spacing: Double,
       mixedHeight: @escaping (LazyHeightCache, AnyHashable) -> Double) {
    self.firstID = firstID
    self.count = count
    self.spacing = spacing
    self.mixedHeight = mixedHeight
  }

  static func == (lhs: UniformLazyRowGap, rhs: UniformLazyRowGap) -> Bool {
    lhs.firstID == rhs.firstID && lhs.count == rhs.count && lhs.spacing == rhs.spacing
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(firstID)
    hasher.combine(count)
    hasher.combine(spacing)
  }

  func extent(cache: LazyHeightCache, stack: AnyHashable) -> Double {
    let rows = cache.uniformEstimate(stack: stack).map { $0 * Double(count) }
      ?? mixedHeight(cache, stack)
    return rows + Double(count - 1) * spacing
  }
}

final class LazyHeightCache {
  struct StackViewportMetrics: Equatable {
    var offsetX: Double
    var offsetY: Double
    var viewportWidth: Double
    var viewportHeight: Double
  }
  nonisolated(unsafe) static let shared = LazyHeightCache()
  private var heightsByStack: [AnyHashable: [AnyHashable: Double]] = [:]
  private var extentCounts: [AnyHashable: [Double: Int]] = [:]
  private var averagesByStack: [AnyHashable: Double] = [:]
  private struct VerticalSelection {
    let viewport: StackViewportMetrics?
    let measurements: Int
  }
  private var measurementRevisions: [AnyHashable: Int] = [:]
  private var verticalSelections: [AnyHashable: VerticalSelection] = [:]
  private var viewportsByStack: [AnyHashable: StackViewportMetrics] = [:]

  func record(stack: AnyHashable, item: AnyHashable, height: Double) {
    guard height.isFinite, height > 0 else { return }
    if let previous = heightsByStack[stack]?[item] {
      guard previous != height else { return }
      if extentCounts[stack]?[previous] == 1 {
        extentCounts[stack]?.removeValue(forKey: previous)
      } else {
        extentCounts[stack]?[previous]? -= 1
      }
    }
    measurementRevisions[stack, default: 0] += 1
    heightsByStack[stack, default: [:]][item] = height
    extentCounts[stack, default: [:]][height, default: 0] += 1
    let dict = heightsByStack[stack]!
    let sample = dict.values.prefix(32)
    if !sample.isEmpty {
      averagesByStack[stack] = sample.reduce(0, +) / Double(sample.count)
    }
  }

  func hasSamples(stack: AnyHashable) -> Bool {
    !(heightsByStack[stack]?.isEmpty ?? true)
  }

  func recordVerticalSelection(stack: AnyHashable) {
    verticalSelections[stack] = VerticalSelection(
      viewport: viewportsByStack[stack], measurements: measurementRevisions[stack] ?? 0)
  }

  func canRefineVerticalSelection(stack: AnyHashable) -> Bool {
    guard let selection = verticalSelections[stack] else { return false }
    return selection.viewport != viewportsByStack[stack]
      || selection.measurements != measurementRevisions[stack] ?? 0
  }

  func recordStackViewport(
    stack: AnyHashable, offsetX: Double, offsetY: Double,
    viewportWidth: Double, viewportHeight: Double
  ) {
    viewportsByStack[stack] = StackViewportMetrics(
      offsetX: offsetX, offsetY: offsetY,
      viewportWidth: viewportWidth, viewportHeight: viewportHeight)
  }

  func stackViewport(stack: AnyHashable) -> StackViewportMetrics? {
    viewportsByStack[stack]
  }

  func estimatedHeight(stack: AnyHashable, item: AnyHashable) -> Double {
    measuredHeight(stack: stack, item: item) ?? averageHeight(stack: stack)
  }

  /// Unknown rows use the estimate; if every known row agrees, every step
  /// in the estimated stack has exactly the same height, regardless of order.
  func uniformEstimate(stack: AnyHashable) -> Double? {
    guard let counts = extentCounts[stack] else { return 44 }
    return counts.count == 1 ? counts.keys.first : nil
  }

  func placeholderExtent(stack: AnyHashable, item: AnyHashable) -> Double {
    if let gap = item.base as? UniformLazyRowGap {
      return gap.extent(cache: self, stack: stack)
    }
    if let gap = item.base as? LazyRowGap {
      return gap.height(average: averageHeight(stack: stack))
    }
    return estimatedHeight(stack: stack, item: item)
  }

  func measuredHeight(stack: AnyHashable, item: AnyHashable) -> Double? {
    heightsByStack[stack]?[item]
  }

  func averageHeight(stack: AnyHashable) -> Double {
    averagesByStack[stack] ?? 44.0
  }
}

struct ScrollViewportContext: Equatable {
  static let bucketSpan: Double = 128.0
  static let virtualizationThreshold = 24
  static func quantize(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value / bucketSpan).rounded(.down) * bucketSpan
  }
  var offsetX: Double = 0
  var offsetY: Double = 0
  var viewportWidth: Double = 800
  var viewportHeight: Double = 600
  var targetID: AnyHashable?
}

struct LazyContainerContext: Equatable {
  enum AxisKind: Equatable {
    case verticalStack
    case horizontalStack
    case verticalGrid(columns: Int)
    case horizontalGrid(rows: Int)
  }
  var key: AnyHashable
  var axis: AxisKind
  var spacing: Double
}

private enum ScrollViewportContextKey: EnvironmentKey {
  static let defaultValue: ScrollViewportContext? = nil
}

private enum LazyStackKeyKey: EnvironmentKey {
  static let defaultValue: AnyHashable? = nil
}

private enum LazyContainerContextKey: EnvironmentKey {
  static let defaultValue: LazyContainerContext? = nil
}

extension EnvironmentValues {
  var scrollViewportContext: ScrollViewportContext? {
    get { self[ScrollViewportContextKey.self] }
    set { self[ScrollViewportContextKey.self] = newValue }
  }
  var lazyStackKey: AnyHashable? {
    get { self[LazyStackKeyKey.self] }
    set { self[LazyStackKeyKey.self] = newValue }
  }
  var lazyContainerContext: LazyContainerContext? {
    get { self[LazyContainerContextKey.self] }
    set { self[LazyContainerContextKey.self] = newValue }
  }
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View,
  _PrimitiveView
{
  public typealias Body = Never
  let data: Data
  let id: KeyPath<Data.Element, ID>
  let content: (Data.Element) -> Content
  public init(
    _ data: Data, id: KeyPath<Data.Element, ID>,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.content = content
  }
  public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content)
  where Data.Element: Identifiable, Data.Element.ID == ID {
    self.init(data, id: \.id, content: content)
  }
  public init<C: MutableCollection & RandomAccessCollection>(
    _ data: Binding<C>,
    @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
  ) where Data == Binding<C>, C.Element: Identifiable, ID == C.Element.ID {
    self.init(data, id: \.id, content: content)
  }
  public init<C: MutableCollection & RandomAccessCollection>(
    _ data: Binding<C>,
    id: KeyPath<C.Element, ID>,
    @ViewBuilder content: @escaping (Binding<C.Element>) -> Content
  ) where Data == Binding<C> {
    self.data = data
    self.id = (\Binding<C.Element>.wrappedValue).appending(path: id)
    self.content = content
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let env = EnvironmentValues.current
    let lazyCtx: LazyContainerContext? =
      env.lazyContainerContext
      ?? env.lazyStackKey.map { LazyContainerContext(key: $0, axis: .verticalStack, spacing: 8) }
    if let lazyCtx, let viewport = env.scrollViewportContext,
      data.count > ScrollViewportContext.virtualizationThreshold
    {
      EvaluationGraph.active?.recordScrollViewportRead()
      let stackKey = lazyCtx.key
      let spacing = lazyCtx.spacing
      let stackMetrics = LazyHeightCache.shared.stackViewport(stack: stackKey)
      let seeded = LazyHeightCache.shared.hasSamples(stack: stackKey)
      let vpW = max(120, stackMetrics?.viewportWidth ?? viewport.viewportWidth)
      let vpH = max(120, stackMetrics?.viewportHeight ?? viewport.viewportHeight)
      let localOffsetX = viewport.offsetX - (stackMetrics?.offsetX ?? 0)
      let localOffsetY = viewport.offsetY - (stackMetrics?.offsetY ?? 0)
      let avgExtent = LazyHeightCache.shared.averageHeight(stack: stackKey)
      let approxSpan = Double(data.count) * (avgExtent + spacing)
      let leadingBuffer = 260.0
      let trailingBuffer = ScrollViewportContext.bucketSpan + 260.0
      var children: [Element] = []

      switch lazyCtx.axis {
      case .verticalStack:
        LazyHeightCache.shared.recordVerticalSelection(stack: stackKey)
        let clampedOffsetY = seeded
          ? max(0, min(localOffsetY, max(0, approxSpan - vpH)))
          : max(0, localOffsetY)
        let minVisibleY = clampedOffsetY - leadingBuffer
        let maxVisibleY = clampedOffsetY + vpH + trailingBuffer
        func appendRow(_ item: Data.Element, id itemID: AnyHashable) {
          let itemView = EvaluationGraph.active?.trackObservation { content(item) } ?? content(item)
          var child = _render(itemView, path: path.appending(id: itemID))
          child.explicitID = itemID
          children.append(child)
        }

        if viewport.targetID == nil, spacing >= 0, seeded || minVisibleY <= 0,
          let uniform = LazyHeightCache.shared.uniformEstimate(stack: stackKey),
          uniform.isFinite, spacing.isFinite, minVisibleY.isFinite, maxVisibleY.isFinite
        {
          let count = data.count
          let step = uniform + spacing
          func bounded(_ index: Double) -> Int {
            if index <= 0 { return 0 }
            if index >= Double(count) { return count }
            return Int(index)
          }
          // Include both boundaries, as in the heterogeneous scan below.
          let first = bounded(ceil((minVisibleY - uniform) / step))
          let end = max(seeded ? 0 : min(14, count), bounded(floor(maxVisibleY / step) + 1))
          let lower = data.index(data.startIndex, offsetBy: first)
          let upper = data.index(data.startIndex, offsetBy: end)
          func appendUniformGap(_ range: Range<Data.Index>, count: Int) {
            guard count > 0 else { return }
            let gap = UniformLazyRowGap(
              firstID: AnyHashable(data[range.lowerBound][keyPath: id]),
              count: count, spacing: spacing
            ) { [data, id] cache, stack in
              var sum = 0.0
              for item in data[range] {
                let itemID = AnyHashable(item[keyPath: id])
                sum += cache.estimatedHeight(stack: stack, item: itemID)
              }
              return sum
            }
            var placeholder = NodeProps()
            placeholder.frameHeight = uniform * Double(count) + Double(count - 1) * spacing
            placeholder.fillWidth = true
            placeholder.isLazyPlaceholder = true
            children.append(Element(kind: .frame, props: placeholder, explicitID: AnyHashable(gap)))
          }

          appendUniformGap(data.startIndex..<lower, count: first)
          for item in data[lower..<upper] { appendRow(item, id: AnyHashable(item[keyPath: id])) }
          appendUniformGap(upper..<data.endIndex, count: count - end)
          break
        }

        var gap = LazyRowGap(spacing: spacing)
        func appendGap() {
          guard gap.count > 0 else { return }
          var placeholder = NodeProps()
          placeholder.frameHeight = gap.height(average: avgExtent)
          placeholder.fillWidth = true
          placeholder.isLazyPlaceholder = true
          children.append(Element(kind: .frame, props: placeholder, explicitID: AnyHashable(gap)))
          gap = LazyRowGap(spacing: spacing)
        }

        var runningY = 0.0
        for (index, item) in data.enumerated() {
          let itemID = AnyHashable(item[keyPath: id])
          let measuredHeight = LazyHeightCache.shared.measuredHeight(stack: stackKey, item: itemID)
          let estH = measuredHeight ?? avgExtent
          let inWindow = (runningY + estH >= minVisibleY && runningY <= maxVisibleY)
            || (!seeded && index < 14)
            || itemID == viewport.targetID
          runningY += estH + spacing
          if inWindow {
            appendGap()
            appendRow(item, id: itemID)
          } else {
            gap.include(itemID, measuredHeight: measuredHeight)
            // Overlapping rows can have a negative total advance, which a
            // single nonnegative frame cannot represent.
            if spacing < 0 { appendGap() }
          }
        }
        appendGap()

      case .horizontalStack:
        children.reserveCapacity(data.count)
        let clampedOffsetX = seeded
          ? max(0, min(localOffsetX, max(0, approxSpan - vpW)))
          : max(0, localOffsetX)
        let minVisibleX = clampedOffsetX - leadingBuffer
        let maxVisibleX = clampedOffsetX + vpW + trailingBuffer
        var runningX = 0.0
        for (index, item) in data.enumerated() {
          let itemID = AnyHashable(item[keyPath: id])
          let estW = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: itemID)
          let inWindow = (runningX + estW >= minVisibleX && runningX <= maxVisibleX)
            || (!seeded && index < 14)
            || itemID == viewport.targetID
          runningX += estW + spacing
          if inWindow {
            let itemView: Content =
              EvaluationGraph.active?.trackObservation { content(item) } ?? content(item)
            var child = _render(itemView, path: path.appending(id: itemID))
            child.explicitID = itemID
            children.append(child)
          } else {
            var placeholder = NodeProps()
            placeholder.frameWidth = estW
            placeholder.fillHeight = true
            placeholder.isLazyPlaceholder = true
            children.append(Element(kind: .frame, props: placeholder, explicitID: itemID))
          }
        }

      case .verticalGrid(let columns):
        children.reserveCapacity(data.count)
        let cols = max(1, columns)
        let minVisibleY = localOffsetY - leadingBuffer
        let maxVisibleY = localOffsetY + vpH + trailingBuffer
        let sampleRowH = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: AnyHashable("__grid_row"))
        for (index, item) in data.enumerated() {
          let itemID = AnyHashable(item[keyPath: id])
          let row = index / cols
          let estH = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: itemID)
          let rowTop = Double(row) * (sampleRowH + spacing)
          let inWindow = (rowTop + estH >= minVisibleY && rowTop <= maxVisibleY)
            || (!seeded && row < 6)
            || itemID == viewport.targetID
          if inWindow {
            let itemView: Content =
              EvaluationGraph.active?.trackObservation { content(item) } ?? content(item)
            var child = _render(itemView, path: path.appending(id: itemID))
            child.explicitID = itemID
            children.append(child)
          } else {
            var placeholder = NodeProps()
            placeholder.frameHeight = estH
            placeholder.fillWidth = true
            placeholder.isLazyPlaceholder = true
            children.append(Element(kind: .frame, props: placeholder, explicitID: itemID))
          }
        }

      case .horizontalGrid(let rows):
        children.reserveCapacity(data.count)
        let rowCount = max(1, rows)
        let minVisibleX = localOffsetX - leadingBuffer
        let maxVisibleX = localOffsetX + vpW + trailingBuffer
        let sampleColW = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: AnyHashable("__grid_col"))
        for (index, item) in data.enumerated() {
          let itemID = AnyHashable(item[keyPath: id])
          let col = index / rowCount
          let estW = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: itemID)
          let colLeft = Double(col) * (sampleColW + spacing)
          let inWindow = (colLeft + estW >= minVisibleX && colLeft <= maxVisibleX)
            || (!seeded && col < 6)
            || itemID == viewport.targetID
          if inWindow {
            let itemView: Content =
              EvaluationGraph.active?.trackObservation { content(item) } ?? content(item)
            var child = _render(itemView, path: path.appending(id: itemID))
            child.explicitID = itemID
            children.append(child)
          } else {
            var placeholder = NodeProps()
            placeholder.frameWidth = estW
            placeholder.fillHeight = true
            placeholder.isLazyPlaceholder = true
            children.append(Element(kind: .frame, props: placeholder, explicitID: itemID))
          }
        }
      }
      var fragProps = NodeProps()
      fragProps.isLazyContainer = true
      return Element(kind: .fragment, props: fragProps, children: children)
    }

    return Element(
      kind: .fragment,
      children: data.map { item in
        let itemID = AnyHashable(item[keyPath: id])
        let itemView: Content
        if let graph = EvaluationGraph.active {
          itemView = graph.trackObservation { content(item) }
        } else {
          itemView = content(item)
        }
        var child = _render(itemView, path: path.appending(id: itemID))
        child.explicitID = itemID
        return child
      })
  }
}
extension ForEach where Data == Range<Int>, ID == Int {
  public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
    self.init(data, id: \.self, content: content)
  }
}
public struct ScrollViewProxy {
  let request: (AnyHashable, UnitPoint?) -> Void

  public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
    request(AnyHashable(id), anchor)
  }
}

public struct ScrollViewReader<Content: View>: View {
  let content: (ScrollViewProxy) -> Content
  @State private var target: ScrollTarget?

  public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
    self.content = content
  }

  public var body: some View {
    content(ScrollViewProxy { target = ScrollTarget(id: $0, anchor: $1) })
      .environment(\.scrollTarget, target)
  }
}

struct ScrollTarget: Equatable {
  let request = UUID()
  let id: AnyHashable
  let anchor: UnitPoint?
}

private enum ScrollTargetKey: EnvironmentKey {
  static let defaultValue: ScrollTarget? = nil
}

extension EnvironmentValues {
  var scrollTarget: ScrollTarget? {
    get { self[ScrollTargetKey.self] }
    set { self[ScrollTargetKey.self] = newValue }
  }
}

public struct ScrollView<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  let axes: Axis.Set
  let content: Content
  let showsIndicators: Bool
  @State private var offset = Point.zero
  @State private var completedTarget: ScrollTarget?
  @Environment(\.scrollTarget) private var scrollTarget
  public init(
    _ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.content = content()
    self.showsIndicators = showsIndicators
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.scrollAxes = axes
    p.scrollOffset = offset
    p.clipped = true
    p.showsScrollIndicators = showsIndicators
    p.fillWidth = true
    p.fillHeight = axes.contains(.vertical)
    let savedViewport = EnvironmentValues.current.scrollViewportContext
    EnvironmentValues.current.scrollViewportContext = ScrollViewportContext(
      offsetX: ScrollViewportContext.quantize(offset.x),
      offsetY: ScrollViewportContext.quantize(offset.y),
      viewportWidth: 800,
      viewportHeight: 600,
      targetID: scrollTarget?.id
    )
    defer { EnvironmentValues.current.scrollViewportContext = savedViewport }
    let child =
      EvaluationGraph.active?.withStoredContent { _render(content, path: path.appending(index: 0)) }
      ?? _render(content, path: path.appending(index: 0))
    var result = Element(kind: .scroll, props: p, children: [child])
    result.scrollAction = { offset = $0 }
    if let scrollTarget, scrollTarget != completedTarget {
      result.scrollTarget = scrollTarget
      result.completeScrollTarget = { completedTarget = scrollTarget }
    }
    result.scrollStateKey = _offset.installedKey
    return result
  }
}

package struct ScrollCoordinateSpaceKey: Hashable, Sendable {
  package static let shared = ScrollCoordinateSpaceKey()
}

public protocol CoordinateSpaceProtocol {
  var coordinateSpace: CoordinateSpace { get }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Equatable, Sendable {
  public init() {}
  public var coordinateSpace: CoordinateSpace { .local }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Equatable, Sendable {
  public init() {}
  public var coordinateSpace: CoordinateSpace { .global }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
  let name: AnyHashable
  public init(_ name: some Hashable) { self.name = AnyHashable(name) }
  public var coordinateSpace: CoordinateSpace { .named(name) }
}

public struct ScrollViewCoordinateSpace: CoordinateSpaceProtocol, Equatable, Sendable {
  public let axis: Axis?
  public init(axis: Axis? = nil) { self.axis = axis }
  public var coordinateSpace: CoordinateSpace { .named(AnyHashable(ScrollCoordinateSpaceKey.shared)) }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
  public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
  public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
    NamedCoordinateSpace(name)
  }
}

extension CoordinateSpaceProtocol where Self == ScrollViewCoordinateSpace {
  public static var scrollView: ScrollViewCoordinateSpace { ScrollViewCoordinateSpace() }
  public static func scrollView(axis: Axis) -> ScrollViewCoordinateSpace {
    ScrollViewCoordinateSpace(axis: axis)
  }
}

public enum CoordinateSpace: CoordinateSpaceProtocol, Equatable {
  case local, global
  case named(AnyHashable)
  public var coordinateSpace: CoordinateSpace { self }
  public static var scrollView: CoordinateSpace {
    .named(AnyHashable(ScrollCoordinateSpaceKey.shared))
  }
}
public struct GeometryProxy {
  let snapshot: GeometrySnapshot
  public var size: CGSize { snapshot.rect.size }
  public var safeAreaInsets: EdgeInsets { .zero }
  public func frame(in space: CoordinateSpace) -> CGRect {
    switch space {
    case .local: return CGRect(origin: .zero, size: size)
    case .global:
      snapshot.dependsOnPosition = true
      return snapshot.rect
    case .named(let name):
      snapshot.dependsOnPosition = true
      let anchor = snapshot.namedOrigins[name] ?? .zero
      return CGRect(
        x: snapshot.rect.minX - anchor.x, y: snapshot.rect.minY - anchor.y,
        width: size.width, height: size.height)
    }
  }
  public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect {
    frame(in: coordinateSpace.coordinateSpace)
  }
  public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
    frame(in: coordinateSpace.coordinateSpace)
  }
}
extension CoordinateSpace {
  fileprivate var isLocal: Bool {
    if case .local = self { return true }
    return false
  }
}
public struct GeometryReader<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  let content: (GeometryProxy) -> Content
  public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let environment = EnvironmentValues.current
    var p = NodeProps()
    p.fillWidth = true
    p.fillHeight = true
    var result = Element(kind: .geometry, props: p)
    result.geometryBuilder = { rect in
      let saved = EnvironmentValues.current
      EnvironmentValues.current = environment
      defer { EnvironmentValues.current = saved }
      let snapshot =
        GeometrySnapshot.active
        ?? GeometrySnapshot(rect: rect, namedOrigins: GeometryContext.current)
      let proxy = GeometryProxy(snapshot: snapshot)
      let contentView: Content
      if let graph = EvaluationGraph.active {
        contentView = graph.trackObservation { content(proxy) }
      } else {
        contentView = content(proxy)
      }
      return _render(contentView, path: path.appending(index: 0))
    }
    return result
  }
}

public struct PinnedScrollableViews: OptionSet, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
  public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

public struct LazyVStack<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  public let alignment: HorizontalAlignment
  public let spacing: Double
  public let pinnedViews: PinnedScrollableViews
  public let content: Content

  private var hasFixedClippedRows = false

  /// The caller guarantees equal row heights and clips each row's drawing and
  /// hit testing to its layout bounds. Only the immediate rows are certified.
  @_spi(WindowsRendering) public func _fixedLazyRows() -> Self {
    var stack = self
    stack.hasFixedClippedRows = true
    return stack
  }

  public init(
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat? = nil,
    pinnedViews: PinnedScrollableViews = [],
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing.map { Double($0) } ?? 8
    self.pinnedViews = pinnedViews
    self.content = content()
  }

  public var body: Never { fatalError("LazyVStack is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let stackKey = AnyHashable(path)
    let saved = EnvironmentValues.current.lazyStackKey
    let savedCtx = EnvironmentValues.current.lazyContainerContext
    EnvironmentValues.current.lazyStackKey = stackKey
    EnvironmentValues.current.lazyContainerContext = LazyContainerContext(
      key: stackKey, axis: .verticalStack, spacing: spacing)
    defer {
      EnvironmentValues.current.lazyStackKey = saved
      EnvironmentValues.current.lazyContainerContext = savedCtx
    }
    let contentElement = _render(content, path: path)
    let children = flattenChildren(contentElement)
    var props = NodeProps()
    props.spacing = spacing
    props.horizontalAlignment = alignment
    props.isLazyContainer =
      contentElement.props.isLazyContainer
      || children.count > ScrollViewportContext.virtualizationThreshold
    var el = Element(
      kind: .container(.vertical),
      props: props,
      children: children
    )
    el.hasFixedLazyRows = hasFixedClippedRows
    el.lazyCacheKey = stackKey
    return el
  }
}

public struct LazyHStack<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  public let alignment: VerticalAlignment
  public let spacing: Double
  public let pinnedViews: PinnedScrollableViews
  public let content: Content

  public init(
    alignment: VerticalAlignment = .center,
    spacing: CGFloat? = nil,
    pinnedViews: PinnedScrollableViews = [],
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing.map { Double($0) } ?? 8
    self.pinnedViews = pinnedViews
    self.content = content()
  }

  public var body: Never { fatalError("LazyHStack is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let stackKey = AnyHashable(path)
    let saved = EnvironmentValues.current.lazyStackKey
    let savedCtx = EnvironmentValues.current.lazyContainerContext
    EnvironmentValues.current.lazyStackKey = stackKey
    EnvironmentValues.current.lazyContainerContext = LazyContainerContext(
      key: stackKey, axis: .horizontalStack, spacing: spacing)
    defer {
      EnvironmentValues.current.lazyStackKey = saved
      EnvironmentValues.current.lazyContainerContext = savedCtx
    }
    let contentElement = _render(content, path: path)
    let children = flattenChildren(contentElement)
    var props = NodeProps()
    props.spacing = spacing
    props.verticalAlignment = alignment
    props.isLazyContainer =
      contentElement.props.isLazyContainer
      || children.count > ScrollViewportContext.virtualizationThreshold
    var el = Element(
      kind: .container(.horizontal),
      props: props,
      children: children
    )
    el.lazyCacheKey = stackKey
    return el
  }
}
public struct ProposedViewSize {
  public var width: CGFloat?, height: CGFloat?
  public init(width: CGFloat?, height: CGFloat?) {
    self.width = width
    self.height = height
  }
  public init(_ size: CGSize) { self.init(width: size.width, height: size.height) }
  public static let unspecified = ProposedViewSize(width: nil, height: nil)
  public static let zero = ProposedViewSize(.zero)
  public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)
  public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10))
    -> CGSize
  { CGSize(width: width ?? size.width, height: height ?? size.height) }
}
public struct UnitPoint: Equatable, Hashable, Sendable {
  public var x: CGFloat, y: CGFloat
  public init(x: CGFloat, y: CGFloat) {
    self.x = x
    self.y = y
  }
  public static let center = UnitPoint(x: 0.5, y: 0.5), topLeading = UnitPoint(x: 0, y: 0),
    topTrailing = UnitPoint(x: 1, y: 0)
  public static let leading = UnitPoint(x: 0, y: 0.5), trailing = UnitPoint(x: 1, y: 0.5)
  public static let top = UnitPoint(x: 0.5, y: 0), bottom = UnitPoint(x: 0.5, y: 1)
  public static let bottomLeading = UnitPoint(x: 0, y: 1), bottomTrailing = UnitPoint(x: 1, y: 1)
}
public final class LayoutSubview: Equatable {
  let measure: (ProposedViewSize) -> CGSize
  var placement: (CGPoint, UnitPoint, ProposedViewSize)?
  init(measure: @escaping (ProposedViewSize) -> CGSize) { self.measure = measure }
  public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool { lhs === rhs }
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { measure(proposal) }
  public func place(at point: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize)
  { placement = (point, anchor, proposal) }
}
public typealias LayoutSubviews = [LayoutSubview]
public protocol Layout {
  associatedtype Cache = Void
  typealias Subviews = LayoutSubviews
  func makeCache(subviews: Subviews) -> Cache
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
}
extension Layout where Cache == Void { public func makeCache(subviews: Subviews) {} }
extension Layout {
  public func callAsFunction<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    LayoutContainer(layout: self, content: content())
  }
}
protocol _LayoutBridge {
  var translatesWithBounds: Bool { get }
  func measure(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> CGSize
  func placements(_ bounds: CGRect, children: [Element], engine: LayoutEngine) -> [CGRect]
}
extension _LayoutBridge {
  var translatesWithBounds: Bool { false }
}
struct LayoutBridge<L: Layout>: _LayoutBridge {
  let layout: L
  func subviews(_ children: [Element], engine: LayoutEngine) -> LayoutSubviews {
    children.map { child in LayoutSubview { p in engine.sizeThatFits(child, proposal: p) } }
  }
  func measure(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> CGSize {
    let views = subviews(children, engine: engine)
    var cache = layout.makeCache(subviews: views)
    return layout.sizeThatFits(proposal: proposal, subviews: views, cache: &cache)
  }
  func placements(_ bounds: CGRect, children: [Element], engine: LayoutEngine) -> [CGRect] {
    let views = subviews(children, engine: engine)
    var cache = layout.makeCache(subviews: views)
    layout.placeSubviews(
      in: bounds, proposal: ProposedViewSize(bounds.size), subviews: views, cache: &cache)
    return views.map { view in
      guard let (point, anchor, proposal) = view.placement else { return .zero }
      let size = view.sizeThatFits(proposal)
      return CGRect(
        x: point.x - anchor.x * size.width, y: point.y - anchor.y * size.height, width: size.width,
        height: size.height)
    }
  }
}
struct LayoutContainer<L: Layout, Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let layout: L
  let content: Content
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var result = Element(
      kind: .customLayout, children: flattenChildren(_render(content, path: path)))
    result.layout = LayoutBridge(layout: layout)
    return result
  }
}
public struct AnyLayout: Layout {
  let measure: (ProposedViewSize, Subviews) -> CGSize
  let place: (CGRect, ProposedViewSize, Subviews) -> Void
  public init<L: Layout>(_ layout: L) {
    measure = { proposal, views in
      var cache = layout.makeCache(subviews: views)
      return layout.sizeThatFits(proposal: proposal, subviews: views, cache: &cache)
    }
    place = { bounds, proposal, views in
      var cache = layout.makeCache(subviews: views)
      layout.placeSubviews(in: bounds, proposal: proposal, subviews: views, cache: &cache)
    }
  }
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
    -> CGSize
  { measure(proposal, subviews) }
  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) { place(bounds, proposal, subviews) }
}
public struct HStackLayout: Layout {
  let alignment: VerticalAlignment
  let spacing: CGFloat
  public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment
    self.spacing = spacing ?? 8
  }
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
    -> CGSize
  {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    return CGSize(
      width: sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * spacing,
      height: sizes.map { $0.height }.max() ?? 0)
  }
  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      let y =
        alignment == .top
        ? bounds.minY
        : alignment == .bottom ? bounds.maxY - size.height : bounds.midY - size.height / 2
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
    }
  }
}
public struct VStackLayout: Layout {
  let alignment: HorizontalAlignment
  let spacing: CGFloat
  public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
    self.alignment = alignment
    self.spacing = spacing ?? 8
  }
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
    -> CGSize
  {
    let sizes = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
    }
    return CGSize(
      width: sizes.map { $0.width }.max() ?? 0,
      height: sizes.reduce(0) { $0 + $1.height } + CGFloat(max(0, sizes.count - 1)) * spacing)
  }
  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for view in subviews {
      let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
      let x =
        alignment == .leading
        ? bounds.minX
        : alignment == .trailing ? bounds.maxX - size.width : bounds.midX - size.width / 2
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      y += size.height + spacing
    }
  }
}
public struct GridRow<Content: View>: View {
  let alignment: VerticalAlignment
  let content: Content
  public init(alignment: VerticalAlignment = .center, @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.content = content()
  }
  public var body: some View { HStack(alignment: alignment, spacing: 0) { content } }
}
public struct Grid<Content: View>: View, _PrimitiveView {
  public typealias Body = Never
  let alignment: Alignment
  let horizontalSpacing: CGFloat
  let verticalSpacing: CGFloat
  let content: Content
  public init(
    alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil,
    verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.horizontalSpacing = horizontalSpacing ?? 8
    self.verticalSpacing = verticalSpacing ?? 8
    self.content = content()
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.alignment = alignment
    p.spacing = verticalSpacing
    p.padding.leading = horizontalSpacing
    return Element(kind: .grid, props: p, children: flattenChildren(_render(content, path: path)))
  }
}
extension View {
  public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
    TransformView(content: self) { $0.props.gridUnsizedAxes = axes }
  }

  public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> some View {
    TransformView(content: self) { $0.props.horizontalAlignment = alignment }
  }

  public func gridCellColumns(_ count: Int) -> some View {
    self
  }

  public func gridCellAnchor(_ anchor: UnitPoint) -> some View {
    self
  }
}
enum GeometryContext { static var current: [AnyHashable: CGPoint] = [:] }
