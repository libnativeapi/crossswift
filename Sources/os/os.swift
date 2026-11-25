@_exported import OSLog
import Foundation

public struct OSAllocatedUnfairLock<State>: @unchecked Sendable {
  private final class Storage: @unchecked Sendable {
    let lock = NSLock()
    var state: State

    init(_ state: State) {
      self.state = state
    }
  }

  private let storage: Storage

  public init(initialState: State) where State: Sendable {
    self.storage = Storage(initialState)
  }

  public init(uncheckedState initialState: State) {
    self.storage = Storage(initialState)
  }

  public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
    storage.lock.lock()
    defer { storage.lock.unlock() }
    return try body(&storage.state)
  }

  public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
    storage.lock.lock()
    defer { storage.lock.unlock() }
    return try body(&storage.state)
  }

  public func withLockIfAvailable<R: Sendable>(
    _ body: @Sendable (inout State) throws -> R
  ) rethrows -> R? {
    guard storage.lock.try() else { return nil }
    defer { storage.lock.unlock() }
    return try body(&storage.state)
  }

  public func withLockIfAvailableUnchecked<R>(
    _ body: (inout State) throws -> R
  ) rethrows -> R? {
    guard storage.lock.try() else { return nil }
    defer { storage.lock.unlock() }
    return try body(&storage.state)
  }
}

extension OSAllocatedUnfairLock where State == Void {
  public init() {
    self.init(uncheckedState: ())
  }

  public func lock() {
    storage.lock.lock()
  }

  public func unlock() {
    storage.lock.unlock()
  }

  public func lockIfAvailable() -> Bool {
    storage.lock.try()
  }

  public func withLock<R: Sendable>(_ body: @Sendable () throws -> R) rethrows -> R {
    storage.lock.lock()
    defer { storage.lock.unlock() }
    return try body()
  }

  public func withLockUnchecked<R>(_ body: () throws -> R) rethrows -> R {
    storage.lock.lock()
    defer { storage.lock.unlock() }
    return try body()
  }

  public func withLockIfAvailable<R: Sendable>(_ body: @Sendable () throws -> R) rethrows -> R? {
    guard storage.lock.try() else { return nil }
    defer { storage.lock.unlock() }
    return try body()
  }

  public func withLockIfAvailableUnchecked<R>(_ body: () throws -> R) rethrows -> R? {
    guard storage.lock.try() else { return nil }
    defer { storage.lock.unlock() }
    return try body()
  }
}
