/// Lifecycle work is collected during evaluation and delivered only after the
/// resulting tree is mounted. Re-evaluating body is not an appearance event.
import Foundation

final class LifecycleRegistry {
  static let shared = LifecycleRegistry()
  struct Entry {
    var value: AnyHashable
    var disappear: (() -> Void)?
    var task: Task<Void, Never>?
  }
  var entries: [StateKey: Entry] = [:]
  var liveByRoot: [ObjectIdentifier: Set<StateKey>] = [:]
  var pendingByRoot: [ObjectIdentifier: [() -> Void]] = [:]
  var activeRoot: ObjectIdentifier?

  func enqueue(_ action: @escaping () -> Void) {
    guard let activeRoot else { return }
    pendingByRoot[activeRoot, default: []].append(action)
  }

  func retain(_ keys: Set<StateKey>) {
    if let first = keys.first {
      liveByRoot[ObjectIdentifier(first.path.root), default: []].formUnion(keys)
    }
    GeometrySnapshot.active?.lifecycle.formUnion(keys)
  }
  func begin(root: ViewPath) {
    let rootID = ObjectIdentifier(root)
    liveByRoot[rootID] = []
    pendingByRoot[rootID] = []
  }
  func clearPending(root: ViewPath) {
    pendingByRoot[ObjectIdentifier(root)] = []
  }
  func flushEnqueued(root: ViewPath) {
    let rootID = ObjectIdentifier(root)
    let work = pendingByRoot.removeValue(forKey: rootID) ?? []
    work.forEach { $0() }
  }
  func register(
    _ key: StateKey, value: AnyHashable, appear: (() -> Void)?, change: (() -> Void)?,
    disappear: (() -> Void)?, task: (() async -> Void)?
  ) {
    let rootID = ObjectIdentifier(key.path.root)
    EvaluationGraph.active?.installLifecycle(key)
    GeometrySnapshot.active?.lifecycle.insert(key)
    liveByRoot[rootID, default: []].insert(key)
    let old = entries[key]
    if old == nil || old!.value != value {
      old?.task?.cancel()
      var entry = Entry(value: value, disappear: disappear)
      if old == nil, let appear { pendingByRoot[rootID, default: []].append(appear) }
      if old != nil, let change { pendingByRoot[rootID, default: []].append(change) }
      if let task {
        pendingByRoot[rootID, default: []].append {
          self.entries[key]?.task = Task { @MainActor in await task() }
        }
      }
      entry.task = nil
      entries[key] = entry
    } else {
      entries[key]?.disappear = disappear
    }
  }
  func commit(root: ViewPath) {
    let rootID = ObjectIdentifier(root)
    let live = liveByRoot[rootID] ?? []
    for key in Set(entries.keys).subtracting(live) where key.path.root === root {
      LifecycleSnapshots.shared.values.removeValue(forKey: key)
      LifecycleSnapshots.shared.versions.removeValue(forKey: key)
      let old = entries.removeValue(forKey: key)
      old?.task?.cancel()
      if let action = old?.disappear { pendingByRoot[rootID, default: []].append(action) }
    }
    let work = pendingByRoot.removeValue(forKey: rootID) ?? []
    work.forEach { $0() }
  }
  func remove(_ root: ViewPath) {
    let rootID = ObjectIdentifier(root)
    for key in Array(entries.keys) where key.path.root === root {
      let old = entries.removeValue(forKey: key)
      old?.task?.cancel()
      LifecycleSnapshots.shared.values.removeValue(forKey: key)
      LifecycleSnapshots.shared.versions.removeValue(forKey: key)
    }
    liveByRoot.removeValue(forKey: rootID)
    pendingByRoot.removeValue(forKey: rootID)
  }
  func reset() {
    entries.values.forEach { $0.task?.cancel() }
    entries.removeAll()
    liveByRoot.removeAll()
    pendingByRoot.removeAll()
    activeRoot = nil
    LifecycleSnapshots.shared.values.removeAll()
    LifecycleSnapshots.shared.versions.removeAll()
  }
}
struct SnapshotBox<Value> {
  let value: Value
}
struct LifecycleView<Content: View, Value: Equatable>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let value: Value
  let appear: (() -> Void)?
  let change: ((Value, Value) -> Void)?
  let disappear: (() -> Void)?
  let task: (() async -> Void)?
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    // Equatable values need not be Hashable. Keep a comparison snapshot without
    // publishing internal bookkeeping as an application state mutation.
    let key = StateKey(path: path, owner: ObjectIdentifier(Self.self), property: -1)
    let snapshot = LifecycleSnapshots.shared.values[key] as? SnapshotBox<Value>
    let oldValue = snapshot?.value ?? value
    let changed = snapshot == nil || snapshot!.value != value
    let version = LifecycleSnapshots.shared.versions[key, default: 0] + (changed ? 1 : 0)
    LifecycleSnapshots.shared.values[key] = SnapshotBox(value: value)
    LifecycleSnapshots.shared.versions[key] = version
    let newValue = value
    LifecycleRegistry.shared.register(
      key, value: version, appear: appear, change: change.map { fn in { fn(oldValue, newValue) } },
      disappear: disappear, task: task)
    return _render(content, path: path.appending(index: 0))
  }
}
struct AnimationValueView<Content: View, Value: Equatable>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let animation: Animation?
  let value: Value
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let key = StateKey(path: path, owner: ObjectIdentifier(Self.self), property: -2)
    let snapshot = LifecycleSnapshots.shared.values[key] as? SnapshotBox<Value>
    let changed = snapshot != nil && snapshot!.value != value
    LifecycleSnapshots.shared.values[key] = SnapshotBox(value: value)
    LifecycleRegistry.shared.register(
      key, value: 0, appear: nil, change: nil, disappear: nil, task: nil)
    var element = _render(content, path: path.appending(index: 0))
    if changed {
      element.props.animationPass = AnimationContext.renderPass
      if let animation {
        element.props.animation = animation
        element.props.animationDisabled = false
      } else {
        element.props.animation = nil
        element.props.animationDisabled = true
      }
    }
    return element
  }
}
final class LifecycleSnapshots {
  static let shared = LifecycleSnapshots()
  var values: [StateKey: Any] = [:]
  var versions: [StateKey: Int] = [:]
}
extension View {
  public func onAppear(perform action: (() -> Void)? = nil) -> some View {
    LifecycleView(
      content: self, value: false, appear: action, change: nil, disappear: nil, task: nil)
  }
  public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
    LifecycleView(
      content: self, value: false, appear: nil, change: nil, disappear: action, task: nil)
  }
  public func onChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void)
    -> some View
  {
    LifecycleView(
      content: self, value: value, appear: nil, change: { _, new in action(new) }, disappear: nil,
      task: nil)
  }
  public func onChange<Value: Equatable>(
    of value: Value, initial: Bool = false, _ action: @escaping () -> Void
  ) -> some View {
    LifecycleView(
      content: self, value: value, appear: initial ? action : nil,
      change: { _, _ in action() }, disappear: nil, task: nil)
  }
  public func onChange<Value: Equatable>(
    of value: Value, initial: Bool = false, _ action: @escaping (Value, Value) -> Void
  ) -> some View {
    LifecycleView(
      content: self, value: value, appear: initial ? { action(value, value) } : nil,
      change: action, disappear: nil, task: nil)
  }
  public func task<ID: Equatable>(id: ID, _ action: @escaping () async -> Void) -> some View {
    LifecycleView(content: self, value: id, appear: nil, change: nil, disappear: nil, task: action)
  }
  public func task(_ action: @escaping () async -> Void) -> some View { task(id: false, action) }
}
