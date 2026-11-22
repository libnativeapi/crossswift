import Foundation

public enum XcodeBuildParseOutcome: Sendable {
  case showHelp
  case run(XcodeBuildOptions)
}

public enum XcodeBuildDriverError: Error, LocalizedError {
  case invalidArguments(String)
  case unsupportedBuildHost(requested: TargetPlatform?, host: TargetPlatform?)
  case unsupportedConfiguration(String)

  public var errorDescription: String? {
    switch self {
    case .invalidArguments(let msg):
      return msg
    case .unsupportedBuildHost(let requested, let host):
      if let requested, let host {
        return "Cannot build target platform '\(requested.rawValue)' on '\(host.rawValue)' host."
      }
      if let requested {
        return "Cannot build target platform '\(requested.rawValue)' on this host; run on a \(requested.rawValue) host."
      }
      return "CrossSwiftUI xcodebuild builds Windows/Linux targets natively and cross-compiles Wasm/HarmonyOS/Android targets from macOS or Linux (pass -destination generic/platform=Wasm, HarmonyOS, or Android)."
    case .unsupportedConfiguration(let raw):
      return "Unsupported build configuration '\(raw)' (expected Debug or Release)."
    }
  }
}

public enum XcodeBuildCLIParser {
  public static let usageText = """
  CrossSwiftUI xcodebuild — compile unmodified macOS .xcodeproj apps for Windows, Linux, Wasm, HarmonyOS & Android

  Usage:
    xcodebuild [-project <name.xcodeproj>] [-scheme <name>] [-target <name>]
               [-configuration <Debug|Release>] [-derivedDataPath <path>]
               [-destination <spec>] [KEY=VALUE ...] [build | clean]
    xcodebuild -list [-json] [-project <name.xcodeproj>]
    xcodebuild -showBuildSettings [-json] [-project <name.xcodeproj>]
               [-scheme <name>] [-configuration <Debug|Release>]
               [-derivedDataPath <path>] [KEY=VALUE ...]
    xcodebuild -version

  Options:
    -project <path>           Build the project specified by path (.xcodeproj)
    -workspace <path>         Build the project referenced by workspace (.xcworkspace)
    -scheme <name>            Build the scheme specified by name
    -target <name>            Build the target specified by name
    -alltargets               Build all targets
    -configuration <cfg>      Use the specified build configuration (Debug or Release)
    -derivedDataPath <dir>    Directory for build products and intermediates (default: ./build)
    -destination <spec>       Target platform specifier (e.g. generic/platform=Windows|Linux|Wasm|HarmonyOS|Android)
    -sdk <sdk>                Target SDK hint (windows, linux, wasm/web/wasi, harmonyos/ohos, android)
    -arch <arch>              Optional architecture hint
    -xcconfig <file>          Load build settings overrides from .xcconfig file
    -list                     List targets, build configurations, and schemes
    -showBuildSettings        Show resolved build settings for the selected target
    -json                     Generate machine-readable JSON output for -list / -showBuildSettings
    -version                  Display CrossSwiftUI xcodebuild version information
    -quiet                    Suppress non-error build output
    --crossswift-path <dir>   Override path to CrossSwiftUI checkout
    --nativeapi-path <dir>    Override path to nativeapi/bindings/swift checkout
    --scratch-path <dir>      Override intermediate SwiftPM scratch directory
    --console                 Keep Windows console subsystem instead of /SUBSYSTEM:WINDOWS
    -h, -help, --help         Show this help message
  """

  public static func parse(
    arguments: [String],
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> XcodeBuildParseOutcome {
    var options = XcodeBuildOptions()
    var actions: [XcodeBuildAction] = []
    var sawVersion = false
    var sawList = false
    var sawShowBuildSettings = false

    let ignoredValuedFlags: Set<String> = [
      "-clonedSourcePackagesDirPath",
      "-scmProvider",
      "-destinationTimeout",
      "-resultBundlePath",
      "-jobs",
      "-toolchain",
      "-exportOptionsPlist",
      "-exportPath",
      "-archivePath",
    ]

    let ignoredBoolFlags: Set<String> = [
      "-skipPackagePluginValidation",
      "-skipMacroValidation",
      "-allowProvisioningUpdates",
      "-allowProvisioningDeviceRegistration",
      "-parallelizeTargets",
      "-hideShellScriptEnvironment",
      "-showBuildTimingSummary",
      "-disableAutomaticPackageResolution",
      "-onlyUsePackageResolved",
      "-skipUnavailableActions",
      "-enableAddressSanitizer",
      "-enableThreadSanitizer",
      "-enableUndefinedBehaviorSanitizer",
      "-UseModernBuildSystem",
    ]

    var i = 0
    while i < arguments.count {
      let arg = arguments[i]
      func nextValue(_ flag: String) throws -> String {
        i += 1
        guard i < arguments.count else {
          throw XcodeBuildDriverError.invalidArguments("Missing value for '\(flag)'")
        }
        return arguments[i]
      }

      if arg == "-h" || arg == "-help" || arg == "--help" || arg == "-usage" {
        return .showHelp
      }

      if arg.hasPrefix("-UseModernBuildSystem=") || arg.hasPrefix("-jobs=") {
        i += 1
        continue
      }

      switch arg {
      case "-version":
        sawVersion = true
      case "-list":
        sawList = true
      case "-showBuildSettings":
        sawShowBuildSettings = true
      case "-json":
        options.jsonOutput = true
      case "-quiet":
        options.quiet = true
      case "-alltargets":
        options.allTargets = true
      case "-project":
        let raw = try nextValue(arg)
        options.projectPath = resolvePath(raw, relativeTo: currentDirectory)
      case "-workspace":
        let raw = try nextValue(arg)
        options.workspacePath = resolvePath(raw, relativeTo: currentDirectory)
      case "-scheme":
        options.schemeName = try nextValue(arg)
      case "-target":
        options.targetName = try nextValue(arg)
      case "-configuration":
        let raw = try nextValue(arg)
        let lower = raw.lowercased()
        if lower == "debug" {
          options.configuration = .debug
        } else if lower == "release" {
          options.configuration = .release
        } else {
          throw XcodeBuildDriverError.unsupportedConfiguration(raw)
        }
      case "-derivedDataPath":
        let raw = try nextValue(arg)
        options.derivedDataPath = resolvePath(raw, relativeTo: currentDirectory)
      case "-destination":
        options.destination = try nextValue(arg)
      case "-sdk":
        options.sdk = try nextValue(arg)
      case "-arch":
        options.arch = try nextValue(arg)
      case "-xcconfig":
        let raw = try nextValue(arg)
        let url = resolvePath(raw, relativeTo: currentDirectory)
        let loaded = XcodeProjectLoader.parseXCConfigFile(at: url)
        for (k, v) in loaded {
          options.buildSettingOverrides[k] = v
        }
      case "--crossswift-path", "-crossswift-path":
        options.crossSwiftPath = resolvePath(try nextValue(arg), relativeTo: currentDirectory)
      case "--nativeapi-path", "-nativeapi-path":
        options.nativeAPISwiftPath = resolvePath(try nextValue(arg), relativeTo: currentDirectory)
      case "--scratch-path", "-scratch-path":
        options.scratchDirectory = resolvePath(try nextValue(arg), relativeTo: currentDirectory)
      case "--console", "-console":
        options.consoleSubsystem = true
      default:
        if ignoredValuedFlags.contains(arg) {
          _ = try nextValue(arg)
        } else if ignoredBoolFlags.contains(arg) {
          break
        } else if arg.hasPrefix("-") {
          throw XcodeBuildDriverError.invalidArguments("Unknown option '\(arg)'")
        } else if let eqIndex = arg.firstIndex(of: "=") {
          let key = String(arg[..<eqIndex]).trimmingCharacters(in: .whitespaces)
          let value = String(arg[arg.index(after: eqIndex)...])
          if key.isEmpty {
            throw XcodeBuildDriverError.invalidArguments("Invalid build setting override '\(arg)'")
          }
          options.buildSettingOverrides[key] = value
        } else if let action = XcodeBuildAction(rawValue: arg) {
          actions.append(action)
        } else {
          throw XcodeBuildDriverError.invalidArguments("Unknown build action or argument '\(arg)'")
        }
      }
      i += 1
    }

    if sawVersion {
      options.mode = .version
    } else if sawList {
      options.mode = .list
    } else if sawShowBuildSettings {
      options.mode = .showBuildSettings
    } else if !actions.isEmpty {
      options.mode = .actions(actions)
    } else {
      options.mode = .actions([.build])
    }

    return .run(options)
  }

  private static func resolvePath(_ raw: String, relativeTo base: URL) -> URL {
    let url = URL(fileURLWithPath: raw, relativeTo: base)
    return url.standardizedFileURL
  }
}

public final class XcodeBuildDriver {
  private let loader = XcodeProjectLoader()
  private let buildBackend = SwiftPMBackend()
  private let stager = ApplicationStager()

  public init() {}

  public func versionOutput() -> String {
    "Xcode 16.0 (CrossSwiftUI)\nBuild version CrossSwiftUI-1.0"
  }

  public func resolveTargetPlatform(options: XcodeBuildOptions) -> TargetPlatform? {
    let hints = [options.destination, options.sdk].compactMap { $0?.lowercased() }.joined(separator: " ")
    if hints.contains("windows") { return .windows }
    if hints.contains("wasm") || hints.contains("wasi") || hints.contains("web") { return .wasm }
    if hints.contains("harmony") || hints.contains("ohos") { return .harmonyos }
    if hints.contains("android") { return .android }
    if hints.contains("linux") { return .linux }
    return TargetPlatform.currentHost
  }

  public static func resolveDerivedDataURL(
    options: XcodeBuildOptions,
    projectRootURL: URL
  ) -> URL {
    if let explicit = options.derivedDataPath {
      return explicit.standardizedFileURL
    }
    return projectRootURL.appendingPathComponent("build").standardizedFileURL
  }

  public static func computeEffectiveBuildSettings(
    project: ResolvedXcodeProject,
    platform: TargetPlatform?,
    derivedDataURL: URL
  ) -> [String: String] {
    var settings = project.mainTarget.buildSettings
    let configName = project.configuration.rawValue
    let productName = project.mainTarget.productName
    let executableName = project.mainTarget.executableName
    let platformName = platform?.rawValue ?? "macos"

    let executablePath: String
    let archName: String
    switch platform {
    case .windows:
      executablePath = "\(productName)/\(executableName).exe"
      archName = TargetArchitecture.currentHost == .arm64 ? "arm64" : "x86_64"
    case .linux:
      executablePath = "\(productName)/\(executableName)"
      archName = TargetArchitecture.currentHost == .arm64 ? "arm64" : "x86_64"
    case .wasm:
      executablePath = "\(productName)/app/\(executableName).wasm"
      archName = "wasm32"
    case .harmonyos:
      executablePath = "\(productName)/runtime/\(executableName).o"
      archName = "arm64-v8a"
    case .android:
      executablePath = "\(productName)/\(productName).apk"
      let rawABIs = settings["ANDROID_ABIS"]
        ?? ProcessRunner.environmentValue("ANDROID_ABIS")
        ?? "arm64-v8a"
      archName = rawABIs
        .split(whereSeparator: { $0 == "," || $0 == " " })
        .map(String.init)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    case nil:
      executablePath = "\(productName)/\(executableName)"
      archName = TargetArchitecture.currentHost == .arm64 ? "arm64" : "x86_64"
    }

    let symroot: String
    if let rawSym = settings["SYMROOT"], !rawSym.isEmpty {
      symroot = URL(fileURLWithPath: rawSym, relativeTo: project.projectRootURL).standardizedFileURL.path
    } else {
      symroot = derivedDataURL.appendingPathComponent("Build/Products").standardizedFileURL.path
    }

    let builtProductsDir: String
    if let rawConfigDir = settings["CONFIGURATION_BUILD_DIR"], !rawConfigDir.isEmpty {
      builtProductsDir = URL(fileURLWithPath: rawConfigDir, relativeTo: project.projectRootURL)
        .standardizedFileURL.path
    } else {
      builtProductsDir = URL(fileURLWithPath: symroot)
        .appendingPathComponent(configName)
        .standardizedFileURL.path
    }

    settings["ACTION"] = "build"
    settings["ARCHS"] = archName
    settings["CONFIGURATION"] = configName
    settings["DERIVED_DATA_DIR"] = derivedDataURL.standardizedFileURL.path
    settings["SYMROOT"] = symroot
    settings["BUILT_PRODUCTS_DIR"] = builtProductsDir
    settings["CONFIGURATION_BUILD_DIR"] = builtProductsDir
    settings["TARGET_BUILD_DIR"] = builtProductsDir
    settings["TARGET_NAME"] = project.mainTarget.name
    settings["PRODUCT_NAME"] = productName
    settings["FULL_PRODUCT_NAME"] = productName
    settings["WRAPPER_NAME"] = productName
    settings["EXECUTABLE_NAME"] = executableName
    settings["EXECUTABLE_PATH"] = executablePath
    settings["UNLOCALIZED_RESOURCES_FOLDER_PATH"] = "\(productName)/Resources"
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = project.mainTarget.bundleIdentifier
    settings["MARKETING_VERSION"] = project.mainTarget.marketingVersion
    settings["CURRENT_PROJECT_VERSION"] = project.mainTarget.buildVersion
    settings["PLATFORM_NAME"] = platformName
    return settings
  }

  public func list(
    options: XcodeBuildOptions,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> String {
    let projectURL = try XcodeProjectLoader.discoverProjectURL(
      projectPath: options.projectPath,
      workspacePath: options.workspacePath,
      in: currentDirectory
    )
    let metadata = try loader.inspectMetadata(from: projectURL)

    if options.jsonOutput {
      let payload: [String: Any] = [
        "project": [
          "configurations": metadata.configurations,
          "name": metadata.name,
          "schemes": metadata.schemes,
          "targets": metadata.targets,
        ]
      ]
      return try encodePrettyJSON(payload)
    }

    var lines: [String] = []
    lines.append("Information about project \"\(metadata.name)\":")
    lines.append("    Targets:")
    for t in metadata.targets {
      lines.append("        \(t)")
    }
    lines.append("")
    lines.append("    Build Configurations:")
    for c in metadata.configurations {
      lines.append("        \(c)")
    }
    lines.append("")
    lines.append(
      "    If no build configuration is specified and -scheme is not passed then \"\(metadata.defaultConfigurationName)\" is used."
    )
    lines.append("")
    lines.append("    Schemes:")
    for s in metadata.schemes {
      lines.append("        \(s)")
    }
    return lines.joined(separator: "\n")
  }

  public func showBuildSettings(
    options: XcodeBuildOptions,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> String {
    let projectURL = try XcodeProjectLoader.discoverProjectURL(
      projectPath: options.projectPath,
      workspacePath: options.workspacePath,
      in: currentDirectory
    )
    let configuration = options.configuration ?? .release
    let project = try loader.load(
      from: projectURL,
      configuration: configuration,
      targetName: options.targetName,
      schemeName: options.schemeName,
      buildSettingOverrides: options.buildSettingOverrides
    )
    let platform = resolveTargetPlatform(options: options)
    let derivedDataURL = Self.resolveDerivedDataURL(
      options: options,
      projectRootURL: project.projectRootURL
    )
    let settings = Self.computeEffectiveBuildSettings(
      project: project,
      platform: platform,
      derivedDataURL: derivedDataURL
    )

    if options.jsonOutput {
      let entry: [String: Any] = [
        "action": "build",
        "buildSettings": settings,
        "target": project.mainTarget.name,
      ]
      return try encodePrettyJSON([entry])
    }

    var lines: [String] = [
      "Build settings for action build and target \(project.mainTarget.name):"
    ]
    for key in settings.keys.sorted() {
      lines.append("    \(key) = \(settings[key] ?? "")")
    }
    return lines.joined(separator: "\n")
  }

  @discardableResult
  public func runActions(
    _ actions: [XcodeBuildAction],
    options: XcodeBuildOptions,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) throws -> StagedApplication? {
    guard let platform = resolveTargetPlatform(options: options),
          platform.canBuildOnCurrentHost
    else {
      throw XcodeBuildDriverError.unsupportedBuildHost(
        requested: resolveTargetPlatform(options: options),
        host: TargetPlatform.currentHost
      )
    }

    let projectURL = try XcodeProjectLoader.discoverProjectURL(
      projectPath: options.projectPath,
      workspacePath: options.workspacePath,
      in: currentDirectory
    )
    let configuration = options.configuration ?? .release
    let project = try loader.load(
      from: projectURL,
      configuration: configuration,
      targetName: options.targetName,
      schemeName: options.schemeName,
      buildSettingOverrides: options.buildSettingOverrides
    )
    let derivedDataURL = Self.resolveDerivedDataURL(
      options: options,
      projectRootURL: project.projectRootURL
    )
    let effectiveSettings = Self.computeEffectiveBuildSettings(
      project: project,
      platform: platform,
      derivedDataURL: derivedDataURL
    )
    let builtProductsDir = URL(
      fileURLWithPath: effectiveSettings["BUILT_PRODUCTS_DIR"]
        ?? derivedDataURL.appendingPathComponent("Build/Products/\(configuration.rawValue)").path
    ).standardizedFileURL

    var lastStaged: StagedApplication?
    let fm = FileManager.default

    for action in actions {
      switch action {
      case .clean:
        let appDir = builtProductsDir.appendingPathComponent(project.mainTarget.productName)
        if fm.fileExists(atPath: appDir.path) {
          try fm.removeItem(at: appDir)
        }
        if let crossSwiftRoot = try? SwiftPMBackend.resolveCrossSwiftRoot(explicit: options.crossSwiftPath) {
          let buildRoot = buildBackend.resolveBuildDirectory(
            project: project,
            platform: platform,
            configuration: configuration,
            derivedDataURL: derivedDataURL,
            scratchDirectory: options.scratchDirectory,
            crossSwiftRoot: crossSwiftRoot
          )
          if fm.fileExists(atPath: buildRoot.path) {
            try fm.removeItem(at: buildRoot)
          }
        }
        if !options.quiet {
          ProcessRunner.writeStdoutLine("** CLEAN SUCCEEDED **")
        }

      case .build:
        if !options.quiet {
          ProcessRunner.writeStdoutLine(
            "Build target \(project.mainTarget.name) of project \(project.projectName) with configuration \(configuration.rawValue) (\(platform.rawValue))"
          )
        }
        let built = try buildBackend.build(
          project: project,
          platform: platform,
          configuration: configuration,
          derivedDataURL: derivedDataURL,
          options: options
        )
        let staged = try stager.stage(
          project: project,
          built: built,
          builtProductsDirectory: builtProductsDir,
          quiet: options.quiet
        )
        lastStaged = staged
        if !options.quiet {
          ProcessRunner.writeStdoutLine("Staged product at \(staged.appBundleDirectory.path)")
          ProcessRunner.writeStdoutLine("** BUILD SUCCEEDED **")
        }
      }
    }

    return lastStaged
  }

  private func encodePrettyJSON(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys]
    )
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}
