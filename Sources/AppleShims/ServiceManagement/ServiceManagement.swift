import Foundation

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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\reg.exe")
        proc.arguments = ["query", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "/v", appName]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
          try proc.run()
          proc.waitUntilExit()
          return proc.terminationStatus == 0 ? .enabled : .notRegistered
        } catch {
          return .notRegistered
        }
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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\reg.exe")
        proc.arguments = [
          "add", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
          "/v", appName, "/t", "REG_SZ", "/d", "\"\(exe)\"", "/f",
        ]
        try proc.run()
        proc.waitUntilExit()
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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\reg.exe")
        proc.arguments = [
          "delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
          "/v", appName, "/f",
        ]
        try proc.run()
        proc.waitUntilExit()
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
