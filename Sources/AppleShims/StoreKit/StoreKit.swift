import Foundation

#if !os(macOS)
  open class SKStoreReviewController: NSObject, @unchecked Sendable {
    public class func requestReview() {}
  }
#endif
