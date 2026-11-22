import Foundation
import SwiftUIRuntime

public struct StagedApplication: Sendable {
  public let project: ResolvedXcodeProject
  public let platform: TargetPlatform
  public let architecture: TargetArchitecture
  public let appName: String
  public let executableName: String
  public let bundleIdentifier: String
  public let version: String
  public let copyright: String?
  public let stageRootDirectory: URL
  public let appBundleDirectory: URL
  public let stagedExecutableURL: URL
  public let resourcesDirectory: URL
  public let windowsIconURL: URL?
  public let desktopEntryURL: URL?
  public let linuxIconsDirectory: URL?
}

public enum PEImportScanner {
  public static func directImportedDLLs(at url: URL) throws -> [String] {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return parseImportedDLLNames(from: data)
  }

  public static func parseImportedDLLNames(from data: Data) -> [String] {
    guard data.count >= 0x40 else { return [] }
    guard readUInt16LE(data, at: 0) == 0x5A4D else { return [] } // "MZ"
    let peOffset = Int(readUInt32LE(data, at: 0x3C))
    guard peOffset >= 0, peOffset + 24 <= data.count else { return [] }
    guard readUInt32LE(data, at: peOffset) == 0x0000_4550 else { return [] } // "PE\0\0"

    let coffOffset = peOffset + 4
    let numberOfSections = Int(readUInt16LE(data, at: coffOffset + 2))
    let sizeOfOptionalHeader = Int(readUInt16LE(data, at: coffOffset + 16))
    let optionalOffset = coffOffset + 20
    guard optionalOffset + sizeOfOptionalHeader <= data.count else { return [] }

    let magic = readUInt16LE(data, at: optionalOffset)
    let dataDirStartOffset: Int
    let numberOfRvaAndSizesOffset: Int
    if magic == 0x020B { // PE32+
      numberOfRvaAndSizesOffset = optionalOffset + 108
      dataDirStartOffset = optionalOffset + 112
    } else if magic == 0x010B { // PE32
      numberOfRvaAndSizesOffset = optionalOffset + 92
      dataDirStartOffset = optionalOffset + 96
    } else {
      return []
    }
    guard numberOfRvaAndSizesOffset + 4 <= data.count else { return [] }
    let dirCount = Int(readUInt32LE(data, at: numberOfRvaAndSizesOffset))

    struct Section {
      let virtualSize: UInt32
      let virtualAddress: UInt32
      let rawSize: UInt32
      let rawPointer: UInt32
    }

    let sectionTableOffset = optionalOffset + sizeOfOptionalHeader
    guard sectionTableOffset + numberOfSections * 40 <= data.count else { return [] }
    var sections: [Section] = []
    sections.reserveCapacity(numberOfSections)
    for i in 0..<numberOfSections {
      let sOff = sectionTableOffset + i * 40
      sections.append(
        Section(
          virtualSize: readUInt32LE(data, at: sOff + 8),
          virtualAddress: readUInt32LE(data, at: sOff + 12),
          rawSize: readUInt32LE(data, at: sOff + 16),
          rawPointer: readUInt32LE(data, at: sOff + 20)
        )
      )
    }

    func rvaToOffset(_ rva: UInt32) -> Int? {
      for sec in sections {
        let span = max(sec.virtualSize, sec.rawSize)
        if rva >= sec.virtualAddress && rva < sec.virtualAddress &+ span {
          let offset = Int(sec.rawPointer) + Int(rva - sec.virtualAddress)
          if offset >= 0 && offset < data.count { return offset }
        }
      }
      return nil
    }

    func readCString(at offset: Int) -> String? {
      guard offset >= 0 && offset < data.count else { return nil }
      var end = offset
      while end < data.count && data[end] != 0 {
        end += 1
      }
      return String(data: data[offset..<end], encoding: .ascii)
    }

    var results: [String] = []
    var seen = Set<String>()
    func appendName(_ name: String?) {
      guard let name, !name.isEmpty else { return }
      if seen.insert(name.lowercased()).inserted {
        results.append(name)
      }
    }

    // DataDirectory[1]: Import Table
    if dirCount > 1 && dataDirStartOffset + 16 <= data.count {
      let importRVA = readUInt32LE(data, at: dataDirStartOffset + 8)
      if importRVA != 0, var cursor = rvaToOffset(importRVA) {
        while cursor + 20 <= data.count {
          let originalFirstThunk = readUInt32LE(data, at: cursor)
          let nameRVA = readUInt32LE(data, at: cursor + 12)
          let firstThunk = readUInt32LE(data, at: cursor + 16)
          if originalFirstThunk == 0 && nameRVA == 0 && firstThunk == 0 { break }
          if nameRVA != 0, let nameOff = rvaToOffset(nameRVA) {
            appendName(readCString(at: nameOff))
          }
          cursor += 20
        }
      }
    }

    // DataDirectory[13]: Delay Import Descriptor
    if dirCount > 13 && dataDirStartOffset + 14 * 8 <= data.count {
      let delayRVA = readUInt32LE(data, at: dataDirStartOffset + 13 * 8)
      if delayRVA != 0, var cursor = rvaToOffset(delayRVA) {
        while cursor + 32 <= data.count {
          let attrs = readUInt32LE(data, at: cursor)
          let dllNameRVA = readUInt32LE(data, at: cursor + 4)
          if attrs == 0 && dllNameRVA == 0 { break }
          if dllNameRVA != 0, let nameOff = rvaToOffset(dllNameRVA) {
            appendName(readCString(at: nameOff))
          }
          cursor += 32
        }
      }
    }

    return results
  }

  public static func readPESubsystem(at url: URL) -> UInt16? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
          data.count >= 0x40,
          readUInt16LE(data, at: 0) == 0x5A4D
    else {
      return nil
    }
    let peOffset = Int(readUInt32LE(data, at: 0x3C))
    guard peOffset >= 0, peOffset + 24 <= data.count,
          readUInt32LE(data, at: peOffset) == 0x0000_4550
    else {
      return nil
    }
    let optionalOffset = peOffset + 24
    let subsystemOffset = optionalOffset + 68
    guard subsystemOffset + 2 <= data.count else { return nil }
    return readUInt16LE(data, at: subsystemOffset)
  }

  private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }
}

public final class ApplicationStager {
  public init() {}

  public func stage(
    project: ResolvedXcodeProject,
    built: BuiltTargetArtifacts,
    builtProductsDirectory: URL? = nil
  ) throws -> StagedApplication {
    let fm = FileManager.default
    let target = project.mainTarget
    let appName = target.productName
    let stageRoot = builtProductsDirectory ?? built.buildDirectory.appendingPathComponent("stage")
    try fm.createDirectory(at: stageRoot, withIntermediateDirectories: true)
    let appDir = stageRoot.appendingPathComponent(appName)
    if fm.fileExists(atPath: appDir.path) {
      try fm.removeItem(at: appDir)
    }
    try fm.createDirectory(at: appDir, withIntermediateDirectories: true)

    var exeDestURL = appDir.appendingPathComponent(built.executableURL.lastPathComponent)
    var resourcesDestURL = appDir.appendingPathComponent("Resources")
    var desktopURL: URL?
    var linuxIconsDir: URL?

    switch built.targetPlatform {
    case .windows:
      try fm.copyItem(at: built.executableURL, to: exeDestURL)
      if project.configuration == .release {
        stripReleaseBinaryIfPossible(
          executableURL: exeDestURL,
          swiftExecutableURL: built.swiftExecutableURL
        )
      }
      try fm.copyItem(at: built.compiledAssets.resourcesDirectory, to: resourcesDestURL)
      try copySwiftPMResourceBundles(
        from: built.executableURL.deletingLastPathComponent(),
        to: appDir
      )
      try collectWindowsRuntimeDLLs(
        executableURL: built.executableURL,
        swiftExecutableURL: built.swiftExecutableURL,
        destinationDir: appDir
      )
    case .linux:
      try fm.copyItem(at: built.executableURL, to: exeDestURL)
      if project.configuration == .release {
        stripReleaseBinaryIfPossible(
          executableURL: exeDestURL,
          swiftExecutableURL: built.swiftExecutableURL
        )
      }
      #if !os(Windows)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeDestURL.path)
      #endif
      try fm.copyItem(at: built.compiledAssets.resourcesDirectory, to: resourcesDestURL)
      try copySwiftPMResourceBundles(
        from: built.executableURL.deletingLastPathComponent(),
        to: appDir
      )
      let libDir = appDir.appendingPathComponent("lib")
      try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
      try collectLinuxRuntimeSharedLibraries(
        executableURL: built.executableURL,
        swiftExecutableURL: built.swiftExecutableURL,
        libDir: libDir
      )
      desktopURL = try writeLinuxDesktopEntry(
        target: target,
        appDir: appDir
      )
      if !built.compiledAssets.linuxIconVariants.isEmpty {
        let iconsBase = appDir.appendingPathComponent("icons")
        for variant in built.compiledAssets.linuxIconVariants {
          let destDir = iconsBase
            .appendingPathComponent("hicolor/\(variant.size)x\(variant.size)/apps")
          try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
          let destFile = destDir.appendingPathComponent("\(target.bundleIdentifier).png")
          try fm.copyItem(at: variant.url, to: destFile)
        }
        linuxIconsDir = iconsBase
      }
    case .wasm:
      guard let wasmPkgDir = built.wasmPackageDirectory else {
        throw BuildBackendError.binaryMissing(built.executableURL.path)
      }
      let webAppDir = appDir.appendingPathComponent("app")
      try fm.copyItem(at: wasmPkgDir, to: webAppDir)
      try fm.copyItem(at: built.compiledAssets.resourcesDirectory, to: resourcesDestURL)
      try stageWasmWebManifest(
        project: project,
        built: built,
        resourcesDestURL: resourcesDestURL
      )

      let home = fm.homeDirectoryForCurrentUser
      if let npmURL = ProcessRunner.findExecutable(
        named: ["npm"],
        extraDirectories: [
          home.appendingPathComponent(".vite-plus/bin"),
          URL(fileURLWithPath: "/opt/homebrew/bin"),
          URL(fileURLWithPath: "/usr/local/bin"),
        ]
      ) {
        let npmResult = try ProcessRunner.run(
          executable: npmURL,
          arguments: [
            "install",
            "--prefix", webAppDir.path,
            "--ignore-scripts",
            "--omit=dev",
            "--no-audit",
            "--no-fund",
          ],
          workingDirectory: appDir
        )
        if npmResult.exitCode != 0 {
          throw ProcessRunnerError.commandFailed(
            command: "\(npmURL.path) install --prefix \(webAppDir.path)",
            exitCode: npmResult.exitCode,
            output: npmResult.stdout + "\n" + npmResult.stderr
          )
        }
      }

      let displayName = target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName
      let templateIndexHTML = built.crossSwiftRoot.appendingPathComponent("Web/index.html")
      let indexHTMLURL = appDir.appendingPathComponent("index.html")
      if let template = try? String(contentsOf: templateIndexHTML, encoding: .utf8) {
        let rendered = template.replacingOccurrences(
          of: "<title>CrossSwiftUI</title>",
          with: "<title>\(htmlEscape(displayName))</title>"
        )
        try rendered.write(to: indexHTMLURL, atomically: true, encoding: .utf8)
      } else {
        let fallback = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(displayName))</title>
          <script type="importmap">
            { "imports": { "@bjorn3/browser_wasi_shim": "./app/node_modules/@bjorn3/browser_wasi_shim/dist/index.js" } }
          </script>
        </head>
        <body>
          <main id="swiftui-root"></main>
          <script type="module">
            const { init } = await import("./app/index.js");
            try {
              const res = await fetch("./Resources/web-manifest.json");
              if (res.ok) { window.__crossSwiftUIResources = await res.json(); }
            } catch {}
            await init();
          </script>
        </body>
        </html>
        """
        try fallback.write(to: indexHTMLURL, atomically: true, encoding: .utf8)
      }
      exeDestURL = indexHTMLURL
    case .harmonyos:
      guard let harmony = built.harmonyArtifacts else {
        throw BuildBackendError.binaryMissing(built.executableURL.path)
      }
      let hapURL = try HarmonyBuilder.stageProject(
        project: project,
        harmonyArtifacts: harmony,
        compiledAssets: built.compiledAssets,
        crossSwiftRoot: built.crossSwiftRoot,
        destinationDir: appDir
      )
      exeDestURL = hapURL ?? appDir.appendingPathComponent("runtime/\(target.executableName).o")
      resourcesDestURL = appDir.appendingPathComponent("entry/src/main/resources/rawfile/Resources")
    case .android:
      guard let android = built.androidArtifacts else {
        throw BuildBackendError.binaryMissing(built.executableURL.path)
      }
      let apkURL = try AndroidBuilder.stageProject(
        project: project,
        androidArtifacts: android,
        compiledAssets: built.compiledAssets,
        crossSwiftRoot: built.crossSwiftRoot,
        destinationDir: appDir
      )
      let firstAbi = android.abis.first ?? "arm64-v8a"
      exeDestURL = apkURL
        ?? appDir.appendingPathComponent("app/src/main/jniLibs/\(firstAbi)/lib\(android.libraryName).so")
      resourcesDestURL = appDir.appendingPathComponent("app/src/main/assets/Resources")
    }

    return StagedApplication(
      project: project,
      platform: built.targetPlatform,
      architecture: built.architecture,
      appName: appName,
      executableName: target.executableName,
      bundleIdentifier: target.bundleIdentifier,
      version: target.marketingVersion,
      copyright: target.copyright,
      stageRootDirectory: stageRoot,
      appBundleDirectory: appDir,
      stagedExecutableURL: exeDestURL,
      resourcesDirectory: resourcesDestURL,
      windowsIconURL: built.compiledAssets.windowsIconURL,
      desktopEntryURL: desktopURL,
      linuxIconsDirectory: linuxIconsDir
    )
  }

  private func stripReleaseBinaryIfPossible(
    executableURL: URL,
    swiftExecutableURL: URL
  ) {
    let toolchainBin = swiftExecutableURL.deletingLastPathComponent()
    guard let stripTool = ProcessRunner.findExecutable(
      named: ["llvm-strip", "strip"],
      extraDirectories: [toolchainBin]
    ) else { return }
    _ = try? ProcessRunner.run(
      executable: stripTool,
      arguments: ["--strip-all", executableURL.path]
    )
  }

  private func copySwiftPMResourceBundles(from binDir: URL, to appDir: URL) throws {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: binDir.path) else { return }
    for entry in entries where entry.hasSuffix(".resources") || entry.hasSuffix(".bundle") {
      let src = binDir.appendingPathComponent(entry)
      let dst = appDir.appendingPathComponent(entry)
      if fm.fileExists(atPath: dst.path) {
        try? fm.removeItem(at: dst)
      }
      try fm.copyItem(at: src, to: dst)
    }
  }

  private func collectWindowsRuntimeDLLs(
    executableURL: URL,
    swiftExecutableURL: URL,
    destinationDir: URL
  ) throws {
    let fm = FileManager.default
    let searchDirs = windowsRuntimeSearchDirectories(
      executableDir: executableURL.deletingLastPathComponent(),
      swiftExecutableURL: swiftExecutableURL
    )

    var queue: [URL] = [executableURL]
    var scannedFiles = Set<String>()
    var copiedDLLs = Set<String>()

    while !queue.isEmpty {
      let binary = queue.removeFirst()
      let stdPath = binary.standardizedFileURL.path.lowercased()
      guard scannedFiles.insert(stdPath).inserted else { continue }

      let imports = (try? PEImportScanner.directImportedDLLs(at: binary)) ?? []
      for dllName in imports {
        let lower = dllName.lowercased()
        if isWindowsSystemDLL(lower) { continue }
        if copiedDLLs.contains(lower) { continue }
        guard let sourceURL = findDLL(named: dllName, in: searchDirs) else { continue }
        let destURL = destinationDir.appendingPathComponent(sourceURL.lastPathComponent)
        if !fm.fileExists(atPath: destURL.path) {
          try fm.copyItem(at: sourceURL, to: destURL)
        }
        copiedDLLs.insert(lower)
        queue.append(sourceURL)
      }
    }
  }

  private func querySwiftRuntimeLibraryPaths(swiftExecutableURL: URL) -> [URL] {
    guard let res = try? ProcessRunner.run(
      executable: swiftExecutableURL,
      arguments: ["-print-target-info"]
    ),
      res.exitCode == 0,
      let data = res.stdout.data(using: .utf8),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let paths = json["paths"] as? [String: Any],
      let rawDirs = paths["runtimeLibraryPaths"] as? [String]
    else {
      return []
    }
    var dirs: [URL] = []
    for raw in rawDirs {
      let url = URL(fileURLWithPath: raw)
      dirs.append(url)
      // On Windows, runtime DLLs often sit in ../../bin relative to lib/swift/windows.
      dirs.append(url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("bin"))
    }
    return dirs
  }

  private func windowsRuntimeSearchDirectories(
    executableDir: URL,
    swiftExecutableURL: URL
  ) -> [URL] {
    let fm = FileManager.default
    var dirs: [URL] = [executableDir]
    dirs.append(contentsOf: querySwiftRuntimeLibraryPaths(swiftExecutableURL: swiftExecutableURL))

    // Swift toolchain bin & adjacent runtime dirs:
    // ...\Swift\Toolchains\<ver>\usr\bin -> ...\Swift\Runtimes\<ver>\usr\bin
    let resolvedSwift = swiftExecutableURL.resolvingSymlinksInPath()
    let swiftBinDir = resolvedSwift.deletingLastPathComponent()
    dirs.append(swiftBinDir)

    let toolchainDir = swiftBinDir.deletingLastPathComponent().deletingLastPathComponent()
    let swiftProgramDir = toolchainDir.deletingLastPathComponent().deletingLastPathComponent()
    let runtimesDir = swiftProgramDir.appendingPathComponent("Runtimes")
    if let runtimeVersions = try? fm.contentsOfDirectory(at: runtimesDir, includingPropertiesForKeys: nil) {
      let toolchainTag = toolchainDir.lastPathComponent
      let sorted = runtimeVersions.sorted { a, b in
        let aMatches = toolchainTag.hasPrefix(a.lastPathComponent)
        let bMatches = toolchainTag.hasPrefix(b.lastPathComponent)
        if aMatches != bMatches { return aMatches }
        return a.lastPathComponent > b.lastPathComponent
      }
      for ver in sorted {
        dirs.append(ver.appendingPathComponent("usr/bin"))
      }
    }

    if let sdkRoot = ProcessRunner.environmentValue("SDKROOT"), !sdkRoot.isEmpty {
      dirs.append(URL(fileURLWithPath: sdkRoot).appendingPathComponent("usr/bin"))
    }

    if let pathEnv = ProcessRunner.environmentValue("PATH") {
      for entry in pathEnv.split(separator: ";").map(String.init) {
        let lower = entry.lowercased()
        if lower.contains("\\windows\\system32") || lower.contains("\\windows\\syswow64") {
          continue
        }
        dirs.append(URL(fileURLWithPath: entry))
      }
    }
    return dirs
  }

  private func findDLL(named dllName: String, in directories: [URL]) -> URL? {
    let fm = FileManager.default
    for dir in directories {
      let candidate = dir.appendingPathComponent(dllName)
      if fm.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func isWindowsSystemDLL(_ lowerName: String) -> Bool {
    if lowerName.hasPrefix("api-ms-win-") || lowerName.hasPrefix("ext-ms-") { return true }
    if lowerName.hasPrefix("vcruntime") || lowerName.hasPrefix("msvcp")
      || lowerName.hasPrefix("concrt") || lowerName.hasPrefix("vcomp")
    {
      return true
    }
    if lowerName.hasPrefix("d3d") { return true }
    let systemNames: Set<String> = [
      "kernel32.dll", "user32.dll", "gdi32.dll", "gdiplus.dll", "advapi32.dll",
      "d2d1.dll", "dwrite.dll",
      "shell32.dll", "ole32.dll", "oleaut32.dll", "uuid.dll", "comctl32.dll",
      "comdlg32.dll", "dwmapi.dll", "imm32.dll", "bcrypt.dll", "crypt32.dll",
      "ncrypt.dll", "shlwapi.dll", "version.dll", "psapi.dll", "winsqlite3.dll",
      "ws2_32.dll", "ntdll.dll", "msvcrt.dll", "ucrtbase.dll", "rpcrt4.dll",
      "sechost.dll", "dbghelp.dll", "winmm.dll", "setupapi.dll", "cfgmgr32.dll",
      "iphlpapi.dll", "userenv.dll", "netapi32.dll", "wtsapi32.dll", "powrprof.dll",
      "uxtheme.dll", "msimg32.dll", "opengl32.dll", "dxgi.dll", "winhttp.dll",
      "wininet.dll", "shcore.dll", "mpr.dll", "normaliz.dll", "wldap32.dll",
    ]
    return systemNames.contains(lowerName)
  }

  private func collectLinuxRuntimeSharedLibraries(
    executableURL: URL,
    swiftExecutableURL: URL,
    libDir: URL
  ) throws {
    let fm = FileManager.default
    guard let lddURL = ProcessRunner.findExecutable(named: ["ldd"]) else { return }

    var envOverrides: [String: String] = [:]
    var ldPaths = querySwiftRuntimeLibraryPaths(swiftExecutableURL: swiftExecutableURL).map(\.path)
    let fallbackLibDir = swiftExecutableURL
      .resolvingSymlinksInPath()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("lib/swift/linux")
    if fm.fileExists(atPath: fallbackLibDir.path) && !ldPaths.contains(fallbackLibDir.path) {
      ldPaths.append(fallbackLibDir.path)
    }
    if let existingLD = ProcessInfo.processInfo.environment["LD_LIBRARY_PATH"], !existingLD.isEmpty {
      ldPaths.append(existingLD)
    }
    if !ldPaths.isEmpty {
      envOverrides["LD_LIBRARY_PATH"] = ldPaths.joined(separator: ":")
    }

    let res = try ProcessRunner.run(
      executable: lddURL,
      arguments: [executableURL.path],
      environmentOverrides: envOverrides
    )
    guard res.exitCode == 0 else { return }

    for rawLine in res.stdout.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard let arrow = line.range(of: "=>") else { continue }
      let soname = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
      let rhs = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
      guard let pathToken = rhs.split(whereSeparator: \.isWhitespace).first.map(String.init),
            pathToken.hasPrefix("/")
      else {
        continue
      }
      guard shouldBundleLinuxLibrary(soname: soname, resolvedPath: pathToken) else {
        continue
      }
      let srcURL = URL(fileURLWithPath: pathToken)
      let destURL = libDir.appendingPathComponent(soname)
      if !fm.fileExists(atPath: destURL.path) {
        let resolvedSrc = srcURL.resolvingSymlinksInPath()
        try fm.copyItem(at: resolvedSrc, to: destURL)
      }
    }
  }

  private func shouldBundleLinuxLibrary(soname: String, resolvedPath: String) -> Bool {
    let lowerName = soname.lowercased()
    let swiftPrefixes = [
      "libswift",
      "libfoundation",
      "lib_foundation",
      "libdispatch",
      "libblocksruntime",
      "libicu",
      "lib_icu",
      "libxctarget",
    ]
    if swiftPrefixes.contains(where: { lowerName.hasPrefix($0) }) {
      return true
    }
    if resolvedPath.contains("/swift") || resolvedPath.contains("/swiftly/") {
      return true
    }
    return false
  }

  private func writeLinuxDesktopEntry(target: ResolvedTarget, appDir: URL) throws -> URL {
    let displayName = target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName
    let categories = mapAppleCategoryToFreedesktop(target.categoryType)
    let contents = """
    [Desktop Entry]
    Type=Application
    Name=\(displayName)
    Exec=\(target.executableName)
    Icon=\(target.bundleIdentifier)
    Terminal=false
    Categories=\(categories)
    StartupWMClass=\(target.executableName)
    """
    let url = appDir.appendingPathComponent("\(target.bundleIdentifier).desktop")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func mapAppleCategoryToFreedesktop(_ appleCategory: String?) -> String {
    guard let appleCategory = appleCategory?.lowercased() else {
      return "Utility;"
    }
    if appleCategory.contains("developer-tools") { return "Development;" }
    if appleCategory.contains("graphics-design") || appleCategory.contains("photography") {
      return "Graphics;"
    }
    if appleCategory.contains("music") || appleCategory.contains("video") {
      return "AudioVideo;"
    }
    if appleCategory.contains("education") { return "Education;" }
    if appleCategory.contains("games") { return "Game;" }
    if appleCategory.contains("social-networking") { return "Network;" }
    if appleCategory.contains("finance") || appleCategory.contains("productivity") {
      return "Office;"
    }
    return "Utility;"
  }

  private func stageWasmWebManifest(
    project: ResolvedXcodeProject,
    built: BuiltTargetArtifacts,
    resourcesDestURL: URL
  ) throws {
    let fm = FileManager.default
    var images: [String: String] = [:]
    var xcstrings: [String] = []
    let webAssetsDir = resourcesDestURL.appendingPathComponent("_web_assets")

    func relativeResourceURL(for url: URL) -> String? {
      let base = resourcesDestURL.standardizedFileURL.path
      let full = url.standardizedFileURL.path
      let prefix = base.hasSuffix("/") ? base : base + "/"
      guard full.hasPrefix(prefix) else { return nil }
      let rel = String(full.dropFirst(prefix.count))
      let encoded = rel.split(separator: "/").map { seg in
        String(seg).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(seg)
      }.joined(separator: "/")
      return "./Resources/" + encoded
    }

    func resolveImagesetFile(in imagesetURL: URL) -> URL? {
      let contentsURL = imagesetURL.appendingPathComponent("Contents.json")
      var candidates: [(url: URL, priority: Int)] = []
      if let data = try? Data(contentsOf: contentsURL),
         let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
         let entries = json["images"] as? [[String: Any]]
      {
        for entry in entries {
          guard let filename = entry["filename"] as? String, !filename.isEmpty else { continue }
          let fileURL = imagesetURL.appendingPathComponent(filename)
          guard fm.fileExists(atPath: fileURL.path) else { continue }
          let ext = fileURL.pathExtension.lowercased()
          let scale = (entry["scale"] as? String) ?? ""
          let priority: Int
          switch ext {
          case "svg": priority = 100
          case "pdf": priority = 90
          case "png", "webp", "jpg", "jpeg":
            if scale == "3x" { priority = 80 }
            else if scale == "2x" { priority = 70 }
            else { priority = 60 }
          default: priority = 10
          }
          candidates.append((fileURL, priority))
        }
      }
      if let best = candidates.max(by: { $0.priority < $1.priority }) {
        return best.url
      }
      if let files = try? fm.contentsOfDirectory(at: imagesetURL, includingPropertiesForKeys: nil) {
        return files.first {
          let ext = $0.pathExtension.lowercased()
          return ext == "svg" || ext == "pdf" || ext == "png" || ext == "webp" || ext == "jpg" || ext == "jpeg"
        }
      }
      return nil
    }

    func scanCatalogs(under root: URL, isInsideResources: Bool) {
      guard fm.fileExists(atPath: root.path),
            let enumerator = fm.enumerator(
              at: root,
              includingPropertiesForKeys: [.isDirectoryKey],
              options: [.skipsHiddenFiles]
            )
      else { return }
      for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if name == ".build" || name == ".git" || name == "node_modules" {
          enumerator.skipDescendants()
          continue
        }
        let lower = name.lowercased()
        if isInsideResources && lower.hasSuffix(".xcstrings") {
          if let text = try? String(contentsOf: url, encoding: .utf8) {
            xcstrings.append(text)
          }
          continue
        }
        if lower.hasSuffix(".imageset") {
          enumerator.skipDescendants()
          let assetName = String(name.dropLast(".imageset".count))
          guard !assetName.isEmpty, images[assetName] == nil else { continue }
          guard let fileURL = resolveImagesetFile(in: url) else { continue }
          let ext = fileURL.pathExtension.lowercased()
          if ext == "pdf" {
            if let vector = PDFVectorParser.parse(filePath: fileURL.path) {
              try? fm.createDirectory(at: webAssetsDir, withIntermediateDirectories: true)
              let safeName = ProcessRunner.sanitizedSlug(assetName) + "-" + ProcessRunner.fnv1aHex(assetName) + ".svg"
              let svgURL = webAssetsDir.appendingPathComponent(safeName)
              try? vector.toSVG().write(to: svgURL, atomically: true, encoding: .utf8)
              if let rel = relativeResourceURL(for: svgURL) {
                images[assetName] = rel
              }
            }
          } else if isInsideResources, let rel = relativeResourceURL(for: fileURL) {
            images[assetName] = rel
          } else {
            try? fm.createDirectory(at: webAssetsDir, withIntermediateDirectories: true)
            let safeName = ProcessRunner.sanitizedSlug(assetName) + "-" + ProcessRunner.fnv1aHex(assetName) + "." + ext
            let dstURL = webAssetsDir.appendingPathComponent(safeName)
            if fm.fileExists(atPath: dstURL.path) {
              try? fm.removeItem(at: dstURL)
            }
            if (try? fm.copyItem(at: fileURL, to: dstURL)) != nil,
               let rel = relativeResourceURL(for: dstURL)
            {
              images[assetName] = rel
            }
          }
        }
      }
    }

    scanCatalogs(under: resourcesDestURL, isInsideResources: true)
    for adaptedDir in built.adaptedRemotePackageDirectories {
      scanCatalogs(under: adaptedDir, isInsideResources: false)
    }
    for localPkg in project.localPackages {
      scanCatalogs(under: localPkg.path, isInsideResources: false)
    }

    let payload: [String: Any] = [
      "images": images,
      "xcstrings": xcstrings,
    ]
    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let manifestURL = resourcesDestURL.appendingPathComponent("web-manifest.json")
    try jsonData.write(to: manifestURL, options: .atomic)
  }

  private func htmlEscape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
