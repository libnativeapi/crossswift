import Foundation
import CrossAppKit
import CrossUIKit
import CoreGraphics
#if os(Windows)
  import CAppKitWindows
#endif

#if !os(macOS)
  public final class QLThumbnailRepresentation: NSObject, @unchecked Sendable {
    public enum RepresentationType: Int, Sendable {
      case icon = 0
      case lowQualityThumbnail = 1
      case thumbnail = 2
    }

    public let nsImage: NSImage
    public let type: RepresentationType
    private let pixelWidth: Int
    private let pixelHeight: Int

    public var uiImage: UIImage {
      if let data = nsImage.imageData, let img = UIImage(data: data) {
        return img
      }
      return UIImage()
    }

    public var cgImage: CGImage {
      if pixelWidth > 0 && pixelHeight > 0 {
        return CGImage(
          width: pixelWidth,
          height: pixelHeight,
          pngData: nsImage.imageData
        )
      }
      return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        ?? CGImage(
          width: max(Int(nsImage.size.width), 1),
          height: max(Int(nsImage.size.height), 1),
          pngData: nsImage.imageData
        )
    }

    public init(
      nsImage: NSImage,
      type: RepresentationType = .thumbnail,
      pixelWidth: Int = 0,
      pixelHeight: Int = 0
    ) {
      self.nsImage = nsImage
      self.type = type
      if pixelWidth > 0 && pixelHeight > 0 {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
      } else if let rep = nsImage.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
        self.pixelWidth = rep.pixelsWide
        self.pixelHeight = rep.pixelsHigh
      } else {
        self.pixelWidth = max(Int(nsImage.size.width.rounded()), 1)
        self.pixelHeight = max(Int(nsImage.size.height.rounded()), 1)
      }
    }
  }

  public final class QLThumbnailGenerator: NSObject, @unchecked Sendable {
    public static let shared = QLThumbnailGenerator()
    public static let errorDomain = "QLThumbnailErrorDomain"

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
      public var iconMode: Bool = false
      public var minimumDimension: CGFloat = 0

      public init(fileAt url: URL, size: CGSize, scale: CGFloat, representationTypes: RepresentationTypes) {
        self.fileURL = url
        self.size = size
        self.scale = scale
        self.representationTypes = representationTypes
      }
    }

    public func generateBestRepresentation(for request: Request) async throws -> QLThumbnailRepresentation {
      guard request.fileURL.isFileURL else {
        throw NSError(
          domain: Self.errorDomain,
          code: NSFileReadInvalidFileNameError,
          userInfo: [NSLocalizedDescriptionKey: "Thumbnail request URL must be a file URL."]
        )
      }
      let path = request.fileURL.path
      guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
        throw NSError(
          domain: Self.errorDomain,
          code: NSFileReadNoSuchFileError,
          userInfo: [NSLocalizedDescriptionKey: "File does not exist at path: \(path)"]
        )
      }
      guard request.size.width > 0, request.size.height > 0 else {
        throw NSError(
          domain: Self.errorDomain,
          code: -2,
          userInfo: [NSLocalizedDescriptionKey: "Thumbnail request size must be positive."]
        )
      }

      var modeFlags: UInt32 = 0
      if request.representationTypes.contains(.icon) { modeFlags |= 1 }
      if request.representationTypes.contains(.thumbnail)
        || request.representationTypes.contains(.lowQualityThumbnail)
      {
        modeFlags |= 2
      }
      guard modeFlags != 0 else {
        throw NSError(
          domain: Self.errorDomain,
          code: -3,
          userInfo: [NSLocalizedDescriptionKey: "Thumbnail request must specify at least one representation type."]
        )
      }

      #if os(Windows)
        let effectiveScale = max(request.scale, 1.0)
        let maxW = max(1, Int((request.size.width * effectiveScale).rounded(.up)))
        let maxH = max(1, Int((request.size.height * effectiveScale).rounded(.up)))
        let requestedTypes = request.representationTypes
        let rep: QLThumbnailRepresentation? = await Task.detached(priority: .userInitiated) {
          var outW: Int32 = 0
          var outH: Int32 = 0
          var outIsIcon: Int32 = 0
          var outLen: Int = 0
          guard let ptr = cak_shell_thumbnail_png_ex(
            path,
            Int32(maxW),
            Int32(maxH),
            modeFlags,
            &outW,
            &outH,
            &outIsIcon,
            &outLen
          ), outLen > 0 else {
            return nil
          }
          let png = Data(bytes: ptr, count: outLen)
          cak_free(ptr)
          guard let image = NSImage(data: png) else { return nil }
          let pxW = outW > 0 ? Int(outW) : max(Int(image.size.width), 1)
          let pxH = outH > 0 ? Int(outH) : max(Int(image.size.height), 1)
          image.size = NSSize(
            width: CGFloat(pxW) / effectiveScale,
            height: CGFloat(pxH) / effectiveScale
          )
          let repType: QLThumbnailRepresentation.RepresentationType
          if outIsIcon != 0 {
            repType = .icon
          } else if requestedTypes.contains(.thumbnail) {
            repType = .thumbnail
          } else {
            repType = .lowQualityThumbnail
          }
          return QLThumbnailRepresentation(
            nsImage: image,
            type: repType,
            pixelWidth: pxW,
            pixelHeight: pxH
          )
        }.value
        if let rep { return rep }
      #endif
      throw NSError(
        domain: Self.errorDomain,
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Unable to generate thumbnail for \(path)"]
      )
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

    public func generateRepresentations(
      for request: Request,
      update updateHandler: (@Sendable (QLThumbnailRepresentation?, QLThumbnailRepresentation.RepresentationType, (any Error)?) -> Void)?
    ) {
      Task {
        do {
          let rep = try await generateBestRepresentation(for: request)
          updateHandler?(rep, rep.type, nil)
        } catch {
          updateHandler?(nil, .icon, error)
        }
      }
    }

    public func cancel(_ request: Request) {}
  }
#endif
