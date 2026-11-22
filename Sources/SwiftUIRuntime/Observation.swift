import Foundation
@_exported import Observation

@propertyWrapper @dynamicMemberLookup
public struct Bindable<Value: AnyObject & Observable> {
  public var wrappedValue: Value

  public init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }

  public init(_ wrappedValue: Value) {
    self.wrappedValue = wrappedValue
  }

  public init(_ projectedValue: Bindable<Value>) {
    self.wrappedValue = projectedValue.wrappedValue
  }

  public var projectedValue: Bindable<Value> { self }

  public subscript<Subject>(
    dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>
  ) -> Binding<Subject> {
    let target = wrappedValue
    return Binding(
      get: { target[keyPath: keyPath] },
      set: { target[keyPath: keyPath] = $0 }
    )
  }
}

public protocol ObservableObject: AnyObject {}
public final class ObservableObjectPublisher {
  private let lock = NSLock()
  private var listeners: [UUID: () -> Void] = [:]

  public init() {}

  public func send() {
    lock.lock()
    let current = Array(listeners.values)
    lock.unlock()
    for listener in current {
      listener()
    }
    StateRegistry.shared.notifyChange()
  }

  public func _subscribe(_ listener: @escaping () -> Void) -> () -> Void {
    let id = UUID()
    lock.lock()
    listeners[id] = listener
    lock.unlock()
    return { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.listeners.removeValue(forKey: id)
      self.lock.unlock()
    }
  }
}
extension ObservableObject {
  public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}
@propertyWrapper public struct Published<Value> {
  fileprivate final class Storage {
    let lock = NSLock()
    var value: Value
    var listeners: [UUID: (Value) -> Void] = [:]
    init(_ value: Value) { self.value = value }

    func get() -> Value {
      lock.lock()
      defer { lock.unlock() }
      return value
    }

    func set(_ newValue: Value) {
      lock.lock()
      value = newValue
      let current = Array(listeners.values)
      lock.unlock()
      for listener in current {
        listener(newValue)
      }
    }

    func subscribe(_ listener: @escaping (Value) -> Void) -> () -> Void {
      let id = UUID()
      lock.lock()
      listeners[id] = listener
      let current = value
      lock.unlock()
      listener(current)
      return { [weak self] in
        guard let self else { return }
        self.lock.lock()
        self.listeners.removeValue(forKey: id)
        self.lock.unlock()
      }
    }
  }

  public struct Publisher {
    private let storage: Storage
    fileprivate init(storage: Storage) {
      self.storage = storage
    }

    public func _subscribe(_ listener: @escaping (Value) -> Void) -> () -> Void {
      storage.subscribe(listener)
    }
  }

  private let storage: Storage
  public var wrappedValue: Value {
    get { storage.get() }
    nonmutating set {
      storage.set(newValue)
      StateRegistry.shared.notifyChange()
    }
  }
  public var projectedValue: Publisher { Publisher(storage: storage) }
  public init(wrappedValue: Value) { storage = Storage(wrappedValue) }
  public init(initialValue: Value) { storage = Storage(initialValue) }
}
@propertyWrapper @dynamicMemberLookup public struct ObservedObject<Object: ObservableObject> {
  public var wrappedValue: Object
  public init(wrappedValue: Object) { self.wrappedValue = wrappedValue }
  public init(initialValue: Object) { self.wrappedValue = initialValue }
  public var projectedValue: Self { self }
  public subscript<Value>(dynamicMember key: ReferenceWritableKeyPath<Object, Value>) -> Binding<
    Value
  > {
    Binding(get: { wrappedValue[keyPath: key] }, set: { wrappedValue[keyPath: key] = $0 })
  }
}
@propertyWrapper public struct StateObject<Object: ObservableObject>: _StateProperty {
  private final class Storage {
    let make: () -> Object
    var value: Object?
    init(make: @escaping () -> Object) { self.make = make }
    func get() -> Object {
      if let value { return value }
      let object = make()
      value = object
      return object
    }
  }
  private let storage: Storage
  public init(wrappedValue: @autoclosure @escaping () -> Object) {
    storage = Storage(make: wrappedValue)
  }
  public var wrappedValue: Object { storage.get() }
  public var projectedValue: ObservedObject<Object> { ObservedObject(wrappedValue: wrappedValue) }
  func install(_ key: StateKey) {
    storage.value = StateRegistry.shared.installLazy(key) { storage.get() }
  }
}
protocol _EnvironmentProperty { func installEnvironment() }
@propertyWrapper @dynamicMemberLookup
public struct EnvironmentObject<Object: ObservableObject>: _EnvironmentProperty {
  private final class Storage { var object: Object? }
  private let storage = Storage()
  public init() {}
  public var wrappedValue: Object {
    guard
      let object = storage.object ?? EnvironmentValues.current.objects[
        ObjectIdentifier(Object.self)] as? Object
    else {
      preconditionFailure("Missing environment object \(Object.self)")
    }
    return object
  }
  public var projectedValue: ObservedObject<Object> { ObservedObject(wrappedValue: wrappedValue) }
  public subscript<Value>(dynamicMember key: KeyPath<Object, Value>) -> Value {
    wrappedValue[keyPath: key]
  }
  func installEnvironment() {
    storage.object = EnvironmentValues.current.objects[ObjectIdentifier(Object.self)] as? Object
  }
}
struct ObjectEnvironment<Content: View, Object: ObservableObject>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let object: Object
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let old = EnvironmentValues.current
    EnvironmentValues.current.objects[ObjectIdentifier(Object.self)] = object
    defer { EnvironmentValues.current = old }
    return _render(content, path: path)
  }
}
extension View {
  public func environmentObject<Object: ObservableObject>(_ object: Object) -> some View {
    ObjectEnvironment(content: self, object: object)
  }

  public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
    ObservableEnvironment(content: self, object: object)
  }
}

struct ObservableEnvironment<Content: View, Object: AnyObject & Observable>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let object: Object?
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let old = EnvironmentValues.current
    if let object {
      EnvironmentValues.current.objects[ObjectIdentifier(Object.self)] = object
    } else {
      EnvironmentValues.current.objects.removeValue(forKey: ObjectIdentifier(Object.self))
    }
    defer { EnvironmentValues.current = old }
    return _render(content, path: path)
  }
}
