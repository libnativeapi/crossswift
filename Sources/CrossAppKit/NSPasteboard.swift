import Foundation
#if !os(macOS)
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

public protocol NSPasteboardWriting: NSObjectProtocol {}
public protocol NSPasteboardReading: NSObjectProtocol {}

extension NSString: NSPasteboardWriting, NSPasteboardReading {}
extension NSURL: NSPasteboardWriting, NSPasteboardReading {}
extension NSImage: NSPasteboardWriting, NSPasteboardReading {}

open class NSPasteboardItem: NSObject, NSPasteboardWriting, NSPasteboardReading {
  private var storage: [NSPasteboard.PasteboardType: Data] = [:]

  open var types: [NSPasteboard.PasteboardType] {
    Array(storage.keys)
  }

  public override init() {
    super.init()
  }

  @discardableResult
  open func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) -> Bool {
    storage[type] = data
    return true
  }

  @discardableResult
  open func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
    storage[type] = Data(string.utf8)
    return true
  }

  open func data(forType type: NSPasteboard.PasteboardType) -> Data? {
    storage[type]
  }

  open func string(forType type: NSPasteboard.PasteboardType) -> String? {
    guard let data = storage[type] else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

#if os(Windows)
  private final class WindowsSystemPasteboardItem: NSPasteboardItem {
    private unowned let board: NSPasteboard
    private let resolvedTypes: [NSPasteboard.PasteboardType]

    init(board: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
      self.board = board
      self.resolvedTypes = types
      super.init()
    }

    override var types: [NSPasteboard.PasteboardType] {
      let extra = super.types.filter { !resolvedTypes.contains($0) }
      return resolvedTypes + extra
    }

    override func data(forType type: NSPasteboard.PasteboardType) -> Data? {
      if let local = super.data(forType: type) { return local }
      return board.readSystemData(forType: type)
    }

    override func string(forType type: NSPasteboard.PasteboardType) -> String? {
      if let local = super.string(forType: type) { return local }
      return board.readSystemString(forType: type)
    }
  }
#endif

open class NSPasteboard: NSObject, @unchecked Sendable {
  public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let general = Name("Apple CFPasteboard general")
  }

  public struct PasteboardType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let string = PasteboardType("public.utf8-plain-text")
    public static let fileURL = PasteboardType("public.file-url")
    public static let URL = PasteboardType("public.url")
    public static let png = PasteboardType("public.png")
    public static let tiff = PasteboardType("public.tiff")
    public static let html = PasteboardType("public.html")
    public static let rtf = PasteboardType("public.rtf")
    public static let pdf = PasteboardType("com.adobe.pdf")
  }

  public struct ReadingOptionKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let urlReadingFileURLsOnly = ReadingOptionKey("NSPasteboardURLReadingFileURLsOnlyKey")
    public static let urlReadingContentsConformToTypes = ReadingOptionKey("NSPasteboardURLReadingContentsConformToTypesKey")
  }

  public static let general = NSPasteboard(name: .general, isSystemGeneral: true)

  public let name: Name
  private let isSystemGeneral: Bool
  private var localChangeCount: Int = 0
  private var localItems: [NSPasteboardItem] = []
  private var knownCustomTypes: Set<PasteboardType> = [
    PasteboardType("org.nspasteboard.ConcealedType"),
    PasteboardType("org.nspasteboard.TransientType"),
    PasteboardType("com.apple.is-sensitive"),
  ]

  public init(name: Name, isSystemGeneral: Bool = false) {
    self.name = name
    self.isSystemGeneral = isSystemGeneral
    super.init()
  }

  public static func withUniqueName() -> NSPasteboard {
    NSPasteboard(name: Name("CrossAppKit.\(UUID().uuidString)"), isSystemGeneral: false)
  }

  public var changeCount: Int {
    #if !os(macOS)
      if isSystemGeneral {
        let count = Int(NativeAPI.Clipboard.shared.getChangeCount())
        if count > 0 { return count }
        #if os(Windows)
          return count
        #endif
      }
    #endif
    return localChangeCount
  }

  @discardableResult
  public func clearContents() -> Int {
    localItems.removeAll()
    #if !os(macOS)
      if isSystemGeneral {
        _ = NativeAPI.Clipboard.shared.clear()
        #if os(Windows)
          return changeCount
        #endif
      }
    #endif
    localChangeCount += 1
    return localChangeCount
  }

  @discardableResult
  public func declareTypes(_ newTypes: [PasteboardType], owner newOwner: Any?) -> Int {
    for t in newTypes where !Self.isStandardType(t) {
      knownCustomTypes.insert(t)
    }
    return clearContents()
  }

  private static func isStandardType(_ type: PasteboardType) -> Bool {
    switch type {
    case .string, .fileURL, .URL, .png, .tiff, .html, .rtf, .pdf:
      return true
    default:
      return false
    }
  }

  private static func decodeFileURL(from data: Data) -> URL? {
    if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
      return url
    }
    if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
      if let url = URL(string: str), url.isFileURL {
        return url
      }
      if !str.isEmpty && FileManager.default.fileExists(atPath: str) {
        return URL(fileURLWithPath: str)
      }
    }
    return nil
  }

  @discardableResult
  public func setString(_ string: String, forType dataType: PasteboardType) -> Bool {
    if localItems.isEmpty { localItems.append(NSPasteboardItem()) }
    _ = localItems[0].setString(string, forType: dataType)
    #if os(Windows)
      if isSystemGeneral {
        if dataType == .fileURL {
          if let url = URL(string: string), url.isFileURL {
            return writeSystemFiles([url.path], clearFirst: false)
          }
          return writeSystemFiles([string], clearFirst: false)
        }
        if dataType == .string || dataType == .URL || dataType == .html {
          return cak_clipboard_add_text(string) != 0
        }
        knownCustomTypes.insert(dataType)
        let utf8 = Data(string.utf8)
        return utf8.withUnsafeBytes { raw in
          cak_clipboard_add_custom(
            dataType.rawValue,
            raw.bindMemory(to: UInt8.self).baseAddress,
            utf8.count
          ) != 0
        }
      }
    #endif
    localChangeCount += 1
    return true
  }

  public func string(forType dataType: PasteboardType) -> String? {
    #if os(Windows)
      if isSystemGeneral {
        return readSystemString(forType: dataType)
      }
    #endif
    return localItems.first?.string(forType: dataType)
  }

  @discardableResult
  public func setData(_ data: Data?, forType dataType: PasteboardType) -> Bool {
    guard let data else { return false }
    if localItems.isEmpty { localItems.append(NSPasteboardItem()) }
    _ = localItems[0].setData(data, forType: dataType)
    #if os(Windows)
      if isSystemGeneral {
        if dataType == .png || dataType == .tiff {
          return data.withUnsafeBytes { raw in
            cak_clipboard_add_png(raw.bindMemory(to: UInt8.self).baseAddress, data.count) != 0
          }
        }
        if dataType == .fileURL {
          guard let url = Self.decodeFileURL(from: data) else { return false }
          return writeSystemFiles([url.path], clearFirst: false)
        }
        if dataType == .string || dataType == .URL {
          guard let str = String(data: data, encoding: .utf8) else { return false }
          return cak_clipboard_add_text(str) != 0
        }
        knownCustomTypes.insert(dataType)
        return data.withUnsafeBytes { raw in
          cak_clipboard_add_custom(
            dataType.rawValue,
            raw.bindMemory(to: UInt8.self).baseAddress,
            data.count
          ) != 0
        }
      }
    #endif
    localChangeCount += 1
    return true
  }

  public func data(forType dataType: PasteboardType) -> Data? {
    #if os(Windows)
      if isSystemGeneral {
        return readSystemData(forType: dataType)
      }
    #endif
    return localItems.first?.data(forType: dataType)
  }

  @discardableResult
  public func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
    var urls: [URL] = []
    var strings: [String] = []
    var images: [NSImage] = []
    var items: [NSPasteboardItem] = []

    for obj in objects {
      if let u = obj as? NSURL, let swiftURL = u as URL? {
        if swiftURL.isFileURL { urls.append(swiftURL) } else { strings.append(swiftURL.absoluteString) }
      } else if let s = obj as? NSString {
        strings.append(s as String)
      } else if let attr = obj as? NSAttributedString {
        strings.append(attr.string)
      } else if let img = obj as? NSImage {
        images.append(img)
      } else if let item = obj as? NSPasteboardItem {
        items.append(item)
      }
    }

    #if os(Windows)
      if isSystemGeneral {
        _ = clearContents()
        var wroteAny = false
        if !urls.isEmpty {
          if writeSystemFiles(urls.map(\.path), clearFirst: false) { wroteAny = true }
        }
        if let firstImg = images.first, let data = firstImg.imageData {
          if setData(data, forType: .png) { wroteAny = true }
        }
        if let firstStr = strings.first {
          if setString(firstStr, forType: .string) { wroteAny = true }
        }
        for item in items {
          for t in item.types {
            if let d = item.data(forType: t), setData(d, forType: t) {
              wroteAny = true
            }
          }
        }
        return wroteAny
      }
    #endif

    localItems.removeAll()
    if !items.isEmpty {
      localItems = items
    } else if !urls.isEmpty {
      localItems = urls.map { u in
        let item = NSPasteboardItem()
        item.setData(u.dataRepresentation, forType: .fileURL)
        return item
      }
    } else if let firstImg = images.first, let data = firstImg.imageData {
      let item = NSPasteboardItem()
      item.setData(data, forType: .png)
      localItems = [item]
    } else if let firstStr = strings.first {
      let item = NSPasteboardItem()
      item.setString(firstStr, forType: .string)
      localItems = [item]
    }
    localChangeCount += 1
    return !localItems.isEmpty
  }

  public func readObjects(forClasses classArray: [AnyClass], options: [ReadingOptionKey: Any]? = nil) -> [Any]? {
    var results: [Any] = []
    let wantsURL = classArray.contains { $0 === NSURL.self }
    let wantsString = classArray.contains { $0 === NSString.self }
    let wantsImage = classArray.contains { $0 === NSImage.self }

    if wantsURL {
      let urls = readFileURLs()
      if !urls.isEmpty { results.append(contentsOf: urls) }
    }
    if wantsImage, let data = data(forType: .png), let img = NSImage(data: data) {
      results.append(img)
    }
    if wantsString, let str = string(forType: .string) {
      results.append(str)
    }
    return results.isEmpty ? nil : results
  }

  public var pasteboardItems: [NSPasteboardItem]? {
    #if os(Windows)
      if isSystemGeneral {
        let sysTypes = querySystemTypes()
        if sysTypes.contains(.fileURL) {
          let urls = readSystemFileURLs()
          if !urls.isEmpty {
            let extraTypes = sysTypes.filter { $0 != .fileURL }
            return urls.enumerated().map { idx, u in
              let item: NSPasteboardItem =
                idx == 0
                ? WindowsSystemPasteboardItem(board: self, types: [.fileURL] + extraTypes)
                : NSPasteboardItem()
              item.setData(u.dataRepresentation, forType: .fileURL)
              return item
            }
          }
        }
        guard !sysTypes.isEmpty else { return nil }
        return [WindowsSystemPasteboardItem(board: self, types: sysTypes)]
      }
    #endif
    return localItems.isEmpty ? nil : localItems
  }

  public var types: [PasteboardType]? {
    #if os(Windows)
      if isSystemGeneral {
        let sys = querySystemTypes()
        return sys.isEmpty ? nil : sys
      }
    #endif
    guard let items = pasteboardItems, let first = items.first else { return nil }
    return first.types
  }

  public func canReadObject(forClasses classArray: [AnyClass], options: [ReadingOptionKey: Any]? = nil) -> Bool {
    if classArray.contains(where: { $0 == NSURL.self }) {
      return !readFileURLs().isEmpty
    }
    if classArray.contains(where: { $0 == NSString.self }) {
      return (types?.contains(.string) == true) || string(forType: .string) != nil
    }
    if classArray.contains(where: { $0 == NSImage.self }) {
      return availableType(from: [.png, .tiff]) != nil
    }
    return false
  }

  public func availableType(from candidateTypes: [PasteboardType]) -> PasteboardType? {
    let available = Set(self.types ?? [])
    return candidateTypes.first { available.contains($0) }
  }

  private func readFileURLs() -> [URL] {
    #if os(Windows)
      if isSystemGeneral {
        return readSystemFileURLs()
      }
    #endif
    return localItems.compactMap { item in
      if let d = item.data(forType: .fileURL), let u = Self.decodeFileURL(from: d) {
        return u
      }
      guard let str = item.string(forType: .fileURL) else { return nil }
      return URL(string: str)
    }
  }

  #if os(Windows)
    private func writeSystemFiles(_ paths: [String], clearFirst: Bool) -> Bool {
      guard !paths.isEmpty else { return false }
      let cStrings = paths.map { _strdup($0) }
      defer { for p in cStrings { free(p) } }
      let ptrs: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
      return ptrs.withUnsafeBufferPointer { buf in
        if clearFirst {
          return cak_clipboard_set_files(buf.baseAddress, Int32(buf.count)) != 0
        } else {
          return cak_clipboard_add_files(buf.baseAddress, Int32(buf.count)) != 0
        }
      }
    }

    private func querySystemTypes() -> [PasteboardType] {
      let clipboard = NativeAPI.Clipboard.shared
      var out: [PasteboardType] = []
      if clipboard.isConcealed() {
        out.append(PasteboardType("org.nspasteboard.ConcealedType"))
      }
      for custom in knownCustomTypes {
        if !out.contains(custom) && clipboard.hasFormat(custom.rawValue) {
          out.append(custom)
        }
      }
      if clipboard.hasFilePaths() { out.append(.fileURL) }
      if clipboard.hasText() { out.append(.string) }
      if clipboard.hasImage() { out.append(.png) }
      if clipboard.hasRtf() { out.append(.rtf) }
      if clipboard.hasHtml() { out.append(.html) }
      return out
    }

    fileprivate func readSystemString(forType dataType: PasteboardType) -> String? {
      switch dataType {
      case .string, .URL:
        if let cstr = cak_clipboard_get_text() {
          defer { cak_free(cstr) }
          return String(cString: cstr)
        }
        return nil
      case .fileURL:
        return readSystemFileURLs().first?.absoluteString
      case .html, .rtf:
        guard let d = readSystemData(forType: dataType) else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
      default:
        guard let d = readSystemData(forType: dataType) else { return nil }
        return String(data: d, encoding: .utf8)
      }
    }

    fileprivate func readSystemData(forType dataType: PasteboardType) -> Data? {
      switch dataType {
      case .png, .tiff:
        var len: Int = 0
        guard let ptr = cak_clipboard_get_png(&len), len > 0 else { return nil }
        let d = Data(bytes: ptr, count: len)
        cak_free(ptr)
        return d
      case .fileURL:
        return readSystemFileURLs().first?.dataRepresentation
      case .string, .URL:
        return readSystemString(forType: dataType).map { Data($0.utf8) }
      case .rtf:
        var len: Int = 0
        guard let ptr = cak_clipboard_get_rtf(&len), len > 0 else { return nil }
        let d = Data(bytes: ptr, count: len)
        cak_free(ptr)
        return d
      case .html:
        var len: Int = 0
        guard let ptr = cak_clipboard_get_html(&len), len > 0 else { return nil }
        let d = Data(bytes: ptr, count: len)
        cak_free(ptr)
        return d
      default:
        var len: Int = 0
        guard let ptr = cak_clipboard_get_custom(dataType.rawValue, &len) else { return nil }
        let d = len > 0 ? Data(bytes: ptr, count: len) : Data()
        cak_free(ptr)
        return d
      }
    }

    private func readSystemFileURLs() -> [URL] {
      guard let cstr = cak_clipboard_get_files_newline() else { return [] }
      defer { cak_free(cstr) }
      let raw = String(cString: cstr)
      return raw.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
  #endif
}
