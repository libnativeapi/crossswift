import Foundation
#if !os(macOS)
  import NativeAPI
#endif

// MARK: - UICoordinateSpace

@MainActor
public protocol UICoordinateSpace: NSObjectProtocol {
  var bounds: CGRect { get }
  func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint
  func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint
  func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect
  func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect
}

@MainActor
private final class _ScreenCoordinateSpace: NSObject, UICoordinateSpace {
  let bounds: CGRect
  init(bounds: CGRect) {
    self.bounds = bounds
    super.init()
  }
  func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint { point }
  func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint { point }
  func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect { rect }
  func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect { rect }
}

// MARK: - UIScreen

@MainActor
open class UIScreen: NSObject, UITraitEnvironment, @unchecked Sendable {
  public static let didConnectNotification = Notification.Name("UIScreenDidConnectNotification")
  public static let didDisconnectNotification = Notification.Name("UIScreenDidDisconnectNotification")
  public static let modeDidChangeNotification = Notification.Name("UIScreenModeDidChangeNotification")
  public static let brightnessDidChangeNotification = Notification.Name("UIScreenBrightnessDidChangeNotification")
  public static let capturedDidChangeNotification = Notification.Name("UIScreenCapturedDidChangeNotification")

  public let bounds: CGRect
  public let nativeBounds: CGRect
  public let scale: CGFloat
  public let nativeScale: CGFloat
  public let maximumFramesPerSecond: Int
  public var brightness: CGFloat = 1.0
  public var wantsSoftwareDimming: Bool = false
  public var isCaptured: Bool { false }

  public var coordinateSpace: any UICoordinateSpace {
    _ScreenCoordinateSpace(bounds: bounds)
  }

  public var fixedCoordinateSpace: any UICoordinateSpace {
    _ScreenCoordinateSpace(bounds: bounds)
  }

  public var traitCollection: UITraitCollection {
    let sys = UITraitCollection.systemTraitCollection
    let hClass: UIUserInterfaceSizeClass = bounds.width >= 667 ? .regular : .compact
    let vClass: UIUserInterfaceSizeClass = bounds.height >= 667 ? .regular : .compact
    return sys.modifyingTraits {
      $0.displayScale = scale
      $0.horizontalSizeClass = hClass
      $0.verticalSizeClass = vClass
    }
  }

  public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}

  public init(
    bounds: CGRect,
    scale: CGFloat = 2.0,
    maximumFramesPerSecond: Int = 60
  ) {
    let resolvedScale = max(scale, 1.0)
    self.bounds = bounds
    self.scale = resolvedScale
    self.nativeScale = resolvedScale
    self.nativeBounds = CGRect(
      x: 0,
      y: 0,
      width: bounds.width * resolvedScale,
      height: bounds.height * resolvedScale
    )
    self.maximumFramesPerSecond = maximumFramesPerSecond
    super.init()
  }

  public static var screens: [UIScreen] {
    #if !os(macOS)
      let displays = NativeAPI.DisplayManager.shared.getAll()
      if !displays.isEmpty {
        return displays.map { d in
          let pos = d.position
          let sz = d.size
          let sf = CGFloat(max(d.scaleFactor, 1.0))
          let refresh = Int(d.refreshRate) > 0 ? Int(d.refreshRate) : 60
          return UIScreen(
            bounds: CGRect(x: CGFloat(pos.x), y: CGFloat(pos.y), width: CGFloat(sz.width), height: CGFloat(sz.height)),
            scale: sf,
            maximumFramesPerSecond: refresh
          )
        }
      }
    #endif
    return [UIScreen(bounds: CGRect(x: 0, y: 0, width: 1280, height: 800), scale: 2.0)]
  }

  public static var main: UIScreen {
    #if !os(macOS)
      if let primary = NativeAPI.DisplayManager.shared.getPrimary() {
        let pos = primary.position
        let sz = primary.size
        let sf = CGFloat(max(primary.scaleFactor, 1.0))
        let refresh = Int(primary.refreshRate) > 0 ? Int(primary.refreshRate) : 60
        return UIScreen(
          bounds: CGRect(x: CGFloat(pos.x), y: CGFloat(pos.y), width: CGFloat(sz.width), height: CGFloat(sz.height)),
          scale: sf,
          maximumFramesPerSecond: refresh
        )
      }
    #endif
    return screens.first ?? UIScreen(bounds: CGRect(x: 0, y: 0, width: 1280, height: 800), scale: 2.0)
  }
}

// MARK: - UIDevice

@MainActor
open class UIDevice: NSObject, @unchecked Sendable {
  public enum BatteryState: Int, Sendable {
    case unknown = 0
    case unplugged = 1
    case charging = 2
    case full = 3
  }

  public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChangeNotification")
  public static let batteryStateDidChangeNotification = Notification.Name("UIDeviceBatteryStateDidChangeNotification")
  public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")
  public static let proximityStateDidChangeNotification = Notification.Name("UIDeviceProximityStateDidChangeNotification")

  public static let current = UIDevice()

  private static let vendorUUIDKey = "CrossUIKit.IdentifierForVendor"

  public var name: String {
    Host.current().localizedName ?? ProcessInfo.processInfo.hostName
  }

  public var model: String {
    #if os(Windows)
      return "PC"
    #elseif os(Linux)
      return "Workstation"
    #else
      return "Mac"
    #endif
  }

  public var localizedModel: String { model }

  public var systemName: String {
    #if os(Windows)
      return "Windows"
    #elseif os(Linux)
      return "Linux"
    #else
      return "macOS"
    #endif
  }

  public var systemVersion: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
  }

  public var orientation: UIDeviceOrientation = .landscapeLeft
  public var userInterfaceIdiom: UIUserInterfaceIdiom = .pad
  public var isMultitaskingSupported: Bool { true }
  public var isBatteryMonitoringEnabled: Bool = false
  public var batteryState: BatteryState = .full
  public var batteryLevel: Float = 1.0
  public var isProximityMonitoringEnabled: Bool = false
  public var proximityState: Bool = false
  public private(set) var isGeneratingDeviceOrientationNotifications: Bool = false

  public var identifierForVendor: UUID? {
    if let existing = UserDefaults.standard.string(forKey: Self.vendorUUIDKey),
       let uuid = UUID(uuidString: existing)
    {
      return uuid
    }
    let created = UUID()
    UserDefaults.standard.set(created.uuidString, forKey: Self.vendorUUIDKey)
    return created
  }

  public func beginGeneratingDeviceOrientationNotifications() {
    isGeneratingDeviceOrientationNotifications = true
  }

  public func endGeneratingDeviceOrientationNotifications() {
    isGeneratingDeviceOrientationNotifications = false
  }

  public func playInputClick() {}
}
