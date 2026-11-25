import Foundation

extension XcodeProjectLoader {
  internal struct TransitiveRemoteDiscovery {
    let remotes: [RemotePackageDependency]
    let productToPackageKey: [String: String]
  }

  private struct XCProjFileMembership {
    let url: URL
    let isResource: Bool
  }

  private struct XCProjSynchronizedFolder {
    let rootDir: URL
    let targetNames: [String]
    let excludedPathsByTarget: [String: Set<String>]
    let globalExcludedPaths: Set<String>
  }

  internal func loadXCProj(
    projectURL: URL,
    projectRootURL: URL,
    projectName: String,
    xcprojURL: URL,
    configuration: BuildConfiguration,
    targetName: String?,
    schemeName: String?,
    buildSettingOverrides: [String: String]
  ) throws -> ResolvedXcodeProject {
    let rawRoot = try XCProjParser.parse(fileAt: xcprojURL)
    guard let root = rawRoot as? [String: Any] else {
      throw XcodeProjectLoaderError.invalidProjectStructure("Expected root object in project.xcproj")
    }

    let rawTargets = (root["targets"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }

    var resolvedTargetNameFromScheme: String?
    if let schemeName {
      if let info = Self.resolveSchemeInfo(forScheme: schemeName, in: projectURL) {
        resolvedTargetNameFromScheme = info.targetName
      } else if rawTargets.contains(where: {
        ($0["name"] as? String)?.caseInsensitiveCompare(schemeName) == .orderedSame
      }) {
        resolvedTargetNameFromScheme = schemeName
      } else {
        throw XcodeProjectLoaderError.applicationTargetNotFound(schemeName)
      }
    }
    let desiredTargetName = targetName ?? resolvedTargetNameFromScheme

    guard let mainTargetObj = Self.selectXCProjMainTarget(
      rawTargets: rawTargets,
      desiredName: desiredTargetName
    ) else {
      throw XcodeProjectLoaderError.applicationTargetNotFound(desiredTargetName)
    }

    // Index targets by name and id for dependency lookup.
    var targetsByName: [String: [String: Any]] = [:]
    var targetsByID: [String: [String: Any]] = [:]
    for t in rawTargets {
      if let name = t["name"] as? String {
        targetsByName[name] = t
      }
      if let id = t["id"] as? String, !id.isEmpty {
        targetsByID[id] = t
      }
    }

    var visitedTargets = Set<String>()
    var orderedInternalTargets: [[String: Any]] = []
    func collectTargetDependencies(_ targetObj: [String: Any]) {
      let deps = targetObj["dependencies"] as? [Any] ?? []
      for dep in deps {
        let refKey: String?
        if let s = dep as? String {
          refKey = s
        } else if let d = dep as? [String: Any] {
          refKey = (d["target"] as? String) ?? (d["name"] as? String) ?? (d["id"] as? String)
        } else {
          refKey = nil
        }
        guard let refKey,
              let childObj = targetsByName[refKey] ?? targetsByID[refKey],
              let childName = childObj["name"] as? String
        else {
          continue
        }
        let ptype = Self.normalizeXCProjProductType(childObj["product-type"] as? String)
        guard ptype.contains("framework") || ptype.contains("library") else { continue }
        if visitedTargets.insert(childName).inserted {
          collectTargetDependencies(childObj)
          orderedInternalTargets.append(childObj)
        }
      }
    }
    collectTargetDependencies(mainTargetObj)

    let projectXCConfigURL = Self.resolveXCProjBaseConfigurationURL(
      in: root,
      configuration: configuration,
      projectRootURL: projectRootURL
    )
    let projectSettings = Self.resolveXCProjBuildSettings(
      rawSettings: root["build-settings"] as? [String: Any],
      configOverrides: root["build-configurations"] as? [String: Any],
      xcconfigURL: projectXCConfigURL,
      configuration: configuration,
      baseSettings: [
        "SRCROOT": projectRootURL.path,
        "PROJECT_DIR": projectRootURL.path,
        "PROJECT_NAME": projectName,
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
      ],
      overlaySettings: buildSettingOverrides
    )

    // Collect file memberships and synchronized folders from root["files"].
    var explicitFilesByTarget: [String: [XCProjFileMembership]] = [:]
    var syncFolders: [XCProjSynchronizedFolder] = []
    Self.walkXCProjFiles(
      entries: root["files"] as? [Any] ?? [],
      baseDir: projectRootURL,
      projectRootURL: projectRootURL,
      explicitFilesByTarget: &explicitFilesByTarget,
      syncFolders: &syncFolders
    )

    let mainTarget = Self.resolveXCProjTarget(
      targetObj: mainTargetObj,
      projectSettings: projectSettings,
      buildSettingOverrides: buildSettingOverrides,
      configuration: configuration,
      projectRootURL: projectRootURL,
      explicitFiles: explicitFilesByTarget[mainTargetObj["name"] as? String ?? ""] ?? [],
      syncFolders: syncFolders
    )

    let internalTargets = orderedInternalTargets.map { targetObj in
      Self.resolveXCProjTarget(
        targetObj: targetObj,
        projectSettings: projectSettings,
        buildSettingOverrides: buildSettingOverrides,
        configuration: configuration,
        projectRootURL: projectRootURL,
        explicitFiles: explicitFilesByTarget[targetObj["name"] as? String ?? ""] ?? [],
        syncFolders: syncFolders
      )
    }

    let resolvedPins = Self.loadPackageResolvedPins(projectURL: projectURL, projectRootURL: projectRootURL)
    let (remotePackages, localPackages, productDependencies) = Self.resolveXCProjSwiftPackages(
      root: root,
      selectedTargets: orderedInternalTargets + [mainTargetObj],
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

  // MARK: - XCProj Helpers

  internal static func normalizeXCProjProductType(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else {
      return "com.apple.product-type.application"
    }
    if raw.hasPrefix("com.apple.product-type.") {
      return raw
    }
    switch raw.lowercased() {
    case "application":
      return "com.apple.product-type.application"
    case "framework":
      return "com.apple.product-type.framework"
    case "static-framework":
      return "com.apple.product-type.framework.static"
    case "dynamic-library":
      return "com.apple.product-type.library.dynamic"
    case "static-library":
      return "com.apple.product-type.library.static"
    case "unit-test-bundle", "bundle.unit-test":
      return "com.apple.product-type.bundle.unit-test"
    case "ui-test-bundle", "ui-testing-bundle", "bundle.ui-testing":
      return "com.apple.product-type.bundle.ui-testing"
    case "app-extension":
      return "com.apple.product-type.app-extension"
    case "command-line-tool", "tool":
      return "com.apple.product-type.tool"
    default:
      return "com.apple.product-type.\(raw)"
    }
  }

  private static func selectXCProjMainTarget(
    rawTargets: [[String: Any]],
    desiredName: String?
  ) -> [String: Any]? {
    if let desiredName {
      if let exact = rawTargets.first(where: { ($0["name"] as? String) == desiredName }) {
        return exact
      }
      if let caseInsensitive = rawTargets.first(where: {
        ($0["name"] as? String)?.lowercased() == desiredName.lowercased()
      }) {
        return caseInsensitive
      }
      return nil
    }
    if let appTarget = rawTargets.first(where: {
      normalizeXCProjProductType($0["product-type"] as? String) == "com.apple.product-type.application"
    }) {
      return appTarget
    }
    return rawTargets.first(where: {
      let ptype = normalizeXCProjProductType($0["product-type"] as? String)
      return !ptype.contains("unit-test") && !ptype.contains("ui-testing")
    })
  }

  private static func resolveXCProjBaseConfigurationURL(
    in container: [String: Any],
    configuration: BuildConfiguration,
    projectRootURL: URL
  ) -> URL? {
    // Support either `"base-configuration": "Path.xcconfig"` or `"configurations": [{ "name": "Release", "base-configuration": "..." }]`
    if let direct = container["base-configuration"] as? String, !direct.isEmpty {
      let candidate = resolveXCProjPath(direct, relativeTo: projectRootURL, projectRootURL: projectRootURL)
      if let candidate, FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    if let configDict = container["base-configuration"] as? [String: Any] {
      for (k, v) in configDict where k.caseInsensitiveCompare(configuration.rawValue) == .orderedSame {
        if let path = v as? String,
           let candidate = resolveXCProjPath(path, relativeTo: projectRootURL, projectRootURL: projectRootURL),
           FileManager.default.fileExists(atPath: candidate.path)
        {
          return candidate
        }
      }
    }
    if let rawConfigs = container["configurations"] as? [Any] {
      for entry in rawConfigs {
        guard let dict = entry as? [String: Any],
              let name = dict["name"] as? String,
              name.caseInsensitiveCompare(configuration.rawValue) == .orderedSame
        else {
          continue
        }
        if let path = (dict["base-configuration"] as? String) ?? (dict["xcconfig"] as? String),
           let candidate = resolveXCProjPath(path, relativeTo: projectRootURL, projectRootURL: projectRootURL),
           FileManager.default.fileExists(atPath: candidate.path)
        {
          return candidate
        }
      }
    }
    return nil
  }

  internal static func resolveXCProjBuildSettings(
    rawSettings: [String: Any]?,
    configOverrides: [String: Any]?,
    xcconfigURL: URL?,
    configuration: BuildConfiguration,
    baseSettings: [String: String],
    overlaySettings: [String: String] = [:]
  ) -> [String: String] {
    var result = baseSettings

    if let xcconfigURL {
      let xcconfigValues = parseXCConfigFile(at: xcconfigURL)
      result = mergeSettings(base: result, overlay: xcconfigValues)
    }

    if let rawSettings {
      var unconditional: [String: String] = [:]
      var conditional: [(rawKey: String, baseKey: String, selector: String, value: String)] = []

      for (k, v) in rawSettings {
        let stringified = stringifySettingValue(v)
        if let bracket = k.firstIndex(of: "[") {
          let baseKey = String(k[..<bracket]).trimmingCharacters(in: .whitespaces)
          let selector = String(k[bracket...]).trimmingCharacters(in: .whitespaces)
          conditional.append((rawKey: k, baseKey: baseKey, selector: selector, value: stringified))
        } else {
          unconditional[k] = stringified
        }
      }

      if !unconditional.isEmpty {
        result = mergeSettings(base: result, overlay: unconditional)
      }

      let effectiveSDK = result["SDKROOT"]?.lowercased()
      for entry in conditional.sorted(by: { $0.rawKey < $1.rawKey }) {
        if matchesXCProjConditionSelector(
          entry.selector,
          configuration: configuration,
          sdkRoot: effectiveSDK
        ) {
          result = mergeSettings(base: result, overlay: [entry.baseKey: entry.value])
        }
      }
    }

    if let configOverrides {
      for (k, v) in configOverrides where k.caseInsensitiveCompare(configuration.rawValue) == .orderedSame {
        if let nested = v as? [String: Any] {
          let settingsDict = (nested["build-settings"] as? [String: Any]) ?? nested
          var flattened: [String: String] = [:]
          for (sk, sv) in settingsDict {
            flattened[sk] = stringifySettingValue(sv)
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

  internal static func matchesXCProjConditionSelector(
    _ selector: String,
    configuration: BuildConfiguration,
    sdkRoot: String?
  ) -> Bool {
    // Parse one or more `[key=value,...]` clauses, e.g. `[config=Debug]` or `[config=Release][sdk=macosx*]`.
    var i = selector.startIndex
    var clauses: [(String, String)] = []
    while i < selector.endIndex {
      guard let open = selector[i...].firstIndex(of: "["),
            let close = selector[selector.index(after: open)...].firstIndex(of: "]")
      else {
        break
      }
      let inner = String(selector[selector.index(after: open)..<close])
      for part in inner.split(separator: ",") {
        guard let eq = part.firstIndex(of: "=") else { continue }
        let key = String(part[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
        let val = String(part[part.index(after: eq)...]).trimmingCharacters(in: .whitespaces).lowercased()
        if !key.isEmpty {
          clauses.append((key, val))
        }
      }
      i = selector.index(after: close)
    }

    for (key, pattern) in clauses {
      switch key {
      case "config", "configuration":
        if !matchesWildcard(value: configuration.rawValue.lowercased(), pattern: pattern) {
          return false
        }
      case "sdk":
        if let sdkRoot, !sdkRoot.isEmpty {
          if !matchesWildcard(value: sdkRoot, pattern: pattern) {
            return false
          }
        } else if pattern.hasPrefix("iphone") || pattern.hasPrefix("watch") || pattern.hasPrefix("appletv") {
          return false
        }
      default:
        break
      }
    }
    return true
  }

  private static func matchesWildcard(value: String, pattern: String) -> Bool {
    if pattern == "*" { return true }
    if !pattern.contains("*") {
      return value == pattern
    }
    let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    var cursor = value.startIndex
    for (idx, part) in parts.enumerated() {
      if part.isEmpty { continue }
      if idx == 0 {
        guard value.hasPrefix(part) else { return false }
        cursor = value.index(value.startIndex, offsetBy: part.count)
      } else if idx == parts.count - 1 {
        guard value[cursor...].hasSuffix(part) else { return false }
        cursor = value.endIndex
      } else {
        guard let found = value[cursor...].range(of: part) else { return false }
        cursor = found.upperBound
      }
    }
    return true
  }

  private static func resolveXCProjPath(
    _ rawPath: String,
    relativeTo baseDir: URL,
    projectRootURL: URL
  ) -> URL? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed == "<PRODUCTS>"
      || trimmed.hasPrefix("<PRODUCTS>/")
      || trimmed.hasPrefix("<SDKROOT>/")
      || trimmed.hasPrefix("<DEVELOPER_DIR>/")
      || trimmed.hasPrefix("<BUILT_PRODUCTS_DIR>/")
    {
      return nil
    }
    if trimmed.hasPrefix("<SRCROOT>/") {
      let rel = String(trimmed.dropFirst("<SRCROOT>/".count))
      return projectRootURL.appendingPathComponent(rel).standardizedFileURL
    }
    if trimmed.hasPrefix("<PROJECT>/") {
      let rel = String(trimmed.dropFirst("<PROJECT>/".count))
      return projectRootURL.appendingPathComponent(rel).standardizedFileURL
    }
    if trimmed.hasPrefix("<ABSOLUTE>/") {
      let abs = String(trimmed.dropFirst("<ABSOLUTE>/".count))
      return URL(fileURLWithPath: abs).standardizedFileURL
    }
    if trimmed.hasPrefix("/") {
      return URL(fileURLWithPath: trimmed).standardizedFileURL
    }
    return baseDir.appendingPathComponent(trimmed).standardizedFileURL
  }

  private static func parseBuildPhaseIsResource(_ raw: Any?) -> Bool {
    if let s = raw as? String {
      return s.lowercased().contains("resource")
    }
    if let d = raw as? [String: Any], let inner = d["build-phase"] as? String {
      return inner.lowercased().contains("resource")
    }
    return false
  }

  private static func extractTargetMemberships(
    from entry: [String: Any]
  ) -> [(targetName: String, isResource: Bool)] {
    let defaultIsResource = parseBuildPhaseIsResource(entry["build-phase"])
    guard let raw = entry["target-membership"] as? [Any] else { return [] }
    var results: [(String, Bool)] = []
    for item in raw {
      if let s = item as? String, !s.isEmpty {
        results.append((s, defaultIsResource))
      } else if let d = item as? [String: Any],
                let t = (d["target"] as? String) ?? (d["name"] as? String),
                !t.isEmpty
      {
        let isRes = d["build-phase"] != nil ? parseBuildPhaseIsResource(d["build-phase"]) : defaultIsResource
        results.append((t, isRes))
      }
    }
    return results
  }

  private static func walkXCProjFiles(
    entries: [Any],
    baseDir: URL,
    projectRootURL: URL,
    explicitFilesByTarget: inout [String: [XCProjFileMembership]],
    syncFolders: inout [XCProjSynchronizedFolder]
  ) {
    for raw in entries {
      guard let entry = raw as? [String: Any] else { continue }
      let kind = (entry["kind"] as? String)?.lowercased()

      if kind == "folder" {
        guard let rawPath = entry["path"] as? String,
              let folderURL = resolveXCProjPath(rawPath, relativeTo: baseDir, projectRootURL: projectRootURL)
        else {
          continue
        }
        let targetNames = extractTargetMemberships(from: entry).map(\.targetName)
        var excludedByTarget: [String: Set<String>] = [:]
        var globalExcluded = Set<String>()

        if let rawExcludes = (entry["exclude"] as? [Any]) ?? (entry["excluded-paths"] as? [Any]) {
          for item in rawExcludes {
            if let rel = item as? String {
              globalExcluded.insert(rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            }
          }
        }
        if let rawExceptions = (entry["exceptions"] as? [Any]) ?? (entry["membership-exceptions"] as? [Any]) {
          for ex in rawExceptions {
            if let rel = ex as? String {
              globalExcluded.insert(rel.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            } else if let exDict = ex as? [String: Any] {
              let exTarget = (exDict["target"] as? String) ?? (exDict["target-name"] as? String)
              let paths =
                (exDict["membership-exceptions"] as? [String])
                ?? (exDict["exclude"] as? [String])
                ?? (exDict["files"] as? [String])
                ?? ((exDict["path"] as? String).map { [$0] } ?? [])
              for rel in paths {
                let clean = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let exTarget {
                  excludedByTarget[exTarget, default: []].insert(clean)
                } else {
                  globalExcluded.insert(clean)
                }
              }
            }
          }
        }

        if !targetNames.isEmpty {
          syncFolders.append(
            XCProjSynchronizedFolder(
              rootDir: folderURL,
              targetNames: targetNames,
              excludedPathsByTarget: excludedByTarget,
              globalExcludedPaths: globalExcluded
            )
          )
        }
        continue
      }

      if kind == "group" {
        let nextBase: URL
        if let rawPath = entry["path"] as? String, !rawPath.isEmpty,
           let resolved = resolveXCProjPath(rawPath, relativeTo: baseDir, projectRootURL: projectRootURL)
        {
          nextBase = resolved
        } else {
          nextBase = baseDir
        }
        if let children = entry["children"] as? [Any] {
          walkXCProjFiles(
            entries: children,
            baseDir: nextBase,
            projectRootURL: projectRootURL,
            explicitFilesByTarget: &explicitFilesByTarget,
            syncFolders: &syncFolders
          )
        }
        continue
      }

      // Regular file entry (`kind == nil` or `kind == "file"`).
      guard let rawPath = entry["path"] as? String,
            let fileURL = resolveXCProjPath(rawPath, relativeTo: baseDir, projectRootURL: projectRootURL)
      else {
        continue
      }
      let memberships = extractTargetMemberships(from: entry)
      for membership in memberships {
        explicitFilesByTarget[membership.targetName, default: []].append(
          XCProjFileMembership(url: fileURL, isResource: membership.isResource)
        )
      }
    }
  }

  private static func resolveXCProjTarget(
    targetObj: [String: Any],
    projectSettings: [String: String],
    buildSettingOverrides: [String: String],
    configuration: BuildConfiguration,
    projectRootURL: URL,
    explicitFiles: [XCProjFileMembership],
    syncFolders: [XCProjSynchronizedFolder]
  ) -> ResolvedTarget {
    let name = targetObj["name"] as? String ?? "App"
    let productType = normalizeXCProjProductType(targetObj["product-type"] as? String)

    var seed = projectSettings
    seed["TARGET_NAME"] = name
    seed["PRODUCT_NAME"] = (targetObj["product-name"] as? String) ?? "$(TARGET_NAME)"
    seed["EXECUTABLE_NAME"] = "$(PRODUCT_NAME)"

    let targetXCConfigURL = resolveXCProjBaseConfigurationURL(
      in: targetObj,
      configuration: configuration,
      projectRootURL: projectRootURL
    )
    let settings = resolveXCProjBuildSettings(
      rawSettings: targetObj["build-settings"] as? [String: Any],
      configOverrides: targetObj["build-configurations"] as? [String: Any],
      xcconfigURL: targetXCConfigURL,
      configuration: configuration,
      baseSettings: seed,
      overlaySettings: buildSettingOverrides
    )

    let infoPlistFile = resolveInfoPlistFile(from: settings, projectRootURL: projectRootURL)

    var swiftSources: [URL] = []
    var cSources: [URL] = []
    var assetCatalogs: [URL] = []
    var stringCatalogs: [URL] = []
    var otherResources: [URL] = []
    var seenPaths = Set<String>()

    func appendClassified(_ url: URL, isResource: Bool = false) {
      classifyTargetFile(
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

    // 1. Explicitly listed files with target-membership
    for file in explicitFiles {
      appendClassified(file.url, isResource: file.isResource)
    }

    // 2. Synchronized folder entries with target-membership matching this target
    for folder in syncFolders where folder.targetNames.contains(name) {
      let excluded = folder.globalExcludedPaths.union(folder.excludedPathsByTarget[name] ?? [])
      enumerateSynchronizedFolder(
        at: folder.rootDir,
        excludedRelativePaths: excluded,
        onFile: { url, isResource in
          appendClassified(url, isResource: isResource)
        }
      )
    }

    return makeResolvedTarget(
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

  private static func resolveXCProjSwiftPackages(
    root: [String: Any],
    selectedTargets: [[String: Any]],
    projectRootURL: URL,
    pins: [PackageResolvedPin]
  ) -> ([RemotePackageDependency], [LocalPackageDependency], [PackageProductDependency]) {
    var remotes: [RemotePackageDependency] = []
    var locals: [LocalPackageDependency] = []
    var remoteLookup: [String: RemotePackageDependency] = [:]
    var localLookup: [String: LocalPackageDependency] = [:]

    let rawPackages = (root["packages"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    for (idx, pkg) in rawPackages.enumerated() {
      let kind = (pkg["kind"] as? String)?.lowercased()
      let rawURL =
        (pkg["url"] as? String)
        ?? (pkg["repository-url"] as? String)
        ?? (pkg["repositoryURL"] as? String)
        ?? (pkg["location"] as? String)
      let rawPath = (pkg["path"] as? String) ?? (pkg["relative-path"] as? String) ?? (pkg["relativePath"] as? String)

      if kind == "local" || (rawURL == nil && rawPath != nil), let relPath = rawPath {
        let pathURL = URL(fileURLWithPath: relPath, relativeTo: projectRootURL).standardizedFileURL
        let explicitName = pkg["name"] as? String
        let pkgName = readPackageName(at: pathURL) ?? explicitName ?? pathURL.lastPathComponent
        let id = (pkg["id"] as? String) ?? "local-\(idx)-\(pkgName)"
        let dep = LocalPackageDependency(id: id, name: pkgName, path: pathURL)
        locals.append(dep)
        localLookup[pkgName.lowercased()] = dep
        localLookup[pathURL.lastPathComponent.lowercased()] = dep
        localLookup[id.lowercased()] = dep
        if let explicitName, !explicitName.isEmpty {
          localLookup[explicitName.lowercased()] = dep
        }
      } else if let url = rawURL, !url.isEmpty {
        let pkgName = (pkg["name"] as? String) ?? packageNameFromURL(url)
        let reqDict = (pkg["requirement"] as? [String: Any]) ?? pkg
        let requirement = parseRequirement(reqDict)
        let pin = pins.first(where: {
          normalizeGitURL($0.location) == normalizeGitURL(url)
            || $0.identity == pkgName.lowercased()
        })
        let id = (pkg["id"] as? String) ?? "remote-\(idx)-\(pkgName)"
        let dep = RemotePackageDependency(
          id: id,
          repositoryURL: url,
          packageName: pkgName,
          requirement: requirement,
          pinnedRevision: pin?.revision,
          pinnedVersion: pin?.version
        )
        remotes.append(dep)
        remoteLookup[pkgName.lowercased()] = dep
        remoteLookup[packageNameFromURL(url).lowercased()] = dep
        remoteLookup[id.lowercased()] = dep
      }
    }

    var productDeps: [PackageProductDependency] = []
    for targetObj in selectedTargets {
      let tName = targetObj["name"] as? String ?? "App"
      let members =
        (targetObj["package-product-members"] as? [Any] ?? [])
        + (targetObj["package-product-dependencies"] as? [Any] ?? [])
      for rawMember in members {
        guard let member = rawMember as? [String: Any] else { continue }
        guard let productName =
          (member["product-name"] as? String)
          ?? (member["productName"] as? String)
          ?? (member["product"] as? String),
          !productName.isEmpty
        else {
          continue
        }
        var packageName: String?
        if let pkgRef = (member["package"] as? String)?.trimmingCharacters(in: .whitespaces), !pkgRef.isEmpty {
          let lower = pkgRef.lowercased()
          if let local = localLookup[lower] {
            packageName = local.name
          } else if let remote = remoteLookup[lower] {
            packageName = remote.packageName
          } else {
            packageName = pkgRef
          }
        } else {
          if let matchingLocal = locals.first(where: { packageProvidesProduct($0.path, productName: productName) }) {
            packageName = matchingLocal.name
          } else if let matchingRemote = remotes.first(where: {
            $0.packageName.caseInsensitiveCompare(productName) == .orderedSame
          }) {
            packageName = matchingRemote.packageName
          } else if remotes.count + locals.count == 1 {
            packageName = remotes.first?.packageName ?? locals.first?.name
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
      remotes.sorted { $0.packageName < $1.packageName },
      locals.sorted { $0.name < $1.name },
      productDeps
    )
  }

  // MARK: - Transitive Local Package Dependency Scanner

  /// Scans local SwiftPM packages' `Package.swift` manifests (recursively across literal
  /// relative local dependencies) to discover transitive remote `.package(url: ...)`
  /// declarations and `.product(name: ..., package: ...)` product mappings.
  internal static func discoverTransitiveRemoteDependencies(
    in localPackages: [LocalPackageDependency],
    pins: [PackageResolvedPin] = []
  ) -> TransitiveRemoteDiscovery {
    var visitedDirs = Set<String>()
    var remotesByNormalizedURL: [String: RemotePackageDependency] = [:]
    var productToPackageKey: [String: String] = [:]

    func scanPackage(at packageRoot: URL, accumulatedPins: [PackageResolvedPin]) {
      let stdPath = packageRoot.standardizedFileURL.path
      guard visitedDirs.insert(stdPath).inserted else { return }

      let manifestURL = packageRoot.appendingPathComponent("Package.swift")
      guard let rawManifest = try? String(contentsOf: manifestURL, encoding: .utf8) else { return }

      var effectivePins = accumulatedPins
      let localResolved = packageRoot.appendingPathComponent("Package.resolved")
      if FileManager.default.fileExists(atPath: localResolved.path) {
        effectivePins.append(
          contentsOf: loadPackageResolvedPins(projectURL: packageRoot, projectRootURL: packageRoot)
        )
      }

      let manifest = stripSwiftCommentsPreservingStrings(rawManifest)
      let packageCalls = extractParenthesizedCalls(marker: ".package(", in: manifest)
      for call in packageCalls {
        if let url = extractFirstRegexGroup(#"\burl\s*:\s*"([^"]+)""#, in: call) {
          let normURL = normalizeGitURL(url)
          let explicitName = extractFirstRegexGroup(#"\bname\s*:\s*"([^"]+)""#, in: call)
          let urlSlug = packageNameFromURL(url)
          let pkgName = explicitName ?? urlSlug
          let requirement = parseSwiftPMRequirement(from: call)
          let pin = effectivePins.first(where: {
            normalizeGitURL($0.location) == normURL
              || $0.identity == urlSlug.lowercased()
              || $0.identity == pkgName.lowercased()
          })
          if remotesByNormalizedURL[normURL] == nil {
            remotesByNormalizedURL[normURL] = RemotePackageDependency(
              id: "transitive:\(urlSlug.lowercased())",
              repositoryURL: url,
              packageName: urlSlug,
              requirement: requirement,
              pinnedRevision: pin?.revision,
              pinnedVersion: pin?.version
            )
          }
        } else if let relPath = extractFirstRegexGroup(#"\bpath\s*:\s*"([^"]+)""#, in: call),
                  !relPath.isEmpty,
                  !relPath.contains("\\(")
        {
          let childDir = URL(fileURLWithPath: relPath, relativeTo: packageRoot).standardizedFileURL
          if FileManager.default.fileExists(atPath: childDir.appendingPathComponent("Package.swift").path) {
            scanPackage(at: childDir, accumulatedPins: effectivePins)
          }
        }
      }

      let productCalls = extractParenthesizedCalls(marker: ".product(", in: manifest)
      for call in productCalls {
        guard let prodName = extractFirstRegexGroup(#"\bname\s*:\s*"([^"]+)""#, in: call),
              let pkgRef = extractFirstRegexGroup(#"\bpackage\s*:\s*"([^"]+)""#, in: call),
              !prodName.isEmpty,
              !pkgRef.isEmpty
        else {
          continue
        }
        if productToPackageKey[prodName] == nil {
          productToPackageKey[prodName] = pkgRef.lowercased()
        }
      }
    }

    for local in localPackages {
      scanPackage(at: local.path, accumulatedPins: pins)
    }

    return TransitiveRemoteDiscovery(
      remotes: Array(remotesByNormalizedURL.values).sorted { $0.packageName < $1.packageName },
      productToPackageKey: productToPackageKey
    )
  }

  private static func parseSwiftPMRequirement(from packageCall: String) -> PackageRequirement {
    if let rev = extractFirstRegexGroup(#"\brevision\s*:\s*"([^"]+)""#, in: packageCall) {
      return .revision(rev)
    }
    if let branch = extractFirstRegexGroup(#"\bbranch\s*:\s*"([^"]+)""#, in: packageCall) {
      return .branch(branch)
    }
    if let exact = extractFirstRegexGroup(#"\bexact\s*:\s*"([^"]+)""#, in: packageCall) {
      return .exact(exact)
    }
    if let upMinor = extractFirstRegexGroup(#"\.upToNextMinor\s*\(\s*from\s*:\s*"([^"]+)""#, in: packageCall) {
      return .upToNextMinor(upMinor)
    }
    if let from = extractFirstRegexGroup(#"\bfrom\s*:\s*"([^"]+)""#, in: packageCall) {
      return .upToNextMajor(from)
    }
    if let regex = try? NSRegularExpression(pattern: #""([^"]+)"\s*\.\.<\s*"([^"]+)""#),
       let match = regex.firstMatch(in: packageCall, range: NSRange(packageCall.startIndex..., in: packageCall)),
       let r1 = Range(match.range(at: 1), in: packageCall),
       let r2 = Range(match.range(at: 2), in: packageCall)
    {
      return .range(from: String(packageCall[r1]), to: String(packageCall[r2]))
    }
    return .upToNextMajor("1.0.0")
  }

  private static func stripSwiftCommentsPreservingStrings(_ text: String) -> String {
    let chars = Array(text)
    let count = chars.count
    var out = ""
    out.reserveCapacity(count)
    var i = 0
    while i < count {
      if chars[i] == "\"" {
        let start = i
        i += 1
        while i < count {
          if chars[i] == "\\" { i += 2; continue }
          if chars[i] == "\"" { i += 1; break }
          i += 1
        }
        out.append(contentsOf: chars[start..<min(i, count)])
        continue
      }
      if i + 1 < count && chars[i] == "/" && chars[i + 1] == "/" {
        i += 2
        while i < count && !chars[i].isNewline { i += 1 }
        continue
      }
      if i + 1 < count && chars[i] == "/" && chars[i + 1] == "*" {
        i += 2
        while i + 1 < count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
        i = min(count, i + 2)
        continue
      }
      out.append(chars[i])
      i += 1
    }
    return out
  }

  private static func extractParenthesizedCalls(marker: String, in text: String) -> [String] {
    let chars = Array(text)
    let markerChars = Array(marker)
    let count = chars.count
    var results: [String] = []
    var i = 0

    func matchesMarker(at idx: Int) -> Bool {
      guard idx + markerChars.count <= count else { return false }
      for k in 0..<markerChars.count where chars[idx + k] != markerChars[k] { return false }
      return true
    }

    while i < count {
      if chars[i] == "\"" {
        i += 1
        while i < count {
          if chars[i] == "\\" { i += 2; continue }
          if chars[i] == "\"" { i += 1; break }
          i += 1
        }
        continue
      }
      if matchesMarker(at: i) {
        let start = i
        var j = i + markerChars.count
        var depth = 1
        while j < count && depth > 0 {
          if chars[j] == "\"" {
            j += 1
            while j < count {
              if chars[j] == "\\" { j += 2; continue }
              if chars[j] == "\"" { j += 1; break }
              j += 1
            }
            continue
          }
          if chars[j] == "(" { depth += 1 }
          else if chars[j] == ")" { depth -= 1 }
          j += 1
        }
        results.append(String(chars[start..<j]))
        i = j
        continue
      }
      i += 1
    }
    return results
  }

  private static func extractFirstRegexGroup(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[range])
  }
}
