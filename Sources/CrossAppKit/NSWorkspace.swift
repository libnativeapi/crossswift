import Foundation
#if !os(macOS)
  import NativeAPI
  import UniformTypeIdentifiers
#endif
#if os(Windows)
  import CAppKitWindows
#elseif os(Linux)
  import Glibc
#endif

open class NSRunningApplication: NSObject, @unchecked Sendable {
  public struct ActivationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let activateAllWindows = ActivationOptions(rawValue: 1 << 0)
    public static let activateIgnoringOtherApps = ActivationOptions(rawValue: 1 << 1)
  }

  public let processIdentifier: Int32
  public let bundleIdentifier: String?
  public let bundleURL: URL?
  public let executableURL: URL?
  public let localizedName: String?
  public private(set) var isTerminated: Bool = false
  public private(set) var isHidden: Bool = false
  public var isActive: Bool {
    #if os(Windows)
      return Int32(cak_frontmost_pid()) == processIdentifier
    #else
      return false
    #endif
  }
  public var activationPolicy: NSApplication.ActivationPolicy { .regular }

  public var icon: NSImage? {
    guard let path = executableURL?.path ?? bundleURL?.path else { return nil }
    return NSWorkspace.shared.icon(forFile: path)
  }

  public init(
    processIdentifier: Int32,
    bundleIdentifier: String?,
    bundleURL: URL?,
    executableURL: URL?,
    localizedName: String?
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.bundleURL = bundleURL
    self.executableURL = executableURL
    self.localizedName = localizedName
    super.init()
  }

  public convenience init?(processIdentifier pid: Int32) {
    guard pid > 0 else { return nil }
    #if os(Windows)
      var exeBuf = [CChar](repeating: 0, count: 1024)
      var titleBuf = [CChar](repeating: 0, count: 512)
      guard cak_process_info(UInt32(pid), &exeBuf, 1024, &titleBuf, 512) != 0 else { return nil }
      let exePath = String(cString: exeBuf)
      guard !exePath.isEmpty else { return nil }
      let url = URL(fileURLWithPath: exePath)
      let stem = url.deletingPathExtension().lastPathComponent
      let winTitle = String(cString: titleBuf)
      let id = exePath.lowercased()
      self.init(
        processIdentifier: pid,
        bundleIdentifier: id,
        bundleURL: url,
        executableURL: url,
        localizedName: stem.isEmpty ? (winTitle.isEmpty ? "Application" : winTitle) : stem
      )
    #elseif os(Linux)
      let exeLink = "/proc/\(pid)/exe"
      var buf = [CChar](repeating: 0, count: 1024)
      let len = readlink(exeLink, &buf, buf.count - 1)
      let exePath: String? = len > 0 ? String(cString: buf) : nil
      let comm = (try? String(contentsOfFile: "/proc/\(pid)/comm", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard exePath != nil || (comm != nil && !comm!.isEmpty) else { return nil }
      let exeURL = exePath.map { URL(fileURLWithPath: $0) }
      let name = comm ?? exeURL?.lastPathComponent ?? "Process \(pid)"
      self.init(
        processIdentifier: pid,
        bundleIdentifier: exePath?.lowercased() ?? "pid.\(pid)",
        bundleURL: exeURL,
        executableURL: exeURL,
        localizedName: name
      )
    #else
      self.init(
        processIdentifier: pid,
        bundleIdentifier: "pid.\(pid)",
        bundleURL: nil,
        executableURL: nil,
        localizedName: "Process \(pid)"
      )
    #endif
  }

  public static var current: NSRunningApplication {
    #if os(Windows)
      let winPID = Int32(cak_current_pid())
      if let app = NSRunningApplication(processIdentifier: winPID) { return app }
    #endif
    let fallbackPID = ProcessInfo.processInfo.processIdentifier
    let executableStem = Bundle.main.executableURL?.deletingPathExtension().lastPathComponent
    let processName = ProcessInfo.processInfo.processName
    let resolvedName = (Bundle.main.infoDictionary?["CFBundleName"] as? String)
      ?? executableStem
      ?? (processName.isEmpty ? "CrossSwiftApp" : processName)
    let fallbackBundleID = "dev.crossswift.\(resolvedName.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })"
    return NSRunningApplication(
      processIdentifier: fallbackPID,
      bundleIdentifier: Bundle.main.bundleIdentifier ?? fallbackBundleID,
      bundleURL: Bundle.main.bundleURL,
      executableURL: Bundle.main.executableURL,
      localizedName: resolvedName
    )
  }

  public static func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [NSRunningApplication] {
    let target = bundleIdentifier.lowercased()
    return NSWorkspace.shared.runningApplications.filter {
      $0.bundleIdentifier?.lowercased() == target
    }
  }

  @discardableResult
  public func activate(options: ActivationOptions = []) -> Bool {
    #if os(Windows)
      return cak_activate_pid(UInt32(processIdentifier)) != 0
    #else
      return true
    #endif
  }

  @discardableResult
  public func activate(from application: NSRunningApplication, options: ActivationOptions = []) -> Bool {
    activate(options: options)
  }

  @discardableResult
  public func hide() -> Bool {
    isHidden = true
    #if os(Windows)
      return cak_hide_pid(UInt32(processIdentifier)) != 0
    #else
      return true
    #endif
  }

  @discardableResult
  public func unhide() -> Bool {
    isHidden = false
    return activate()
  }

  @discardableResult
  public func terminate() -> Bool {
    #if os(Windows)
      let ok = cak_terminate_pid(UInt32(processIdentifier), 0) != 0
      if ok { isTerminated = true }
      return ok
    #elseif os(Linux)
      let ok = kill(pid_t(processIdentifier), SIGTERM) == 0
      if ok { isTerminated = true }
      return ok
    #else
      return false
    #endif
  }

  @discardableResult
  public func forceTerminate() -> Bool {
    #if os(Windows)
      let ok = cak_terminate_pid(UInt32(processIdentifier), 1) != 0
      if ok { isTerminated = true }
      return ok
    #elseif os(Linux)
      let ok = kill(pid_t(processIdentifier), SIGKILL) == 0
      if ok { isTerminated = true }
      return ok
    #else
      return false
    #endif
  }
}

open class NSWorkspace: NSObject, @unchecked Sendable {
  open class OpenConfiguration: NSObject, @unchecked Sendable {
    public var activates: Bool = true
    public var addsToRecentItems: Bool = true
    public var createsNewApplicationInstance: Bool = false
    public var allowsRunningApplicationSubstitution: Bool = true
    public var arguments: [String] = []
    public var environment: [String: String] = [:]
    public override init() { super.init() }
  }

  public static let didLaunchApplicationNotification = Notification.Name("NSWorkspaceDidLaunchApplicationNotification")
  public static let didTerminateApplicationNotification = Notification.Name("NSWorkspaceDidTerminateApplicationNotification")
  public static let didActivateApplicationNotification = Notification.Name("NSWorkspaceDidActivateApplicationNotification")
  public static let didDeactivateApplicationNotification = Notification.Name("NSWorkspaceDidDeactivateApplicationNotification")
  public static let didWakeNotification = Notification.Name("NSWorkspaceDidWakeNotification")
  public static let willSleepNotification = Notification.Name("NSWorkspaceWillSleepNotification")
  public static let activeSpaceDidChangeNotification = Notification.Name("NSWorkspaceActiveSpaceDidChangeNotification")
  public static let sessionDidResignActiveNotification = Notification.Name("NSWorkspaceSessionDidResignActiveNotification")
  public static let sessionDidBecomeActiveNotification = Notification.Name("NSWorkspaceSessionDidBecomeActiveNotification")
  public static let applicationUserInfoKey = "NSWorkspaceApplicationKey"

  public static let shared = NSWorkspace()

  public let notificationCenter = NotificationCenter()

  public var accessibilityDisplayShouldReduceMotion: Bool { false }
  public var isVoiceOverEnabled: Bool { false }

  public var frontmostApplication: NSRunningApplication? {
    #if os(Windows)
      let pid = Int32(cak_frontmost_real_pid())
      guard pid > 0 else { return nil }
      return NSRunningApplication(processIdentifier: pid)
    #else
      return nil
    #endif
  }

  public var menuBarOwningApplication: NSRunningApplication? {
    frontmostApplication
  }

  public var runningApplications: [NSRunningApplication] {
    #if os(Windows)
      var count: Int32 = 0
      guard let raw = cak_enum_gui_pids(&count), count > 0 else { return [] }
      defer { cak_free(raw) }
      var result: [NSRunningApplication] = []
      result.reserveCapacity(Int(count))
      for i in 0..<Int(count) {
        let pid = Int32(raw[i])
        if let app = NSRunningApplication(processIdentifier: pid) {
          result.append(app)
        }
      }
      return result
    #elseif os(Linux)
      guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else {
        return [NSRunningApplication.current]
      }
      var result: [NSRunningApplication] = []
      for name in entries {
        guard let pid = Int32(name), pid > 0 else { continue }
        if let app = NSRunningApplication(processIdentifier: pid) {
          result.append(app)
        }
      }
      return result
    #else
      return []
    #endif
  }

  @discardableResult
  public func open(_ url: URL) -> Bool {
    #if os(Windows)
      let target = url.isFileURL ? url.path : url.absoluteString
      return cak_open_url_or_path(target) != 0
    #elseif !os(macOS)
      return NativeAPI.UrlOpener.shared.open(url.absoluteString).success
    #else
      return false
    #endif
  }

  public func open(
    _ urls: [URL],
    withApplicationAt applicationURL: URL,
    configuration: OpenConfiguration,
    completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)? = nil
  ) {
    #if os(Windows)
      let appPath = applicationURL.path
      if urls.isEmpty {
        let ok = cak_open_url_or_path(appPath) != 0
        completionHandler?(ok ? frontmostApplication : nil, nil)
      } else {
        var ok = true
        for u in urls {
          let arg = u.isFileURL ? u.path : u.absoluteString
          if cak_open_with_app(appPath, arg) == 0 { ok = false }
        }
        completionHandler?(ok ? frontmostApplication : nil, nil)
      }
    #elseif os(Linux)
      let proc = Process()
      proc.executableURL = applicationURL
      proc.arguments = configuration.arguments + urls.map { $0.isFileURL ? $0.path : $0.absoluteString }
      do {
        try proc.run()
        completionHandler?(NSRunningApplication(processIdentifier: proc.processIdentifier), nil)
      } catch {
        completionHandler?(nil, error)
      }
    #else
      completionHandler?(nil, nil)
    #endif
  }

  public func open(
    _ url: URL,
    configuration: OpenConfiguration,
    completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)? = nil
  ) {
    let ok = open(url)
    completionHandler?(ok ? frontmostApplication : nil, ok ? nil : NSError(domain: "CrossAppKit", code: 1))
  }

  @discardableResult
  public func open(_ url: URL, configuration: OpenConfiguration) async throws -> NSRunningApplication {
    guard open(url) else {
      throw NSError(domain: "CrossAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open URL"])
    }
    return frontmostApplication ?? NSRunningApplication.current
  }

  @discardableResult
  public func open(
    _ urls: [URL],
    withApplicationAt applicationURL: URL,
    configuration: OpenConfiguration
  ) async throws -> NSRunningApplication {
    #if os(Windows)
      let appPath = applicationURL.path
      if urls.isEmpty {
        guard cak_open_url_or_path(appPath) != 0 else {
          throw NSError(domain: "CrossAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to launch application"])
        }
      } else {
        for u in urls {
          let arg = u.isFileURL ? u.path : u.absoluteString
          guard cak_open_with_app(appPath, arg) != 0 else {
            throw NSError(domain: "CrossAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open URL with application"])
          }
        }
      }
      return frontmostApplication ?? NSRunningApplication.current
    #else
      return NSRunningApplication.current
    #endif
  }

  public func openApplication(
    at applicationURL: URL,
    configuration: OpenConfiguration,
    completionHandler: ((NSRunningApplication?, (any Error)?) -> Void)? = nil
  ) {
    let ok = open(applicationURL)
    completionHandler?(ok ? frontmostApplication : nil, ok ? nil : NSError(domain: "CrossAppKit", code: 1))
  }

  @discardableResult
  public func openApplication(
    at applicationURL: URL,
    configuration: OpenConfiguration
  ) async throws -> NSRunningApplication {
    guard open(applicationURL) else {
      throw NSError(domain: "CrossAppKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open application"])
    }
    return frontmostApplication ?? NSRunningApplication.current
  }

  public func activateFileViewerSelecting(_ fileURLs: [URL]) {
    guard let first = fileURLs.first else { return }
    #if os(Windows)
      _ = cak_reveal_in_explorer(first.path)
    #elseif os(Linux)
      _ = selectFile(first.path, inFileViewerRootedAtPath: "")
    #endif
  }

  public func selectFile(_ fullPath: String?, inFileViewerRootedAtPath rootFullPath: String) -> Bool {
    guard let fullPath else { return false }
    #if os(Windows)
      return cak_reveal_in_explorer(fullPath) != 0
    #elseif os(Linux)
      let targetURL = URL(fileURLWithPath: fullPath)
      let parentDir = targetURL.deletingLastPathComponent()
      return open(parentDir)
    #else
      return false
    #endif
  }

  public func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
    if FileManager.default.fileExists(atPath: bundleIdentifier) {
      return URL(fileURLWithPath: bundleIdentifier)
    }
    return nil
  }

  public func urlForApplication(toOpen url: URL) -> URL? {
    nil
  }

  public func urlsForApplications(toOpen url: URL) -> [URL] {
    []
  }

  #if !os(macOS)
    public func urlForApplication(toOpen contentType: UTType) -> URL? { nil }
    public func urlsForApplications(toOpen contentType: UTType) -> [URL] { [] }
  #endif

  public func icon(forFile fullPath: String) -> NSImage {
    #if os(Windows)
      var len: Int = 0
      if let ptr = cak_file_icon_png(fullPath, 32, &len), len > 0 {
        let data = Data(bytes: ptr, count: len)
        cak_free(ptr)
        if let img = NSImage(data: data) {
          img.size = NSSize(width: 32, height: 32)
          return img
        }
      }
    #endif
    return NSImage(size: NSSize(width: 32, height: 32))
  }

  #if !os(macOS)
    public func icon(for contentType: UTType) -> NSImage {
      if let ext = contentType.preferredFilenameExtension {
        return icon(forFile: "dummy.\(ext)")
      }
      return NSImage(size: NSSize(width: 32, height: 32))
    }
  #endif

  public func unmountAndEjectDevice(at url: URL) throws {}

  #if !os(macOS)
    public func observe<Value>(
      _ keyPath: KeyPath<NSWorkspace, Value>,
      options: NSKeyValueObservingOptions = [],
      changeHandler: @escaping @Sendable (NSWorkspace, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
      if options.contains(.initial) {
        changeHandler(self, NSKeyValueObservedChange<Value>())
      }
      return NSKeyValueObservation {}
    }
  #endif
}
