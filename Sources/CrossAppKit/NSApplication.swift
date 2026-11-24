import Foundation
#if !os(macOS)
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

@MainActor
public protocol NSApplicationDelegate: AnyObject {
  init()
  func applicationWillFinishLaunching(_ notification: Notification)
  func applicationDidFinishLaunching(_ notification: Notification)
  func applicationWillTerminate(_ notification: Notification)
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
  func application(_ application: NSApplication, open urls: [URL])
  func applicationDidBecomeActive(_ notification: Notification)
  func applicationDidResignActive(_ notification: Notification)
}

extension NSApplicationDelegate {
  public func applicationWillFinishLaunching(_ notification: Notification) {}
  public func applicationDidFinishLaunching(_ notification: Notification) {}
  public func applicationWillTerminate(_ notification: Notification) {}
  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
  public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  public func application(_ application: NSApplication, open urls: [URL]) {}
  public func applicationDidBecomeActive(_ notification: Notification) {}
  public func applicationDidResignActive(_ notification: Notification) {}
}

@MainActor
public var NSApp: NSApplication! {
  get { NSApplication.shared }
  set {}
}

@inline(__always)
internal func _performOnMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
  if Thread.isMainThread {
    MainActor.assumeIsolated(body)
  } else {
    DispatchQueue.main.async(execute: body)
  }
}

#if os(Windows)
  private let _singleInstanceCallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { rawPtr in
    let payload = rawPtr.map { String(cString: $0) } ?? ""
    _performOnMainActor {
      NSApplication.shared._receiveSingleInstancePayload(payload)
    }
  }
#endif

@MainActor
open class NSApplication: NSResponder, @unchecked Sendable {
  public enum ActivationPolicy: Int, Sendable {
    case regular = 0
    case accessory = 1
    case prohibited = 2
  }

  public enum TerminateReply: UInt, Sendable {
    case terminateCancel = 0
    case terminateNow = 1
    case terminateLater = 2
  }

  public typealias ModalResponse = NSModalResponse

  public static let willFinishLaunchingNotification = Notification.Name("NSApplicationWillFinishLaunchingNotification")
  public static let didFinishLaunchingNotification = Notification.Name("NSApplicationDidFinishLaunchingNotification")
  public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
  public static let didBecomeActiveNotification = Notification.Name("NSApplicationDidBecomeActiveNotification")
  public static let didResignActiveNotification = Notification.Name("NSApplicationDidResignActiveNotification")
  public static let didChangeScreenParametersNotification = Notification.Name("NSApplicationDidChangeScreenParametersNotification")

  public static let shared = NSApplication()

  public weak var delegate: (any NSApplicationDelegate)?
  private var currentActivationPolicy: ActivationPolicy = .regular
  public var mainMenu: NSMenu?
  public var applicationIconImage: NSImage = NSImage(size: NSSize(width: 64, height: 64))
  public private(set) var isActive: Bool = false
  public private(set) var isRunning: Bool = false
  public var currentEvent: NSEvent?
  public var modalWindow: NSWindow?

  public var appearance: NSAppearance? {
    didSet {
      NSAppearance._appAppearanceOverride = appearance
      #if !os(macOS)
        if let app = appearance {
          let dark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
          _ = NativeAPI.Application.shared.setBrightness(dark ? .dark : .light)
        } else {
          _ = NativeAPI.Application.shared.setBrightness(.system)
        }
      #endif
      notifyAppearanceObservers()
      for win in windows { win.contentView?.viewDidChangeEffectiveAppearance() }
    }
  }

  public var effectiveAppearance: NSAppearance {
    appearance ?? NSAppearance.systemAppearance
  }

  private struct WeakWindow {
    weak var window: NSWindow?
  }
  private var trackedWindows: [WeakWindow] = []
  private var appearanceObservers: [UUID: () -> Void] = [:]
  private var didEnsureSingleInstance = false
  private var didCompleteFinishLaunching = false
  private var pendingSingleInstancePayloads: [String] = []
  #if !os(macOS)
    public weak var _primarySceneWindow: NativeAPI.Window?
  #endif

  public var windows: [NSWindow] {
    trackedWindows.compactMap(\.window)
  }

  public var keyWindow: NSWindow? {
    windows.first { $0.isKeyWindow && $0.isVisible }
  }

  public var mainWindow: NSWindow? {
    windows.first { $0.isMainWindow && $0.isVisible } ?? keyWindow
  }

  private override init() {
    #if os(Windows)
      cak_enable_per_monitor_dpi()
      _cgPostToPidHook = { pid, sendAction in
        guard pid > 0 else { return false }
        MainActor.assumeIsolated {
          let activePanel = NSApplication.shared.keyWindow
          let keepPanelOpen = activePanel?.isVisible == true && activePanel?.styleMask.contains(.nonactivatingPanel) == true
          if keepPanelOpen {
            NSWindow._suppressResignKeyCount += 1
          }
          _ = cak_activate_pid(UInt32(bitPattern: pid))
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            sendAction()
            if keepPanelOpen {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                if let panel = activePanel, panel.isVisible {
                  panel.makeKeyAndOrderFront(nil)
                }
                NSWindow._suppressResignKeyCount = max(0, NSWindow._suppressResignKeyCount - 1)
              }
            }
          }
        }
        return true
      }
    #endif
    #if !os(macOS)
      CarbonHotKeyBridge.install()
    #endif
    super.init()
  }

  public override init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  internal func registerWindow(_ window: NSWindow) {
    trackedWindows.removeAll { $0.window == nil || $0.window === window }
    trackedWindows.append(WeakWindow(window: window))
  }

  internal func unregisterWindow(_ window: NSWindow) {
    trackedWindows.removeAll { $0.window == nil || $0.window === window }
  }

  #if !os(macOS)
    public func observeEffectiveAppearance(
      initial: Bool = true,
      _ changeHandler: @escaping () -> Void
    ) -> NSKeyValueObservation {
      let id = UUID()
      appearanceObservers[id] = changeHandler
      if initial { changeHandler() }
      return NSKeyValueObservation { [weak self] in
        self?.appearanceObservers.removeValue(forKey: id)
      }
    }

    public func observe<Value>(
      _ keyPath: KeyPath<NSApplication, Value>,
      options: NSKeyValueObservingOptions = [],
      changeHandler: @escaping @Sendable (NSApplication, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
      let fireInitial = options.contains(.initial)
      return observeEffectiveAppearance(initial: fireInitial) { [weak self] in
        guard let self else { return }
        changeHandler(self, NSKeyValueObservedChange<Value>())
      }
    }
  #endif

  private func notifyAppearanceObservers() {
    for handler in Array(appearanceObservers.values) {
      handler()
    }
  }

  @discardableResult
  public func setActivationPolicy(_ activationPolicy: ActivationPolicy) -> Bool {
    currentActivationPolicy = activationPolicy
    #if !os(macOS)
      _ = NativeAPI.Application.shared.setDockIconVisible(activationPolicy == .regular)
    #endif
    return true
  }

  public func activationPolicy() -> ActivationPolicy {
    currentActivationPolicy
  }

  public func activate(ignoringOtherApps flag: Bool = true) {
    isActive = true
    #if !os(macOS)
      _ = NativeAPI.Application.shared.show()
    #endif
    keyWindow?.makeKeyAndOrderFront(nil)
  }

  public func activate() {
    activate(ignoringOtherApps: true)
  }

  public func hide(_ sender: Any?) {
    isActive = false
    #if !os(macOS)
      _ = NativeAPI.Application.shared.hide()
    #endif
  }

  public func registerForRemoteNotifications() {}
  public func unregisterForRemoteNotifications() {}

  nonisolated public static var _systemPreferredLanguages: [String] {
    #if os(Windows)
      if let raw = cak_preferred_ui_languages_newline() {
        defer { cak_free(raw) }
        let list = String(cString: raw)
          .split(whereSeparator: \.isNewline)
          .map(String.init)
          .filter { !$0.isEmpty }
        if !list.isEmpty {
          return list
        }
      }
    #endif
    var languages = Locale.preferredLanguages
    if let envLang = ProcessInfo.processInfo.environment["CROSSSWIFT_PREFERRED_LANGUAGE"],
       !envLang.isEmpty,
       !languages.contains(envLang)
    {
      languages.insert(envLang, at: 0)
    }
    return languages
  }

  nonisolated internal static func _parseOpenURLs<S: Sequence>(from rawArgs: S) -> [URL]
  where S.Element == String {
    var urls: [URL] = []
    for raw in rawArgs {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { continue }
      if FileManager.default.fileExists(atPath: trimmed) {
        urls.append(URL(fileURLWithPath: trimmed))
        continue
      }
      if let colon = trimmed.firstIndex(of: ":") {
        let scheme = trimmed[..<colon]
        if scheme.count >= 2,
          let first = scheme.unicodeScalars.first,
          CharacterSet.letters.contains(first),
          scheme.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || $0 == "+" || $0 == "-" || $0 == "."
          }),
          let url = URL(string: trimmed)
        {
          urls.append(url)
        }
      }
    }
    return urls
  }

  public func ensureSingleInstance() {
    guard !didEnsureSingleInstance else { return }
    didEnsureSingleInstance = true
    #if os(Windows)
      let args = CommandLine.arguments
      if args.contains("--new-instance") || args.contains("--smoke")
        || args.contains(where: { $0.hasPrefix("--role=") })
      {
        return
      }
      if ProcessInfo.processInfo.environment["CROSS_ALLOW_MULTIPLE_INSTANCES"] == "1" { return }
      if let prohibited = Bundle.main.object(forInfoDictionaryKey: "LSMultipleInstancesProhibited") as? Bool,
        !prohibited
      {
        return
      }

      let forwardArgs = args.dropFirst().filter { !$0.hasPrefix("-") }
      let payload = forwardArgs.joined(separator: "\n")
      let isBackground = args.contains("--background")
      let notifyPrimary: Int32 = (!isBackground || !forwardArgs.isEmpty) ? 1 : 0
      let waitMs: Int32 = args.contains("--relaunch") ? 5000 : 0
      let appID = Bundle.main.bundleIdentifier ?? ""

      let acquired = cak_single_instance_acquire(
        appID,
        payload,
        notifyPrimary,
        waitMs,
        _singleInstanceCallback
      )
      if acquired == 0 {
        exit(0)
      }
    #endif
  }

  internal func _receiveSingleInstancePayload(_ payload: String) {
    if !didCompleteFinishLaunching {
      pendingSingleInstancePayloads.append(payload)
      return
    }
    _deliverSingleInstancePayload(payload)
  }

  private func _deliverSingleInstancePayload(_ payload: String) {
    let parts = payload.split(whereSeparator: \.isNewline).map(String.init)
    let urls = Self._parseOpenURLs(from: parts)
    if !urls.isEmpty {
      if let delegate {
        delegate.application(self, open: urls)
      } else {
        #if !os(macOS)
          if let win = _primarySceneWindow {
            if win.isMinimized { win.restore() }
            win.show()
            win.focus()
          }
        #endif
      }
      return
    }

    #if !os(macOS)
      let primaryVisible = _primarySceneWindow?.isVisible == true
    #else
      let primaryVisible = false
    #endif
    let hadVisible = windows.contains { $0.isVisible } || primaryVisible
    let shouldPerformNormalReopen =
      delegate?.applicationShouldHandleReopen(self, hasVisibleWindows: hadVisible) ?? true
    if shouldPerformNormalReopen {
      #if !os(macOS)
        let primaryVisibleNow = _primarySceneWindow?.isVisible == true
      #else
        let primaryVisibleNow = false
      #endif
      let hasVisibleNow = windows.contains { $0.isVisible } || primaryVisibleNow
      if !hasVisibleNow {
        #if !os(macOS)
          if let win = _primarySceneWindow {
            if win.isMinimized { win.restore() }
            win.show()
            win.focus()
            return
          }
        #endif
        if let win = mainWindow ?? windows.first {
          if win.isMiniaturized { win.deminiaturize(nil) }
          win.makeKeyAndOrderFront(nil)
        }
      } else if let win = keyWindow ?? mainWindow {
        win.makeKeyAndOrderFront(nil)
      } else {
        #if !os(macOS)
          if let win = _primarySceneWindow, win.isVisible {
            if win.isMinimized { win.restore() }
            win.focus()
          }
        #endif
      }
    }
  }

  public func finishLaunching() {
    let willNote = Notification(name: Self.willFinishLaunchingNotification, object: self)
    NotificationCenter.default.post(willNote)
    delegate?.applicationWillFinishLaunching(willNote)

    let didNote = Notification(name: Self.didFinishLaunchingNotification, object: self)
    NotificationCenter.default.post(didNote)
    delegate?.applicationDidFinishLaunching(didNote)

    #if !os(macOS)
      let initialURLs = Self._parseOpenURLs(from: CommandLine.arguments.dropFirst())
      if !initialURLs.isEmpty {
        delegate?.application(self, open: initialURLs)
      }
    #endif

    didCompleteFinishLaunching = true
    if !pendingSingleInstancePayloads.isEmpty {
      let queued = pendingSingleInstancePayloads
      pendingSingleInstancePayloads.removeAll()
      for payload in queued {
        _deliverSingleInstancePayload(payload)
      }
    }
  }

  public func run() {
    ensureSingleInstance()
    guard !isRunning else { return }
    isRunning = true
    #if !os(macOS)
      NativeAPI.Application.shared.installMainQueue()
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
    #endif
    finishLaunching()
    #if !os(macOS)
      _ = NativeAPI.Application.shared.run()
      runLoopPump.invalidate()
      #if os(Windows)
        _ = UserDefaults.standard.synchronize()
      #endif
    #endif
    isRunning = false
  }

  public func terminate(_ sender: Any?) {
    if let reply = delegate?.applicationShouldTerminate(self) {
      switch reply {
      case .terminateCancel:
        return
      case .terminateLater:
        return
      case .terminateNow:
        break
      }
    }
    performFinalTermination()
  }

  public func reply(toApplicationShouldTerminate shouldTerminate: Bool) {
    guard shouldTerminate else { return }
    performFinalTermination()
  }

  private func performFinalTermination() {
    for win in windows where win.isVisible {
      win.orderOut(nil)
    }
    NSStatusBar.system._removeAllItemsForTermination()
    #if os(Windows)
      _ = UserDefaults.standard.synchronize()
    #endif
    let termNote = Notification(name: Self.willTerminateNotification, object: self)
    NotificationCenter.default.post(termNote)
    delegate?.applicationWillTerminate(termNote)
    #if os(Windows)
      _ = UserDefaults.standard.synchronize()
      cak_single_instance_release()
    #endif
    #if !os(macOS)
      NativeAPI.Application.shared.quit(0)
    #endif
  }
}

// Apple Event minimal shims used by AppDelegate launch-cause checks
public let kCoreEventClass: UInt32 = 0x61657674
public let kAEOpenApplication: UInt32 = 0x6F617070
public let kAEQuitApplication: UInt32 = 0x71756974
public let keySenderPIDAttr: UInt32 = 0x73706964
public let keyAEPropData: UInt32 = 0x70726474
public let keyAELaunchedAsLogInItem: UInt32 = 0x6C636E74

open class NSAppleEventDescriptor: NSObject {
  public var eventClass: UInt32 = 0
  public var eventID: UInt32 = 0
  public var int32Value: Int32 = 0
  public var booleanValue: Bool = false
  public var enumCodeValue: UInt32 = 0
  public var stringValue: String?
  public func attributeDescriptor(forKeyword keyword: UInt32) -> NSAppleEventDescriptor? { nil }
  public func paramDescriptor(forKeyword keyword: UInt32) -> NSAppleEventDescriptor? { nil }
}

open class NSAppleEventManager: NSObject, @unchecked Sendable {
  private static let sharedInstance = NSAppleEventManager()
  public static func shared() -> NSAppleEventManager { sharedInstance }
  public var currentAppleEvent: NSAppleEventDescriptor? {
    #if !os(macOS)
      if CommandLine.arguments.contains("--background") { return nil }
      if !NSApplication._parseOpenURLs(from: CommandLine.arguments.dropFirst()).isEmpty {
        return nil
      }
      let desc = NSAppleEventDescriptor()
      desc.eventClass = kCoreEventClass
      desc.eventID = kAEOpenApplication
      return desc
    #else
      return nil
    #endif
  }
}

open class NSAppleScript: NSObject {
  public static let errorMessage = "NSAppleScriptErrorMessage"
  public static let errorNumber = "NSAppleScriptErrorNumber"
  public let source: String?

  public init?(source: String) {
    self.source = source
    super.init()
  }

  @discardableResult
  public func executeAndReturnError(_ errorInfo: UnsafeMutablePointer<NSDictionary?>?) -> NSAppleEventDescriptor {
    let desc = NSAppleEventDescriptor()
    let script = source ?? ""
    #if os(Windows)
      if script.contains("count items of trash") {
        errorInfo?.pointee = nil
        desc.int32Value = 1
        return desc
      }
      if script.contains("empty trash") {
        _ = cak_empty_recycle_bin()
        errorInfo?.pointee = nil
        return desc
      }
    #endif
    errorInfo?.pointee = nil
    return desc
  }
}

#if !os(macOS)
  public struct AutoreleasingUnsafeMutablePointer<Pointee> {
    public var pointee: Pointee
    public init(_ pointee: Pointee) { self.pointee = pointee }
  }
#endif
