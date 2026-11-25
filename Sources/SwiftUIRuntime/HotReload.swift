import Foundation
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

// MARK: - Snapshot Wire Types

enum HotReloadValueKind: String, Codable {
  case codable
  case rawRepresentable
  case optionalRawRepresentable
  case navigationPath
}

struct HotReloadEncodedValue: Codable {
  let kind: HotReloadValueKind
  let typeName: String
  let payload: String
}

struct HotReloadStateEntry: Codable {
  let path: String
  let owner: String
  let property: Int
  let label: String?
  let value: HotReloadEncodedValue
}

enum HotReloadAppStorageValue: Codable, Equatable {
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case url(String)
  case data(Data)
  case nilValue
}

struct HotReloadAppStorageBinding {
  let storageKey: String
  let export: () -> HotReloadAppStorageValue
}

private struct NavigationPathElementSnapshot: Codable {
  let typeName: String
  let payload: String
  let label: String
}

private struct HotReloadSnapshot: Codable {
  let version: Int
  let states: [HotReloadStateEntry]
  let sceneStorage: [String: HotReloadEncodedValue]
  let appStorage: [String: HotReloadAppStorageValue]
}

// MARK: - Restore Buffer

final class HotReloadRestoreBuffer {
  struct LabelKey: Hashable {
    let path: String
    let owner: String
    let label: String
  }

  struct IndexKey: Hashable {
    let path: String
    let owner: String
    let property: Int
  }

  var statesByLabel: [LabelKey: HotReloadEncodedValue] = [:]
  var statesByIndex: [IndexKey: HotReloadEncodedValue] = [:]
  var sceneStorage: [String: HotReloadEncodedValue] = [:]
  var appStorage: [String: HotReloadAppStorageValue] = [:]

  fileprivate init(snapshot: HotReloadSnapshot) {
    for entry in snapshot.states {
      if let label = entry.label {
        statesByLabel[LabelKey(path: entry.path, owner: entry.owner, label: label)] = entry.value
      } else {
        statesByIndex[IndexKey(path: entry.path, owner: entry.owner, property: entry.property)] =
          entry.value
      }
    }
    self.sceneStorage = snapshot.sceneStorage
    self.appStorage = snapshot.appStorage
  }
}

// MARK: - Codec Helpers

private struct EncodeBox<T: Encodable>: Encodable {
  let v: T
}

private struct DecodeBox<T: Decodable>: Decodable {
  let v: T
}

private protocol _HotReloadOptional {
  static var _wrappedType: Any.Type { get }
  var _wrappedAny: Any? { get }
  static func _wrapOptional(_ value: Any?) -> Any?
}

extension Optional: _HotReloadOptional {
  fileprivate static var _wrappedType: Any.Type { Wrapped.self }
  fileprivate var _wrappedAny: Any? { self }
  fileprivate static func _wrapOptional(_ value: Any?) -> Any? {
    guard let value else { return Optional<Wrapped>.none as Any }
    guard let typed = value as? Wrapped else { return nil }
    return Optional<Wrapped>.some(typed) as Any
  }
}

enum HotReloadCodec {
  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  /// Strips unstable per-binary memory addresses from Swift private context reflection names
  /// (e.g. `MyApp.(unknown context at $104a3b2c0).Counter` -> `MyApp.(private).Counter`).
  static func normalizeTypeName(_ reflected: String) -> String {
    let marker = "(unknown context at "
    guard reflected.contains(marker) else { return reflected }
    var result = ""
    var index = reflected.startIndex
    while index < reflected.endIndex {
      if let range = reflected.range(of: marker, range: index..<reflected.endIndex) {
        result.append(contentsOf: reflected[index..<range.lowerBound])
        if let close = reflected[range.upperBound...].firstIndex(of: ")") {
          result.append("(private)")
          index = reflected.index(after: close)
        } else {
          result.append(contentsOf: reflected[range.lowerBound...])
          break
        }
      } else {
        result.append(contentsOf: reflected[index...])
        break
      }
    }
    return result
  }

  static func stableIDComponent(_ hashable: AnyHashable) -> String {
    let base = hashable.base
    let typeName = normalizeTypeName(String(reflecting: type(of: base)))
    let raw: String
    if let encodable = base as? any Encodable, let encoded = encodeCodable(encodable) {
      raw = encoded
    } else {
      raw = String(describing: base)
    }
    return escapeSegment("\(typeName)=\(raw)")
  }

  private static func escapeSegment(_ input: String) -> String {
    var out = ""
    out.reserveCapacity(input.count)
    for ch in input {
      switch ch {
      case "\\": out.append("\\\\")
      case "/": out.append("\\/")
      default: out.append(ch)
      }
    }
    return out
  }

  static func encodeCodable<T: Encodable>(_ value: T) -> String? {
    guard let data = try? makeEncoder().encode(EncodeBox(v: value)) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func decodeCodable<T: Decodable>(_ type: T.Type, from payload: String) -> Any? {
    guard let data = payload.data(using: .utf8) else { return nil }
    guard let box = try? JSONDecoder().decode(DecodeBox<T>.self, from: data) else { return nil }
    return box.v
  }

  private static func encodeRawRepresentable<T: RawRepresentable>(_ value: T) -> String? {
    guard let encodable = value.rawValue as? any Encodable else { return nil }
    return encodeCodable(encodable)
  }

  private static func decodeRawRepresentable<T: RawRepresentable>(
    _ type: T.Type,
    from payload: String
  ) -> Any? {
    guard let rawDecodable = T.RawValue.self as? any Decodable.Type,
          let raw = decodeCodable(rawDecodable, from: payload) as? T.RawValue
    else {
      return nil
    }
    return T(rawValue: raw)
  }

  static func encodeValue(_ value: Any) -> HotReloadEncodedValue? {
    if let path = value as? NavigationPath {
      var elements: [NavigationPathElementSnapshot] = []
      elements.reserveCapacity(path.boxes.count)
      for box in path.boxes {
        if let deferred = box.raw as? _DeferredCodableNavigationPayload {
          elements.append(
            NavigationPathElementSnapshot(
              typeName: deferred.typeName,
              payload: deferred.payload,
              label: deferred.label
            )
          )
          continue
        }
        let concrete: Any
        let label: String
        if let rawPayload = box.raw as? _RawBoxPayload {
          concrete = rawPayload.raw
          label = rawPayload.label
        } else {
          concrete = box.raw
          label = box.label
        }
        if let encodable = concrete as? any Encodable,
           let encoded = encodeCodable(encodable)
        {
          elements.append(
            NavigationPathElementSnapshot(
              typeName: normalizeTypeName(String(reflecting: type(of: concrete))),
              payload: encoded,
              label: label
            )
          )
        }
      }
      guard let encoded = encodeCodable(elements) else { return nil }
      return HotReloadEncodedValue(
        kind: .navigationPath,
        typeName: normalizeTypeName(String(reflecting: NavigationPath.self)),
        payload: encoded
      )
    }

    if let encodable = value as? any Encodable,
       let encoded = encodeCodable(encodable)
    {
      return HotReloadEncodedValue(
        kind: .codable,
        typeName: normalizeTypeName(String(reflecting: type(of: value))),
        payload: encoded
      )
    }

    if let optionalValue = value as? any _HotReloadOptional,
       type(of: optionalValue)._wrappedType is any RawRepresentable.Type
    {
      let payload: String
      if let unwrapped = optionalValue._wrappedAny {
        guard let rawRep = unwrapped as? any RawRepresentable,
              let encoded = encodeRawRepresentable(rawRep)
        else {
          return nil
        }
        payload = encoded
      } else {
        payload = ""
      }
      return HotReloadEncodedValue(
        kind: .optionalRawRepresentable,
        typeName: normalizeTypeName(String(reflecting: type(of: value))),
        payload: payload
      )
    }

    if let rawRep = value as? any RawRepresentable,
       let encoded = encodeRawRepresentable(rawRep)
    {
      return HotReloadEncodedValue(
        kind: .rawRepresentable,
        typeName: normalizeTypeName(String(reflecting: type(of: value))),
        payload: encoded
      )
    }

    return nil
  }

  static func decodeValue<Value>(_ entry: HotReloadEncodedValue, as type: Value.Type) -> Value? {
    let expectedTypeName = normalizeTypeName(String(reflecting: Value.self))
    switch entry.kind {
    case .navigationPath:
      guard Value.self == NavigationPath.self,
            let elements = decodeCodable([NavigationPathElementSnapshot].self, from: entry.payload)
              as? [NavigationPathElementSnapshot]
      else {
        return nil
      }
      var path = NavigationPath()
      for element in elements {
        if let box = decodeNavigationPathElement(element) {
          path.boxes.append(box)
        }
      }
      return path as? Value

    case .codable:
      guard entry.typeName == expectedTypeName,
            let decodableType = Value.self as? any Decodable.Type
      else {
        return nil
      }
      return decodeCodable(decodableType, from: entry.payload) as? Value

    case .rawRepresentable:
      guard entry.typeName == expectedTypeName,
            let rawType = Value.self as? any RawRepresentable.Type
      else {
        return nil
      }
      return decodeRawRepresentable(rawType, from: entry.payload) as? Value

    case .optionalRawRepresentable:
      guard entry.typeName == expectedTypeName,
            let optionalType = Value.self as? any _HotReloadOptional.Type,
            let rawType = optionalType._wrappedType as? any RawRepresentable.Type
      else {
        return nil
      }
      if entry.payload.isEmpty {
        return optionalType._wrapOptional(nil) as? Value
      }
      guard let decoded = decodeRawRepresentable(rawType, from: entry.payload) else {
        return nil
      }
      return optionalType._wrapOptional(decoded) as? Value
    }
  }

  private static func decodeNavigationPathElement(
    _ element: NavigationPathElementSnapshot
  ) -> NavigationPath.Box? {
    func tryDecode<T: Hashable & Decodable>(_ type: T.Type) -> NavigationPath.Box? {
      guard element.typeName == normalizeTypeName(String(reflecting: type)),
            let value = decodeCodable(type, from: element.payload) as? T
      else {
        return nil
      }
      return NavigationPath.Box(value)
    }

    if let box = tryDecode(String.self) { return box }
    if let box = tryDecode(Int.self) { return box }
    if let box = tryDecode(Int64.self) { return box }
    if let box = tryDecode(Double.self) { return box }
    if let box = tryDecode(Float.self) { return box }
    if let box = tryDecode(Bool.self) { return box }
    if let box = tryDecode(UUID.self) { return box }
    if let box = tryDecode(URL.self) { return box }
    if let box = tryDecode(Date.self) { return box }
    if let box = tryDecode(Data.self) { return box }
    #if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
      if let box = tryDecode(CGFloat.self) { return box }
    #endif

    return NavigationPath.Box(
      deferred: _DeferredCodableNavigationPayload(
        typeName: element.typeName,
        payload: element.payload,
        label: element.label
      )
    )
  }
}

// MARK: - StateRegistry Hot Reload API

extension StateRegistry {
  func registerAppStorage(
    key: StateKey,
    storageKey: String,
    export: @escaping () -> HotReloadAppStorageValue
  ) {
    appStorageBindings[key] = HotReloadAppStorageBinding(storageKey: storageKey, export: export)
  }

  func pendingAppStorageValue(for storageKey: String) -> HotReloadAppStorageValue? {
    pendingHotReload?.appStorage[storageKey]
  }

  func consumePendingSceneStorage<Value>(for key: String, as type: Value.Type) -> Value? {
    guard let pending = pendingHotReload,
          let encoded = pending.sceneStorage.removeValue(forKey: key)
    else {
      return nil
    }
    return HotReloadCodec.decodeValue(encoded, as: type)
  }

  func consumePendingHotReloadValue<Value>(for key: StateKey, as type: Value.Type) -> Value? {
    guard let pending = pendingHotReload,
          let owner = ownerTypeNames[key.owner]
    else {
      return nil
    }
    let path = key.path.stablePath
    let encoded: HotReloadEncodedValue?
    if let label = propertyLabels[key.owner]?[key.property] {
      encoded = pending.statesByLabel.removeValue(
        forKey: HotReloadRestoreBuffer.LabelKey(path: path, owner: owner, label: label)
      )
    } else {
      encoded = pending.statesByIndex.removeValue(
        forKey: HotReloadRestoreBuffer.IndexKey(path: path, owner: owner, property: key.property)
      )
    }
    guard let encoded else { return nil }
    return HotReloadCodec.decodeValue(encoded, as: type)
  }

  /// Encodes all serializable live state (`@State`, `@FocusState`, `@SceneStorage`,
  /// `@AppStorage`, `NavigationPath`, and `Codable` `@StateObject`) into a UTF-8 JSON
  /// snapshot keyed by stable cross-instance paths.
  public func exportHotReloadSnapshot() -> Data {
    var stateEntries: [HotReloadStateEntry] = []
    stateEntries.reserveCapacity(values.count)

    for (key, value) in values {
      // `@AppStorage` values are exported under `appStorage` keyed by storage key.
      if appStorageBindings[key] != nil { continue }
      guard let owner = ownerTypeNames[key.owner],
            let encoded = HotReloadCodec.encodeValue(value)
      else {
        continue
      }
      let label = propertyLabels[key.owner]?[key.property]
      stateEntries.append(
        HotReloadStateEntry(
          path: key.path.stablePath,
          owner: owner,
          property: key.property,
          label: label,
          value: encoded
        )
      )
    }

    stateEntries.sort { lhs, rhs in
      if lhs.path != rhs.path { return lhs.path < rhs.path }
      if lhs.owner != rhs.owner { return lhs.owner < rhs.owner }
      if lhs.property != rhs.property { return lhs.property < rhs.property }
      return (lhs.label ?? "") < (rhs.label ?? "")
    }

    var sceneEntries: [String: HotReloadEncodedValue] = [:]
    for (name, value) in SceneStorageStore.shared.snapshotEntries() {
      if let encoded = HotReloadCodec.encodeValue(value) {
        sceneEntries[name] = encoded
      }
    }

    var appEntries: [String: HotReloadAppStorageValue] = [:]
    for binding in appStorageBindings.values {
      appEntries[binding.storageKey] = binding.export()
    }

    let snapshot = HotReloadSnapshot(
      version: 1,
      states: stateEntries,
      sceneStorage: sceneEntries,
      appStorage: appEntries
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
  }

  /// Convenience UTF-8 JSON string wrapper around `exportHotReloadSnapshot()`.
  public func exportHotReloadSnapshotJSON() -> String {
    String(data: exportHotReloadSnapshot(), encoding: .utf8) ?? "{}"
  }

  /// Loads a previously exported hot-reload snapshot into the pending restore buffer.
  /// Matching state slots restore during the initial mount pass; mismatched types or
  /// removed views are gracefully skipped. Returns `true` if the snapshot parsed cleanly.
  @discardableResult
  public func importHotReloadSnapshot(_ data: Data) -> Bool {
    guard !data.isEmpty,
          let snapshot = try? JSONDecoder().decode(HotReloadSnapshot.self, from: data),
          snapshot.version == 1
    else {
      pendingHotReload = nil
      return false
    }
    pendingHotReload = HotReloadRestoreBuffer(snapshot: snapshot)
    return true
  }

  /// Convenience UTF-8 JSON string wrapper around `importHotReloadSnapshot(_: Data)`.
  @discardableResult
  public func importHotReloadSnapshot(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8) else {
      pendingHotReload = nil
      return false
    }
    return importHotReloadSnapshot(data)
  }

  /// Clears any unconsumed pending hot-reload entries (also called automatically at the
  /// end of `Renderer.mount()`). Idempotent.
  public func finishHotReloadRestore() {
    pendingHotReload = nil
  }
}
