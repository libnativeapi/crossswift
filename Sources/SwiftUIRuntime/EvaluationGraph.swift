import Foundation
import Observation

/// Tracks state reads while evaluating bodies. A local state write invalidates
/// its readers and their ancestors; unrelated branches retain their raw element
/// trees, state slots and lifecycle registrations. Unknown notifications (for
/// example ObservableObject) conservatively invalidate the whole graph.
final class EvaluationGraph {
  static var active: EvaluationGraph?
  var onObservableChange: (() -> Void)?
  private static var nextID = 1
  private final class Node {
    let type: ObjectIdentifier
    let path: ViewPath
    let id: Int
    var revision = 0
    /// Increments only when this node's own inputs or state changed, not when
    /// only a descendant inside a `GeometryReader` scope became dirty.
    var inputRevision = 0
    weak var parent: Node?
    weak var graph: EvaluationGraph?
    var children: [Node] = []
    var childrenByPath: [ViewPath: Node]?
    var hadOutOfOrderChild = false
    var cursor = 0
    var dirty = true, descendantDirty = true, forceChildren = true
    var readsScrollViewport = false
    var lastScrollViewport: ScrollViewportContext?
    var inputChanged = true
    var result: Element?
    var lastEquatableView: (any Equatable)?
    var lastEnvironment: EnvironmentValues?
    var lastGlobalInvalidationEpoch = -1
    var reads = Set<StateKey>()
    var previousReads = Set<StateKey>()
    var state = Set<StateKey>()
    var lifecycle = Set<StateKey>()
    /// Dedicated child evaluation scope for `.geometry` nodes (`GeometryReader`).
    var geometryChild: Node?
    var geometryInputRevision = -1
    var geometryRect: CGRect?
    var geometryNamedOrigins: [AnyHashable: CGPoint]?
    lazy var reference = WeakNode(self)
    init(type: ObjectIdentifier, path: ViewPath, parent: Node?, graph: EvaluationGraph) {
      self.type = type
      self.path = path
      self.parent = parent
      self.graph = graph
      id = EvaluationGraph.nextID
      EvaluationGraph.nextID += 1
      graph.nodesByID[id] = WeakNode(self)
    }
    deinit {
      graph?.nodesByID.removeValue(forKey: id)
      for key in reads {
        graph?.removeReader(id, of: key)
      }
    }
    func retain() {
      if !state.isEmpty { StateRegistry.shared.retain(state) }
      if !lifecycle.isEmpty { LifecycleRegistry.shared.retain(lifecycle) }
      for child in children { child.retain() }
    }
  }
  private final class WeakNode {
    weak var value: Node?
    init(_ value: Node) { self.value = value }
  }
  private final class WeakPair: @unchecked Sendable {
    weak var graph: EvaluationGraph?
    weak var node: Node?
    init(graph: EvaluationGraph, node: Node) {
      self.graph = graph
      self.node = node
    }
  }
  private var root: Node?
  private var current: Node?
  private var trackingObservation = false
  private var globalInvalidationEpoch = 0
  private var readers: [StateKey: [Int: WeakNode]] = [:]
  private var nodesByID: [Int: WeakNode] = [:]

  private func removeReader(_ id: Int, of key: StateKey) {
    readers[key]?.removeValue(forKey: id)
    if readers[key]?.isEmpty == true { readers.removeValue(forKey: key) }
  }

  func invalidateAll() {
    globalInvalidationEpoch += 1
    root?.dirty = true
    root?.descendantDirty = true
    for entry in nodesByID.values {
      if let geo = entry.value?.geometryChild {
        geo.dirty = true
        geo.descendantDirty = true
      }
    }
  }

  private func markNodeDirty(_ node: Node) {
    node.dirty = true
    var ancestor: Node? = node
    while let item = ancestor {
      if item.descendantDirty { break }
      item.descendantDirty = true
      ancestor = item.parent
    }
  }

  func invalidate(_ key: StateKey) {
    // Layout-built content can read state outside this graph.
    guard let entries = readers[key], entries.values.contains(where: { $0.value != nil }) else {
      invalidateAll()
      return
    }
    for entry in entries.values {
      guard let node = entry.value else { continue }
      markNodeDirty(node)
    }
  }
  func read(_ key: StateKey) {
    guard let current, current.reads.insert(key).inserted,
      !current.previousReads.contains(key)
    else { return }
    readers[key, default: [:]][current.id] = current.reference
  }
  func installState(_ key: StateKey) { current?.state.insert(key) }
  func installLifecycle(_ key: StateKey) { current?.lifecycle.insert(key) }
  func recordScrollViewportRead() {
    var item = current
    while let node = item {
      if node.readsScrollViewport { break }
      node.readsScrollViewport = true
      item = node.parent
    }
  }
  /// A primitive's stored content is unchanged by its own internal state (for
  /// example a ScrollView offset). An ancestor supplying new input still wins.
  func withStoredContent(_ body: () -> Element) -> Element {
    guard let current, !current.inputChanged else { return body() }
    let previous = current.forceChildren
    current.forceChildren = false
    defer { current.forceChildren = previous }
    return body()
  }

  func evaluateRoot(_ body: () -> Element) -> Element {
    let previous = Self.active
    Self.active = self
    defer { Self.active = previous }
    return body()
  }
  private static func sameEquatableView(_ lhs: (any Equatable)?, _ rhs: any Equatable) -> Bool {
    guard let lhs else { return false }
    func equal<T: Equatable>(_ a: T, _ b: any Equatable) -> Bool {
      guard let b = b as? T else { return false }
      return a == b
    }
    return equal(lhs, rhs)
  }

  func evaluate(
    type: ObjectIdentifier,
    path: ViewPath,
    equatableView: (any Equatable)? = nil,
    _ body: () -> Element
  ) -> Element {
    let parent = current
    let node: Node
    if let parent {
      let index = parent.cursor
      parent.cursor += 1
      if index < parent.children.count,
        parent.children[index].type == type && parent.children[index].path == path
      {
        node = parent.children[index]
      } else {
        parent.hadOutOfOrderChild = true
        if parent.childrenByPath == nil {
          var map: [ViewPath: Node] = [:]
          map.reserveCapacity(parent.children.count + 8)
          for existing in parent.children {
            map[existing.path] = existing
          }
          parent.childrenByPath = map
        }
        if let reused = parent.childrenByPath?[path], reused.type == type,
          !parent.children[0..<min(index, parent.children.count)].contains(where: { $0 === reused })
        {
          node = reused
        } else {
          node = Node(type: type, path: path, parent: parent, graph: self)
          parent.childrenByPath?[path] = node
        }
        if index < parent.children.count {
          parent.children[index] = node
        } else {
          parent.children.append(node)
        }
      }
    } else if let root, root.type == type, root.path == path {
      node = root
    } else {
      node = Node(type: type, path: path, parent: nil, graph: self)
      root = node
    }
    let currentViewport = EnvironmentValues.current.scrollViewportContext
    let viewportChanged =
      node.readsScrollViewport && node.lastScrollViewport != currentViewport
    var forced = parent?.forceChildren ?? false
    if forced, !viewportChanged, let eqView = equatableView, !node.dirty, node.result != nil,
      node.lastGlobalInvalidationEpoch == globalInvalidationEpoch,
      let prevEnv = node.lastEnvironment,
      prevEnv.isEquivalent(to: EnvironmentValues.current),
      Self.sameEquatableView(node.lastEquatableView, eqView)
    {
      forced = false
    }
    if !forced && !node.descendantDirty && !viewportChanged, let result = node.result {
      node.retain()
      return result
    }
    swap(&node.reads, &node.previousReads)
    node.reads.removeAll(keepingCapacity: true)
    node.state.removeAll(keepingCapacity: true)
    node.lifecycle.removeAll(keepingCapacity: true)
    let inputsChanged = forced || node.dirty || node.result == nil
    if inputsChanged { node.inputRevision += 1 }
    node.forceChildren = forced || node.dirty
    node.inputChanged = forced || node.result == nil
    node.hadOutOfOrderChild = false
    node.cursor = 0
    current = node
    var result = body()
    for key in node.previousReads where !node.reads.contains(key) { removeReader(node.id, of: key) }
    result.evaluationID = node.id
    node.revision += 1
    result.evaluationRevision = node.revision
    current = parent
    if node.cursor < node.children.count {
      node.children.removeLast(node.children.count - node.cursor)
    }
    if node.hadOutOfOrderChild || node.childrenByPath != nil {
      var map: [ViewPath: Node] = [:]
      map.reserveCapacity(node.children.count)
      for liveChild in node.children {
        map[liveChild.path] = liveChild
      }
      node.childrenByPath = map
    }
    node.result = result
    node.lastScrollViewport = currentViewport
    if let eqView = equatableView {
      node.lastEquatableView = eqView
      node.lastEnvironment = EnvironmentValues.current
    } else {
      node.lastEquatableView = nil
      node.lastEnvironment = nil
    }
    node.lastGlobalInvalidationEpoch = globalInvalidationEpoch
    node.dirty = false
    node.descendantDirty = false
    return result
  }

  /// Tracks `@Observable` reads exclusively for the currently evaluating node,
  /// without nesting across recursive child `_render` calls.
  func trackObservation<T>(_ body: () -> T) -> T {
    guard !trackingObservation, let node = current else { return body() }
    let pair = WeakPair(graph: self, node: node)
    trackingObservation = true
    defer { trackingObservation = false }
    return withObservationTracking {
      body()
    } onChange: {
      if Thread.isMainThread {
        if let graph = pair.graph, let target = pair.node {
          graph.markNodeDirty(target)
          graph.onObservableChange?()
        }
      } else {
        Task { @MainActor in
          guard let graph = pair.graph, let target = pair.node else { return }
          graph.markNodeDirty(target)
          graph.onObservableChange?()
        }
      }
    }
  }

  func retainGeometry(ownerID: Int) {
    guard ownerID != 0, let geo = nodesByID[ownerID]?.value?.geometryChild else { return }
    geo.retain()
  }

  /// Evaluates a `GeometryReader` builder inside this `EvaluationGraph` so its
  /// descendants participate in incremental `@State` / `@Observable` tracking,
  /// `evaluationID` stability, and `reusesLayout` caching.
  func evaluateGeometry(
    ownerID: Int,
    rect: CGRect,
    namedOrigins: [AnyHashable: CGPoint],
    _ body: () -> Element
  ) -> Element {
    guard ownerID != 0, let owner = nodesByID[ownerID]?.value else {
      return body()
    }
    let scopeRoot: Node
    let needsFullRebuild: Bool
    if let existing = owner.geometryChild {
      scopeRoot = existing
      needsFullRebuild =
        owner.geometryInputRevision != owner.inputRevision
        || owner.geometryRect != rect
        || owner.geometryNamedOrigins != namedOrigins
        || scopeRoot.dirty
    } else {
      scopeRoot = Node(
        type: ObjectIdentifier(EvaluationGraph.self),
        path: owner.path,
        parent: owner,
        graph: self
      )
      owner.geometryChild = scopeRoot
      needsFullRebuild = true
    }
    let currentViewport = EnvironmentValues.current.scrollViewportContext
    let viewportChanged =
      scopeRoot.readsScrollViewport && scopeRoot.lastScrollViewport != currentViewport
    if !needsFullRebuild && !scopeRoot.descendantDirty && !viewportChanged, let cached = scopeRoot.result {
      scopeRoot.retain()
      return cached
    }
    let previousActive = Self.active
    let previousCurrent = current
    Self.active = self
    current = scopeRoot
    defer {
      current = previousCurrent
      Self.active = previousActive
    }
    scopeRoot.forceChildren = needsFullRebuild
    scopeRoot.inputChanged = needsFullRebuild
    scopeRoot.hadOutOfOrderChild = false
    scopeRoot.cursor = 0
    let result = body()
    if scopeRoot.cursor < scopeRoot.children.count {
      scopeRoot.children.removeLast(scopeRoot.children.count - scopeRoot.cursor)
    }
    if scopeRoot.hadOutOfOrderChild || scopeRoot.childrenByPath != nil {
      var map: [ViewPath: Node] = [:]
      map.reserveCapacity(scopeRoot.children.count)
      for liveChild in scopeRoot.children {
        map[liveChild.path] = liveChild
      }
      scopeRoot.childrenByPath = map
    }
    owner.geometryInputRevision = owner.inputRevision
    owner.geometryRect = rect
    owner.geometryNamedOrigins = namedOrigins
    scopeRoot.result = result
    scopeRoot.lastScrollViewport = currentViewport
    scopeRoot.dirty = false
    scopeRoot.descendantDirty = false
    return result
  }
}
