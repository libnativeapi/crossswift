import CrossAppKit
import Foundation
#if !os(macOS)
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

// MARK: - UIScene, UIWindowScene & Scene Lifecycle

@MainActor
public protocol UISceneDelegate: NSObjectProtocol {
  init()
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
  func sceneDidDisconnect(_ scene: UIScene)
  func sceneDidBecomeActive(_ scene: UIScene)
  func sceneWillResignActive(_ scene: UIScene)
  func sceneWillEnterForeground(_ scene: UIScene)
  func sceneDidEnterBackground(_ scene: UIScene)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>)
}

extension UISceneDelegate {
  public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {}
  public func sceneDidDisconnect(_ scene: UIScene) {}
  public func sceneDidBecomeActive(_ scene: UIScene) {}
  public func sceneWillResignActive(_ scene: UIScene) {}
  public func sceneWillEnterForeground(_ scene: UIScene) {}
  public func sceneDidEnterBackground(_ scene: UIScene) {}
  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {}
}

@MainActor
public protocol UIWindowSceneDelegate: UISceneDelegate {
  var window: UIWindow? { get set }
}

extension UIWindowSceneDelegate {
  public var window: UIWindow? {
    get { nil }
    set {}
  }
}

open class UIOpenURLContext: NSObject {
  public let url: URL
  public init(url: URL) {
    self.url = url
    super.init()
  }
}

open class UISceneConfiguration: NSObject, NSCopying {
  public var name: String?
  public let role: UISceneSession.Role
  public var sceneClass: AnyClass?
  public var delegateClass: AnyClass?

  public init(name: String?, sessionRole: UISceneSession.Role) {
    self.name = name
    self.role = sessionRole
    super.init()
  }

  open func copy(with zone: NSZone? = nil) -> Any {
    let c = UISceneConfiguration(name: name, sessionRole: role)
    c.sceneClass = sceneClass
    c.delegateClass = delegateClass
    return c
  }
}

open class UISceneSession: NSObject {
  public struct Role: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let windowApplication = Role(rawValue: "UIWindowSceneSessionRoleApplication")
    public static let windowExternalDisplayNonInteractive = Role(rawValue: "UIWindowSceneSessionRoleExternalDisplayNonInteractive")
  }

  public let persistentIdentifier: String
  public let role: Role
  public internal(set) var configuration: UISceneConfiguration
  public internal(set) weak var scene: UIScene?
  public var userInfo: [String: Any]? = [:]

  public init(role: Role = .windowApplication, configurationName: String? = "Default Configuration") {
    self.persistentIdentifier = UUID().uuidString
    self.role = role
    self.configuration = UISceneConfiguration(name: configurationName, sessionRole: role)
    super.init()
  }
}

@MainActor
open class UIScene: UIResponder {
  public enum ActivationState: Int, Sendable {
    case unattached = -1
    case foregroundActive = 0
    case foregroundInactive = 1
    case background = 2
  }

  open class ConnectionOptions: NSObject {
    public let urlContexts: Set<UIOpenURLContext>
    public init(urlContexts: Set<UIOpenURLContext> = []) {
      self.urlContexts = urlContexts
      super.init()
    }
  }

  open class ActivationRequestOptions: NSObject {}

  public static let willConnectNotification = Notification.Name("UISceneWillConnectNotification")
  public static let didDisconnectNotification = Notification.Name("UISceneDidDisconnectNotification")
  public static let didActivateNotification = Notification.Name("UISceneDidActivateNotification")
  public static let willDeactivateNotification = Notification.Name("UISceneWillDeactivateNotification")
  public static let willEnterForegroundNotification = Notification.Name("UISceneWillEnterForegroundNotification")
  public static let didEnterBackgroundNotification = Notification.Name("UISceneDidEnterBackgroundNotification")

  public let session: UISceneSession
  public var delegate: (any UISceneDelegate)?
  private var retainedDelegate: (any UISceneDelegate)?
  public internal(set) var activationState: ActivationState = .foregroundActive
  public var title: String! = "" {
    didSet {
      (self as? UIWindowScene)?._syncSceneTitle()
    }
  }
  public var subtitle: String = ""

  public init(session: UISceneSession, connectionOptions: ConnectionOptions) {
    self.session = session
    super.init()
    session.scene = self
  }

  public required override init?(coder: NSCoder) {
    self.session = UISceneSession()
    super.init(coder: coder)
  }

  internal func _installRetainedDelegate(_ delegate: any UISceneDelegate) {
    self.retainedDelegate = delegate
    self.delegate = delegate
  }
}

@MainActor
open class UIStatusBarManager: NSObject {
  public var statusBarStyle: UIStatusBarStyle = .default
  public var isStatusBarHidden: Bool = false
  public var statusBarFrame: CGRect = .zero
}

@MainActor
open class UISceneSizeRestrictions: NSObject {
  public var minimumSize: CGSize = CGSize(width: 320, height: 240) {
    didSet { onChange?() }
  }
  public var maximumSize: CGSize = CGSize(width: 10000, height: 10000) {
    didSet { onChange?() }
  }
  internal var onChange: (() -> Void)?
}

@MainActor
open class UIWindowScene: UIScene {
  public let screen: UIScreen
  public internal(set) var interfaceOrientation: UIInterfaceOrientation = .landscapeLeft
  public let statusBarManager: UIStatusBarManager? = UIStatusBarManager()
  public let sizeRestrictions: UISceneSizeRestrictions? = UISceneSizeRestrictions()

  private struct WeakUIWindow {
    weak var window: UIWindow?
  }
  private var sceneWindows: [WeakUIWindow] = []

  public var windows: [UIWindow] {
    sceneWindows.compactMap(\.window)
  }

  public var keyWindow: UIWindow? {
    windows.first { $0.isKeyWindow && !$0.isHidden } ?? windows.first { !$0.isHidden }
  }

  public var coordinateSpace: any UICoordinateSpace {
    keyWindow ?? screen.coordinateSpace
  }

  public var traitCollection: UITraitCollection {
    screen.traitCollection
  }

  public override init(session: UISceneSession, connectionOptions: ConnectionOptions) {
    self.screen = UIScreen.main
    super.init(session: session, connectionOptions: connectionOptions)
    sizeRestrictions?.onChange = { [weak self] in
      self?._syncSizeRestrictions()
    }
  }

  public required init?(coder: NSCoder) {
    self.screen = UIScreen.main
    super.init(coder: coder)
  }

  internal func _registerWindow(_ win: UIWindow) {
    sceneWindows.removeAll { $0.window == nil || $0.window === win }
    sceneWindows.append(WeakUIWindow(window: win))
    _syncSceneTitle()
    _syncSizeRestrictions()
  }

  internal func _unregisterWindow(_ win: UIWindow) {
    sceneWindows.removeAll { $0.window == nil || $0.window === win }
  }

  internal func _syncSceneTitle() {
    guard let t = title, !t.isEmpty else { return }
    #if !os(macOS)
      for w in windows {
        w.nativeWindow?.setTitle(t)
      }
    #endif
  }

  private func _syncSizeRestrictions() {
    #if !os(macOS)
      guard let sr = sizeRestrictions else { return }
      for w in windows {
        w.nativeWindow?.setMinimumSize(NativeAPI.Size(width: Double(sr.minimumSize.width), height: Double(sr.minimumSize.height)))
        w.nativeWindow?.setMaximumSize(NativeAPI.Size(width: Double(sr.maximumSize.width), height: Double(sr.maximumSize.height)))
      }
    #endif
  }
}

// MARK: - UIWindow

@MainActor
open class UIWindow: UIView {
  public struct Level: RawRepresentable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: CGFloat
    public init(_ rawValue: CGFloat) { self.rawValue = rawValue }
    public init(rawValue: CGFloat) { self.rawValue = rawValue }
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let normal = Level(rawValue: 0)
    public static let alert = Level(rawValue: 2000)
    public static let statusBar = Level(rawValue: 1000)
  }

  public static let didBecomeVisibleNotification = Notification.Name("UIWindowDidBecomeVisibleNotification")
  public static let didBecomeHiddenNotification = Notification.Name("UIWindowDidBecomeHiddenNotification")
  public static let didBecomeKeyNotification = Notification.Name("UIWindowDidBecomeKeyNotification")
  public static let didResignKeyNotification = Notification.Name("UIWindowDidResignKeyNotification")
  public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
  public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
  public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
  public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
  public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
  public static let keyboardDidChangeFrameNotification = Notification.Name("UIKeyboardDidChangeFrameNotification")

  public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
  public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
  public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
  public static let keyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"

  public var windowScene: UIWindowScene? {
    didSet {
      oldValue?._unregisterWindow(self)
      windowScene?._registerWindow(self)
    }
  }

  public var screen: UIScreen {
    windowScene?.screen ?? .main
  }

  public var windowLevel: Level = .normal {
    didSet {
      #if !os(macOS)
        nativeWindow?.setAlwaysOnTop(windowLevel > .normal)
      #endif
    }
  }

  public private(set) var isKeyWindow: Bool = false
  public var canResizeToFitContent: Bool = true

  /// Invoked when `rootViewController` or content size changes so `UIHostingController` attaches cleanly.
  public var onRootContentChanged: ((UIViewController?) -> Void)?

  public var rootViewController: UIViewController? {
    didSet {
      if let old = oldValue, old !== rootViewController {
        old.viewWillDisappear(false)
        old.viewIfLoaded?.removeFromSuperview()
        old.viewDidDisappear(false)
      }
      if let vc = rootViewController {
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
        vc.view.frame = bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(vc.view)
        vc.view.layoutIfNeeded()
        vc.viewDidAppear(false)
        #if !os(macOS)
          if let t = vc.title ?? vc.navigationItem.title, !t.isEmpty,
             (windowScene?.title ?? "").isEmpty
          {
            nativeWindow?.setTitle(t)
          }
        #endif
      }
      onRootContentChanged?(rootViewController)
    }
  }

  #if !os(macOS)
    nonisolated(unsafe) public private(set) var nativeWindow: NativeAPI.Window?
    nonisolated(unsafe) private var nativeListenerId: ListenerId?
    private var isApplyingNativeResize = false
  #endif

  open override var frame: CGRect {
    didSet {
      #if !os(macOS)
        guard !isApplyingNativeResize, frame.size != oldValue.size, frame.width > 0, frame.height > 0 else { return }
        nativeWindow?.setContentSize(NativeAPI.Size(width: Double(frame.width), height: Double(frame.height)))
      #endif
    }
  }

  public override init(frame: CGRect) {
    let resolvedFrame = (frame.width > 0 && frame.height > 0)
      ? frame
      : CGRect(x: 80, y: 80, width: 960, height: 680)
    super.init(frame: resolvedFrame)
    super.isHidden = true
    self.backgroundColor = .systemBackground
    createNativeWindowIfPossible(initialSize: resolvedFrame.size)
    UIApplication.shared._registerWindow(self)
  }

  public convenience init(windowScene: UIWindowScene) {
    self.init(frame: CGRect(x: 80, y: 80, width: 960, height: 680))
    self.windowScene = windowScene
    windowScene._registerWindow(self)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    super.isHidden = true
    UIApplication.shared._registerWindow(self)
  }

  deinit {
    #if !os(macOS)
      if let id = nativeListenerId {
        _ = nativeWindow?.removeListener(id)
      }
    #endif
  }

  private func createNativeWindowIfPossible(initialSize: CGSize) {
    #if !os(macOS)
      _ = NativeAPI.Application.shared.isRunning()
      guard let nw = NativeAPI.Window.create() else { return }
      self.nativeWindow = nw
      self.ownedNativeView = nw.contentView
      nw.contentView?.setLayout(.absolute)
      let defaultTitle = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "CrossUIKit"
      nw.setTitle(defaultTitle)
      nw.setContentSize(NativeAPI.Size(width: Double(initialSize.width), height: Double(initialSize.height)))
      syncWindowBackgroundToNative()
      nativeListenerId = nw.addListener { [weak self] event in
        MainActor.assumeIsolated {
          self?.handleNativeWindowEvent(event)
        }
      }
    #endif
  }

  internal func syncWindowBackgroundToNative() {
    #if !os(macOS)
      guard let nw = nativeWindow else { return }
      let c = (backgroundColor ?? .systemBackground).resolved(for: traitCollection)
      nw.setBackgroundColor(NativeAPI.Color(
        r: UInt8(clamping: Int((c.r * 255).rounded())),
        g: UInt8(clamping: Int((c.g * 255).rounded())),
        b: UInt8(clamping: Int((c.b * 255).rounded())),
        a: UInt8(clamping: Int((c.a * 255).rounded()))
      ))
    #endif
  }

  open override var backgroundColor: UIColor? {
    didSet { syncWindowBackgroundToNative() }
  }

  open override var isHidden: Bool {
    didSet {
      guard isHidden != oldValue else { return }
      #if !os(macOS)
        if isHidden {
          nativeWindow?.hide()
        } else {
          nativeWindow?.show()
        }
      #endif
      NotificationCenter.default.post(
        name: isHidden ? Self.didBecomeHiddenNotification : Self.didBecomeVisibleNotification,
        object: self
      )
    }
  }

  open func makeKey() {
    for other in UIApplication.shared.windows where other !== self && other.isKeyWindow {
      other.resignKey()
    }
    if !isKeyWindow {
      isKeyWindow = true
      becomeKey()
    }
    #if !os(macOS)
      nativeWindow?.focus()
    #endif
  }

  open func makeKeyAndVisible() {
    isHidden = false
    #if !os(macOS)
      if let nw = nativeWindow {
        nw.show()
        let cs = nw.contentSize
        if cs.width > 0 && cs.height > 0 {
          isApplyingNativeResize = true
          bounds.size = CGSize(width: CGFloat(cs.width), height: CGFloat(cs.height))
          isApplyingNativeResize = false
          rootViewController?.viewIfLoaded?.frame = bounds
          layoutIfNeeded()
        }
      }
    #endif
    makeKey()
  }

  open func becomeKey() {
    NotificationCenter.default.post(name: Self.didBecomeKeyNotification, object: self)
  }

  open func resignKey() {
    isKeyWindow = false
    NotificationCenter.default.post(name: Self.didResignKeyNotification, object: self)
  }

  open func sendEvent(_ event: UIEvent) {
    guard let touches = event.allTouches else { return }
    for touch in touches {
      let pt = touch.location(in: self)
      let target = touch.view ?? hitTest(pt, with: event)
      touch.view = target
      if touch.phase == .ended, let view = target {
        var cur: UIView? = view
        while let v = cur {
          for gr in v.gestureRecognizers ?? [] where gr is UITapGestureRecognizer {
            gr._fireRecognized(at: pt, state: .ended)
          }
          cur = v.superview
        }
      }
      switch touch.phase {
      case .began: target?.touchesBegan([touch], with: event)
      case .moved: target?.touchesMoved([touch], with: event)
      case .ended: target?.touchesEnded([touch], with: event)
      case .cancelled: target?.touchesCancelled([touch], with: event)
      default: break
      }
    }
  }

  #if !os(macOS)
    private func handleNativeWindowEvent(_ event: NativeAPI.WindowEvent) {
      switch event {
      case .focused:
        if !isKeyWindow {
          isKeyWindow = true
          becomeKey()
        }
      case .blurred:
        if isKeyWindow {
          resignKey()
        }
      case .resized(_, let newSize):
        let sz = CGSize(width: CGFloat(max(1, newSize.width)), height: CGFloat(max(1, newSize.height)))
        if abs(bounds.width - sz.width) > 0.5 || abs(bounds.height - sz.height) > 0.5 {
          isApplyingNativeResize = true
          bounds.size = sz
          isApplyingNativeResize = false
          rootViewController?.viewIfLoaded?.frame = bounds
          layoutIfNeeded()
        }
      default:
        break
      }
    }
  #endif
}

// MARK: - UIApplication & UIApplicationDelegate

@MainActor
public protocol UIApplicationDelegate: NSObjectProtocol {
  init()
  var window: UIWindow? { get set }
  func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool
  func applicationDidBecomeActive(_ application: UIApplication)
  func applicationWillResignActive(_ application: UIApplication)
  func applicationDidEnterBackground(_ application: UIApplication)
  func applicationWillEnterForeground(_ application: UIApplication)
  func applicationWillTerminate(_ application: UIApplication)
  func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration
  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
}

extension UIApplicationDelegate {
  public var window: UIWindow? {
    get { nil }
    set {}
  }

  public func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool { true }

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool { true }

  public func applicationDidBecomeActive(_ application: UIApplication) {}
  public func applicationWillResignActive(_ application: UIApplication) {}
  public func applicationDidEnterBackground(_ application: UIApplication) {}
  public func applicationWillEnterForeground(_ application: UIApplication) {}
  public func applicationWillTerminate(_ application: UIApplication) {}

  public func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any]
  ) -> Bool { false }

  public func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    connectingSceneSession.configuration
  }

  public func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

  /// Supports `@main class AppDelegate: UIResponder, UIApplicationDelegate` directly on Windows and Linux.
  public static func main() {
    UIApplication._runMainLoop(delegateType: Self.self)
  }
}

@MainActor
open class UIApplication: UIResponder, @unchecked Sendable {
  public enum State: Int, Sendable {
    case active = 0
    case inactive = 1
    case background = 2
  }

  public struct LaunchOptionsKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
    public static let sourceApplication = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsSourceApplicationKey")
    public static let userActivityDictionary = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsUserActivityDictionaryKey")
  }

  public struct OpenURLOptionsKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sourceApplication = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsSourceApplicationKey")
    public static let openInPlace = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsOpenInPlaceKey")
  }

  public struct OpenExternalURLOptionsKey: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let universalLinksOnly = OpenExternalURLOptionsKey(rawValue: "UIApplicationOpenURLOptionUniversalLinksOnly")
  }

  public static let didFinishLaunchingNotification = Notification.Name("UIApplicationDidFinishLaunchingNotification")
  public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
  public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
  public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
  public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
  public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
  public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")
  public static let significantTimeChangeNotification = Notification.Name("UIApplicationSignificantTimeChangeNotification")
  public static let userDidTakeScreenshotNotification = Notification.Name("UIApplicationUserDidTakeScreenshotNotification")
  public static let contentSizeCategoryDidChangeNotification = Notification.Name("UIContentSizeCategoryDidChangeNotification")

  public static let openSettingsURLString = "app-settings:"
  public static let openNotificationSettingsURLString = "app-notification-settings:"

  public static let shared = UIApplication()

  /// Optional bootstrap hook installed by `CrossSwiftUI` so pure UIKit `@main` apps also wire SF Symbols & assets.
  nonisolated(unsafe) public static var _hostBootstrapHook: (@MainActor () -> Void)?

  public weak var delegate: (any UIApplicationDelegate)?
  private var retainedDelegate: (any UIApplicationDelegate)?
  public private(set) var applicationState: State = .active
  public var isIdleTimerDisabled: Bool = false
  public var applicationIconBadgeNumber: Int = 0
  public var supportsMultipleScenes: Bool = false
  public var preferredContentSizeCategory: UIContentSizeCategory = .large

  private struct WeakWindow {
    weak var window: UIWindow?
  }
  private var trackedWindows: [WeakWindow] = []
  public private(set) var connectedScenes: Set<UIScene> = []
  public private(set) var openSessions: Set<UISceneSession> = []
  private var nextBackgroundTaskID: Int = 1

  public var windows: [UIWindow] {
    trackedWindows.compactMap(\.window)
  }

  public var keyWindow: UIWindow? {
    windows.first { $0.isKeyWindow && !$0.isHidden } ?? windows.first { !$0.isHidden }
  }

  private override init() {
    #if os(Windows)
      cak_enable_per_monitor_dpi()
    #endif
    super.init()
  }

  public override init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  internal func _registerWindow(_ window: UIWindow) {
    trackedWindows.removeAll { $0.window == nil || $0.window === window }
    trackedWindows.append(WeakWindow(window: window))
  }

  public func _installRetainedDelegate(_ delegate: any UIApplicationDelegate) {
    self.retainedDelegate = delegate
    self.delegate = delegate
  }

  public func canOpenURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme else { return false }
    return !scheme.isEmpty
  }

  public func open(
    _ url: URL,
    options: [OpenExternalURLOptionsKey: Any] = [:],
    completionHandler completion: (@MainActor @Sendable (Bool) -> Void)? = nil
  ) {
    let ok = CrossAppKit.NSWorkspace.shared.open(url)
    completion?(ok)
  }

  @discardableResult
  public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:]) async -> Bool {
    CrossAppKit.NSWorkspace.shared.open(url)
  }

  @discardableResult
  public func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
    if let explicitTarget = target as? any _UIActionInvoking {
      return explicitTarget._invokeAction(action, sender: sender)
    }
    #if canImport(ObjectiveC)
      if let objTarget = target as? NSObject, objTarget.responds(to: action) {
        _ = objTarget.perform(action, with: sender)
        return true
      }
    #endif
    var responder: UIResponder? = (target as? UIResponder) ?? (sender as? UIResponder) ?? keyWindow?.rootViewController
    while let r = responder {
      if let invokable = r as? any _UIActionInvoking, invokable._invokeAction(action, sender: sender) {
        return true
      }
      #if canImport(ObjectiveC)
        if r.responds(to: action) {
          _ = r.perform(action, with: sender)
          return true
        }
      #endif
      responder = r.next
    }
    return false
  }

  public func sendEvent(_ event: UIEvent) {
    keyWindow?.sendEvent(event)
  }

  public func beginBackgroundTask(
    withName taskName: String? = nil,
    expirationHandler handler: (() -> Void)? = nil
  ) -> UIBackgroundTaskIdentifier {
    defer { nextBackgroundTaskID += 1 }
    return UIBackgroundTaskIdentifier(rawValue: nextBackgroundTaskID)
  }

  public func beginBackgroundTask(expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
    beginBackgroundTask(withName: nil, expirationHandler: handler)
  }

  public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
  public func registerForRemoteNotifications() {}
  public func unregisterForRemoteNotifications() {}

  public func requestSceneSessionActivation(
    _ sceneSession: UISceneSession?,
    userActivity: NSUserActivity?,
    options: UIScene.ActivationRequestOptions?,
    errorHandler: ((any Error) -> Void)? = nil
  ) {}

  public func requestSceneSessionDestruction(
    _ sceneSession: UISceneSession,
    options: Any?,
    errorHandler: ((any Error) -> Void)? = nil
  ) {}

  /// Called by `CrossSwiftUI.runApp` when `@UIApplicationDelegateAdaptor` is installed on a SwiftUI `App`.
  public func _notifyFinishLaunchingFromSwiftUI() {
    guard let delegate else { return }
    _ = delegate.application(self, willFinishLaunchingWithOptions: nil)
    _ = delegate.application(self, didFinishLaunchingWithOptions: nil)
    NotificationCenter.default.post(name: Self.didFinishLaunchingNotification, object: self)
    delegate.applicationDidBecomeActive(self)
    NotificationCenter.default.post(name: Self.didBecomeActiveNotification, object: self)
  }

  public func _notifyWillTerminate() {
    delegate?.applicationWillTerminate(self)
    NotificationCenter.default.post(name: Self.willTerminateNotification, object: self)
  }

  nonisolated private static func _parseLaunchOpenURLs<S: Sequence>(from rawArgs: S) -> [URL]
  where S.Element == String {
    var urls: [URL] = []
    for arg in rawArgs {
      guard !arg.hasPrefix("-") else { continue }
      if let u = URL(string: arg), let scheme = u.scheme, scheme.count > 1 {
        urls.append(u)
      }
    }
    return urls
  }

  internal static func _runMainLoop<D: UIApplicationDelegate>(delegateType: D.Type) {
    _hostBootstrapHook?()
    CrossAppKit.NSApplication.shared.ensureSingleInstance()

    let app = UIApplication.shared
    let delegate = delegateType.init()
    app._installRetainedDelegate(delegate)

    #if !os(macOS)
      _ = NativeAPI.Application.shared.isRunning()
      NativeAPI.Application.shared.installMainQueue()
    #endif

    let initialURLs = Self._parseLaunchOpenURLs(from: CommandLine.arguments.dropFirst())
    var launchOptions: [LaunchOptionsKey: Any] = [:]
    if let firstURL = initialURLs.first {
      launchOptions[.url] = firstURL
    }
    let optionsArg: [LaunchOptionsKey: Any]? = launchOptions.isEmpty ? nil : launchOptions

    _ = delegate.application(app, willFinishLaunchingWithOptions: optionsArg)
    _ = delegate.application(app, didFinishLaunchingWithOptions: optionsArg)
    NotificationCenter.default.post(name: Self.didFinishLaunchingNotification, object: app)

    let session = UISceneSession(role: .windowApplication)
    let urlContexts = Set(initialURLs.map { UIOpenURLContext(url: $0) })
    let connOptions = UIScene.ConnectionOptions(urlContexts: urlContexts)
    let sceneConfig = delegate.application(app, configurationForConnecting: session, options: connOptions)
    session.configuration = sceneConfig
    app.openSessions.insert(session)

    let windowScene = UIWindowScene(session: session, connectionOptions: connOptions)
    app.connectedScenes.insert(windowScene)

    if let sceneDelegateType = sceneConfig.delegateClass as? any UISceneDelegate.Type {
      let sceneDelegate = sceneDelegateType.init()
      windowScene._installRetainedDelegate(sceneDelegate)
      sceneDelegate.scene(windowScene, willConnectTo: session, options: connOptions)
      sceneDelegate.sceneWillEnterForeground(windowScene)
      sceneDelegate.sceneDidBecomeActive(windowScene)
    } else if let directWindow = delegate.window {
      directWindow.windowScene = windowScene
      if directWindow.isHidden {
        directWindow.makeKeyAndVisible()
      }
    }

    for u in initialURLs {
      _ = delegate.application(app, open: u, options: [:])
    }

    delegate.applicationDidBecomeActive(app)
    NotificationCenter.default.post(name: Self.didBecomeActiveNotification, object: app)

    #if !os(macOS)
      if CommandLine.arguments.contains("--smoke") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
          NativeAPI.Application.shared.quit(0)
        }
      }

      var syncTickCounter = 0
      let runLoopPump = NativeAPI.RunLoopTimer(milliseconds: 25) {
        _ = RunLoop.main.limitDate(forMode: .default)
        #if os(Windows)
          syncTickCounter += 1
          if syncTickCounter >= 40 {
            syncTickCounter = 0
            _ = UserDefaults.standard.synchronize()
          }
        #endif
      }

      if let primaryNativeWin = (windowScene.keyWindow ?? app.keyWindow ?? app.windows.first)?.nativeWindow {
        CrossAppKit.NSApplication.shared._primarySceneWindow = primaryNativeWin
        _ = NativeAPI.Application.shared.runWithWindow(primaryNativeWin)
      } else {
        _ = NativeAPI.Application.shared.run()
      }

      runLoopPump.invalidate()
      app._notifyWillTerminate()
      #if os(Windows)
        _ = UserDefaults.standard.synchronize()
        cak_single_instance_release()
      #endif
    #endif
  }
}

@MainActor
public func UIApplicationMain(
  _ argc: Int32,
  _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
  _ principalClassName: String?,
  _ delegateClassName: String?
) -> Int32 {
  if let delegateClassName,
     let cls = NSClassFromString(delegateClassName) as? any UIApplicationDelegate.Type
  {
    cls.main()
    return 0
  }
  #if !os(macOS)
    _ = NativeAPI.Application.shared.run()
  #endif
  return 0
}
