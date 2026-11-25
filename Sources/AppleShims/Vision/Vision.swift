import CoreGraphics
import Foundation

#if !os(macOS)
  public enum VNRequestTextRecognitionLevel: Int, Sendable {
    case accurate = 0
    case fast = 1
  }

  public struct VNImageOption: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
  }

  open class VNObservation: NSObject, @unchecked Sendable {
    public var uuid: UUID = UUID()
    public var confidence: Float = 0
  }

  open class VNRecognizedText: NSObject, @unchecked Sendable {
    public let string: String
    public let confidence: Float
    public init(string: String, confidence: Float = 1.0) {
      self.string = string
      self.confidence = confidence
      super.init()
    }
  }

  open class VNRecognizedTextObservation: VNObservation, @unchecked Sendable {
    private let candidates: [VNRecognizedText]
    public init(candidates: [VNRecognizedText] = []) {
      self.candidates = candidates
      super.init()
    }
    public func topCandidates(_ maxCandidateCount: Int) -> [VNRecognizedText] {
      Array(candidates.prefix(maxCandidateCount))
    }
  }

  public typealias VNRequestCompletionHandler = (VNRequest, (any Error)?) -> Void

  open class VNRequest: NSObject, @unchecked Sendable {
    public var completionHandler: VNRequestCompletionHandler?
    public var preferBackgroundProcessing: Bool = false
    public var usesCPUOnly: Bool = false
    public var revision: Int = 1

    public init(completionHandler: VNRequestCompletionHandler? = nil) {
      self.completionHandler = completionHandler
      super.init()
    }
  }

  open class VNRecognizeTextRequest: VNRequest, @unchecked Sendable {
    public var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    public var recognitionLanguages: [String] = []
    public var customWords: [String] = []
    public var usesLanguageCorrection: Bool = true
    public var automaticallyDetectsLanguage: Bool = false
    public var minimumTextHeight: Float = 0
    public var results: [VNRecognizedTextObservation]? = []

    public override init(completionHandler: VNRequestCompletionHandler? = nil) {
      super.init(completionHandler: completionHandler)
    }
  }

  open class VNImageRequestHandler: NSObject, @unchecked Sendable {
    private let imageData: Data?
    private let imageURL: URL?

    public init(data: Data, options: [VNImageOption: Any] = [:]) {
      self.imageData = data
      self.imageURL = nil
      super.init()
    }

    public init(url: URL, options: [VNImageOption: Any] = [:]) {
      self.imageData = nil
      self.imageURL = url
      super.init()
    }

    public init(cgImage: CGImage, options: [VNImageOption: Any] = [:]) {
      self.imageData = nil
      self.imageURL = nil
      super.init()
    }

    public func perform(_ requests: [VNRequest]) throws {
      for request in requests {
        if let textReq = request as? VNRecognizeTextRequest {
          textReq.results = []
        }
        request.completionHandler?(request, nil)
      }
    }
  }
#endif
