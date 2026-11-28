import Foundation

public struct HarmonyBuildArtifacts: Sendable {
  public let runtimeDirectory: URL
  public let appObjectURL: URL
  public let internalObjectNames: [String]
  public let staticLinuxSDKURL: URL
  public let nativeAPISwiftRoot: URL
  public let usesDesktopShims: Bool

  public init(
    runtimeDirectory: URL,
    appObjectURL: URL,
    internalObjectNames: [String],
    staticLinuxSDKURL: URL,
    nativeAPISwiftRoot: URL,
    usesDesktopShims: Bool = false
  ) {
    self.runtimeDirectory = runtimeDirectory
    self.appObjectURL = appObjectURL
    self.internalObjectNames = internalObjectNames
    self.staticLinuxSDKURL = staticLinuxSDKURL
    self.nativeAPISwiftRoot = nativeAPISwiftRoot
    self.usesDesktopShims = usesDesktopShims
  }
}

public enum HarmonyBuilder {
  public static func resolveStaticLinuxSDK(crossSwiftRoot: URL) throws -> URL {
    let fm = FileManager.default
    var candidates: [URL] = []

    if let envPath = ProcessRunner.environmentValue("SWIFT_STATIC_LINUX_SDK"), !envPath.isEmpty {
      let url = URL(fileURLWithPath: envPath).standardizedFileURL
      candidates.append(url)
      candidates.append(
        url.appendingPathComponent(
          "swift-6.4.2-RELEASE_static-linux-0.1.0/swift-linux-musl/musl-1.2.5.sdk/aarch64"
        )
      )
    }

    let probeCached = crossSwiftRoot.appendingPathComponent(
      "Examples/HarmonyRuntimeProbe/.build/sdk/swift-6.4.2-RELEASE_static-linux-0.1.0.artifactbundle/swift-6.4.2-RELEASE_static-linux-0.1.0/swift-linux-musl/musl-1.2.5.sdk/aarch64"
    )
    candidates.append(probeCached.standardizedFileURL)

    let home = fm.homeDirectoryForCurrentUser
    let sdkRoots = [
      home.appendingPathComponent("Library/org.swift.swiftpm/swift-sdks"),
      home.appendingPathComponent(".swiftpm/swift-sdks"),
    ]
    for root in sdkRoots where fm.fileExists(atPath: root.path) {
      if let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) {
        for case let url as URL in enumerator {
          if url.lastPathComponent == "aarch64",
             url.path.contains("musl-"),
             fm.fileExists(atPath: url.appendingPathComponent("usr/lib/swift_static/linux-static").path)
          {
            candidates.append(url.standardizedFileURL)
            enumerator.skipDescendants()
          }
        }
      }
    }

    for candidate in candidates {
      let staticLibs = candidate.appendingPathComponent("usr/lib/swift_static/linux-static")
      if fm.fileExists(atPath: staticLibs.path) {
        return candidate
      }
    }

    throw BuildBackendError.toolMissing(
      "Could not locate the ARM64 Swift Static Linux SDK (musl-1.2.5.sdk/aarch64). Set SWIFT_STATIC_LINUX_SDK or install swift-6.4.2-RELEASE_static-linux-0.1.0."
    )
  }

  public static func locateHarmonySwiftc() throws -> (executable: URL, prefixArgs: [String], suffixArgs: [String]) {
    let fm = FileManager.default
    if let toolchainBin = ProcessRunner.environmentValue("SWIFT_TOOLCHAIN_BIN"), !toolchainBin.isEmpty {
      let swiftc = URL(fileURLWithPath: toolchainBin).appendingPathComponent("swiftc")
      if fm.isExecutableFile(atPath: swiftc.path) {
        return (swiftc, [], [])
      }
    }

    let home = fm.homeDirectoryForCurrentUser
    let extraDirs = [
      home.appendingPathComponent(".swiftly/bin"),
      home.appendingPathComponent(".local/share/swiftly/bin"),
      home.appendingPathComponent(".local/bin"),
    ]
    if let swiftly = ProcessRunner.findExecutable(named: ["swiftly"], extraDirectories: extraDirs) {
      if let check = try? ProcessRunner.run(
        executable: swiftly,
        arguments: ["run", "+6.4.2", "swiftc", "--version"]
      ), check.exitCode == 0 {
        return (swiftly, ["run", "+6.4.2", "swiftc"], [])
      }
    }

    if let swiftc = ProcessRunner.findExecutable(named: ["swiftc"], extraDirectories: extraDirs) {
      return (swiftc, [], [])
    }

    throw BuildBackendError.toolMissing(
      "Could not locate Swift 6.4.2 'swiftc' for HarmonyOS cross-compilation; set SWIFT_TOOLCHAIN_BIN or install via swiftly."
    )
  }

  public static func detectMainAppTypeName(in swiftSources: [URL]) -> String? {
    let pattern = "@main\\s+(?:(?:public|internal|private|fileprivate|final|@MainActor)\\s+)*(?:struct|class|enum)\\s+([A-Za-z_][A-Za-z0-9_]*)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
      return nil
    }
    for url in swiftSources {
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      if let match = regex.firstMatch(in: text, range: range),
         let nameRange = Range(match.range(at: 1), in: text)
      {
        return String(text[nameRange])
      }
    }
    return nil
  }

  public static func usesDesktopShims(project: ResolvedXcodeProject) -> Bool {
    let nonSwiftUI = project.inferredCrossSwiftModules.filter {
      $0 != "SwiftUI" && $0 != "SwiftUIRuntime"
    }
    if !nonSwiftUI.isEmpty { return true }
    let desktopIndicators: Set<String> = [
      "AppKit", "CrossAppKit", "UIKit", "CrossUIKit", "CrossFoundation",
      "CoreGraphics", "CoreText", "Combine", "CryptoKit", "Carbon",
      "UniformTypeIdentifiers", "OSLog", "os", "SQLite3", "Darwin",
      "CoreFoundation", "QuartzCore", "Security", "IOKit",
    ]
    return project.allTargets.contains { target in
      target.importedModules.contains { desktopIndicators.contains($0) }
    }
  }

  public static func renderHarmonyAppHostSwift(
    appTypeName: String,
    usesDesktopShims: Bool = false
  ) -> String {
    if usesDesktopShims {
      return """
      // AUTO-GENERATED BY CrossXcodeBuild. DO NOT EDIT.
      import CrossAppKit
      import Foundation
      import SwiftUIHarmony
      import SwiftUIRuntime

      @MainActor
      private final class HarmonySurfaceSession {
        let backend: HarmonyBackend
        var renderer: Renderer?
        var viewportSize: Size

        init(backend: HarmonyBackend, viewportSize: Size) {
          self.backend = backend
          self.viewportSize = viewportSize
        }
      }

      @MainActor
      private var _harmonySessions: [Int: HarmonySurfaceSession] = [:]
      @MainActor
      private var _harmonyAppBootstrapped = false
      @MainActor
      private var _harmonyIsDark = false

      @MainActor
      private func _harmonyInstallRootView(_ rootView: AnyView, forSurface surfaceId: Int) {
        guard let session = _harmonySessions[surfaceId] else { return }
        let config = HarmonyHost.surfaceConfig(for: surfaceId)
        let initialSize = config.fixedContentSize ?? session.viewportSize
        let renderer = Renderer(
          backend: session.backend,
          root: rootView,
          size: initialSize,
          layoutEngine: LayoutEngine(textMeasurer: session.backend.measureText)
        )
        session.renderer = renderer
        renderer.mount()
      }

      @MainActor @_cdecl("swift_configure_resources")
      public func swiftConfigureResources(
        _ directory: UnsafePointer<CChar>?,
        _ language: UnsafePointer<CChar>?
      ) {
        let dir = directory.map(String.init(cString:)) ?? ""
        let lang = language.map(String.init(cString:))
        if !dir.isEmpty {
          HarmonyHost.configureResources(directory: dir, preferredLanguage: lang)
        } else if let lang, !lang.isEmpty {
          XCStringsCatalog.shared.preferredLanguage = lang
        }
      }

      @MainActor @_cdecl("swift_mount_surface")
      public func swiftMountSurface(
        _ surfaceId: Int32,
        _ context: UnsafeMutableRawPointer,
        _ update: HarmonyUpdate,
        _ width: Double,
        _ height: Double,
        _ pixelsPerPoint: Double
      ) {
        let sid = Int(surfaceId)
        let backend = HarmonyBackend(
          context: context,
          update: update,
          pixelsPerPoint: pixelsPerPoint,
          surfaceId: sid
        )
        backend.environment.colorScheme = _harmonyIsDark ? .dark : .light
        let session = HarmonySurfaceSession(
          backend: backend,
          viewportSize: Size(width: width, height: height)
        )
        _harmonySessions[sid] = session
        HarmonyHost.setMountHandler(forSurface: sid) { rootView in
          _harmonyInstallRootView(rootView, forSurface: sid)
        }
        HarmonyHost.setSizeHandler(forSurface: sid) { size in
          _harmonySessions[sid]?.renderer?.resize(to: size)
        }
        if !_harmonyAppBootstrapped {
          _harmonyAppBootstrapped = true
          let envMap = ProcessInfo.processInfo.environment
          if let resDir = envMap["CROSS_SWIFTUI_RESOURCES_DIR"], !resDir.isEmpty {
            HarmonyHost.configureResources(
              directory: resDir,
              preferredLanguage: envMap["CROSS_SWIFTUI_LANGUAGE"]
            )
          }
          \(appTypeName).main()
        }
        if session.renderer == nil {
          if let pending = HarmonyHost.pendingRootView(forSurface: sid) {
            _harmonyInstallRootView(pending, forSurface: sid)
          } else if sid == 0 {
            _harmonyInstallRootView(AnyView(EmptyView()), forSurface: sid)
          }
        }
      }

      @MainActor @_cdecl("swift_mount_app")
      public func swiftMountApp(
        _ context: UnsafeMutableRawPointer,
        _ update: HarmonyUpdate,
        _ width: Double,
        _ height: Double,
        _ pixelsPerPoint: Double
      ) {
        swiftMountSurface(0, context, update, width, height, pixelsPerPoint)
      }

      @MainActor @_cdecl("swift_reopen_app")
      public func swiftReopenApp() {
        _ = NSApplication.shared.delegate?.applicationShouldHandleReopen(
          NSApplication.shared,
          hasVisibleWindows: false
        )
      }

      @MainActor @_cdecl("swift_resize_surface")
      public func swiftResizeSurface(_ surfaceId: Int32, _ width: Double, _ height: Double) {
        let sid = Int(surfaceId)
        guard let session = _harmonySessions[sid] else { return }
        session.viewportSize = Size(width: width, height: height)
        if let fixed = HarmonyHost.surfaceConfig(for: sid).fixedContentSize {
          session.renderer?.resize(to: fixed)
        } else {
          session.renderer?.resize(to: session.viewportSize)
        }
      }

      @MainActor @_cdecl("swift_resize_app")
      public func swiftResizeApp(_ width: Double, _ height: Double) {
        swiftResizeSurface(0, width, height)
      }

      @MainActor @_cdecl("swift_set_color_scheme")
      public func swiftSetColorScheme(_ isDark: Int32) {
        _harmonyIsDark = isDark != 0
        let target: ColorScheme = _harmonyIsDark ? .dark : .light
        for session in _harmonySessions.values {
          guard session.backend.environment.colorScheme != target else { continue }
          session.backend.environment.colorScheme = target
          session.renderer?.setNeedsRender()
          session.renderer?.renderIfNeeded()
        }
      }

      @MainActor @_cdecl("swift_surface_event")
      public func swiftSurfaceEvent(
        _ surfaceId: Int32,
        _ id: Int,
        _ event: Int32,
        _ text: UnsafePointer<CChar>?
      ) {
        let sid = Int(surfaceId)
        let payload = text.map(String.init(cString:)) ?? ""
        if event == 17, let code = Int(payload) {
          if HarmonyHost.keyEventHandler?(sid, code) == true {
            return
          }
        }
        guard let renderer = _harmonySessions[sid]?.renderer else { return }
        let nodeID = NodeID(rawValue: id)
        switch event {
        case 1: renderer.performTap(nodeID)
        case 2, 3: renderer.interact(nodeID, .hover(event == 2))
        case 4, 5: renderer.interact(nodeID, .pressed(event == 4))
        case 7: renderer.input(id: nodeID, event: 7, text: payload)
        case 8, 9: renderer.interact(nodeID, .focus(event == 8))
        case 10: renderer.performBoolInput(nodeID, value: payload == "1" || payload == "true")
        case 11:
          if let v = Double(payload) {
            renderer.performDoubleInput(nodeID, value: v, ended: true)
          }
        case 12:
          if let idx = Int(payload) {
            renderer.performIntInput(nodeID, value: idx)
          }
        case 13:
          if let delta = Int(payload) {
            renderer.performStepInput(nodeID, delta: delta)
          }
        case 14: renderer.performBackInput(nodeID)
        case 15: renderer.dismissActivePresentation()
        case 16: _ = renderer.input(id: nodeID, event: 6, value: 13)
        case 17:
          if let code = Int(payload) {
            _ = renderer.input(id: nodeID, event: 6, value: code)
          }
        default: break
        }
      }

      @MainActor @_cdecl("swift_app_event")
      public func swiftAppEvent(_ id: Int, _ event: Int32, _ text: UnsafePointer<CChar>?) {
        swiftSurfaceEvent(0, id, event, text)
      }

      @MainActor @_cdecl("swift_unmount_surface")
      public func swiftUnmountSurface(_ surfaceId: Int32) {
        let sid = Int(surfaceId)
        HarmonyHost.clearSurface(sid)
        _harmonySessions.removeValue(forKey: sid)
      }

      @MainActor @_cdecl("swift_unmount_app")
      public func swiftUnmountApp() {
        HarmonyHost.resetMountedRoot()
        _harmonySessions.removeAll()
      }
      """
    }
    return """
    // AUTO-GENERATED BY CrossXcodeBuild. DO NOT EDIT.
    import Foundation
    import SwiftUIHarmony
    import SwiftUIRuntime

    extension App {
      public static func main() {}
    }

    @MainActor
    private func _harmonyFlattenScenes(_ scene: any Scene) -> [any Scene] {
      if let composite = scene as? any _CompositeScene {
        return composite._childScenes.flatMap { _harmonyFlattenScenes($0) }
      }
      if scene is EmptyScene || scene is any _WindowScene || scene is any _MenuBarExtraScene {
        return [scene]
      }
      let body = scene.body
      if body is EmptyScene { return [scene] }
      return _harmonyFlattenScenes(body)
    }

    @MainActor
    private var _harmonyAppRenderer: Renderer?
    @MainActor
    private var _harmonyAppBackend: HarmonyBackend?

    @MainActor @_cdecl("swift_configure_resources")
    public func swiftConfigureResources(
      _ directory: UnsafePointer<CChar>?,
      _ language: UnsafePointer<CChar>?
    ) {
      let dir = directory.map(String.init(cString:)) ?? ""
      let lang = language.map(String.init(cString:))
      if !dir.isEmpty {
        HarmonyHost.configureResources(directory: dir, preferredLanguage: lang)
      } else if let lang, !lang.isEmpty {
        XCStringsCatalog.shared.preferredLanguage = lang
      }
    }

    @MainActor @_cdecl("swift_mount_app")
    public func swiftMountApp(
      _ context: UnsafeMutableRawPointer,
      _ update: HarmonyUpdate,
      _ width: Double,
      _ height: Double,
      _ pixelsPerPoint: Double
    ) {
      let envMap = ProcessInfo.processInfo.environment
      if let resDir = envMap["CROSS_SWIFTUI_RESOURCES_DIR"], !resDir.isEmpty {
        HarmonyHost.configureResources(
          directory: resDir,
          preferredLanguage: envMap["CROSS_SWIFTUI_LANGUAGE"]
        )
      }
      let app = \(appTypeName)()
      let scenes = _harmonyFlattenScenes(app.body)
      let rootView: AnyView
      if let windowScene = scenes.first(where: { $0 is any _WindowScene }) as? any _WindowScene {
        rootView = windowScene._makeRootView()
      } else {
        rootView = AnyView(EmptyView())
      }
      let backend = HarmonyBackend(context: context, update: update, pixelsPerPoint: pixelsPerPoint)
      let renderer = Renderer(
        backend: backend,
        root: rootView,
        size: Size(width: width, height: height),
        layoutEngine: LayoutEngine(textMeasurer: backend.measureText)
      )
      _harmonyAppBackend = backend
      _harmonyAppRenderer = renderer
      renderer.mount()
    }

    @MainActor @_cdecl("swift_mount_surface")
    public func swiftMountSurface(
      _ surfaceId: Int32,
      _ context: UnsafeMutableRawPointer,
      _ update: HarmonyUpdate,
      _ width: Double,
      _ height: Double,
      _ pixelsPerPoint: Double
    ) {
      if surfaceId == 0 {
        swiftMountApp(context, update, width, height, pixelsPerPoint)
      }
    }

    @MainActor @_cdecl("swift_resize_app")
    public func swiftResizeApp(_ width: Double, _ height: Double) {
      _harmonyAppRenderer?.resize(to: Size(width: width, height: height))
    }

    @MainActor @_cdecl("swift_resize_surface")
    public func swiftResizeSurface(_ surfaceId: Int32, _ width: Double, _ height: Double) {
      if surfaceId == 0 {
        swiftResizeApp(width, height)
      }
    }

    @MainActor @_cdecl("swift_set_color_scheme")
    public func swiftSetColorScheme(_ isDark: Int32) {
      guard let backend = _harmonyAppBackend, let renderer = _harmonyAppRenderer else { return }
      let target: ColorScheme = isDark != 0 ? .dark : .light
      guard backend.environment.colorScheme != target else { return }
      backend.environment.colorScheme = target
      renderer.setNeedsRender()
      renderer.renderIfNeeded()
    }

    @MainActor @_cdecl("swift_app_event")
    public func swiftAppEvent(_ id: Int, _ event: Int32, _ text: UnsafePointer<CChar>?) {
      guard let renderer = _harmonyAppRenderer else { return }
      let nodeID = NodeID(rawValue: id)
      let payload = text.map(String.init(cString:)) ?? ""
      switch event {
      case 1: renderer.performTap(nodeID)
      case 2, 3: renderer.interact(nodeID, .hover(event == 2))
      case 4, 5: renderer.interact(nodeID, .pressed(event == 4))
      case 7: renderer.input(id: nodeID, event: 7, text: payload)
      case 8, 9: renderer.interact(nodeID, .focus(event == 8))
      case 10: renderer.performBoolInput(nodeID, value: payload == "1" || payload == "true")
      case 11:
        if let v = Double(payload) {
          renderer.performDoubleInput(nodeID, value: v, ended: true)
        }
      case 12:
        if let idx = Int(payload) {
          renderer.performIntInput(nodeID, value: idx)
        }
      case 13:
        if let delta = Int(payload) {
          renderer.performStepInput(nodeID, delta: delta)
        }
      case 14: renderer.performBackInput(nodeID)
      case 15: renderer.dismissActivePresentation()
      case 16: _ = renderer.input(id: nodeID, event: 6, value: 13)
      case 17:
        if let code = Int(payload) {
          _ = renderer.input(id: nodeID, event: 6, value: code)
        }
      default: break
      }
    }

    @MainActor @_cdecl("swift_surface_event")
    public func swiftSurfaceEvent(
      _ surfaceId: Int32,
      _ id: Int,
      _ event: Int32,
      _ text: UnsafePointer<CChar>?
    ) {
      if surfaceId == 0 {
        swiftAppEvent(id, event, text)
      }
    }

    @MainActor @_cdecl("swift_unmount_app")
    public func swiftUnmountApp() {
      _harmonyAppRenderer = nil
      _harmonyAppBackend = nil
    }

    @MainActor @_cdecl("swift_unmount_surface")
    public func swiftUnmountSurface(_ surfaceId: Int32) {
      if surfaceId == 0 {
        swiftUnmountApp()
      }
    }
    """
  }

  public static func build(
    project: ResolvedXcodeProject,
    configuration: BuildConfiguration,
    buildRoot: URL,
    compiledAssets: CompiledAssets,
    crossSwiftRoot: URL,
    nativeAPISwiftRoot: URL,
    dependencyPackages: [URL] = [],
    quiet: Bool = false
  ) throws -> HarmonyBuildArtifacts {
    let fm = FileManager.default
    let sdkURL = try resolveStaticLinuxSDK(crossSwiftRoot: crossSwiftRoot)
    let resourcesURL = sdkURL.appendingPathComponent("usr/lib/swift_static")
    let runtimeDir = buildRoot.appendingPathComponent("runtime")
    try fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

    let buildOhosScript = nativeAPISwiftRoot.appendingPathComponent("scripts/build-ohos.sh")
    guard fm.fileExists(atPath: buildOhosScript.path) else {
      throw BuildBackendError.toolMissing(
        "Missing HarmonyOS build script at '\(buildOhosScript.path)'."
      )
    }

    let home = fm.homeDirectoryForCurrentUser
    var pathParts = [
      home.appendingPathComponent(".swiftly/bin").path,
      home.appendingPathComponent(".local/share/swiftly/bin").path,
    ]
    if let existing = ProcessRunner.environmentValue("PATH"), !existing.isEmpty {
      pathParts.append(existing)
    }
    let swiftcTool = try locateHarmonySwiftc()
    var envOverrides = ["PATH": pathParts.joined(separator: ":")]
    if ProcessRunner.environmentValue("SWIFT_TOOLCHAIN_BIN")?.isEmpty != false,
       swiftcTool.executable.lastPathComponent == "swiftc"
    {
      envOverrides["SWIFT_TOOLCHAIN_BIN"] = swiftcTool.executable.deletingLastPathComponent().path
    }

    let desktopShims = usesDesktopShims(project: project)

    // 1. Build NativeAPI.o and stage Swift/Foundation static archives via nativeapi/bindings/swift/scripts/build-ohos.sh
    let nativeObjURL = runtimeDir.appendingPathComponent("NativeAPI.o")
    let nativeModURL = runtimeDir.appendingPathComponent("NativeAPI.swiftmodule")
    let nativeAPISources = collectSwiftFiles(in: nativeAPISwiftRoot.appendingPathComponent("Sources/NativeAPI"))
    let needsNativeAPIBuild = !isUpToDate(
      outputs: [nativeObjURL, nativeModURL],
      inputs: nativeAPISources + [buildOhosScript]
    )
    if needsNativeAPIBuild {
      let bashURL = ProcessRunner.findExecutable(named: ["bash"]) ?? URL(fileURLWithPath: "/bin/bash")
      let nativeLog = buildRoot.appendingPathComponent("harmony-nativeapi.log")
      if !quiet {
        ProcessRunner.writeStdoutLine(
          "Building HarmonyOS NativeAPI runtime — log: \(nativeLog.path)"
        )
      }
      let nativeRes = try ProcessRunner.run(
        executable: bashURL,
        arguments: [buildOhosScript.path, sdkURL.path, runtimeDir.path],
        workingDirectory: buildRoot,
        environmentOverrides: envOverrides,
        logFile: nativeLog,
        echoOutput: !quiet
      )
      if nativeRes.exitCode != 0 {
        throw ProcessRunnerError.commandFailed(
          command: "bash \(buildOhosScript.path) \(sdkURL.path) \(runtimeDir.path)",
          exitCode: nativeRes.exitCode,
          output: nativeRes.stdout
        )
      }
    }

    func stageSDKArchive(from srcURL: URL) throws {
      guard fm.fileExists(atPath: srcURL.path) else { return }
      let dstURL = runtimeDir.appendingPathComponent(srcURL.lastPathComponent)
      if !fm.fileExists(atPath: dstURL.path) {
        try fm.copyItem(at: srcURL, to: dstURL)
      }
    }

    let swiftStaticLibs = sdkURL.appendingPathComponent("usr/lib/swift_static/linux-static")
    let usrLibs = sdkURL.appendingPathComponent("usr/lib")
    try stageSDKArchive(from: swiftStaticLibs.appendingPathComponent("libswiftObservation.a"))
    if configuration == .debug {
      try stageSDKArchive(from: swiftStaticLibs.appendingPathComponent("libswiftSwiftOnoneSupport.a"))
    }
    if desktopShims {
      for libName in [
        "libFoundationNetworking.a",
        "lib_CFURLSessionInterface.a",
        "libFoundationXML.a",
        "lib_CFXMLInterface.a",
        "libswiftRegexBuilder.a",
      ] {
        try stageSDKArchive(from: swiftStaticLibs.appendingPathComponent(libName))
      }
      for libName in ["libcurl.a", "libssl.a", "libcrypto.a", "libxml2.a"] {
        try stageSDKArchive(from: usrLibs.appendingPathComponent(libName))
      }
    }

    let optFlag = configuration == .release ? "-O" : "-Onone"
    let nativeAPIHeaders = nativeAPISwiftRoot.appendingPathComponent("Sources/CNativeAPI/include")
    var cShimIncludeFlags: [String] = []
    if desktopShims {
      for rel in [
        "Sources/AppleShims/CDarwinShims/include",
        "Sources/Carbon/include",
        "Sources/AppleShims/IOKit/include",
        "Sources/SQLite3/include",
        "Sources/CQuickJS/include",
      ] {
        let dir = crossSwiftRoot.appendingPathComponent(rel)
        if fm.fileExists(atPath: dir.path) {
          cShimIncludeFlags += ["-I", dir.path]
        }
      }
    }

    // Build host SwiftUIRuntimeMacros compiler plugin so @Entry and #Preview expand during HarmonyOS compilation.
    let macroPluginFlags: [String] = try {
      let macroMain = crossSwiftRoot.appendingPathComponent("Sources/SwiftUIRuntimeMacros/main.swift")
      guard fm.fileExists(atPath: macroMain.path) else { return [] }
      let pluginExe = buildRoot.appendingPathComponent("SwiftUIRuntimeMacros-tool")
      if !fm.isExecutableFile(atPath: pluginExe.path) {
        let hostSwiftc = ProcessRunner.findExecutable(named: ["swiftc"]) ?? swiftcTool.executable
        let hostArgs = (hostSwiftc == swiftcTool.executable ? swiftcTool.prefixArgs : []) + [
          "-O", macroMain.path, "-o", pluginExe.path,
        ]
        let pluginRes = try ProcessRunner.run(
          executable: hostSwiftc,
          arguments: hostArgs,
          workingDirectory: buildRoot,
          environmentOverrides: envOverrides
        )
        if pluginRes.exitCode != 0 {
          return []
        }
      }
      return ["-load-plugin-executable", "\(pluginExe.path)#SwiftUIRuntimeMacros"]
    }()

    func compileSwiftModule(
      moduleName: String,
      outputStem: String,
      sources: [URL],
      extraFlags: [String] = [],
      dependencyOutputs: [URL] = [],
      allowCache: Bool = false
    ) throws -> URL {
      let objURL = runtimeDir.appendingPathComponent("\(outputStem).o")
      let modURL = runtimeDir.appendingPathComponent("\(moduleName).swiftmodule")
      if allowCache && isUpToDate(outputs: [objURL, modURL], inputs: sources + dependencyOutputs) {
        return objURL
      }
      var args = swiftcTool.prefixArgs + [
        "-target", "aarch64-swift-linux-musl",
        "-sdk", sdkURL.path,
        "-resource-dir", resourcesURL.path,
        "-static-stdlib",
        "-parse-as-library",
        "-whole-module-optimization",
        "-emit-object",
        "-emit-module",
        optFlag,
        "-D", "CROSS_SWIFTUI_HARMONY",
        "-I", runtimeDir.path,
        "-I", nativeAPIHeaders.path,
      ]
      if desktopShims {
        args += ["-D", "CROSS_SWIFTUI_HARMONY_DESKTOP"]
        args += cShimIncludeFlags
      }
      args += [
        "-module-name", moduleName,
        "-emit-module-path", modURL.path,
        "-o", objURL.path,
      ] + macroPluginFlags + extraFlags + sources.map(\.path) + swiftcTool.suffixArgs

      let logURL = buildRoot.appendingPathComponent("harmony-\(moduleName).log")
      if !quiet {
        ProcessRunner.writeStdoutLine(
          "Compiling HarmonyOS module \(moduleName) (\(sources.count) file(s)) — log: \(logURL.path)"
        )
      }
      let res = try ProcessRunner.run(
        executable: swiftcTool.executable,
        arguments: args,
        workingDirectory: buildRoot,
        environmentOverrides: envOverrides,
        logFile: logURL,
        echoOutput: !quiet
      )
      if res.exitCode != 0 {
        throw ProcessRunnerError.commandFailed(
          command: "\(swiftcTool.executable.path) \(args.joined(separator: " "))",
          exitCode: res.exitCode,
          output: res.stdout
        )
      }
      return objURL
    }

    // 2. Compile SwiftUIRuntime
    let runtimeSrcDir = crossSwiftRoot.appendingPathComponent("Sources/SwiftUIRuntime")
    let runtimeSources = try fm.contentsOfDirectory(at: runtimeSrcDir, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension.lowercased() == "swift" }
      .sorted { $0.path < $1.path }
    _ = try compileSwiftModule(
      moduleName: "SwiftUIRuntime",
      outputStem: "SwiftUIRuntime",
      sources: runtimeSources,
      extraFlags: ["-swift-version", "5", "-package-name", "CrossSwiftUI"],
      allowCache: true
    )
    let runtimeModURL = runtimeDir.appendingPathComponent("SwiftUIRuntime.swiftmodule")

    // 3. Compile formal SwiftUIHarmony backend module
    let harmonySrcDir = crossSwiftRoot.appendingPathComponent("Sources/SwiftUIHarmony")
    let harmonySources = try fm.contentsOfDirectory(at: harmonySrcDir, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension.lowercased() == "swift" }
      .sorted { $0.path < $1.path }
    guard !harmonySources.isEmpty else {
      throw BuildBackendError.toolMissing(
        "Missing SwiftUIHarmony sources at '\(harmonySrcDir.path)'."
      )
    }
    _ = try compileSwiftModule(
      moduleName: "SwiftUIHarmony",
      outputStem: "SwiftUIHarmony",
      sources: harmonySources,
      extraFlags: ["-swift-version", "5", "-package-name", "CrossSwiftUI"],
      dependencyOutputs: [runtimeModURL],
      allowCache: true
    )
    let harmonyModURL = runtimeDir.appendingPathComponent("SwiftUIHarmony.swiftmodule")

    var internalObjectNames: [String] = []
    var compiledModules: Set<String> = ["SwiftUIRuntime", "SwiftUIHarmony", "SwiftUI", "NativeAPI"]

    // 3b. Compile desktop Apple-framework compatibility shims & AppKit/UIKit hosting when needed
    if desktopShims {
      let desktopShimSpecs: [(name: String, relPath: String, excludes: Set<String>, extraFlags: [String])] = [
        ("CoreFoundation", "Sources/AppleShims/CoreFoundation", [], []),
        ("Combine", "Sources/Combine", [], []),
        ("UniformTypeIdentifiers", "Sources/UniformTypeIdentifiers", [], []),
        ("OSLog", "Sources/OSLog", [], []),
        ("os", "Sources/os", [], []),
        ("CryptoKit", "Sources/CryptoKit", [], []),
        ("Darwin", "Sources/AppleShims/Darwin", [], []),
        ("CoreGraphics", "Sources/CoreGraphics", [], []),
        ("CoreServices", "Sources/AppleShims/CoreServices", [], []),
        ("ApplicationServices", "Sources/AppleShims/ApplicationServices", [], []),
        ("CrossFoundation", "Sources/CrossFoundation", [], []),
        ("CrossAppKit", "Sources/CrossAppKit", [], []),
        ("CrossUIKit", "Sources/CrossUIKit", [], []),
        ("ServiceManagement", "Sources/AppleShims/ServiceManagement", [], []),
        ("Security", "Sources/AppleShims/Security", [], []),
        ("CloudKit", "Sources/AppleShims/CloudKit", [], []),
        ("EventKit", "Sources/AppleShims/EventKit", [], []),
        ("AudioToolbox", "Sources/AppleShims/AudioToolbox", [], []),
        ("CoreMedia", "Sources/AppleShims/CoreMedia", [], []),
        ("AVFoundation", "Sources/AppleShims/AVFoundation", [], []),
        ("AVKit", "Sources/AppleShims/AVKit", [], []),
        ("QuartzCore", "Sources/AppleShims/QuartzCore", [], []),
        ("CoreAudio", "Sources/AppleShims/CoreAudio", [], []),
        ("CoreText", "Sources/AppleShims/CoreText", [], []),
        ("ImageIO", "Sources/AppleShims/ImageIO", [], []),
        ("ColorSync", "Sources/AppleShims/ColorSync", [], []),
        ("PDFKit", "Sources/AppleShims/PDFKit", [], []),
        ("QuickLookUI", "Sources/AppleShims/QuickLookUI", [], []),
        ("QuickLookThumbnailing", "Sources/AppleShims/QuickLookThumbnailing", [], []),
        ("Network", "Sources/AppleShims/Network", [], []),
        ("SystemConfiguration", "Sources/AppleShims/SystemConfiguration", [], []),
        ("AuthenticationServices", "Sources/AppleShims/AuthenticationServices", [], []),
        ("JavaScriptCore", "Sources/AppleShims/JavaScriptCore", [], []),
        ("Compression", "Sources/AppleShims/Compression", [], []),
        ("System", "Sources/AppleShims/System", [], []),
        ("AppleArchive", "Sources/AppleShims/AppleArchive", [], []),
        ("Accelerate", "Sources/AppleShims/Accelerate", [], []),
        ("notify", "Sources/AppleShims/notify", [], []),
        ("CommonCrypto", "Sources/AppleShims/CommonCrypto", [], []),
        ("FoundationModels", "Sources/AppleShims/FoundationModels", [], []),
        ("NaturalLanguage", "Sources/AppleShims/NaturalLanguage", [], []),
        ("Translation", "Sources/AppleShims/Translation", [], []),
        ("AppKit", "Sources/AppKit", [], []),
        ("UIKit", "Sources/UIKit", [], []),
        (
          "CrossSwiftUI",
          "Sources/CrossSwiftUI",
          ["LinuxDrawing.swift", "LinuxDrawingBackend.swift", "WindowsDrawingBackend.swift"],
          ["-package-name", "CrossSwiftUI"]
        ),
      ]
      var compiledModURLs: [URL] = [nativeModURL, runtimeModURL, harmonyModURL]
      for spec in desktopShimSpecs {
        let dir = crossSwiftRoot.appendingPathComponent(spec.relPath)
        let swiftFiles = collectSwiftFiles(in: dir).filter { !spec.excludes.contains($0.lastPathComponent) }
        guard !swiftFiles.isEmpty else { continue }
        _ = try compileSwiftModule(
          moduleName: spec.name,
          outputStem: spec.name,
          sources: swiftFiles,
          extraFlags: ["-swift-version", "5"] + spec.extraFlags,
          dependencyOutputs: compiledModURLs,
          allowCache: true
        )
        compiledModURLs.append(runtimeDir.appendingPathComponent("\(spec.name).swiftmodule"))
        compiledModules.insert(spec.name)
        internalObjectNames.append("\(spec.name).o")
      }
      _ = try compileSwiftModule(
        moduleName: "SwiftUI",
        outputStem: "SwiftUI",
        sources: [crossSwiftRoot.appendingPathComponent("Sources/SwiftUI/SwiftUI.swift")],
        extraFlags: ["-swift-version", "5"],
        dependencyOutputs: compiledModURLs,
        allowCache: true
      )
    } else {
      // 4. Compile SwiftUI facade
      let swiftUISrc = crossSwiftRoot.appendingPathComponent("Sources/SwiftUI/SwiftUI.swift")
      _ = try compileSwiftModule(
        moduleName: "SwiftUI",
        outputStem: "SwiftUI",
        sources: [swiftUISrc],
        extraFlags: ["-swift-version", "5"],
        dependencyOutputs: [runtimeModURL, harmonyModURL],
        allowCache: true
      )
    }

    // 5. Compile compatible remote/local SwiftPM package library targets and internal targets
    let packageRoots: [URL] = dependencyPackages.isEmpty
      ? project.localPackages.map(\.path)
      : dependencyPackages
    for pkgRoot in packageRoots {
      let targets = PackageDependencyAdapter.listLibraryTargets(in: pkgRoot)
      for targetInfo in targets {
        if compiledModules.contains(targetInfo.name) { continue }
        let targetDir = pkgRoot.appendingPathComponent(targetInfo.relativePath)
        let swiftFiles = collectSwiftFiles(in: targetDir)
        guard !swiftFiles.isEmpty else { continue }
        _ = try compileSwiftModule(
          moduleName: targetInfo.name,
          outputStem: targetInfo.name,
          sources: swiftFiles
        )
        compiledModules.insert(targetInfo.name)
        internalObjectNames.append("\(targetInfo.name).o")
      }
      // Copy any staged *.xcassets catalogs from adapted dependency packages into Resources.
      if let enumerator = fm.enumerator(
        at: pkgRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) {
        for case let url as URL in enumerator {
          if url.pathExtension.lowercased() == "xcassets" {
            let dst = compiledAssets.resourcesDirectory.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) {
              try? fm.copyItem(at: url, to: dst)
            }
            enumerator.skipDescendants()
          }
        }
      }
    }

    func prepareTargetSources(target: ResolvedTarget) throws -> [URL] {
      guard desktopShims else { return target.swiftSources }
      let stageDir = buildRoot.appendingPathComponent("HarmonySources/\(target.name)")
      if fm.fileExists(atPath: stageDir.path) {
        try fm.removeItem(at: stageDir)
      }
      try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
      let rootPrefix = project.projectRootURL.standardizedFileURL.path + "/"
      var usedRel = Set<String>()
      var staged: [URL] = []
      var hasNSCacheAlias = false
      var hasDispatchSourceTimerAlias = false
      for (idx, fileURL) in target.swiftSources.enumerated() {
        let stdPath = fileURL.standardizedFileURL.path
        var relPath = stdPath.hasPrefix(rootPrefix)
          ? String(stdPath.dropFirst(rootPrefix.count))
          : "\(idx)_\(fileURL.lastPathComponent)"
        if !usedRel.insert(relPath).inserted {
          relPath = "\(idx)_\(fileURL.lastPathComponent)"
        }
        let dst = stageDir.appendingPathComponent(relPath)
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
          if content.contains("typealias NSCache ") || content.contains("typealias NSCache=") {
            hasNSCacheAlias = true
          }
          if content.contains("typealias DispatchSourceTimer ")
            || content.contains("typealias DispatchSourceTimer=")
          {
            hasDispatchSourceTimerAlias = true
          }
          let rewritten = SwiftPMBackend.preprocessSwiftSourceForCrossPlatform(content)
          try rewritten.write(to: dst, atomically: true, encoding: .utf8)
        } else {
          try fm.copyItem(at: fileURL, to: dst)
        }
        staged.append(dst)
      }
      if (!hasNSCacheAlias || !hasDispatchSourceTimerAlias) && !target.swiftSources.isEmpty {
        let compatURL = stageDir.appendingPathComponent("CrossSwiftTargetCompat.swift")
        var compatLines = [
          "// AUTO-GENERATED BY CrossXcodeBuild. DO NOT EDIT.",
          "import CrossFoundation",
        ]
        if !hasNSCacheAlias {
          compatLines.append("typealias NSCache = CrossFoundation.NSCache")
        }
        if !hasDispatchSourceTimerAlias {
          compatLines.append("typealias DispatchSourceTimer = CrossFoundation._CrossDispatchSourceTimer")
        }
        try (compatLines.joined(separator: "\n") + "\n").write(to: compatURL, atomically: true, encoding: .utf8)
        staged.append(compatURL)
      }
      return staged
    }

    func languageModeFlags(for target: ResolvedTarget) -> [String] {
      let raw = (target.swiftVersion.isEmpty ? (target.buildSettings["SWIFT_VERSION"] ?? "") : target.swiftVersion)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let major = raw.split(separator: ".").first.flatMap { Int($0) } ?? 5
      if major >= 6 {
        return ["-swift-version", "6"]
      }
      return [
        "-swift-version", "5",
        "-enable-upcoming-feature", "BareSlashRegexLiterals",
        "-enable-upcoming-feature", "IsolatedDefaultValues",
        "-enable-upcoming-feature", "GlobalActorIsolatedTypesUsability",
      ]
    }

    for target in project.internalTargets where !target.swiftSources.isEmpty {
      var flags = languageModeFlags(for: target)
      for cond in target.activeCompilationConditions {
        if cond == "DEBUG" && configuration != .debug { continue }
        flags += ["-D", cond]
      }
      let targetSources = try prepareTargetSources(target: target)
      _ = try compileSwiftModule(
        moduleName: target.name,
        outputStem: target.name,
        sources: targetSources,
        extraFlags: flags
      )
      internalObjectNames.append("\(target.name).o")
    }

    // 6. Synthesize HarmonyAppHost and compile main target
    let mainTarget = project.mainTarget
    let bridgeDir = buildRoot.appendingPathComponent("HarmonyBridge")
    try fm.createDirectory(at: bridgeDir, withIntermediateDirectories: true)

    let appTypeName = detectMainAppTypeName(in: mainTarget.swiftSources) ?? "\(mainTarget.name)App"
    let hostSwiftURL = bridgeDir.appendingPathComponent("HarmonyAppHost.swift")
    try renderHarmonyAppHostSwift(appTypeName: appTypeName, usesDesktopShims: desktopShims).write(
      to: hostSwiftURL, atomically: true, encoding: .utf8
    )

    var mainSources = try prepareTargetSources(target: mainTarget) + [hostSwiftURL]
    if let generatedSymbols = compiledAssets.generatedSymbolsSwiftURL {
      mainSources.append(generatedSymbols)
    }

    var mainFlags = languageModeFlags(for: mainTarget)
    for cond in mainTarget.activeCompilationConditions {
      if cond == "DEBUG" && configuration != .debug { continue }
      mainFlags += ["-D", cond]
    }
    if mainTarget.defaultActorIsolation?.caseInsensitiveCompare("MainActor") == .orderedSame {
      mainFlags += ["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]
    }

    let appObjectURL = try compileSwiftModule(
      moduleName: mainTarget.executableName,
      outputStem: mainTarget.executableName,
      sources: mainSources,
      extraFlags: mainFlags
    )

    return HarmonyBuildArtifacts(
      runtimeDirectory: runtimeDir,
      appObjectURL: appObjectURL,
      internalObjectNames: internalObjectNames,
      staticLinuxSDKURL: sdkURL,
      nativeAPISwiftRoot: nativeAPISwiftRoot,
      usesDesktopShims: desktopShims
    )
  }

  public static func stageProject(
    project: ResolvedXcodeProject,
    harmonyArtifacts: HarmonyBuildArtifacts,
    compiledAssets: CompiledAssets,
    crossSwiftRoot: URL,
    destinationDir: URL,
    quiet: Bool = false
  ) throws -> URL? {
    let fm = FileManager.default
    let target = project.mainTarget
    let displayName = target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName
    let libStem = ProcessRunner.sanitizedSlug(target.executableName)
      .lowercased()
      .replacingOccurrences(of: "-", with: "")
    let nativeLibName = libStem.isEmpty ? "crossswiftapp" : libStem
    let versionCode = Int(target.buildVersion.prefix(while: { $0.isNumber })) ?? 1

    // Copy compiled ARM64 runtime objects and archives into <appDir>/runtime
    let runtimeDest = destinationDir.appendingPathComponent("runtime")
    try fm.copyItem(at: harmonyArtifacts.runtimeDirectory, to: runtimeDest)

    // Create Stage-model HarmonyOS directories
    let appScopeElemDir = destinationDir.appendingPathComponent("AppScope/resources/base/element")
    let appScopeMediaDir = destinationDir.appendingPathComponent("AppScope/resources/base/media")
    let hvigorDir = destinationDir.appendingPathComponent("hvigor")
    let cppDir = destinationDir.appendingPathComponent("entry/src/main/cpp")
    let typesDir = cppDir.appendingPathComponent("types/lib\(nativeLibName)")
    let etsAbilityDir = destinationDir.appendingPathComponent("entry/src/main/ets/entryability")
    let etsPagesDir = destinationDir.appendingPathComponent("entry/src/main/ets/pages")
    let entryElemDir = destinationDir.appendingPathComponent("entry/src/main/resources/base/element")
    let entryMediaDir = destinationDir.appendingPathComponent("entry/src/main/resources/base/media")
    let entryProfileDir = destinationDir.appendingPathComponent("entry/src/main/resources/base/profile")
    let rawfileResDir = destinationDir.appendingPathComponent("entry/src/main/resources/rawfile/Resources")

    for dir in [
      appScopeElemDir, appScopeMediaDir, hvigorDir, cppDir, typesDir,
      etsAbilityDir, etsPagesDir, entryElemDir, entryMediaDir, entryProfileDir,
      rawfileResDir.deletingLastPathComponent(),
    ] {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    try fm.copyItem(at: compiledAssets.resourcesDirectory, to: rawfileResDir)

    let iconSource = compiledAssets.resourcesDirectory.appendingPathComponent("AppIcon.png")
    let fallbackIcon = crossSwiftRoot.appendingPathComponent(
      "Examples/HarmonyRuntimeProbe/AppScope/resources/base/media/icon.png"
    )
    let chosenIcon = fm.fileExists(atPath: iconSource.path) ? iconSource : fallbackIcon
    if fm.fileExists(atPath: chosenIcon.path) {
      try fm.copyItem(at: chosenIcon, to: appScopeMediaDir.appendingPathComponent("icon.png"))
      try fm.copyItem(at: chosenIcon, to: entryMediaDir.appendingPathComponent("icon.png"))
    } else if let placeholderPNG = Data(
      base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    ) {
      try placeholderPNG.write(to: appScopeMediaDir.appendingPathComponent("icon.png"))
      try placeholderPNG.write(to: entryMediaDir.appendingPathComponent("icon.png"))
    }

    try writeText(
      """
      {
        "app": {
          "bundleName": "\(escapeJSON(target.bundleIdentifier))",
          "vendor": "CrossSwiftUI",
          "versionCode": \(versionCode),
          "versionName": "\(escapeJSON(target.marketingVersion))",
          "icon": "$media:icon",
          "label": "$string:app_name"
        }
      }
      """,
      to: destinationDir.appendingPathComponent("AppScope/app.json5")
    )

    let stringJSON = """
    {
      "string": [
        { "name": "app_name", "value": "\(escapeJSON(displayName))" }
      ]
    }
    """
    try writeText(stringJSON, to: appScopeElemDir.appendingPathComponent("string.json"))
    try writeText(stringJSON, to: entryElemDir.appendingPathComponent("string.json"))
    try writeText(
      """
      {
        "color": [
          { "name": "background", "value": "#FFFFFF" }
        ]
      }
      """,
      to: entryElemDir.appendingPathComponent("color.json")
    )
    let sdkRoot = (target.buildSettings["SDKROOT"] ?? "").lowercased()
    let isDesktopApp = harmonyArtifacts.usesDesktopShims && !sdkRoot.contains("iphone")
    let usesFloatingHost = isDesktopApp && target.isAccessoryApp
    let mainPagesJSON = usesFloatingHost
      ? "{ \"src\": [\"pages/Index\", \"pages/HostAnchor\"] }"
      : "{ \"src\": [\"pages/Index\"] }"
    try writeText(
      mainPagesJSON + "\n",
      to: entryProfileDir.appendingPathComponent("main_pages.json")
    )

    let targetSdkVersion = target.buildSettings["HARMONY_SDK_VERSION"]
      ?? ProcessRunner.environmentValue("HARMONY_SDK_VERSION")
      ?? "26.0.0"
    let compatibleSdkVersion = target.buildSettings["HARMONY_COMPATIBLE_SDK_VERSION"]
      ?? ProcessRunner.environmentValue("HARMONY_COMPATIBLE_SDK_VERSION")
      ?? targetSdkVersion
    let rawAbis = target.buildSettings["HARMONY_ABIS"]
      ?? ProcessRunner.environmentValue("HARMONY_ABIS")
      ?? "arm64-v8a"
    let abiList = rawAbis
      .split(whereSeparator: { $0 == "," || $0 == " " })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let abiJSON = (abiList.isEmpty ? ["arm64-v8a"] : abiList)
      .map { "\"\(escapeJSON($0))\"" }
      .joined(separator: ", ")

    try writeText(
      """
      {
        "app": {
          "products": [
            {
              "name": "default",
              "targetSdkVersion": "\(escapeJSON(targetSdkVersion))",
              "compatibleSdkVersion": "\(escapeJSON(compatibleSdkVersion))",
              "runtimeOS": "HarmonyOS",
              "buildOption": {
                "strictMode": { "caseSensitiveCheck": true, "useNormalizedOHMUrl": true }
              }
            }
          ],
          "buildModeSet": [
            { "name": "debug" },
            { "name": "release" }
          ]
        },
        "modules": [
          { "name": "entry", "srcPath": "./entry", "targets": [
            { "name": "default", "applyToProducts": ["default"] }
          ] }
        ]
      }
      """,
      to: destinationDir.appendingPathComponent("build-profile.json5")
    )

    try writeText(
      """
      {
        "modelVersion": "\(escapeJSON(targetSdkVersion))",
        "name": "\(escapeJSON(nativeLibName))",
        "version": "\(escapeJSON(target.marketingVersion))",
        "dependencies": {}
      }
      """,
      to: destinationDir.appendingPathComponent("oh-package.json5")
    )

    try writeText(
      "import { appTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: appTasks };\n",
      to: destinationDir.appendingPathComponent("hvigorfile.ts")
    )
    try writeText(
      """
      {
        "modelVersion": "\(escapeJSON(targetSdkVersion))",
        "dependencies": {},
        "execution": { "daemon": false, "parallel": false },
        "nodeOptions": { "maxOldSpaceSize": 2048 }
      }
      """,
      to: hvigorDir.appendingPathComponent("hvigor-config.json5")
    )

    try writeText(
      """
      {
        "apiType": "stageMode",
        "buildOption": {
          "externalNativeOptions": {
            "path": "./src/main/cpp/CMakeLists.txt",
            "abiFilters": [\(abiJSON)]
          }
        },
        "targets": [{ "name": "default" }]
      }
      """,
      to: destinationDir.appendingPathComponent("entry/build-profile.json5")
    )
    try writeText(
      "import { hapTasks } from '@ohos/hvigor-ohos-plugin';\nexport default { system: hapTasks };\n",
      to: destinationDir.appendingPathComponent("entry/hvigorfile.ts")
    )
    try writeText(
      """
      {
        "name": "entry",
        "version": "\(escapeJSON(target.marketingVersion))",
        "dependencies": {
          "lib\(nativeLibName).so": "file:./src/main/cpp/types/lib\(nativeLibName)"
        }
      }
      """,
      to: destinationDir.appendingPathComponent("entry/oh-package.json5")
    )

    let deviceTypesJSON = isDesktopApp ? "\"2in1\"" : "\"phone\", \"tablet\", \"2in1\""
    let launchTypeLine = isDesktopApp ? "\n              \"launchType\": \"singleton\"," : ""
    let permissionsBlock = isDesktopApp
      ? ",\n          \"requestPermissions\": [{ \"name\": \"ohos.permission.SET_WINDOW_TRANSPARENT\" }]"
      : ""

    try writeText(
      """
      {
        "module": {
          "name": "entry",
          "type": "entry",
          "mainElement": "EntryAbility",
          "deviceTypes": [\(deviceTypesJSON)],
          "deliveryWithInstall": true,
          "installationFree": false,
          "pages": "$profile:main_pages",
          "abilities": [
            {
              "name": "EntryAbility",\(launchTypeLine)
              "srcEntry": "./ets/entryability/EntryAbility.ets",
              "icon": "$media:icon",
              "label": "$string:app_name",
              "startWindowIcon": "$media:icon",
              "startWindowBackground": "$color:background",
              "exported": true,
              "skills": [{ "entities": ["entity.system.home"], "actions": ["ohos.want.action.home"] }]
            }
          ]\(permissionsBlock)
        }
      }
      """,
      to: destinationDir.appendingPathComponent("entry/src/main/module.json5")
    )

    try writeText(
      """
      {
        "name": "lib\(nativeLibName).so",
        "types": "./Index.d.ts",
        "version": "1.0.0",
        "description": "CrossSwiftUI HarmonyOS native module"
      }
      """,
      to: typesDir.appendingPathComponent("oh-package.json5")
    )
    try writeText(
      """
      export const attachNativeAPI: (context: Object) => boolean;
      export const detachNativeAPI: (context: Object) => boolean;
      export const notifyLifecycle: (context: Object, state: number) => boolean;
      export const attachWindowStage: (stage: Object) => boolean;
      export const attachFloatingWindow: (win: Object) => boolean;
      export const attachSurfaceWindow: (surfaceId: number, win: Object) => boolean;
      export const registerWindowHost: (host: Object) => void;
      export const configureResources: (directory: string, language: string) => void;
      export const mountApp: (onTree: (json: string) => void, width: number, height: number, scale: number) => void;
      export const resizeApp: (width: number, height: number) => void;
      export const setColorScheme: (isDark: boolean) => void;
      export const appEvent: (id: number, event: number, text: string) => void;
      export const unmountApp: () => void;
      export const mountSurface: (surfaceId: number, onTree: (json: string) => void, width: number, height: number, scale: number) => void;
      export const resizeSurface: (surfaceId: number, width: number, height: number) => void;
      export const surfaceEvent: (surfaceId: number, id: number, event: number, text: string) => void;
      export const unmountSurface: (surfaceId: number) => void;
      export const reopenApp: () => void;
      """,
      to: typesDir.appendingPathComponent("Index.d.ts")
    )

    var cShimSources: [String] = []
    var cShimIncludeDirs: [String] = []
    if harmonyArtifacts.usesDesktopShims {
      let cShimSpecs: [(name: String, relDir: String, cFile: String)] = [
        ("CDarwinShims", "Sources/AppleShims/CDarwinShims", "CDarwinShims.c"),
        ("Carbon", "Sources/Carbon", "Carbon.c"),
        ("IOKit", "Sources/AppleShims/IOKit", "IOKit.c"),
        ("SQLite3", "Sources/SQLite3", "SQLite3.c"),
      ]
      let cShimsDestRoot = cppDir.appendingPathComponent("cshims")
      for spec in cShimSpecs {
        let srcDir = crossSwiftRoot.appendingPathComponent(spec.relDir)
        let srcC = srcDir.appendingPathComponent(spec.cFile)
        guard fm.fileExists(atPath: srcC.path) else { continue }
        let dstDir = cShimsDestRoot.appendingPathComponent(spec.name)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        try fm.copyItem(at: srcC, to: dstDir.appendingPathComponent(spec.cFile))
        let srcInc = srcDir.appendingPathComponent("include")
        if fm.fileExists(atPath: srcInc.path) {
          try fm.copyItem(at: srcInc, to: dstDir.appendingPathComponent("include"))
          cShimIncludeDirs.append("\"${CMAKE_CURRENT_SOURCE_DIR}/cshims/\(spec.name)/include\"")
        }
        cShimSources.append("cshims/\(spec.name)/\(spec.cFile)")
      }
    }

    let objectList = (
      ["SwiftUIRuntime.o", "SwiftUIHarmony.o", "SwiftUI.o"]
      + harmonyArtifacts.internalObjectNames
      + ["\(target.executableName).o"]
    ).map { "\"${SWIFT_INPUTS}/\($0)\"" }.joined(separator: " ")
    let cShimSourceList = cShimSources.isEmpty ? "" : " " + cShimSources.joined(separator: " ")
    let cShimIncludeBlock = cShimIncludeDirs.isEmpty
      ? ""
      : "target_include_directories(\(nativeLibName) PRIVATE \(cShimIncludeDirs.joined(separator: " ")))\n"

    try writeText(
      """
      cmake_minimum_required(VERSION 3.16)
      project(\(nativeLibName) LANGUAGES C CXX)

      set(SWIFT_INPUTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../runtime")
      set(NATIVEAPI_SWIFT_PATH "$ENV{NATIVEAPI_SWIFT_PATH}")
      if(NOT NATIVEAPI_SWIFT_PATH)
        set(NATIVEAPI_SWIFT_PATH "\(harmonyArtifacts.nativeAPISwiftRoot.path)")
      endif()
      add_subdirectory("${NATIVEAPI_SWIFT_PATH}/ohos" nativeapi-swift-ohos)

      add_library(\(nativeLibName) SHARED app_host.cpp\(cShimSourceList) \(objectList))
      \(cShimIncludeBlock)target_compile_features(\(nativeLibName) PRIVATE cxx_std_17)
      target_link_options(\(nativeLibName) PRIVATE -Wl,--no-undefined -Wl,--exclude-libs,ALL -Wl,--wrap=_CFProcessPath)
      set(CROSSSWIFT_OPTIONAL_ARCHIVES)
      foreach(archive_name
        libswiftObservation.a
        libswiftSwiftOnoneSupport.a
        libswiftRegexBuilder.a
        libFoundationNetworking.a
        lib_CFURLSessionInterface.a
        libFoundationXML.a
        lib_CFXMLInterface.a
        libcurl.a
        libssl.a
        libcrypto.a
        libxml2.a
      )
        if(EXISTS "${SWIFT_INPUTS}/${archive_name}")
          list(APPEND CROSSSWIFT_OPTIONAL_ARCHIVES "${SWIFT_INPUTS}/${archive_name}")
        endif()
      endforeach()
      if(CROSSSWIFT_OPTIONAL_ARCHIVES)
        target_link_libraries(\(nativeLibName) PRIVATE -Wl,--start-group ${CROSSSWIFT_OPTIONAL_ARCHIVES} -Wl,--end-group)
      endif()
      nativeapi_target_link_swift_ohos(\(nativeLibName) "${SWIFT_INPUTS}")
      if(CROSSSWIFT_OPTIONAL_ARCHIVES)
        target_link_libraries(\(nativeLibName) PRIVATE -Wl,--start-group ${CROSSSWIFT_OPTIONAL_ARCHIVES} -Wl,--end-group)
      endif()
      target_link_libraries(\(nativeLibName) PRIVATE
        libace_napi.z.so
        ace_ndk.z
        native_drawing
        c++_shared
        uv
        z
        dl
        m
      )
      """,
      to: cppDir.appendingPathComponent("CMakeLists.txt")
    )

    try writeText(
      renderAppHostCpp(nativeLibName: nativeLibName),
      to: cppDir.appendingPathComponent("app_host.cpp")
    )

    let harmonyWindowHostClass: String = isDesktopApp
      ? """
      interface WindowSpec {
        surfaceId: number;
        title: string;
        x: number;
        y: number;
        width: number;
        height: number;
        isTransparent: boolean;
        isTitled: boolean;
        isResizable: boolean;
        isFloating: boolean;
        focus: boolean;
      }

      class HarmonyWindowHost {
        private stage: window.WindowStage;
        private anchor: window.Window | undefined;
        private defaultTitle: string;
        private windows: Map<number, window.Window> = new Map<number, window.Window>();
        private transparentIds: Set<number> = new Set<number>();
        private visibleIds: Set<number> = new Set<number>();
        private creatingIds: Set<number> = new Set<number>();
        private pendingSpecs: Map<number, WindowSpec> = new Map<number, WindowSpec>();
        private pendingDestroy: Set<number> = new Set<number>();

        constructor(stage: window.WindowStage, anchor: window.Window | undefined, defaultTitle: string) {
          this.stage = stage;
          this.anchor = anchor;
          this.defaultTitle = defaultTitle;
        }

        registerExisting(surfaceId: number, win: window.Window, isTransparent: boolean): void {
          this.windows.set(surfaceId, win);
          if (isTransparent) {
            this.transparentIds.add(surfaceId);
          } else {
            this.transparentIds.delete(surfaceId);
          }
          this.visibleIds.add(surfaceId);
          win.on('windowRectChange', (data: window.RectChangeOptions) => {
            if (this.visibleIds.has(surfaceId) && (surfaceId === 0 || !this.visibleIds.has(0))) {
              this.syncAnchorToRect(surfaceId, data.rect);
            }
          });
        }

        private syncAnchorToRect(surfaceId: number, rect: window.Rect): void {
          if (!this.anchor) return;
          const win = this.windows.get(surfaceId);
          if (!win) return;
          try {
            const scale = win.getWindowDensityInfo().systemDensity || 1;
            const side = Math.max(76, Math.ceil(40 * scale));
            if (rect.width < side || rect.height < side) return;
            const isTrans = this.transparentIds.has(surfaceId);
            const bleedPx = isTrans ? Math.round(24 * scale) : 0;
            const contentLeft = rect.left + bleedPx;
            const contentTop = rect.top + bleedPx + (isTrans ? Math.round(8 * scale) : Math.round(48 * scale));
            const contentW = Math.max(side, rect.width - bleedPx * 2);
            const ax = contentLeft + Math.min(Math.round(80 * scale), Math.max(0, Math.floor((contentW - side) / 2)));
            this.anchor.moveWindowTo(ax, contentTop).catch(() => {});
          } catch {}
        }

        syncAnchorToAnyVisible(): void {
          if (!this.anchor) return;
          let targetId: number | undefined = undefined;
          if (this.visibleIds.has(0) && this.windows.has(0)) {
            targetId = 0;
          } else {
            this.visibleIds.forEach((id: number) => {
              if (targetId === undefined && this.windows.has(id)) {
                targetId = id;
              }
            });
          }
          if (targetId === undefined) {
            this.anchor.minimize().catch(() => {});
            return;
          }
          const win = this.windows.get(targetId);
          if (!win) return;
          try {
            this.syncAnchorToRect(targetId, win.getWindowProperties().windowRect);
          } catch {}
        }

        reconcileVisibility(): void {
          if (this.visibleIds.size === 0) {
            nativeApp.reopenApp();
            return;
          }
          if (!this.visibleIds.has(0) && this.visibleIds.size > 0) {
            const w0 = this.windows.get(0);
            if (w0) {
              w0.minimize().catch(() => {});
            }
          }
          this.syncAnchorToAnyVisible();
        }

        private async applyBounds(
          win: window.Window,
          x: number,
          y: number,
          width: number,
          height: number,
          isTitled: boolean
        ): Promise<void> {
          try {
            const scale = win.getWindowDensityInfo().systemDensity || 1;
            const px = Math.max(0, Math.round(x * scale));
            const py = Math.max(0, Math.round(y * scale));
            const pw = Math.max(48, Math.round(width * scale));
            const ph = Math.max(48, Math.round(height * scale));
            await win.moveWindowTo(px, py);
            await win.resize(pw, ph);
          } catch (error) {
            hilog.warn(0x0000, 'CrossSwiftUI', 'applyBounds note: %{public}s', String(error));
          }
        }

        openWindow(
          surfaceId: number,
          title: string,
          x: number,
          y: number,
          width: number,
          height: number,
          isTransparent: boolean,
          isTitled: boolean,
          isResizable: boolean,
          isFloating: boolean,
          focus: boolean
        ): void {
          const spec: WindowSpec = {
            surfaceId,
            title,
            x,
            y,
            width,
            height,
            isTransparent,
            isTitled,
            isResizable,
            isFloating,
            focus
          };
          this.pendingDestroy.delete(surfaceId);
          this.visibleIds.add(surfaceId);
          if (isTransparent) {
            this.transparentIds.add(surfaceId);
          } else {
            this.transparentIds.delete(surfaceId);
          }

          const existing = this.windows.get(surfaceId);
          if (existing) {
            this.applyBounds(existing, x, y, width, height, isTitled).then(() => {
              existing.showWindow().then(() => {
                this.syncAnchorToAnyVisible();
              }).catch(() => {});
            }).catch(() => {});
            return;
          }

          if (this.creatingIds.has(surfaceId)) {
            this.pendingSpecs.set(surfaceId, spec);
            return;
          }

          this.creatingIds.add(surfaceId);
          this.createSecondaryWindow(spec);
        }

        private async createSecondaryWindow(spec: WindowSpec): Promise<void> {
          try {
            const winName = spec.surfaceId === 0 ? 'CrossSwiftFloating' : `CrossSwiftWin_${spec.surfaceId}`;
            const options: window.SubWindowOptions = {
              title: spec.title.length > 0 ? spec.title : this.defaultTitle,
              decorEnabled: spec.isTitled,
              maximizeSupported: spec.isTitled && spec.isResizable
            };
            if (!spec.isTitled && spec.isFloating) {
              options.zLevel = 100;
            }
            const sub = await this.stage.createSubWindowWithOptions(winName, options);
            if (this.pendingDestroy.has(spec.surfaceId)) {
              this.pendingDestroy.delete(spec.surfaceId);
              try { await sub.destroyWindow(); } catch {}
              return;
            }
            const latest = this.pendingSpecs.get(spec.surfaceId) ?? spec;
            this.pendingSpecs.delete(spec.surfaceId);

            if (latest.isTransparent) {
              try { await sub.setWindowLimits({ minWidth: 1, minHeight: 1, pixelUnit: window.PixelUnit.PX }, true); } catch {}
              try { sub.setWindowDecorVisible(false); } catch {}
              try { sub.setWindowBackgroundColor('#00000000'); } catch {}
              try { sub.setWindowShadowRadius(0); } catch {}
              try { await sub.setWindowCornerRadius(0); } catch {}
              try { await sub.setWindowShadowEnabled(false); } catch {}
            } else {
              const isDark = AppStorage.get<boolean>('crossSwiftIsDark') ?? false;
              try { sub.setWindowBackgroundColor(isDark ? '#ff1b1b1f' : '#fff6f6f8'); } catch {}
              try { sub.setResizeByDragEnabled(latest.isResizable); } catch {}
            }

            await this.applyBounds(sub, latest.x, latest.y, latest.width, latest.height, latest.isTitled);

            const storage = new LocalStorage();
            storage.setOrCreate('crossSwiftSurfaceId', latest.surfaceId);
            nativeApp.attachSurfaceWindow(latest.surfaceId, sub);
            await sub.loadContent('pages/Index', storage);

            if (latest.isTransparent) {
              try { sub.setWindowBackgroundColor('#00000000'); } catch {}
              try { sub.setWindowShadowRadius(0); } catch {}
              try { await sub.setWindowCornerRadius(0); } catch {}
              try { await sub.setWindowShadowEnabled(false); } catch {}
            }

            if (this.pendingDestroy.has(latest.surfaceId)) {
              this.pendingDestroy.delete(latest.surfaceId);
              try { await sub.destroyWindow(); } catch {}
              return;
            }

            this.windows.set(latest.surfaceId, sub);
            sub.on('windowRectChange', (data: window.RectChangeOptions) => {
              if (this.visibleIds.has(latest.surfaceId) && (!this.visibleIds.has(0) || latest.surfaceId === 0)) {
                this.syncAnchorToRect(latest.surfaceId, data.rect);
              }
            });
            sub.on('windowEvent', (ev: window.WindowEventType) => {
              if (ev === window.WindowEventType.WINDOW_DESTROYED || ev === window.WindowEventType.WINDOW_HIDDEN) {
                this.visibleIds.delete(latest.surfaceId);
                if (ev === window.WindowEventType.WINDOW_DESTROYED) {
                  this.windows.delete(latest.surfaceId);
                  this.transparentIds.delete(latest.surfaceId);
                }
                this.syncAnchorToAnyVisible();
              }
            });
            await sub.showWindow();

            const afterSpec = this.pendingSpecs.get(latest.surfaceId);
            if (afterSpec) {
              this.pendingSpecs.delete(latest.surfaceId);
              await this.applyBounds(sub, afterSpec.x, afterSpec.y, afterSpec.width, afterSpec.height, afterSpec.isTitled);
            }
            this.syncAnchorToAnyVisible();

            if (latest.surfaceId !== 0 && !this.visibleIds.has(0)) {
              const w0 = this.windows.get(0);
              if (w0) {
                w0.minimize().catch(() => {});
              }
            }
          } catch (error) {
            hilog.error(0x0000, 'CrossSwiftUI', 'openWindow(%{public}d) failed: %{public}s', spec.surfaceId, String(error));
          } finally {
            this.creatingIds.delete(spec.surfaceId);
          }
        }

        updateBounds(surfaceId: number, x: number, y: number, width: number, height: number): void {
          if (this.creatingIds.has(surfaceId)) {
            const pending = this.pendingSpecs.get(surfaceId);
            if (pending) {
              pending.x = x;
              pending.y = y;
              pending.width = width;
              pending.height = height;
            }
            return;
          }
          const win = this.windows.get(surfaceId);
          if (!win) return;
          const isTitled = !this.transparentIds.has(surfaceId);
          this.applyBounds(win, x, y, width, height, isTitled);
        }

        focusWindow(surfaceId: number): void {
          const win = this.windows.get(surfaceId);
          if (!win || !this.visibleIds.has(surfaceId)) return;
          win.showWindow().catch(() => {});
        }

        hideWindow(surfaceId: number): void {
          this.visibleIds.delete(surfaceId);
          if (surfaceId !== 0) {
            this.destroyWindow(surfaceId);
            return;
          }
          const win = this.windows.get(0);
          if (win) {
            win.minimize().catch(() => {});
          }
          this.syncAnchorToAnyVisible();
        }

        destroyWindow(surfaceId: number): void {
          this.visibleIds.delete(surfaceId);
          this.pendingSpecs.delete(surfaceId);
          if (surfaceId === 0) {
            const win = this.windows.get(0);
            if (win) {
              win.minimize().catch(() => {});
            }
            return;
          }
          this.transparentIds.delete(surfaceId);
          if (this.creatingIds.has(surfaceId)) {
            this.pendingDestroy.add(surfaceId);
            return;
          }
          const win = this.windows.get(surfaceId);
          if (!win) return;
          this.windows.delete(surfaceId);
          win.destroyWindow().then(() => {
            this.syncAnchorToAnyVisible();
          }).catch(() => {
            this.syncAnchorToAnyVisible();
          });
        }
      }


      """
      : ""

    let entryAbilityFields: String
    let entryAbilityConfigHook: String
    let entryAbilityForegroundHook: String
    let entryAbilityWindowStageBody: String
    if usesFloatingHost {
      try writeText(
        """
        @Entry
        @Component
        struct HostAnchor {
          @StorageProp('crossSwiftIsDark') isDark: boolean = false;

          build() {
            Stack()
              .width('100%')
              .height('100%')
              .backgroundColor(this.isDark ? '#ff26262b' : '#fff5f5fa')
          }
        }
        """,
        to: etsPagesDir.appendingPathComponent("HostAnchor.ets")
      )
      entryAbilityFields = """
        private anchorWindow: window.Window | undefined = undefined;
        private windowHost: HarmonyWindowHost | undefined = undefined;

        private applyAnchorColor(isDark: boolean): void {
          if (!this.anchorWindow) return;
          const hex = isDark ? '#26262B' : '#F5F5FA';
          const argb = isDark ? '#FF26262B' : '#FFF5F5FA';
          try { this.anchorWindow.setWindowContainerColor(hex, hex); } catch {}
          try { this.anchorWindow.setWindowBackgroundColor(argb); } catch {}
        }

      """
      entryAbilityConfigHook = "\n          this.applyAnchorColor(isDark);"
      entryAbilityForegroundHook = "\n          this.windowHost?.reconcileVisibility();"
      entryAbilityWindowStageBody = """
          stage.loadContent('pages/HostAnchor').then(async () => {
            try {
              const mainWin = stage.getMainWindowSync();
              this.anchorWindow = mainWin;
              const isDark = AppStorage.get<boolean>('crossSwiftIsDark') ?? false;
              try { mainWin.setWindowDecorVisible(false); } catch {}
              this.applyAnchorColor(isDark);
              try { await mainWin.setWindowShadowEnabled(false); } catch {}
              try { await mainWin.setWindowLimits({ minWidth: 1, minHeight: 1, pixelUnit: window.PixelUnit.PX }, true); } catch {}
              const d = mainWin.getWindowDensityInfo().systemDensity || 1;
              const anchorSide = Math.max(76, Math.ceil(40 * d));
              try { await mainWin.resize(anchorSide, anchorSide); } catch {}
              try { await mainWin.setWindowTouchable(false); } catch {}
              try { await mainWin.setWindowFocusable(false); } catch {}

              const host = new HarmonyWindowHost(stage, mainWin, '\(escapeJSON(displayName))');
              this.windowHost = host;
              nativeApp.registerWindowHost(host);

              const sub = await stage.createSubWindowWithOptions('CrossSwiftFloating', {
                title: '\(escapeJSON(displayName))',
                decorEnabled: false,
                isModal: false
              });
              host.registerExisting(0, sub, true);
              nativeApp.attachFloatingWindow(sub);
              const storage = new LocalStorage();
              storage.setOrCreate('crossSwiftSurfaceId', 0);
              await sub.loadContent('pages/Index', storage);
              try { sub.setWindowBackgroundColor('#00000000'); } catch {}
              try { sub.setWindowShadowRadius(0); } catch {}
              try { await sub.setWindowCornerRadius(0); } catch {}
              try { await sub.setWindowShadowEnabled(false); } catch {}
              await sub.showWindow();
              host.syncAnchorToAnyVisible();
            } catch (error) {
              hilog.error(0x0000, 'CrossSwiftUI', 'Could not launch floating host: %{public}s', String(error));
            }
          }).catch((error: Error) => {
            hilog.error(0x0000, 'CrossSwiftUI', 'Could not load HostAnchor page: %{public}s', error.message);
          });
      """
    } else if isDesktopApp {
      entryAbilityFields = """
        private windowHost: HarmonyWindowHost | undefined = undefined;

      """
      entryAbilityConfigHook = ""
      entryAbilityForegroundHook = "\n          this.windowHost?.reconcileVisibility();"
      entryAbilityWindowStageBody = """
          const host = new HarmonyWindowHost(stage, undefined, '\(escapeJSON(displayName))');
          this.windowHost = host;
          nativeApp.registerWindowHost(host);
          const storage = new LocalStorage();
          storage.setOrCreate('crossSwiftSurfaceId', 0);
          stage.loadContent('pages/Index', storage).then(() => {
            try {
              const mainWin = stage.getMainWindowSync();
              host.registerExisting(0, mainWin, false);
            } catch {}
          }).catch((error: Error) => {
            hilog.error(0x0000, 'CrossSwiftUI', 'Could not load Index page: %{public}s', error.message);
          });
      """
    } else {
      entryAbilityFields = ""
      entryAbilityConfigHook = ""
      entryAbilityForegroundHook = ""
      entryAbilityWindowStageBody = """
          stage.loadContent('pages/Index').then(() => {
          }).catch((error: Error) => {
            hilog.error(0x0000, 'CrossSwiftUI', 'Could not load Index page: %{public}s', error.message);
          });
      """
    }

    try writeText(
      """
      import { Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
      import { fileIo as fs } from '@kit.CoreFileKit';
      import { i18n } from '@kit.LocalizationKit';
      import { hilog } from '@kit.PerformanceAnalysisKit';
      import { window } from '@kit.ArkUI';
      import nativeApp from 'lib\(nativeLibName).so';

      \(harmonyWindowHostClass)export default class EntryAbility extends UIAbility {
      \(entryAbilityFields)  private extractRawResources(): string {
          const destRoot = `${this.context.filesDir}/CrossSwiftResources`;
          try {
            if (!fs.accessSync(destRoot)) {
              fs.mkdirSync(destRoot, true);
            }
            const rm = this.context.resourceManager;
            const copyTree = (rawRel: string, dstDir: string) => {
              let entries: string[] = [];
              try {
                entries = rm.getRawFileListSync(rawRel);
              } catch {
                return;
              }
              if (!fs.accessSync(dstDir)) {
                fs.mkdirSync(dstDir, true);
              }
              for (const name of entries) {
                const childRaw = rawRel.length > 0 ? `${rawRel}/${name}` : name;
                const childDst = `${dstDir}/${name}`;
                try {
                  const data = rm.getRawFileContentSync(childRaw);
                  const file = fs.openSync(childDst, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
                  fs.writeSync(file.fd, data.buffer);
                  fs.closeSync(file.fd);
                } catch {
                  copyTree(childRaw, childDst);
                }
              }
            };
            const contentsDir = `${destRoot}/Contents`;
            const resourcesDir = `${contentsDir}/Resources`;
            copyTree('Resources', resourcesDir);
            try {
              const infoData = rm.getRawFileContentSync('Resources/Info.plist');
              const infoFile = fs.openSync(`${contentsDir}/Info.plist`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
              fs.writeSync(infoFile.fd, infoData.buffer);
              fs.closeSync(infoFile.fd);
            } catch {}
          } catch (error) {
            hilog.warn(0x0000, 'CrossSwiftUI', 'Resource staging note: %{public}s', String(error));
          }
          return destRoot;
        }

        onCreate(_want: Want): void {
          if (!nativeApp.attachNativeAPI(this.context)) {
            throw new Error('Could not attach the UIAbility context to NativeAPI');
          }
          const isDark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
          AppStorage.setOrCreate('crossSwiftIsDark', isDark);
          const resourcesDir = this.extractRawResources();
          let language = 'en';
          try {
            language = i18n.System.getSystemLocale();
          } catch {
            language = 'en';
          }
          nativeApp.configureResources(resourcesDir, language);
        }

        onNewWant(_want: Want): void {\(entryAbilityForegroundHook)
        }

        onConfigurationUpdate(newConfig: Configuration): void {
          const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
          AppStorage.setOrCreate('crossSwiftIsDark', isDark);\(entryAbilityConfigHook)
        }

        onForeground(): void {
          nativeApp.notifyLifecycle(this.context, 1);\(entryAbilityForegroundHook)
        }

        onBackground(): void {
          nativeApp.notifyLifecycle(this.context, 2);
        }

        onDestroy(): void {
          nativeApp.detachNativeAPI(this.context);
        }

        onWindowStageCreate(stage: window.WindowStage): void {
          nativeApp.attachWindowStage(stage);
      \(entryAbilityWindowStageBody)
        }
      }
      """,
      to: etsAbilityDir.appendingPathComponent("EntryAbility.ets")
    )

    let defaultStyle = sdkRoot.contains("iphone") ? "ios" : "harmony"
    let initialUIStyle = (target.buildSettings["HARMONY_UI_STYLE"]
      ?? ProcessRunner.environmentValue("HARMONY_UI_STYLE")
      ?? defaultStyle).lowercased() == "harmony" ? "harmony" : "ios"

    let hostTemplate = crossSwiftRoot.appendingPathComponent(
      "Sources/SwiftUIHarmony/ArkTS/CrossSwiftUIHost.ets"
    )
    guard let rawEts = try? String(contentsOf: hostTemplate, encoding: .utf8) else {
      throw BuildBackendError.toolMissing(
        "Missing HarmonyOS ArkTS host template at '\(hostTemplate.path)'."
      )
    }
    let adapted = rawEts
      .replacingOccurrences(of: "{{NATIVE_LIB_NAME}}", with: nativeLibName)
      .replacingOccurrences(of: "{{INITIAL_UI_STYLE}}", with: initialUIStyle)
      .replacingOccurrences(of: "{{IS_DESKTOP}}", with: isDesktopApp ? "true" : "false")
    try writeText(adapted, to: etsPagesDir.appendingPathComponent("Index.ets"))

    // If DevEco Studio is installed, assemble the HAP automatically.
    if let devEcoHome = locateDevEcoStudioHome() {
      let hvigorScript = devEcoHome.appendingPathComponent("tools/hvigor/bin/hvigorw.js")
      let nodeBin = devEcoHome.appendingPathComponent("tools/node/bin/node")
      let ohpmBin = devEcoHome.appendingPathComponent("tools/ohpm/bin/ohpm")
      let javaHome = devEcoHome.appendingPathComponent("jbr/Contents/Home")
      var pathEntries = [
        devEcoHome.appendingPathComponent("tools/node/bin").path,
        devEcoHome.appendingPathComponent("tools/ohpm/bin").path,
        javaHome.appendingPathComponent("bin").path,
      ]
      if let existing = ProcessRunner.environmentValue("PATH"), !existing.isEmpty {
        pathEntries.append(existing)
      }
      let env = [
        "DEVECO_SDK_HOME": devEcoHome.appendingPathComponent("sdk").path,
        "JAVA_HOME": javaHome.path,
        "NATIVEAPI_SWIFT_PATH": harmonyArtifacts.nativeAPISwiftRoot.path,
        "PATH": pathEntries.joined(separator: ":"),
      ]
      if fm.isExecutableFile(atPath: ohpmBin.path) {
        if !quiet {
          ProcessRunner.writeStdoutLine("Installing HarmonyOS packages (ohpm)...")
        }
        let ohpmRes = try ProcessRunner.run(
          executable: ohpmBin,
          arguments: ["install", "--all"],
          workingDirectory: destinationDir,
          environmentOverrides: env,
          echoOutput: !quiet
        )
        if ohpmRes.exitCode != 0 {
          throw ProcessRunnerError.commandFailed(
            command: "\(ohpmBin.path) install --all",
            exitCode: ohpmRes.exitCode,
            output: ohpmRes.stdout + "\n" + ohpmRes.stderr
          )
        }
      }
      if fm.isExecutableFile(atPath: nodeBin.path) && fm.fileExists(atPath: hvigorScript.path) {
        if !quiet {
          ProcessRunner.writeStdoutLine("Assembling HarmonyOS HAP (hvigorw)...")
        }
        let hvRes = try ProcessRunner.run(
          executable: nodeBin,
          arguments: [
            hvigorScript.path, "--mode", "module", "-p", "product=default", "assembleHap", "--no-daemon",
          ],
          workingDirectory: destinationDir,
          environmentOverrides: env,
          echoOutput: !quiet
        )
        if hvRes.exitCode != 0 {
          throw ProcessRunnerError.commandFailed(
            command: "\(nodeBin.path) \(hvigorScript.path) assembleHap",
            exitCode: hvRes.exitCode,
            output: hvRes.stdout + "\n" + hvRes.stderr
          )
        }
        let hapSrc = destinationDir.appendingPathComponent(
          "entry/build/default/outputs/default/entry-default-unsigned.hap"
        )
        if fm.fileExists(atPath: hapSrc.path) {
          let hapDest = destinationDir.appendingPathComponent("\(target.productName).hap")
          if fm.fileExists(atPath: hapDest.path) { try? fm.removeItem(at: hapDest) }
          try fm.copyItem(at: hapSrc, to: hapDest)
          return hapDest
        }
      }
    }

    return nil
  }

  private static func locateDevEcoStudioHome() -> URL? {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let env = ProcessRunner.environmentValue("DEVECO_STUDIO_HOME"), !env.isEmpty {
      candidates.append(URL(fileURLWithPath: env))
    }
    candidates.append(URL(fileURLWithPath: "/Applications/DevEco-Studio.app/Contents"))
    for candidate in candidates {
      if fm.fileExists(atPath: candidate.appendingPathComponent("tools/hvigor/bin/hvigorw.js").path) {
        return candidate
      }
    }
    return nil
  }

  private static func renderAppHostCpp(nativeLibName: String) -> String {
    """
    #include <algorithm>
    #include <cmath>
    #include <cstdint>
    #include <cstdlib>
    #include <cstring>
    #include <fstream>
    #include <memory>
    #include <string>
    #include <sys/stat.h>
    #include <unistd.h>
    #include <unordered_map>
    #include <vector>
    #include <zlib.h>
    #include <napi/native_api.h>
    #include <native_drawing/drawing_bitmap.h>
    #include <native_drawing/drawing_brush.h>
    #include <native_drawing/drawing_canvas.h>
    #include <native_drawing/drawing_color.h>
    #include <native_drawing/drawing_font_collection.h>
    #include <native_drawing/drawing_path.h>
    #include <native_drawing/drawing_pen.h>
    #include <native_drawing/drawing_text_typography.h>
    #include "../../application.h"
    #include "ohos_application.h"
    #include "ohos_runtime.h"
    #include "swift_ohos_runtime.h"

    namespace nativeapi::ohos {
    bool AttachWindowStage(napi_env env, napi_value stage);
    std::shared_ptr<nativeapi::Window> AttachWindow(
        napi_env env, napi_value window, nativeapi::WindowId parent, bool primary);
    }

    using Update = void (*)(void*, const char*);
    extern "C" void swift_configure_resources(const char* directory, const char* language);
    extern "C" void swift_mount_app(void* context, Update update, double width, double height,
                                    double pixelsPerPoint);
    extern "C" void swift_mount_surface(std::int32_t surfaceId, void* context, Update update,
                                        double width, double height, double pixelsPerPoint);
    extern "C" void swift_resize_app(double width, double height);
    extern "C" void swift_resize_surface(std::int32_t surfaceId, double width, double height);
    extern "C" void swift_set_color_scheme(std::int32_t isDark);
    extern "C" void swift_app_event(std::intptr_t id, std::int32_t event, const char* text);
    extern "C" void swift_surface_event(std::int32_t surfaceId, std::intptr_t id,
                                        std::int32_t event, const char* text);
    extern "C" void swift_unmount_app();
    extern "C" void swift_unmount_surface(std::int32_t surfaceId);
    extern "C" __attribute__((weak)) void swift_harmony_window_attached(
        std::int32_t surfaceId, std::uint32_t windowId);
    extern "C" __attribute__((weak)) void swift_reopen_app();

    namespace {
    struct SurfaceSlot {
      std::int32_t surfaceId = 0;
      napi_env env = nullptr;
      napi_ref callback = nullptr;
    };

    std::unordered_map<std::int32_t, std::unique_ptr<SurfaceSlot>> g_surfaces;
    napi_env g_host_env = nullptr;
    napi_ref g_window_host = nullptr;
    bool g_cleanup_registered = false;

    std::string g_process_path;
    }  // namespace

    extern "C" const char* __real__CFProcessPath(void);
    extern "C" const char* __wrap__CFProcessPath(void) {
      if (!g_process_path.empty()) return g_process_path.c_str();
      const char* real = __real__CFProcessPath();
      if (real && *real != '\\0') return real;
      return "/data/storage/el1/bundle/\(nativeLibName)";
    }

    namespace {

    void ClearPendingException(napi_env env) {
      bool pending = false;
      if (napi_is_exception_pending(env, &pending) == napi_ok && pending) {
        napi_value exc = nullptr;
        napi_get_and_clear_last_exception(env, &exc);
      }
    }

    void UpdateTree(void* context, const char* json) {
      auto* slot = static_cast<SurfaceSlot*>(context);
      if (!slot || !slot->env || !slot->callback) return;
      napi_value callback, receiver, argument;
      if (napi_get_reference_value(slot->env, slot->callback, &callback) != napi_ok ||
          napi_get_undefined(slot->env, &receiver) != napi_ok ||
          napi_create_string_utf8(slot->env, json, NAPI_AUTO_LENGTH, &argument) != napi_ok) return;
      napi_call_function(slot->env, receiver, callback, 1, &argument, nullptr);
      ClearPendingException(slot->env);
    }

    napi_value Undefined(napi_env env) {
      napi_value result;
      return napi_get_undefined(env, &result) == napi_ok ? result : nullptr;
    }

    void UnmountSurfaceSlot(std::int32_t surfaceId) {
      auto it = g_surfaces.find(surfaceId);
      if (it == g_surfaces.end()) return;
      swift_unmount_surface(surfaceId);
      if (it->second && it->second->callback != nullptr) {
        napi_delete_reference(it->second->env, it->second->callback);
        it->second->callback = nullptr;
      }
      g_surfaces.erase(it);
    }

    void UnmountAll(void*) {
      swift_unmount_app();
      for (auto& kv : g_surfaces) {
        if (kv.second && kv.second->callback != nullptr) {
          napi_delete_reference(kv.second->env, kv.second->callback);
          kv.second->callback = nullptr;
        }
      }
      g_surfaces.clear();
      if (g_window_host != nullptr && g_host_env != nullptr) {
        napi_delete_reference(g_host_env, g_window_host);
      }
      g_window_host = nullptr;
      g_host_env = nullptr;
      g_cleanup_registered = false;
    }

    void EnsureCleanupHook(napi_env env) {
      if (g_cleanup_registered) return;
      if (napi_add_env_cleanup_hook(env, UnmountAll, nullptr) == napi_ok) {
        g_cleanup_registered = true;
      }
    }

    void InvokeWindowHost(const char* method, std::size_t argc, napi_value* argv) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value hostObj = nullptr;
      napi_value fn = nullptr;
      napi_valuetype fnType = napi_undefined;
      if (napi_get_reference_value(g_host_env, g_window_host, &hostObj) == napi_ok &&
          napi_get_named_property(g_host_env, hostObj, method, &fn) == napi_ok &&
          napi_typeof(g_host_env, fn, &fnType) == napi_ok && fnType == napi_function) {
        napi_call_function(g_host_env, hostObj, fn, argc, argv, nullptr);
        ClearPendingException(g_host_env);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    bool Dimensions(napi_env env, const napi_value* args, double& width, double& height) {
      return napi_get_value_double(env, args[0], &width) == napi_ok &&
             napi_get_value_double(env, args[1], &height) == napi_ok &&
             std::isfinite(width) && std::isfinite(height) && width > 0 && height > 0;
    }
    }  // namespace

    extern "C" void harmony_host_open_window(
        std::int32_t surfaceId, const char* title,
        double x, double y, double width, double height,
        std::int32_t isTransparent, std::int32_t isTitled,
        std::int32_t isResizable, std::int32_t isFloating, std::int32_t focus) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value argv[11];
      if (napi_create_int32(g_host_env, surfaceId, &argv[0]) == napi_ok &&
          napi_create_string_utf8(g_host_env, title ? title : "", NAPI_AUTO_LENGTH, &argv[1]) == napi_ok &&
          napi_create_double(g_host_env, x, &argv[2]) == napi_ok &&
          napi_create_double(g_host_env, y, &argv[3]) == napi_ok &&
          napi_create_double(g_host_env, width, &argv[4]) == napi_ok &&
          napi_create_double(g_host_env, height, &argv[5]) == napi_ok &&
          napi_get_boolean(g_host_env, isTransparent != 0, &argv[6]) == napi_ok &&
          napi_get_boolean(g_host_env, isTitled != 0, &argv[7]) == napi_ok &&
          napi_get_boolean(g_host_env, isResizable != 0, &argv[8]) == napi_ok &&
          napi_get_boolean(g_host_env, isFloating != 0, &argv[9]) == napi_ok &&
          napi_get_boolean(g_host_env, focus != 0, &argv[10]) == napi_ok) {
        InvokeWindowHost("openWindow", 11, argv);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    extern "C" void harmony_host_update_bounds(
        std::int32_t surfaceId, double x, double y, double width, double height) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value argv[5];
      if (napi_create_int32(g_host_env, surfaceId, &argv[0]) == napi_ok &&
          napi_create_double(g_host_env, x, &argv[1]) == napi_ok &&
          napi_create_double(g_host_env, y, &argv[2]) == napi_ok &&
          napi_create_double(g_host_env, width, &argv[3]) == napi_ok &&
          napi_create_double(g_host_env, height, &argv[4]) == napi_ok) {
        InvokeWindowHost("updateBounds", 5, argv);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    extern "C" void harmony_host_hide_window(std::int32_t surfaceId) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value arg = nullptr;
      if (napi_create_int32(g_host_env, surfaceId, &arg) == napi_ok) {
        InvokeWindowHost("hideWindow", 1, &arg);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    extern "C" void harmony_host_focus_window(std::int32_t surfaceId) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value arg = nullptr;
      if (napi_create_int32(g_host_env, surfaceId, &arg) == napi_ok) {
        InvokeWindowHost("focusWindow", 1, &arg);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    extern "C" void harmony_host_destroy_window(std::int32_t surfaceId) {
      if (!g_host_env || !g_window_host) return;
      napi_handle_scope scope = nullptr;
      if (napi_open_handle_scope(g_host_env, &scope) != napi_ok) return;
      napi_value arg = nullptr;
      if (napi_create_int32(g_host_env, surfaceId, &arg) == napi_ok) {
        InvokeWindowHost("destroyWindow", 1, &arg);
      }
      napi_close_handle_scope(g_host_env, scope);
    }

    extern "C" bool harmony_measure_text(const char* text, const char* family, double fontSize,
                                         int weight, double* width, double* height) {
      auto* fonts = OH_Drawing_GetFontCollectionGlobalInstance();
      std::unique_ptr<OH_Drawing_TypographyStyle, decltype(&OH_Drawing_DestroyTypographyStyle)>
          paragraph(OH_Drawing_CreateTypographyStyle(), OH_Drawing_DestroyTypographyStyle);
      std::unique_ptr<OH_Drawing_TextStyle, decltype(&OH_Drawing_DestroyTextStyle)>
          style(OH_Drawing_CreateTextStyle(), OH_Drawing_DestroyTextStyle);
      if (!fonts || !paragraph || !style) return false;
      OH_Drawing_SetTypographyTextDirection(paragraph.get(), TEXT_DIRECTION_LTR);
      OH_Drawing_SetTextStyleFontSize(style.get(), fontSize);
      OH_Drawing_SetTextStyleFontWeight(style.get(), weight);
      if (*family != '\\0') OH_Drawing_SetTextStyleFontFamilies(style.get(), 1, &family);
      std::unique_ptr<OH_Drawing_TypographyCreate, decltype(&OH_Drawing_DestroyTypographyHandler)>
          builder(OH_Drawing_CreateTypographyHandler(paragraph.get(), fonts), OH_Drawing_DestroyTypographyHandler);
      if (!builder) return false;
      OH_Drawing_TypographyHandlerPushTextStyle(builder.get(), style.get());
      OH_Drawing_TypographyHandlerAddText(builder.get(), *text == '\\0' ? " " : text);
      OH_Drawing_TypographyHandlerPopTextStyle(builder.get());
      std::unique_ptr<OH_Drawing_Typography, decltype(&OH_Drawing_DestroyTypography)>
          layout(OH_Drawing_CreateTypography(builder.get()), OH_Drawing_DestroyTypography);
      if (!layout) return false;
      OH_Drawing_TypographyLayout(layout.get(), INFINITY);
      *width = *text == '\\0' ? 0 : std::ceil(OH_Drawing_TypographyGetLongestLine(layout.get()));
      *height = std::ceil(OH_Drawing_TypographyGetHeight(layout.get()));
      return std::isfinite(*width) && std::isfinite(*height) && *height > 0;
    }

    namespace {
    struct HarmonyOffscreen {
      OH_Drawing_Bitmap* bitmap = nullptr;
      OH_Drawing_Canvas* canvas = nullptr;
      std::int32_t width = 0;
      std::int32_t height = 0;
    };

    void AppendBE32(std::vector<std::uint8_t>& out, std::uint32_t v) {
      out.push_back(static_cast<std::uint8_t>((v >> 24) & 0xFF));
      out.push_back(static_cast<std::uint8_t>((v >> 16) & 0xFF));
      out.push_back(static_cast<std::uint8_t>((v >> 8) & 0xFF));
      out.push_back(static_cast<std::uint8_t>(v & 0xFF));
    }

    void AppendPNGChunk(std::vector<std::uint8_t>& out, const char type[4],
                        const std::uint8_t* data, std::size_t len) {
      AppendBE32(out, static_cast<std::uint32_t>(len));
      out.insert(out.end(), type, type + 4);
      if (len > 0 && data) out.insert(out.end(), data, data + len);
      uLong crc = crc32(0L, Z_NULL, 0);
      crc = crc32(crc, reinterpret_cast<const Bytef*>(type), 4);
      if (len > 0 && data) {
        crc = crc32(crc, reinterpret_cast<const Bytef*>(data), static_cast<uInt>(len));
      }
      AppendBE32(out, static_cast<std::uint32_t>(crc));
    }
    }  // namespace

    extern "C" void* harmony_offscreen_create(std::int32_t width, std::int32_t height) {
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return nullptr;
      OH_Drawing_Bitmap* bitmap = OH_Drawing_BitmapCreate();
      if (!bitmap) return nullptr;
      OH_Drawing_BitmapFormat fmt{COLOR_FORMAT_RGBA_8888, ALPHA_FORMAT_PREMUL};
      OH_Drawing_BitmapBuild(bitmap, static_cast<std::uint32_t>(width),
                             static_cast<std::uint32_t>(height), &fmt);
      OH_Drawing_Canvas* canvas = OH_Drawing_CanvasCreate();
      if (!canvas) {
        OH_Drawing_BitmapDestroy(bitmap);
        return nullptr;
      }
      OH_Drawing_CanvasBind(canvas, bitmap);
      OH_Drawing_CanvasClear(canvas, 0x00000000);
      return new HarmonyOffscreen{bitmap, canvas, width, height};
    }

    extern "C" void harmony_offscreen_path(void* raw, const double* cmds, std::int32_t count,
                                           std::uint32_t fillARGB, std::uint32_t strokeARGB,
                                           double strokeWidth) {
      auto* ctx = static_cast<HarmonyOffscreen*>(raw);
      if (!ctx || !ctx->canvas || !cmds || count <= 0) return;
      OH_Drawing_Path* path = OH_Drawing_PathCreate();
      if (!path) return;
      std::int32_t i = 0;
      while (i < count) {
        std::int32_t op = static_cast<std::int32_t>(cmds[i]);
        if (op == 0 && i + 2 < count) {
          OH_Drawing_PathMoveTo(path, static_cast<float>(cmds[i + 1]),
                                static_cast<float>(cmds[i + 2]));
          i += 3;
        } else if (op == 1 && i + 2 < count) {
          OH_Drawing_PathLineTo(path, static_cast<float>(cmds[i + 1]),
                                static_cast<float>(cmds[i + 2]));
          i += 3;
        } else if (op == 2 && i + 6 < count) {
          OH_Drawing_PathCubicTo(path,
                                 static_cast<float>(cmds[i + 1]), static_cast<float>(cmds[i + 2]),
                                 static_cast<float>(cmds[i + 3]), static_cast<float>(cmds[i + 4]),
                                 static_cast<float>(cmds[i + 5]), static_cast<float>(cmds[i + 6]));
          i += 7;
        } else if (op == 3) {
          OH_Drawing_PathClose(path);
          i += 1;
        } else {
          break;
        }
      }
      if ((fillARGB >> 24) != 0) {
        OH_Drawing_Brush* brush = OH_Drawing_BrushCreate();
        if (brush) {
          OH_Drawing_BrushSetAntiAlias(brush, true);
          OH_Drawing_BrushSetColor(brush, OH_Drawing_ColorSetArgb(
              (fillARGB >> 24) & 0xFF, (fillARGB >> 16) & 0xFF,
              (fillARGB >> 8) & 0xFF, fillARGB & 0xFF));
          OH_Drawing_CanvasAttachBrush(ctx->canvas, brush);
          OH_Drawing_CanvasDrawPath(ctx->canvas, path);
          OH_Drawing_CanvasDetachBrush(ctx->canvas);
          OH_Drawing_BrushDestroy(brush);
        }
      }
      if ((strokeARGB >> 24) != 0 && strokeWidth > 0.0) {
        OH_Drawing_Pen* pen = OH_Drawing_PenCreate();
        if (pen) {
          OH_Drawing_PenSetAntiAlias(pen, true);
          OH_Drawing_PenSetColor(pen, OH_Drawing_ColorSetArgb(
              (strokeARGB >> 24) & 0xFF, (strokeARGB >> 16) & 0xFF,
              (strokeARGB >> 8) & 0xFF, strokeARGB & 0xFF));
          OH_Drawing_PenSetWidth(pen, static_cast<float>(strokeWidth));
          OH_Drawing_PenSetCap(pen, LINE_ROUND_CAP);
          OH_Drawing_PenSetJoin(pen, LINE_ROUND_JOIN);
          OH_Drawing_CanvasAttachPen(ctx->canvas, pen);
          OH_Drawing_CanvasDrawPath(ctx->canvas, path);
          OH_Drawing_CanvasDetachPen(ctx->canvas);
          OH_Drawing_PenDestroy(pen);
        }
      }
      OH_Drawing_PathDestroy(path);
    }

    extern "C" std::uint8_t* harmony_offscreen_finish_png(void* raw, std::int32_t* outLen) {
      if (outLen) *outLen = 0;
      std::unique_ptr<HarmonyOffscreen> ctx(static_cast<HarmonyOffscreen*>(raw));
      if (!ctx || !ctx->bitmap || !ctx->canvas || ctx->width <= 0 || ctx->height <= 0) {
        if (ctx) {
          if (ctx->canvas) OH_Drawing_CanvasDestroy(ctx->canvas);
          if (ctx->bitmap) OH_Drawing_BitmapDestroy(ctx->bitmap);
        }
        return nullptr;
      }
      const std::size_t w = static_cast<std::size_t>(ctx->width);
      const std::size_t h = static_cast<std::size_t>(ctx->height);
      const std::size_t rowBytes = w * 4;
      std::vector<std::uint8_t> rgba(rowBytes * h, 0);
      OH_Drawing_Image_Info dstInfo{ctx->width, ctx->height, COLOR_FORMAT_RGBA_8888,
                                    ALPHA_FORMAT_UNPREMUL};
      bool ok = OH_Drawing_BitmapReadPixels(ctx->bitmap, &dstInfo, rgba.data(), rowBytes, 0, 0);
      if (!ok) {
        if (const auto* src =
                static_cast<const std::uint8_t*>(OH_Drawing_BitmapGetPixels(ctx->bitmap))) {
          for (std::size_t i = 0; i < rgba.size(); i += 4) {
            std::uint8_t a = src[i + 3];
            if (a == 0) {
              rgba[i] = rgba[i + 1] = rgba[i + 2] = rgba[i + 3] = 0;
            } else if (a == 255) {
              rgba[i] = src[i];
              rgba[i + 1] = src[i + 1];
              rgba[i + 2] = src[i + 2];
              rgba[i + 3] = 255;
            } else {
              rgba[i] = static_cast<std::uint8_t>(std::min<int>(255, (int(src[i]) * 255 + a / 2) / a));
              rgba[i + 1] = static_cast<std::uint8_t>(std::min<int>(255, (int(src[i + 1]) * 255 + a / 2) / a));
              rgba[i + 2] = static_cast<std::uint8_t>(std::min<int>(255, (int(src[i + 2]) * 255 + a / 2) / a));
              rgba[i + 3] = a;
            }
          }
          ok = true;
        }
      }
      OH_Drawing_CanvasDestroy(ctx->canvas);
      OH_Drawing_BitmapDestroy(ctx->bitmap);
      if (!ok) return nullptr;

      std::vector<std::uint8_t> rawRows((rowBytes + 1) * h);
      for (std::size_t y = 0; y < h; ++y) {
        std::size_t dstOff = y * (rowBytes + 1);
        rawRows[dstOff] = 0;
        std::memcpy(rawRows.data() + dstOff + 1, rgba.data() + y * rowBytes, rowBytes);
      }
      uLongf compLen = compressBound(static_cast<uLong>(rawRows.size()));
      std::vector<std::uint8_t> compressed(compLen);
      if (compress2(compressed.data(), &compLen, rawRows.data(),
                    static_cast<uLong>(rawRows.size()), Z_DEFAULT_COMPRESSION) != Z_OK) {
        return nullptr;
      }
      compressed.resize(compLen);

      std::vector<std::uint8_t> png;
      png.reserve(64 + compressed.size());
      static const std::uint8_t sig[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
      png.insert(png.end(), sig, sig + 8);
      std::vector<std::uint8_t> ihdr;
      ihdr.reserve(13);
      AppendBE32(ihdr, static_cast<std::uint32_t>(w));
      AppendBE32(ihdr, static_cast<std::uint32_t>(h));
      ihdr.push_back(8);
      ihdr.push_back(6);
      ihdr.push_back(0);
      ihdr.push_back(0);
      ihdr.push_back(0);
      AppendPNGChunk(png, "IHDR", ihdr.data(), ihdr.size());
      AppendPNGChunk(png, "IDAT", compressed.data(), compressed.size());
      AppendPNGChunk(png, "IEND", nullptr, 0);

      auto* result = static_cast<std::uint8_t*>(std::malloc(png.size()));
      if (!result) return nullptr;
      std::memcpy(result, png.data(), png.size());
      if (outLen) *outLen = static_cast<std::int32_t>(png.size());
      return result;
    }

    extern "C" void harmony_free_bytes(std::uint8_t* ptr) {
      std::free(ptr);
    }

    static napi_value SetAbilityContext(napi_env env, napi_callback_info info, bool attach) {
      napi_value context, result;
      size_t count = 1;
      if (napi_get_cb_info(env, info, &count, &context, nullptr, nullptr) != napi_ok || count != 1) {
        napi_throw_type_error(env, nullptr, "Expected the owning UIAbility context");
        return nullptr;
      }
      bool ok = false;
      if (attach) {
        ok = nativeapi::ohos::AttachContext(env, context);
        if (ok) {
          nativeapi::ohos::HandleApplicationLifecycle(
              env, context, nativeapi::ohos::AbilityLifecycle::Create);
        }
      } else {
        ok = nativeapi::ohos::HandleApplicationLifecycle(
            env, context, nativeapi::ohos::AbilityLifecycle::Destroy);
        if (!ok) {
          ok = nativeapi::ohos::DetachContext(env, context);
        }
      }
      return napi_get_boolean(env, ok, &result) == napi_ok ? result : nullptr;
    }

    static napi_value AttachNativeAPI(napi_env env, napi_callback_info info) {
      return SetAbilityContext(env, info, true);
    }

    static napi_value DetachNativeAPI(napi_env env, napi_callback_info info) {
      return SetAbilityContext(env, info, false);
    }

    static napi_value NotifyLifecycle(napi_env env, napi_callback_info info) {
      napi_value args[2], result;
      size_t count = 2;
      std::int32_t state = 0;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2 ||
          napi_get_value_int32(env, args[1], &state) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected UIAbility context and lifecycle state");
        return nullptr;
      }
      nativeapi::ohos::AbilityLifecycle event =
          state == 1 ? nativeapi::ohos::AbilityLifecycle::Foreground
                     : nativeapi::ohos::AbilityLifecycle::Background;
      const bool ok = nativeapi::ohos::HandleApplicationLifecycle(env, args[0], event);
      return napi_get_boolean(env, ok, &result) == napi_ok ? result : nullptr;
    }

    static napi_value AttachWindowStage(napi_env env, napi_callback_info info) {
      napi_value stage, result;
      size_t count = 1;
      if (napi_get_cb_info(env, info, &count, &stage, nullptr, nullptr) != napi_ok || count != 1) {
        napi_throw_type_error(env, nullptr, "Expected the owning WindowStage");
        return nullptr;
      }
      const bool ok = nativeapi::ohos::AttachWindowStage(env, stage);
      return napi_get_boolean(env, ok, &result) == napi_ok ? result : nullptr;
    }

    static napi_value RegisterWindowHost(napi_env env, napi_callback_info info) {
      napi_value hostObj;
      size_t count = 1;
      if (napi_get_cb_info(env, info, &count, &hostObj, nullptr, nullptr) != napi_ok || count != 1) {
        napi_throw_type_error(env, nullptr, "Expected a HarmonyWindowHost object");
        return nullptr;
      }
      if (g_window_host != nullptr && g_host_env != nullptr) {
        napi_delete_reference(g_host_env, g_window_host);
        g_window_host = nullptr;
      }
      g_host_env = env;
      if (napi_create_reference(env, hostObj, 1, &g_window_host) != napi_ok) return nullptr;
      EnsureCleanupHook(env);
      return Undefined(env);
    }

    static napi_value AttachSurfaceWindowImpl(napi_env env, std::int32_t surfaceId, napi_value win) {
      napi_value result;
      auto attached = nativeapi::ohos::AttachWindow(env, win, nativeapi::IdAllocator::kInvalidId, false);
      const bool ok = attached != nullptr;
      if (ok) {
        if (surfaceId == 0) {
          nativeapi::Application::GetInstance().SetPrimaryWindow(attached);
        }
        if (swift_harmony_window_attached != nullptr) {
          swift_harmony_window_attached(surfaceId, static_cast<std::uint32_t>(attached->GetId()));
        }
      }
      return napi_get_boolean(env, ok, &result) == napi_ok ? result : nullptr;
    }

    static napi_value AttachFloatingWindow(napi_env env, napi_callback_info info) {
      napi_value win;
      size_t count = 1;
      if (napi_get_cb_info(env, info, &count, &win, nullptr, nullptr) != napi_ok || count != 1) {
        napi_throw_type_error(env, nullptr, "Expected a HarmonyOS Window object");
        return nullptr;
      }
      return AttachSurfaceWindowImpl(env, 0, win);
    }

    static napi_value AttachSurfaceWindow(napi_env env, napi_callback_info info) {
      napi_value args[2];
      size_t count = 2;
      std::int32_t surfaceId = 0;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2 ||
          napi_get_value_int32(env, args[0], &surfaceId) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a surface ID and HarmonyOS Window object");
        return nullptr;
      }
      return AttachSurfaceWindowImpl(env, surfaceId, args[1]);
    }

    static napi_value MountSurfaceImpl(
        napi_env env, std::int32_t surfaceId, napi_value callbackArg,
        double width, double height, double pixelsPerPoint) {
      if (g_surfaces.find(surfaceId) != g_surfaces.end()) {
        UnmountSurfaceSlot(surfaceId);
      }
      auto slot = std::make_unique<SurfaceSlot>();
      slot->surfaceId = surfaceId;
      slot->env = env;
      if (napi_create_reference(env, callbackArg, 1, &slot->callback) != napi_ok) return nullptr;
      EnsureCleanupHook(env);
      SurfaceSlot* rawSlot = slot.get();
      g_surfaces[surfaceId] = std::move(slot);
      if (surfaceId == 0) {
        swift_mount_app(rawSlot, UpdateTree, width, height, pixelsPerPoint);
      } else {
        swift_mount_surface(surfaceId, rawSlot, UpdateTree, width, height, pixelsPerPoint);
      }
      return Undefined(env);
    }

    static napi_value MountApp(napi_env env, napi_callback_info info) {
      napi_value args[4];
      size_t count = 4;
      double width, height, pixelsPerPoint;
      napi_valuetype type;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 4 ||
          napi_typeof(env, args[0], &type) != napi_ok || type != napi_function ||
          !Dimensions(env, args + 1, width, height) ||
          napi_get_value_double(env, args[3], &pixelsPerPoint) != napi_ok ||
          !std::isfinite(pixelsPerPoint) || pixelsPerPoint <= 0) {
        napi_throw_type_error(env, nullptr, "Expected a tree callback, width, height and pixel density");
        return nullptr;
      }
      return MountSurfaceImpl(env, 0, args[0], width, height, pixelsPerPoint);
    }

    static napi_value MountSurface(napi_env env, napi_callback_info info) {
      napi_value args[5];
      size_t count = 5;
      std::int32_t surfaceId = 0;
      double width, height, pixelsPerPoint;
      napi_valuetype type;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 5 ||
          napi_get_value_int32(env, args[0], &surfaceId) != napi_ok ||
          napi_typeof(env, args[1], &type) != napi_ok || type != napi_function ||
          !Dimensions(env, args + 2, width, height) ||
          napi_get_value_double(env, args[4], &pixelsPerPoint) != napi_ok ||
          !std::isfinite(pixelsPerPoint) || pixelsPerPoint <= 0) {
        napi_throw_type_error(env, nullptr, "Expected a surface ID, tree callback, width, height and pixel density");
        return nullptr;
      }
      return MountSurfaceImpl(env, surfaceId, args[1], width, height, pixelsPerPoint);
    }

    static napi_value ResizeApp(napi_env env, napi_callback_info info) {
      napi_value args[2];
      size_t count = 2;
      double width, height;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok ||
          count != 2 || !Dimensions(env, args, width, height)) {
        napi_throw_type_error(env, nullptr, "Expected a positive window size");
        return nullptr;
      }
      swift_resize_app(width, height);
      return Undefined(env);
    }

    static napi_value ResizeSurface(napi_env env, napi_callback_info info) {
      napi_value args[3];
      size_t count = 3;
      std::int32_t surfaceId = 0;
      double width, height;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 3 ||
          napi_get_value_int32(env, args[0], &surfaceId) != napi_ok ||
          !Dimensions(env, args + 1, width, height)) {
        napi_throw_type_error(env, nullptr, "Expected a surface ID and positive window size");
        return nullptr;
      }
      swift_resize_surface(surfaceId, width, height);
      return Undefined(env);
    }

    static napi_value AppEvent(napi_env env, napi_callback_info info) {
      napi_value args[3];
      size_t count = 3, length;
      std::int64_t id;
      std::int32_t event;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 3 ||
          napi_get_value_int64(env, args[0], &id) != napi_ok ||
          napi_get_value_int32(env, args[1], &event) != napi_ok ||
          napi_get_value_string_utf8(env, args[2], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a Swift node ID, event and text");
        return nullptr;
      }
      std::string text(length + 1, '\\0');
      if (napi_get_value_string_utf8(env, args[2], text.data(), text.size(), nullptr) != napi_ok) return nullptr;
      swift_app_event(id, event, text.c_str());
      return Undefined(env);
    }

    static napi_value SurfaceEvent(napi_env env, napi_callback_info info) {
      napi_value args[4];
      size_t count = 4, length;
      std::int32_t surfaceId = 0;
      std::int64_t id;
      std::int32_t event;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 4 ||
          napi_get_value_int32(env, args[0], &surfaceId) != napi_ok ||
          napi_get_value_int64(env, args[1], &id) != napi_ok ||
          napi_get_value_int32(env, args[2], &event) != napi_ok ||
          napi_get_value_string_utf8(env, args[3], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a surface ID, Swift node ID, event and text");
        return nullptr;
      }
      std::string text(length + 1, '\\0');
      if (napi_get_value_string_utf8(env, args[3], text.data(), text.size(), nullptr) != napi_ok) return nullptr;
      swift_surface_event(surfaceId, id, event, text.c_str());
      return Undefined(env);
    }

    static napi_value UnmountApp(napi_env env, napi_callback_info) {
      if (g_cleanup_registered) {
        napi_remove_env_cleanup_hook(env, UnmountAll, nullptr);
      }
      UnmountAll(nullptr);
      return Undefined(env);
    }

    static napi_value UnmountSurface(napi_env env, napi_callback_info info) {
      napi_value arg;
      size_t count = 1;
      std::int32_t surfaceId = 0;
      if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1 ||
          napi_get_value_int32(env, arg, &surfaceId) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a surface ID");
        return nullptr;
      }
      UnmountSurfaceSlot(surfaceId);
      return Undefined(env);
    }

    static napi_value ConfigureResources(napi_env env, napi_callback_info info) {
      napi_value args[2];
      size_t count = 2, dirLen = 0, langLen = 0;
      if (napi_get_cb_info(env, info, &count, args, nullptr, nullptr) != napi_ok || count != 2 ||
          napi_get_value_string_utf8(env, args[0], nullptr, 0, &dirLen) != napi_ok ||
          napi_get_value_string_utf8(env, args[1], nullptr, 0, &langLen) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected resource directory and language strings");
        return nullptr;
      }
      std::string dir(dirLen + 1, '\\0');
      std::string lang(langLen + 1, '\\0');
      if (napi_get_value_string_utf8(env, args[0], dir.data(), dir.size(), nullptr) != napi_ok ||
          napi_get_value_string_utf8(env, args[1], lang.data(), lang.size(), nullptr) != napi_ok) {
        return nullptr;
      }
      if (!dir.empty()) {
        std::string resDir(dir.c_str());
        std::string contentsDir = resDir + "/Contents";
        mkdir(contentsDir.c_str(), 0755);
        std::string fakeExe = resDir + "/\(nativeLibName)";
        struct stat st{};
        if (stat(fakeExe.c_str(), &st) != 0) {
          std::ofstream marker(fakeExe, std::ios::binary | std::ios::trunc);
        }
        std::string infoPlistDst = contentsDir + "/Info.plist";
        std::string infoPlistRes = contentsDir + "/Resources/Info.plist";
        std::string infoPlistRoot = resDir + "/Info.plist";
        if (stat(infoPlistDst.c_str(), &st) != 0) {
          std::string srcPath;
          if (stat(infoPlistRes.c_str(), &st) == 0) srcPath = infoPlistRes;
          else if (stat(infoPlistRoot.c_str(), &st) == 0) srcPath = infoPlistRoot;
          if (!srcPath.empty()) {
            std::ifstream src(srcPath, std::ios::binary);
            std::ofstream dst(infoPlistDst, std::ios::binary | std::ios::trunc);
            if (src && dst) dst << src.rdbuf();
          }
        }
        g_process_path = fakeExe;
        setenv("CFProcessPath", fakeExe.c_str(), 1);
        auto slash = resDir.rfind('/');
        std::string sandboxHome = (slash != std::string::npos && slash > 0) ? resDir.substr(0, slash) : resDir;
        setenv("HOME", sandboxHome.c_str(), 1);
        std::string tmpDir = sandboxHome + "/tmp";
        mkdir(tmpDir.c_str(), 0700);
        setenv("TMPDIR", tmpDir.c_str(), 1);
        setenv("XDG_CONFIG_HOME", (sandboxHome + "/.config").c_str(), 0);
        setenv("XDG_DATA_HOME", (sandboxHome + "/.local/share").c_str(), 0);
        setenv("XDG_CACHE_HOME", (sandboxHome + "/.cache").c_str(), 0);
      }
      if (lang[0] != '\\0') {
        setenv("CROSSSWIFT_PREFERRED_LANGUAGE", lang.c_str(), 1);
      }
      swift_configure_resources(dir.c_str(), lang.c_str());
      return Undefined(env);
    }

    static napi_value ReopenApp(napi_env env, napi_callback_info) {
      if (swift_reopen_app != nullptr) {
        swift_reopen_app();
      }
      return Undefined(env);
    }

    static napi_value SetColorScheme(napi_env env, napi_callback_info info) {
      napi_value arg;
      size_t count = 1;
      bool isDark = false;
      if (napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr) != napi_ok || count != 1 ||
          napi_get_value_bool(env, arg, &isDark) != napi_ok) {
        napi_throw_type_error(env, nullptr, "Expected a boolean color scheme flag");
        return nullptr;
      }
      swift_set_color_scheme(isDark ? 1 : 0);
      return Undefined(env);
    }

    static napi_value Init(napi_env env, napi_value exports) {
      if (!nativeapi::ohos::Initialize(env) || !nativeapi::swift_ohos::Initialize(env)) {
        napi_throw_error(env, nullptr, "Cannot initialize NativeAPI and Swift runtime on the ArkTS UI thread");
        return nullptr;
      }
      const napi_property_descriptor properties[] = {
          {"attachNativeAPI", nullptr, AttachNativeAPI, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"detachNativeAPI", nullptr, DetachNativeAPI, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"notifyLifecycle", nullptr, NotifyLifecycle, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"attachWindowStage", nullptr, AttachWindowStage, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"attachFloatingWindow", nullptr, AttachFloatingWindow, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"attachSurfaceWindow", nullptr, AttachSurfaceWindow, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"registerWindowHost", nullptr, RegisterWindowHost, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"configureResources", nullptr, ConfigureResources, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"mountApp", nullptr, MountApp, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"resizeApp", nullptr, ResizeApp, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"setColorScheme", nullptr, SetColorScheme, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"appEvent", nullptr, AppEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"unmountApp", nullptr, UnmountApp, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"mountSurface", nullptr, MountSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"resizeSurface", nullptr, ResizeSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"surfaceEvent", nullptr, SurfaceEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"unmountSurface", nullptr, UnmountSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
          {"reopenApp", nullptr, ReopenApp, nullptr, nullptr, nullptr, napi_default, nullptr},
      };
      if (napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties) != napi_ok) return nullptr;
      return exports;
    }

    static napi_module module = {1, 0, nullptr, Init, "\(nativeLibName)", nullptr, {0}};

    __attribute__((constructor)) static void Register() {
      napi_module_register(&module);
    }
    """
  }

  private static func isUpToDate(outputs: [URL], inputs: [URL]) -> Bool {
    let fm = FileManager.default
    var oldestOutput: Date?
    for out in outputs {
      guard let attrs = try? fm.attributesOfItem(atPath: out.path),
            let mtime = attrs[.modificationDate] as? Date
      else {
        return false
      }
      if let current = oldestOutput {
        if mtime < current { oldestOutput = mtime }
      } else {
        oldestOutput = mtime
      }
    }
    guard let threshold = oldestOutput else { return false }
    for input in inputs {
      guard let attrs = try? fm.attributesOfItem(atPath: input.path),
            let mtime = attrs[.modificationDate] as? Date
      else {
        return false
      }
      if mtime > threshold {
        return false
      }
    }
    return true
  }

  private static func collectSwiftFiles(in directory: URL) -> [URL] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }
    var files: [URL] = []
    for case let url as URL in enumerator {
      if url.pathExtension.lowercased() == "swift" {
        files.append(url)
      }
    }
    return files.sorted { $0.path < $1.path }
  }

  private static func writeText(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func escapeJSON(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
