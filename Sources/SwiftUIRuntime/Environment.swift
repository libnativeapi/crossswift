import Foundation

/// Environment writes are value copies scoped to evaluating a subtree.

public enum ScenePhase: Int, Comparable, Hashable, Sendable {
  case background = 0
  case inactive = 1
  case active = 2

  public static func < (lhs: ScenePhase, rhs: ScenePhase) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

private struct _ScenePhaseKey: EnvironmentKey {
  static let defaultValue: ScenePhase = .active
}

extension EnvironmentValues {
  public var scenePhase: ScenePhase {
    get { self[_ScenePhaseKey.self] }
    set { self[_ScenePhaseKey.self] = newValue }
  }
}

public protocol EnvironmentKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro Entry() = #externalMacro(module: "SwiftUIRuntimeMacros", type: "EntryMacro")

@attached(accessor)
public macro _EntryDefaultValue() =
  #externalMacro(module: "SwiftUIRuntimeMacros", type: "EntryDefaultValueMacro")

@freestanding(declaration)
public macro Preview<V: View>(
  _ name: String? = nil,
  @ViewBuilder body: @escaping () -> V
) = #externalMacro(module: "SwiftUIRuntimeMacros", type: "PreviewMacro")

@attached(peer)
public macro Previewable() =
  #externalMacro(module: "SwiftUIRuntimeMacros", type: "PreviewableMacro")
public enum ColorScheme: Sendable { case light, dark }
public struct EnvironmentValues {
  var objects: [ObjectIdentifier: AnyObject] = [:]
  private var values: [ObjectIdentifier: Any] = [:]
  public var foregroundColor: Color?
  public var isEnabled: Bool
  public var layoutDirection: LayoutDirection = .leftToRight
  public var colorScheme: ColorScheme = .light
  public var tint: Color = .blue
  public var locale: Locale {
    get { self[LocaleKey.self] }
    set { self[LocaleKey.self] = newValue }
  }
  public var openURL: OpenURLAction {
    get { self[OpenURLKey.self] }
    set { self[OpenURLKey.self] = newValue }
  }
  public var font: Font? = nil
  public var fontResolutionContext: Font.Context { Font.Context() }
  public var accessibilityReduceMotion = false

  package weak var hoverPaintHost: (any HoverPaintHost)?
  public init(foregroundColor: Color? = nil, isEnabled: Bool = true) {
    self.foregroundColor = foregroundColor
    self.isEnabled = isEnabled
  }
  public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
    get { values[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
    set { values[ObjectIdentifier(key)] = newValue }
  }
  public static let `default` = EnvironmentValues()
  package static var current = EnvironmentValues()

  /// Returns true when every entry in `self` matches `other` so an `Equatable`
  /// view can soundly skip re-evaluation when its inputs and environment match.
  func isEquivalent(to other: EnvironmentValues) -> Bool {
    guard hoverPaintHost === other.hoverPaintHost else { return false }
    guard foregroundColor == other.foregroundColor,
      isEnabled == other.isEnabled,
      layoutDirection == other.layoutDirection,
      colorScheme == other.colorScheme,
      tint == other.tint,
      font == other.font,
      accessibilityReduceMotion == other.accessibilityReduceMotion,
      objects.count == other.objects.count,
      values.count == other.values.count
    else { return false }
    for (key, lhs) in objects {
      guard let rhs = other.objects[key], lhs === rhs else { return false }
    }
    for (key, lhs) in values {
      guard let rhs = other.values[key], Self.valuesEqual(lhs, rhs) else { return false }
    }
    return true
  }

  private static func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    if let eq = lhs as? any Equatable {
      return openEquatableEqual(eq, rhs)
    }
    if let lhsOpt = lhs as? any _OptionalEnvironmentValue,
      let rhsOpt = rhs as? any _OptionalEnvironmentValue
    {
      guard type(of: lhs) == type(of: rhs) else { return false }
      if lhsOpt._isNilValue && rhsOpt._isNilValue { return true }
      if lhsOpt._isNilValue != rhsOpt._isNilValue { return false }
      if let lObj = lhsOpt._unwrappedObject, let rObj = rhsOpt._unwrappedObject {
        return lObj === rObj
      }
      return false
    }
    if type(of: lhs) is AnyClass, type(of: rhs) is AnyClass {
      return (lhs as AnyObject) === (rhs as AnyObject)
    }
    return false
  }

  private static func openEquatableEqual<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
    guard let rhs = rhs as? T else { return false }
    return lhs == rhs
  }
}
private protocol _OptionalEnvironmentValue {
  var _isNilValue: Bool { get }
  var _unwrappedObject: AnyObject? { get }
}
extension Optional: _OptionalEnvironmentValue {
  var _isNilValue: Bool { self == nil }
  var _unwrappedObject: AnyObject? {
    guard let wrapped = self, type(of: wrapped) is AnyClass else { return nil }
    return wrapped as AnyObject
  }
}
@propertyWrapper public struct Environment<Value>: _EnvironmentProperty, @unchecked Sendable {
  private final class Storage { var value: Value? }
  private enum Source {
    case keyPath(KeyPath<EnvironmentValues, Value>)
    case resolver((EnvironmentValues) -> Value)
  }
  private let storage = Storage()
  private let source: Source

  nonisolated public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
    self.source = .keyPath(keyPath)
  }

  nonisolated public init(_ objectType: Value.Type) where Value: AnyObject & Observable {
    self.source = .resolver { env in
      guard let object = env.objects[ObjectIdentifier(Value.self)] as? Value else {
        preconditionFailure("No Observable object of type \(Value.self) found in environment.")
      }
      return object
    }
  }

  nonisolated public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
    self.source = .resolver { env in
      env.objects[ObjectIdentifier(T.self)] as? T
    }
  }

  private func read(from env: EnvironmentValues) -> Value {
    switch source {
    case .keyPath(let kp): return env[keyPath: kp]
    case .resolver(let fn): return fn(env)
    }
  }

  public var wrappedValue: Value { storage.value ?? read(from: EnvironmentValues.current) }
  func installEnvironment() { storage.value = read(from: EnvironmentValues.current) }
}
struct EnvironmentView<Content: View, Value>: View, _PrimitiveView {
  typealias Body = Never
  nonisolated let content: Content
  nonisolated let keyPath: WritableKeyPath<EnvironmentValues, Value>
  nonisolated let value: Value
  nonisolated init(content: Content, keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
    self.content = content
    self.keyPath = keyPath
    self.value = value
  }
  var body: Never { fatalError("EnvironmentView is primitive") }
  func _makeElement(path: ViewPath) -> Element {
    let saved = EnvironmentValues.current
    var scoped = saved
    scoped[keyPath: keyPath] = value
    EnvironmentValues.current = scoped
    defer { EnvironmentValues.current = saved }
    var element = _render(content, path: path)
    if keyPath == \EnvironmentValues.colorScheme, let scheme = value as? ColorScheme {
      element.props.colorSchemeOverride = scheme
    }
    return element
  }
}
struct TransformEnvironmentView<Content: View, Value>: View, _PrimitiveView {
  typealias Body = Never
  nonisolated let content: Content
  nonisolated let keyPath: WritableKeyPath<EnvironmentValues, Value>
  nonisolated let transform: (inout Value) -> Void
  nonisolated init(
    content: Content,
    keyPath: WritableKeyPath<EnvironmentValues, Value>,
    transform: @escaping (inout Value) -> Void
  ) {
    self.content = content
    self.keyPath = keyPath
    self.transform = transform
  }
  var body: Never { fatalError("TransformEnvironmentView is primitive") }
  func _makeElement(path: ViewPath) -> Element {
    let saved = EnvironmentValues.current
    var scoped = saved
    transform(&scoped[keyPath: keyPath])
    EnvironmentValues.current = scoped
    defer { EnvironmentValues.current = saved }
    var element = _render(content, path: path)
    if keyPath == \EnvironmentValues.colorScheme,
      let scheme = scoped[keyPath: keyPath] as? ColorScheme
    {
      element.props.colorSchemeOverride = scheme
    }
    return element
  }
}
extension View {
  nonisolated public func environment<Value>(
    _ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value
  ) -> some View {
    EnvironmentView(content: self, keyPath: keyPath, value: value)
  }

  nonisolated public func transformEnvironment<V>(
    _ keyPath: WritableKeyPath<EnvironmentValues, V>,
    transform: @escaping (inout V) -> Void
  ) -> some View {
    TransformEnvironmentView(content: self, keyPath: keyPath, transform: transform)
  }
}

public struct OpenURLAction {
  public enum Result { case handled, discarded, systemAction }
  let action: (URL) -> Result

  public init(handler: @escaping (URL) -> Result) { action = handler }

  @discardableResult public func callAsFunction(_ url: URL) -> Result { action(url) }
}

private enum LocaleKey: EnvironmentKey {
  static var defaultValue: Locale { .current }
}

private enum OpenURLKey: EnvironmentKey {
  static let defaultValue = OpenURLAction { _ in .systemAction }
}
