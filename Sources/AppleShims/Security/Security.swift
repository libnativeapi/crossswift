import Foundation
@_exported import CoreFoundation
#if os(Windows)
  import CAppKitWindows
#elseif os(Linux)
  import Glibc
#endif

#if !os(macOS)
  public typealias OSStatus = Int32
  public let errSecSuccess: OSStatus = 0
  public let errSecItemNotFound: OSStatus = -25300
  public let errSecDuplicateItem: OSStatus = -25299
  public let errSecUnimplemented: OSStatus = -4
  public let errSecParam: OSStatus = -50

  public let kSecClass: CFString = "class"
  public let kSecClassGenericPassword: CFString = "genp"
  public let kSecAttrService: CFString = "svce"
  public let kSecAttrAccount: CFString = "acct"
  public let kSecAttrAccessible: CFString = "pdmn"
  public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck"
  public let kSecAttrAccessibleWhenUnlocked: CFString = "ak"
  public let kSecValueData: CFString = "v_Data"
  public let kSecReturnData: CFString = "r_Data"
  public let kSecMatchLimit: CFString = "m_Limit"
  public let kSecMatchLimitOne: CFString = "m_LimitOne"
  public let kSecMatchLimitAll: CFString = "m_LimitAll"
  public let kSecReturnAttributes: CFString = "r_Attributes"
  public let kSecUseDataProtectionKeychain: CFString = "nleg"

  private struct _KeychainLookup {
    let secClass: String
    let service: String
    let account: String
    let returnData: Bool
    let returnAttributes: Bool
    let matchAll: Bool
    let valueData: Data?

    var targetKey: String {
      "crossswift:\(secClass):\(service):\(account)"
    }

    private static func stringValue(_ raw: Any?) -> String? {
      if let s = raw as? String { return s }
      if let ns = raw as? NSString { return String(ns) }
      return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool {
      if let b = raw as? Bool { return b }
      if let n = raw as? NSNumber { return n.boolValue }
      return false
    }

    private static func dataValue(_ raw: Any?) -> Data? {
      if let d = raw as? Data { return d }
      if let ns = raw as? NSData { return Data(referencing: ns) }
      return nil
    }

    static func parse(_ dict: CFDictionary) -> _KeychainLookup? {
      let map: [String: Any]
      if let s = dict as? [String: Any] {
        map = s
      } else {
        let ns: NSDictionary = dict
        var converted: [String: Any] = [:]
        for (k, v) in ns {
          if let ks = stringValue(k) { converted[ks] = v }
        }
        map = converted
      }
      let secClass = stringValue(map[kSecClass as String]) ?? (kSecClassGenericPassword as String)
      let service = stringValue(map[kSecAttrService as String]) ?? ""
      let account = stringValue(map[kSecAttrAccount as String]) ?? ""
      let returnData = boolValue(map[kSecReturnData as String])
      let returnAttributes = boolValue(map[kSecReturnAttributes as String])
      let matchAll = stringValue(map[kSecMatchLimit as String]) == (kSecMatchLimitAll as String)
      let valueData = dataValue(map[kSecValueData as String])
      return _KeychainLookup(
        secClass: secClass,
        service: service,
        account: account,
        returnData: returnData,
        returnAttributes: returnAttributes,
        matchAll: matchAll,
        valueData: valueData
      )
    }
  }

  #if os(Linux) || os(Windows)
    private final class _FileKeychainStore: @unchecked Sendable {
      static let shared = _FileKeychainStore()
      private let lock = NSLock()

      private var storeURL: URL {
        let base: URL
        #if os(Windows)
          if let local = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !local.isEmpty {
            base = URL(fileURLWithPath: local)
          } else {
            base = FileManager.default.temporaryDirectory
          }
        #else
          if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
          } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
          }
        #endif
        return base.appendingPathComponent("crossswift/keychain.json")
      }

      private func loadUnlocked() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
      }

      private func saveUnlocked(_ dict: [String: String]) throws {
        let url = storeURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if os(Linux)
          _ = chmod(dir.path, 0o700)
        #endif
        let data = try JSONEncoder().encode(dict)
        try data.write(to: url, options: .atomic)
        #if os(Linux)
          _ = chmod(url.path, 0o600)
        #endif
      }

      func exists(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()[key] != nil
      }

      func read(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let b64 = loadUnlocked()[key] else { return nil }
        return Data(base64Encoded: b64)
      }

      func write(key: String, data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var dict = loadUnlocked()
        dict[key] = data.base64EncodedString()
        return (try? saveUnlocked(dict)) != nil
      }

      func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var dict = loadUnlocked()
        guard dict.removeValue(forKey: key) != nil else { return false }
        return (try? saveUnlocked(dict)) != nil
      }
    }
  #endif

  public func SecItemCopyMatching(
    _ query: CFDictionary,
    _ result: UnsafeMutablePointer<CFTypeRef?>?
  ) -> OSStatus {
    result?.pointee = nil
    guard let q = _KeychainLookup.parse(query) else { return errSecParam }
    guard !q.service.isEmpty || !q.account.isEmpty else { return errSecParam }

    let foundData: Data?
    #if os(Windows)
      if cak_cred_available() != 0 {
        var len: Int = 0
        if let ptr = cak_cred_read(q.targetKey, &len) {
          foundData = len > 0 ? Data(bytes: ptr, count: len) : Data()
          cak_free(ptr)
        } else {
          foundData = _FileKeychainStore.shared.read(key: q.targetKey)
        }
      } else {
        foundData = _FileKeychainStore.shared.read(key: q.targetKey)
      }
    #elseif os(Linux)
      foundData = _FileKeychainStore.shared.read(key: q.targetKey)
    #else
      foundData = nil
    #endif

    guard let data = foundData else {
      return errSecItemNotFound
    }

    if let result {
      if q.returnAttributes && q.returnData {
        let entry: [String: Any] = [
          kSecClass as String: q.secClass,
          kSecAttrService as String: q.service,
          kSecAttrAccount as String: q.account,
          kSecValueData as String: data,
        ]
        result.pointee = q.matchAll ? ([entry] as AnyObject) : (entry as AnyObject)
      } else if q.returnAttributes {
        let entry: [String: Any] = [
          kSecClass as String: q.secClass,
          kSecAttrService as String: q.service,
          kSecAttrAccount as String: q.account,
        ]
        result.pointee = q.matchAll ? ([entry] as AnyObject) : (entry as AnyObject)
      } else if q.returnData {
        result.pointee = q.matchAll ? ([data] as AnyObject) : (data as AnyObject)
      }
    }
    return errSecSuccess
  }

  public func SecItemAdd(
    _ attributes: CFDictionary,
    _ result: UnsafeMutablePointer<CFTypeRef?>?
  ) -> OSStatus {
    guard let q = _KeychainLookup.parse(attributes), let data = q.valueData else {
      return errSecParam
    }
    guard !q.service.isEmpty || !q.account.isEmpty else { return errSecParam }

    #if os(Windows)
      if cak_cred_available() != 0 {
        if cak_cred_exists(q.targetKey) != 0 {
          return errSecDuplicateItem
        }
        let status = data.withUnsafeBytes { raw -> Int32 in
          cak_cred_write(q.targetKey, q.account, raw.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
        if status > 0 {
          if let result, q.returnData { result.pointee = data as AnyObject }
          return errSecSuccess
        }
        if status == 0 { return errSecParam }
      }
      if _FileKeychainStore.shared.exists(key: q.targetKey) {
        return errSecDuplicateItem
      }
      guard _FileKeychainStore.shared.write(key: q.targetKey, data: data) else {
        return errSecParam
      }
      if let result, q.returnData { result.pointee = data as AnyObject }
      return errSecSuccess
    #elseif os(Linux)
      if _FileKeychainStore.shared.exists(key: q.targetKey) {
        return errSecDuplicateItem
      }
      guard _FileKeychainStore.shared.write(key: q.targetKey, data: data) else {
        return errSecParam
      }
      if let result, q.returnData { result.pointee = data as AnyObject }
      return errSecSuccess
    #else
      return errSecUnimplemented
    #endif
  }

  public func SecItemUpdate(
    _ query: CFDictionary,
    _ attributesToUpdate: CFDictionary
  ) -> OSStatus {
    guard let q = _KeychainLookup.parse(query),
          let updates = _KeychainLookup.parse(attributesToUpdate),
          let newData = updates.valueData
    else { return errSecParam }
    guard !q.service.isEmpty || !q.account.isEmpty else { return errSecParam }

    #if os(Windows)
      if cak_cred_available() != 0, cak_cred_exists(q.targetKey) != 0 {
        let status = newData.withUnsafeBytes { raw -> Int32 in
          cak_cred_write(q.targetKey, q.account, raw.bindMemory(to: UInt8.self).baseAddress, newData.count)
        }
        if status > 0 { return errSecSuccess }
        if status == 0 { return errSecParam }
      }
      guard _FileKeychainStore.shared.exists(key: q.targetKey) else { return errSecItemNotFound }
      return _FileKeychainStore.shared.write(key: q.targetKey, data: newData) ? errSecSuccess : errSecParam
    #elseif os(Linux)
      guard _FileKeychainStore.shared.exists(key: q.targetKey) else { return errSecItemNotFound }
      return _FileKeychainStore.shared.write(key: q.targetKey, data: newData) ? errSecSuccess : errSecParam
    #else
      return errSecUnimplemented
    #endif
  }

  public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    guard let q = _KeychainLookup.parse(query) else { return errSecParam }
    guard !q.service.isEmpty || !q.account.isEmpty else { return errSecParam }

    #if os(Windows)
      if cak_cred_available() != 0, cak_cred_delete(q.targetKey) != 0 {
        return errSecSuccess
      }
      return _FileKeychainStore.shared.delete(key: q.targetKey) ? errSecSuccess : errSecItemNotFound
    #elseif os(Linux)
      return _FileKeychainStore.shared.delete(key: q.targetKey) ? errSecSuccess : errSecItemNotFound
    #else
      return errSecItemNotFound
    #endif
  }

  public final class SecRandom: @unchecked Sendable {}
  public let kSecRandomDefault: SecRandom? = nil
  public func SecRandomCopyBytes(_ rnd: SecRandom?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
    let ptr = bytes.assumingMemoryBound(to: UInt8.self)
    #if os(Windows)
      if cak_random_bytes(ptr, count) != 0 {
        return errSecSuccess
      }
    #endif
    for i in 0..<count { ptr[i] = UInt8.random(in: 0...255) }
    return errSecSuccess
  }

  public final class SecStaticCode: @unchecked Sendable {}
  public final class SecCode: @unchecked Sendable {}
  public final class SecRequirement: @unchecked Sendable {}
  public struct SecCSFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let defaultFlags = SecCSFlags([])
    public static let strictValidate = SecCSFlags(rawValue: 1 << 4)
    public static let checkAllArchitectures = SecCSFlags(rawValue: 1 << 0)
    public static let doNotValidateExecutable = SecCSFlags(rawValue: 1 << 1)
    public static let doNotValidateResources = SecCSFlags(rawValue: 1 << 2)
    public static let signingInformation = SecCSFlags(rawValue: 1 << 1)
  }
  public let kSecCSCheckAllArchitectures: UInt32 = 1 << 0
  public let kSecCSCheckNestedCode: UInt32 = 1 << 3
  public let kSecCSStrictValidate: UInt32 = 1 << 4
  public let kSecCSSigningInformation: UInt32 = 1 << 1
  public let kSecCodeInfoTeamIdentifier: CFString = "teamid"
  public let kSecCodeInfoIdentifier: CFString = "identifier"
  public let kSecCodeInfoUnique: CFString = "unique"
  public func SecStaticCodeCreateWithPath(_ path: URL, _ flags: SecCSFlags, _ staticCode: UnsafeMutablePointer<SecStaticCode?>) -> OSStatus {
    staticCode.pointee = nil
    return errSecUnimplemented
  }
  public func SecStaticCodeCreateWithPath(_ path: CFURL, _ flags: SecCSFlags, _ staticCode: UnsafeMutablePointer<SecStaticCode?>) -> OSStatus {
    staticCode.pointee = nil
    return errSecUnimplemented
  }
  public func SecRequirementCreateWithString(_ text: CFString, _ flags: SecCSFlags, _ requirement: UnsafeMutablePointer<SecRequirement?>) -> OSStatus {
    requirement.pointee = nil
    return errSecUnimplemented
  }
  public func SecCodeCopyStaticCode(_ code: SecCode, _ flags: SecCSFlags, _ staticCode: UnsafeMutablePointer<SecStaticCode?>) -> OSStatus {
    staticCode.pointee = nil
    return errSecUnimplemented
  }
  public func SecCodeCopyDesignatedRequirement(_ code: SecStaticCode, _ flags: SecCSFlags, _ requirement: UnsafeMutablePointer<SecRequirement?>) -> OSStatus {
    requirement.pointee = nil
    return errSecUnimplemented
  }
  public func SecStaticCodeCheckValidity(_ staticCode: SecStaticCode, _ flags: SecCSFlags, _ requirement: SecRequirement?) -> OSStatus {
    errSecUnimplemented
  }
  public func SecCodeCopySigningInformation(_ code: SecStaticCode, _ flags: SecCSFlags, _ information: UnsafeMutablePointer<CFDictionary?>) -> OSStatus {
    information.pointee = nil
    return errSecUnimplemented
  }
  public func SecCodeCopySelf(_ flags: SecCSFlags, _ selfCode: UnsafeMutablePointer<SecCode?>) -> OSStatus {
    selfCode.pointee = nil
    return errSecUnimplemented
  }
  public func SecCodeCopySigningInformation(_ code: SecCode, _ flags: SecCSFlags, _ information: UnsafeMutablePointer<CFDictionary?>) -> OSStatus {
    information.pointee = nil
    return errSecUnimplemented
  }

  public final class SecTask: @unchecked Sendable {}
  public func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> SecTask? { nil }
  public func SecTaskCopyValueForEntitlement(_ task: SecTask, _ entitlement: CFString, _ error: UnsafeMutablePointer<AnyObject?>?) -> CFTypeRef? { nil }
#endif
