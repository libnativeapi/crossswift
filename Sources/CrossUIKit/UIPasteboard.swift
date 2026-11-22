import CrossAppKit
import Foundation

open class UIPasteboard: NSObject, @unchecked Sendable {
  public struct Name: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let general = Name("com.apple.UIKit.pboard.general")
  }

  public static let changedNotification = Notification.Name("UIPasteboardChangedNotification")
  public static let removedNotification = Notification.Name("UIPasteboardRemovedNotification")

  public static let general = UIPasteboard(backing: CrossAppKit.NSPasteboard.general, name: .general)

  public let name: Name
  public let isPersistent: Bool
  private let backing: CrossAppKit.NSPasteboard
  private var storedColor: UIColor?

  private init(backing: CrossAppKit.NSPasteboard, name: Name, isPersistent: Bool = true) {
    self.backing = backing
    self.name = name
    self.isPersistent = isPersistent
    super.init()
  }

  public convenience init?(name pasteboardName: Name, create: Bool) {
    if pasteboardName == .general {
      self.init(backing: CrossAppKit.NSPasteboard.general, name: .general)
      return
    }
    guard create else { return nil }
    let pb = CrossAppKit.NSPasteboard(name: .init(pasteboardName.rawValue), isSystemGeneral: false)
    self.init(backing: pb, name: pasteboardName, isPersistent: false)
  }

  public static func withUniqueName() -> UIPasteboard {
    let unique = CrossAppKit.NSPasteboard.withUniqueName()
    return UIPasteboard(backing: unique, name: Name(unique.name.rawValue), isPersistent: false)
  }

  public static func remove(withName pasteboardName: Name) {
    NotificationCenter.default.post(name: removedNotification, object: nil)
  }

  public var changeCount: Int {
    backing.changeCount
  }

  public var types: [String] {
    backing.types?.map(\.rawValue) ?? []
  }

  public var hasStrings: Bool {
    string != nil
  }

  public var hasURLs: Bool {
    url != nil
  }

  public var hasImages: Bool {
    image != nil
  }

  public var hasColors: Bool {
    storedColor != nil
  }

  public var string: String? {
    get {
      backing.string(forType: .string)
    }
    set {
      backing.clearContents()
      if let newValue {
        _ = backing.setString(newValue, forType: .string)
      }
      NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
  }

  public var strings: [String]? {
    get {
      guard let s = string else { return nil }
      return [s]
    }
    set {
      string = newValue?.joined(separator: "\n")
    }
  }

  public var url: URL? {
    get {
      if let raw = backing.string(forType: .URL), let parsed = URL(string: raw) {
        return parsed
      }
      if let raw = backing.string(forType: .fileURL), let parsed = URL(string: raw) {
        return parsed
      }
      if let str = backing.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
         str.contains("://"),
         let parsed = URL(string: str)
      {
        return parsed
      }
      return nil
    }
    set {
      backing.clearContents()
      if let newValue {
        if newValue.isFileURL {
          _ = backing.setString(newValue.absoluteString, forType: .fileURL)
        } else {
          _ = backing.setString(newValue.absoluteString, forType: .URL)
          _ = backing.setString(newValue.absoluteString, forType: .string)
        }
      }
      NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
  }

  public var urls: [URL]? {
    get {
      guard let u = url else { return nil }
      return [u]
    }
    set {
      url = newValue?.first
    }
  }

  public var image: UIImage? {
    get {
      guard let data = backing.data(forType: .png) ?? backing.data(forType: .tiff) else { return nil }
      return UIImage(data: data)
    }
    set {
      backing.clearContents()
      if let data = newValue?.pngData() {
        _ = backing.setData(data, forType: .png)
      }
      NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
  }

  public var images: [UIImage]? {
    get {
      guard let img = image else { return nil }
      return [img]
    }
    set {
      image = newValue?.first
    }
  }

  public var color: UIColor? {
    get { storedColor }
    set {
      storedColor = newValue
      NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
  }

  public var colors: [UIColor]? {
    get { storedColor.map { [$0] } }
    set { color = newValue?.first }
  }

  public var items: [[String: Any]] {
    get {
      guard let pbItems = backing.pasteboardItems else { return [] }
      return pbItems.map { item in
        var dict: [String: Any] = [:]
        for t in item.types {
          if let s = item.string(forType: t) {
            dict[t.rawValue] = s
          } else if let d = item.data(forType: t) {
            dict[t.rawValue] = d
          }
        }
        return dict
      }
    }
    set {
      backing.clearContents()
      for dict in newValue {
        for (typeKey, value) in dict {
          setValue(value, forPasteboardType: typeKey)
        }
      }
    }
  }

  public func data(forPasteboardType pasteboardType: String) -> Data? {
    backing.data(forType: .init(pasteboardType))
  }

  public func value(forPasteboardType pasteboardType: String) -> Any? {
    let pt = CrossAppKit.NSPasteboard.PasteboardType(pasteboardType)
    if let s = backing.string(forType: pt) { return s }
    return backing.data(forType: pt)
  }

  public func setData(_ data: Data, forPasteboardType pasteboardType: String) {
    _ = backing.setData(data, forType: .init(pasteboardType))
    NotificationCenter.default.post(name: Self.changedNotification, object: self)
  }

  public func setValue(_ value: Any, forPasteboardType pasteboardType: String) {
    let pt = CrossAppKit.NSPasteboard.PasteboardType(pasteboardType)
    if let str = value as? String {
      _ = backing.setString(str, forType: pt)
    } else if let data = value as? Data {
      _ = backing.setData(data, forType: pt)
    } else if let url = value as? URL {
      _ = backing.setString(url.absoluteString, forType: pt)
    } else if let img = value as? UIImage, let png = img.pngData() {
      _ = backing.setData(png, forType: .png)
    }
    NotificationCenter.default.post(name: Self.changedNotification, object: self)
  }

  public func contains(pasteboardTypes: [String]) -> Bool {
    let active = Set(types)
    return pasteboardTypes.contains { active.contains($0) }
  }
}
