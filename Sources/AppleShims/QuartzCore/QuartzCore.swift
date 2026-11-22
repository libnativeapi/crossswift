@_exported import Foundation
#if !os(macOS)
  @_exported import CoreGraphics
  import CrossAppKit

  public typealias CFTimeInterval = Double
  public typealias CALayer = CrossAppKit.CALayer
  public typealias CAShapeLayer = CrossAppKit.CAShapeLayer
  public typealias CAGradientLayer = CrossAppKit.CAGradientLayer
  public typealias CATextLayer = CrossAppKit.CATextLayer
  public typealias CAAnimation = CrossAppKit.CAAnimation
  public typealias CABasicAnimation = CrossAppKit.CABasicAnimation
  public typealias CASpringAnimation = CrossAppKit.CASpringAnimation
  public typealias CATransaction = CrossAppKit.CATransaction
  public typealias CADisplayLink = CrossAppKit.CADisplayLink
  public typealias CAMediaTimingFunction = CrossAppKit.CAMediaTimingFunction
  public typealias CAMediaTimingFunctionName = CrossAppKit.CAMediaTimingFunctionName
  public typealias CACornerMask = CrossAppKit.CACornerMask
  public typealias CALayerCornerCurve = CrossAppKit.CALayerCornerCurve

  public func CACurrentMediaTime() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
  }
#endif
