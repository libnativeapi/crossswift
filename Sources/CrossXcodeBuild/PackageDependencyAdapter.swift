import Foundation

/// Generic adapter for external Apple-ecosystem SwiftPM packages consumed by an
/// Xcode project when building on Windows or Linux through CrossSwiftUI.
///
/// Two Apple-only assumptions break unmodified SwiftPM packages on non-Apple hosts:
/// 1. Targets `import SwiftUI`, `AppKit`, `CoreGraphics`, etc. without declaring a
///    SwiftPM dependency because those modules live in Apple's system SDK.
/// 2. Targets ship `*.xcassets` catalogs without declaring `resources:` in
///    `Package.swift`, relying on Xcode's implicit asset-catalog compilation and
///    `Bundle.module` synthesis.
///
/// `PackageDependencyAdapter` inspects a package checkout, detects whether either
/// condition applies, and — when needed — writes a patched `Package.swift` that
/// injects the required CrossSwiftUI product dependencies and explicit `.copy(...)`
/// resource entries for undeclared `*.xcassets` catalogs. Pure-Swift packages that
/// need neither patch are left untouched.
public enum PackageDependencyAdapter {
  /// Modules provided by CrossSwiftUI that Apple packages import implicitly from the SDK.
  public static let crossSwiftProvidedModules: Set<String> = [
    "SwiftUI",
    "AppKit",
    "UIKit",
    "QuartzCore",
    "CoreGraphics",
    "Combine",
    "CryptoKit",
    "UniformTypeIdentifiers",
    "OSLog",
    "ServiceManagement",
    "ImageIO",
    "QuickLookThumbnailing",
    "AVKit",
    "CloudKit",
    "ColorSync",
    "CommonCrypto",
    "Compression",
    "JavaScriptCore",
    "Translation",
  ]

  /// Consumer-side symbol and string-literal references collected from the app
  /// targets and local packages, used to generically tree-shake oversized `*.xcassets`
  /// catalogs down to only the `.imageset`s actually referenced by the project.
  public struct ConsumerReferences: Equatable, Sendable {
    public let memberIdentifiers: Set<String>
    public let stringLiterals: Set<String>

    public init(memberIdentifiers: Set<String> = [], stringLiterals: Set<String> = []) {
      self.memberIdentifiers = memberIdentifiers
      self.stringLiterals = stringLiterals
    }

    public var isEmpty: Bool {
      memberIdentifiers.isEmpty && stringLiterals.isEmpty
    }

    /// Scans all Swift source files in the project's targets and local packages.
    public static func scan(project: ResolvedXcodeProject) -> ConsumerReferences {
      var files: [URL] = []
      for target in project.allTargets {
        files.append(contentsOf: target.swiftSources)
      }
      var dirs: [URL] = []
      for local in project.localPackages {
        dirs.append(local.path)
      }
      return scan(swiftFiles: files, additionalDirectories: dirs)
    }

    public static func scan(
      swiftFiles: [URL],
      additionalDirectories: [URL] = []
    ) -> ConsumerReferences {
      var allFiles = swiftFiles
      let fm = FileManager.default
      for dir in additionalDirectories {
        guard let enumerator = fm.enumerator(
          at: dir,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        ) else { continue }
        for case let fileURL as URL in enumerator {
          let name = fileURL.lastPathComponent
          if name == ".build" || name == ".git" || name == "node_modules" || name.lowercased().hasSuffix(".xcassets") {
            enumerator.skipDescendants()
            continue
          }
          if fileURL.pathExtension.lowercased() == "swift" {
            allFiles.append(fileURL)
          }
        }
      }

      let memberRegex = try? NSRegularExpression(pattern: "\\.([A-Za-z_][A-Za-z0-9_]*)\\b")
      let stringRegex = try? NSRegularExpression(pattern: "\"([^\"\\\\\\n]{1,160})\"")

      var members = Set<String>()
      var strings = Set<String>()
      for file in allFiles {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        let range = NSRange(text.startIndex..., in: text)
        if let memberRegex {
          for m in memberRegex.matches(in: text, range: range) {
            if let r = Range(m.range(at: 1), in: text) {
              members.insert(String(text[r]))
            }
          }
        }
        if let stringRegex {
          for m in stringRegex.matches(in: text, range: range) {
            if let r = Range(m.range(at: 1), in: text) {
              strings.insert(String(text[r]))
            }
          }
        }
      }
      return ConsumerReferences(memberIdentifiers: members, stringLiterals: strings)
    }
  }

  public struct TargetInspection: Equatable, Sendable {
    public let name: String
    public let relativePath: String
    public let importedCrossSwiftModules: [String]
    public let undeclaredAssetCatalogs: [String]
    public let largeAssetCatalogs: [String]
    public let hasObjCAttributes: Bool
    public let importsJavaScriptKit: Bool

    public init(
      name: String,
      relativePath: String,
      importedCrossSwiftModules: [String],
      undeclaredAssetCatalogs: [String],
      largeAssetCatalogs: [String],
      hasObjCAttributes: Bool,
      importsJavaScriptKit: Bool = false
    ) {
      self.name = name
      self.relativePath = relativePath
      self.importedCrossSwiftModules = importedCrossSwiftModules
      self.undeclaredAssetCatalogs = undeclaredAssetCatalogs
      self.largeAssetCatalogs = largeAssetCatalogs
      self.hasObjCAttributes = hasObjCAttributes
      self.importsJavaScriptKit = importsJavaScriptKit
    }
  }

  public struct InspectionResult: Equatable, Sendable {
    public let targets: [TargetInspection]
    public var needsAdaptation: Bool {
      targets.contains {
        !$0.importedCrossSwiftModules.isEmpty
          || !$0.undeclaredAssetCatalogs.isEmpty
          || !$0.largeAssetCatalogs.isEmpty
          || $0.hasObjCAttributes
          || $0.importsJavaScriptKit
      }
    }
  }

  /// Lists `.target(...)` declarations from a SwiftPM package manifest, independent of adaptation status.
  public static func listLibraryTargets(in packageRoot: URL) -> [(name: String, relativePath: String)] {
    let manifestURL = packageRoot.appendingPathComponent("Package.swift")
    guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
      return []
    }
    return parseTargetDeclarations(from: manifest).map { decl in
      (name: decl.name, relativePath: decl.path ?? "Sources/\(decl.name)")
    }
  }

  /// Inspects a local Swift package directory to determine whether any of its
  /// targets need CrossSwiftUI module dependencies or undeclared `.xcassets` resources.
  public static func inspect(
    packageRoot: URL,
    allowedCrossSwiftModules: Set<String> = crossSwiftProvidedModules,
    includeJavaScriptKit: Bool = false
  ) -> InspectionResult {
    let manifestURL = packageRoot.appendingPathComponent("Package.swift")
    guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
      return InspectionResult(targets: [])
    }

    // If the package already explicitly references CrossSwiftUI, leave it as-is.
    if manifest.contains("CrossSwiftUI") {
      return InspectionResult(targets: [])
    }

    let declaredTargets = parseTargetDeclarations(from: manifest)
    let fm = FileManager.default
    var results: [TargetInspection] = []

    for decl in declaredTargets {
      let relPath = decl.path ?? "Sources/\(decl.name)"
      let targetDir = packageRoot.appendingPathComponent(relPath)
      guard fm.fileExists(atPath: targetDir.path) else { continue }

      let (imports, hasObjC) = scanSwiftSources(in: targetDir)
      let crossSwiftImports = imports
        .filter { allowedCrossSwiftModules.contains($0) }
        .sorted()
      let importsJSKit = includeJavaScriptKit && imports.contains("JavaScriptKit")

      let allCatalogs = findAssetCatalogs(in: targetDir)
        .filter { relCatalog in
          // Skip catalogs already mentioned in the target's manifest slice.
          let catalogName = URL(fileURLWithPath: relCatalog).lastPathComponent
          return !decl.rawBody.contains(relCatalog) && !decl.rawBody.contains(catalogName)
        }
        .sorted()

      var smallCatalogs: [String] = []
      var largeCatalogs: [String] = []
      for relCatalog in allCatalogs {
        let catalogURL = targetDir.appendingPathComponent(relCatalog)
        let entryCount = (try? fm.contentsOfDirectory(atPath: catalogURL.path).count) ?? 0
        if entryCount > 200 {
          largeCatalogs.append(relCatalog)
        } else {
          smallCatalogs.append(relCatalog)
        }
      }

      results.append(TargetInspection(
        name: decl.name,
        relativePath: relPath,
        importedCrossSwiftModules: crossSwiftImports,
        undeclaredAssetCatalogs: smallCatalogs,
        largeAssetCatalogs: largeCatalogs,
        hasObjCAttributes: hasObjC,
        importsJavaScriptKit: importsJSKit
      ))
    }

    return InspectionResult(targets: results)
  }

  /// Patches `Package.swift` text in-place for a checked-out package so its targets
  /// depend on CrossSwiftUI products for implicitly imported Apple frameworks and
  /// explicitly copy any undeclared `*.xcassets` catalogs into `Bundle.module`.
  ///
  /// When `prunedLargeCatalogs` contains a large catalog's relative path, it is
  /// staged as a pruned `.xcassets` directory and declared with `.copy(<relPath>)`
  /// instead of falling back to a `crossswift-assets.json` pointer.
  public static func patchManifest(
    _ manifest: String,
    inspection: InspectionResult,
    crossSwiftRoot: URL,
    prunedLargeCatalogs: Set<String> = [],
    useWasmBundleShim: Bool = false,
    adaptedRemoteOverrides: [String: URL] = [:],
    sourceRoot: URL? = nil
  ) -> String {
    var updated = rewritePackageDependencies(
      manifest,
      adaptedRemoteOverrides: adaptedRemoteOverrides,
      sourceRoot: sourceRoot
    )
    let didRewriteDeps = updated != manifest
    guard inspection.needsAdaptation || didRewriteDeps else { return manifest }

    let crossSwiftIdentity = crossSwiftRoot.lastPathComponent.lowercased()
    let crossSwiftPkgDecl = ".package(path: \(swiftStringLiteral(crossSwiftRoot.path)))"

    // 1. Ensure top-level `dependencies: [...]` includes CrossSwiftUI (and JavaScriptKit on Wasm if needed).
    if inspection.targets.contains(where: { !$0.importedCrossSwiftModules.isEmpty }) {
      updated = injectTopLevelPackageDependency(updated, packageDecl: crossSwiftPkgDecl)
    }
    if inspection.targets.contains(where: { $0.importsJavaScriptKit }) && !updated.contains("JavaScriptKit") {
      updated = injectTopLevelPackageDependency(
        updated,
        packageDecl: ".package(url: \"https://github.com/swiftwasm/JavaScriptKit.git\", exact: \"0.63.0\")"
      )
    }

    // 2. For each target needing modules or resources, patch its `.target(...)` block.
    for target in inspection.targets
      where !target.importedCrossSwiftModules.isEmpty
        || target.importsJavaScriptKit
        || !target.undeclaredAssetCatalogs.isEmpty
        || !target.largeAssetCatalogs.isEmpty
    {
      var productDeps = target.importedCrossSwiftModules.map { mod in
        ".product(name: \(swiftStringLiteral(mod)), package: \(swiftStringLiteral(crossSwiftIdentity)))"
      }
      if target.importsJavaScriptKit {
        productDeps.append(".product(name: \"JavaScriptKit\", package: \"javascriptkit\")")
      }
      var excludeDecls: [String] = []
      var resourceDecls: [String] = []
      if useWasmBundleShim {
        // WASI has no on-disk .resources bundle for SwiftPM's synthesized Bundle.module;
        // ApplicationStager publishes these catalogs into web-manifest.json instead.
        for relPath in target.undeclaredAssetCatalogs {
          excludeDecls.append(swiftStringLiteral(relPath))
        }
        for relPath in target.largeAssetCatalogs where prunedLargeCatalogs.contains(relPath) {
          excludeDecls.append(swiftStringLiteral(relPath))
        }
      } else {
        resourceDecls = target.undeclaredAssetCatalogs.map { relPath in
          ".copy(\(swiftStringLiteral(relPath)))"
        }
        var needsPointerFallback = false
        for relPath in target.largeAssetCatalogs {
          if prunedLargeCatalogs.contains(relPath) {
            resourceDecls.append(".copy(\(swiftStringLiteral(relPath)))")
          } else {
            needsPointerFallback = true
          }
        }
        if needsPointerFallback {
          resourceDecls.append(".copy(\"crossswift-assets.json\")")
        }
      }
      updated = patchTargetBlock(
        in: updated,
        targetName: target.name,
        addDependencies: productDeps,
        addExcludes: excludeDecls,
        addResources: resourceDecls
      )
    }

    return updated
  }

  /// Rewrites `.package(url: ...)` declarations matching `adaptedRemoteOverrides` to local
  /// `.package(path: ...)` declarations, and resolves relative `.package(path: "...")`
  /// literals against `sourceRoot` so adapted local packages stay valid from staging dirs.
  private static func rewritePackageDependencies(
    _ manifest: String,
    adaptedRemoteOverrides: [String: URL],
    sourceRoot: URL?
  ) -> String {
    guard !adaptedRemoteOverrides.isEmpty || sourceRoot != nil else { return manifest }
    let chars = Array(manifest)
    let count = chars.count
    var i = 0
    var result = ""
    let marker = Array(".package(")

    func matchMarker(at idx: Int) -> Bool {
      guard idx + marker.count <= count else { return false }
      for k in 0..<marker.count where chars[idx + k] != marker[k] { return false }
      return true
    }

    let urlRegex = try? NSRegularExpression(pattern: #"\burl\s*:\s*"([^"]+)""#)
    let pathRegex = try? NSRegularExpression(pattern: #"\bpath\s*:\s*"([^"]+)""#)

    while i < count {
      // Skip line comments
      if i + 1 < count && chars[i] == "/" && chars[i + 1] == "/" {
        let start = i
        i += 2
        while i < count && !chars[i].isNewline { i += 1 }
        result.append(contentsOf: chars[start..<i])
        continue
      }
      // Skip block comments
      if i + 1 < count && chars[i] == "/" && chars[i + 1] == "*" {
        let start = i
        i += 2
        while i + 1 < count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
        i = min(count, i + 2)
        result.append(contentsOf: chars[start..<i])
        continue
      }
      // Skip string literals
      if chars[i] == "\"" {
        let start = i
        i += 1
        while i < count {
          if chars[i] == "\\" { i += 2; continue }
          if chars[i] == "\"" { i += 1; break }
          i += 1
        }
        result.append(contentsOf: chars[start..<min(i, count)])
        continue
      }

      if matchMarker(at: i) {
        let callStart = i
        var j = i + marker.count
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
        let callText = String(chars[callStart..<j])
        let nsCall = callText as NSString
        let fullRange = NSRange(location: 0, length: nsCall.length)

        var replacement: String? = nil
        if !adaptedRemoteOverrides.isEmpty,
           let m = urlRegex?.firstMatch(in: callText, range: fullRange),
           let r = Range(m.range(at: 1), in: callText)
        {
          let rawURL = String(callText[r])
          let lowerURL = rawURL.lowercased()
          let urlLast = rawURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").last.map(String.init) ?? ""
          let slug = (urlLast.hasSuffix(".git") ? String(urlLast.dropLast(4)) : urlLast).lowercased()
          if let overrideURL = adaptedRemoteOverrides[lowerURL] ?? adaptedRemoteOverrides[slug] {
            replacement = ".package(path: \(swiftStringLiteral(overrideURL.path)))"
          }
        } else if let sourceRoot,
                  let m = pathRegex?.firstMatch(in: callText, range: fullRange),
                  let r = Range(m.range(at: 1), in: callText)
        {
          let rawPath = String(callText[r])
          let isWindowsAbs = rawPath.count >= 2 && rawPath[rawPath.index(after: rawPath.startIndex)] == ":"
          if !rawPath.isEmpty && !rawPath.hasPrefix("/") && !rawPath.hasPrefix("\\") && !isWindowsAbs && !rawPath.contains("\\(") {
            let resolved = sourceRoot.appendingPathComponent(rawPath).standardizedFileURL.path
              .replacingOccurrences(of: "\\", with: "/")
            replacement = callText.replacingCharacters(in: r, with: resolved)
          }
        }

        result.append(replacement ?? callText)
        i = j
        continue
      }

      result.append(chars[i])
      i += 1
    }

    return result
  }

  /// Adapts a checked-out package directory into `outputDirectory` if inspection shows
  /// it needs CrossSwiftUI module injection, `@objc` stripping, or undeclared `.xcassets`
  /// resource wiring. Returns `nil` if the package needs no adaptation.
  ///
  /// When `consumerReferences` is provided, oversized `*.xcassets` catalogs (> 200 entries)
  /// are generically tree-shaken by matching consumer member/string references against the
  /// package's Swift enum-to-string mappings and `.imageset` names so only referenced assets
  /// are bundled into the self-contained `.resources` output.
  public static func adaptCheckoutIfNeeded(
    sourceRoot: URL,
    outputDirectory: URL,
    crossSwiftRoot: URL,
    consumerReferences: ConsumerReferences? = nil,
    allowedCrossSwiftModules: Set<String> = crossSwiftProvidedModules,
    useWasmBundleShim: Bool = false,
    adaptedRemoteOverrides: [String: URL] = [:],
    resolveRelativePaths: Bool = false
  ) throws -> URL? {
    let inspection = inspect(
      packageRoot: sourceRoot,
      allowedCrossSwiftModules: allowedCrossSwiftModules,
      includeJavaScriptKit: useWasmBundleShim
    )

    let fm = FileManager.default
    let manifestURL = sourceRoot.appendingPathComponent("Package.swift")
    guard let originalManifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
      return nil
    }

    // Compute generic tree-shaken imageset subsets for any large *.xcassets catalogs.
    var prunedImagesetsByCatalogKey: [String: [String]] = [:]
    var prunedLargeCatalogRelPaths = Set<String>()
    if let refs = consumerReferences, !refs.isEmpty {
      for target in inspection.targets where !target.largeAssetCatalogs.isEmpty {
        let srcTarget = sourceRoot.appendingPathComponent(target.relativePath)
        let candidateNames = resolveReferencedAssetNames(in: srcTarget, consumerReferences: refs)
        for relCatalog in target.largeAssetCatalogs {
          let srcCatalog = srcTarget.appendingPathComponent(relCatalog)
          let matched = candidateNames.filter { name in
            fm.fileExists(atPath: srcCatalog.appendingPathComponent("\(name).imageset").path)
          }.sorted()
          if !matched.isEmpty {
            let key = "\(target.name)|\(relCatalog)"
            prunedImagesetsByCatalogKey[key] = matched
            prunedLargeCatalogRelPaths.insert(relCatalog)
          }
        }
      }
    }

    let patchedManifest = patchManifest(
      originalManifest,
      inspection: inspection,
      crossSwiftRoot: crossSwiftRoot,
      prunedLargeCatalogs: prunedLargeCatalogRelPaths,
      useWasmBundleShim: useWasmBundleShim,
      adaptedRemoteOverrides: adaptedRemoteOverrides,
      sourceRoot: resolveRelativePaths ? sourceRoot : nil
    )

    guard inspection.needsAdaptation || patchedManifest != originalManifest else { return nil }

    let stampSummary = prunedImagesetsByCatalogKey.keys.sorted().map { key in
      "\(key)=\(prunedImagesetsByCatalogKey[key]?.joined(separator: ",") ?? "")"
    }.joined(separator: "\n")
    let stampText = patchedManifest + "\n// PRUNED-V2:\n" + stampSummary
    let stampURL = outputDirectory.appendingPathComponent(".crossswift-adapt-stamp")
    let dstManifestURL = outputDirectory.appendingPathComponent("Package.swift")
    if let existingStamp = try? String(contentsOf: stampURL, encoding: .utf8),
       existingStamp == stampText,
       fm.fileExists(atPath: dstManifestURL.path)
    {
      return outputDirectory
    }

    if fm.fileExists(atPath: outputDirectory.path) {
      try removeDirectoryPreservingLinkTargets(outputDirectory)
    }
    try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    // Only stage the directories actually referenced by declared targets (plus Package.swift),
    // avoiding unrelated repository trees (such as web/android assets or docs).
    let needsSwiftRewrite = inspection.targets.contains { $0.hasObjCAttributes }
    for target in inspection.targets {
      let rel = target.relativePath
      let srcTarget = sourceRoot.appendingPathComponent(rel)
      let dstTarget = outputDirectory.appendingPathComponent(rel)
      guard fm.fileExists(atPath: srcTarget.path) else { continue }

      let targetHasPrunedCatalog = target.largeAssetCatalogs.contains {
        prunedImagesetsByCatalogKey["\(target.name)|\($0)"] != nil
      }
      var keptEnumCases: Set<String>? = nil
      if targetHasPrunedCatalog, let refs = consumerReferences, !refs.isEmpty {
        // Union consumer member identifiers with any member identifiers referenced by
        // smaller sibling Swift files inside the same target (e.g. #Preview blocks).
        var kept = refs.memberIdentifiers
        kept.formUnion(scanSmallSiblingMemberReferences(in: srcTarget))
        keptEnumCases = kept
      }

      if !needsSwiftRewrite
        && !targetHasPrunedCatalog
        && target.largeAssetCatalogs.isEmpty
        && !(useWasmBundleShim && !target.undeclaredAssetCatalogs.isEmpty)
      {
        try fm.createDirectory(at: dstTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try linkOrCopyDirectory(from: srcTarget, to: dstTarget)
      } else {
        try stageDirectory(
          from: srcTarget,
          to: dstTarget,
          skipNames: Set(target.largeAssetCatalogs.map { URL(fileURLWithPath: $0).lastPathComponent }),
          stripObjCInSwiftFiles: needsSwiftRewrite,
          pruneEnumCases: keptEnumCases
        )
      }

      var fallbackCatalogPaths: [String] = []
      for relCatalog in target.largeAssetCatalogs {
        let key = "\(target.name)|\(relCatalog)"
        let srcCatalog = srcTarget.appendingPathComponent(relCatalog)
        if let matchedSets = prunedImagesetsByCatalogKey[key], !matchedSets.isEmpty {
          let dstCatalog = dstTarget.appendingPathComponent(relCatalog)
          try fm.createDirectory(at: dstCatalog, withIntermediateDirectories: true)
          let srcContents = srcCatalog.appendingPathComponent("Contents.json")
          if fm.fileExists(atPath: srcContents.path) {
            try fm.copyItem(at: srcContents, to: dstCatalog.appendingPathComponent("Contents.json"))
          } else {
            try "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".write(
              to: dstCatalog.appendingPathComponent("Contents.json"),
              atomically: true,
              encoding: .utf8
            )
          }
          for name in matchedSets {
            let srcSet = srcCatalog.appendingPathComponent("\(name).imageset")
            let dstSet = dstCatalog.appendingPathComponent("\(name).imageset")
            if !fm.fileExists(atPath: dstSet.path) {
              try fm.copyItem(at: srcSet, to: dstSet)
            }
          }
        } else {
          fallbackCatalogPaths.append(srcCatalog.standardizedFileURL.path)
        }
      }

      if useWasmBundleShim && (!target.undeclaredAssetCatalogs.isEmpty || !target.largeAssetCatalogs.isEmpty) {
        let shimSource = """
        #if os(WASI) || os(Android) || CROSS_SWIFTUI_HARMONY
        import Foundation

        extension Foundation.Bundle {
          static var module: Foundation.Bundle {
            #if CROSS_SWIFTUI_HARMONY || os(Android)
              for path in [
                FileManager.default.currentDirectoryPath,
                FileManager.default.temporaryDirectory.path,
                "/data/storage/el1/bundle",
                "/",
              ] {
                if let bundle = Foundation.Bundle(path: path) { return bundle }
              }
            #endif
            return .main
          }
        }
        #endif
        """
        try shimSource.write(
          to: dstTarget.appendingPathComponent("_CrossSwiftUIWasmBundleShim.swift"),
          atomically: true,
          encoding: .utf8
        )
      }

      if !useWasmBundleShim && !fallbackCatalogPaths.isEmpty {
        let pointerJSON = try JSONSerialization.data(
          withJSONObject: ["catalogPaths": fallbackCatalogPaths],
          options: [.prettyPrinted, .sortedKeys]
        )
        try pointerJSON.write(
          to: dstTarget.appendingPathComponent("crossswift-assets.json"),
          options: .atomic
        )
      }
    }

    try patchedManifest.write(
      to: dstManifestURL,
      atomically: true,
      encoding: .utf8
    )
    try stampText.write(to: stampURL, atomically: true, encoding: .utf8)

    return outputDirectory
  }

  /// Resolves candidate `.imageset` resource names referenced by `consumerReferences`
  /// by combining direct string literals with any enum-case-to-string mappings found in
  /// the target's Swift sources (`case foo = "bar"` or `case .foo: return "bar"`).
  public static func resolveReferencedAssetNames(
    in targetDir: URL,
    consumerReferences: ConsumerReferences
  ) -> Set<String> {
    var candidates = consumerReferences.stringLiterals
    let members = consumerReferences.memberIdentifiers
    guard !members.isEmpty else { return candidates }

    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: targetDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return candidates }

    for case let fileURL as URL in enumerator {
      let name = fileURL.lastPathComponent
      if name.lowercased().hasSuffix(".xcassets") || name == ".build" || name == ".git" {
        enumerator.skipDescendants()
        continue
      }
      guard fileURL.pathExtension.lowercased() == "swift",
            let text = try? String(contentsOf: fileURL, encoding: .utf8)
      else { continue }

      text.enumerateLines { line, _ in
        guard line.contains("case "), line.contains("\"") else { return }
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("case ") else { return }
        let afterCase = trimmed.dropFirst(5).drop(while: { $0 == " " || $0 == "\t" })
        let identStart = afterCase.hasPrefix(".") ? afterCase.dropFirst() : afterCase
        let ident = String(identStart.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
        guard !ident.isEmpty, members.contains(ident) else { return }
        // Extract the first double-quoted string literal on the line.
        guard let q1 = afterCase.firstIndex(of: "\"") else { return }
        let afterQ1 = afterCase.index(after: q1)
        guard afterQ1 < afterCase.endIndex,
              let q2 = afterCase[afterQ1...].firstIndex(of: "\"")
        else { return }
        let value = String(afterCase[afterQ1..<q2])
        if !value.isEmpty && !value.hasPrefix(".") {
          candidates.insert(value)
        }
      }
    }

    return candidates
  }

  private static func removeDirectoryPreservingLinkTargets(_ dir: URL) throws {
    #if os(Windows)
      let cmdExe = URL(fileURLWithPath: ProcessRunner.environmentValue("ComSpec") ?? "C:\\Windows\\System32\\cmd.exe")
      let winPath = dir.path.replacingOccurrences(of: "/", with: "\\")
      _ = try? ProcessRunner.run(executable: cmdExe, arguments: ["/c", "rmdir", "/s", "/q", winPath])
    #else
      try FileManager.default.removeItem(at: dir)
    #endif
  }

  /// Stages `src` into `dst`, linking directories that contain no `.swift` files
  /// (such as `*.xcassets` or `Assets/` trees) to avoid duplicating large assets,
  /// while copying `.swift` files with `@objc` attributes stripped when needed.
  private static func stageDirectory(
    from src: URL,
    to dst: URL,
    skipNames: Set<String> = [],
    stripObjCInSwiftFiles: Bool,
    pruneEnumCases: Set<String>? = nil
  ) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: dst, withIntermediateDirectories: true)
    let items = try fm.contentsOfDirectory(atPath: src.path)
    for item in items {
      if skipNames.contains(item) { continue }
      let srcItem = src.appendingPathComponent(item)
      let dstItem = dst.appendingPathComponent(item)
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: srcItem.path, isDirectory: &isDir) else { continue }
      if isDir.boolValue {
        let needsSwiftProcessing = stripObjCInSwiftFiles || pruneEnumCases != nil
        if !needsSwiftProcessing
          || item.lowercased().hasSuffix(".xcassets")
          || (!directoryContainsSwiftFiles(srcItem) && !directoryContainsAnyName(srcItem, names: skipNames))
        {
          try linkOrCopyDirectory(from: srcItem, to: dstItem)
        } else {
          try stageDirectory(
            from: srcItem,
            to: dstItem,
            skipNames: skipNames,
            stripObjCInSwiftFiles: stripObjCInSwiftFiles,
            pruneEnumCases: pruneEnumCases
          )
        }
      } else if (stripObjCInSwiftFiles || pruneEnumCases != nil) && srcItem.pathExtension.lowercased() == "swift",
                var text = try? String(contentsOf: srcItem, encoding: .utf8)
      {
        if stripObjCInSwiftFiles {
          text = stripObjCAttributes(text)
        }
        if let keptCases = pruneEnumCases {
          text = pruneOversizedAssetEnumSource(text, keepingCases: keptCases)
        }
        try text.write(to: dstItem, atomically: true, encoding: .utf8)
      } else {
        try fm.copyItem(at: srcItem, to: dstItem)
      }
    }
  }

  /// Scans `.swift` files <= 100 KB inside `targetDir` for `.member` references so
  /// internal references (such as `#Preview` blocks) are preserved when pruning an
  /// oversized generated asset enum file in the same target.
  private static func scanSmallSiblingMemberReferences(in targetDir: URL) -> Set<String> {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: targetDir,
      includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }
    guard let regex = try? NSRegularExpression(pattern: "\\.([A-Za-z_][A-Za-z0-9_]*)\\b") else {
      return []
    }
    var members = Set<String>()
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if name.lowercased().hasSuffix(".xcassets") || name == ".build" || name == ".git" {
        enumerator.skipDescendants()
        continue
      }
      guard url.pathExtension.lowercased() == "swift" else { continue }
      if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 100_000 {
        continue
      }
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      for m in regex.matches(in: text, range: range) {
        if let r = Range(m.range(at: 1), in: text) {
          members.insert(String(text[r]))
        }
      }
    }
    return members
  }

  /// Prunes unreferenced `case <ident>` and `case .<ident>:` lines from oversized
  /// generated asset-enum Swift files (> 100 KB, > 200 cases) when a target's large
  /// `.xcassets` catalog has been tree-shaken. Keeps all non-case lines intact and
  /// leaves the file unchanged if fewer than 1 case matches `keepingCases`.
  private static func pruneOversizedAssetEnumSource(_ source: String, keepingCases: Set<String>) -> String {
    guard source.utf8.count > 100_000, !keepingCases.isEmpty else { return source }
    var totalCases = 0
    var matchedCases = 0
    var outLines: [String] = []
    outLines.reserveCapacity(1024)

    source.enumerateLines { line, _ in
      let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
      if trimmed.hasPrefix("case ") {
        let afterCase = trimmed.dropFirst(5).drop(while: { $0 == " " || $0 == "\t" })
        let identStart = afterCase.hasPrefix(".") ? afterCase.dropFirst() : afterCase
        let ident = String(identStart.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
        if !ident.isEmpty {
          totalCases += 1
          if keepingCases.contains(ident) {
            matchedCases += 1
            outLines.append(line)
          }
          return
        }
      }
      outLines.append(line)
    }

    guard totalCases > 200, matchedCases > 0 else { return source }
    return outLines.joined(separator: "\n") + "\n"
  }

  private static func directoryContainsAnyName(_ dir: URL, names: Set<String>) -> Bool {
    guard !names.isEmpty else { return false }
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
    return items.contains { names.contains($0) }
  }

  private static func directoryContainsSwiftFiles(_ dir: URL) -> Bool {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: dir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return false }
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if name.lowercased().hasSuffix(".xcassets") || name == ".build" || name == ".git" {
        enumerator.skipDescendants()
        continue
      }
      if url.pathExtension.lowercased() == "swift" {
        return true
      }
    }
    return false
  }

  private static func stripObjCAttributes(_ source: String) -> String {
    guard source.contains("@objc"),
          let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])@objc(?:\([^)]*\))?[ \t]*"#)
    else { return source }
    let ns = source as NSString
    return regex.stringByReplacingMatches(
      in: source,
      range: NSRange(location: 0, length: ns.length),
      withTemplate: ""
    )
  }

  /// Shallow-clones (or reuses a cached checkout of) a remote package dependency.
  public static func checkoutRemotePackage(
    _ remote: RemotePackageDependency,
    cacheRoot: URL,
    echoOutput: Bool = false
  ) throws -> URL {
    let fm = FileManager.default
    let targetRef: String? = {
      if let rev = remote.pinnedRevision, !rev.isEmpty { return rev }
      if let ver = remote.pinnedVersion, !ver.isEmpty { return ver }
      switch remote.requirement {
      case .revision(let r): return r
      case .branch(let b): return b
      case .exact(let v): return v
      default: return nil
      }
    }()

    let refKey = targetRef ?? "default"
    let slug = ProcessRunner.sanitizedSlug(remote.packageName).prefix(24)
    let hash = ProcessRunner.fnv1aHex(remote.repositoryURL + "|" + refKey)
    let checkoutDir = cacheRoot.appendingPathComponent("\(slug)-\(hash)")
    if fm.fileExists(atPath: checkoutDir.appendingPathComponent("Package.swift").path) {
      return checkoutDir
    }

    guard let gitExe = ProcessRunner.findExecutable(named: ["git"]) else {
      throw BuildBackendError.toolMissing(
        "Could not locate 'git' to inspect remote package \(remote.repositoryURL)"
      )
    }

    if echoOutput {
      ProcessRunner.writeStdoutLine(
        "Fetching remote package \(remote.packageName) (\(remote.repositoryURL))..."
      )
    }

    try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    if fm.fileExists(atPath: checkoutDir.path) {
      try? fm.removeItem(at: checkoutDir)
    }

    if let targetRef {
      try fm.createDirectory(at: checkoutDir, withIntermediateDirectories: true)
      for args in [
        ["init"],
        ["config", "core.longpaths", "true"],
        ["remote", "add", "origin", remote.repositoryURL],
        ["fetch", "--depth", "1", "origin", targetRef],
        ["-c", "core.longpaths=true", "checkout", "FETCH_HEAD"],
      ] {
        let shouldEcho = echoOutput && args.first == "fetch"
        let res = try ProcessRunner.run(
          executable: gitExe,
          arguments: args,
          workingDirectory: checkoutDir,
          echoOutput: shouldEcho
        )
        if res.exitCode != 0 {
          try? fm.removeItem(at: checkoutDir)
          throw ProcessRunnerError.commandFailed(
            command: "git \(args.joined(separator: " "))",
            exitCode: res.exitCode,
            output: res.stdout + "\n" + res.stderr
          )
        }
      }
    } else {
      let args = ["-c", "core.longpaths=true", "clone", "--depth", "1", remote.repositoryURL, checkoutDir.path]
      let res = try ProcessRunner.run(executable: gitExe, arguments: args, echoOutput: echoOutput)
      if res.exitCode != 0 {
        throw ProcessRunnerError.commandFailed(
          command: "git \(args.joined(separator: " "))",
          exitCode: res.exitCode,
          output: res.stdout + "\n" + res.stderr
        )
      }
    }

    return checkoutDir
  }

  // MARK: - Helpers

  private struct RawTargetDecl {
    let name: String
    let path: String?
    let rawBody: String
  }

  private static func parseTargetDeclarations(from manifest: String) -> [RawTargetDecl] {
    var result: [RawTargetDecl] = []
    guard let regex = try? NSRegularExpression(pattern: "\\.(?:target|executableTarget)\\s*\\(") else {
      return result
    }
    let ns = manifest as NSString
    let matches = regex.matches(in: manifest, range: NSRange(location: 0, length: ns.length))
    for match in matches {
      let openParenIdx = match.range.location + match.range.length - 1
      guard let closeParenIdx = findMatchingDelimiter(in: manifest, openIndex: openParenIdx, open: "(", close: ")")
      else { continue }
      let bodyRange = NSRange(location: openParenIdx + 1, length: closeParenIdx - openParenIdx - 1)
      let body = ns.substring(with: bodyRange)
      guard let name = extractStringArgument(named: "name", in: body) else { continue }
      let path = extractStringArgument(named: "path", in: body)
      result.append(RawTargetDecl(name: name, path: path, rawBody: body))
    }
    return result
  }

  private static func extractStringArgument(named label: String, in text: String) -> String? {
    let pattern = "(?:^|[,\\s])\(label)\\s*:\\s*\"([^\"]+)\""
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
  }

  private static func findMatchingDelimiter(
    in text: String,
    openIndex: Int,
    open: UInt16,
    close: UInt16
  ) -> Int? {
    let units = Array(text.utf16)
    guard openIndex < units.count, units[openIndex] == open else { return nil }
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
        else if b == open { depth += 1 }
        else if b == close {
          depth -= 1
          if depth == 0 { return i }
        }
      }
      i += 1
    }
    return nil
  }

  private static func findMatchingDelimiter(
    in text: String,
    openIndex: Int,
    open: Character,
    close: Character
  ) -> Int? {
    guard let o = open.asciiValue, let c = close.asciiValue else { return nil }
    return findMatchingDelimiter(in: text, openIndex: openIndex, open: UInt16(o), close: UInt16(c))
  }

  private static func scanSwiftSources(in directory: URL) -> (modules: Set<String>, hasObjC: Bool) {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return ([], false) }

    guard let importRegex = try? NSRegularExpression(
      pattern: "(?m)^\\s*(?:@\\w+\\s+)*import\\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    ) else { return ([], false) }
    let objcRegex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])@objc(?:\([^)]*\))?"#)

    var modules = Set<String>()
    var hasObjC = false
    for case let fileURL as URL in enumerator {
      let name = fileURL.lastPathComponent
      if name.lowercased().hasSuffix(".xcassets") || name == ".build" || name == ".git" {
        enumerator.skipDescendants()
        continue
      }
      guard fileURL.pathExtension.lowercased() == "swift",
            let text = try? String(contentsOf: fileURL, encoding: .utf8)
      else { continue }
      let range = NSRange(text.startIndex..., in: text)
      for match in importRegex.matches(in: text, range: range) {
        if let r = Range(match.range(at: 1), in: text) {
          modules.insert(String(text[r]))
        }
      }
      if !hasObjC, let objcRegex, objcRegex.firstMatch(in: text, range: range) != nil {
        hasObjC = true
      }
    }
    return (modules, hasObjC)
  }

  private static func findAssetCatalogs(in targetDir: URL) -> [String] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: targetDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }

    let basePath = targetDir.standardizedFileURL.path
    var catalogs: [String] = []
    for case let itemURL as URL in enumerator {
      if itemURL.lastPathComponent.lowercased().hasSuffix(".xcassets") {
        let full = itemURL.standardizedFileURL.path
        if full.hasPrefix(basePath + "/") {
          catalogs.append(String(full.dropFirst(basePath.count + 1)))
        } else {
          catalogs.append(itemURL.lastPathComponent)
        }
        enumerator.skipDescendants()
      }
    }
    return catalogs
  }

  private static func stripSwiftComments(_ text: String) -> String {
    var out = text
    if let blockRegex = try? NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/") {
      let ns = out as NSString
      out = blockRegex.stringByReplacingMatches(
        in: out,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
      )
    }
    if let lineRegex = try? NSRegularExpression(pattern: "(?m)//.*$") {
      let ns = out as NSString
      out = lineRegex.stringByReplacingMatches(
        in: out,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
      )
    }
    return out
  }

  /// Finds the index of a top-level argument label (e.g. `dependencies` or `targets`)
  /// directly inside `Package(...)` (at nesting depth 1), ignoring comments and strings.
  private static func findTopLevelPackageLabel(
    _ label: String,
    in manifest: String,
    openParen: Int
  ) -> (labelStart: Int, colonIndex: Int, openBracket: Int?)? {
    let bytes = Array(manifest.utf16)
    let labelBytes = Array(label.utf16)
    let count = bytes.count
    guard openParen < count, bytes[openParen] == 0x28 else { return nil }

    var depth = 0
    var inString = false
    var escaped = false
    var i = openParen

    while i < count {
      let b = bytes[i]
      if inString {
        if escaped { escaped = false }
        else if b == 0x5C { escaped = true }
        else if b == 0x22 { inString = false }
        i += 1
        continue
      }
      // Line comment
      if b == 0x2F && i + 1 < count && bytes[i + 1] == 0x2F {
        i += 2
        while i < count && bytes[i] != 0x0A { i += 1 }
        continue
      }
      // Block comment
      if b == 0x2F && i + 1 < count && bytes[i + 1] == 0x2A {
        i += 2
        while i + 1 < count && !(bytes[i] == 0x2A && bytes[i + 1] == 0x2F) { i += 1 }
        i += 2
        continue
      }
      if b == 0x22 {
        inString = true
        i += 1
        continue
      }
      if b == 0x28 || b == 0x5B { // '(' or '['
        depth += 1
        i += 1
        continue
      }
      if b == 0x29 || b == 0x5D { // ')' or ']'
        depth -= 1
        if depth == 0 { return nil }
        i += 1
        continue
      }

      if depth == 1 && i + labelBytes.count < count {
        let prevIsIdent = i > 0 && isIdentByte(bytes[i - 1])
        if !prevIsIdent {
          var matched = true
          for k in 0..<labelBytes.count where bytes[i + k] != labelBytes[k] {
            matched = false
            break
          }
          if matched {
            var j = i + labelBytes.count
            while j < count && (bytes[j] == 0x20 || bytes[j] == 0x09 || bytes[j] == 0x0A || bytes[j] == 0x0D) {
              j += 1
            }
            if j < count && bytes[j] == 0x3A { // ':'
              var k = j + 1
              while k < count && (bytes[k] == 0x20 || bytes[k] == 0x09 || bytes[k] == 0x0A || bytes[k] == 0x0D) {
                k += 1
              }
              let openBracket = (k < count && bytes[k] == 0x5B) ? k : nil
              return (labelStart: i, colonIndex: j, openBracket: openBracket)
            }
          }
        }
      }
      i += 1
    }
    return nil
  }

  private static func isIdentByte(_ b: UInt16) -> Bool {
    (b >= 0x41 && b <= 0x5A)
      || (b >= 0x61 && b <= 0x7A)
      || (b >= 0x30 && b <= 0x39)
      || b == 0x5F
  }

  private static func injectTopLevelPackageDependency(_ manifest: String, packageDecl: String) -> String {
    guard let pkgRegex = try? NSRegularExpression(pattern: "Package\\s*\\("),
          let pkgMatch = pkgRegex.firstMatch(in: manifest, range: NSRange(manifest.startIndex..., in: manifest))
    else { return manifest }

    let openParen = pkgMatch.range.location + pkgMatch.range.length - 1
    let ns = manifest as NSString

    if let depLoc = findTopLevelPackageLabel("dependencies", in: manifest, openParen: openParen),
       let openBracket = depLoc.openBracket,
       let closeBracket = findMatchingDelimiter(in: manifest, openIndex: openBracket, open: "[", close: "]")
    {
      let inner = ns.substring(with: NSRange(location: openBracket + 1, length: closeBracket - openBracket - 1))
      let codeOnly = stripSwiftComments(inner).trimmingCharacters(in: .whitespacesAndNewlines)
      let prefix = ns.substring(to: closeBracket)
      let suffix = ns.substring(from: closeBracket)
      let sep = codeOnly.isEmpty ? "\n    " : (codeOnly.hasSuffix(",") ? "\n    " : ",\n    ")
      return prefix + sep + packageDecl + "\n  " + suffix
    }

    // No top-level `dependencies:` parameter; insert right before top-level `targets:`.
    if let targetsLoc = findTopLevelPackageLabel("targets", in: manifest, openParen: openParen) {
      let prefix = ns.substring(to: targetsLoc.labelStart)
      let suffix = ns.substring(from: targetsLoc.labelStart)
      return prefix + "dependencies: [\n    \(packageDecl)\n  ],\n  " + suffix
    }
    return manifest
  }

  private static func patchTargetBlock(
    in manifest: String,
    targetName: String,
    addDependencies: [String],
    addExcludes: [String] = [],
    addResources: [String]
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: "\\.(?:target|executableTarget)\\s*\\(") else {
      return manifest
    }
    let ns = manifest as NSString
    let matches = regex.matches(in: manifest, range: NSRange(location: 0, length: ns.length))
    for match in matches {
      let openParen = match.range.location + match.range.length - 1
      guard let closeParen = findMatchingDelimiter(in: manifest, openIndex: openParen, open: "(", close: ")")
      else { continue }
      let bodyRange = NSRange(location: openParen + 1, length: closeParen - openParen - 1)
      let body = ns.substring(with: bodyRange)
      guard extractStringArgument(named: "name", in: body) == targetName else { continue }

      var patchedBody = body
      if !addDependencies.isEmpty {
        patchedBody = insertIntoArrayParameter(
          in: patchedBody,
          paramName: "dependencies",
          entries: addDependencies
        )
      }
      if !addExcludes.isEmpty {
        patchedBody = insertIntoArrayParameter(
          in: patchedBody,
          paramName: "exclude",
          entries: addExcludes
        )
      }
      if !addResources.isEmpty {
        patchedBody = insertIntoArrayParameter(
          in: patchedBody,
          paramName: "resources",
          entries: addResources
        )
      }

      let prefix = ns.substring(to: bodyRange.location)
      let suffix = ns.substring(from: bodyRange.location + bodyRange.length)
      return prefix + patchedBody + suffix
    }
    return manifest
  }

  private static func insertIntoArrayParameter(
    in targetBody: String,
    paramName: String,
    entries: [String]
  ) -> String {
    let ns = targetBody as NSString
    if let regex = try? NSRegularExpression(pattern: "\\b\(paramName)\\s*:\\s*\\["),
       let match = regex.firstMatch(in: targetBody, range: NSRange(location: 0, length: ns.length))
    {
      let openBracket = match.range.location + match.range.length - 1
      if let closeBracket = findMatchingDelimiter(in: targetBody, openIndex: openBracket, open: "[", close: "]") {
        let inner = ns.substring(with: NSRange(location: openBracket + 1, length: closeBracket - openBracket - 1))
        let codeOnly = stripSwiftComments(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = ns.substring(to: closeBracket)
        let suffix = ns.substring(from: closeBracket)
        let joined = entries.joined(separator: ",\n        ")
        let sep = codeOnly.isEmpty ? "\n        " : (codeOnly.hasSuffix(",") ? "\n        " : ",\n        ")
        return prefix + sep + joined + "\n      " + suffix
      }
    }

    let joined = entries.joined(separator: ",\n        ")
    let followingLabels: [String]
    switch paramName {
    case "dependencies":
      followingLabels = ["path", "exclude", "sources", "resources", "publicHeadersPath", "packageAccess", "cSettings", "cxxSettings", "swiftSettings", "linkerSettings", "plugins"]
    case "exclude":
      followingLabels = ["sources", "resources", "publicHeadersPath", "packageAccess", "cSettings", "cxxSettings", "swiftSettings", "linkerSettings", "plugins"]
    case "resources":
      followingLabels = ["publicHeadersPath", "packageAccess", "cSettings", "cxxSettings", "swiftSettings", "linkerSettings", "plugins"]
    default:
      followingLabels = []
    }
    for label in followingLabels {
      if let labelRegex = try? NSRegularExpression(pattern: "(?m)^([ \\t]*)\(label)\\s*:"),
         let labelMatch = labelRegex.firstMatch(in: targetBody, range: NSRange(location: 0, length: ns.length))
      {
        let prefix = ns.substring(to: labelMatch.range.location)
        let suffix = ns.substring(from: labelMatch.range.location)
        return prefix + "      \(paramName): [\n        \(joined)\n      ],\n" + suffix
      }
    }
    let trimmedEnd = targetBody.trimmingCharacters(in: .whitespacesAndNewlines)
    let comma = trimmedEnd.hasSuffix(",") ? "" : ","
    return targetBody + "\(comma)\n      \(paramName): [\n        \(joined)\n      ]"
  }

  private static func linkOrCopyDirectory(from src: URL, to dst: URL) throws {
    let fm = FileManager.default
    #if os(Windows)
      let cmdExe = URL(fileURLWithPath: ProcessRunner.environmentValue("ComSpec") ?? "C:\\Windows\\System32\\cmd.exe")
      let winDst = dst.path.replacingOccurrences(of: "/", with: "\\")
      let winSrc = src.path.replacingOccurrences(of: "/", with: "\\")
      if let res = try? ProcessRunner.run(
        executable: cmdExe,
        arguments: ["/c", "mklink", "/J", winDst, winSrc]
      ), res.exitCode == 0 {
        return
      }
    #else
      if (try? fm.createSymbolicLink(at: dst, withDestinationURL: src)) != nil {
        return
      }
    #endif
    try fm.copyItem(at: src, to: dst)
  }

  private static func swiftStringLiteral(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
