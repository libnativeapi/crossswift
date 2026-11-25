import Foundation

public enum XcodeProjectLoaderError: Error, LocalizedError {
  case projectNotFound(String)
  case multipleProjectsFound(String)
  case invalidProjectStructure(String)
  case applicationTargetNotFound(String?)

  public var errorDescription: String? {
    switch self {
    case .projectNotFound(let path):
      return "Could not find an .xcodeproj bundle at '\(path)'"
    case .multipleProjectsFound(let path):
      return "The directory '\(path)' contains multiple Xcode projects; specify one with -project"
    case .invalidProjectStructure(let detail):
      return "Invalid Xcode project structure: \(detail)"
    case .applicationTargetNotFound(let name):
      if let name {
        return "Could not find application target or scheme '\(name)' in project"
      }
      return "No application target (com.apple.product-type.application) found in project"
    }
  }
}

public final class XcodeProjectLoader {
  public static let crossSwiftProvidedModules: Set<String> = Set(orderedCrossSwiftModules)

  private static let orderedCrossSwiftModules: [String] = [
    "SwiftUI",
    "AppKit",
    "UIKit",
    "QuartzCore",
    "CrossFoundation",
    "CoreFoundation",
    "Darwin",
    "ApplicationServices",
    "ServiceManagement",
    "Security",
    "CloudKit",
    "EventKit",
    "AVFoundation",
    "AVKit",
    "CoreAudio",
    "AudioToolbox",
    "CoreMedia",
    "CoreServices",
    "CoreText",
    "ImageIO",
    "ColorSync",
    "PDFKit",
    "QuickLookUI",
    "QuickLookThumbnailing",
    "Network",
    "SystemConfiguration",
    "AuthenticationServices",
    "JavaScriptCore",
    "IOKit",
    "Compression",
    "System",
    "AppleArchive",
    "Accelerate",
    "notify",
    "CommonCrypto",
    "FoundationModels",
    "NaturalLanguage",
    "Translation",
    "Cocoa",
    "Sparkle",
    "Vision",
    "StoreKit",
    "UserNotifications",
    "AppIntents",
    "SwiftData",
    "Combine",
    "CoreGraphics",
    "Carbon",
    "CryptoKit",
    "OSLog",
    "os",
    "UniformTypeIdentifiers",
    "SQLite3",
  ]

  public init() {}

  public struct SchemeInfo: Sendable, Equatable {
    public let targetName: String?
    public let launchConfiguration: BuildConfiguration?
    public let archiveConfiguration: BuildConfiguration?
  }

  public static func discoverProjectURL(
    projectPath: URL?,
    workspacePath: URL?,
    in currentDirectory: URL
  ) throws -> URL {
    if let projectPath {
      return try resolveProjectBundleURL(from: projectPath)
    }
    let fm = FileManager.default
    if let workspacePath {
      let stdWS = workspacePath.standardizedFileURL
      if stdWS.lastPathComponent == "project.xcworkspace" {
        let parent = stdWS.deletingLastPathComponent()
        if parent.pathExtension.lowercased() == "xcodeproj" {
          return try resolveProjectBundleURL(from: parent)
        }
      }
      let wsDir = stdWS.deletingLastPathComponent()
      let baseName = stdWS.deletingPathExtension().lastPathComponent
      let matchingProj = wsDir.appendingPathComponent("\(baseName).xcodeproj")
      if fm.fileExists(atPath: matchingProj.path) {
        return try resolveProjectBundleURL(from: matchingProj)
      }
      let contentsFile = stdWS.appendingPathComponent("contents.xcworkspacedata")
      if let xml = try? String(contentsOf: contentsFile, encoding: .utf8) {
        let pattern = "location\\s*=\\s*\"(?:group|container):([^\"]+\\.xcodeproj)\""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
           let range = Range(match.range(at: 1), in: xml)
        {
          let rel = String(xml[range])
          let candidate = URL(fileURLWithPath: rel, relativeTo: wsDir).standardizedFileURL
          if fm.fileExists(atPath: candidate.path) {
            return try resolveProjectBundleURL(from: candidate)
          }
        }
      }
      let siblings = (try? fm.contentsOfDirectory(at: wsDir, includingPropertiesForKeys: nil)) ?? []
      let siblingProjects = siblings.filter { $0.pathExtension.lowercased() == "xcodeproj" }
      if siblingProjects.count == 1, let only = siblingProjects.first {
        return only
      }
      throw XcodeProjectLoaderError.projectNotFound(stdWS.path)
    }

    let stdCwd = currentDirectory.standardizedFileURL
    let children = (try? fm.contentsOfDirectory(at: stdCwd, includingPropertiesForKeys: nil)) ?? []
    let projects = children
      .filter { $0.pathExtension.lowercased() == "xcodeproj" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    if projects.count == 1, let only = projects.first {
      return only
    }
    if projects.count > 1 {
      throw XcodeProjectLoaderError.multipleProjectsFound(stdCwd.path)
    }
    throw XcodeProjectLoaderError.projectNotFound(stdCwd.path)
  }

  private enum ProjectDescriptor {
    case pbxproj(URL)
    case xcproj(URL)
  }

  private static func locateProjectDescriptor(in projectURL: URL) throws -> ProjectDescriptor {
    let fm = FileManager.default
    let xcprojURL = projectURL.appendingPathComponent("project.xcproj")
    let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
    if fm.fileExists(atPath: xcprojURL.path) {
      return .xcproj(xcprojURL)
    }
    if fm.fileExists(atPath: pbxprojURL.path) {
      return .pbxproj(pbxprojURL)
    }
    throw XcodeProjectLoaderError.invalidProjectStructure(
      "Missing project.pbxproj or project.xcproj at \(projectURL.path)"
    )
  }

  public func inspectMetadata(from inputURL: URL) throws -> XcodeProjectMetadata {
    let projectURL = try Self.resolveProjectBundleURL(from: inputURL)
    let projectName = projectURL.deletingPathExtension().lastPathComponent
    switch try Self.locateProjectDescriptor(in: projectURL) {
    case .xcproj(let xcprojURL):
      return try inspectXCProjMetadata(projectURL: projectURL, projectName: projectName, xcprojURL: xcprojURL)
    case .pbxproj(let pbxprojURL):
      let rawRoot = try OpenStepPlistParser.parse(fileAt: pbxprojURL)
      guard let plist = rawRoot as? [String: Any],
            let objects = plist["objects"] as? [String: [String: Any]],
            let rootObjectID = plist["rootObject"] as? String,
            let projectObject = objects[rootObjectID]
      else {
        throw XcodeProjectLoaderError.invalidProjectStructure("Missing rootObject or objects map in project.pbxproj")
      }

      let targetIDs = projectObject["targets"] as? [String] ?? []
      let targetNames = targetIDs.compactMap { objects[$0]?["name"] as? String }

      var configurations: [String] = []
      var defaultConfigName = "Release"
      if let configListID = projectObject["buildConfigurationList"] as? String,
         let configList = objects[configListID]
      {
        if let defName = configList["defaultConfigurationName"] as? String, !defName.isEmpty {
          defaultConfigName = defName
        }
        for cid in configList["buildConfigurations"] as? [String] ?? [] {
          if let cname = objects[cid]?["name"] as? String, !configurations.contains(cname) {
            configurations.append(cname)
          }
        }
      }
      if configurations.isEmpty {
        configurations = ["Debug", "Release"]
      }

      let discoveredSchemes = Self.discoverSchemeNames(in: projectURL)
      let schemes = discoveredSchemes.isEmpty ? targetNames : discoveredSchemes

      return XcodeProjectMetadata(
        name: projectName,
        projectURL: projectURL,
        configurations: configurations,
        targets: targetNames,
        schemes: schemes,
        defaultConfigurationName: defaultConfigName
      )
    }
  }

  private func inspectXCProjMetadata(
    projectURL: URL,
    projectName: String,
    xcprojURL: URL
  ) throws -> XcodeProjectMetadata {
    let rawRoot = try XCProjParser.parse(fileAt: xcprojURL)
    guard let root = rawRoot as? [String: Any] else {
      throw XcodeProjectLoaderError.invalidProjectStructure("Expected root object in project.xcproj")
    }

    let rawTargets = (root["targets"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    let targetNames = rawTargets.compactMap { $0["name"] as? String }

    var configurations: [String] = []
    if let rawConfigs = root["configurations"] as? [Any] {
      for entry in rawConfigs {
        if let name = entry as? String, !name.isEmpty, !configurations.contains(name) {
          configurations.append(name)
        } else if let dict = entry as? [String: Any],
                  let name = dict["name"] as? String,
                  !name.isEmpty,
                  !configurations.contains(name)
        {
          configurations.append(name)
        }
      }
    }
    if configurations.isEmpty {
      configurations = ["Debug", "Release"]
    }

    let defaultConfigName: String
    if let def = root["default-configuration"] as? String, !def.isEmpty {
      defaultConfigName = def
    } else if let def = root["defaultConfiguration"] as? String, !def.isEmpty {
      defaultConfigName = def
    } else {
      defaultConfigName = configurations.contains("Release") ? "Release" : (configurations.first ?? "Release")
    }

    let discoveredSchemes = Self.discoverSchemeNames(in: projectURL)
    let schemes = discoveredSchemes.isEmpty ? targetNames : discoveredSchemes

    return XcodeProjectMetadata(
      name: projectName,
      projectURL: projectURL,
      configurations: configurations,
      targets: targetNames,
      schemes: schemes,
      defaultConfigurationName: defaultConfigName
    )
  }

  public func load(
    from inputURL: URL,
    configuration: BuildConfiguration = .release,
    targetName: String? = nil,
    schemeName: String? = nil,
    buildSettingOverrides: [String: String] = [:]
  ) throws -> ResolvedXcodeProject {
    let projectURL = try Self.resolveProjectBundleURL(from: inputURL)
    let projectRootURL = projectURL.deletingLastPathComponent().standardizedFileURL
    let projectName = projectURL.deletingPathExtension().lastPathComponent

    switch try Self.locateProjectDescriptor(in: projectURL) {
    case .xcproj(let xcprojURL):
      return try loadXCProj(
        projectURL: projectURL,
        projectRootURL: projectRootURL,
        projectName: projectName,
        xcprojURL: xcprojURL,
        configuration: configuration,
        targetName: targetName,
        schemeName: schemeName,
        buildSettingOverrides: buildSettingOverrides
      )
    case .pbxproj(let pbxprojURL):
      return try loadPbxproj(
        projectURL: projectURL,
        projectRootURL: projectRootURL,
        projectName: projectName,
        pbxprojURL: pbxprojURL,
        configuration: configuration,
        targetName: targetName,
        schemeName: schemeName,
        buildSettingOverrides: buildSettingOverrides
      )
    }
  }

  private func loadPbxproj(
    projectURL: URL,
    projectRootURL: URL,
    projectName: String,
    pbxprojURL: URL,
    configuration: BuildConfiguration,
    targetName: String?,
    schemeName: String?,
    buildSettingOverrides: [String: String]
  ) throws -> ResolvedXcodeProject {
    let rawRoot = try OpenStepPlistParser.parse(fileAt: pbxprojURL)
    guard let plist = rawRoot as? [String: Any],
          let objects = plist["objects"] as? [String: [String: Any]],
          let rootObjectID = plist["rootObject"] as? String,
          let projectObject = objects[rootObjectID]
    else {
      throw XcodeProjectLoaderError.invalidProjectStructure("Missing rootObject or objects map in project.pbxproj")
    }

    let parentGroups = Self.buildParentGroupIndex(objects: objects)
    let targetIDs = projectObject["targets"] as? [String] ?? []
    var resolvedTargetNameFromScheme: String?
    if let schemeName {
      if let info = Self.resolveSchemeInfo(forScheme: schemeName, in: projectURL) {
        resolvedTargetNameFromScheme = info.targetName
      } else if targetIDs.contains(where: {
        (objects[$0]?["name"] as? String)?.caseInsensitiveCompare(schemeName) == .orderedSame
      }) {
        resolvedTargetNameFromScheme = schemeName
      } else {
        throw XcodeProjectLoaderError.applicationTargetNotFound(schemeName)
      }
    }
    let desiredTargetName = targetName ?? resolvedTargetNameFromScheme

    let projectSettings = Self.resolveBuildSettings(
      configListID: projectObject["buildConfigurationList"] as? String,
      configuration: configuration,
      baseSettings: [
        "SRCROOT": projectRootURL.path,
        "PROJECT_DIR": projectRootURL.path,
        "PROJECT_NAME": projectName,
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
      ],
      overlaySettings: buildSettingOverrides,
      objects: objects,
      projectRootURL: projectRootURL,
      parentGroups: parentGroups
    )

    guard let mainTargetID = Self.selectMainTargetID(
      targetIDs: targetIDs,
      desiredName: desiredTargetName,
      objects: objects
    ) else {
      throw XcodeProjectLoaderError.applicationTargetNotFound(desiredTargetName)
    }

    var visitedTargets = Set<String>()
    var orderedInternalIDs: [String] = []
    func collectTargetDependencies(_ tid: String) {
      guard let targetObj = objects[tid] else { return }
      let deps = targetObj["dependencies"] as? [String] ?? []
      for depID in deps {
        guard let depObj = objects[depID] else { continue }
        var refTargetID = depObj["target"] as? String
        if refTargetID == nil,
           let proxyID = depObj["targetProxy"] as? String,
           let proxyObj = objects[proxyID]
        {
          refTargetID = proxyObj["remoteGlobalIDString"] as? String
        }
        guard let resolvedID = refTargetID,
              let childObj = objects[resolvedID],
              let ptype = childObj["productType"] as? String,
              ptype.contains("framework") || ptype.contains("library")
        else {
          continue
        }
        if visitedTargets.insert(resolvedID).inserted {
          collectTargetDependencies(resolvedID)
          orderedInternalIDs.append(resolvedID)
        }
      }
    }
    collectTargetDependencies(mainTargetID)

    let mainTarget = Self.resolveTarget(
      targetID: mainTargetID,
      objects: objects,
      projectSettings: projectSettings,
      buildSettingOverrides: buildSettingOverrides,
      configuration: configuration,
      projectRootURL: projectRootURL,
      parentGroups: parentGroups
    )

    let internalTargets = orderedInternalIDs.map { tid in
      Self.resolveTarget(
        targetID: tid,
        objects: objects,
        projectSettings: projectSettings,
        buildSettingOverrides: buildSettingOverrides,
        configuration: configuration,
        projectRootURL: projectRootURL,
        parentGroups: parentGroups
      )
    }

    let resolvedPins = Self.loadPackageResolvedPins(projectURL: projectURL, projectRootURL: projectRootURL)
    let (remotePackages, localPackages, productDependencies) = Self.resolveSwiftPackages(
      projectObject: projectObject,
      targetIDs: orderedInternalIDs + [mainTargetID],
      objects: objects,
      projectRootURL: projectRootURL,
      pins: resolvedPins
    )

    return Self.finalizeResolvedProject(
      projectURL: projectURL,
      projectRootURL: projectRootURL,
      projectName: projectName,
      configuration: configuration,
      mainTarget: mainTarget,
      internalTargets: internalTargets,
      remotePackages: remotePackages,
      localPackages: localPackages,
      productDependencies: productDependencies,
      resolvedPins: resolvedPins
    )
  }

  internal static func finalizeResolvedProject(
    projectURL: URL,
    projectRootURL: URL,
    projectName: String,
    configuration: BuildConfiguration,
    mainTarget: ResolvedTarget,
    internalTargets: [ResolvedTarget],
    remotePackages: [RemotePackageDependency],
    localPackages: [LocalPackageDependency],
    productDependencies: [PackageProductDependency],
    resolvedPins: [PackageResolvedPin]
  ) -> ResolvedXcodeProject {
    let allTargets = internalTargets + [mainTarget]
    let allSwiftSources = allTargets.flatMap(\.swiftSources)
    let importAnalysis = Self.analyzeSwiftImports(in: allSwiftSources)

    var inferredModules: [String] = []
    for mod in Self.orderedCrossSwiftModules {
      if importAnalysis.unconditionalImports.contains(mod) || importAnalysis.conditionalImports.contains(mod) {
        inferredModules.append(mod)
      }
    }
    if !inferredModules.contains("SwiftUI") {
      // Ensure SwiftUI/CrossSwiftUI runtime bootstrap is linked when CrossSwift modules are used.
      if inferredModules.contains("AppKit") || inferredModules.contains("UIKit") || inferredModules.contains("CrossSwiftUI") {
        inferredModules.insert("SwiftUI", at: 0)
      }
    }

    var filteredRemotes: [RemotePackageDependency] = []
    var filteredLocals: [LocalPackageDependency] = []
    var filteredProducts: [PackageProductDependency] = []
    var skippedDarwinProducts: [String] = []

    let remoteByName = Dictionary(uniqueKeysWithValues: remotePackages.map { ($0.packageName.lowercased(), $0) })
    let localByName = Dictionary(uniqueKeysWithValues: localPackages.map { ($0.name.lowercased(), $0) })

    for dep in productDependencies {
      let pkgNameLower = dep.packageName?.lowercased()
      let localPkg = pkgNameLower.flatMap { localByName[$0] }
      let isDarwinOnlyLocal = localPkg.map { Self.isPackageDarwinOnly($0.path) } ?? false
      let isOnlyConditionallyImported =
        !importAnalysis.unconditionalImports.contains(dep.productName)
        && (importAnalysis.conditionalImports.contains(dep.productName)
          || importAnalysis.hasDarwinGuard(for: dep.productName))
      let looksLikeKnownDarwinBinaryPkg =
        pkgNameLower == "sparkle" || dep.productName == "Sparkle"

      if isDarwinOnlyLocal
        || looksLikeKnownDarwinBinaryPkg
        || (isOnlyConditionallyImported
          && importAnalysis.hasDarwinGuard(for: dep.productName))
      {
        skippedDarwinProducts.append(dep.productName)
        continue
      }
      filteredProducts.append(dep)
      if let localPkg, !filteredLocals.contains(localPkg) {
        filteredLocals.append(localPkg)
      } else if let pkgNameLower, let remotePkg = remoteByName[pkgNameLower],
                !filteredRemotes.contains(remotePkg)
      {
        filteredRemotes.append(remotePkg)
      }
    }

    // Resolve transitive remote package products declared by local SwiftPM packages
    // when an app or internal target directly imports them (e.g., an Xcode project
    // linking local package `DazzUI` while target Swift files `import FluentIcons`).
    if !filteredLocals.isEmpty {
      let transitive = Self.discoverTransitiveRemoteDependencies(
        in: filteredLocals,
        pins: resolvedPins
      )
      if !transitive.remotes.isEmpty {
        let internalTargetNames = Set(allTargets.map(\.name))
        let skippedSet = Set(skippedDarwinProducts)
        let standardModules: Set<String> = [
          "Swift", "Foundation", "Observation", "Dispatch", "Glibc", "WinSDK", "ucrt",
          "JavaScriptKit", "NativeAPI", "CNativeAPI", "CrossSwiftUI", "SwiftUIRuntime",
        ]
        var remoteByLowerKey: [String: RemotePackageDependency] = [:]
        for r in transitive.remotes {
          remoteByLowerKey[r.packageName.lowercased()] = r
          let urlSlug = Self.packageNameFromURL(r.repositoryURL).lowercased()
          remoteByLowerKey[urlSlug] = r
        }

        for target in allTargets {
          let existingTargetProducts = Set(
            filteredProducts
              .filter { $0.targetName == target.name }
              .map(\.productName)
          )
          for mod in target.importedModules {
            if existingTargetProducts.contains(mod)
              || skippedSet.contains(mod)
              || internalTargetNames.contains(mod)
              || Self.crossSwiftProvidedModules.contains(mod)
              || standardModules.contains(mod)
            {
              continue
            }
            let isOnlyDarwinGuarded =
              !importAnalysis.unconditionalImports.contains(mod)
              && importAnalysis.hasDarwinGuard(for: mod)
            if isOnlyDarwinGuarded {
              continue
            }
            let matchedRemote: RemotePackageDependency?
            if let pkgKey = transitive.productToPackageKey[mod],
               let remote = remoteByLowerKey[pkgKey]
            {
              matchedRemote = remote
            } else if let direct = remoteByLowerKey[mod.lowercased()] {
              matchedRemote = direct
            } else {
              matchedRemote = nil
            }
            guard let remote = matchedRemote else { continue }

            let alreadyHasRemote = filteredRemotes.contains {
              Self.normalizeGitURL($0.repositoryURL) == Self.normalizeGitURL(remote.repositoryURL)
                || $0.packageName.caseInsensitiveCompare(remote.packageName) == .orderedSame
            }
            let resolvedRemote: RemotePackageDependency
            if alreadyHasRemote,
               let existing = filteredRemotes.first(where: {
                 Self.normalizeGitURL($0.repositoryURL) == Self.normalizeGitURL(remote.repositoryURL)
                   || $0.packageName.caseInsensitiveCompare(remote.packageName) == .orderedSame
               })
            {
              resolvedRemote = existing
            } else {
              filteredRemotes.append(remote)
              resolvedRemote = remote
            }

            filteredProducts.append(
              PackageProductDependency(
                productName: mod,
                packageName: resolvedRemote.packageName,
                targetName: target.name
              )
            )
          }
        }
      }
    }

    // Preserve directly referenced local/remote packages that matched kept products.
    return ResolvedXcodeProject(
      projectURL: projectURL,
      projectRootURL: projectRootURL,
      projectName: projectName,
      configuration: configuration,
      mainTarget: mainTarget,
      internalTargets: internalTargets,
      remotePackages: filteredRemotes,
      localPackages: filteredLocals,
      productDependencies: filteredProducts,
      inferredCrossSwiftModules: inferredModules,
      skippedDarwinOnlyProducts: skippedDarwinProducts
    )
  }

  private static func resolveProjectBundleURL(from inputURL: URL) throws -> URL {
    let standardized = inputURL.standardizedFileURL
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
      throw XcodeProjectLoaderError.projectNotFound(standardized.path)
    }
    if standardized.pathExtension.lowercased() == "xcodeproj" {
      return standardized
    }
    if isDir.boolValue {
      let children = (try? fm.contentsOfDirectory(at: standardized, includingPropertiesForKeys: nil)) ?? []
      let projects = children.filter { $0.pathExtension.lowercased() == "xcodeproj" }
      if projects.count == 1, let only = projects.first {
        return only
      }
    }
    throw XcodeProjectLoaderError.projectNotFound(standardized.path)
  }

  private static func discoverSchemeNames(in projectURL: URL) -> [String] {
    let fm = FileManager.default
    var names = Set<String>()
    let sharedDir = projectURL.appendingPathComponent("xcshareddata/xcschemes")
    if let files = try? fm.contentsOfDirectory(at: sharedDir, includingPropertiesForKeys: nil) {
      for url in files where url.pathExtension.lowercased() == "xcscheme" {
        names.insert(url.deletingPathExtension().lastPathComponent)
      }
    }
    let userDataDir = projectURL.appendingPathComponent("xcuserdata")
    if let users = try? fm.contentsOfDirectory(at: userDataDir, includingPropertiesForKeys: nil) {
      for userDir in users where userDir.pathExtension.lowercased() == "xcuserdatad" {
        let schemesDir = userDir.appendingPathComponent("xcschemes")
        if let files = try? fm.contentsOfDirectory(at: schemesDir, includingPropertiesForKeys: nil) {
          for url in files where url.pathExtension.lowercased() == "xcscheme" {
            names.insert(url.deletingPathExtension().lastPathComponent)
          }
        }
      }
    }
    return names.sorted()
  }

  public static func resolveSchemeInfo(forScheme scheme: String, in projectURL: URL) -> SchemeInfo? {
    let fm = FileManager.default
    var candidates: [URL] = [
      projectURL.appendingPathComponent("xcshareddata/xcschemes/\(scheme).xcscheme")
    ]
    let userDataDir = projectURL.appendingPathComponent("xcuserdata")
    if let users = try? fm.contentsOfDirectory(at: userDataDir, includingPropertiesForKeys: nil) {
      for userDir in users where userDir.pathExtension.lowercased() == "xcuserdatad" {
        candidates.append(userDir.appendingPathComponent("xcschemes/\(scheme).xcscheme"))
      }
    }

    guard let schemeURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }),
          let xml = try? String(contentsOf: schemeURL, encoding: .utf8)
    else {
      return nil
    }

    func firstMatch(_ pattern: String) -> String? {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
            let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
            let range = Range(match.range(at: 1), in: xml)
      else {
        return nil
      }
      return String(xml[range])
    }

    let targetName = firstMatch("BlueprintName\\s*=\\s*\"([^\"]+)\"")
    let launchRaw = firstMatch("<LaunchAction[^>]*buildConfiguration\\s*=\\s*\"([^\"]+)\"")
    let archiveRaw = firstMatch("<ArchiveAction[^>]*buildConfiguration\\s*=\\s*\"([^\"]+)\"")
    let parseConfig: (String?) -> BuildConfiguration? = { raw in
      guard let lower = raw?.lowercased() else { return nil }
      if lower == "debug" { return .debug }
      if lower == "release" { return .release }
      return nil
    }
    return SchemeInfo(
      targetName: targetName,
      launchConfiguration: parseConfig(launchRaw),
      archiveConfiguration: parseConfig(archiveRaw)
    )
  }

  private static func selectMainTargetID(
    targetIDs: [String],
    desiredName: String?,
    objects: [String: [String: Any]]
  ) -> String? {
    if let desiredName {
      if let exact = targetIDs.first(where: {
        (objects[$0]?["name"] as? String) == desiredName
      }) {
        return exact
      }
      if let caseInsensitive = targetIDs.first(where: {
        (objects[$0]?["name"] as? String)?.lowercased() == desiredName.lowercased()
      }) {
        return caseInsensitive
      }
      return nil
    }
    if let appTarget = targetIDs.first(where: {
      (objects[$0]?["productType"] as? String) == "com.apple.product-type.application"
    }) {
      return appTarget
    }
    return targetIDs.first(where: {
      let ptype = objects[$0]?["productType"] as? String ?? ""
      return !ptype.contains("unit-test") && !ptype.contains("ui-testing")
    })
  }

  private static func buildParentGroupIndex(objects: [String: [String: Any]]) -> [String: String] {
    var parent: [String: String] = [:]
    for (id, obj) in objects {
      let isa = obj["isa"] as? String
      guard isa == "PBXGroup" || isa == "PBXVariantGroup" else { continue }
      for child in obj["children"] as? [String] ?? [] {
        parent[child] = id
      }
    }
    return parent
  }

  private static func resolveObjectURL(
    id: String,
    objects: [String: [String: Any]],
    projectRootURL: URL,
    parentGroups: [String: String]
  ) -> URL? {
    var segments: [String] = []
    var currentID: String? = id
    var visited = Set<String>()

    while let cid = currentID, visited.insert(cid).inserted, let obj = objects[cid] {
      let sourceTree = obj["sourceTree"] as? String ?? "<group>"
      let path = obj["path"] as? String
      if let path, !path.isEmpty {
        segments.insert(path, at: 0)
      }
      switch sourceTree {
      case "<absolute>":
        let joined = segments.joined(separator: "/")
        return URL(fileURLWithPath: joined).standardizedFileURL
      case "SOURCE_ROOT", "<project>":
        let rel = segments.joined(separator: "/")
        return projectRootURL.appendingPathComponent(rel).standardizedFileURL
      case "BUILT_PRODUCTS_DIR", "SDKROOT", "DEVELOPER_DIR":
        return nil
      default:
        currentID = parentGroups[cid]
      }
    }

    let rel = segments.joined(separator: "/")
    return rel.isEmpty ? projectRootURL : projectRootURL.appendingPathComponent(rel).standardizedFileURL
  }

  private static func resolveBuildSettings(
    configListID: String?,
    configuration: BuildConfiguration,
    baseSettings: [String: String],
    overlaySettings: [String: String] = [:],
    objects: [String: [String: Any]],
    projectRootURL: URL,
    parentGroups: [String: String]
  ) -> [String: String] {
    var result = baseSettings
    if let configListID,
       let configList = objects[configListID],
       let configIDs = configList["buildConfigurations"] as? [String]
    {
      let matchedConfigID =
        configIDs.first(where: {
          (objects[$0]?["name"] as? String)?.lowercased() == configuration.rawValue.lowercased()
        })
        ?? configIDs.first(where: {
          (objects[$0]?["name"] as? String) == (configList["defaultConfigurationName"] as? String)
        })
        ?? configIDs.first

      if let matchedConfigID, let configObj = objects[matchedConfigID] {
        if let xcconfigID = configObj["baseConfigurationReference"] as? String,
           let xcconfigURL = resolveObjectURL(
             id: xcconfigID, objects: objects, projectRootURL: projectRootURL, parentGroups: parentGroups)
        {
          let xcconfigValues = parseXCConfig(fileAt: xcconfigURL)
          result = mergeSettings(base: result, overlay: xcconfigValues)
        }

        if let buildSettings = configObj["buildSettings"] as? [String: Any] {
          var flattened: [String: String] = [:]
          for (k, v) in buildSettings {
            flattened[k] = stringifySettingValue(v)
          }
          result = mergeSettings(base: result, overlay: flattened)
        }
      }
    }

    if !overlaySettings.isEmpty {
      result = mergeSettings(base: result, overlay: overlaySettings)
    }

    return expandVariables(in: result)
  }

  internal static func stringifySettingValue(_ value: Any) -> String {
    if let s = value as? String { return s }
    if let arr = value as? [Any] {
      return arr.compactMap { $0 as? String }.joined(separator: " ")
    }
    if let b = value as? Bool { return b ? "YES" : "NO" }
    if let num = value as? NSNumber { return num.stringValue }
    return String(describing: value)
  }

  internal static func mergeSettings(base: [String: String], overlay: [String: String]) -> [String: String] {
    var merged = base
    for (key, value) in overlay {
      if value.contains("$(inherited)") || value.contains("${inherited}") {
        let prev = merged[key] ?? ""
        let replaced = value
          .replacingOccurrences(of: "$(inherited)", with: prev)
          .replacingOccurrences(of: "${inherited}", with: prev)
          .trimmingCharacters(in: .whitespaces)
        merged[key] = replaced
      } else {
        merged[key] = value
      }
    }
    return merged
  }

  private static func parseXCConfig(fileAt url: URL, visited: inout Set<String>) -> [String: String] {
    let stdPath = url.standardizedFileURL.path
    guard visited.insert(stdPath).inserted,
          let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return [:]
    }
    var settings: [String: String] = [:]
    let dir = url.deletingLastPathComponent()

    for rawLine in text.components(separatedBy: .newlines) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("//") { continue }
      if let commentRange = line.range(of: " //") {
        line = String(line[..<commentRange.lowerBound]).trimmingCharacters(in: .whitespaces)
      }
      if line.hasPrefix("#include") {
        let rest = line.dropFirst("#include".count).trimmingCharacters(in: .whitespaces)
        let cleaned = rest.trimmingCharacters(in: CharacterSet(charactersIn: "?\" "))
        let includeURL = dir.appendingPathComponent(cleaned)
        let nested = parseXCConfig(fileAt: includeURL, visited: &visited)
        settings = mergeSettings(base: settings, overlay: nested)
        continue
      }
      guard let eq = line.firstIndex(of: "=") else { continue }
      let lhs = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
      let rhs = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
      // Strip optional conditional selector `[sdk=...]` for key lookup; keep default unconditionally if no arch/sdk filter or matching macOS.
      let key: String
      if let bracket = lhs.firstIndex(of: "[") {
        let baseKey = String(lhs[..<bracket]).trimmingCharacters(in: .whitespaces)
        let selector = String(lhs[bracket...]).lowercased()
        if selector.contains("sdk=iphone") || selector.contains("sdk=watch") || selector.contains("sdk=appletv") {
          continue
        }
        key = baseKey
      } else {
        key = lhs
      }
      settings = mergeSettings(base: settings, overlay: [key: rhs])
    }
    return settings
  }

  public static func parseXCConfigFile(at url: URL) -> [String: String] {
    var visited = Set<String>()
    return parseXCConfig(fileAt: url, visited: &visited)
  }

  private static func parseXCConfig(fileAt url: URL) -> [String: String] {
    parseXCConfigFile(at: url)
  }

  public static func expandVariables(in settings: [String: String]) -> [String: String] {
    var current = settings
    let pattern = "(\\$\\(([^()]+)\\)|\\$\\{([^{}]+)\\})"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return current }

    for _ in 0..<10 {
      var changed = false
      for (key, value) in current {
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        if matches.isEmpty { continue }
        var updated = value
        for match in matches.reversed() {
          let innerRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
          guard let r = Range(innerRange, in: value),
                let fullRange = Range(match.range, in: updated)
          else {
            continue
          }
          let expr = String(value[r])
          let parts = expr.split(separator: ":", maxSplits: 1).map(String.init)
          let varName = parts[0]
          let modifier = parts.count > 1 ? parts[1].lowercased() : nil
          var replacement = current[varName] ?? ""
          if modifier == "rfc1034identifier" {
            replacement = String(
              replacement.unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
              })
          } else if modifier == "lower" {
            replacement = replacement.lowercased()
          } else if modifier == "upper" {
            replacement = replacement.uppercased()
          } else if modifier == "c99extidentifier" {
            replacement = String(
              replacement.unicodeScalars.map { scalar in
                CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
              })
          }
          if updated[fullRange] != replacement {
            updated.replaceSubrange(fullRange, with: replacement)
            changed = true
          }
        }
        current[key] = updated
      }
      if !changed { break }
    }
    return current
  }

  private static func resolveTarget(
    targetID: String,
    objects: [String: [String: Any]],
    projectSettings: [String: String],
    buildSettingOverrides: [String: String],
    configuration: BuildConfiguration,
    projectRootURL: URL,
    parentGroups: [String: String]
  ) -> ResolvedTarget {
    let targetObj = objects[targetID] ?? [:]
    let name = targetObj["name"] as? String ?? "App"
    let productType = targetObj["productType"] as? String ?? "com.apple.product-type.application"

    var seed = projectSettings
    seed["TARGET_NAME"] = name
    seed["PRODUCT_NAME"] = targetObj["productName"] as? String ?? "$(TARGET_NAME)"
    seed["EXECUTABLE_NAME"] = "$(PRODUCT_NAME)"

    let settings = resolveBuildSettings(
      configListID: targetObj["buildConfigurationList"] as? String,
      configuration: configuration,
      baseSettings: seed,
      overlaySettings: buildSettingOverrides,
      objects: objects,
      projectRootURL: projectRootURL,
      parentGroups: parentGroups
    )

    let infoPlistFile = Self.resolveInfoPlistFile(from: settings, projectRootURL: projectRootURL)

    var swiftSources: [URL] = []
    var cSources: [URL] = []
    var assetCatalogs: [URL] = []
    var stringCatalogs: [URL] = []
    var otherResources: [URL] = []
    var seenPaths = Set<String>()

    func appendClassified(_ url: URL, isResource: Bool = false) {
      Self.classifyTargetFile(
        url,
        isResource: isResource,
        infoPlistFile: infoPlistFile,
        seenPaths: &seenPaths,
        swiftSources: &swiftSources,
        cSources: &cSources,
        assetCatalogs: &assetCatalogs,
        stringCatalogs: &stringCatalogs,
        otherResources: &otherResources
      )
    }

    // 1. Classic build phases (PBXSourcesBuildPhase / PBXResourcesBuildPhase)
    for phaseID in targetObj["buildPhases"] as? [String] ?? [] {
      guard let phaseObj = objects[phaseID],
            let phaseIsa = phaseObj["isa"] as? String
      else {
        continue
      }
      let isResPhase = phaseIsa == "PBXResourcesBuildPhase"
      guard phaseIsa == "PBXSourcesBuildPhase" || isResPhase else { continue }

      for buildFileID in phaseObj["files"] as? [String] ?? [] {
        guard let buildFileObj = objects[buildFileID],
              let fileRefID = buildFileObj["fileRef"] as? String,
              let fileObj = objects[fileRefID]
        else {
          continue
        }
        let fileIsa = fileObj["isa"] as? String
        if fileIsa == "PBXVariantGroup" {
          for childID in fileObj["children"] as? [String] ?? [] {
            if let childURL = resolveObjectURL(
              id: childID, objects: objects, projectRootURL: projectRootURL, parentGroups: parentGroups)
            {
              appendClassified(childURL, isResource: isResPhase)
            }
          }
        } else if let fileURL = resolveObjectURL(
          id: fileRefID, objects: objects, projectRootURL: projectRootURL, parentGroups: parentGroups)
        {
          appendClassified(fileURL, isResource: isResPhase)
        }
      }
    }

    // 2. Xcode 16+ fileSystemSynchronizedGroups
    for syncGroupID in targetObj["fileSystemSynchronizedGroups"] as? [String] ?? [] {
      guard let groupObj = objects[syncGroupID],
            let rootDir = resolveObjectURL(
              id: syncGroupID, objects: objects, projectRootURL: projectRootURL, parentGroups: parentGroups)
      else {
        continue
      }

      var excludedRelativePaths = Set<String>()
      for exID in groupObj["exceptions"] as? [String] ?? [] {
        guard let exObj = objects[exID] else { continue }
        if let exTarget = exObj["target"] as? String, exTarget != targetID { continue }
        for rel in exObj["membershipExceptions"] as? [String] ?? [] {
          excludedRelativePaths.insert(rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
      }

      Self.enumerateSynchronizedFolder(
        at: rootDir,
        excludedRelativePaths: excludedRelativePaths,
        onFile: { url, isResource in
          appendClassified(url, isResource: isResource)
        }
      )
    }

    return Self.makeResolvedTarget(
      name: name,
      productType: productType,
      settings: settings,
      projectRootURL: projectRootURL,
      infoPlistFile: infoPlistFile,
      swiftSources: swiftSources,
      cSources: cSources,
      assetCatalogs: assetCatalogs,
      stringCatalogs: stringCatalogs,
      otherResources: otherResources
    )
  }

  internal static func classifyTargetFile(
    _ url: URL,
    isResource: Bool = false,
    infoPlistFile: URL?,
    seenPaths: inout Set<String>,
    swiftSources: inout [URL],
    cSources: inout [URL],
    assetCatalogs: inout [URL],
    stringCatalogs: inout [URL],
    otherResources: inout [URL]
  ) {
    let std = url.standardizedFileURL
    guard seenPaths.insert(std.path).inserted else { return }
    if let infoPlistFile, std.path == infoPlistFile.path { return }

    let ext = std.pathExtension.lowercased()
    switch ext {
    case "swift":
      if !isResource { swiftSources.append(std) }
    case "c", "cpp", "cc", "cxx", "h", "hpp":
      if !isResource { cSources.append(std) }
    case "xcassets":
      assetCatalogs.append(std)
    case "xcstrings":
      stringCatalogs.append(std)
    case "entitlements", "storyboard", "xib", "metal", "sdef", "xcprivacy", "m", "mm":
      break
    default:
      if FileManager.default.fileExists(atPath: std.path) {
        otherResources.append(std)
      }
    }
  }

  internal static func enumerateSynchronizedFolder(
    at rootDir: URL,
    excludedRelativePaths: Set<String>,
    onFile: (URL, Bool) -> Void
  ) {
    let fm = FileManager.default
    // Use explicit recursive `contentsOfDirectory` instead of `FileManager.enumerator` +
    // `skipDescendants()`, because Windows `swift-foundation` has a bug where calling
    // `skipDescendants()` on a bundle directory (e.g. `Assets.xcassets`) skips the
    // descendants of the next sibling directory (e.g. `App/`).
    func walk(directory: URL, relativePrefix: String) {
      guard let entries = try? fm.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else {
        return
      }
      let sortedEntries = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
      for entry in sortedEntries {
        let name = entry.lastPathComponent
        if name.hasPrefix(".") { continue }
        let std = entry.standardizedFileURL
        let relPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"

        if excludedRelativePaths.contains(relPath) {
          continue
        }

        let ext = std.pathExtension.lowercased()
        if ext == "xcodeproj" || ext == "xcworkspace" {
          continue
        }
        if ext == "xcassets" || ext == "icon" {
          onFile(std, true)
          continue
        }

        let isDir: Bool
        if let dirValue = try? std.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
          isDir = dirValue
        } else {
          var objBool: ObjCBool = false
          isDir = fm.fileExists(atPath: std.path, isDirectory: &objBool) && objBool.boolValue
        }
        if isDir {
          walk(directory: std, relativePrefix: relPath)
        } else {
          onFile(std, false)
        }
      }
    }

    walk(directory: rootDir.standardizedFileURL, relativePrefix: "")
  }

  internal static func resolveInfoPlistFile(
    from settings: [String: String],
    projectRootURL: URL
  ) -> URL? {
    guard let rawPlist = settings["INFOPLIST_FILE"], !rawPlist.isEmpty else { return nil }
    let candidate = URL(fileURLWithPath: rawPlist, relativeTo: projectRootURL).standardizedFileURL
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }

  internal static func makeResolvedTarget(
    name: String,
    productType: String,
    settings: [String: String],
    projectRootURL: URL,
    infoPlistFile: URL?,
    swiftSources: [URL],
    cSources: [URL],
    assetCatalogs: [URL],
    stringCatalogs: [URL],
    otherResources: [URL]
  ) -> ResolvedTarget {
    let productName = (settings["PRODUCT_NAME"].flatMap { $0.isEmpty ? nil : $0 }) ?? name
    let executableName = (settings["EXECUTABLE_NAME"].flatMap { $0.isEmpty ? nil : $0 }) ?? productName
    let bundleIdentifier =
      (settings["PRODUCT_BUNDLE_IDENTIFIER"].flatMap { $0.isEmpty ? nil : $0 })
      ?? "dev.crossswift.\(productName.lowercased())"
    let marketingVersion =
      (settings["MARKETING_VERSION"].flatMap { $0.isEmpty ? nil : $0 }) ?? "1.0.0"
    let buildVersion =
      (settings["CURRENT_PROJECT_VERSION"].flatMap { $0.isEmpty ? nil : $0 }) ?? "1"
    let swiftVersion =
      (settings["SWIFT_VERSION"].flatMap { $0.isEmpty ? nil : $0 }) ?? "5.0"
    let defaultActorIsolation = settings["SWIFT_DEFAULT_ACTOR_ISOLATION"].flatMap {
      $0.isEmpty ? nil : $0
    }
    let activeConditions = Self.splitFlags(settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"])
    let preprocessorDefs = Self.splitFlags(settings["GCC_PREPROCESSOR_DEFINITIONS"])

    var infoPlistKeys: [String: String] = [:]
    for (k, v) in settings where k.hasPrefix("INFOPLIST_KEY_") {
      let plistKey = String(k.dropFirst("INFOPLIST_KEY_".count))
      infoPlistKeys[plistKey] = v
    }

    let copyright = infoPlistKeys["NSHumanReadableCopyright"]
    let categoryType = infoPlistKeys["LSApplicationCategoryType"]
    let rawLSUI = infoPlistKeys["LSUIElement"]?.lowercased()
    var isAccessoryApp = rawLSUI == "yes" || rawLSUI == "true" || rawLSUI == "1"
    if !isAccessoryApp, let infoPlistFile,
      let data = try? Data(contentsOf: infoPlistFile),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    {
      if let flag = plist["LSUIElement"] as? Bool {
        isAccessoryApp = flag
      } else if let str = plist["LSUIElement"] as? String {
        let lower = str.lowercased()
        isAccessoryApp = lower == "yes" || lower == "true" || lower == "1"
      } else if let num = plist["LSUIElement"] as? NSNumber {
        isAccessoryApp = num.boolValue
      }
    }
    let genSymbolsSetting = settings["ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS"]?
      .uppercased()
    let generateAssetSymbols = genSymbolsSetting != "NO" && genSymbolsSetting != "FALSE"
    let appIconName =
      (settings["ASSETCATALOG_COMPILER_APPICON_NAME"].flatMap { $0.isEmpty ? nil : $0 })
      ?? "AppIcon"

    let sortedSwift = swiftSources.sorted { $0.path < $1.path }
    let sortedC = cSources.sorted { $0.path < $1.path }
    let sortedAssets = assetCatalogs.sorted { $0.path < $1.path }
    let sortedStrings = stringCatalogs.sorted { $0.path < $1.path }
    let sortedOther = otherResources.sorted { $0.path < $1.path }

    let imports = analyzeSwiftImports(in: sortedSwift)
    let allImported = Array(imports.unconditionalImports.union(imports.conditionalImports)).sorted()

    return ResolvedTarget(
      name: name,
      productName: productName,
      executableName: executableName,
      bundleIdentifier: bundleIdentifier,
      marketingVersion: marketingVersion,
      buildVersion: buildVersion,
      productType: productType,
      swiftVersion: swiftVersion,
      defaultActorIsolation: defaultActorIsolation,
      activeCompilationConditions: activeConditions,
      preprocessorDefinitions: preprocessorDefs,
      infoPlistFile: infoPlistFile,
      infoPlistKeys: infoPlistKeys,
      copyright: copyright,
      categoryType: categoryType,
      isAccessoryApp: isAccessoryApp,
      generateAssetSymbols: generateAssetSymbols,
      appIconName: appIconName,
      swiftSources: sortedSwift,
      cSources: sortedC,
      assetCatalogs: sortedAssets,
      stringCatalogs: sortedStrings,
      otherResources: sortedOther,
      buildSettings: settings,
      importedModules: allImported
    )
  }

  private static func splitFlags(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw.split(whereSeparator: { $0.isWhitespace })
      .map(String.init)
      .filter { $0 != "$(inherited)" && $0 != "${inherited}" }
  }

  struct PackageResolvedPin {
    let identity: String
    let location: String
    let revision: String?
    let version: String?
  }

  internal static func loadPackageResolvedPins(
    projectURL: URL,
    projectRootURL: URL
  ) -> [PackageResolvedPin] {
    let candidates = [
      projectURL.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved"),
      projectRootURL.appendingPathComponent("Package.resolved"),
    ]
    for url in candidates where FileManager.default.fileExists(atPath: url.path) {
      guard let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      else {
        continue
      }
      var rawPins: [[String: Any]] = []
      if let pins = root["pins"] as? [[String: Any]] {
        rawPins = pins
      } else if let obj = root["object"] as? [String: Any],
                let pins = obj["pins"] as? [[String: Any]]
      {
        rawPins = pins
      }
      return rawPins.compactMap { pin in
        let state = pin["state"] as? [String: Any]
        let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
        let identity = (pin["identity"] as? String) ?? (pin["package"] as? String)
          ?? Self.packageNameFromURL(location).lowercased()
        guard !location.isEmpty else { return nil }
        return PackageResolvedPin(
          identity: identity.lowercased(),
          location: location,
          revision: state?["revision"] as? String,
          version: state?["version"] as? String
        )
      }
    }
    return []
  }

  private static func resolveSwiftPackages(
    projectObject: [String: Any],
    targetIDs: [String],
    objects: [String: [String: Any]],
    projectRootURL: URL,
    pins: [PackageResolvedPin]
  ) -> ([RemotePackageDependency], [LocalPackageDependency], [PackageProductDependency]) {
    var remotesByID: [String: RemotePackageDependency] = [:]
    var localsByID: [String: LocalPackageDependency] = [:]

    for refID in projectObject["packageReferences"] as? [String] ?? [] {
      guard let obj = objects[refID], let isa = obj["isa"] as? String else { continue }
      if isa == "XCRemoteSwiftPackageReference",
         let url = obj["repositoryURL"] as? String
      {
        let pkgName = Self.packageNameFromURL(url)
        let reqObj = obj["requirement"] as? [String: Any] ?? [:]
        let requirement = Self.parseRequirement(reqObj)
        let pin = pins.first(where: {
          Self.normalizeGitURL($0.location) == Self.normalizeGitURL(url)
            || $0.identity == pkgName.lowercased()
        })
        remotesByID[refID] = RemotePackageDependency(
          id: refID,
          repositoryURL: url,
          packageName: pkgName,
          requirement: requirement,
          pinnedRevision: pin?.revision,
          pinnedVersion: pin?.version
        )
      } else if isa == "XCLocalSwiftPackageReference",
                let relPath = obj["relativePath"] as? String
      {
        let pathURL = URL(fileURLWithPath: relPath, relativeTo: projectRootURL).standardizedFileURL
        let pkgName = Self.readPackageName(at: pathURL) ?? pathURL.lastPathComponent
        localsByID[refID] = LocalPackageDependency(id: refID, name: pkgName, path: pathURL)
      }
    }

    var productDeps: [PackageProductDependency] = []
    for tid in targetIDs {
      guard let targetObj = objects[tid] else { continue }
      let tName = targetObj["name"] as? String ?? "App"
      for depID in targetObj["packageProductDependencies"] as? [String] ?? [] {
        guard let depObj = objects[depID],
              let productName = depObj["productName"] as? String
        else {
          continue
        }
        var packageName: String?
        if let pkgID = depObj["package"] as? String {
          if let remote = remotesByID[pkgID] {
            packageName = remote.packageName
          } else if let local = localsByID[pkgID] {
            packageName = local.name
          }
        } else {
          // Xcode 16 can omit `package` on local/inferred product dependencies.
          if let matchingLocal = localsByID.values.first(where: {
            Self.packageProvidesProduct($0.path, productName: productName)
          }) {
            packageName = matchingLocal.name
          } else if let matchingRemote = remotesByID.values.first(where: {
            $0.packageName.caseInsensitiveCompare(productName) == .orderedSame
          }) {
            packageName = matchingRemote.packageName
          } else if remotesByID.count + localsByID.count == 1 {
            packageName = remotesByID.values.first?.packageName ?? localsByID.values.first?.name
          }
        }
        productDeps.append(
          PackageProductDependency(
            productName: productName,
            packageName: packageName,
            targetName: tName
          )
        )
      }
    }

    return (
      Array(remotesByID.values).sorted { $0.packageName < $1.packageName },
      Array(localsByID.values).sorted { $0.name < $1.name },
      productDeps
    )
  }

  internal static func parseRequirement(_ dict: [String: Any]) -> PackageRequirement {
    let rawKind = (dict["kind"] as? String ?? "").lowercased().replacingOccurrences(of: "-", with: "")
    let minVersion = (dict["minimumVersion"] as? String) ?? (dict["minimum-version"] as? String) ?? (dict["from"] as? String)
    let maxVersion = (dict["maximumVersion"] as? String) ?? (dict["maximum-version"] as? String) ?? (dict["to"] as? String)
    let exactVersion = (dict["version"] as? String) ?? (dict["exact"] as? String)
    switch rawKind {
    case "uptonextmajorversion", "uptonextmajor":
      return .upToNextMajor(minVersion ?? "1.0.0")
    case "uptonextminorversion", "uptonextminor":
      return .upToNextMinor(minVersion ?? "1.0.0")
    case "exactversion", "exact":
      return .exact(exactVersion ?? "1.0.0")
    case "versionrange", "range":
      return .range(
        from: minVersion ?? "1.0.0",
        to: maxVersion ?? "2.0.0"
      )
    case "branch":
      return .branch(dict["branch"] as? String ?? "main")
    case "revision":
      return .revision(dict["revision"] as? String ?? "")
    default:
      if let rev = dict["revision"] as? String, !rev.isEmpty {
        return .revision(rev)
      }
      if let branch = dict["branch"] as? String, !branch.isEmpty {
        return .branch(branch)
      }
      if let exact = exactVersion, !exact.isEmpty {
        return .exact(exact)
      }
      if let upMajor = (dict["up-to-next-major"] as? String) ?? (dict["upToNextMajor"] as? String) {
        return .upToNextMajor(upMajor)
      }
      if let upMinor = (dict["up-to-next-minor"] as? String) ?? (dict["upToNextMinor"] as? String) {
        return .upToNextMinor(upMinor)
      }
      return .upToNextMajor(minVersion ?? "1.0.0")
    }
  }

  internal static func packageNameFromURL(_ rawURL: String) -> String {
    let trimmed = rawURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
  }

  internal static func normalizeGitURL(_ rawURL: String) -> String {
    var s = rawURL.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
    return s
  }

  internal static func readPackageName(at directory: URL) -> String? {
    let manifestURL = directory.appendingPathComponent("Package.swift")
    guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return nil }
    let pattern = "name\\s*:\\s*\"([^\"]+)\""
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let r = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[r])
  }

  internal static func packageProvidesProduct(_ directory: URL, productName: String) -> Bool {
    let manifestURL = directory.appendingPathComponent("Package.swift")
    guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return false }
    return text.contains("\"\(productName)\"")
  }

  private static func isPackageDarwinOnly(_ directory: URL) -> Bool {
    let manifestURL = directory.appendingPathComponent("Package.swift")
    guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return false }
    return text.contains(".binaryTarget(") && text.contains(".xcframework")
      && !text.contains(".target(")
  }

  struct ImportAnalysis {
    var unconditionalImports: Set<String> = []
    var conditionalImports: Set<String> = []
    var darwinGuardedModules: Set<String> = []

    func hasDarwinGuard(for module: String) -> Bool {
      darwinGuardedModules.contains(module)
    }
  }

  static func analyzeSwiftImports(in files: [URL]) -> ImportAnalysis {
    var result = ImportAnalysis()
    let importRegex = try! NSRegularExpression(
      pattern: "^(?:@_[a-zA-Z]+\\s+)?import\\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    )

    for url in files {
      guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
      var conditionStack: [String] = []
      for rawLine in content.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#if ") {
          conditionStack.append(String(line.dropFirst(4)))
          continue
        }
        if line.hasPrefix("#elseif ") {
          if !conditionStack.isEmpty {
            conditionStack[conditionStack.count - 1] = String(line.dropFirst(8))
          }
          continue
        }
        if line.hasPrefix("#else") {
          if !conditionStack.isEmpty {
            conditionStack[conditionStack.count - 1] = "!(" + conditionStack.last! + ")"
          }
          continue
        }
        if line.hasPrefix("#endif") {
          if !conditionStack.isEmpty { conditionStack.removeLast() }
          continue
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = importRegex.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line)
        else {
          continue
        }
        let module = String(line[r])
        if conditionStack.isEmpty {
          result.unconditionalImports.insert(module)
        } else {
          result.conditionalImports.insert(module)
          let combined = conditionStack.joined(separator: " && ")
          if combined.contains("os(macOS)") || combined.contains("canImport(\(module))")
            || combined.contains("canImport(Darwin)")
          {
            result.darwinGuardedModules.insert(module)
          }
        }
      }
    }
    return result
  }
}
