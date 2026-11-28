import Foundation

#if !os(Windows) && !os(Linux) && canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Classification of a file change in an Xcode project for hot-reload routing.
public enum ProjectChangeKind: String, Sendable, Equatable, Comparable {
  case ignored
  case resourceOnly
  case swiftSource
  case projectConfig

  private var rank: Int {
    switch self {
    case .ignored: return 0
    case .resourceOnly: return 1
    case .swiftSource: return 2
    case .projectConfig: return 3
    }
  }

  public static func < (lhs: ProjectChangeKind, rhs: ProjectChangeKind) -> Bool {
    lhs.rank < rhs.rank
  }
}

/// Coalesced set of file paths changed since the previous poll snapshot.
public struct ProjectChangeBatch: Sendable, Equatable {
  public let changedPaths: [String]
  public let kind: ProjectChangeKind

  public init(changedPaths: [String], kind: ProjectChangeKind) {
    self.changedPaths = changedPaths
    self.kind = kind
  }
}

/// Maps project file paths to rebuild severity (ignored, resource-only, Swift source, or project config).
public enum ProjectChangeClassifier {
  public static let ignoredDirectoryNames: Set<String> = [
    ".git",
    ".build",
    "build",
    "DerivedData",
    "node_modules",
    "xcuserdata",
    ".swiftpm",
    "Intermediates.noindex",
    ".Trash",
  ]

  private static let swiftSourceExtensions: Set<String> = [
    "swift", "c", "cc", "cpp", "cxx", "h", "hpp", "m", "mm", "modulemap", "metal",
  ]

  private static let resourceExtensions: Set<String> = [
    "xcstrings", "strings", "stringsdict", "plist", "json",
    "png", "jpg", "jpeg", "webp", "gif", "svg", "pdf", "ico", "icns",
    "ttf", "otf", "woff", "woff2",
    "txt", "md", "html", "css", "xml", "yaml", "yml", "csv",
    "mp3", "wav", "m4a", "mp4", "mov",
  ]

  public static func classify(path: String) -> ProjectChangeKind {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let components = normalized.split(separator: "/").map(String.init)
    guard let fileName = components.last, !fileName.isEmpty else {
      return .ignored
    }

    // Ignore anything inside build/VCS/IDE transient directories.
    for comp in components.dropLast() {
      if ignoredDirectoryNames.contains(comp) {
        return .ignored
      }
      if comp.hasPrefix(".") && comp != "." && comp != ".." {
        return .ignored
      }
    }

    // Ignore dotfiles, editor swap/backup/temp files, and Xcode user state.
    let lowerName = fileName.lowercased()
    if fileName.hasPrefix(".")
      || fileName.hasSuffix("~")
      || (fileName.hasPrefix("#") && fileName.hasSuffix("#"))
      || lowerName.hasSuffix(".swp")
      || lowerName.hasSuffix(".swo")
      || lowerName.hasSuffix(".tmp")
      || lowerName.hasSuffix(".bak")
      || lowerName.hasSuffix(".orig")
      || lowerName.hasSuffix(".xcuserstate")
      || lowerName.hasSuffix(".lock")
      || lowerName == ".ds_store"
    {
      return .ignored
    }

    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()

    // Project/package configuration files require reloading the project graph + rebuilding.
    if fileName == "project.pbxproj"
      || fileName == "project.xcproj"
      || fileName == "Package.swift"
      || fileName == "Package.resolved"
      || ext == "xcconfig"
    {
      return .projectConfig
    }

    // Swift / C / C++ / ObjC source files require incremental compilation.
    if swiftSourceExtensions.contains(ext) {
      return .swiftSource
    }

    // Anything inside an asset catalog or localization directory is a resource change.
    for comp in components.dropLast() {
      let lowerComp = comp.lowercased()
      if lowerComp.hasSuffix(".xcassets") || lowerComp.hasSuffix(".lproj") {
        return .resourceOnly
      }
    }

    if resourceExtensions.contains(ext) {
      return .resourceOnly
    }

    return .ignored
  }

  public static func classify(paths: [String]) -> ProjectChangeKind {
    paths.reduce(.ignored) { acc, path in
      max(acc, classify(path: path))
    }
  }
}

/// Portable, zero-dependency stat-polling file watcher with debounce and change classification.
public final class ProjectFileWatcher: @unchecked Sendable {
  private struct FileStamp: Equatable {
    let mtimeSeconds: Int64
    let mtimeNanoseconds: Int64
    let size: Int64
  }

  private let roots: [URL]
  private let excludedPathPrefixes: [String]
  private let pollInterval: TimeInterval
  private let debounceInterval: TimeInterval
  private let onChange: @Sendable (ProjectChangeBatch) -> Void

  private let lock = NSLock()
  private var isRunning = false
  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "dev.crossswift.filewatcher", qos: .utility)

  private var lastSnapshot: [String: FileStamp] = [:]
  private var pendingPaths = Set<String>()
  private var pendingKind: ProjectChangeKind = .ignored
  private var lastChangeDate: Date?

  public init(
    roots: [URL],
    excludedDirectories: [URL] = [],
    pollInterval: TimeInterval = 0.25,
    debounceInterval: TimeInterval = 0.15,
    onChange: @escaping @Sendable (ProjectChangeBatch) -> Void
  ) {
    self.roots = roots.map(\.standardizedFileURL)
    self.excludedPathPrefixes = excludedDirectories.map { dir in
      let p = dir.standardizedFileURL.path
      return p.hasSuffix("/") ? p : p + "/"
    }
    self.pollInterval = max(0.05, pollInterval)
    self.debounceInterval = max(0.02, debounceInterval)
    self.onChange = onChange
  }

  public func start() {
    lock.lock()
    if isRunning {
      lock.unlock()
      return
    }
    isRunning = true
    lastSnapshot = takeSnapshot()
    pendingPaths.removeAll()
    pendingKind = .ignored
    lastChangeDate = nil

    let source = DispatchSource.makeTimerSource(queue: queue)
    let intervalMs = max(25, Int(pollInterval * 1000))
    source.schedule(deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs))
    source.setEventHandler { [weak self] in
      self?.pollOnce()
    }
    timer = source
    lock.unlock()
    source.resume()
  }

  public func stop() {
    lock.lock()
    isRunning = false
    let activeTimer = timer
    timer = nil
    pendingPaths.removeAll()
    pendingKind = .ignored
    lastChangeDate = nil
    lock.unlock()
    activeTimer?.cancel()
  }

  deinit {
    stop()
  }

  private func pollOnce() {
    let current = takeSnapshot()
    var batchToEmit: ProjectChangeBatch?

    lock.lock()
    guard isRunning else {
      lock.unlock()
      return
    }

    var newlyChanged: [String] = []
    for (path, stamp) in current {
      if lastSnapshot[path] != stamp {
        newlyChanged.append(path)
      }
    }
    for path in lastSnapshot.keys where current[path] == nil {
      newlyChanged.append(path)
    }
    lastSnapshot = current

    let now = Date()
    if !newlyChanged.isEmpty {
      for path in newlyChanged {
        let kind = ProjectChangeClassifier.classify(path: path)
        if kind != .ignored {
          pendingPaths.insert(path)
          if kind > pendingKind {
            pendingKind = kind
          }
          lastChangeDate = now
        }
      }
    }

    if pendingKind != .ignored,
       let lastDate = lastChangeDate,
       now.timeIntervalSince(lastDate) >= debounceInterval
    {
      batchToEmit = ProjectChangeBatch(
        changedPaths: Array(pendingPaths).sorted(),
        kind: pendingKind
      )
      pendingPaths.removeAll()
      pendingKind = .ignored
      lastChangeDate = nil
    }
    lock.unlock()

    if let batch = batchToEmit {
      onChange(batch)
    }
  }

  private func takeSnapshot() -> [String: FileStamp] {
    var snapshot: [String: FileStamp] = [:]
    let fm = FileManager.default

    for root in roots {
      let rootPath = root.path
      guard fm.fileExists(atPath: rootPath) else { continue }
      guard let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: []
      ) else { continue }

      for case let url as URL in enumerator {
        let stdPath = url.standardizedFileURL.path
        if isExcluded(path: stdPath) {
          enumerator.skipDescendants()
          continue
        }

        let name = url.lastPathComponent
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: stdPath, isDirectory: &isDir), isDir.boolValue {
          if ProjectChangeClassifier.ignoredDirectoryNames.contains(name)
            || (name.hasPrefix(".") && name != "." && name != "..")
          {
            enumerator.skipDescendants()
          }
          continue
        }

        // Skip classifying/statting obvious non-watched files early.
        if ProjectChangeClassifier.classify(path: stdPath) == .ignored {
          continue
        }
        if let stamp = readFileStamp(atPath: stdPath) {
          snapshot[stdPath] = stamp
        }
      }
    }
    return snapshot
  }

  private func isExcluded(path: String) -> Bool {
    let withSlash = path.hasSuffix("/") ? path : path + "/"
    for prefix in excludedPathPrefixes {
      if withSlash.hasPrefix(prefix) || path + "/" == prefix {
        return true
      }
    }
    return false
  }

  private func readFileStamp(atPath path: String) -> FileStamp? {
    #if !os(Windows) && !os(Linux) && canImport(Darwin)
      var st = stat()
      guard stat(path, &st) == 0 else { return nil }
      return FileStamp(
        mtimeSeconds: Int64(st.st_mtimespec.tv_sec),
        mtimeNanoseconds: Int64(st.st_mtimespec.tv_nsec),
        size: Int64(st.st_size)
      )
    #elseif canImport(Glibc)
      var st = stat()
      guard stat(path, &st) == 0 else { return nil }
      return FileStamp(
        mtimeSeconds: Int64(st.st_mtim.tv_sec),
        mtimeNanoseconds: Int64(st.st_mtim.tv_nsec),
        size: Int64(st.st_size)
      )
    #else
      guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let modDate = attrs[.modificationDate] as? Date,
            let rawSize = attrs[.size]
      else {
        return nil
      }
      let fileSize: Int64
      if let n = rawSize as? UInt64 {
        fileSize = Int64(bitPattern: n)
      } else if let n = rawSize as? Int64 {
        fileSize = n
      } else if let n = rawSize as? Int {
        fileSize = Int64(n)
      } else if let n = rawSize as? NSNumber {
        fileSize = n.int64Value
      } else {
        return nil
      }
      let secs = modDate.timeIntervalSince1970
      let whole = Int64(secs)
      let nanos = Int64((secs - Double(whole)) * 1_000_000_000)
      return FileStamp(mtimeSeconds: whole, mtimeNanoseconds: nanos, size: fileSize)
    #endif
  }
}
