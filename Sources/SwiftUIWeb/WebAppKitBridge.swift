import AppKit
import Foundation
import JavaScriptEventLoop
import JavaScriptKit
import SwiftUIRuntime

// MARK: - Font <-> NSFont / CTFont

extension SwiftUIRuntime.Font {
  public init(_ font: AppKit.NSFont) {
    self.init(
      size: Double(font.pointSize),
      weight: Weight(font.fontDescriptor.weight.cssWeight),
      family: font.fontName
    )
  }
}

extension SwiftUIRuntime.Font.Resolved {
  public var ctFont: AppKit.NSFont {
    let nsWeight: AppKit.NSFont.Weight
    switch weight.value {
    case ..<150: nsWeight = .ultraLight
    case ..<250: nsWeight = .thin
    case ..<350: nsWeight = .light
    case ..<450: nsWeight = .regular
    case ..<550: nsWeight = .medium
    case ..<650: nsWeight = .semibold
    case ..<750: nsWeight = .bold
    case ..<850: nsWeight = .heavy
    default: nsWeight = .black
    }
    let lower = family.lowercased()
    if lower.contains("mono") || lower == "consolas" {
      return AppKit.NSFont.monospacedSystemFont(ofSize: pointSize, weight: nsWeight)
    }
    if lower.contains("serif") || lower == "georgia" {
      let base = AppKit.NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
      if let desc = base.fontDescriptor.withDesign(.serif),
         let serif = AppKit.NSFont(descriptor: desc, size: pointSize)
      {
        return serif
      }
    }
    return AppKit.NSFont(name: family, size: pointSize)
      ?? AppKit.NSFont.systemFont(ofSize: pointSize, weight: nsWeight)
  }
}

// MARK: - UIImage / Image(uiImage:)

open class UIImage: NSObject, @unchecked Sendable {
  public let data: Data?
  public let size: CGSize
  public let dataURI: String?

  public init?(data: Data) {
    guard !data.isEmpty else { return nil }
    self.data = data
    let mime = Self.detectMIME(data)
    self.dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
    self.size = Self.detectSize(data) ?? CGSize(width: 240, height: 160)
    super.init()
  }

  public init?(named name: String, in bundle: Bundle? = nil, compatibleWith traitCollection: Any? = nil) {
    return nil
  }

  private static func detectMIME(_ data: Data) -> String {
    let bytes = [UInt8](data.prefix(12))
    if bytes.count >= 8, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
      return "image/png"
    }
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return "image/jpeg"
    }
    if bytes.count >= 6, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
      return "image/gif"
    }
    if bytes.count >= 12,
       bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
       bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
    {
      return "image/webp"
    }
    return "image/png"
  }

  private static func detectSize(_ data: Data) -> CGSize? {
    let bytes = [UInt8](data.prefix(24))
    // PNG IHDR width/height at bytes 16..23 (big-endian UInt32).
    if bytes.count >= 24,
       bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47
    {
      let w = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16) | (UInt32(bytes[18]) << 8) | UInt32(bytes[19])
      let h = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16) | (UInt32(bytes[22]) << 8) | UInt32(bytes[23])
      if w > 0, h > 0 { return CGSize(width: CGFloat(w), height: CGFloat(h)) }
    }
    // GIF logical screen descriptor at bytes 6..9 (little-endian UInt16).
    if bytes.count >= 10, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
      let w = UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)
      let h = UInt16(bytes[8]) | (UInt16(bytes[9]) << 8)
      if w > 0, h > 0 { return CGSize(width: CGFloat(w), height: CGFloat(h)) }
    }
    return nil
  }
}

extension SwiftUIRuntime.Image {
  public init(uiImage: UIImage) {
    self.init(
      filePath: uiImage.dataURI ?? "",
      size: Size(width: Double(uiImage.size.width), height: Double(uiImage.size.height))
    )
  }
}

// MARK: - InlinePresentationIntent (missing from WASI Foundation)

public struct InlinePresentationIntent: OptionSet, Hashable, Codable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let emphasized = InlinePresentationIntent(rawValue: 1 << 0)
  public static let stronglyEmphasized = InlinePresentationIntent(rawValue: 1 << 1)
  public static let code = InlinePresentationIntent(rawValue: 1 << 2)
  public static let strikethrough = InlinePresentationIntent(rawValue: 1 << 3)
  public static let softBreak = InlinePresentationIntent(rawValue: 1 << 4)
  public static let lineBreak = InlinePresentationIntent(rawValue: 1 << 5)
  public static let inlineHTML = InlinePresentationIntent(rawValue: 1 << 6)
  public static let blockHTML = InlinePresentationIntent(rawValue: 1 << 7)
}

public enum CrossInlinePresentationIntentAttribute: CodableAttributedStringKey, Hashable, Sendable {
  public typealias Value = InlinePresentationIntent
  public static let name = "NSInlinePresentationIntent"
}

extension AttributedString {
  public var inlinePresentationIntent: InlinePresentationIntent? {
    get { self[CrossInlinePresentationIntentAttribute.self] }
    set { self[CrossInlinePresentationIntentAttribute.self] = newValue }
  }
}

extension AttributeContainer {
  public var inlinePresentationIntent: InlinePresentationIntent? {
    get { self[CrossInlinePresentationIntentAttribute.self] }
    set { self[CrossInlinePresentationIntentAttribute.self] = newValue }
  }

  public func inlinePresentationIntent(_ value: InlinePresentationIntent?) -> AttributeContainer {
    var copy = self
    copy[CrossInlinePresentationIntentAttribute.self] = value
    return copy
  }
}

// MARK: - DispatchQueue (browser setTimeout-backed shim for WASI)

public struct DispatchTime: Sendable {
  public let uptimeNanoseconds: UInt64
  public init(uptimeNanoseconds: UInt64) { self.uptimeNanoseconds = uptimeNanoseconds }
  public static func now() -> DispatchTime { DispatchTime(uptimeNanoseconds: 0) }
}

public enum DispatchTimeInterval: Sendable {
  case seconds(Int)
  case milliseconds(Int)
  case microseconds(Int)
  case nanoseconds(Int)
  case never

  var nanoseconds: UInt64 {
    switch self {
    case .seconds(let v): return UInt64(max(0, v)) * 1_000_000_000
    case .milliseconds(let v): return UInt64(max(0, v)) * 1_000_000
    case .microseconds(let v): return UInt64(max(0, v)) * 1_000
    case .nanoseconds(let v): return UInt64(max(0, v))
    case .never: return UInt64.max
    }
  }
}

public func + (lhs: DispatchTime, rhs: DispatchTimeInterval) -> DispatchTime {
  DispatchTime(uptimeNanoseconds: lhs.uptimeNanoseconds &+ rhs.nanoseconds)
}

public func + (lhs: DispatchTime, rhs: Double) -> DispatchTime {
  DispatchTime(uptimeNanoseconds: lhs.uptimeNanoseconds &+ UInt64(max(0, rhs * 1_000_000_000)))
}

public final class DispatchQueue: @unchecked Sendable {
  public static let main = DispatchQueue()
  public static func global() -> DispatchQueue { main }

  public func async(execute work: @escaping @Sendable () -> Void) {
    _ = JSObject.global.setTimeout!(
      JSOneshotClosure { _ in
        work()
        return .undefined
      },
      0
    )
  }

  public func asyncAfter(deadline: DispatchTime, execute work: @escaping @Sendable () -> Void) {
    let ms = Double(deadline.uptimeNanoseconds) / 1_000_000.0
    _ = JSObject.global.setTimeout!(
      JSOneshotClosure { _ in
        work()
        return .undefined
      },
      ms
    )
  }
}

// MARK: - Browser fetch()-backed URLSession shim for WASI

public struct WebURLResponse: Sendable {
  public let url: URL?
  public let statusCode: Int

  public init(url: URL?, statusCode: Int = 200) {
    self.url = url
    self.statusCode = statusCode
  }
}

public enum WebURLSessionError: Error, Sendable {
  case fetchUnavailable
  case invalidResponse
  case httpError(Int)
}

public final class WebURLSession: @unchecked Sendable {
  public static let shared = WebURLSession()

  @MainActor
  public func data(from url: URL) async throws -> (Data, WebURLResponse) {
    guard let fetchFn = JSObject.global.fetch.function else {
      throw WebURLSessionError.fetchUnavailable
    }
    let promiseValue = fetchFn(url.absoluteString)
    guard let fetchPromise = JSPromise(from: promiseValue) else {
      throw WebURLSessionError.invalidResponse
    }
    let responseValue = try await fetchPromise.value
    guard let responseObj = responseValue.object else {
      throw WebURLSessionError.invalidResponse
    }
    let status = Int(responseObj.status.number ?? 200)
    if let ok = responseObj.ok.boolean, !ok {
      throw WebURLSessionError.httpError(status)
    }
    let bufferPromiseValue = responseObj.arrayBuffer!()
    guard let bufferPromise = JSPromise(from: bufferPromiseValue) else {
      throw WebURLSessionError.invalidResponse
    }
    let arrayBuffer = try await bufferPromise.value
    let uint8Ctor = JSObject.global.Uint8Array.function!
    let view = uint8Ctor.new(arrayBuffer)
    let length = Int(view.length.number ?? 0)
    var bytes = [UInt8](repeating: 0, count: length)
    for i in 0..<length {
      bytes[i] = UInt8(view[i].number ?? 0)
    }
    return (Data(bytes), WebURLResponse(url: url, statusCode: status))
  }
}
