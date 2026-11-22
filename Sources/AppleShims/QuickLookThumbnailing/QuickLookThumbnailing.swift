import Foundation
import CrossAppKit
import CrossUIKit
import CoreGraphics
#if os(Windows)
  import CAppKitWindows
#endif

#if !os(macOS)
  public final class QLThumbnailRepresentation: NSObject, @unchecked Sendable {
    public let nsImage: NSImage
    public var uiImage: UIImage {
      if let data = nsImage.imageData, let img = UIImage(data: data) {
        return img
      }
      return UIImage()
    }
    public var cgImage: CGImage {
      nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        ?? CGImage(
          width: max(Int(nsImage.size.width), 1),
          height: max(Int(nsImage.size.height), 1),
          pngData: nsImage.imageData
        )
    }
    public init(nsImage: NSImage) { self.nsImage = nsImage }
  }

  public final class QLThumbnailGenerator: NSObject, @unchecked Sendable {
    public static let shared = QLThumbnailGenerator()

    public final class Request: NSObject, @unchecked Sendable {
      public struct RepresentationTypes: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let icon = RepresentationTypes(rawValue: 1 << 0)
        public static let lowQualityThumbnail = RepresentationTypes(rawValue: 1 << 1)
        public static let thumbnail = RepresentationTypes(rawValue: 1 << 2)
        public static let all: RepresentationTypes = [.icon, .lowQualityThumbnail, .thumbnail]
      }
      public let fileURL: URL
      public let size: CGSize
      public let scale: CGFloat
      public let representationTypes: RepresentationTypes
      public init(fileAt url: URL, size: CGSize, scale: CGFloat, representationTypes: RepresentationTypes) {
        self.fileURL = url
        self.size = size
        self.scale = scale
        self.representationTypes = representationTypes
      }
    }

    public func generateBestRepresentation(for request: Request) async throws -> QLThumbnailRepresentation {
      #if os(Windows)
        let path = request.fileURL.path
        let maxPx = max(16, Int((max(request.size.width, request.size.height) * max(request.scale, 1.0)).rounded(.up)))
        let rep: QLThumbnailRepresentation? = await Task.detached(priority: .userInitiated) {
          var outW: Int32 = 0
          var outH: Int32 = 0
          var outLen: Int = 0
          guard let ptr = cak_shell_thumbnail_png(path, Int32(maxPx), &outW, &outH, &outLen),
            outLen > 0
          else {
            return nil
          }
          let png = Data(bytes: ptr, count: outLen)
          cak_free(ptr)
          guard let image = NSImage(data: png) else { return nil }
          if outW > 0 && outH > 0 {
            image.size = NSSize(width: CGFloat(outW), height: CGFloat(outH))
          }
          return QLThumbnailRepresentation(nsImage: image)
        }.value
        if let rep { return rep }
      #endif
      throw NSError(domain: "QLThumbnailGenerator", code: -1)
    }

    public func generateBestRepresentation(
      for request: Request,
      completion completionHandler: @escaping @Sendable (QLThumbnailRepresentation?, (any Error)?) -> Void
    ) {
      Task {
        do {
          let rep = try await generateBestRepresentation(for: request)
          completionHandler(rep, nil)
        } catch {
          completionHandler(nil, error)
        }
      }
    }
  }
#endif
