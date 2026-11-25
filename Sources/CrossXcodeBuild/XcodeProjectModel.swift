import Foundation

public enum TargetPlatform: String, CaseIterable, Codable, Hashable, Sendable {
  case windows
  case linux
  case wasm
  case harmonyos
  case android

  public static var currentHost: TargetPlatform? {
    #if os(Windows)
      return .windows
    #elseif os(Linux)
      return .linux
    #else
      return nil
    #endif
  }

  public var canBuildOnCurrentHost: Bool {
    switch self {
    case .windows:
      return Self.currentHost == .windows
    case .linux:
      return Self.currentHost == .linux
    case .wasm:
      return true
    case .harmonyos, .android:
      #if os(macOS) || os(Linux)
        return true
      #else
        return false
      #endif
    }
  }
}

public enum TargetArchitecture: String, CaseIterable, Codable, Hashable, Sendable {
  case x64
  case arm64
  case wasm32

  public static var currentHost: TargetArchitecture {
    #if arch(arm64)
      return .arm64
    #else
      return .x64
    #endif
  }
}

public enum BuildConfiguration: String, CaseIterable, Codable, Hashable, Sendable {
  case debug = "Debug"
  case release = "Release"

  public var swiftPMFlag: String {
    switch self {
    case .debug: return "debug"
    case .release: return "release"
    }
  }
}

public enum XcodeBuildAction: String, CaseIterable, Sendable, Equatable {
  case build
  case clean
  case dev
}

public enum XcodeBuildMode: Sendable, Equatable {
  case version
  case list
  case showBuildSettings
  case actions([XcodeBuildAction])
}

public struct XcodeProjectMetadata: Codable, Sendable, Equatable {
  public let name: String
  public let projectURL: URL
  public let configurations: [String]
  public let targets: [String]
  public let schemes: [String]
  public let defaultConfigurationName: String

  public init(
    name: String,
    projectURL: URL,
    configurations: [String],
    targets: [String],
    schemes: [String],
    defaultConfigurationName: String
  ) {
    self.name = name
    self.projectURL = projectURL
    self.configurations = configurations
    self.targets = targets
    self.schemes = schemes
    self.defaultConfigurationName = defaultConfigurationName
  }
}

public enum PackageRequirement: Equatable, Codable, Sendable {
  case upToNextMajor(String)
  case upToNextMinor(String)
  case exact(String)
  case range(from: String, to: String)
  case branch(String)
  case revision(String)
}

public struct RemotePackageDependency: Equatable, Codable, Sendable {
  public let id: String
  public let repositoryURL: String
  public let packageName: String
  public let requirement: PackageRequirement
  public let pinnedRevision: String?
  public let pinnedVersion: String?
}

public struct LocalPackageDependency: Equatable, Codable, Sendable {
  public let id: String
  public let name: String
  public let path: URL
}

public struct PackageProductDependency: Equatable, Codable, Sendable {
  public let productName: String
  public let packageName: String?
  public let targetName: String
}

public struct ResolvedTarget: Codable, Sendable {
  public let name: String
  public let productName: String
  public let executableName: String
  public let bundleIdentifier: String
  public let marketingVersion: String
  public let buildVersion: String
  public let productType: String
  public let swiftVersion: String
  public let defaultActorIsolation: String?
  public let activeCompilationConditions: [String]
  public let preprocessorDefinitions: [String]
  public let infoPlistFile: URL?
  public let infoPlistKeys: [String: String]
  public let copyright: String?
  public let categoryType: String?
  public let isAccessoryApp: Bool
  public let generateAssetSymbols: Bool
  public let appIconName: String
  public let swiftSources: [URL]
  public let cSources: [URL]
  public let assetCatalogs: [URL]
  public let stringCatalogs: [URL]
  public let otherResources: [URL]
  public let buildSettings: [String: String]
  public let importedModules: [String]
}

public struct ResolvedXcodeProject: Codable, Sendable {
  public let projectURL: URL
  public let projectRootURL: URL
  public let projectName: String
  public let configuration: BuildConfiguration
  public let mainTarget: ResolvedTarget
  public let internalTargets: [ResolvedTarget]
  public let remotePackages: [RemotePackageDependency]
  public let localPackages: [LocalPackageDependency]
  public let productDependencies: [PackageProductDependency]
  public let inferredCrossSwiftModules: [String]
  public let skippedDarwinOnlyProducts: [String]

  public var allTargets: [ResolvedTarget] {
    internalTargets + [mainTarget]
  }
}

public struct XcodeBuildOptions: Sendable {
  public var projectPath: URL?
  public var workspacePath: URL?
  public var schemeName: String?
  public var targetName: String?
  public var allTargets: Bool
  public var configuration: BuildConfiguration?
  public var derivedDataPath: URL?
  public var destination: String?
  public var sdk: String?
  public var arch: String?
  public var quiet: Bool
  public var jsonOutput: Bool
  public var buildSettingOverrides: [String: String]
  public var mode: XcodeBuildMode
  public var crossSwiftPath: URL?
  public var nativeAPISwiftPath: URL?
  public var scratchDirectory: URL?
  public var consoleSubsystem: Bool
  public var watch: Bool
  public var devPort: UInt16
  public var devHost: String

  public init(
    projectPath: URL? = nil,
    workspacePath: URL? = nil,
    schemeName: String? = nil,
    targetName: String? = nil,
    allTargets: Bool = false,
    configuration: BuildConfiguration? = nil,
    derivedDataPath: URL? = nil,
    destination: String? = nil,
    sdk: String? = nil,
    arch: String? = nil,
    quiet: Bool = false,
    jsonOutput: Bool = false,
    buildSettingOverrides: [String: String] = [:],
    mode: XcodeBuildMode = .actions([.build]),
    crossSwiftPath: URL? = nil,
    nativeAPISwiftPath: URL? = nil,
    scratchDirectory: URL? = nil,
    consoleSubsystem: Bool = false,
    watch: Bool = false,
    devPort: UInt16 = 8000,
    devHost: String = "127.0.0.1"
  ) {
    self.projectPath = projectPath
    self.workspacePath = workspacePath
    self.schemeName = schemeName
    self.targetName = targetName
    self.allTargets = allTargets
    self.configuration = configuration
    self.derivedDataPath = derivedDataPath
    self.destination = destination
    self.sdk = sdk
    self.arch = arch
    self.quiet = quiet
    self.jsonOutput = jsonOutput
    self.buildSettingOverrides = buildSettingOverrides
    self.mode = mode
    self.crossSwiftPath = crossSwiftPath
    self.nativeAPISwiftPath = nativeAPISwiftPath
    self.scratchDirectory = scratchDirectory
    self.consoleSubsystem = consoleSubsystem
    self.watch = watch
    self.devPort = devPort
    self.devHost = devHost
  }
}
