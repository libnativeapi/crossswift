/// A reference to a value owned elsewhere.
///
/// A child view takes a binding with `@Binding var value: T` and the parent
/// passes `$value`. Reads and writes go straight to the owner's storage, so a
/// write marks the renderer dirty exactly as a direct `@State` write does.
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
  private let getter: () -> Value
  private let setter: (Value) -> Void

  public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
    self.getter = get
    self.setter = set
  }

  public init(projectedValue: Binding<Value>) {
    self = projectedValue
  }

  public var wrappedValue: Value {
    get {
      if let graph = EvaluationGraph.active {
        return graph.trackObservation { getter() }
      }
      return getter()
    }
    nonmutating set { setter(newValue) }
  }

  public var projectedValue: Binding<Value> { self }

  public subscript<Member>(dynamicMember key: WritableKeyPath<Value, Member>) -> Binding<Member> {
    Binding<Member>(
      get: { wrappedValue[keyPath: key] },
      set: {
        var value = wrappedValue
        value[keyPath: key] = $0
        wrappedValue = value
      })
  }

  /// A binding that ignores writes. Reads always return `value`.
  public static func constant(_ value: Value) -> Binding<Value> {
    Binding(get: { value }, set: { _ in })
  }
}

extension Binding: Sequence where Value: MutableCollection {
  public typealias Element = Binding<Value.Element>
  public typealias Iterator = IndexingIterator<Binding<Value>>
}

extension Binding: Collection where Value: MutableCollection {
  public typealias Index = Value.Index
  public typealias Indices = Value.Indices

  public var startIndex: Value.Index { wrappedValue.startIndex }
  public var endIndex: Value.Index { wrappedValue.endIndex }
  public var indices: Value.Indices { wrappedValue.indices }

  public func index(after i: Value.Index) -> Value.Index {
    wrappedValue.index(after: i)
  }

  public func formIndex(after i: inout Value.Index) {
    wrappedValue.formIndex(after: &i)
  }

  public subscript(position: Value.Index) -> Binding<Value.Element> {
    Binding<Value.Element>(
      get: { wrappedValue[position] },
      set: {
        var copy = wrappedValue
        copy[position] = $0
        wrappedValue = copy
      })
  }
}

extension Binding: BidirectionalCollection
where Value: BidirectionalCollection & MutableCollection {
  public func index(before i: Value.Index) -> Value.Index {
    wrappedValue.index(before: i)
  }

  public func formIndex(before i: inout Value.Index) {
    wrappedValue.formIndex(before: &i)
  }
}

extension Binding: RandomAccessCollection
where Value: MutableCollection & RandomAccessCollection {}
