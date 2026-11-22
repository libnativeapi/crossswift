import Foundation

// MARK: - @AppStorage

/// Shared invalidation hook so `@AppStorage` writes notify all mounted renderers
/// while persisting values in `UserDefaults`.
@propertyWrapper
public struct AppStorage<Value>: _StateProperty {
  private final class Storage {
    var key: StateKey?
    let storageKey: String
    let store: UserDefaults
    let read: (UserDefaults, String) -> Value
    let write: (UserDefaults, String, Value) -> Void

    init(
      storageKey: String,
      store: UserDefaults,
      read: @escaping (UserDefaults, String) -> Value,
      write: @escaping (UserDefaults, String, Value) -> Void
    ) {
      self.storageKey = storageKey
      self.store = store
      self.read = read
      self.write = write
    }
  }

  private let storage: Storage

  private init(
    storageKey: String,
    store: UserDefaults?,
    read: @escaping (UserDefaults, String) -> Value,
    write: @escaping (UserDefaults, String, Value) -> Void
  ) {
    self.storage = Storage(
      storageKey: storageKey,
      store: store ?? .standard,
      read: read,
      write: write
    )
  }

  func install(_ key: StateKey) {
    storage.key = key
    StateRegistry.shared.install(key, initial: storage.read(storage.store, storage.storageKey))
  }

  public var wrappedValue: Value {
    get {
      let current = storage.read(storage.store, storage.storageKey)
      if let key = storage.key {
        _ = StateRegistry.shared.value(key, initial: current)
      }
      return current
    }
    nonmutating set {
      storage.write(storage.store, storage.storageKey, newValue)
      if let key = storage.key {
        StateRegistry.shared.set(key, value: newValue)
      }
      StateRegistry.shared.notifyChange()
    }
  }

  public var projectedValue: Binding<Value> {
    Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
  }
}

extension AppStorage where Value == Bool {
  public init(wrappedValue: Bool, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Bool ?? wrappedValue },
      write: { defaults, k, v in defaults.set(v, forKey: k) }
    )
  }
}

extension AppStorage where Value == Int {
  public init(wrappedValue: Int, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Int ?? wrappedValue },
      write: { defaults, k, v in defaults.set(v, forKey: k) }
    )
  }
}

extension AppStorage where Value == Double {
  public init(wrappedValue: Double, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Double ?? wrappedValue },
      write: { defaults, k, v in defaults.set(v, forKey: k) }
    )
  }
}

extension AppStorage where Value == String {
  public init(wrappedValue: String, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.string(forKey: k) ?? wrappedValue },
      write: { defaults, k, v in defaults.set(v, forKey: k) }
    )
  }
}

extension AppStorage where Value == URL {
  public init(wrappedValue: URL, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in
        if let str = defaults.string(forKey: k), let url = URL(string: str) { return url }
        return defaults.url(forKey: k) ?? wrappedValue
      },
      write: { defaults, k, v in defaults.set(v.absoluteString, forKey: k) }
    )
  }
}

extension AppStorage where Value == Data {
  public init(wrappedValue: Data, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.data(forKey: k) ?? wrappedValue },
      write: { defaults, k, v in defaults.set(v, forKey: k) }
    )
  }
}

extension AppStorage where Value: RawRepresentable, Value.RawValue == Int {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in
        guard let raw = defaults.object(forKey: k) as? Int, let v = Value(rawValue: raw) else {
          return wrappedValue
        }
        return v
      },
      write: { defaults, k, v in defaults.set(v.rawValue, forKey: k) }
    )
  }
}

extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
  public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in
        guard let raw = defaults.string(forKey: k), let v = Value(rawValue: raw) else {
          return wrappedValue
        }
        return v
      },
      write: { defaults, k, v in defaults.set(v.rawValue, forKey: k) }
    )
  }
}

extension AppStorage where Value == Bool? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Bool },
      write: { defaults, k, v in
        if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

extension AppStorage where Value == Int? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Int },
      write: { defaults, k, v in
        if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

extension AppStorage where Value == Double? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.object(forKey: k) as? Double },
      write: { defaults, k, v in
        if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

extension AppStorage where Value == String? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.string(forKey: k) },
      write: { defaults, k, v in
        if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

extension AppStorage where Value == URL? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.string(forKey: k).flatMap(URL.init(string:)) },
      write: { defaults, k, v in
        if let v { defaults.set(v.absoluteString, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

extension AppStorage where Value == Data? {
  public init(_ key: String, store: UserDefaults? = nil) {
    self.init(
      storageKey: key, store: store,
      read: { defaults, k in defaults.data(forKey: k) },
      write: { defaults, k, v in
        if let v { defaults.set(v, forKey: k) } else { defaults.removeObject(forKey: k) }
      }
    )
  }
}

// MARK: - @SceneStorage

final class SceneStorageStore {
  nonisolated(unsafe) static let shared = SceneStorageStore()
  private var valuesByRoot: [ObjectIdentifier: [String: Any]] = [:]

  func value<Value>(root: ViewPath, key: String, default fallback: Value) -> Value {
    valuesByRoot[ObjectIdentifier(root)]?[key] as? Value ?? fallback
  }

  func set<Value>(root: ViewPath, key: String, value: Value) {
    valuesByRoot[ObjectIdentifier(root), default: [:]][key] = value
  }

  func remove(root: ViewPath) {
    valuesByRoot.removeValue(forKey: ObjectIdentifier(root))
  }

  func reset() {
    valuesByRoot.removeAll()
  }
}

@propertyWrapper
public struct SceneStorage<Value>: _StateProperty {
  private final class Storage {
    var key: StateKey?
    let name: String
    var fallback: Value
    init(name: String, fallback: Value) {
      self.name = name
      self.fallback = fallback
    }
  }

  private let storage: Storage

  public init(wrappedValue: Value, _ key: String) {
    self.storage = Storage(name: key, fallback: wrappedValue)
  }

  func install(_ key: StateKey) {
    storage.key = key
    let current = SceneStorageStore.shared.value(
      root: key.path.root, key: storage.name, default: storage.fallback
    )
    StateRegistry.shared.install(key, initial: current)
  }

  public var wrappedValue: Value {
    get {
      guard let key = storage.key else { return storage.fallback }
      let current = SceneStorageStore.shared.value(
        root: key.path.root, key: storage.name, default: storage.fallback
      )
      _ = StateRegistry.shared.value(key, initial: current)
      return current
    }
    nonmutating set {
      storage.fallback = newValue
      if let key = storage.key {
        SceneStorageStore.shared.set(root: key.path.root, key: storage.name, value: newValue)
        StateRegistry.shared.set(key, value: newValue)
      }
    }
  }

  public var projectedValue: Binding<Value> {
    Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
  }
}

extension SceneStorage where Value == Bool? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}
extension SceneStorage where Value == Int? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}
extension SceneStorage where Value == Double? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}
extension SceneStorage where Value == String? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}
extension SceneStorage where Value == URL? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}
extension SceneStorage where Value == Data? {
  public init(_ key: String) { self.init(wrappedValue: nil, key) }
}

// MARK: - FocusedValues / @FocusedValue / @FocusedObject

public protocol FocusedValueKey {
  associatedtype Value
}

public struct FocusedValues {
  nonisolated(unsafe) static var active = FocusedValues()
  private var storage: [ObjectIdentifier: Any] = [:]

  public init() {}

  public subscript<Key: FocusedValueKey>(key: Key.Type) -> Key.Value? {
    get { storage[ObjectIdentifier(key)] as? Key.Value }
    set {
      storage[ObjectIdentifier(key)] = newValue
      StateRegistry.shared.notifyChange()
    }
  }

  mutating func setObject<T: AnyObject>(_ object: T?) {
    storage[ObjectIdentifier(T.self)] = object
  }

  func object<T: AnyObject>(_ type: T.Type) -> T? {
    storage[ObjectIdentifier(type)] as? T
  }
}

@propertyWrapper
public struct FocusedValue<Value> {
  private let keyPath: KeyPath<FocusedValues, Value?>

  public init(_ keyPath: KeyPath<FocusedValues, Value?>) {
    self.keyPath = keyPath
  }

  public var wrappedValue: Value? {
    FocusedValues.active[keyPath: keyPath]
  }
}

@propertyWrapper
public struct FocusedObject<ObjectType: ObservableObject> {
  public init() {}

  public var wrappedValue: ObjectType? {
    FocusedValues.active.object(ObjectType.self)
  }
}

private struct FocusedValueModifierView<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let apply: () -> Void
  var body: Never { fatalError("FocusedValueModifierView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    apply()
    return _render(content, path: path)
  }
}

extension View {
  public func focusedValue<Value>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value
  ) -> some View {
    FocusedValueModifierView(content: self) {
      FocusedValues.active[keyPath: keyPath] = value
    }
  }

  public func focusedSceneValue<Value>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value
  ) -> some View {
    focusedValue(keyPath, value)
  }

  public func focusedSceneValue<Value>(
    _ keyPath: WritableKeyPath<FocusedValues, Value?>,
    _ value: Value?
  ) -> some View {
    FocusedValueModifierView(content: self) {
      FocusedValues.active[keyPath: keyPath] = value
    }
  }

  public func focusedObject<T: ObservableObject>(_ object: T) -> some View {
    FocusedValueModifierView(content: self) {
      FocusedValues.active.setObject(object)
    }
  }

  public func focusedSceneObject<T: ObservableObject>(_ object: T) -> some View {
    focusedObject(object)
  }
}
