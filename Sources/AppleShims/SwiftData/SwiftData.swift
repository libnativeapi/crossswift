import CrossFoundation
import Foundation
import SwiftUIRuntime

#if !os(macOS)
  public struct PersistentIdentifier: Hashable, Sendable, Codable {
    public let id: UUID
    public init(id: UUID = UUID()) {
      self.id = id
    }
  }

  public protocol PersistentModel: AnyObject, Identifiable, Hashable {
    var persistentModelID: PersistentIdentifier { get }
    var modelContext: ModelContext? { get }
    func _swiftDataSyncRelationships(in context: ModelContext)
    func _swiftDataCascadeChildren() -> [any PersistentModel]
  }

  private final class _PersistentModelBox {
    let id: PersistentIdentifier = PersistentIdentifier()
    weak var context: ModelContext?
  }

  private final class _PersistentModelRegistry: @unchecked Sendable {
    static let shared = _PersistentModelRegistry()
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: _PersistentModelBox] = [:]

    func box(for model: AnyObject) -> _PersistentModelBox {
      let key = ObjectIdentifier(model)
      lock.lock()
      defer { lock.unlock() }
      if let existing = entries[key] {
        return existing
      }
      let created = _PersistentModelBox()
      entries[key] = created
      return created
    }

    func remove(for model: AnyObject) {
      let key = ObjectIdentifier(model)
      lock.lock()
      entries.removeValue(forKey: key)
      lock.unlock()
    }
  }

  public extension PersistentModel {
    var persistentModelID: PersistentIdentifier {
      _PersistentModelRegistry.shared.box(for: self).id
    }

    var id: PersistentIdentifier {
      persistentModelID
    }

    var modelContext: ModelContext? {
      _PersistentModelRegistry.shared.box(for: self).context
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(self))
    }

    func _swiftDataSyncRelationships(in context: ModelContext) {}
    func _swiftDataCascadeChildren() -> [any PersistentModel] { [] }
  }

  public enum Schema {
    public enum Relationship {
      public enum DeleteRule: Sendable, Hashable {
        case noAction
        case nullify
        case cascade
        case deny
      }
    }

    public enum Attribute {
      public enum Option: Sendable, Hashable {
        case unique
        case spotlight
        case externalStorage
        case allowsCloudEncryption
        case preserveValueOnDeletion
        case ephemeral
      }
    }
  }

  public struct ModelConfiguration: Sendable {
    public var name: String
    public var url: URL?
    public var isStoredInMemoryOnly: Bool
    public var allowsSave: Bool

    public init(
      _ name: String? = nil,
      isStoredInMemoryOnly: Bool = false,
      allowsSave: Bool = true
    ) {
      self.name = name ?? "default"
      self.url = nil
      self.isStoredInMemoryOnly = isStoredInMemoryOnly
      self.allowsSave = allowsSave
    }

    public init(
      _ name: String? = nil,
      url: URL,
      allowsSave: Bool = true
    ) {
      self.name = name ?? "default"
      self.url = url
      self.isStoredInMemoryOnly = false
      self.allowsSave = allowsSave
    }
  }

  public struct FetchDescriptor<T: PersistentModel> {
    public var predicate: Predicate<T>?
    public var sortBy: [SortDescriptor<T>]
    public var fetchLimit: Int?
    public var fetchOffset: Int?
    public var includePendingChanges: Bool

    public init(
      predicate: Predicate<T>? = nil,
      sortBy: [SortDescriptor<T>] = []
    ) {
      self.predicate = predicate
      self.sortBy = sortBy
      self.fetchLimit = nil
      self.fetchOffset = nil
      self.includePendingChanges = true
    }
  }

  public final class ModelContext: @unchecked Sendable {
    public unowned let container: ModelContainer
    public var autosaveEnabled: Bool = true
    private let lock = NSLock()
    private var storage: [ObjectIdentifier: [any PersistentModel]] = [:]

    public init(_ container: ModelContainer) {
      self.container = container
    }

    public func insert<T: PersistentModel>(_ model: T) {
      let typeKey = ObjectIdentifier(type(of: model))
      var needsSync = false
      lock.lock()
      var list = storage[typeKey] ?? []
      if !list.contains(where: { ($0 as AnyObject) === (model as AnyObject) }) {
        list.append(model)
        storage[typeKey] = list
        _PersistentModelRegistry.shared.box(for: model).context = self
        needsSync = true
      }
      lock.unlock()
      if needsSync {
        model._swiftDataSyncRelationships(in: self)
      }
    }

    public func delete<T: PersistentModel>(_ model: T) {
      let cascadeChildren = model._swiftDataCascadeChildren()
      let typeKey = ObjectIdentifier(type(of: model))
      lock.lock()
      if var list = storage[typeKey] {
        list.removeAll { ($0 as AnyObject) === (model as AnyObject) }
        storage[typeKey] = list
      }
      _PersistentModelRegistry.shared.box(for: model).context = nil
      lock.unlock()
      for child in cascadeChildren {
        deleteAny(child)
      }
    }

    private func deleteAny(_ model: any PersistentModel) {
      let cascadeChildren = model._swiftDataCascadeChildren()
      let typeKey = ObjectIdentifier(type(of: model))
      lock.lock()
      if var list = storage[typeKey] {
        list.removeAll { ($0 as AnyObject) === (model as AnyObject) }
        storage[typeKey] = list
      }
      _PersistentModelRegistry.shared.box(for: model).context = nil
      lock.unlock()
      for child in cascadeChildren {
        deleteAny(child)
      }
    }

    public func delete<T: PersistentModel>(
      model: T.Type,
      where predicate: Predicate<T>? = nil,
      includeSubclasses: Bool = true
    ) throws {
      let typeKey = ObjectIdentifier(model)
      lock.lock()
      let existing = (storage[typeKey] ?? []).compactMap { $0 as? T }
      lock.unlock()

      var toDelete: [T] = []
      for item in existing {
        if let predicate {
          if try predicate.evaluate(item) {
            toDelete.append(item)
          }
        } else {
          toDelete.append(item)
        }
      }
      for item in toDelete {
        delete(item)
      }
    }

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
      let typeKey = ObjectIdentifier(T.self)
      lock.lock()
      let raw = (storage[typeKey] ?? []).compactMap { $0 as? T }
      lock.unlock()

      var matched: [T]
      if let predicate = descriptor.predicate {
        matched = []
        for item in raw {
          if try predicate.evaluate(item) {
            matched.append(item)
          }
        }
      } else {
        matched = raw
      }

      if !descriptor.sortBy.isEmpty {
        matched.sort(using: descriptor.sortBy)
      }
      if let offset = descriptor.fetchOffset, offset > 0 {
        matched = Array(matched.dropFirst(offset))
      }
      if let limit = descriptor.fetchLimit, limit >= 0 {
        matched = Array(matched.prefix(limit))
      }
      return matched
    }

    public func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int {
      try fetch(descriptor).count
    }

    public func processPendingChanges() {}

    public func save() throws {}

    public func transaction(block: () throws -> Void) throws {
      try block()
    }
  }

  public final class ModelContainer: @unchecked Sendable {
    public let configurations: [ModelConfiguration]
    @MainActor
    public lazy var mainContext: ModelContext = ModelContext(self)

    public init(
      for forTypes: any PersistentModel.Type...,
      configurations: ModelConfiguration...
    ) throws {
      self.configurations = configurations
      for config in configurations {
        if !config.isStoredInMemoryOnly, let url = config.url {
          try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
        }
      }
    }
  }

  private struct _ModelContainerEnvironmentKey: EnvironmentKey {
    static let defaultValue: ModelContainer? = nil
  }

  public extension EnvironmentValues {
    var modelContext: ModelContext {
      get {
        if let container = self[_ModelContainerEnvironmentKey.self] {
          return MainActor.assumeIsolated { container.mainContext }
        }
        fatalError("SwiftData ModelContext not configured in Environment")
      }
      set {}
    }
  }

  public extension View {
    func modelContainer(_ container: ModelContainer) -> some View {
      self.environment(\._modelContainerStorage, container)
    }
  }

  private extension EnvironmentValues {
    var _modelContainerStorage: ModelContainer? {
      get { self[_ModelContainerEnvironmentKey.self] }
      set { self[_ModelContainerEnvironmentKey.self] = newValue }
    }
  }

  @attached(member, names: named(_swiftDataSyncRelationships), named(_swiftDataCascadeChildren))
  @attached(extension, conformances: PersistentModel, Hashable, Identifiable, Sendable)
  public macro Model() = #externalMacro(module: "SwiftUIRuntimeMacros", type: "ModelMacro")

  @attached(peer)
  public macro Relationship(
    deleteRule: Schema.Relationship.DeleteRule = .nullify,
    minimumModelCount: Int? = 0,
    maximumModelCount: Int? = 0,
    originalName: String? = nil,
    inverse: AnyKeyPath? = nil,
    hashModifier: String? = nil
  ) = #externalMacro(module: "SwiftUIRuntimeMacros", type: "SwiftDataNoOpMacro")

  @attached(peer)
  public macro Transient() = #externalMacro(module: "SwiftUIRuntimeMacros", type: "SwiftDataNoOpMacro")

  @attached(peer)
  public macro Attribute(
    _ options: Schema.Attribute.Option...,
    originalName: String? = nil,
    hashModifier: String? = nil
  ) = #externalMacro(module: "SwiftUIRuntimeMacros", type: "SwiftDataNoOpMacro")
#endif
