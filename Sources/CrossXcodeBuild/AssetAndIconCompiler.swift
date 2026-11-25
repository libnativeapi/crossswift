import Foundation
import SwiftUIRuntime

public struct CompiledAssets: Sendable {
  public let resourcesDirectory: URL
  public let infoPlistURL: URL
  public let windowsIconURL: URL?
  public let windowsResourceScriptURL: URL?
  public let windowsManifestURL: URL?
  public let linuxIconVariants: [(size: Int, url: URL)]
  public let generatedSymbolsSwiftURL: URL?
  public let usesSQLite3: Bool
}

public enum ICOEncoder {
  public struct PNGEntry: Sendable {
    public let width: Int
    public let height: Int
    public let data: Data

    public init(width: Int, height: Int, data: Data) {
      self.width = width
      self.height = height
      self.data = data
    }
  }

  public static func readPNGDimensions(data: Data) -> (width: Int, height: Int)? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard data.count >= 24 else { return nil }
    let bytes = [UInt8](data.prefix(24))
    guard Array(bytes[0..<8]) == signature else { return nil }
    // IHDR chunk name: 'I', 'H', 'D', 'R'
    guard bytes[12] == 0x49, bytes[13] == 0x48, bytes[14] == 0x44, bytes[15] == 0x52 else {
      return nil
    }
    let width =
      (Int(bytes[16]) << 24)
      | (Int(bytes[17]) << 16)
      | (Int(bytes[18]) << 8)
      | Int(bytes[19])
    let height =
      (Int(bytes[20]) << 24)
      | (Int(bytes[21]) << 16)
      | (Int(bytes[22]) << 8)
      | Int(bytes[23])
    guard width > 0 && height > 0 else { return nil }
    return (width, height)
  }

  public static func encode(pngEntries: [PNGEntry]) -> Data? {
    guard !pngEntries.isEmpty else { return nil }
    let bounded = pngEntries.filter { $0.width <= 256 && $0.height <= 256 }
    let candidates = bounded.isEmpty
      ? [pngEntries.min(by: { $0.width * $0.height < $1.width * $1.height })!]
      : bounded.sorted(by: {
        if $0.width != $1.width { return $0.width < $1.width }
        return $0.height < $1.height
      })

    var unique: [PNGEntry] = []
    var seenDimensions = Set<String>()
    for item in candidates {
      let key = "\(item.width)x\(item.height)"
      if seenDimensions.insert(key).inserted {
        unique.append(item)
      }
    }
    guard !unique.isEmpty else { return nil }

    var output = Data()
    func appendUInt16LE(_ v: UInt16) {
      var le = v.littleEndian
      withUnsafeBytes(of: &le) { output.append(contentsOf: $0) }
    }
    func appendUInt32LE(_ v: UInt32) {
      var le = v.littleEndian
      withUnsafeBytes(of: &le) { output.append(contentsOf: $0) }
    }

    // ICONDIR header (6 bytes)
    appendUInt16LE(0) // reserved
    appendUInt16LE(1) // type: 1 = icon
    appendUInt16LE(UInt16(unique.count))

    var offset = 6 + unique.count * 16
    for entry in unique {
      let wByte: UInt8 = entry.width >= 256 ? 0 : UInt8(entry.width)
      let hByte: UInt8 = entry.height >= 256 ? 0 : UInt8(entry.height)
      output.append(wByte)
      output.append(hByte)
      output.append(0) // color count (0 = >=8bpp)
      output.append(0) // reserved
      appendUInt16LE(1) // color planes
      appendUInt16LE(32) // bits per pixel
      appendUInt32LE(UInt32(entry.data.count))
      appendUInt32LE(UInt32(offset))
      offset += entry.data.count
    }

    for entry in unique {
      output.append(entry.data)
    }
    return output
  }
}

public struct ResolvedColorAsset: Sendable, Equatable {
  public struct RGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public let a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
      self.r = r
      self.g = g
      self.b = b
      self.a = a
    }
  }

  public let name: String
  public let light: RGBA
  public let dark: RGBA

  public init(name: String, light: RGBA, dark: RGBA) {
    self.name = name
    self.light = light
    self.dark = dark
  }
}

public final class AssetAndIconCompiler {
  public init() {}

  public func compile(
    project: ResolvedXcodeProject,
    stagingRoot: URL
  ) throws -> CompiledAssets {
    let fm = FileManager.default
    let resourcesDir = stagingRoot.appendingPathComponent("Resources")
    let winMetaDir = stagingRoot.appendingPathComponent("WindowsMeta")
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: winMetaDir, withIntermediateDirectories: true)

    let target = project.mainTarget
    var expectedResourceTopNames = Set<String>(["Info.plist", "AppIcon.ico", "AppIcon.png"])

    // 1. Incrementally sync *.xcassets, *.xcstrings, and other resource files into Resources/
    for xcassets in target.assetCatalogs {
      let name = xcassets.lastPathComponent
      expectedResourceTopNames.insert(name)
      let dest = resourcesDir.appendingPathComponent(name)
      try IncrementalFileWriter.syncDirectory(from: xcassets, to: dest)
    }
    for xcstrings in target.stringCatalogs {
      let name = xcstrings.lastPathComponent
      expectedResourceTopNames.insert(name)
      let dest = resourcesDir.appendingPathComponent(name)
      try IncrementalFileWriter.copyFileIfChanged(from: xcstrings, to: dest)
    }
    var expectedLprojFiles: [String: Set<String>] = [:]
    for res in target.otherResources {
      if res.pathExtension.lowercased() == "icon" {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: res.path, isDirectory: &isDir), isDir.boolValue {
          continue
        }
      }
      let components = res.pathComponents
      let dest: URL
      if let lprojIdx = components.lastIndex(where: { $0.lowercased().hasSuffix(".lproj") }) {
        let lprojName = components[lprojIdx]
        expectedResourceTopNames.insert(lprojName)
        var targetURL = resourcesDir
        var relParts: [String] = []
        for comp in components[lprojIdx...] {
          targetURL = targetURL.appendingPathComponent(comp)
          if comp != lprojName {
            relParts.append(comp)
          }
        }
        expectedLprojFiles[lprojName, default: []].insert(relParts.joined(separator: "/"))
        try fm.createDirectory(
          at: targetURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        dest = targetURL
      } else {
        let name = res.lastPathComponent
        expectedResourceTopNames.insert(name)
        dest = resourcesDir.appendingPathComponent(name)
      }
      var resIsDir: ObjCBool = false
      if fm.fileExists(atPath: res.path, isDirectory: &resIsDir), resIsDir.boolValue {
        try IncrementalFileWriter.syncDirectory(from: res, to: dest)
      } else {
        try IncrementalFileWriter.copyFileIfChanged(from: res, to: dest)
      }
    }
    if let existingRes = try? fm.contentsOfDirectory(atPath: resourcesDir.path) {
      for name in existingRes where !expectedResourceTopNames.contains(name) {
        try? fm.removeItem(at: resourcesDir.appendingPathComponent(name))
      }
    }
    for (lprojName, keptRelPaths) in expectedLprojFiles {
      IncrementalFileWriter.pruneStaleEntries(
        under: resourcesDir.appendingPathComponent(lprojName),
        keeping: keptRelPaths
      )
    }

    // 2. Synthesize Info.plist
    let infoPlistURL = resourcesDir.appendingPathComponent("Info.plist")
    let infoPlistDict = buildInfoPlistDictionary(target: target)
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: infoPlistDict, format: .xml, options: 0)
    try IncrementalFileWriter.writeIfChanged(data: plistData, to: infoPlistURL)

    // 3. Compile AppIcon.appiconset -> Windows .ico & Linux PNG icons
    let iconEntries = collectAppIconPNGs(target: target)
    var windowsIconURL: URL?
    if let icoData = ICOEncoder.encode(pngEntries: iconEntries) {
      let resIco = resourcesDir.appendingPathComponent("AppIcon.ico")
      let metaIco = winMetaDir.appendingPathComponent("AppIcon.ico")
      try IncrementalFileWriter.writeIfChanged(data: icoData, to: resIco)
      try IncrementalFileWriter.writeIfChanged(data: icoData, to: metaIco)
      windowsIconURL = metaIco
    } else {
      try? fm.removeItem(at: resourcesDir.appendingPathComponent("AppIcon.ico"))
    }

    var linuxIconVariants: [(size: Int, url: URL)] = []
    if !iconEntries.isEmpty {
      var bySize: [Int: ICOEncoder.PNGEntry] = [:]
      for entry in iconEntries where entry.width == entry.height {
        bySize[entry.width] = entry
      }
      if bySize.isEmpty, let largest = iconEntries.max(by: { $0.width < $1.width }) {
        bySize[largest.width] = largest
      }
      let linuxIconsDir = stagingRoot.appendingPathComponent("LinuxIcons")
      try fm.createDirectory(at: linuxIconsDir, withIntermediateDirectories: true)
      for size in bySize.keys.sorted() {
        if let entry = bySize[size] {
          let pngURL = linuxIconsDir.appendingPathComponent("\(size).png")
          try IncrementalFileWriter.writeIfChanged(data: entry.data, to: pngURL)
          linuxIconVariants.append((size: size, url: pngURL))
        }
      }
      let preferredAppPNG =
        bySize[256] ?? bySize[128] ?? bySize[512] ?? bySize[bySize.keys.max() ?? 0]
      if let preferredAppPNG {
        try IncrementalFileWriter.writeIfChanged(
          data: preferredAppPNG.data,
          to: resourcesDir.appendingPathComponent("AppIcon.png")
        )
      }
    } else {
      try? fm.removeItem(at: resourcesDir.appendingPathComponent("AppIcon.png"))
    }

    // 4. Generate Windows manifest & resource script (.rc)
    let manifestURL = winMetaDir.appendingPathComponent("Application.manifest")
    try IncrementalFileWriter.writeIfChanged(
      text: generateWindowsManifest(target: target),
      to: manifestURL
    )

    let rcURL = winMetaDir.appendingPathComponent("AppResources.rc")
    try IncrementalFileWriter.writeIfChanged(
      text: generateWindowsRC(target: target, hasIcon: windowsIconURL != nil),
      to: rcURL
    )

    // 5. Synthesize GeneratedAssetSymbols.swift
    var generatedSymbolsURL: URL?
    if target.generateAssetSymbols {
      let (colors, images) = scanAssetSymbols(in: target.assetCatalogs, appIconName: target.appIconName)
      if !colors.isEmpty || !images.isEmpty {
        let swiftDir = stagingRoot.appendingPathComponent("GeneratedSwift")
        try fm.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        let outURL = swiftDir.appendingPathComponent("GeneratedAssetSymbols.swift")
        let source = renderGeneratedAssetSymbolsSwift(colors: colors, imageNames: images)
        try IncrementalFileWriter.writeIfChanged(text: source, to: outURL)
        generatedSymbolsURL = outURL
      }
    }

    let usesSQLite3 = project.inferredCrossSwiftModules.contains("SQLite3")
    return CompiledAssets(
      resourcesDirectory: resourcesDir,
      infoPlistURL: infoPlistURL,
      windowsIconURL: windowsIconURL,
      windowsResourceScriptURL: rcURL,
      windowsManifestURL: manifestURL,
      linuxIconVariants: linuxIconVariants,
      generatedSymbolsSwiftURL: generatedSymbolsURL,
      usesSQLite3: usesSQLite3
    )
  }

  public func buildInfoPlistDictionary(target: ResolvedTarget) -> [String: Any] {
    var dict: [String: Any] = [:]
    if let infoURL = target.infoPlistFile,
       let raw = try? OpenStepPlistParser.parse(fileAt: infoURL) as? [String: Any]
    {
      dict = raw
    }

    for (key, value) in target.infoPlistKeys {
      if key == "LSUIElement" {
        let lower = value.lowercased()
        dict[key] = (lower == "yes" || lower == "true" || lower == "1")
      } else {
        dict[key] = value
      }
    }

    if dict["CFBundleIdentifier"] == nil { dict["CFBundleIdentifier"] = target.bundleIdentifier }
    if dict["CFBundleName"] == nil { dict["CFBundleName"] = target.productName }
    if dict["CFBundleDisplayName"] == nil {
      dict["CFBundleDisplayName"] = target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName
    }
    if dict["CFBundleExecutable"] == nil { dict["CFBundleExecutable"] = target.executableName }
    if dict["CFBundleShortVersionString"] == nil {
      dict["CFBundleShortVersionString"] = target.marketingVersion
    }
    if dict["CFBundleVersion"] == nil { dict["CFBundleVersion"] = target.buildVersion }
    if dict["CFBundlePackageType"] == nil { dict["CFBundlePackageType"] = "APPL" }

    var expansionMap = target.buildSettings
    expansionMap["EXECUTABLE_NAME"] = target.executableName
    expansionMap["PRODUCT_NAME"] = target.productName
    expansionMap["PRODUCT_BUNDLE_IDENTIFIER"] = target.bundleIdentifier
    expansionMap["MARKETING_VERSION"] = target.marketingVersion
    expansionMap["CURRENT_PROJECT_VERSION"] = target.buildVersion

    func expandAny(_ value: Any) -> Any {
      if let s = value as? String {
        return XcodeProjectLoader.expandVariables(in: expansionMap.merging(["__VALUE__": s]) { _, r in r })["__VALUE__"] ?? s
      }
      if let arr = value as? [Any] {
        return arr.map(expandAny)
      }
      if let sub = value as? [String: Any] {
        return sub.mapValues(expandAny)
      }
      return value
    }

    return dict.mapValues(expandAny)
  }

  private func collectAppIconPNGs(target: ResolvedTarget) -> [ICODecoderCandidate] {
    let fm = FileManager.default
    var collected: [ICOEncoder.PNGEntry] = []

    for catalogURL in target.assetCatalogs {
      guard let enumerator = fm.enumerator(
        at: catalogURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }
      for case let url as URL in enumerator {
        if url.pathExtension.lowercased() == "appiconset" {
          let setName = url.deletingPathExtension().lastPathComponent
          if setName == target.appIconName || collected.isEmpty {
            let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "png" {
              if let data = try? Data(contentsOf: file),
                 let dims = ICOEncoder.readPNGDimensions(data: data)
              {
                collected.append(
                  ICOEncoder.PNGEntry(width: dims.width, height: dims.height, data: data))
              }
            }
          }
          enumerator.skipDescendants()
        }
      }
    }
    if !collected.isEmpty {
      return collected
    }

    var iconBundleCandidates: [URL] = []
    for res in target.otherResources where res.pathExtension.lowercased() == "icon" {
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: res.path, isDirectory: &isDir), isDir.boolValue {
        iconBundleCandidates.append(res)
      }
    }
    if let plistDir = target.infoPlistFile?.deletingLastPathComponent() {
      let siblingIcon = plistDir.appendingPathComponent("\(target.appIconName).icon")
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: siblingIcon.path, isDirectory: &isDir), isDir.boolValue,
         !iconBundleCandidates.contains(where: { $0.standardizedFileURL.path == siblingIcon.standardizedFileURL.path })
      {
        iconBundleCandidates.append(siblingIcon)
      }
    }
    let chosenIconBundle =
      iconBundleCandidates.first(where: {
        $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(target.appIconName) == .orderedSame
      }) ?? iconBundleCandidates.first
    if let chosenIconBundle {
      collected = IconComposerRenderer.renderIconBundle(at: chosenIconBundle)
    }
    return collected
  }

  private typealias ICODecoderCandidate = ICOEncoder.PNGEntry

  private func generateWindowsManifest(target: ResolvedTarget) -> String {
    let appID = escapeXML(target.bundleIdentifier)
    let version = normalizedFourPartVersion(
      marketingVersion: target.marketingVersion, buildVersion: target.buildVersion)
    let description = escapeXML(target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName)
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
      <assemblyIdentity version="\(version)" processorArchitecture="*" name="\(appID)" type="win32"/>
      <description>\(description)</description>
      <dependency>
        <dependentAssembly>
          <assemblyIdentity
            type="win32"
            name="Microsoft.Windows.Common-Controls"
            version="6.0.0.0"
            processorArchitecture="*"
            publicKeyToken="6595b64144ccf1df"
            language="*" />
        </dependentAssembly>
      </dependency>
      <application xmlns="urn:schemas-microsoft-com:asm.v3">
        <windowsSettings>
          <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
          <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>
          <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
        </windowsSettings>
      </application>
    </assembly>
    """
  }

  private func generateWindowsRC(target: ResolvedTarget, hasIcon: Bool) -> String {
    let numericTuple = normalizedFourPartVersion(
      marketingVersion: target.marketingVersion, buildVersion: target.buildVersion
    ).replacingOccurrences(of: ".", with: ",")
    let displayName = escapeRC(target.infoPlistKeys["CFBundleDisplayName"] ?? target.productName)
    let copyright = escapeRC(target.copyright ?? "")
    let versionStr = escapeRC(target.marketingVersion)
    let exeFile = escapeRC("\(target.executableName).exe")
    let internalName = escapeRC(target.executableName)

    var lines: [String] = ["#pragma code_page(65001)", ""]
    if hasIcon {
      lines.append("1 ICON \"AppIcon.ico\"")
    }
    lines.append("1 24 \"Application.manifest\"")
    lines.append("")
    lines.append("1 VERSIONINFO")
    lines.append("FILEVERSION \(numericTuple)")
    lines.append("PRODUCTVERSION \(numericTuple)")
    lines.append("FILEFLAGSMASK 0x3fL")
    lines.append("FILEFLAGS 0x0L")
    lines.append("FILEOS 0x40004L")
    lines.append("FILETYPE 0x1L")
    lines.append("FILESUBTYPE 0x0L")
    lines.append("BEGIN")
    lines.append("  BLOCK \"StringFileInfo\"")
    lines.append("  BEGIN")
    lines.append("    BLOCK \"040904B0\"")
    lines.append("    BEGIN")
    lines.append("      VALUE \"FileDescription\", \"\(displayName)\\0\"")
    lines.append("      VALUE \"FileVersion\", \"\(versionStr)\\0\"")
    lines.append("      VALUE \"InternalName\", \"\(internalName)\\0\"")
    lines.append("      VALUE \"LegalCopyright\", \"\(copyright)\\0\"")
    lines.append("      VALUE \"OriginalFilename\", \"\(exeFile)\\0\"")
    lines.append("      VALUE \"ProductName\", \"\(displayName)\\0\"")
    lines.append("      VALUE \"ProductVersion\", \"\(versionStr)\\0\"")
    lines.append("    END")
    lines.append("  END")
    lines.append("  BLOCK \"VarFileInfo\"")
    lines.append("  BEGIN")
    lines.append("    VALUE \"Translation\", 0x0409, 1200")
    lines.append("  END")
    lines.append("END")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  private func scanAssetSymbols(
    in catalogs: [URL],
    appIconName: String
  ) -> (colors: [ResolvedColorAsset], images: [String]) {
    let fm = FileManager.default
    var colors: [ResolvedColorAsset] = []
    var images: [String] = []
    var seenColors = Set<String>()
    var seenImages = Set<String>()

    for catalogURL in catalogs {
      guard let enumerator = fm.enumerator(
        at: catalogURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }
      for case let url as URL in enumerator {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        if ext == "colorset" {
          if seenColors.insert(name).inserted {
            colors.append(parseColorSet(named: name, at: url))
          }
          enumerator.skipDescendants()
        } else if ext == "imageset" {
          if name != appIconName && seenImages.insert(name).inserted { images.append(name) }
          enumerator.skipDescendants()
        } else if ext == "appiconset" {
          enumerator.skipDescendants()
        }
      }
    }
    return (colors.sorted { $0.name < $1.name }, images.sorted())
  }

  private func parseColorSet(named name: String, at colorSetURL: URL) -> ResolvedColorAsset {
    let fallback = ResolvedColorAsset.RGBA(r: 0.0, g: 0.478, b: 1.0, a: 1.0)
    let contentsURL = colorSetURL.appendingPathComponent("Contents.json")
    guard let data = try? Data(contentsOf: contentsURL),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let entries = root["colors"] as? [[String: Any]]
    else {
      return ResolvedColorAsset(name: name, light: fallback, dark: fallback)
    }

    func parseComponent(_ raw: Any?) -> Double? {
      if let d = raw as? Double {
        let normalized = d > 1.0 ? d / 255.0 : d
        return min(max(normalized, 0.0), 1.0)
      }
      if let n = raw as? NSNumber {
        let d = n.doubleValue
        let normalized = d > 1.0 ? d / 255.0 : d
        return min(max(normalized, 0.0), 1.0)
      }
      if let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
        let lower = s.lowercased()
        if lower.hasPrefix("0x"), let hexVal = UInt64(lower.dropFirst(2), radix: 16) {
          return min(max(Double(hexVal) / 255.0, 0.0), 1.0)
        }
        if s.contains("."), let d = Double(s) {
          return min(max(d, 0.0), 1.0)
        }
        if let d = Double(s) {
          let normalized = d > 1.0 ? d / 255.0 : d
          return min(max(normalized, 0.0), 1.0)
        }
      }
      return nil
    }

    var lightColor: ResolvedColorAsset.RGBA?
    var darkColor: ResolvedColorAsset.RGBA?

    for entry in entries {
      guard let colorObj = entry["color"] as? [String: Any],
            let comps = colorObj["components"] as? [String: Any],
            let r = parseComponent(comps["red"]),
            let g = parseComponent(comps["green"]),
            let b = parseComponent(comps["blue"])
      else {
        continue
      }
      let a = parseComponent(comps["alpha"]) ?? 1.0
      let rgba = ResolvedColorAsset.RGBA(r: r, g: g, b: b, a: a)

      let appearances = entry["appearances"] as? [[String: Any]] ?? []
      let isDark = appearances.contains { item in
        (item["value"] as? String)?.lowercased() == "dark"
      }
      let isLightExplicit = appearances.contains { item in
        (item["value"] as? String)?.lowercased() == "light"
      }
      if isDark {
        if darkColor == nil { darkColor = rgba }
      } else if isLightExplicit || appearances.isEmpty {
        if lightColor == nil { lightColor = rgba }
      }
    }

    let resolvedLight = lightColor ?? darkColor ?? fallback
    let resolvedDark = darkColor ?? resolvedLight
    return ResolvedColorAsset(name: name, light: resolvedLight, dark: resolvedDark)
  }

  public func renderGeneratedAssetSymbolsSwift(
    colors: [ResolvedColorAsset],
    imageNames: [String]
  ) -> String {
    var out: [String] = [
      "// AUTO-GENERATED BY CrossXcodeBuild. DO NOT EDIT.",
      "import Foundation",
      "",
      "#if CROSS_SWIFTUI_HARMONY || os(Android)",
      "private let _crossSwiftAssetBundle: Bundle? = nil",
      "#else",
      "private let _crossSwiftAssetBundle: Bundle? = .main",
      "#endif",
      "",
    ]

    if !colors.isEmpty {
      out += [
        "struct ColorResource: Hashable, @unchecked Sendable {",
        "  let name: String",
        "  let bundle: Bundle?",
        "  let lightRed: Double",
        "  let lightGreen: Double",
        "  let lightBlue: Double",
        "  let lightAlpha: Double",
        "  let darkRed: Double",
        "  let darkGreen: Double",
        "  let darkBlue: Double",
        "  let darkAlpha: Double",
        "",
        "  init(",
        "    name: String,",
        "    bundle: Bundle? = nil,",
        "    lightRed: Double,",
        "    lightGreen: Double,",
        "    lightBlue: Double,",
        "    lightAlpha: Double,",
        "    darkRed: Double,",
        "    darkGreen: Double,",
        "    darkBlue: Double,",
        "    darkAlpha: Double",
        "  ) {",
        "    self.name = name",
        "    self.bundle = bundle",
        "    self.lightRed = lightRed",
        "    self.lightGreen = lightGreen",
        "    self.lightBlue = lightBlue",
        "    self.lightAlpha = lightAlpha",
        "    self.darkRed = darkRed",
        "    self.darkGreen = darkGreen",
        "    self.darkBlue = darkBlue",
        "    self.darkAlpha = darkAlpha",
        "  }",
        "}",
        "",
        "extension ColorResource {",
      ]
      for item in colors {
        let ident = Self.swiftIdentifier(from: item.name)
        out.append(
          "  static let \(ident) = ColorResource(name: \"\(escapeSwiftString(item.name))\", bundle: _crossSwiftAssetBundle, lightRed: \(item.light.r), lightGreen: \(item.light.g), lightBlue: \(item.light.b), lightAlpha: \(item.light.a), darkRed: \(item.dark.r), darkGreen: \(item.dark.g), darkBlue: \(item.dark.b), darkAlpha: \(item.dark.a))"
        )
      }
      out.append("}")
      out.append("")
    }

    if !imageNames.isEmpty {
      out += [
        "struct ImageResource: Hashable, @unchecked Sendable {",
        "  let name: String",
        "  let bundle: Bundle?",
        "",
        "  init(name: String, bundle: Bundle? = nil) {",
        "    self.name = name",
        "    self.bundle = bundle",
        "  }",
        "}",
        "",
        "extension ImageResource {",
      ]
      for raw in imageNames {
        let ident = Self.swiftIdentifier(from: raw)
        out.append("  static let \(ident) = ImageResource(name: \"\(escapeSwiftString(raw))\", bundle: _crossSwiftAssetBundle)")
      }
      out.append("}")
      out.append("")
    }

    out.append("#if canImport(SwiftUI)")
    out.append("import SwiftUI")
    out.append("")

    if !colors.isEmpty {
      out += [
        "extension Color {",
        "  init(_ resource: ColorResource) {",
        "    self.init { scheme in",
        "      scheme == .dark",
        "        ? (resource.darkRed, resource.darkGreen, resource.darkBlue, resource.darkAlpha)",
        "        : (resource.lightRed, resource.lightGreen, resource.lightBlue, resource.lightAlpha)",
        "    }",
        "  }",
        "}",
        "",
        "extension ShapeStyle where Self == Color {",
      ]
      for item in colors {
        let ident = Self.swiftIdentifier(from: item.name)
        out.append("  static var \(ident): Color { Color(.\(ident)) }")
      }
      out.append("}")
      out.append("")
    }

    if !imageNames.isEmpty {
      out += [
        "extension Image {",
        "  init(_ resource: ImageResource) {",
        "    self.init(resource.name, bundle: resource.bundle)",
        "  }",
        "",
      ]
      for raw in imageNames {
        let ident = Self.swiftIdentifier(from: raw)
        out.append("  static var \(ident): Image { Image(.\(ident)) }")
      }
      out.append("}")
      out.append("")
    }

    out.append("#endif")
    out.append("")

    if !colors.isEmpty || !imageNames.isEmpty {
      out.append("#if canImport(AppKit)")
      out.append("import AppKit")
      out.append("")
      if !colors.isEmpty {
        out += [
          "extension NSColor {",
          "  convenience init(resource: ColorResource) {",
          "    self.init(name: resource.name) { appearance in",
          "      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua",
          "      return NSColor(",
          "        srgbRed: isDark ? resource.darkRed : resource.lightRed,",
          "        green: isDark ? resource.darkGreen : resource.lightGreen,",
          "        blue: isDark ? resource.darkBlue : resource.lightBlue,",
          "        alpha: isDark ? resource.darkAlpha : resource.lightAlpha",
          "      )",
          "    }",
          "  }",
          "}",
          "",
        ]
      }
      if !imageNames.isEmpty {
        out += [
          "extension NSImage {",
          "  convenience init(resource: ImageResource) {",
          "    if let resolved = Self.resolveAssetPath(named: resource.name),",
          "       FileManager.default.fileExists(atPath: resolved),",
          "       NSImage(contentsOfFile: resolved) != nil",
          "    {",
          "      self.init(contentsOfFile: resolved)!",
          "    } else {",
          "      self.init(size: .zero)",
          "    }",
          "  }",
          "}",
          "",
        ]
      }
      out.append("#endif")
      out.append("")

      out.append("#if canImport(UIKit)")
      out.append("import UIKit")
      out.append("#if !os(macOS) && canImport(CrossSwiftUI)")
      out.append("import CrossSwiftUI")
      out.append("#endif")
      out.append("")
      if !colors.isEmpty {
        out += [
          "extension UIColor {",
          "  convenience init(resource: ColorResource) {",
          "    #if !os(macOS) && canImport(CrossSwiftUI)",
          "      _installCrossSwiftUIBootstrap()",
          "    #endif",
          "    self.init { traits in",
          "      let isDark = traits.userInterfaceStyle == .dark",
          "      return UIColor(",
          "        red: isDark ? resource.darkRed : resource.lightRed,",
          "        green: isDark ? resource.darkGreen : resource.lightGreen,",
          "        blue: isDark ? resource.darkBlue : resource.lightBlue,",
          "        alpha: isDark ? resource.darkAlpha : resource.lightAlpha",
          "      )",
          "    }",
          "  }",
          "}",
          "",
        ]
      }
      if !imageNames.isEmpty {
        out += [
          "extension UIImage {",
          "  convenience init(resource: ImageResource) {",
          "    #if !os(macOS) && canImport(CrossSwiftUI)",
          "      _installCrossSwiftUIBootstrap()",
          "    #endif",
          "    #if !os(macOS) && canImport(CrossUIKit)",
          "      if let resolved = Self.resolveAssetPath(named: resource.name, in: resource.bundle),",
          "         FileManager.default.fileExists(atPath: resolved),",
          "         UIImage(contentsOfFile: resolved) != nil",
          "      {",
          "        self.init(contentsOfFile: resolved)!",
          "      } else {",
          "        self.init()",
          "      }",
          "    #else",
          "      self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!",
          "    #endif",
          "  }",
          "}",
          "",
        ]
      }
      out.append("#endif")
      out.append("")
    }

    return out.joined(separator: "\n")
  }

  public static func swiftIdentifier(from assetName: String) -> String {
    let tokens = assetName.split { ch in
      !(ch.isLetter || ch.isNumber)
    }.map(String.init)
    guard !tokens.isEmpty else { return "_asset" }

    var parts: [String] = []
    for (idx, token) in tokens.enumerated() {
      if idx == 0 {
        let chars = Array(token)
        var prefixCount = 0
        while prefixCount < chars.count && chars[prefixCount].isUppercase {
          prefixCount += 1
        }
        if prefixCount == 0 {
          parts.append(token)
        } else if prefixCount == 1 {
          parts.append(chars[0].lowercased() + String(chars.dropFirst()))
        } else if prefixCount == chars.count {
          parts.append(token.lowercased())
        } else {
          let lowered = String(chars[0..<(prefixCount - 1)]).lowercased()
          parts.append(lowered + String(chars[(prefixCount - 1)...]))
        }
      } else {
        parts.append(token.prefix(1).uppercased() + token.dropFirst())
      }
    }

    var ident = parts.joined()
    if let first = ident.first, first.isNumber {
      ident = "_" + ident
    }
    let keywords: Set<String> = [
      "class", "struct", "enum", "protocol", "extension", "func", "var", "let", "default",
      "switch", "case", "import", "return", "true", "false", "nil", "self", "Self", "in",
      "for", "while", "if", "else", "as", "is", "try", "catch", "throw", "public", "private",
      "internal", "static", "init", "deinit", "typealias", "associatedtype", "operator",
    ]
    if keywords.contains(ident) {
      return "`\(ident)`"
    }
    return ident
  }

  private func normalizedFourPartVersion(marketingVersion: String, buildVersion: String) -> String {
    let rawParts = marketingVersion
      .split(separator: ".")
      .map { $0.prefix(while: { $0.isNumber }) }
      .compactMap { Int($0) }
    let major = rawParts.count > 0 ? rawParts[0] : 1
    let minor = rawParts.count > 1 ? rawParts[1] : 0
    let patch = rawParts.count > 2 ? rawParts[2] : 0
    let buildNum = Int(buildVersion.prefix(while: { $0.isNumber })) ?? (rawParts.count > 3 ? rawParts[3] : 0)
    return "\(major).\(minor).\(patch).\(buildNum)"
  }

  private func escapeXML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private func escapeRC(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func escapeSwiftString(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

enum IconComposerRenderer {
  struct RGBA {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
  }

  static func renderIconBundle(
    at bundleURL: URL,
    sizes: [Int] = [16, 32, 48, 64, 128, 256]
  ) -> [ICOEncoder.PNGEntry] {
    let fm = FileManager.default
    let iconJSONURL = bundleURL.appendingPathComponent("icon.json")
    let assetsDir = bundleURL.appendingPathComponent("Assets")
    let json =
      (try? Data(contentsOf: iconJSONURL))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      ?? [:]

    let (bgTop, bgBottom) = parseBackgroundFill(json["fill"])

    struct LayerSpec {
      let vector: VectorImage
      let scale: Double
      let offsetX: Double
      let offsetY: Double
      let shadowOpacity: Double
    }
    var layerSpecs: [LayerSpec] = []
    if let groups = json["groups"] as? [[String: Any]] {
      for group in groups {
        let shadowOpacity: Double
        if let shadow = group["shadow"] as? [String: Any],
           (shadow["kind"] as? String) != "none"
        {
          shadowOpacity = (shadow["opacity"] as? Double) ?? 0.45
        } else {
          shadowOpacity = 0.0
        }
        for layer in (group["layers"] as? [[String: Any]]) ?? [] {
          guard let imageName = layer["image-name"] as? String else { continue }
          let fileURL = assetsDir.appendingPathComponent(imageName)
          guard fm.fileExists(atPath: fileURL.path) else { continue }
          if fileURL.pathExtension.lowercased() == "png",
             let pngData = try? Data(contentsOf: fileURL),
             let dims = ICOEncoder.readPNGDimensions(data: pngData)
          {
            return [ICOEncoder.PNGEntry(width: dims.width, height: dims.height, data: pngData)]
          }
          if let vec = VectorImage.load(fileURL.path), !vec.layers.isEmpty {
            let pos = layer["position"] as? [String: Any]
            let userScale = (pos?["scale"] as? Double) ?? 1.0
            let trans = (pos?["translation-in-points"] as? [Double]) ?? [0, 0]
            let tx = trans.count > 0 ? trans[0] / 1024.0 : 0.0
            let ty = trans.count > 1 ? trans[1] / 1024.0 : 0.0
            layerSpecs.append(
              LayerSpec(
                vector: vec,
                scale: userScale,
                offsetX: tx,
                offsetY: ty,
                shadowOpacity: shadowOpacity
              ))
          }
        }
      }
    }

    if layerSpecs.isEmpty,
       let files = try? fm.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil)
    {
      for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        if file.pathExtension.lowercased() == "svg", let vec = VectorImage.load(file.path) {
          layerSpecs.append(
            LayerSpec(vector: vec, scale: 1.0, offsetX: 0, offsetY: 0, shadowOpacity: 0.4))
        } else if file.pathExtension.lowercased() == "png",
                  let data = try? Data(contentsOf: file),
                  let dims = ICOEncoder.readPNGDimensions(data: data)
        {
          return [ICOEncoder.PNGEntry(width: dims.width, height: dims.height, data: data)]
        }
      }
    }
    guard !layerSpecs.isEmpty else { return [] }

    return sizes.map { size in
      let rgbaBytes = rasterizeIcon(
        size: size,
        bgTop: bgTop,
        bgBottom: bgBottom,
        layers: layerSpecs.map { ($0.vector, $0.scale, $0.offsetX, $0.offsetY, $0.shadowOpacity) }
      )
      let pngData = encodeUncompressedPNG(width: size, height: size, rgba: rgbaBytes)
      return ICOEncoder.PNGEntry(width: size, height: size, data: pngData)
    }
  }

  private static func parseBackgroundFill(_ raw: Any?) -> (top: RGBA, bottom: RGBA) {
    let defaultTop = RGBA(r: 0.165, g: 0.165, b: 0.205, a: 1.0)
    let defaultBottom = RGBA(r: 0.082, g: 0.082, b: 0.108, a: 1.0)
    guard let dict = raw as? [String: Any] else {
      return (defaultTop, defaultBottom)
    }
    if let solid = dict["solid"] as? String, let c = parseIconColor(solid) {
      return (c, c)
    }
    if let stops = dict["linear-gradient"] as? [String], stops.count >= 2,
       let c0 = parseIconColor(stops.first!),
       let c1 = parseIconColor(stops.last!)
    {
      return (c0, c1)
    }
    return (defaultTop, defaultBottom)
  }

  private static func parseIconColor(_ spec: String) -> RGBA? {
    let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("#") {
      let hex = String(trimmed.dropFirst())
      if hex.count == 6, let v = UInt32(hex, radix: 16) {
        return RGBA(
          r: Double((v >> 16) & 0xFF) / 255.0,
          g: Double((v >> 8) & 0xFF) / 255.0,
          b: Double(v & 0xFF) / 255.0,
          a: 1.0
        )
      }
    }
    if let colon = trimmed.firstIndex(of: ":") {
      let comps = trimmed[trimmed.index(after: colon)...]
        .split(separator: ",")
        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      if comps.count >= 3 {
        return RGBA(
          r: min(max(comps[0], 0), 1),
          g: min(max(comps[1], 0), 1),
          b: min(max(comps[2], 0), 1),
          a: comps.count >= 4 ? min(max(comps[3], 0), 1) : 1.0
        )
      }
    }
    return nil
  }

  private struct Edge {
    let x0: Double
    let y0: Double
    let x1: Double
    let y1: Double
  }

  private static func flattenPath(
    _ path: Path,
    transform: (Double, Double) -> (Double, Double)
  ) -> [Edge] {
    var edges: [Edge] = []
    let cmds = path.commands
    var i = 0
    var cur = (0.0, 0.0)
    var subStart = (0.0, 0.0)

    func addSeg(_ a: (Double, Double), _ b: (Double, Double)) {
      if abs(a.1 - b.1) > 1e-9 {
        edges.append(Edge(x0: a.0, y0: a.1, x1: b.0, y1: b.1))
      }
    }

    while i < cmds.count {
      let op = Int(cmds[i])
      i += 1
      switch op {
      case 0:
        guard i + 1 < cmds.count else { break }
        cur = transform(cmds[i], cmds[i + 1])
        subStart = cur
        i += 2
      case 1:
        guard i + 1 < cmds.count else { break }
        let next = transform(cmds[i], cmds[i + 1])
        addSeg(cur, next)
        cur = next
        i += 2
      case 2:
        guard i + 5 < cmds.count else { break }
        let c1 = transform(cmds[i], cmds[i + 1])
        let c2 = transform(cmds[i + 2], cmds[i + 3])
        let end = transform(cmds[i + 4], cmds[i + 5])
        let p0 = cur
        let steps = 16
        var prev = p0
        for s in 1...steps {
          let t = Double(s) / Double(steps)
          let mt = 1.0 - t
          let x =
            mt * mt * mt * p0.0
            + 3.0 * mt * mt * t * c1.0
            + 3.0 * mt * t * t * c2.0
            + t * t * t * end.0
          let y =
            mt * mt * mt * p0.1
            + 3.0 * mt * mt * t * c1.1
            + 3.0 * mt * t * t * c2.1
            + t * t * t * end.1
          let pt = (x, y)
          addSeg(prev, pt)
          prev = pt
        }
        cur = end
        i += 6
      case 3:
        addSeg(cur, subStart)
        cur = subStart
      default:
        break
      }
    }
    return edges
  }

  private static func isInsideNonZero(_ edges: [Edge], x: Double, y: Double) -> Bool {
    var winding = 0
    for e in edges {
      if e.y0 <= y {
        if e.y1 > y {
          let isLeft = (e.x1 - e.x0) * (y - e.y0) - (x - e.x0) * (e.y1 - e.y0)
          if isLeft > 0 { winding += 1 }
        }
      } else {
        if e.y1 <= y {
          let isLeft = (e.x1 - e.x0) * (y - e.y0) - (x - e.x0) * (e.y1 - e.y0)
          if isLeft < 0 { winding -= 1 }
        }
      }
    }
    return winding != 0
  }

  private static func rasterizeIcon(
    size: Int,
    bgTop: RGBA,
    bgBottom: RGBA,
    layers: [(vector: VectorImage, scale: Double, offsetX: Double, offsetY: Double, shadowOpacity: Double)]
  ) -> [UInt8] {
    let fSize = Double(size)
    let inset = size <= 20 ? 0.0 : fSize * 0.055
    let cardMin = inset
    let cardMax = fSize - inset
    let cardSize = cardMax - cardMin
    let cornerR = cardSize * 0.225
    let sub = 4
    let invSub2 = 1.0 / Double(sub * sub)

    func inRoundedRect(_ px: Double, _ py: Double) -> Bool {
      if px < cardMin || px > cardMax || py < cardMin || py > cardMax { return false }
      let innerMinX = cardMin + cornerR
      let innerMaxX = cardMax - cornerR
      let innerMinY = cardMin + cornerR
      let innerMaxY = cardMax - cornerR
      let dx: Double
      if px < innerMinX { dx = innerMinX - px }
      else if px > innerMaxX { dx = px - innerMaxX }
      else { dx = 0 }
      let dy: Double
      if py < innerMinY { dy = innerMinY - py }
      else if py > innerMaxY { dy = py - innerMaxY }
      else { dy = 0 }
      if dx == 0 || dy == 0 { return true }
      // Continuous squircle exponent (n = 4.4)
      let nx = dx / cornerR
      let ny = dy / cornerR
      return pow(nx, 4.4) + pow(ny, 4.4) <= 1.0
    }

    var pmR = [Double](repeating: 0, count: size * size)
    var pmG = [Double](repeating: 0, count: size * size)
    var pmB = [Double](repeating: 0, count: size * size)
    var pmA = [Double](repeating: 0, count: size * size)

    func blendPixel(idx: Int, sr: Double, sg: Double, sb: Double, sa: Double) {
      guard sa > 0 else { return }
      let inv = 1.0 - sa
      pmR[idx] = sr * sa + pmR[idx] * inv
      pmG[idx] = sg * sa + pmG[idx] * inv
      pmB[idx] = sb * sa + pmB[idx] * inv
      pmA[idx] = sa + pmA[idx] * inv
    }

    // 1. Squircle background + subtle top specular rim
    for y in 0..<size {
      let t = max(0, min(1, (Double(y) + 0.5 - cardMin) / max(1, cardSize)))
      let baseR = bgTop.r + (bgBottom.r - bgTop.r) * t
      let baseG = bgTop.g + (bgBottom.g - bgTop.g) * t
      let baseB = bgTop.b + (bgBottom.b - bgTop.b) * t
      let baseA = bgTop.a + (bgBottom.a - bgTop.a) * t
      for x in 0..<size {
        var hits = 0
        var rimHits = 0
        for sy in 0..<sub {
          let py = Double(y) + (Double(sy) + 0.5) / Double(sub)
          for sx in 0..<sub {
            let px = Double(x) + (Double(sx) + 0.5) / Double(sub)
            if inRoundedRect(px, py) {
              hits += 1
              if size >= 32 && !inRoundedRect(px, py - max(1.0, fSize * 0.012)) {
                rimHits += 1
              }
            }
          }
        }
        if hits > 0 {
          let cov = Double(hits) * invSub2 * baseA
          let idx = y * size + x
          blendPixel(idx: idx, sr: baseR, sg: baseG, sb: baseB, sa: cov)
          if rimHits > 0 {
            let rimAlpha = Double(rimHits) * invSub2 * 0.14
            blendPixel(idx: idx, sr: 1.0, sg: 1.0, sb: 1.0, sa: rimAlpha)
          }
        }
      }
    }

    // 2. Foreground vector layers + soft shadow
    for item in layers {
      let vb = item.vector.bounds
      guard vb.width > 0, vb.height > 0 else { continue }
      let glyphBox = cardSize * 0.66 * item.scale
      let scaleFactor = min(glyphBox / vb.width, glyphBox / vb.height)
      let drawW = vb.width * scaleFactor
      let drawH = vb.height * scaleFactor
      let originX = cardMin + (cardSize - drawW) * 0.5 + item.offsetX * cardSize
      let originY = cardMin + (cardSize - drawH) * 0.5 + item.offsetY * cardSize

      for vLayer in item.vector.layers {
        guard let fill = vLayer.fill, fill.opacity > 0 else { continue }
        let edges = flattenPath(vLayer.path) { vx, vy in
          (originX + (vx - vb.minX) * scaleFactor, originY + (vy - vb.minY) * scaleFactor)
        }
        guard !edges.isEmpty else { continue }

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for e in edges {
          minX = min(minX, min(e.x0, e.x1))
          minY = min(minY, min(e.y0, e.y1))
          maxX = max(maxX, max(e.x0, e.x1))
          maxY = max(maxY, max(e.y0, e.y1))
        }

        if item.shadowOpacity > 0 && size >= 24 {
          let shOffsetY = max(1.0, fSize * 0.03)
          let y0 = max(0, Int(floor(minY + shOffsetY)) - 1)
          let y1 = min(size - 1, Int(ceil(maxY + shOffsetY)) + 1)
          let x0 = max(0, Int(floor(minX)) - 1)
          let x1 = min(size - 1, Int(ceil(maxX)) + 1)
          if x0 <= x1 && y0 <= y1 {
            for y in y0...y1 {
              for x in x0...x1 {
                var shHits = 0
                for sy in 0..<2 {
                  let py = Double(y) + (Double(sy) + 0.5) * 0.5 - shOffsetY
                  for sx in 0..<2 {
                    let px = Double(x) + (Double(sx) + 0.5) * 0.5
                    if inRoundedRect(Double(x) + 0.5, Double(y) + 0.5) && isInsideNonZero(edges, x: px, y: py) {
                      shHits += 1
                    }
                  }
                }
                if shHits > 0 {
                  let sa = Double(shHits) * 0.25 * item.shadowOpacity * 0.45
                  blendPixel(idx: y * size + x, sr: 0, sg: 0, sb: 0, sa: sa)
                }
              }
            }
          }
        }

        let py0 = max(0, Int(floor(minY)))
        let py1 = min(size - 1, Int(ceil(maxY)))
        let px0 = max(0, Int(floor(minX)))
        let px1 = min(size - 1, Int(ceil(maxX)))
        guard px0 <= px1, py0 <= py1 else { continue }
        for y in py0...py1 {
          for x in px0...px1 {
            var hits = 0
            for sy in 0..<sub {
              let py = Double(y) + (Double(sy) + 0.5) / Double(sub)
              for sx in 0..<sub {
                let px = Double(x) + (Double(sx) + 0.5) / Double(sub)
                if inRoundedRect(px, py) && isInsideNonZero(edges, x: px, y: py) {
                  hits += 1
                }
              }
            }
            if hits > 0 {
              let cov = Double(hits) * invSub2 * fill.opacity
              blendPixel(idx: y * size + x, sr: fill.red, sg: fill.green, sb: fill.blue, sa: cov)
            }
          }
        }
      }
    }

    var out = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
      let a = min(1.0, max(0.0, pmA[i]))
      if a > 1e-6 {
        let r = min(1.0, max(0.0, pmR[i] / a))
        let g = min(1.0, max(0.0, pmG[i] / a))
        let b = min(1.0, max(0.0, pmB[i] / a))
        out[i * 4 + 0] = UInt8((r * 255.0).rounded())
        out[i * 4 + 1] = UInt8((g * 255.0).rounded())
        out[i * 4 + 2] = UInt8((b * 255.0).rounded())
        out[i * 4 + 3] = UInt8((a * 255.0).rounded())
      }
    }
    return out
  }

  static func encodeUncompressedPNG(width: Int, height: Int, rgba: [UInt8]) -> Data {
    var rawScanlines = [UInt8]()
    rawScanlines.reserveCapacity(height * (1 + width * 4))
    for y in 0..<height {
      rawScanlines.append(0) // filter type 0 (None)
      let start = y * width * 4
      rawScanlines.append(contentsOf: rgba[start..<(start + width * 4)])
    }

    // Wrap rawScanlines in valid zlib stream with stored (BTYPE=00) DEFLATE blocks
    var zlib = [UInt8]()
    zlib.reserveCapacity(rawScanlines.count + (rawScanlines.count / 65535 + 2) * 5 + 6)
    zlib.append(0x78)
    zlib.append(0x01)
    var offset = 0
    let total = rawScanlines.count
    while true {
      let chunkLen = min(65535, total - offset)
      let isFinal = (offset + chunkLen >= total)
      zlib.append(isFinal ? 0x01 : 0x00)
      let len16 = UInt16(chunkLen)
      let nlen16 = ~len16
      zlib.append(UInt8(len16 & 0xFF))
      zlib.append(UInt8(len16 >> 8))
      zlib.append(UInt8(nlen16 & 0xFF))
      zlib.append(UInt8(nlen16 >> 8))
      if chunkLen > 0 {
        zlib.append(contentsOf: rawScanlines[offset..<(offset + chunkLen)])
      }
      offset += chunkLen
      if isFinal { break }
    }
    let adler = adler32(rawScanlines)
    zlib.append(UInt8((adler >> 24) & 0xFF))
    zlib.append(UInt8((adler >> 16) & 0xFF))
    zlib.append(UInt8((adler >> 8) & 0xFF))
    zlib.append(UInt8(adler & 0xFF))

    var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    func appendChunk(_ type: [UInt8], _ payload: [UInt8]) {
      var lenBE = UInt32(payload.count).bigEndian
      withUnsafeBytes(of: &lenBE) { out.append(contentsOf: $0) }
      out.append(contentsOf: type)
      out.append(contentsOf: payload)
      var crcInput = type
      crcInput.append(contentsOf: payload)
      var crcBE = crc32(crcInput).bigEndian
      withUnsafeBytes(of: &crcBE) { out.append(contentsOf: $0) }
    }

    var ihdr = [UInt8]()
    for v in [UInt32(width), UInt32(height)] {
      ihdr.append(UInt8((v >> 24) & 0xFF))
      ihdr.append(UInt8((v >> 16) & 0xFF))
      ihdr.append(UInt8((v >> 8) & 0xFF))
      ihdr.append(UInt8(v & 0xFF))
    }
    ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit RGBA
    appendChunk([0x49, 0x48, 0x44, 0x52], ihdr)
    appendChunk([0x49, 0x44, 0x41, 0x54], zlib)
    appendChunk([0x49, 0x45, 0x4E, 0x44], [])
    return out
  }

  private static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var s1: UInt32 = 1
    var s2: UInt32 = 0
    for b in bytes {
      s1 = (s1 + UInt32(b)) % 65521
      s2 = (s2 + s1) % 65521
    }
    return (s2 << 16) | s1
  }

  private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
    }
    return c
  }

  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var c: UInt32 = 0xFFFFFFFF
    for b in bytes {
      let idx = Int((c ^ UInt32(b)) & 0xFF)
      c = crcTable[idx] ^ (c >> 8)
    }
    return c ^ 0xFFFFFFFF
  }
}
