import Foundation

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
    if fm.fileExists(atPath: resourcesDir.path) {
      try fm.removeItem(at: resourcesDir)
    }
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: winMetaDir, withIntermediateDirectories: true)

    let target = project.mainTarget

    // 1. Copy *.xcassets, *.xcstrings, and other resource files into Resources/
    for xcassets in target.assetCatalogs {
      let dest = resourcesDir.appendingPathComponent(xcassets.lastPathComponent)
      if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
      try fm.copyItem(at: xcassets, to: dest)
    }
    for xcstrings in target.stringCatalogs {
      let dest = resourcesDir.appendingPathComponent(xcstrings.lastPathComponent)
      if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
      try fm.copyItem(at: xcstrings, to: dest)
    }
    for res in target.otherResources {
      let components = res.pathComponents
      let dest: URL
      if let lprojIdx = components.lastIndex(where: { $0.lowercased().hasSuffix(".lproj") }) {
        var targetURL = resourcesDir
        for comp in components[lprojIdx...] {
          targetURL = targetURL.appendingPathComponent(comp)
        }
        try fm.createDirectory(
          at: targetURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        dest = targetURL
      } else {
        dest = resourcesDir.appendingPathComponent(res.lastPathComponent)
      }
      if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
      try fm.copyItem(at: res, to: dest)
    }

    // 2. Synthesize Info.plist
    let infoPlistURL = resourcesDir.appendingPathComponent("Info.plist")
    let infoPlistDict = buildInfoPlistDictionary(target: target)
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: infoPlistDict, format: .xml, options: 0)
    try plistData.write(to: infoPlistURL, options: .atomic)

    // 3. Compile AppIcon.appiconset -> Windows .ico & Linux PNG icons
    let iconEntries = collectAppIconPNGs(target: target)
    var windowsIconURL: URL?
    if let icoData = ICOEncoder.encode(pngEntries: iconEntries) {
      let resIco = resourcesDir.appendingPathComponent("AppIcon.ico")
      let metaIco = winMetaDir.appendingPathComponent("AppIcon.ico")
      try icoData.write(to: resIco, options: .atomic)
      try icoData.write(to: metaIco, options: .atomic)
      windowsIconURL = metaIco
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
          try entry.data.write(to: pngURL, options: .atomic)
          linuxIconVariants.append((size: size, url: pngURL))
        }
      }
      let preferredAppPNG =
        bySize[256] ?? bySize[128] ?? bySize[512] ?? bySize[bySize.keys.max() ?? 0]
      if let preferredAppPNG {
        try preferredAppPNG.data.write(
          to: resourcesDir.appendingPathComponent("AppIcon.png"), options: .atomic)
      }
    }

    // 4. Generate Windows manifest & resource script (.rc)
    let manifestURL = winMetaDir.appendingPathComponent("Application.manifest")
    try generateWindowsManifest(target: target).write(
      to: manifestURL, atomically: true, encoding: .utf8)

    let rcURL = winMetaDir.appendingPathComponent("AppResources.rc")
    try generateWindowsRC(
      target: target,
      hasIcon: windowsIconURL != nil
    ).write(to: rcURL, atomically: true, encoding: .utf8)

    // 5. Synthesize GeneratedAssetSymbols.swift
    var generatedSymbolsURL: URL?
    if target.generateAssetSymbols {
      let (colors, images) = scanAssetSymbols(in: target.assetCatalogs, appIconName: target.appIconName)
      if !colors.isEmpty || !images.isEmpty {
        let swiftDir = stagingRoot.appendingPathComponent("GeneratedSwift")
        try fm.createDirectory(at: swiftDir, withIntermediateDirectories: true)
        let outURL = swiftDir.appendingPathComponent("GeneratedAssetSymbols.swift")
        let source = renderGeneratedAssetSymbolsSwift(colors: colors, imageNames: images)
        try source.write(to: outURL, atomically: true, encoding: .utf8)
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
          "  static let \(ident) = ColorResource(name: \"\(escapeSwiftString(item.name))\", bundle: .main, lightRed: \(item.light.r), lightGreen: \(item.light.g), lightBlue: \(item.light.b), lightAlpha: \(item.light.a), darkRed: \(item.dark.r), darkGreen: \(item.dark.g), darkBlue: \(item.dark.b), darkAlpha: \(item.dark.a))"
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
        out.append("  static let \(ident) = ImageResource(name: \"\(escapeSwiftString(raw))\", bundle: .main)")
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
