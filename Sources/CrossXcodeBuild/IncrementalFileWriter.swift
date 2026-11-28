import Foundation

#if !os(Windows) && !os(Linux) && canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Helpers that preserve file modification times (mtimes) when generated or staged
/// contents have not changed, and perform atomic replacements so live dev servers
/// never observe half-written artifacts.
public enum IncrementalFileWriter {
  /// Writes `data` to `url` only if the destination does not exist or its bytes differ.
  /// Returns `true` if the file was created or updated, `false` if left untouched.
  @discardableResult
  public static func writeIfChanged(data: Data, to url: URL) throws -> Bool {
    let fm = FileManager.default
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fm.fileExists(atPath: url.path),
       let existing = try? Data(contentsOf: url),
       existing == data
    {
      return false
    }
    try data.write(to: url, options: .atomic)
    return true
  }

  /// Writes UTF-8 `text` to `url` only if the destination does not exist or its text differs.
  /// Returns `true` if the file was created or updated, `false` if left untouched.
  @discardableResult
  public static func writeIfChanged(text: String, to url: URL) throws -> Bool {
    try writeIfChanged(data: Data(text.utf8), to: url)
  }

  /// Copies `source` to `destination` only if `destination` is missing, is a symlink,
  /// or has different contents. Uses an atomic sibling temp-file swap so readers
  /// (e.g. a running dev server) never see a missing or truncated file.
  @discardableResult
  public static func copyFileIfChanged(from source: URL, to destination: URL) throws -> Bool {
    let fm = FileManager.default
    let destDir = destination.deletingLastPathComponent()
    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

    let destIsSymlink = (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil
    if !destIsSymlink,
       fm.fileExists(atPath: destination.path),
       filesHaveEqualContents(source, destination)
    {
      return false
    }

    let tmpURL = destDir.appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")
    defer {
      if fm.fileExists(atPath: tmpURL.path) {
        try? fm.removeItem(at: tmpURL)
      }
    }
    try fm.copyItem(at: source, to: tmpURL)

    if destIsSymlink {
      try? fm.removeItem(at: destination)
      try fm.moveItem(at: tmpURL, to: destination)
    } else if fm.fileExists(atPath: destination.path) {
      #if os(Windows)
        try fm.removeItem(at: destination)
        try fm.moveItem(at: tmpURL, to: destination)
      #else
        if rename(tmpURL.path, destination.path) != 0 {
          _ = try fm.replaceItemAt(destination, withItemAt: tmpURL)
        }
      #endif
    } else {
      try fm.moveItem(at: tmpURL, to: destination)
    }
    return true
  }

  /// Ensures `destination` is a symlink to `source` (on POSIX) or an up-to-date copy (on Windows),
  /// avoiding unnecessary unlinks/rewrites so SwiftPM preserves incremental compilation caches.
  @discardableResult
  public static func syncSymlinkOrCopy(from source: URL, to destination: URL) throws -> Bool {
    let fm = FileManager.default
    let targetPath = source.standardizedFileURL.path
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

    #if !os(Windows)
      if let existingTarget = try? fm.destinationOfSymbolicLink(atPath: destination.path) {
        let resolvedExisting = URL(
          fileURLWithPath: existingTarget,
          relativeTo: destination.deletingLastPathComponent()
        ).standardizedFileURL.path
        if resolvedExisting == targetPath {
          return false
        }
        try fm.removeItem(at: destination)
      } else if fm.fileExists(atPath: destination.path) {
        try fm.removeItem(at: destination)
      }
      if (try? fm.createSymbolicLink(atPath: destination.path, withDestinationPath: targetPath)) != nil {
        return true
      }
    #endif

    return try copyFileIfChanged(from: source, to: destination)
  }

  /// Recursively synchronizes `sourceDir` into `destDir`, copying only new/changed files
  /// atomically and pruning stale entries that are no longer in `sourceDir`.
  /// Entries whose top-level names are in `excluding` are left completely untouched in `destDir`.
  public static func syncDirectory(
    from sourceDir: URL,
    to destDir: URL,
    excluding excludedTopLevelNames: Set<String> = []
  ) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

    var expectedNames = Set<String>()
    let sourceEntries = try fm.contentsOfDirectory(atPath: sourceDir.path)
    for name in sourceEntries {
      if excludedTopLevelNames.contains(name) { continue }
      expectedNames.insert(name)
      let srcItem = sourceDir.appendingPathComponent(name)
      let dstItem = destDir.appendingPathComponent(name)
      var srcIsDir: ObjCBool = false
      guard fm.fileExists(atPath: srcItem.path, isDirectory: &srcIsDir) else { continue }

      if srcIsDir.boolValue {
        var dstIsDir: ObjCBool = false
        if fm.fileExists(atPath: dstItem.path, isDirectory: &dstIsDir), !dstIsDir.boolValue {
          try fm.removeItem(at: dstItem)
        }
        try syncDirectory(from: srcItem, to: dstItem)
      } else {
        var dstIsDir: ObjCBool = false
        if fm.fileExists(atPath: dstItem.path, isDirectory: &dstIsDir), dstIsDir.boolValue {
          try fm.removeItem(at: dstItem)
        }
        try copyFileIfChanged(from: srcItem, to: dstItem)
      }
    }

    let existingEntries = (try? fm.contentsOfDirectory(atPath: destDir.path)) ?? []
    for name in existingEntries {
      if excludedTopLevelNames.contains(name) { continue }
      if !expectedNames.contains(name) {
        try? fm.removeItem(at: destDir.appendingPathComponent(name))
      }
    }
  }

  /// Removes any files or empty directories under `root` whose relative POSIX paths
  /// are not in `keepRelativePaths`.
  public static func pruneStaleEntries(
    under root: URL,
    keeping keepRelativePaths: Set<String>
  ) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return }
    let basePath = root.standardizedFileURL.path
    let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"

    var filesToRemove: [URL] = []
    var dirsToCheck: [URL] = []
    if let enumerator = fm.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: []
    ) {
      for case let url as URL in enumerator {
        let stdPath = url.standardizedFileURL.path
        guard stdPath.hasPrefix(prefix) else { continue }
        let rel = String(stdPath.dropFirst(prefix.count))
        let isSymlink = (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
        if isSymlink {
          if !keepRelativePaths.contains(rel) {
            filesToRemove.append(url)
          }
          continue
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
          dirsToCheck.append(url)
        } else if !keepRelativePaths.contains(rel) {
          filesToRemove.append(url)
        }
      }
    }

    for file in filesToRemove {
      try? fm.removeItem(at: file)
    }
    // Remove now-empty directories deepest-first.
    for dir in dirsToCheck.sorted(by: { $0.path.count > $1.path.count }) {
      if let children = try? fm.contentsOfDirectory(atPath: dir.path), children.isEmpty {
        try? fm.removeItem(at: dir)
      }
    }
  }

  private static func fileSize(from attrs: [FileAttributeKey: Any]) -> UInt64? {
    guard let raw = attrs[.size] else { return nil }
    if let n = raw as? UInt64 { return n }
    if let n = raw as? Int64 { return n >= 0 ? UInt64(n) : nil }
    if let n = raw as? Int { return n >= 0 ? UInt64(n) : nil }
    if let n = raw as? NSNumber { return n.uint64Value }
    return nil
  }

  private static func filesHaveEqualContents(_ a: URL, _ b: URL) -> Bool {
    let fm = FileManager.default
    guard let aAttr = try? fm.attributesOfItem(atPath: a.path),
          let bAttr = try? fm.attributesOfItem(atPath: b.path),
          let aSize = fileSize(from: aAttr),
          let bSize = fileSize(from: bAttr),
          aSize == bSize
    else {
      return false
    }
    return fm.contentsEqual(atPath: a.path, andPath: b.path)
  }
}
