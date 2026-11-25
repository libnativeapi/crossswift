/// State belongs to a mounted view/property, not the place its value was
/// constructed. Two same-typed siblings therefore keep independent slots.

/// Interns structural paths for the lifetime of the nodes and state using them.
/// Child lookup is local to the parent, so StateKey never hashes a full path.
package final class ViewPath: Hashable {
  private enum Component: Hashable {
    case index(Int)
    case id(AnyHashable)
  }
  private final class Child {
    weak var path: ViewPath?
    init(_ path: ViewPath) { self.path = path }
  }
  private let parent: ViewPath?
  private let component: Component?
  private var children: [Component: Child] = [:]

  init() {
    parent = nil
    component = nil
  }

  private init(parent: ViewPath, component: Component) {
    self.parent = parent
    self.component = component
  }

  deinit {
    if let component { parent?.children.removeValue(forKey: component) }
  }

  var root: ViewPath { parent?.root ?? self }

  var stablePath: String {
    var segments: [String] = []
    var cursor: ViewPath? = self
    while let current = cursor {
      if let component = current.component {
        switch component {
        case .index(let index):
          segments.append("i:\(index)")
        case .id(let hashable):
          segments.append("id:\(HotReloadCodec.stableIDComponent(hashable))")
        }
      }
      cursor = current.parent
    }
    segments.reverse()
    return segments.joined(separator: "/")
  }

  func appending(index: Int) -> ViewPath { child(.index(index)) }
  func appending(id: AnyHashable) -> ViewPath { child(.id(id)) }

  private func child(_ component: Component) -> ViewPath {
    if let path = children[component]?.path { return path }
    let path = ViewPath(parent: self, component: component)
    children[component] = Child(path)
    return path
  }

  package static func == (lhs: ViewPath, rhs: ViewPath) -> Bool { lhs === rhs }
  package func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

struct StateKey: Hashable {
  let path: ViewPath
  let owner: ObjectIdentifier
  let property: Int
}
protocol _StateProperty { func install(_ key: StateKey) }
public final class StateRegistry {
  public static let shared = StateRegistry()
  var values: [StateKey: Any] = [:]
  private var liveByRoot: [ObjectIdentifier: Set<StateKey>] = [:]
  var ownerTypeNames: [ObjectIdentifier: String] = [:]
  var propertyLabels: [ObjectIdentifier: [Int: String]] = [:]
  var pendingHotReload: HotReloadRestoreBuffer?
  var appStorageBindings: [StateKey: HotReloadAppStorageBinding] = [:]
  public var onChange: (() -> Void)?
  var onStateChange: ((StateKey) -> Void)?
  private struct Observer {
    let change: () -> Void
    let stateChange: (StateKey) -> Void
  }
  private var observers: [ObjectIdentifier: Observer] = [:]
  func registerOwnerType(_ id: ObjectIdentifier, name: String) {
    if ownerTypeNames[id] == nil {
      ownerTypeNames[id] = HotReloadCodec.normalizeTypeName(name)
    }
  }
  func registerPropertyLabel(owner: ObjectIdentifier, property: Int, label: String) {
    propertyLabels[owner, default: [:]][property] = label
  }
  func observe(_ root: ViewPath, change: @escaping () -> Void, stateChange: @escaping (StateKey) -> Void) {
    observers[ObjectIdentifier(root)] = Observer(change: change, stateChange: stateChange)
  }
  func removeObserver(_ root: ViewPath) {
    let rootID = ObjectIdentifier(root)
    observers.removeValue(forKey: rootID)
    values = values.filter { $0.key.path.root !== root }
    appStorageBindings = appStorageBindings.filter { $0.key.path.root !== root }
    liveByRoot.removeValue(forKey: rootID)
    LifecycleRegistry.shared.remove(root)
    SceneStorageStore.shared.remove(root: root)
  }
  func notifyChange() {
    onChange?()
    for observer in Array(observers.values) { observer.change() }
  }
  private init() {}
  public func reset() {
    LifecycleRegistry.shared.reset()
    SceneStorageStore.shared.reset()
    values.removeAll()
    liveByRoot.removeAll()
    appStorageBindings.removeAll()
    pendingHotReload = nil
    onChange = nil
    onStateChange = nil
    observers.removeAll()
  }
  func begin(root: ViewPath) {
    liveByRoot[ObjectIdentifier(root)] = []
  }
  func retain(_ keys: Set<StateKey>) {
    if let first = keys.first {
      liveByRoot[ObjectIdentifier(first.path.root), default: []].formUnion(keys)
    }
    GeometrySnapshot.active?.state.formUnion(keys)
  }
  func end(root: ViewPath) {
    let live = liveByRoot[ObjectIdentifier(root)] ?? []
    values = values.filter { $0.key.path.root !== root || live.contains($0.key) }
    if !appStorageBindings.isEmpty {
      appStorageBindings = appStorageBindings.filter { $0.key.path.root !== root || live.contains($0.key) }
    }
  }
  func install<Value>(_ key: StateKey, initial: Value, allowHotReloadRestore: Bool = true) {
    EvaluationGraph.active?.installState(key)
    GeometrySnapshot.active?.state.insert(key)
    liveByRoot[ObjectIdentifier(key.path.root), default: []].insert(key)
    if values[key] == nil {
      if allowHotReloadRestore, pendingHotReload != nil,
         let restored: Value = consumePendingHotReloadValue(for: key, as: Value.self)
      {
        values[key] = restored
      } else {
        values[key] = initial
      }
    }
  }
  func installLazy<Value>(_ key: StateKey, initial: () -> Value) -> Value {
    EvaluationGraph.active?.installState(key)
    GeometrySnapshot.active?.state.insert(key)
    liveByRoot[ObjectIdentifier(key.path.root), default: []].insert(key)
    if let value = values[key] as? Value { return value }
    if pendingHotReload != nil,
       let restored: Value = consumePendingHotReloadValue(for: key, as: Value.self)
    {
      values[key] = restored
      return restored
    }
    let value = initial()
    values[key] = value
    return value
  }
  func value<Value>(_ key: StateKey, initial: Value) -> Value {
    EvaluationGraph.active?.read(key)
    return values[key] as? Value ?? initial
  }
  func set<Value>(_ key: StateKey, value: Value) {
    func equal<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool { (rhs as? T) == lhs }
    if let old = values[key] as? any Equatable, equal(old, value) { return }
    values[key] = value
    if let observer = observers[ObjectIdentifier(key.path.root)] {
      observer.stateChange(key)
    } else if let onStateChange {
      onStateChange(key)
    } else {
      onChange?()
    }
  }
}
@propertyWrapper public struct State<Value>: _StateProperty, @unchecked Sendable {
  private final class Storage {
    var value: Value
    var key: StateKey?
    init(_ value: Value) { self.value = value }
  }
  private let storage: Storage
  nonisolated public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
  nonisolated public init(initialValue: Value) { self.init(wrappedValue: initialValue) }
  func install(_ key: StateKey) {
    storage.key = key
    StateRegistry.shared.install(key, initial: storage.value)
  }
  public var wrappedValue: Value {
    get {
      guard let key = storage.key else { return storage.value }
      return StateRegistry.shared.value(key, initial: storage.value)
    }
    nonmutating set {
      storage.value = newValue
      if let key = storage.key { StateRegistry.shared.set(key, value: newValue) }
    }
  }
  public var projectedValue: Binding<Value> {
    Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
  }
  var installedKey: StateKey? { storage.key }
}
