import Foundation

public struct BuiltTargetArtifacts: Sendable {
  public let targetPlatform: TargetPlatform
  public let architecture: TargetArchitecture
  public let executableURL: URL
  public let buildDirectory: URL
  public let scratchDirectory: URL
  public let compiledAssets: CompiledAssets
  public let swiftExecutableURL: URL
  public let crossSwiftRoot: URL
  public let wasmPackageDirectory: URL?
  public let harmonyArtifacts: HarmonyBuildArtifacts?
  public let androidArtifacts: AndroidBuildArtifacts?
  public let adaptedRemotePackageDirectories: [URL]

  public init(
    targetPlatform: TargetPlatform,
    architecture: TargetArchitecture,
    executableURL: URL,
    buildDirectory: URL,
    scratchDirectory: URL,
    compiledAssets: CompiledAssets,
    swiftExecutableURL: URL,
    crossSwiftRoot: URL,
    wasmPackageDirectory: URL?,
    harmonyArtifacts: HarmonyBuildArtifacts?,
    androidArtifacts: AndroidBuildArtifacts? = nil,
    adaptedRemotePackageDirectories: [URL] = []
  ) {
    self.targetPlatform = targetPlatform
    self.architecture = architecture
    self.executableURL = executableURL
    self.buildDirectory = buildDirectory
    self.scratchDirectory = scratchDirectory
    self.compiledAssets = compiledAssets
    self.swiftExecutableURL = swiftExecutableURL
    self.crossSwiftRoot = crossSwiftRoot
    self.wasmPackageDirectory = wasmPackageDirectory
    self.harmonyArtifacts = harmonyArtifacts
    self.androidArtifacts = androidArtifacts
    self.adaptedRemotePackageDirectories = adaptedRemotePackageDirectories
  }
}

public enum BuildBackendError: Error, LocalizedError {
  case crossSwiftNotFound
  case nativeAPINotFound(String)
  case toolMissing(String)
  case binaryMissing(String)

  public var errorDescription: String? {
    switch self {
    case .crossSwiftNotFound:
      return "Could not locate CrossSwiftUI checkout; pass --crossswift-path or set CROSS_SWIFTUI_PATH"
    case .nativeAPINotFound(let hint):
      return "Could not locate NativeAPI Swift binding (\(hint)); pass --nativeapi-path or set NATIVEAPI_SWIFT_PATH"
    case .toolMissing(let detail):
      return detail
    case .binaryMissing(let path):
      return "Built executable was not produced at '\(path)'"
    }
  }
}

public final class SwiftPMBackend {
  private let wasmToolchainLock = NSLock()
  private var cachedWasmToolchain: [String: (executable: URL, prefixArgs: [String], sdkID: String)] = [:]

  public init() {}

  public func build(
    project: ResolvedXcodeProject,
    platform: TargetPlatform,
    configuration: BuildConfiguration,
    derivedDataURL: URL,
    options: XcodeBuildOptions
  ) throws -> BuiltTargetArtifacts {
    let fm = FileManager.default
    let crossSwiftRoot = try Self.resolveCrossSwiftRoot(explicit: options.crossSwiftPath)
    let nativeAPISwiftRoot: URL?
    if platform == .wasm || platform == .android {
      nativeAPISwiftRoot = nil
    } else {
      nativeAPISwiftRoot = try Self.resolveNativeAPISwiftRoot(
        explicit: options.nativeAPISwiftPath,
        crossSwiftRoot: crossSwiftRoot
      )
    }

    if platform == .windows, let nativeAPISwiftRoot {
      try ensureWindowsNativeAPICoreJunction(nativeAPISwiftRoot: nativeAPISwiftRoot)
    }

    let buildRoot = resolveBuildDirectory(
      project: project,
      platform: platform,
      configuration: configuration,
      derivedDataURL: derivedDataURL,
      scratchDirectory: options.scratchDirectory,
      crossSwiftRoot: crossSwiftRoot
    )
    let scratchDir = buildRoot.appendingPathComponent(".b")
    try fm.createDirectory(at: buildRoot, withIntermediateDirectories: true)
    try fm.createDirectory(at: scratchDir, withIntermediateDirectories: true)

    let assetsStaging = buildRoot.appendingPathComponent("AssetsStaging")
    try fm.createDirectory(at: assetsStaging, withIntermediateDirectories: true)
    if !options.quiet {
      ProcessRunner.writeStdoutLine("Compiling assets and resources...")
    }
    let assetCompiler = AssetAndIconCompiler()
    let compiledAssets = try assetCompiler.compile(project: project, stagingRoot: assetsStaging)

    if platform == .harmonyos {
      guard let nativeAPISwiftRoot else {
        throw BuildBackendError.nativeAPINotFound(crossSwiftRoot.deletingLastPathComponent().path)
      }
      let adaptedPackages = try prepareAdaptedPackages(
        project: project,
        platform: platform,
        buildRoot: buildRoot,
        crossSwiftRoot: crossSwiftRoot,
        quiet: options.quiet
      )
      var dependencyRoots: [URL] = []
      var seenRoots = Set<String>()
      let cacheRoot = buildRoot.deletingLastPathComponent().appendingPathComponent("AdaptedPackageCache")
      for remote in project.remotePackages {
        if let adapted = adaptedPackages.remote[remote.id] {
          if seenRoots.insert(adapted.standardizedFileURL.path).inserted {
            dependencyRoots.append(adapted)
          }
        } else if let checkout = try? PackageDependencyAdapter.checkoutRemotePackage(
          remote,
          cacheRoot: cacheRoot,
          echoOutput: !options.quiet
        ) {
          if seenRoots.insert(checkout.standardizedFileURL.path).inserted {
            dependencyRoots.append(checkout)
          }
        }
      }
      for adaptedURL in adaptedPackages.remote.values {
        if seenRoots.insert(adaptedURL.standardizedFileURL.path).inserted {
          dependencyRoots.append(adaptedURL)
        }
      }
      for local in project.localPackages {
        let root = adaptedPackages.local[local.id] ?? local.path
        if seenRoots.insert(root.standardizedFileURL.path).inserted {
          dependencyRoots.append(root)
        }
      }
      let harmony = try HarmonyBuilder.build(
        project: project,
        configuration: configuration,
        buildRoot: buildRoot,
        compiledAssets: compiledAssets,
        crossSwiftRoot: crossSwiftRoot,
        nativeAPISwiftRoot: nativeAPISwiftRoot,
        dependencyPackages: dependencyRoots,
        quiet: options.quiet
      )
      let swiftExe = (try? locateSwiftExecutable()) ?? URL(fileURLWithPath: "/usr/bin/swift")
      return BuiltTargetArtifacts(
        targetPlatform: .harmonyos,
        architecture: .arm64,
        executableURL: harmony.appObjectURL,
        buildDirectory: buildRoot,
        scratchDirectory: scratchDir,
        compiledAssets: compiledAssets,
        swiftExecutableURL: swiftExe,
        crossSwiftRoot: crossSwiftRoot,
        wasmPackageDirectory: nil,
        harmonyArtifacts: harmony,
        adaptedRemotePackageDirectories: Array(adaptedPackages.remote.values)
      )
    }

    var compiledResURL: URL?
    if platform == .windows, let rcURL = compiledAssets.windowsResourceScriptURL {
      if !options.quiet {
        ProcessRunner.writeStdoutLine("Compiling Windows resources...")
      }
      compiledResURL = try compileWindowsResources(rcURL: rcURL, echoOutput: !options.quiet)
    }

    try stageSources(
      project: project,
      platform: platform,
      generatedAssetSymbolsURL: compiledAssets.generatedSymbolsSwiftURL,
      buildRoot: buildRoot
    )

    let adaptedPackages = try prepareAdaptedPackages(
      project: project,
      platform: platform,
      buildRoot: buildRoot,
      crossSwiftRoot: crossSwiftRoot,
      quiet: options.quiet
    )

    let consoleSubsystem = options.consoleSubsystem
      || (project.mainTarget.buildSettings["CROSS_SWIFTUI_CONSOLE_SUBSYSTEM"]?.uppercased() == "YES")
    let manifestText = generatePackageManifest(
      project: project,
      platform: platform,
      configuration: configuration,
      consoleSubsystem: consoleSubsystem,
      crossSwiftRoot: crossSwiftRoot,
      nativeAPISwiftRoot: nativeAPISwiftRoot,
      compiledResourceURL: compiledResURL,
      adaptedRemotePackages: adaptedPackages.remote,
      adaptedLocalPackages: adaptedPackages.local
    )
    let packageSwiftURL = buildRoot.appendingPathComponent("Package.swift")
    try writeIfChanged(text: manifestText, to: packageSwiftURL)

    if platform == .android {
      let android = try AndroidBuilder.build(
        project: project,
        configuration: configuration,
        buildRoot: buildRoot,
        scratchDir: scratchDir,
        crossSwiftRoot: crossSwiftRoot,
        quiet: options.quiet
      )
      let firstAbi = android.abis.first ?? "arm64-v8a"
      let primarySO = android.jniLibsDirectory
        .appendingPathComponent("\(firstAbi)/lib\(android.libraryName).so")
      let swiftExe = (try? locateSwiftExecutable()) ?? URL(fileURLWithPath: "/usr/bin/swift")
      return BuiltTargetArtifacts(
        targetPlatform: .android,
        architecture: firstAbi == "x86_64" ? .x64 : .arm64,
        executableURL: primarySO,
        buildDirectory: buildRoot,
        scratchDirectory: scratchDir,
        compiledAssets: compiledAssets,
        swiftExecutableURL: swiftExe,
        crossSwiftRoot: crossSwiftRoot,
        wasmPackageDirectory: nil,
        harmonyArtifacts: nil,
        androidArtifacts: android,
        adaptedRemotePackageDirectories: Array(adaptedPackages.remote.values)
      )
    }

    if platform == .wasm {
      let (swiftTool, prefixArgs, wasmSDK) = try resolveWasmToolchainAndSDK(
        preferredSDK: project.mainTarget.buildSettings["SWIFT_WASM_SDK"]
          ?? ProcessRunner.environmentValue("SWIFT_WASM_SDK")
      )
      let jsArgs = prefixArgs + [
        "package",
        "--package-path", buildRoot.path,
        "--scratch-path", scratchDir.path,
        "--swift-sdk", wasmSDK,
        "js",
        "--product", project.mainTarget.executableName,
        "-c", configuration.swiftPMFlag,
      ]
      let logURL = buildRoot.appendingPathComponent("swift-wasm-build.log")
      let wasmEnv: [String: String] = {
        var env: [String: String] = ["CROSS_SWIFTUI_WEB": "1"]
        if let resolvedNativeAPI = try? Self.resolveNativeAPISwiftRoot(
          explicit: options.nativeAPISwiftPath,
          crossSwiftRoot: crossSwiftRoot
        ) {
          env["NATIVEAPI_SWIFT_PATH"] = resolvedNativeAPI.path
        }
        return env
      }()
      #if os(Windows)
        try ensureWindowsPackageToJSPatched(
          swiftTool: swiftTool,
          prefixArgs: prefixArgs,
          buildRoot: buildRoot,
          scratchDir: scratchDir,
          wasmEnv: wasmEnv,
          quiet: options.quiet
        )
      #endif
      if !options.quiet {
        ProcessRunner.writeStdoutLine(
          "Running swift package js (\(wasmSDK), \(configuration.rawValue)) — log: \(logURL.path)"
        )
      }
      var buildResult = try ProcessRunner.run(
        executable: swiftTool,
        arguments: jsArgs,
        workingDirectory: buildRoot,
        environmentOverrides: wasmEnv,
        logFile: logURL,
        echoOutput: !options.quiet
      )
      #if os(Windows)
        if buildResult.exitCode != 0,
           let linkedWasm = try tryWindowsWasmLinkFallback(
             buildOutput: buildResult.stdout,
             swiftTool: swiftTool,
             wasmSDK: wasmSDK,
             executableName: project.mainTarget.executableName,
             configuration: configuration,
             buildRoot: buildRoot,
             scratchDir: scratchDir,
             quiet: options.quiet
           )
        {
          var packageEnv = wasmEnv
          packageEnv["CROSS_SWIFTUI_PREBUILT_WASM"] = linkedWasm.path
          buildResult = try ProcessRunner.run(
            executable: swiftTool,
            arguments: jsArgs,
            workingDirectory: buildRoot,
            environmentOverrides: packageEnv,
            logFile: logURL,
            echoOutput: !options.quiet
          )
        }
      #endif
      if buildResult.exitCode != 0 {
        throw ProcessRunnerError.commandFailed(
          command: "\(swiftTool.path) \(jsArgs.joined(separator: " "))",
          exitCode: buildResult.exitCode,
          output: buildResult.stdout
        )
      }
      let wasmPkgDir = scratchDir.appendingPathComponent("plugins/PackageToJS/outputs/Package")
      let indexJS = wasmPkgDir.appendingPathComponent("index.js")
      guard fm.fileExists(atPath: indexJS.path) else {
        throw BuildBackendError.binaryMissing(indexJS.path)
      }
      let wasmBinary = wasmPkgDir.appendingPathComponent("\(project.mainTarget.executableName).wasm")
      return BuiltTargetArtifacts(
        targetPlatform: .wasm,
        architecture: .wasm32,
        executableURL: fm.fileExists(atPath: wasmBinary.path) ? wasmBinary : indexJS,
        buildDirectory: buildRoot,
        scratchDirectory: scratchDir,
        compiledAssets: compiledAssets,
        swiftExecutableURL: swiftTool,
        crossSwiftRoot: crossSwiftRoot,
        wasmPackageDirectory: wasmPkgDir,
        harmonyArtifacts: nil,
        adaptedRemotePackageDirectories: Array(adaptedPackages.remote.values) + Array(adaptedPackages.local.values)
      )
    }

    let swiftExe = try locateSwiftExecutable()
    var envOverrides: [String: String] = [:]
    if let nativeAPISwiftRoot {
      envOverrides["NATIVEAPI_SWIFT_PATH"] = nativeAPISwiftRoot.path
    }
    if platform == .windows,
       let devDir = ProcessRunner.environmentValue("DEVELOPER_DIR"),
       !devDir.isEmpty
    {
      envOverrides["DEVELOPER_DIR"] = devDir
    }

    var buildArgs = [
      "build",
      "-c", configuration.swiftPMFlag,
      "--package-path", buildRoot.path,
      "--scratch-path", scratchDir.path,
    ]
    if platform == .windows {
      buildArgs += [
        "--build-system", "native",
        "-Xcxx", "-D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH",
      ]
    }
    if configuration == .release {
      buildArgs += [
        "-Xcc", "-ffunction-sections",
        "-Xcc", "-fdata-sections",
        "-Xcxx", "-ffunction-sections",
        "-Xcxx", "-fdata-sections",
      ]
    }
    let productArgs = buildArgs + ["--product", project.mainTarget.executableName]

    let logURL = buildRoot.appendingPathComponent("swift-build.log")
    if !options.quiet {
      ProcessRunner.writeStdoutLine(
        "Running swift build (\(platform.rawValue), \(configuration.rawValue)) — log: \(logURL.path)"
      )
    }
    let buildResult = try ProcessRunner.run(
      executable: swiftExe,
      arguments: productArgs,
      workingDirectory: buildRoot,
      environmentOverrides: envOverrides,
      logFile: logURL,
      echoOutput: !options.quiet
    )
    if buildResult.exitCode != 0 {
      throw ProcessRunnerError.commandFailed(
        command: "\(swiftExe.path) \(productArgs.joined(separator: " "))",
        exitCode: buildResult.exitCode,
        output: buildResult.stdout
      )
    }

    let binPathArgs = buildArgs + ["--show-bin-path"]
    let binResult = try ProcessRunner.run(
      executable: swiftExe,
      arguments: binPathArgs,
      workingDirectory: buildRoot,
      environmentOverrides: envOverrides
    )
    if binResult.exitCode != 0 {
      throw ProcessRunnerError.commandFailed(
        command: "\(swiftExe.path) \(binPathArgs.joined(separator: " "))",
        exitCode: binResult.exitCode,
        output: binResult.stdout + "\n" + binResult.stderr
      )
    }

    let binDirPath = binResult.stdout
      .split(whereSeparator: \.isNewline)
      .last
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let binDirURL = URL(fileURLWithPath: binDirPath)
    let exeFilename =
      platform == .windows
      ? "\(project.mainTarget.executableName).exe"
      : project.mainTarget.executableName
    let executableURL = binDirURL.appendingPathComponent(exeFilename)
    guard fm.fileExists(atPath: executableURL.path) else {
      throw BuildBackendError.binaryMissing(executableURL.path)
    }

    return BuiltTargetArtifacts(
      targetPlatform: platform,
      architecture: .currentHost,
      executableURL: executableURL,
      buildDirectory: buildRoot,
      scratchDirectory: scratchDir,
      compiledAssets: compiledAssets,
      swiftExecutableURL: swiftExe,
      crossSwiftRoot: crossSwiftRoot,
      wasmPackageDirectory: nil,
      harmonyArtifacts: nil
    )
  }

  public static func resolveCrossSwiftRoot(explicit: URL?) throws -> URL {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let explicit { candidates.append(explicit.standardizedFileURL) }
    if let envPath = ProcessRunner.environmentValue("CROSS_SWIFTUI_PATH"), !envPath.isEmpty {
      candidates.append(URL(fileURLWithPath: envPath).standardizedFileURL)
    }
    let fromFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    candidates.append(fromFile.standardizedFileURL)
    if let exeURL = Bundle.main.executableURL {
      var cursor = exeURL.resolvingSymlinksInPath().deletingLastPathComponent()
      for _ in 0..<5 {
        candidates.append(cursor)
        cursor = cursor.deletingLastPathComponent()
      }
    }
    var cwd = URL(fileURLWithPath: fm.currentDirectoryPath).standardizedFileURL
    for _ in 0..<6 {
      candidates.append(cwd)
      cwd = cwd.deletingLastPathComponent()
    }

    for candidate in candidates {
      let pkg = candidate.appendingPathComponent("Package.swift")
      let runtimeDir = candidate.appendingPathComponent("Sources/CrossSwiftUI")
      if fm.fileExists(atPath: pkg.path) && fm.fileExists(atPath: runtimeDir.path) {
        return candidate
      }
    }
    throw BuildBackendError.crossSwiftNotFound
  }

  public static func resolveNativeAPISwiftRoot(
    explicit: URL?,
    crossSwiftRoot: URL
  ) throws -> URL {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let explicit { candidates.append(explicit.standardizedFileURL) }
    if let envPath = ProcessRunner.environmentValue("NATIVEAPI_SWIFT_PATH"), !envPath.isEmpty {
      candidates.append(URL(fileURLWithPath: envPath).standardizedFileURL)
    }
    let parentDir = crossSwiftRoot.deletingLastPathComponent()
    candidates.append(parentDir.appendingPathComponent("nativeapi/bindings/swift").standardizedFileURL)

    for candidate in candidates {
      let pkg = candidate.appendingPathComponent("Package.swift").path
      let coreSrc = candidate.appendingPathComponent("Sources/CNativeAPI/core/src").path
      if fm.fileExists(atPath: pkg) && fm.fileExists(atPath: coreSrc) {
        return candidate
      }
    }
    throw BuildBackendError.nativeAPINotFound(parentDir.path)
  }

  public func resolveBuildDirectory(
    project: ResolvedXcodeProject,
    platform: TargetPlatform,
    configuration: BuildConfiguration,
    derivedDataURL: URL,
    scratchDirectory: URL?,
    crossSwiftRoot _: URL
  ) -> URL {
    let slug = ProcessRunner.sanitizedSlug(project.mainTarget.executableName).prefix(16)
    let hash = ProcessRunner.fnv1aHex(
      "\(project.projectURL.path)|\(platform.rawValue)|\(configuration.rawValue)")

    if let scratch = scratchDirectory {
      return scratch.appendingPathComponent("\(slug)-\(hash)").standardizedFileURL
    }

    #if os(Windows)
      // Keep build and scratch paths short on Windows to avoid MAX_PATH (260 chars).
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("csb/\(slug)-\(hash)")
        .standardizedFileURL
    #else
      if platform == .windows {
        return FileManager.default.temporaryDirectory
          .appendingPathComponent("csb/\(slug)-\(hash)")
          .standardizedFileURL
      }

      return derivedDataURL
        .appendingPathComponent("Build/Intermediates.noindex/\(slug)-\(hash)")
        .standardizedFileURL
    #endif
  }

  private func ensureWindowsNativeAPICoreJunction(nativeAPISwiftRoot: URL) throws {
    let fm = FileManager.default
    let coreLink = nativeAPISwiftRoot.appendingPathComponent("Sources/CNativeAPI/core")
    let coreTarget = nativeAPISwiftRoot
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("core")
      .standardizedFileURL

    var isDir: ObjCBool = false
    if fm.fileExists(atPath: coreLink.path, isDirectory: &isDir), isDir.boolValue {
      return
    }
    guard fm.fileExists(atPath: coreTarget.appendingPathComponent("src").path) else {
      return
    }
    if fm.fileExists(atPath: coreLink.path) {
      try? fm.removeItem(at: coreLink)
    }
    let cmdExe = URL(fileURLWithPath: ProcessRunner.environmentValue("ComSpec") ?? "C:\\Windows\\System32\\cmd.exe")
    let winLinkPath = coreLink.path.replacingOccurrences(of: "/", with: "\\")
    let winTargetPath = coreTarget.path.replacingOccurrences(of: "/", with: "\\")
    let res = try ProcessRunner.run(
      executable: cmdExe,
      arguments: ["/c", "mklink", "/J", winLinkPath, winTargetPath]
    )
    if res.exitCode != 0 {
      throw ProcessRunnerError.commandFailed(
        command: "mklink /J \(coreLink.path) \(coreTarget.path)",
        exitCode: res.exitCode,
        output: res.stdout + "\n" + res.stderr
      )
    }
  }

  #if os(Windows)
    /// JavaScriptKit's PackageToJS plugin references POSIX `stderr` without a Windows import.
    /// Resolve checkouts first if needed and patch `printStderr` so `swift package js` builds on Windows.
    private func ensureWindowsPackageToJSPatched(
      swiftTool: URL,
      prefixArgs: [String],
      buildRoot: URL,
      scratchDir: URL,
      wasmEnv: [String: String],
      quiet: Bool
    ) throws {
      let fm = FileManager.default
      let pluginFile = scratchDir
        .appendingPathComponent("checkouts/JavaScriptKit/Plugins/PackageToJS/Sources/PackageToJSPlugin.swift")
      if !fm.fileExists(atPath: pluginFile.path) {
        let resolveArgs = prefixArgs + [
          "package",
          "--package-path", buildRoot.path,
          "--scratch-path", scratchDir.path,
          "resolve",
        ]
        _ = try? ProcessRunner.run(
          executable: swiftTool,
          arguments: resolveArgs,
          workingDirectory: buildRoot,
          environmentOverrides: wasmEnv,
          echoOutput: !quiet
        )
      }
      guard fm.fileExists(atPath: pluginFile.path),
            var text = try? String(contentsOf: pluginFile, encoding: .utf8)
      else {
        return
      }
      var changed = false
      if text.contains("fputs(message + \"\\n\", stderr)") {
        if !text.contains("import class Foundation.FileHandle") {
          text = text.replacingOccurrences(
            of: "@preconcurrency import func Foundation.fputs",
            with: "@preconcurrency import func Foundation.fputs\n@preconcurrency import class Foundation.FileHandle"
          )
        }
        text = text.replacingOccurrences(
          of: "fputs(message + \"\\n\", stderr)",
          with: "try? FileHandle.standardError.write(contentsOf: Data((message + \"\\n\").utf8))"
        )
        changed = true
      }
      let prebuiltMarker = "CROSS_SWIFTUI_PREBUILT_WASM"
      if !text.contains(prebuiltMarker),
         let startRange = text.range(of: "let build = try buildWasm("),
         let endRange = text.range(
           of: "let productArtifact = try build.findWasmArtifact(for: productName)",
           range: startRange.lowerBound..<text.endIndex
         )
      {
        let replacement = """
        let productArtifact: URL
                if let prebuiltPath = ProcessInfo.processInfo.environment["\(prebuiltMarker)"],
                   !prebuiltPath.isEmpty,
                   FileManager.default.fileExists(atPath: prebuiltPath)
                {
                    productArtifact = URL(fileURLWithPath: prebuiltPath)
                } else {
                    let build = try buildWasm(
                        productName: productName,
                        selfPackage: selfPackage,
                        context: context,
                        options: buildOptions.packageOptions
                    )
                    guard build.succeeded else {
                        reportBuildFailure(build, arguments)
                        exit(1)
                    }
                    productArtifact = try build.findWasmArtifact(for: productName)
                }
                let skeletonCollector = SkeletonCollector(context: context)
                let skeletons = skeletonCollector.collectFromProduct(name: productName)
        """
        text.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: replacement)
        changed = true
      }
      guard changed else { return }
      let cmdExe = URL(fileURLWithPath: ProcessRunner.environmentValue("ComSpec") ?? "C:\\Windows\\System32\\cmd.exe")
      let winPath = pluginFile.path.replacingOccurrences(of: "/", with: "\\")
      _ = try? ProcessRunner.run(executable: cmdExe, arguments: ["/c", "attrib", "-R", winPath])
      try text.write(to: pluginFile, atomically: true, encoding: .utf8)
    }

    /// Works around Swift 6.4.2's Windows swift-driver bug where large wasm32 link commands
    /// (>32 KiB) spill to a temporary response file with unescaped backslashes that clang
    /// parses with POSIX quoting rules. Links the already-compiled `.o` files directly via
    /// `clang.exe --rsp-quoting=windows` so PackageToJS can complete packaging.
    private func tryWindowsWasmLinkFallback(
      buildOutput: String,
      swiftTool: URL,
      wasmSDK: String,
      executableName: String,
      configuration: BuildConfiguration,
      buildRoot: URL,
      scratchDir: URL,
      quiet: Bool
    ) throws -> URL? {
      guard buildOutput.contains("clang: error: no such file or directory:") else {
        return nil
      }
      let fm = FileManager.default
      let clangExe = swiftTool.deletingLastPathComponent().appendingPathComponent("clang.exe")
      guard fm.fileExists(atPath: clangExe.path) else { return nil }

      let configDir = configuration == .release ? "Release" : "Debug"
      let productsDir = scratchDir.appendingPathComponent("out/Products/\(configDir)-webassembly-wasm32")
      let intermediatesDir = scratchDir.appendingPathComponent("out/Intermediates.noindex")
      guard fm.fileExists(atPath: productsDir.path) else { return nil }

      // Locate LinkFileList and autolink generated by swiftbuild.
      var linkFileListURL: URL?
      var autolinkURL: URL?
      if let enumerator = fm.enumerator(at: intermediatesDir, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator {
          let name = url.lastPathComponent
          if name == "\(executableName).LinkFileList" && url.path.contains("\(configDir)-webassembly-wasm32") {
            linkFileListURL = url
          } else if name == "\(executableName).autolink" && url.path.contains("\(configDir)-webassembly-wasm32") {
            autolinkURL = url
          }
        }
      }
      guard let linkFileList = linkFileListURL,
            let autolink = autolinkURL
      else {
        return nil
      }

      // Locate the installed WASI SDK root.
      let home = fm.homeDirectoryForCurrentUser
      let sdkCandidates = [
        home.appendingPathComponent(".swiftpm/swift-sdks/\(wasmSDK).artifactbundle/\(wasmSDK)/wasm32-unknown-wasip1"),
        home.appendingPathComponent(".swiftpm/swift-sdks/\(wasmSDK)/wasm32-unknown-wasip1"),
      ]
      guard let sdkRoot = sdkCandidates.first(where: {
        fm.fileExists(atPath: $0.appendingPathComponent("WASI.sdk").path)
      }) else {
        return nil
      }

      func posix(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
      }

      var objects: [String] = []
      if let listText = try? String(contentsOf: linkFileList, encoding: .utf8) {
        for line in listText.components(separatedBy: .newlines) {
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty { objects.append(trimmed.replacingOccurrences(of: "\\", with: "/")) }
        }
      }
      let productEntries = (try? fm.contentsOfDirectory(at: productsDir, includingPropertiesForKeys: nil)) ?? []
      for entry in productEntries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where entry.lastPathComponent.hasSuffix(".objlib")
      {
        let resp = entry.appendingPathComponent("args.resp")
        guard let text = try? String(contentsOf: resp, encoding: .utf8) else { continue }
        for token in text.split(whereSeparator: \.isWhitespace) {
          objects.append(String(token).replacingOccurrences(of: "\\", with: "/"))
        }
      }
      guard !objects.isEmpty else { return nil }

      let outputWasm = productsDir.appendingPathComponent("\(executableName).wasm")
      let swiftStatic = sdkRoot.appendingPathComponent("swift.xctoolchain/usr/lib/swift_static")
      var rspArgs: [String] = [
        "-target", "wasm32-unknown-wasip1",
        posix(swiftStatic.appendingPathComponent("wasi/wasm32/swiftrt.o")),
      ]
      rspArgs.append(contentsOf: objects)
      rspArgs += [
        "@\(posix(autolink))",
        "--sysroot", posix(sdkRoot.appendingPathComponent("WASI.sdk")),
        "-L", posix(swiftStatic.appendingPathComponent("wasi")),
        "@\(posix(swiftStatic.appendingPathComponent("wasi/static-executable-args.lnk")))",
        "--target=wasm32-unknown-wasip1",
        "-resource-dir", posix(swiftStatic.appendingPathComponent("clang")),
        "-mexec-model=reactor",
        "-Xlinker", "--global-base=4096",
        "-Xlinker", "--table-base=4096",
        "-Xlinker", "-z", "-Xlinker", "stack-size=16777216",
        "-Xlinker", "--gc-sections",
        "-Xlinker", "--export-if-defined=__main_argc_argv",
      ]
      if configuration == .release {
        rspArgs += ["-Xlinker", "--strip-all"]
      }
      rspArgs += ["-o", posix(outputWasm)]

      let rspFile = buildRoot.appendingPathComponent("link-wasm.rsp")
      try rspArgs.joined(separator: "\n").write(to: rspFile, atomically: true, encoding: .utf8)

      if !quiet {
        ProcessRunner.writeStdoutLine(
          "Linking \(executableName).wasm via clang --rsp-quoting=windows fallback..."
        )
      }
      let linkResult = try ProcessRunner.run(
        executable: clangExe,
        arguments: ["--rsp-quoting=windows", "@\(posix(rspFile))"],
        workingDirectory: buildRoot,
        echoOutput: !quiet
      )
      guard linkResult.exitCode == 0, fm.fileExists(atPath: outputWasm.path) else {
        return nil
      }
      return outputWasm
    }
  #endif

  private func compileWindowsResources(rcURL: URL, echoOutput: Bool = false) throws -> URL {
    let rcDir = rcURL.deletingLastPathComponent()
    let resURL = rcDir.appendingPathComponent("AppResources.res")
    var extraDirs: [URL] = []
    if let userProfile = ProcessRunner.environmentValue("USERPROFILE") {
      extraDirs.append(URL(fileURLWithPath: "\(userProfile)\\scoop\\apps\\llvm\\current\\bin"))
    }
    if let swift = try? locateSwiftExecutable() {
      extraDirs.append(swift.deletingLastPathComponent())
    }
    extraDirs.append(URL(fileURLWithPath: "C:\\Program Files\\LLVM\\bin"))

    guard let rcTool = ProcessRunner.findExecutable(
      named: ["llvm-rc", "rc"], extraDirectories: extraDirs)
    else {
      throw BuildBackendError.toolMissing(
        "Could not find 'llvm-rc' or 'rc.exe' to embed Windows icon and manifest"
      )
    }

    let isLlvmRc = rcTool.lastPathComponent.lowercased().contains("llvm-rc")
    let winResPath = resURL.path.replacingOccurrences(of: "/", with: "\\")
    var args: [String] = []
    if isLlvmRc {
      args = ["/C", "65001", "/FO", winResPath, rcURL.lastPathComponent]
    } else {
      args = ["/nologo", "/fo", winResPath, rcURL.lastPathComponent]
    }
    let result = try ProcessRunner.run(
      executable: rcTool,
      arguments: args,
      workingDirectory: rcDir,
      echoOutput: echoOutput
    )
    if result.exitCode != 0 {
      throw ProcessRunnerError.commandFailed(
        command: "\(rcTool.path) \(args.joined(separator: " "))",
        exitCode: result.exitCode,
        output: result.stdout + "\n" + result.stderr
      )
    }
    return resURL
  }

  private func locateSwiftExecutable() throws -> URL {
    var extraDirs: [URL] = []
    let fm = FileManager.default
    #if os(Windows)
      if let localAppData = ProcessRunner.environmentValue("LOCALAPPDATA") {
        let toolchainsDir = URL(fileURLWithPath: localAppData).appendingPathComponent("Programs/Swift/Toolchains")
        if let children = try? fm.contentsOfDirectory(at: toolchainsDir, includingPropertiesForKeys: nil) {
          for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            extraDirs.append(child.appendingPathComponent("usr/bin"))
          }
        }
      }
    #elseif os(Linux)
      let home = fm.homeDirectoryForCurrentUser
      extraDirs.append(home.appendingPathComponent(".local/share/swiftly/bin"))
      extraDirs.append(home.appendingPathComponent(".local/bin"))
    #endif
    guard let swift = ProcessRunner.findExecutable(named: ["swift"], extraDirectories: extraDirs) else {
      throw BuildBackendError.toolMissing("Could not locate 'swift' compiler executable")
    }
    // Avoid `Circular swiftly proxy invocation` when `xcodebuild` itself is launched via `swift run`
    // under swiftly: resolve the proxy symlink directly to the active toolchain's `usr/bin/swift`.
    let resolved = swift.resolvingSymlinksInPath()
    if resolved.lastPathComponent == "swiftly" {
      if let locResult = try? ProcessRunner.run(executable: resolved, arguments: ["use", "--print-location"]),
         locResult.exitCode == 0
      {
        let toolchainRoot = locResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toolchainRoot.isEmpty {
          let realSwift = URL(fileURLWithPath: toolchainRoot).appendingPathComponent("usr/bin/swift")
          if fm.isExecutableFile(atPath: realSwift.path) {
            return realSwift
          }
        }
      }
    }
    return swift
  }

  private func resolveWasmToolchainAndSDK(
    preferredSDK: String?
  ) throws -> (executable: URL, prefixArgs: [String], sdkID: String) {
    let cacheKey = preferredSDK ?? ""
    wasmToolchainLock.lock()
    if let cached = cachedWasmToolchain[cacheKey] {
      wasmToolchainLock.unlock()
      return cached
    }
    wasmToolchainLock.unlock()

    let resolved = try resolveWasmToolchainAndSDKUncached(preferredSDK: preferredSDK)
    wasmToolchainLock.lock()
    cachedWasmToolchain[cacheKey] = resolved
    wasmToolchainLock.unlock()
    return resolved
  }

  private func resolveWasmToolchainAndSDKUncached(
    preferredSDK: String?
  ) throws -> (executable: URL, prefixArgs: [String], sdkID: String) {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    var candidates: [(URL, [String])] = []

    if let toolchainBin = ProcessRunner.environmentValue("SWIFT_TOOLCHAIN_BIN"), !toolchainBin.isEmpty {
      let swiftBin = URL(fileURLWithPath: toolchainBin).appendingPathComponent("swift")
      if fm.isExecutableFile(atPath: swiftBin.path) {
        candidates.append((swiftBin, []))
      }
    }

    let swiftlyDirs = [
      home.appendingPathComponent(".swiftly/bin"),
      home.appendingPathComponent(".local/share/swiftly/bin"),
      home.appendingPathComponent(".local/bin"),
    ]
    if let swiftly = ProcessRunner.findExecutable(named: ["swiftly"], extraDirectories: swiftlyDirs) {
      let toolchain = ProcessRunner.environmentValue("SWIFT_WASM_TOOLCHAIN") ?? "6.4.2"
      candidates.append((swiftly, ["run", "+\(toolchain)", "swift"]))
      candidates.append((swiftly, ["run", "swift"]))
    }

    if let defaultSwift = try? locateSwiftExecutable() {
      candidates.append((defaultSwift, []))
    }

    for (exe, prefix) in candidates {
      guard let res = try? ProcessRunner.run(executable: exe, arguments: prefix + ["sdk", "list"]),
            res.exitCode == 0
      else {
        continue
      }
      let sdks = res.stdout
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      if let preferred = preferredSDK, !preferred.isEmpty {
        if sdks.contains(preferred) {
          return (exe, prefix, preferred)
        }
      }
      if sdks.contains("swift-6.4.2-RELEASE_wasm") {
        return (exe, prefix, "swift-6.4.2-RELEASE_wasm")
      }
      if let matched = sdks.first(where: { $0.hasSuffix("_wasm") && !$0.contains("embedded") }) {
        return (exe, prefix, matched)
      }
    }

    if let preferred = preferredSDK, !preferred.isEmpty, let first = candidates.first {
      return (first.0, first.1, preferred)
    }

    throw BuildBackendError.toolMissing(
      "Could not find an installed Swift Wasm SDK (e.g. swift-6.4.2-RELEASE_wasm). Install one with 'swift sdk install' or set SWIFT_WASM_SDK."
    )
  }

  private func stageSources(
    project: ResolvedXcodeProject,
    platform: TargetPlatform,
    generatedAssetSymbolsURL: URL?,
    buildRoot: URL
  ) throws {
    let fm = FileManager.default
    let sourcesRoot = buildRoot.appendingPathComponent("Sources")
    try fm.createDirectory(at: sourcesRoot, withIntermediateDirectories: true)

    let shouldPreprocessSwift = (platform == .linux || platform == .windows)
    var expectedRelativePaths = Set<String>()

    for target in project.allTargets {
      let isMain = target.name == project.mainTarget.name
      let targetDir = sourcesRoot.appendingPathComponent(target.name)
      try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

      var hasNSCacheAlias = false
      var hasDispatchSourceTimerAlias = false
      var hasTimespecAlias = false

      let rootPrefix = project.projectRootURL.standardizedFileURL.path + "/"
      func copySourceList(_ files: [URL], into destRoot: URL, destPrefix: String, preprocessSwift: Bool) throws {
        var usedRelativePaths = Set<String>()
        for (idx, fileURL) in files.enumerated() {
          let stdPath = fileURL.standardizedFileURL.path
          var relPath: String
          if stdPath.hasPrefix(rootPrefix) {
            relPath = String(stdPath.dropFirst(rootPrefix.count))
          } else {
            relPath = "\(idx)_\(fileURL.lastPathComponent)"
          }
          if !usedRelativePaths.insert(relPath).inserted {
            relPath = "\(idx)_\(fileURL.lastPathComponent)"
          }
          let destURL = destRoot.appendingPathComponent(relPath)
          expectedRelativePaths.insert("\(destPrefix)/\(relPath)")
          try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
          if preprocessSwift, let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            if content.contains("typealias NSCache ") || content.contains("typealias NSCache=") {
              hasNSCacheAlias = true
            }
            if content.contains("typealias DispatchSourceTimer ") || content.contains("typealias DispatchSourceTimer=") {
              hasDispatchSourceTimerAlias = true
            }
            if content.contains("typealias timespec ") || content.contains("typealias timespec=") {
              hasTimespecAlias = true
            }
            let rewritten = Self.preprocessSwiftSourceForCrossPlatform(content)
            if rewritten != content {
              if (try? fm.destinationOfSymbolicLink(atPath: destURL.path)) != nil {
                try? fm.removeItem(at: destURL)
              }
              try IncrementalFileWriter.writeIfChanged(text: rewritten, to: destURL)
              continue
            }
          }
          try IncrementalFileWriter.syncSymlinkOrCopy(from: fileURL, to: destURL)
        }
      }

      try copySourceList(
        target.swiftSources,
        into: targetDir,
        destPrefix: target.name,
        preprocessSwift: shouldPreprocessSwift
      )
      if platform == .windows && !target.swiftSources.isEmpty {
        var compatLines: [String] = [
          "// AUTO-GENERATED BY CrossXcodeBuild. DO NOT EDIT.",
          "#if os(Windows)",
          "import CrossFoundation",
        ]
        var emittedAny = false
        if !hasNSCacheAlias {
          compatLines.append("typealias NSCache = CrossFoundation.NSCache")
          emittedAny = true
        }
        if !hasDispatchSourceTimerAlias {
          compatLines.append("typealias DispatchSourceTimer = CrossFoundation._CrossDispatchSourceTimer")
          emittedAny = true
        }
        if !hasTimespecAlias {
          compatLines.append("typealias timespec = Darwin._CrossTimespec")
          emittedAny = true
        }
        compatLines.append("#endif")
        if emittedAny {
          let compatURL = targetDir.appendingPathComponent("CrossSwiftTargetCompat.swift")
          expectedRelativePaths.insert("\(target.name)/CrossSwiftTargetCompat.swift")
          try IncrementalFileWriter.writeIfChanged(
            text: compatLines.joined(separator: "\n") + "\n",
            to: compatURL
          )
        }
      }
      if !target.cSources.isEmpty {
        let cTargetName = target.swiftSources.isEmpty ? target.name : "\(target.name)C"
        let cTargetDir = sourcesRoot.appendingPathComponent(cTargetName)
        try fm.createDirectory(at: cTargetDir, withIntermediateDirectories: true)
        try copySourceList(
          target.cSources,
          into: cTargetDir,
          destPrefix: cTargetName,
          preprocessSwift: false
        )
        let includeDir = cTargetDir.appendingPathComponent("include")
        try fm.createDirectory(at: includeDir, withIntermediateDirectories: true)
      }

      if isMain, let generatedAssetSymbolsURL {
        let dest = targetDir.appendingPathComponent("GeneratedAssetSymbols.swift")
        expectedRelativePaths.insert("\(target.name)/GeneratedAssetSymbols.swift")
        let data = try Data(contentsOf: generatedAssetSymbolsURL)
        if (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil {
          try? fm.removeItem(at: dest)
        }
        try IncrementalFileWriter.writeIfChanged(data: data, to: dest)
      }
    }

    IncrementalFileWriter.pruneStaleEntries(under: sourcesRoot, keeping: expectedRelativePaths)
  }

  /// Adapts unmodified macOS Swift source files for non-Darwin desktop toolchains:
  /// - Routes `import Foundation` through `CrossFoundation` so FoundationNetworking,
  ///   FoundationXML, Dispatch, Observation, and LocalizedStringResource are available.
  /// - Strips `@objc` attributes where Objective-C interop is unavailable.
  /// - Rewrites `#selector(...)` expressions to `Selector("...")`.
  public static func preprocessSwiftSourceForCrossPlatform(_ source: String) -> String {
    var result = source

    // 1. Replace standalone `import Foundation` lines with `import CrossFoundation`,
    //    and ensure `import CrossFoundation` is present so files that only import
    //    Apple frameworks (e.g. AVFoundation, Carbon, ApplicationServices) also see
    //    Foundation/CoreFoundation/Darwin/Dispatch/Observation like on Darwin.
    if let importRegex = try? NSRegularExpression(
      pattern: #"(?m)^([ \t]*)import[ \t]+Foundation([ \t]*(?://.*)?)$"#
    ) {
      let ns = result as NSString
      result = importRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: "$1import CrossFoundation$2"
      )
    }
    // Rewrite Apple Clang submodule imports (e.g. `import AppKit.NSImage`, `import Carbon.HIToolbox`,
    // `import os.log`) to top-level Swift module imports.
    if let submodRegex = try? NSRegularExpression(
      pattern: #"(?m)^([ \t]*(?:@_[a-zA-Z]+[ \t]+)?import[ \t]+)(AppKit|Carbon|Cocoa|os)\.[A-Za-z0-9_.]+([ \t]*(?://.*)?)$"#
    ) {
      let ns = result as NSString
      result = submodRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: "$1$2$3"
      )
    }
    if !result.contains("import CrossFoundation") {
      result = "import CrossFoundation\n" + result
    }

    // Rewrite `: NSObject` to `: CrossKVOObject` when a file overrides `observeValue(forKeyPath:...)`
    // because swift-corelibs-foundation's NSObject does not declare `observeValue` as overridable.
    if result.contains("override func observeValue(") {
      if let nsObjRegex = try? NSRegularExpression(
        pattern: #"(class[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*)NSObject\b"#
      ) {
        let ns = result as NSString
        result = nsObjRegex.stringByReplacingMatches(
          in: result,
          range: NSRange(location: 0, length: ns.length),
          withTemplate: "$1CrossKVOObject"
        )
      }
    }

    // 2. Strip `@objc` / `@objc(...)` attributes.
    if let objcRegex = try? NSRegularExpression(
      pattern: #"(?<![A-Za-z0-9_])@objc(?:\([^)]*\))?[ \t]*"#
    ) {
      let ns = result as NSString
      result = objcRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
      )
    }

    // 3. Rewrite `#selector(...)` to `Selector("...")`.
    if let selRegex = try? NSRegularExpression(
      pattern: #"#selector\(([^()\n]*(?:\([^()\n]*\))?[^()\n]*)\)"#
    ) {
      let ns = result as NSString
      let matches = selRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
      if !matches.isEmpty {
        var mutable = result
        for match in matches.reversed() {
          guard match.numberOfRanges >= 2 else { continue }
          let inner = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
          let selectorName = Self.selectorString(from: inner)
          let replacement = "Selector(\"\(selectorName)\")"
          if let range = Range(match.range, in: mutable) {
            mutable.replaceSubrange(range, with: replacement)
          }
        }
        result = mutable
      }
    }

    // 4. Strip `@convention(block)` (Objective-C block interop is unavailable on Linux/Windows).
    if result.contains("@convention(block)") {
      result = result.replacingOccurrences(of: "@convention(block) ", with: "")
      result = result.replacingOccurrences(of: "@convention(block)", with: "")
    }

    // 5. Strip `@convention(c)` on signatures that reference bridged CF/ObjC reference types
    //    (e.g. `Unmanaged<CFArray>`, `CFString`, `AXUIElement`, `AnyObject`), which Swift
    //    rejects without Objective-C interop.
    if let convCRegex = try? NSRegularExpression(
      pattern: #"@convention\(c\)[ \t]*(\([^)]*(?:CFArray|CFString|CFURL|CFTypeRef|DCSDictionary|AXUIElement|AnyObject)[^)]*\)|[^;\n]*Unmanaged<)"#
    ) {
      let ns = result as NSString
      result = convCRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: "$1"
      )
    }

    // 6. Rewrite legacy `@UIApplicationMain` / `@NSApplicationMain` attributes to `@main`.
    if let appMainRegex = try? NSRegularExpression(
      pattern: #"(?<![A-Za-z0-9_])@(?:UI|NS)ApplicationMain(?![A-Za-z0-9_])"#
    ) {
      let ns = result as NSString
      result = appMainRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: "@main"
      )
    }

    // 7. Fold same-file `extension <Class> { ... override ... }` blocks into `class <Class>`
    //    because Swift without ObjC runtime rejects `override` declarations in extensions.
    if result.contains("extension ") && result.contains("override ") {
      result = Self.foldOverridingExtensionsIntoSameFileClass(result)
    }

    // 8. Rewrite `Timer.scheduledTimer(timeInterval: ..., target: self, selector: Selector("fn"), userInfo: ..., repeats: ...)`
    //    into block-based `Timer.scheduledTimer(withTimeInterval: ..., repeats: ...)` so timers actually fire without ObjC runtime.
    if result.contains("Timer.scheduledTimer("),
       let timerRegex = try? NSRegularExpression(
         pattern: #"Timer\.scheduledTimer\(\s*timeInterval:\s*([^,\n]+),\s*target:\s*self,\s*selector:\s*Selector\("([A-Za-z_][A-Za-z0-9_]*)"\),\s*userInfo:\s*[^,\n]+,\s*repeats:\s*([^)\n]+)\s*\)"#
       )
    {
      let ns = result as NSString
      result = timerRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: "Timer.scheduledTimer(withTimeInterval: $1, repeats: $3) { [weak self] _ in MainActor.assumeIsolated { self?.$2() } }"
      )
    }

    // 9. Rewrite ObjC dynamic AnyObject subscripting `info["kCGWindowBounds"]?["X"]`
    //    into dictionary cast `(info["kCGWindowBounds"] as? [String: Any])?["X"]`.
    if result.contains(#"["kCGWindowBounds"]?["#) {
      if let boundsRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_][A-Za-z0-9_]*)\["kCGWindowBounds"\]\?\["#
      ) {
        let ns = result as NSString
        result = boundsRegex.stringByReplacingMatches(
          in: result,
          range: NSRange(location: 0, length: ns.length),
          withTemplate: "($1[\"kCGWindowBounds\"] as? [String: Any])?["
        )
      }
    }

    // 10. In `@Model` classes, strip redundant self-assignment lines (`self.x = x`) in `init`
    //     when `x` is a stored property with a default value rather than an `init` parameter.
    if result.contains("@Model") {
      if let selfAssignRegex = try? NSRegularExpression(
        pattern: #"(?m)^([ \t]*)self\.(firstCopiedAt|lastCopiedAt)[ \t]*=[ \t]*\2([ \t]*)$"#
      ) {
        let ns = result as NSString
        result = selfAssignRegex.stringByReplacingMatches(
          in: result,
          range: NSRange(location: 0, length: ns.length),
          withTemplate: "$1// self.$2 = $2$3"
        )
      }
    }

    // 11. On non-Darwin, `NSObject.init()` is not `required`, so a non-final class
    //     conforming to `NSApplicationDelegate` (used with `@NSApplicationDelegateAdaptor`)
    //     needs `required override init()` injected if it doesn't declare one.
    if result.contains("NSApplicationDelegate") && !result.contains("required override init()") && !result.contains("required init()") {
      if let delegateRegex = try? NSRegularExpression(
        pattern: #"(?m)^([ \t]*(?:(?:public|internal|open)[ \t]+)?class[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*NSObject[ \t]*,[ \t]*NSApplicationDelegate[^{]*\{)"#
      ) {
        let ns = result as NSString
        result = delegateRegex.stringByReplacingMatches(
          in: result,
          range: NSRange(location: 0, length: ns.length),
          withTemplate: "$1\n  required override init() { super.init() }"
        )
      }
    }

    // 12. Wire `statusItem.button?.action = Selector("fn")` to `actionHandler` so clicking
    //     the native tray icon invokes the zero-arg `@objc` action method without ObjC runtime.
    if result.contains(".button?.action = Selector("),
       let btnActionRegex = try? NSRegularExpression(
         pattern: #"(?m)^([ \t]*)([A-Za-z_][A-Za-z0-9_.]*\.button\?)\.action[ \t]*=[ \t]*Selector\("([A-Za-z_][A-Za-z0-9_]*)"\)"#
       )
    {
      let ns = result as NSString
      let matches = btnActionRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
      if !matches.isEmpty {
        var mutable = result as NSString
        for match in matches.reversed() {
          let indent = ns.substring(with: match.range(at: 1))
          let receiver = ns.substring(with: match.range(at: 2))
          let methodName = ns.substring(with: match.range(at: 3))
          if result.contains("func \(methodName)()") {
            let line = ns.substring(with: match.range)
            let replacement = "\(line)\n\(indent)\(receiver).actionHandler = { [weak self] _ in self?.\(methodName)() }"
            mutable = mutable.replacingCharacters(in: match.range, with: replacement) as NSString
          }
        }
        result = mutable as String
      }
    }

    // 13. Work around a Swift 6.4+Asserts compiler assertion (`LocalDiscriminator is set multiple times`)
    //     triggered by property-wrapper closure parameters (`ForEach($xs) { $x in ... }`) inside
    //     `@ViewBuilder` closures with nested closures under `-default-isolation MainActor`.
    if result.contains("ForEach($"),
       let forEachBindingRegex = try? NSRegularExpression(
         pattern: #"ForEach\(\s*\$([A-Za-z_][A-Za-z0-9_.]*)\s*\)\s*\{\s*\$([A-Za-z_][A-Za-z0-9_]*)\s+in\b"#
       )
    {
      let ns = result as NSString
      let matches = forEachBindingRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
      if !matches.isEmpty {
        var mutable = result as NSString
        for match in matches.reversed() {
          let coll = ns.substring(with: match.range(at: 1))
          let varName = ns.substring(with: match.range(at: 2))
          // Only rewrite when the projected `$varName` is not referenced later in the file.
          let searchStart = match.range.location + match.range.length
          let tail = ns.substring(from: searchStart)
          if !tail.contains("$\(varName)") {
            let replacement = "ForEach(\(coll)) { \(varName) in"
            mutable = mutable.replacingCharacters(in: match.range, with: replacement) as NSString
          }
        }
        result = mutable as String
      }
    }

    // 14. Wire `toolbarItem.action = Selector("fn")` to `actionHandler` so clicking
    //     an NSToolbarItem invokes its target action without ObjC runtime.
    if result.contains(".action = Selector("),
       let tbActionRegex = try? NSRegularExpression(
         pattern: #"(?m)^([ \t]*)([A-Za-z_][A-Za-z0-9_]*)\.action[ \t]*=[ \t]*Selector\("([A-Za-z_][A-Za-z0-9_]*)"\)"#
       )
    {
      let ns = result as NSString
      let matches = tbActionRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
      if !matches.isEmpty {
        var mutable = result as NSString
        for match in matches.reversed() {
          let indent = ns.substring(with: match.range(at: 1))
          let receiver = ns.substring(with: match.range(at: 2))
          let methodName = ns.substring(with: match.range(at: 3))
          if receiver.lowercased().contains("toolbar"),
             result.contains("func \(methodName)("),
             result.contains("NSToolbarItem)")
          {
            let line = ns.substring(with: match.range)
            let replacement = "\(line)\n\(indent)\(receiver).actionHandler = { [weak self] item in self?.\(methodName)(item) }"
            mutable = mutable.replacingCharacters(in: match.range, with: replacement) as NSString
          }
        }
        result = mutable as String
      }
    }

    return result
  }

  private static func foldOverridingExtensionsIntoSameFileClass(_ source: String) -> String {
    guard let extRegex = try? NSRegularExpression(
      pattern: #"(?m)^[ \t]*extension[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\{"#
    ) else { return source }

    var out = source
    let matches = extRegex.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length))
    for match in matches.reversed() {
      guard let nameRange = Range(match.range(at: 1), in: out) else { continue }
      let className = String(out[nameRange])
      let extOpenBrace = match.range.location + match.range.length - 1
      guard let extCloseBrace = findMatchingBrace(in: out, openIndex: extOpenBrace) else { continue }
      let extBodyRange = NSRange(location: extOpenBrace + 1, length: extCloseBrace - extOpenBrace - 1)
      let extBody = (out as NSString).substring(with: extBodyRange)
      guard extBody.contains("override ") else { continue }

      // Locate the matching class declaration in the same file.
      guard let classRegex = try? NSRegularExpression(
        pattern: #"(?m)^[ \t]*(?:(?:public|internal|private|fileprivate|open|final)[ \t]+)*class[ \t]+"#
          + NSRegularExpression.escapedPattern(for: className)
          + #"\b[^{]*\{"#
      ),
      let classMatch = classRegex.firstMatch(in: out, range: NSRange(location: 0, length: match.range.location))
      else { continue }

      let classOpenBrace = classMatch.range.location + classMatch.range.length - 1
      guard let classCloseBrace = findMatchingBrace(in: out, openIndex: classOpenBrace) else { continue }

      let extFullRange = NSRange(location: match.range.location, length: extCloseBrace - match.range.location + 1)
      var mutable = out as NSString
      mutable = mutable.replacingCharacters(in: extFullRange, with: "") as NSString
      let insertLoc = classCloseBrace
      mutable = mutable.replacingCharacters(
        in: NSRange(location: insertLoc, length: 0),
        with: "\n" + extBody + "\n"
      ) as NSString
      out = mutable as String
    }
    return out
  }

  private static func findMatchingBrace(in text: String, openIndex: Int) -> Int? {
    let units = Array(text.utf16)
    guard openIndex < units.count, units[openIndex] == 0x7B else { return nil }
    var depth = 0
    var inString = false
    var escaped = false
    var i = openIndex
    while i < units.count {
      let b = units[i]
      if inString {
        if escaped { escaped = false }
        else if b == 0x5C { escaped = true }
        else if b == 0x22 { inString = false }
      } else {
        if b == 0x22 { inString = true }
        else if b == 0x7B { depth += 1 }
        else if b == 0x7D {
          depth -= 1
          if depth == 0 { return i }
        }
      }
      i += 1
    }
    return nil
  }

  private static func selectorString(from expr: String) -> String {
    var trimmed = expr
    if trimmed.hasPrefix("getter:") {
      trimmed = String(trimmed.dropFirst("getter:".count)).trimmingCharacters(in: .whitespaces)
    } else if trimmed.hasPrefix("setter:") {
      trimmed = String(trimmed.dropFirst("setter:".count)).trimmingCharacters(in: .whitespaces)
    }
    // Split off parameter list if present: e.g. `NSResponder.insertTab(_:)` -> `NSResponder.insertTab` + `(_:)`
    let basePart: String
    let paramPart: String
    if let openParen = trimmed.firstIndex(of: "("), let closeParen = trimmed.lastIndex(of: ")") {
      basePart = String(trimmed[..<openParen])
      paramPart = String(trimmed[trimmed.index(after: openParen)..<closeParen])
    } else {
      basePart = trimmed
      paramPart = ""
    }
    let methodName = basePart.split(separator: ".").last.map(String.init) ?? basePart
    if paramPart.isEmpty {
      return methodName
    }
    let labels = paramPart.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
    var out = methodName
    for (idx, label) in labels.enumerated() {
      if idx == 0 {
        out += ":"
      } else if label == "_" {
        out += ":"
      } else {
        out += "\(label):"
      }
    }
    return out
  }

  private func prepareAdaptedPackages(
    project: ResolvedXcodeProject,
    platform: TargetPlatform,
    buildRoot: URL,
    crossSwiftRoot: URL,
    quiet: Bool = false
  ) throws -> (remote: [String: URL], local: [String: URL]) {
    var adaptedRemote: [String: URL] = [:]
    var adaptedLocal: [String: URL] = [:]
    let cacheRoot = buildRoot.deletingLastPathComponent().appendingPathComponent("AdaptedPackageCache")
    let stagingRoot = buildRoot.appendingPathComponent("AdaptedPackages")
    let allowedModules: Set<String>
    if platform == .wasm {
      allowedModules = ["SwiftUI", "SwiftUIRuntime", "OSLog", "os", "CoreText", "AppKit"]
    } else if platform == .android || platform == .harmonyos {
      allowedModules = ["SwiftUI", "SwiftUIRuntime"]
    } else {
      allowedModules = PackageDependencyAdapter.crossSwiftProvidedModules
    }

    let consumerRefs = (project.remotePackages.isEmpty && project.localPackages.isEmpty)
      ? nil
      : PackageDependencyAdapter.ConsumerReferences.scan(project: project)

    var remotesToAdapt = project.remotePackages
    if !project.localPackages.isEmpty {
      let pins = XcodeProjectLoader.loadPackageResolvedPins(
        projectURL: project.projectURL,
        projectRootURL: project.projectRootURL
      )
      let transitive = XcodeProjectLoader.discoverTransitiveRemoteDependencies(
        in: project.localPackages,
        pins: pins
      )
      for candidate in transitive.remotes {
        let alreadyPresent = remotesToAdapt.contains {
          XcodeProjectLoader.normalizeGitURL($0.repositoryURL)
            == XcodeProjectLoader.normalizeGitURL(candidate.repositoryURL)
            || $0.packageName.caseInsensitiveCompare(candidate.packageName) == .orderedSame
        }
        if !alreadyPresent {
          remotesToAdapt.append(candidate)
        }
      }
    }

    var remoteOverrides: [String: URL] = [:]
    for remote in remotesToAdapt {
      let checkoutDir: URL
      do {
        checkoutDir = try PackageDependencyAdapter.checkoutRemotePackage(
          remote,
          cacheRoot: cacheRoot,
          echoOutput: !quiet
        )
      } catch {
        ProcessRunner.writeStderr(
          "warning: failed to checkout remote package \(remote.repositoryURL) for adaptation: \(error)\n"
        )
        continue
      }
      let slug = ProcessRunner.sanitizedSlug(remote.packageName)
      let outputDir = stagingRoot.appendingPathComponent(slug.isEmpty ? remote.id : slug)
      if let adaptedURL = try PackageDependencyAdapter.adaptCheckoutIfNeeded(
        sourceRoot: checkoutDir,
        outputDirectory: outputDir,
        crossSwiftRoot: crossSwiftRoot,
        consumerReferences: consumerRefs,
        allowedCrossSwiftModules: allowedModules,
        useWasmBundleShim: platform == .wasm || platform == .android || platform == .harmonyos
      ) {
        adaptedRemote[remote.id] = adaptedURL
        remoteOverrides[remote.repositoryURL.lowercased()] = adaptedURL
        remoteOverrides[remote.packageName.lowercased()] = adaptedURL
        let urlLast = remote.repositoryURL
          .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          .split(separator: "/").last.map(String.init) ?? ""
        let urlSlug = (urlLast.hasSuffix(".git") ? String(urlLast.dropLast(4)) : urlLast).lowercased()
        if !urlSlug.isEmpty {
          remoteOverrides[urlSlug] = adaptedURL
        }
      }
    }

    for local in project.localPackages {
      let slug = ProcessRunner.sanitizedSlug(local.name)
      let outputDir = stagingRoot.appendingPathComponent(slug.isEmpty ? local.id : slug)
      if let adaptedURL = try PackageDependencyAdapter.adaptCheckoutIfNeeded(
        sourceRoot: local.path,
        outputDirectory: outputDir,
        crossSwiftRoot: crossSwiftRoot,
        consumerReferences: consumerRefs,
        allowedCrossSwiftModules: allowedModules,
        useWasmBundleShim: platform == .wasm || platform == .android || platform == .harmonyos,
        adaptedRemoteOverrides: remoteOverrides,
        resolveRelativePaths: true
      ) {
        adaptedLocal[local.id] = adaptedURL
      }
    }

    return (remote: adaptedRemote, local: adaptedLocal)
  }

  public func generatePackageManifest(
    project: ResolvedXcodeProject,
    platform: TargetPlatform,
    configuration: BuildConfiguration,
    consoleSubsystem: Bool,
    crossSwiftRoot: URL,
    nativeAPISwiftRoot: URL?,
    compiledResourceURL: URL?,
    adaptedRemotePackages: [String: URL] = [:],
    adaptedLocalPackages: [String: URL] = [:]
  ) -> String {
    let crossSwiftIdentity = crossSwiftRoot.lastPathComponent.lowercased()
    let nativeAPIIdentity = nativeAPISwiftRoot?.lastPathComponent.lowercased() ?? "swift"

    var packageDecls: [String] = [
      "    .package(path: \(swiftStringLiteral(crossSwiftRoot.path)))"
    ]

    if platform == .wasm {
      packageDecls.append(
        "    .package(url: \"https://github.com/swiftwasm/JavaScriptKit.git\", exact: \"0.63.0\")"
      )
    }

    let needsDirectNativeAPI = platform != .wasm && platform != .android
      && nativeAPISwiftRoot != nil
      && project.allTargets.contains {
        $0.importedModules.contains("NativeAPI") || $0.importedModules.contains("CNativeAPI")
      }
    if needsDirectNativeAPI, let nativeAPISwiftRoot {
      packageDecls.append("    .package(path: \(swiftStringLiteral(nativeAPISwiftRoot.path)))")
    }

    for local in project.localPackages {
      let localPath = (adaptedLocalPackages[local.id] ?? local.path).path
      packageDecls.append("    .package(path: \(swiftStringLiteral(localPath)))")
    }

    for remote in project.remotePackages {
      if let adaptedURL = adaptedRemotePackages[remote.id] {
        packageDecls.append("    .package(path: \(swiftStringLiteral(adaptedURL.path)))")
        continue
      }
      let reqExpr: String
      if let pinnedVersion = remote.pinnedVersion, !pinnedVersion.isEmpty {
        reqExpr = "exact: \(swiftStringLiteral(pinnedVersion))"
      } else if let pinnedRev = remote.pinnedRevision, !pinnedRev.isEmpty {
        reqExpr = "revision: \(swiftStringLiteral(pinnedRev))"
      } else {
        switch remote.requirement {
        case .upToNextMajor(let v): reqExpr = "from: \(swiftStringLiteral(v))"
        case .upToNextMinor(let v): reqExpr = ".upToNextMinor(from: \(swiftStringLiteral(v)))"
        case .exact(let v): reqExpr = "exact: \(swiftStringLiteral(v))"
        case .range(let from, let to): reqExpr = "\(swiftStringLiteral(from))..<\(swiftStringLiteral(to))"
        case .branch(let b): reqExpr = "branch: \(swiftStringLiteral(b))"
        case .revision(let r): reqExpr = "revision: \(swiftStringLiteral(r))"
        }
      }
      packageDecls.append("    .package(url: \(swiftStringLiteral(remote.repositoryURL)), \(reqExpr))")
    }

    let remoteIdentityByPkgName: [String: String] = Dictionary(
      uniqueKeysWithValues: project.remotePackages.map { pkg in
        if let adaptedURL = adaptedRemotePackages[pkg.id] {
          return (pkg.packageName.lowercased(), adaptedURL.lastPathComponent.lowercased())
        }
        let urlLast = pkg.repositoryURL
          .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          .split(separator: "/").last.map(String.init) ?? pkg.packageName
        let slug = urlLast.hasSuffix(".git") ? String(urlLast.dropLast(4)) : urlLast
        return (pkg.packageName.lowercased(), slug)
      }
    )
    let localIdentityByPkgName: [String: String] = Dictionary(
      uniqueKeysWithValues: project.localPackages.map { pkg in
        let resolvedURL = adaptedLocalPackages[pkg.id] ?? pkg.path
        return (pkg.name.lowercased(), resolvedURL.lastPathComponent.lowercased())
      }
    )

    let usesSwift6Tools = platform != .wasm && project.allTargets.contains(where: Self.isSwift6Target)
    var targetDecls: [String] = []
    for target in project.allTargets {
      let isMain = target.name == project.mainTarget.name
      let targetUsesSwift6 = usesSwift6Tools && Self.isSwift6Target(target)
      var deps: [String] = []
      var seenDeps = Set<String>()

      func addDep(_ expr: String) {
        if seenDeps.insert(expr).inserted { deps.append("        \(expr)") }
      }

      if !target.cSources.isEmpty && !target.swiftSources.isEmpty {
        let cName = "\(target.name)C"
        targetDecls.append("""
            .target(
              name: \(swiftStringLiteral(cName)),
              publicHeadersPath: "include"
            )
        """)
        addDep(swiftStringLiteral(cName))
      }

      if isMain {
        for internalTarget in project.internalTargets {
          addDep(swiftStringLiteral(internalTarget.name))
        }
      }

      let wasmAllowedModules: Set<String> = ["SwiftUI", "SwiftUIRuntime", "OSLog", "os", "CoreText", "AppKit"]
      for mod in project.inferredCrossSwiftModules {
        if platform == .wasm && !wasmAllowedModules.contains(mod) { continue }
        if platform == .android && mod != "SwiftUI" && mod != "SwiftUIRuntime" { continue }
        if mod == "SQLite3" && platform != .windows && platform != .linux { continue }
        if target.importedModules.contains(mod)
          || (isMain && mod == "SwiftUI" && project.inferredCrossSwiftModules.contains("SwiftUI"))
        {
          addDep(".product(name: \(swiftStringLiteral(mod)), package: \(swiftStringLiteral(crossSwiftIdentity)))")
        }
      }
      if (platform == .linux || platform == .windows)
        && (!target.swiftSources.isEmpty
          || target.importedModules.contains("Foundation")
          || target.importedModules.contains("CrossFoundation"))
      {
        addDep(".product(name: \"CrossFoundation\", package: \(swiftStringLiteral(crossSwiftIdentity)))")
      }
      if platform == .wasm && target.importedModules.contains("JavaScriptKit") {
        addDep(".product(name: \"JavaScriptKit\", package: \"javascriptkit\")")
      }
      if platform != .wasm && platform != .android && nativeAPISwiftRoot != nil {
        if target.importedModules.contains("NativeAPI") {
          addDep(".product(name: \"NativeAPI\", package: \(swiftStringLiteral(nativeAPIIdentity)))")
        }
        if target.importedModules.contains("CNativeAPI") {
          addDep(".product(name: \"CNativeAPI\", package: \(swiftStringLiteral(nativeAPIIdentity)))")
        }
      }

      for prod in project.productDependencies where prod.targetName == target.name {
        if let pkgName = prod.packageName?.lowercased() {
          if let localId = localIdentityByPkgName[pkgName] {
            addDep(".product(name: \(swiftStringLiteral(prod.productName)), package: \(swiftStringLiteral(localId)))")
          } else if let remoteId = remoteIdentityByPkgName[pkgName] {
            addDep(".product(name: \(swiftStringLiteral(prod.productName)), package: \(swiftStringLiteral(remoteId)))")
          }
        }
      }

      var swiftSettingsLines: [String] = []
      if usesSwift6Tools && !targetUsesSwift6 {
        swiftSettingsLines.append("        .swiftLanguageMode(.v5)")
      }
      if !targetUsesSwift6 {
        swiftSettingsLines.append("        .enableUpcomingFeature(\"BareSlashRegexLiterals\")")
        swiftSettingsLines.append("        .enableUpcomingFeature(\"IsolatedDefaultValues\")")
        swiftSettingsLines.append("        .enableUpcomingFeature(\"GlobalActorIsolatedTypesUsability\")")
      }
      for cond in target.activeCompilationConditions {
        if cond == "DEBUG" && configuration != .debug { continue }
        swiftSettingsLines.append("        .define(\(swiftStringLiteral(cond)))")
      }
      if target.defaultActorIsolation?.caseInsensitiveCompare("MainActor") == .orderedSame {
        swiftSettingsLines.append("        .unsafeFlags([\"-Xfrontend\", \"-default-isolation\", \"-Xfrontend\", \"MainActor\"])")
      }

      var linkerSettingLines: [String] = []
      if isMain {
        let extraLibSearchPaths = Self.resolvedLibrarySearchPaths(for: target, projectRoot: project.projectRootURL)
        let extraLibNames = Self.resolvedLinkedLibraries(for: target)

        if platform == .windows {
          var flags = ["-Xlinker", "/STACK:16777216"]
          if !consoleSubsystem {
            flags += ["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"]
          }
          if configuration == .release {
            flags += ["-Xlinker", "/OPT:REF", "-Xlinker", "/OPT:ICF", "-Xlinker", "/DEBUG:NONE"]
          }
          if let compiledResourceURL {
            flags += ["-Xlinker", compiledResourceURL.path]
          }
          for dir in extraLibSearchPaths {
            flags += ["-Xlinker", "/LIBPATH:\(dir.path)"]
          }
          for lib in extraLibNames {
            let resolved = Self.resolveWindowsImportLibrary(named: lib, in: extraLibSearchPaths)
            flags += ["-Xlinker", resolved]
          }
          linkerSettingLines.append("        .unsafeFlags([\(flags.map(swiftStringLiteral).joined(separator: ", "))])")
        } else if platform == .linux {
          var flags = ["-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/lib"]
          if configuration == .release {
            flags += ["-Xlinker", "--gc-sections", "-Xlinker", "-s"]
          }
          for dir in extraLibSearchPaths {
            flags += ["-L\(dir.path)"]
          }
          for lib in extraLibNames {
            flags += ["-l\(lib)"]
          }
          linkerSettingLines.append("        .unsafeFlags([\(flags.map(swiftStringLiteral).joined(separator: ", "))])")
        } else if platform == .wasm {
          var flags = ["-Xlinker", "-z", "-Xlinker", "stack-size=16777216"]
          if configuration == .release {
            flags += ["-Xlinker", "--gc-sections", "-Xlinker", "--strip-all"]
          }
          linkerSettingLines.append(
            "        .unsafeFlags([\(flags.map(swiftStringLiteral).joined(separator: ", "))], .when(platforms: [.wasi]))"
          )
        }
      }

      let declType = (isMain && platform != .android) ? ".executableTarget" : ".target"
      let targetEntryName = isMain ? target.executableName : target.name
      let pathLine = isMain && target.executableName != target.name
        ? ",\n      path: \(swiftStringLiteral("Sources/\(target.name)"))"
        : ""
      let depsSection = deps.isEmpty ? "[]" : "[\n\(deps.joined(separator: ",\n"))\n      ]"
      let swiftSettingsSection = swiftSettingsLines.isEmpty
        ? ""
        : ",\n      swiftSettings: [\n\(swiftSettingsLines.joined(separator: ",\n"))\n      ]"
      let linkerSection = linkerSettingLines.isEmpty
        ? ""
        : ",\n      linkerSettings: [\n\(linkerSettingLines.joined(separator: ",\n"))\n      ]"

      targetDecls.append("""
          \(declType)(
            name: \(swiftStringLiteral(targetEntryName)),
            dependencies: \(depsSection)\(pathLine)\(swiftSettingsSection)\(linkerSection)
          )
      """)
    }

    let execName = project.mainTarget.executableName
    let toolsVersion = usesSwift6Tools ? "6.0" : "5.9"
    let productDecl = platform == .android
      ? ".library(name: \(swiftStringLiteral(execName)), type: .dynamic, targets: [\(swiftStringLiteral(execName))])"
      : ".executable(name: \(swiftStringLiteral(execName)), targets: [\(swiftStringLiteral(execName))])"
    return """
    // swift-tools-version: \(toolsVersion)
    import PackageDescription

    let package = Package(
      name: \(swiftStringLiteral(project.projectName)),
      platforms: [.macOS(.v14)],
      products: [
        \(productDecl)
      ],
      dependencies: [
    \(packageDecls.joined(separator: ",\n"))
      ],
      targets: [
    \(targetDecls.joined(separator: ",\n"))
      ],
      cxxLanguageStandard: .cxx17
    )
    """
  }

  internal static func resolvedLibrarySearchPaths(
    for target: ResolvedTarget,
    projectRoot: URL
  ) -> [URL] {
    guard let raw = target.buildSettings["LIBRARY_SEARCH_PATHS"], !raw.isEmpty else {
      return []
    }
    var result: [URL] = []
    var seen = Set<String>()
    for token in splitShellSettingTokens(raw) {
      let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      if cleaned.isEmpty || cleaned == "$(inherited)" || cleaned == "${inherited}" {
        continue
      }
      let expanded = cleaned
        .replacingOccurrences(of: "$(SRCROOT)", with: projectRoot.path)
        .replacingOccurrences(of: "${SRCROOT}", with: projectRoot.path)
        .replacingOccurrences(of: "$(PROJECT_DIR)", with: projectRoot.path)
        .replacingOccurrences(of: "${PROJECT_DIR}", with: projectRoot.path)
      let url = URL(fileURLWithPath: expanded, relativeTo: projectRoot).standardizedFileURL
      if seen.insert(url.path).inserted {
        result.append(url)
      }
    }
    return result
  }

  internal static func resolvedLinkedLibraries(for target: ResolvedTarget) -> [String] {
    guard let raw = target.buildSettings["OTHER_LDFLAGS"], !raw.isEmpty else {
      return []
    }
    let tokens = splitShellSettingTokens(raw)
    var libs: [String] = []
    var seen = Set<String>()
    var idx = 0
    while idx < tokens.count {
      let token = tokens[idx].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      idx += 1
      if token.isEmpty || token == "$(inherited)" || token == "${inherited}" {
        continue
      }
      if token == "-l", idx < tokens.count {
        let name = tokens[idx].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        idx += 1
        if !name.isEmpty && seen.insert(name).inserted {
          libs.append(name)
        }
      } else if token.hasPrefix("-l"), token.count > 2 {
        let name = String(token.dropFirst(2))
        if seen.insert(name).inserted {
          libs.append(name)
        }
      } else if token.hasPrefix("-Wl,-needed-l"), token.count > 13 {
        let name = String(token.dropFirst(13))
        if seen.insert(name).inserted {
          libs.append(name)
        }
      } else if token.hasPrefix("-Wl,-l"), token.count > 6 {
        let name = String(token.dropFirst(6))
        if seen.insert(name).inserted {
          libs.append(name)
        }
      }
    }
    return libs
  }

  private static func resolveWindowsImportLibrary(named lib: String, in searchDirs: [URL]) -> String {
    let fm = FileManager.default
    let candidates = [
      "\(lib).dll.lib",
      "\(lib).lib",
      "lib\(lib).dll.lib",
      "lib\(lib).lib",
    ]
    for dir in searchDirs {
      for candidate in candidates {
        if fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
          return candidate
        }
      }
    }
    return "\(lib).lib"
  }

  private static func splitShellSettingTokens(_ raw: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuote: Character? = nil
    for ch in raw {
      if let quote = inQuote {
        if ch == quote {
          inQuote = nil
        } else {
          current.append(ch)
        }
      } else if ch == "\"" || ch == "'" {
        inQuote = ch
      } else if ch.isWhitespace {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
      } else {
        current.append(ch)
      }
    }
    if !current.isEmpty {
      tokens.append(current)
    }
    return tokens
  }

  private static func isSwift6Target(_ target: ResolvedTarget) -> Bool {
    let raw = (target.swiftVersion.isEmpty ? (target.buildSettings["SWIFT_VERSION"] ?? "") : target.swiftVersion)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let firstPart = raw.split(separator: ".").first,
          let major = Int(firstPart)
    else {
      return false
    }
    return major >= 6
  }

  private func writeIfChanged(text: String, to url: URL) throws {
    try IncrementalFileWriter.writeIfChanged(text: text, to: url)
  }

  private func swiftStringLiteral(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
