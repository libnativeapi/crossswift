import Foundation
#if os(Windows)
  import CAppKitWindows
#endif

#if !os(macOS)
  public final class SMAppService: @unchecked Sendable {
    public enum Status: Int, Sendable {
      case notRegistered = 0
      case enabled = 1
      case requiresApproval = 2
      case notFound = 3
    }

    public static let mainApp = SMAppService()

    public var status: Status {
      #if os(Windows)
        return cak_login_item_status(appName) != 0 ? .enabled : .notRegistered
      #elseif os(Linux)
        return FileManager.default.fileExists(atPath: linuxAutostartFileURL.path) ? .enabled : .notRegistered
      #else
        return .notRegistered
      #endif
    }

    public func register() throws {
      #if os(Windows)
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
        guard !exe.isEmpty else { return }
        if cak_login_item_set(appName, "\"\(exe)\" --background") == 0 {
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        }
      #elseif os(Linux)
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? ""
        guard !exe.isEmpty else { return }
        let fileURL = linuxAutostartFileURL
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        let escapedExe = exe.replacingOccurrences(of: "\"", with: "\\\"")
        let entry = """
        [Desktop Entry]
        Type=Application
        Name=\(appName)
        Exec="\(escapedExe)"
        X-GNOME-Autostart-enabled=true
        """
        try entry.write(to: fileURL, atomically: true, encoding: .utf8)
      #endif
    }

    public func unregister() throws {
      #if os(Windows)
        if cak_login_item_remove(appName) == 0 {
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        }
      #elseif os(Linux)
        let fileURL = linuxAutostartFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
          try FileManager.default.removeItem(at: fileURL)
        }
      #endif
    }

    #if os(Linux)
      private var linuxAutostartFileURL: URL {
        let configHome: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
          configHome = URL(fileURLWithPath: xdg)
        } else {
          configHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let stem = (Bundle.main.bundleIdentifier ?? appName)
          .replacingOccurrences(of: "/", with: "_")
          .replacingOccurrences(of: " ", with: "-")
        return configHome.appendingPathComponent("autostart/\(stem).desktop")
      }
    #endif

    private var appName: String {
      (Bundle.main.infoDictionary?["CFBundleName"] as? String)
        ?? Bundle.main.executableURL?.deletingPathExtension().lastPathComponent
        ?? ProcessInfo.processInfo.processName
    }
  }
#endif
