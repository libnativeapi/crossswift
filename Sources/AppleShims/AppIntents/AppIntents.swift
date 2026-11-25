import CrossFoundation
import Foundation

#if !os(macOS)
  public struct IntentDialog: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public var full: LocalizedStringResource
    public var supporting: LocalizedStringResource?

    public init(_ full: LocalizedStringResource, supporting: LocalizedStringResource? = nil) {
      self.full = full
      self.supporting = supporting
    }

    public init(stringLiteral value: String) {
      self.full = LocalizedStringResource(stringLiteral: value)
      self.supporting = nil
    }
  }

  public struct IntentDescription: ExpressibleByStringLiteral, Sendable {
    public var descriptionText: LocalizedStringResource
    public var categoryName: LocalizedStringResource?
    public var searchKeywords: [LocalizedStringResource]
    public var resultValueName: LocalizedStringResource?

    public init(
      _ descriptionText: LocalizedStringResource,
      categoryName: LocalizedStringResource? = nil,
      searchKeywords: [LocalizedStringResource] = [],
      resultValueName: LocalizedStringResource? = nil
    ) {
      self.descriptionText = descriptionText
      self.categoryName = categoryName
      self.searchKeywords = searchKeywords
      self.resultValueName = resultValueName
    }

    public init(stringLiteral value: String) {
      self.descriptionText = LocalizedStringResource(stringLiteral: value)
      self.categoryName = nil
      self.searchKeywords = []
      self.resultValueName = nil
    }
  }

  public struct TypeDisplayRepresentation: ExpressibleByStringLiteral, Sendable {
    public var name: LocalizedStringResource
    public init(name: LocalizedStringResource) {
      self.name = name
    }
    public init(stringLiteral value: String) {
      self.name = LocalizedStringResource(stringLiteral: value)
    }
  }

  public struct DisplayRepresentation: Sendable {
    public var title: LocalizedStringResource
    public var subtitle: LocalizedStringResource?

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
      self.title = title
      self.subtitle = subtitle
    }
  }

  public protocol IntentResult {
    associatedtype Dialog = Never
    associatedtype Value = Never
  }

  public protocol ReturnsValue<Value>: IntentResult {
    var value: Value? { get }
  }

  public protocol ProvidesDialog: IntentResult {
    var dialog: IntentDialog? { get }
  }

  public struct _EmptyIntentResult: IntentResult, Sendable {
    public init() {}
  }

  public struct _ValueIntentResult<Value>: IntentResult, ReturnsValue {
    public let value: Value?
    public init(value: Value?) {
      self.value = value
    }
  }

  public extension IntentResult where Self == _EmptyIntentResult {
    static func result() -> _EmptyIntentResult {
      _EmptyIntentResult()
    }
  }

  public extension IntentResult {
    static func result<V>(value: V) -> _ValueIntentResult<V> where Self == _ValueIntentResult<V> {
      _ValueIntentResult(value: value)
    }
  }

  public protocol ParameterSummary {}

  public struct _AnyParameterSummary: ParameterSummary {
    public init() {}
  }

  public struct IntentParameterSummaryString<Root>: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public struct StringInterpolation: StringInterpolationProtocol {
      public init(literalCapacity: Int, interpolationCount: Int) {}
      public mutating func appendLiteral(_ literal: String) {}
      public mutating func appendInterpolation<Value>(_ keyPath: KeyPath<Root, IntentParameter<Value>>) {}
      public mutating func appendInterpolation<T>(_ value: T) {}
    }

    public init(stringLiteral value: String) {}
    public init(stringInterpolation: StringInterpolation) {}
  }

  @resultBuilder
  public enum ParameterSummaryContentBuilder<Root> {
    public static func buildBlock(_ components: Any...) -> [Any] { components }
    public static func buildExpression<Value>(_ expression: KeyPath<Root, IntentParameter<Value>>) -> Any { expression }
    public static func buildExpression<T>(_ expression: T) -> Any { expression }
  }

  public struct IntentSummary<Root>: ParameterSummary {
    public init(_ string: IntentParameterSummaryString<Root>) {}
    public init(
      _ string: IntentParameterSummaryString<Root>,
      @ParameterSummaryContentBuilder<Root> _ content: () -> [Any]
    ) {}
    public init(@ParameterSummaryContentBuilder<Root> _ content: () -> [Any]) {}
  }

  public enum ComparisonOperator {
    case equalTo
    case notEqualTo
    case greaterThan
    case lessThan
    case greaterThanOrEqualTo
    case lessThanOrEqualTo
    case hasAnyValue
    case hasNoValue
  }

  public struct IntentWhen<Root, Value>: ParameterSummary {
    public init(
      _ keyPath: KeyPath<Root, IntentParameter<Value>>,
      _ op: ComparisonOperator,
      _ value: Value,
      @ParameterSummaryContentBuilder<Root> _ content: () -> [Any],
      @ParameterSummaryContentBuilder<Root> otherwise: () -> [Any] = { [] }
    ) {}

    public init(
      _ keyPath: KeyPath<Root, IntentParameter<Value>>,
      _ op: ComparisonOperator,
      @ParameterSummaryContentBuilder<Root> _ content: () -> [Any],
      @ParameterSummaryContentBuilder<Root> otherwise: () -> [Any] = { [] }
    ) {}
  }

  @propertyWrapper
  public final class IntentParameter<Value>: @unchecked Sendable {
    public var wrappedValue: Value
    public var projectedValue: IntentParameter<Value> { self }
    public var title: LocalizedStringResource

    public init(
      wrappedValue: Value,
      title: LocalizedStringResource = "",
      description: IntentDescription? = nil,
      requestValueDialog: IntentDialog? = nil
    ) {
      self.wrappedValue = wrappedValue
      self.title = title
    }

    public init(
      title: LocalizedStringResource,
      description: IntentDescription? = nil,
      default defaultValue: Value,
      requestValueDialog: IntentDialog? = nil
    ) {
      self.wrappedValue = defaultValue
      self.title = title
    }

    public init<T>(
      title: LocalizedStringResource,
      description: IntentDescription? = nil,
      requestValueDialog: IntentDialog? = nil
    ) where Value == T? {
      self.wrappedValue = nil
      self.title = title
    }
  }

  public typealias Parameter = IntentParameter

  @propertyWrapper
  public final class EntityProperty<Value>: @unchecked Sendable {
    public var wrappedValue: Value
    public var projectedValue: EntityProperty<Value> { self }
    public var title: LocalizedStringResource

    public init(wrappedValue: Value, title: LocalizedStringResource = "") {
      self.wrappedValue = wrappedValue
      self.title = title
    }

    public init<T>(title: LocalizedStringResource = "") where Value == T? {
      self.wrappedValue = nil
      self.title = title
    }
  }

  public typealias Property = EntityProperty

  public protocol AppIntent {
    associatedtype PerformResult: IntentResult = _EmptyIntentResult
    associatedtype SummaryContent: ParameterSummary = _AnyParameterSummary

    static var title: LocalizedStringResource { get }
    static var description: IntentDescription? { get }
    static var parameterSummary: SummaryContent { get }

    init()
    func perform() async throws -> PerformResult
  }

  public extension AppIntent {
    typealias Summary = IntentSummary<Self>
    typealias When<Value> = IntentWhen<Self, Value>

    static var description: IntentDescription? { nil }
    static var parameterSummary: _AnyParameterSummary { _AnyParameterSummary() }

    @MainActor
    func requestConfirmation(
      actionName: Any? = nil,
      dialog: IntentDialog? = nil
    ) async throws {}
  }

  public protocol CustomIntentMigratedAppIntent: AppIntent {
    static var intentClassName: String { get }
  }

  public protocol AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { get }
    var displayRepresentation: DisplayRepresentation { get }
  }

  public protocol TransientAppEntity: AppEntity {
    init()
  }
#endif
