import Dispatch
import Foundation

// MARK: - Cancellable

public protocol Cancellable {
  func cancel()
}

public final class AnyCancellable: Cancellable, Hashable {
  private let lock = NSLock()
  private var cancelAction: (() -> Void)?

  public init(_ cancel: @escaping () -> Void) {
    self.cancelAction = cancel
  }

  public init<C: Cancellable>(_ canceller: C) {
    self.cancelAction = { canceller.cancel() }
  }

  public func cancel() {
    lock.lock()
    let action = cancelAction
    cancelAction = nil
    lock.unlock()
    action?()
  }

  public func store(in set: inout Set<AnyCancellable>) {
    set.insert(self)
  }

  public func store<C: RangeReplaceableCollection>(in collection: inout C)
  where C.Element == AnyCancellable {
    collection.append(self)
  }

  deinit {
    cancel()
  }

  public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

// MARK: - Subscribers & Completion

public enum Subscribers {
  public enum Completion<Failure: Error> {
    case finished
    case failure(Failure)
  }

  public enum Demand: Equatable {
    case unlimited
    case max(Int)
    public static let none = Demand.max(0)
  }
}

extension Subscribers.Completion: Equatable where Failure: Equatable {}

// MARK: - Scheduler

public protocol SchedulerTimeIntervalConvertible {
  static func seconds(_ s: Int) -> Self
  static func seconds(_ s: Double) -> Self
  static func milliseconds(_ ms: Int) -> Self
  static func microseconds(_ us: Int) -> Self
  static func nanoseconds(_ ns: Int) -> Self
  var _timeIntervalSeconds: TimeInterval { get }
}

public protocol Scheduler {
  associatedtype SchedulerTimeType: SchedulerTimeIntervalConvertible
  associatedtype SchedulerOptions

  func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void)
  func schedule(
    after delay: SchedulerTimeType,
    tolerance: SchedulerTimeType?,
    options: SchedulerOptions?,
    _ action: @escaping () -> Void
  )
}

public struct DispatchQueueSchedulerInterval: SchedulerTimeIntervalConvertible, Equatable, Comparable {
  public let seconds: TimeInterval
  public var _timeIntervalSeconds: TimeInterval { seconds }

  public init(_ seconds: TimeInterval) { self.seconds = seconds }
  public static func seconds(_ s: Int) -> Self { Self(Double(s)) }
  public static func seconds(_ s: Double) -> Self { Self(s) }
  public static func milliseconds(_ ms: Int) -> Self { Self(Double(ms) / 1_000.0) }
  public static func microseconds(_ us: Int) -> Self { Self(Double(us) / 1_000_000.0) }
  public static func nanoseconds(_ ns: Int) -> Self { Self(Double(ns) / 1_000_000_000.0) }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.seconds < rhs.seconds }
}

extension DispatchQueue: Scheduler {
  public typealias SchedulerTimeType = DispatchQueueSchedulerInterval
  public struct SchedulerOptions: Sendable {
    public init() {}
  }

  public func schedule(options: SchedulerOptions? = nil, _ action: @escaping () -> Void) {
    async(execute: action)
  }

  public func schedule(
    after delay: SchedulerTimeType,
    tolerance: SchedulerTimeType? = nil,
    options: SchedulerOptions? = nil,
    _ action: @escaping () -> Void
  ) {
    asyncAfter(deadline: .now() + max(0, delay.seconds), execute: action)
  }
}

extension RunLoop {
  public struct SchedulerOptions: Sendable {
    public init() {}
  }
}

extension RunLoop: Scheduler {
  public typealias SchedulerTimeType = DispatchQueueSchedulerInterval

  public func schedule(options: SchedulerOptions? = nil, _ action: @escaping () -> Void) {
    if self === RunLoop.main {
      DispatchQueue.main.async(execute: action)
    } else {
      let timer = Timer(timeInterval: 0, repeats: false) { _ in action() }
      add(timer, forMode: .common)
    }
  }

  public func schedule(
    after delay: SchedulerTimeType,
    tolerance: SchedulerTimeType? = nil,
    options: SchedulerOptions? = nil,
    _ action: @escaping () -> Void
  ) {
    let interval = max(0, delay.seconds)
    if self === RunLoop.main {
      DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: action)
    } else {
      let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
      add(timer, forMode: .common)
    }
  }
}

// MARK: - Publisher Protocol

public protocol Publisher<Output, Failure> {
  associatedtype Output
  associatedtype Failure: Error

  func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable
}

extension Publisher {
  public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
    sink(receiveCompletion: { _ in }, receiveValue: receiveValue)
  }

  public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> {
    AnyPublisher(self)
  }

  public func autoconnect() -> Self {
    self
  }
}

extension Publisher where Failure == Never {
  public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Output>, on object: Root) -> AnyCancellable {
    sink { value in
      object[keyPath: keyPath] = value
    }
  }
}

// MARK: - AnyPublisher

public struct AnyPublisher<Output, Failure: Error>: Publisher {
  private let subscribeHandler: (
    @escaping (Subscribers.Completion<Failure>) -> Void,
    @escaping (Output) -> Void
  ) -> AnyCancellable

  public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {
    self.subscribeHandler = { completion, value in
      publisher.sink(receiveCompletion: completion, receiveValue: value)
    }
  }

  public init(
    _ subscribe: @escaping (
      @escaping (Subscribers.Completion<Failure>) -> Void,
      @escaping (Output) -> Void
    ) -> AnyCancellable
  ) {
    self.subscribeHandler = subscribe
  }

  public init(_ subscribe: @escaping (@escaping (Output) -> Void) -> AnyCancellable) {
    self.subscribeHandler = { _, receiveValue in
      subscribe(receiveValue)
    }
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    subscribeHandler(receiveCompletion, receiveValue)
  }
}

// MARK: - Core Publishers (Just, Empty, Fail, Future, Deferred, Sequence)

public struct Just<Output>: Publisher {
  public typealias Failure = Never
  public let output: Output

  public init(_ output: Output) {
    self.output = output
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Never>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    receiveValue(output)
    receiveCompletion(.finished)
    return AnyCancellable {}
  }
}

public struct Empty<Output, Failure: Error>: Publisher {
  public let completeImmediately: Bool

  public init(completeImmediately: Bool = true) {
    self.completeImmediately = completeImmediately
  }

  public init(completeImmediately: Bool = true, outputType: Output.Type, failureType: Failure.Type) {
    self.completeImmediately = completeImmediately
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    if completeImmediately {
      receiveCompletion(.finished)
    }
    return AnyCancellable {}
  }
}

public struct Fail<Output, Failure: Error>: Publisher {
  public let error: Failure

  public init(error: Failure) {
    self.error = error
  }

  public init(outputType: Output.Type, failure: Failure) {
    self.error = failure
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    receiveCompletion(.failure(error))
    return AnyCancellable {}
  }
}

public final class Future<Output, Failure: Error>: Publisher {
  public typealias Promise = (Result<Output, Failure>) -> Void

  private let lock = NSLock()
  private var result: Result<Output, Failure>?
  private var waiters: [UUID: ((Subscribers.Completion<Failure>) -> Void, (Output) -> Void)] = [:]

  public init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
    attemptToFulfill { [weak self] outcome in
      guard let self else { return }
      self.lock.lock()
      guard self.result == nil else {
        self.lock.unlock()
        return
      }
      self.result = outcome
      let pending = Array(self.waiters.values)
      self.waiters.removeAll()
      self.lock.unlock()
      for (onCompletion, onValue) in pending {
        Self.deliver(outcome, onCompletion: onCompletion, onValue: onValue)
      }
    }
  }

  private static func deliver(
    _ outcome: Result<Output, Failure>,
    onCompletion: (Subscribers.Completion<Failure>) -> Void,
    onValue: (Output) -> Void
  ) {
    switch outcome {
    case .success(let value):
      onValue(value)
      onCompletion(.finished)
    case .failure(let error):
      onCompletion(.failure(error))
    }
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    lock.lock()
    if let resolved = result {
      lock.unlock()
      Self.deliver(resolved, onCompletion: receiveCompletion, onValue: receiveValue)
      return AnyCancellable {}
    }
    let id = UUID()
    waiters[id] = (receiveCompletion, receiveValue)
    lock.unlock()
    return AnyCancellable { [weak self] in
      self?.lock.lock()
      self?.waiters.removeValue(forKey: id)
      self?.lock.unlock()
    }
  }
}

public struct Deferred<DeferredPublisher: Publisher>: Publisher {
  public typealias Output = DeferredPublisher.Output
  public typealias Failure = DeferredPublisher.Failure

  public let createPublisher: () -> DeferredPublisher

  public init(createPublisher: @escaping () -> DeferredPublisher) {
    self.createPublisher = createPublisher
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    createPublisher().sink(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
  }
}

public enum Publishers {
  public struct Sequence<Elements: Swift.Sequence, Failure: Error>: Publisher {
    public typealias Output = Elements.Element
    public let sequence: Elements

    public init(sequence: Elements) {
      self.sequence = sequence
    }

    public func sink(
      receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
      receiveValue: @escaping (Output) -> Void
    ) -> AnyCancellable {
      for element in sequence {
        receiveValue(element)
      }
      receiveCompletion(.finished)
      return AnyCancellable {}
    }
  }
}

extension Sequence {
  public var publisher: Publishers.Sequence<Self, Never> {
    Publishers.Sequence(sequence: self)
  }
}

// MARK: - Subjects

public protocol Subject<Output, Failure>: AnyObject, Publisher {
  func send(_ value: Output)
  func send(completion: Subscribers.Completion<Failure>)
}

public final class PassthroughSubject<Output, Failure: Error>: Subject {
  private let lock = NSLock()
  private var completion: Subscribers.Completion<Failure>?
  private var subscribers: [UUID: ((Subscribers.Completion<Failure>) -> Void, (Output) -> Void)] = [:]

  public init() {}

  public func send(_ value: Output) {
    lock.lock()
    guard completion == nil else {
      lock.unlock()
      return
    }
    let snapshot = Array(subscribers.values)
    lock.unlock()
    for (_, handler) in snapshot {
      handler(value)
    }
  }

  public func send(completion: Subscribers.Completion<Failure>) {
    lock.lock()
    guard self.completion == nil else {
      lock.unlock()
      return
    }
    self.completion = completion
    let snapshot = Array(subscribers.values)
    subscribers.removeAll()
    lock.unlock()
    for (onCompletion, _) in snapshot {
      onCompletion(completion)
    }
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    lock.lock()
    if let completion {
      lock.unlock()
      receiveCompletion(completion)
      return AnyCancellable {}
    }
    let id = UUID()
    subscribers[id] = (receiveCompletion, receiveValue)
    lock.unlock()
    return AnyCancellable { [weak self] in
      self?.lock.lock()
      self?.subscribers.removeValue(forKey: id)
      self?.lock.unlock()
    }
  }
}

public final class CurrentValueSubject<Output, Failure: Error>: Subject {
  private let lock = NSLock()
  private var _value: Output
  private var completion: Subscribers.Completion<Failure>?
  private var subscribers: [UUID: ((Subscribers.Completion<Failure>) -> Void, (Output) -> Void)] = [:]

  public var value: Output {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      send(newValue)
    }
  }

  public init(_ value: Output) {
    self._value = value
  }

  public func send(_ input: Output) {
    lock.lock()
    guard completion == nil else {
      lock.unlock()
      return
    }
    _value = input
    let snapshot = Array(subscribers.values)
    lock.unlock()
    for (_, handler) in snapshot {
      handler(input)
    }
  }

  public func send(completion: Subscribers.Completion<Failure>) {
    lock.lock()
    guard self.completion == nil else {
      lock.unlock()
      return
    }
    self.completion = completion
    let snapshot = Array(subscribers.values)
    subscribers.removeAll()
    lock.unlock()
    for (onCompletion, _) in snapshot {
      onCompletion(completion)
    }
  }

  public func sink(
    receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
    receiveValue: @escaping (Output) -> Void
  ) -> AnyCancellable {
    lock.lock()
    if let completion {
      lock.unlock()
      receiveCompletion(completion)
      return AnyCancellable {}
    }
    let current = _value
    let id = UUID()
    subscribers[id] = (receiveCompletion, receiveValue)
    lock.unlock()
    receiveValue(current)
    return AnyCancellable { [weak self] in
      self?.lock.lock()
      self?.subscribers.removeValue(forKey: id)
      self?.lock.unlock()
    }
  }
}

// MARK: - Operators

extension Publisher {
  public func map<T>(_ transform: @escaping (Output) -> T) -> AnyPublisher<T, Failure> {
    AnyPublisher { onCompletion, onValue in
      self.sink(receiveCompletion: onCompletion, receiveValue: { onValue(transform($0)) })
    }
  }

  public func tryMap<T>(_ transform: @escaping (Output) throws -> T) -> AnyPublisher<T, any Error> {
    AnyPublisher { onCompletion, onValue in
      var terminated = false
      var upstream: AnyCancellable?
      upstream = self.sink(
        receiveCompletion: { comp in
          guard !terminated else { return }
          terminated = true
          switch comp {
          case .finished: onCompletion(.finished)
          case .failure(let err): onCompletion(.failure(err))
          }
        },
        receiveValue: { value in
          guard !terminated else { return }
          do {
            onValue(try transform(value))
          } catch {
            terminated = true
            upstream?.cancel()
            onCompletion(.failure(error))
          }
        }
      )
      return AnyCancellable {
        terminated = true
        upstream?.cancel()
      }
    }
  }

  public func compactMap<T>(_ transform: @escaping (Output) -> T?) -> AnyPublisher<T, Failure> {
    AnyPublisher { onCompletion, onValue in
      self.sink(receiveCompletion: onCompletion, receiveValue: {
        if let mapped = transform($0) { onValue(mapped) }
      })
    }
  }

  public func filter(_ isIncluded: @escaping (Output) -> Bool) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      self.sink(receiveCompletion: onCompletion, receiveValue: {
        if isIncluded($0) { onValue($0) }
      })
    }
  }

  public func flatMap<P: Publisher>(
    maxPublishers: Subscribers.Demand = .unlimited,
    _ transform: @escaping (Output) -> P
  ) -> AnyPublisher<P.Output, Failure> where P.Failure == Failure {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var innerCancellables: [UUID: AnyCancellable] = [:]
      var upstreamFinished = false
      var terminated = false

      func finishIfDone() {
        lock.lock()
        let shouldFinish = !terminated && upstreamFinished && innerCancellables.isEmpty
        if shouldFinish { terminated = true }
        lock.unlock()
        if shouldFinish { onCompletion(.finished) }
      }

      let outer = self.sink(
        receiveCompletion: { comp in
          switch comp {
          case .finished:
            lock.lock()
            upstreamFinished = true
            lock.unlock()
            finishIfDone()
          case .failure(let err):
            lock.lock()
            let shouldFail = !terminated
            terminated = true
            let toCancel = Array(innerCancellables.values)
            innerCancellables.removeAll()
            lock.unlock()
            toCancel.forEach { $0.cancel() }
            if shouldFail { onCompletion(.failure(err)) }
          }
        },
        receiveValue: { value in
          let innerID = UUID()
          let inner = transform(value).sink(
            receiveCompletion: { comp in
              switch comp {
              case .finished:
                lock.lock()
                innerCancellables.removeValue(forKey: innerID)
                lock.unlock()
                finishIfDone()
              case .failure(let err):
                lock.lock()
                let shouldFail = !terminated
                terminated = true
                let toCancel = Array(innerCancellables.values)
                innerCancellables.removeAll()
                lock.unlock()
                toCancel.forEach { $0.cancel() }
                if shouldFail { onCompletion(.failure(err)) }
              }
            },
            receiveValue: { innerVal in
              lock.lock()
              let active = !terminated
              lock.unlock()
              if active { onValue(innerVal) }
            }
          )
          lock.lock()
          if terminated {
            lock.unlock()
            inner.cancel()
          } else {
            innerCancellables[innerID] = inner
            lock.unlock()
          }
        }
      )

      return AnyCancellable {
        lock.lock()
        terminated = true
        let toCancel = Array(innerCancellables.values)
        innerCancellables.removeAll()
        lock.unlock()
        outer.cancel()
        toCancel.forEach { $0.cancel() }
      }
    }
  }

  public func removeDuplicates(
    by predicate: @escaping (Output, Output) -> Bool
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var last: Output?
      return self.sink(receiveCompletion: onCompletion, receiveValue: { value in
        if let prev = last, predicate(prev, value) { return }
        last = value
        onValue(value)
      })
    }
  }

  public func dropFirst(_ count: Int = 1) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var remaining = max(0, count)
      return self.sink(receiveCompletion: onCompletion, receiveValue: { value in
        if remaining > 0 {
          remaining -= 1
          return
        }
        onValue(value)
      })
    }
  }

  public func prefix(_ maxLength: Int) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var remaining = max(0, maxLength)
      var finished = false
      if remaining == 0 {
        onCompletion(.finished)
        return AnyCancellable {}
      }
      var upstream: AnyCancellable?
      upstream = self.sink(
        receiveCompletion: { comp in
          guard !finished else { return }
          finished = true
          onCompletion(comp)
        },
        receiveValue: { value in
          guard !finished, remaining > 0 else { return }
          remaining -= 1
          onValue(value)
          if remaining == 0 {
            finished = true
            upstream?.cancel()
            onCompletion(.finished)
          }
        }
      )
      return AnyCancellable {
        finished = true
        upstream?.cancel()
      }
    }
  }

  public func first() -> AnyPublisher<Output, Failure> {
    prefix(1)
  }

  public func first(where predicate: @escaping (Output) -> Bool) -> AnyPublisher<Output, Failure> {
    filter(predicate).prefix(1)
  }

  public func scan<T>(
    _ initialResult: T,
    _ nextPartialResult: @escaping (T, Output) -> T
  ) -> AnyPublisher<T, Failure> {
    AnyPublisher { onCompletion, onValue in
      var state = initialResult
      return self.sink(receiveCompletion: onCompletion, receiveValue: { value in
        state = nextPartialResult(state, value)
        onValue(state)
      })
    }
  }

  public func receive<S: Scheduler>(
    on scheduler: S,
    options: S.SchedulerOptions? = nil
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var cancelled = false
      let upstream = self.sink(
        receiveCompletion: { comp in
          scheduler.schedule(options: options) {
            if !cancelled { onCompletion(comp) }
          }
        },
        receiveValue: { value in
          scheduler.schedule(options: options) {
            if !cancelled { onValue(value) }
          }
        }
      )
      return AnyCancellable {
        cancelled = true
        upstream.cancel()
      }
    }
  }

  public func subscribe<S: Scheduler>(
    on scheduler: S,
    options: S.SchedulerOptions? = nil
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var cancelled = false
      var upstream: AnyCancellable?
      scheduler.schedule(options: options) {
        guard !cancelled else { return }
        upstream = self.sink(receiveCompletion: onCompletion, receiveValue: onValue)
      }
      return AnyCancellable {
        cancelled = true
        upstream?.cancel()
      }
    }
  }

  public func delay<S: Scheduler>(
    for interval: S.SchedulerTimeType,
    tolerance: S.SchedulerTimeType? = nil,
    scheduler: S,
    options: S.SchedulerOptions? = nil
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      var cancelled = false
      let upstream = self.sink(
        receiveCompletion: { comp in
          scheduler.schedule(after: interval, tolerance: tolerance, options: options) {
            if !cancelled { onCompletion(comp) }
          }
        },
        receiveValue: { value in
          scheduler.schedule(after: interval, tolerance: tolerance, options: options) {
            if !cancelled { onValue(value) }
          }
        }
      )
      return AnyCancellable {
        cancelled = true
        upstream.cancel()
      }
    }
  }

  public func debounce<S: Scheduler>(
    for dueTime: S.SchedulerTimeType,
    scheduler: S,
    options: S.SchedulerOptions? = nil
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var token: UInt64 = 0
      var cancelled = false
      let upstream = self.sink(
        receiveCompletion: { comp in
          lock.lock()
          token &+= 1
          let current = token
          lock.unlock()
          scheduler.schedule(after: dueTime, tolerance: nil, options: options) {
            lock.lock()
            let active = !cancelled && token == current
            lock.unlock()
            if active { onCompletion(comp) }
          }
        },
        receiveValue: { value in
          lock.lock()
          token &+= 1
          let current = token
          lock.unlock()
          scheduler.schedule(after: dueTime, tolerance: nil, options: options) {
            lock.lock()
            let active = !cancelled && token == current
            lock.unlock()
            if active { onValue(value) }
          }
        }
      )
      return AnyCancellable {
        lock.lock()
        cancelled = true
        token &+= 1
        lock.unlock()
        upstream.cancel()
      }
    }
  }

  public func throttle<S: Scheduler>(
    for interval: S.SchedulerTimeType,
    scheduler: S,
    latest: Bool
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var lastEmitTime: TimeInterval = -.infinity
      var pending: Output?
      var timerScheduled = false
      var cancelled = false
      let span = max(0, interval._timeIntervalSeconds)

      let upstream = self.sink(
        receiveCompletion: { comp in
          scheduler.schedule(options: nil) {
            if !cancelled { onCompletion(comp) }
          }
        },
        receiveValue: { value in
          let now = Date.timeIntervalSinceReferenceDate
          lock.lock()
          if now - lastEmitTime >= span {
            lastEmitTime = now
            pending = nil
            lock.unlock()
            scheduler.schedule(options: nil) {
              if !cancelled { onValue(value) }
            }
          } else {
            if latest || pending == nil { pending = value }
            if !timerScheduled {
              timerScheduled = true
              lock.unlock()
              scheduler.schedule(after: interval, tolerance: nil, options: nil) {
                lock.lock()
                timerScheduled = false
                let nextVal = pending
                pending = nil
                if nextVal != nil { lastEmitTime = Date.timeIntervalSinceReferenceDate }
                let active = !cancelled
                lock.unlock()
                if active, let nextVal { onValue(nextVal) }
              }
            } else {
              lock.unlock()
            }
          }
        }
      )
      return AnyCancellable {
        lock.lock()
        cancelled = true
        pending = nil
        lock.unlock()
        upstream.cancel()
      }
    }
  }

  public func combineLatest<P: Publisher>(
    _ other: P
  ) -> AnyPublisher<(Output, P.Output), Failure> where P.Failure == Failure {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var left: Output?
      var right: P.Output?
      var leftDone = false
      var rightDone = false
      var terminated = false

      let c1 = self.sink(
        receiveCompletion: { comp in
          lock.lock()
          defer { lock.unlock() }
          guard !terminated else { return }
          switch comp {
          case .finished:
            leftDone = true
            if rightDone { terminated = true; onCompletion(.finished) }
          case .failure(let err):
            terminated = true
            onCompletion(.failure(err))
          }
        },
        receiveValue: { v in
          lock.lock()
          left = v
          let pair = right.map { (v, $0) }
          let active = !terminated
          lock.unlock()
          if active, let pair { onValue(pair) }
        }
      )
      let c2 = other.sink(
        receiveCompletion: { comp in
          lock.lock()
          defer { lock.unlock() }
          guard !terminated else { return }
          switch comp {
          case .finished:
            rightDone = true
            if leftDone { terminated = true; onCompletion(.finished) }
          case .failure(let err):
            terminated = true
            onCompletion(.failure(err))
          }
        },
        receiveValue: { v in
          lock.lock()
          right = v
          let pair = left.map { ($0, v) }
          let active = !terminated
          lock.unlock()
          if active, let pair { onValue(pair) }
        }
      )
      return AnyCancellable {
        lock.lock()
        terminated = true
        lock.unlock()
        c1.cancel()
        c2.cancel()
      }
    }
  }

  public func combineLatest<P: Publisher, T>(
    _ other: P,
    _ transform: @escaping (Output, P.Output) -> T
  ) -> AnyPublisher<T, Failure> where P.Failure == Failure {
    combineLatest(other).map { transform($0.0, $0.1) }
  }

  public func merge<P: Publisher>(
    with other: P
  ) -> AnyPublisher<Output, Failure> where P.Output == Output, P.Failure == Failure {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var finishedCount = 0
      var terminated = false

      func handleCompletion(_ comp: Subscribers.Completion<Failure>) {
        lock.lock()
        guard !terminated else {
          lock.unlock()
          return
        }
        switch comp {
        case .finished:
          finishedCount += 1
          let done = finishedCount >= 2
          if done { terminated = true }
          lock.unlock()
          if done { onCompletion(.finished) }
        case .failure(let err):
          terminated = true
          lock.unlock()
          onCompletion(.failure(err))
        }
      }

      let c1 = self.sink(receiveCompletion: handleCompletion, receiveValue: onValue)
      let c2 = other.sink(receiveCompletion: handleCompletion, receiveValue: onValue)
      return AnyCancellable {
        lock.lock()
        terminated = true
        lock.unlock()
        c1.cancel()
        c2.cancel()
      }
    }
  }

  public func zip<P: Publisher>(
    _ other: P
  ) -> AnyPublisher<(Output, P.Output), Failure> where P.Failure == Failure {
    AnyPublisher { onCompletion, onValue in
      let lock = NSLock()
      var leftQueue: [Output] = []
      var rightQueue: [P.Output] = []
      var leftDone = false
      var rightDone = false
      var terminated = false

      func drain() {
        while !terminated && !leftQueue.isEmpty && !rightQueue.isEmpty {
          let l = leftQueue.removeFirst()
          let r = rightQueue.removeFirst()
          lock.unlock()
          onValue((l, r))
          lock.lock()
        }
        if !terminated && ((leftDone && leftQueue.isEmpty) || (rightDone && rightQueue.isEmpty)) {
          terminated = true
          lock.unlock()
          onCompletion(.finished)
          lock.lock()
        }
      }

      let c1 = self.sink(
        receiveCompletion: { comp in
          lock.lock()
          defer { lock.unlock() }
          guard !terminated else { return }
          switch comp {
          case .finished: leftDone = true; drain()
          case .failure(let err): terminated = true; onCompletion(.failure(err))
          }
        },
        receiveValue: { v in
          lock.lock()
          leftQueue.append(v)
          drain()
          lock.unlock()
        }
      )
      let c2 = other.sink(
        receiveCompletion: { comp in
          lock.lock()
          defer { lock.unlock() }
          guard !terminated else { return }
          switch comp {
          case .finished: rightDone = true; drain()
          case .failure(let err): terminated = true; onCompletion(.failure(err))
          }
        },
        receiveValue: { v in
          lock.lock()
          rightQueue.append(v)
          drain()
          lock.unlock()
        }
      )
      return AnyCancellable {
        lock.lock()
        terminated = true
        lock.unlock()
        c1.cancel()
        c2.cancel()
      }
    }
  }

  public func `catch`<P: Publisher>(
    _ handler: @escaping (Failure) -> P
  ) -> AnyPublisher<Output, P.Failure> where P.Output == Output {
    AnyPublisher { onCompletion, onValue in
      var fallback: AnyCancellable?
      let upstream = self.sink(
        receiveCompletion: { comp in
          switch comp {
          case .finished: onCompletion(.finished)
          case .failure(let err):
            fallback = handler(err).sink(receiveCompletion: onCompletion, receiveValue: onValue)
          }
        },
        receiveValue: onValue
      )
      return AnyCancellable {
        upstream.cancel()
        fallback?.cancel()
      }
    }
  }

  public func replaceError(with output: Output) -> AnyPublisher<Output, Never> {
    self.catch { _ in Just(output) }
  }

  public func setFailureType<E: Error>(to failureType: E.Type) -> AnyPublisher<Output, E>
  where Failure == Never {
    AnyPublisher { onCompletion, onValue in
      self.sink(
        receiveCompletion: { _ in onCompletion(.finished) },
        receiveValue: onValue
      )
    }
  }

  public func handleEvents(
    receiveSubscription: (() -> Void)? = nil,
    receiveOutput: ((Output) -> Void)? = nil,
    receiveCompletion: ((Subscribers.Completion<Failure>) -> Void)? = nil,
    receiveCancel: (() -> Void)? = nil
  ) -> AnyPublisher<Output, Failure> {
    AnyPublisher { onCompletion, onValue in
      receiveSubscription?()
      let upstream = self.sink(
        receiveCompletion: { comp in
          receiveCompletion?(comp)
          onCompletion(comp)
        },
        receiveValue: { val in
          receiveOutput?(val)
          onValue(val)
        }
      )
      return AnyCancellable {
        receiveCancel?()
        upstream.cancel()
      }
    }
  }
}

extension Publisher where Output: Equatable {
  public func removeDuplicates() -> AnyPublisher<Output, Failure> {
    removeDuplicates(by: ==)
  }
}

// MARK: - Timer & NotificationCenter Publishers

extension Timer {
  public struct TimerPublisher: Publisher {
    public typealias Output = Date
    public typealias Failure = Never

    public let interval: TimeInterval
    public let runLoop: RunLoop
    public let mode: RunLoop.Mode

    public init(interval: TimeInterval, tolerance: TimeInterval? = nil, runLoop: RunLoop, mode: RunLoop.Mode) {
      self.interval = interval
      self.runLoop = runLoop
      self.mode = mode
    }

    public func sink(
      receiveCompletion: @escaping (Subscribers.Completion<Never>) -> Void,
      receiveValue: @escaping (Date) -> Void
    ) -> AnyCancellable {
      let timer = Timer(timeInterval: max(0.01, interval), repeats: true) { _ in
        receiveValue(Date())
      }
      runLoop.add(timer, forMode: mode)
      return AnyCancellable {
        timer.invalidate()
      }
    }
  }

  public static func publish(
    every interval: TimeInterval,
    tolerance: TimeInterval? = nil,
    on runLoop: RunLoop,
    in mode: RunLoop.Mode,
    options: RunLoop.SchedulerOptions? = nil
  ) -> TimerPublisher {
    TimerPublisher(interval: interval, tolerance: tolerance, runLoop: runLoop, mode: mode)
  }
}

extension NotificationCenter {
  public struct Publisher: Combine.Publisher {
    public typealias Output = Notification
    public typealias Failure = Never

    public let center: NotificationCenter
    public let name: Notification.Name
    public let object: AnyObject?

    public init(center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil) {
      self.center = center
      self.name = name
      self.object = object
    }

    public func sink(
      receiveCompletion: @escaping (Subscribers.Completion<Never>) -> Void,
      receiveValue: @escaping (Notification) -> Void
    ) -> AnyCancellable {
      let token = center.addObserver(forName: name, object: object, queue: .main) { note in
        receiveValue(note)
      }
      return AnyCancellable { [center] in
        center.removeObserver(token)
      }
    }
  }

  public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> Publisher {
    Publisher(center: self, name: name, object: object)
  }
}
