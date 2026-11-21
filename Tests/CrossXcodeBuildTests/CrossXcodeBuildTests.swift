import Foundation
import XCTest

@testable import CrossXcodeBuild

final class CrossXcodeBuildTests: XCTestCase {
  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testOpenStepPlistParserHandlesCommentsEscapesAndNestedStructures() throws {
    let source = """
    // !$*UTF8*$!
    {
      archiveVersion = 1;
      /* block comment */
      objects = {
        AA01 /* Main.swift */ = {
          isa = PBXFileReference;
          path = "Sources/My\\"App\\nFile.swift";
          rawBytes = <0a 1b 2c>;
          list = (
            itemOne,
            "itemTwo",
          );
        };
      };
      rootObject = AA01;
    }
    """
    let parsed = try OpenStepPlistParser.parse(data: Data(source.utf8))
    let root = try XCTUnwrap(parsed as? [String: Any])
    XCTAssertEqual(root["archiveVersion"] as? String, "1")
    XCTAssertEqual(root["rootObject"] as? String, "AA01")

    let objects = try XCTUnwrap(root["objects"] as? [String: Any])
    let entry = try XCTUnwrap(objects["AA01"] as? [String: Any])
    XCTAssertEqual(entry["isa"] as? String, "PBXFileReference")
    XCTAssertEqual(entry["path"] as? String, "Sources/My\"App\nFile.swift")
    XCTAssertEqual(entry["rawBytes"] as? Data, Data([0x0A, 0x1B, 0x2C]))
    let list = try XCTUnwrap(entry["list"] as? [String])
    XCTAssertEqual(list, ["itemOne", "itemTwo"])
  }

  func testLoadXcodeDemoSynchronizedProjectAndInferredModules() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let loader = XcodeProjectLoader()
    let resolved = try loader.load(from: demoProject, configuration: .release)

    XCTAssertEqual(resolved.mainTarget.name, "XcodeDemo")
    XCTAssertEqual(resolved.mainTarget.productName, "XcodeDemo")
    XCTAssertEqual(resolved.mainTarget.executableName, "XcodeDemo")
    XCTAssertEqual(resolved.mainTarget.bundleIdentifier, "dev.crossswift.xcodedemo")
    XCTAssertEqual(resolved.mainTarget.marketingVersion, "1.2.0")
    XCTAssertEqual(resolved.mainTarget.buildVersion, "1")
    XCTAssertEqual(
      resolved.mainTarget.categoryType,
      "public.app-category.developer-tools"
    )

    let swiftNames = Set(resolved.mainTarget.swiftSources.map(\.lastPathComponent))
    XCTAssertTrue(swiftNames.contains("XcodeDemoApp.swift"))
    XCTAssertTrue(swiftNames.contains("ContentView.swift"))
    XCTAssertEqual(resolved.mainTarget.assetCatalogs.map(\.lastPathComponent), ["Assets.xcassets"])
    XCTAssertEqual(resolved.mainTarget.stringCatalogs.map(\.lastPathComponent), ["Localizable.xcstrings"])

    XCTAssertTrue(resolved.inferredCrossSwiftModules.contains("SwiftUI"))
    XCTAssertTrue(resolved.inferredCrossSwiftModules.contains("AppKit"))
    XCTAssertTrue(resolved.inferredCrossSwiftModules.contains("CryptoKit"))
  }

  func testClassicPbxprojWithXCConfigRemotePackageAndDarwinGuardedSparkle() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossswift-classic-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    try """
    MARKETING_VERSION = 2.4.1
    PRODUCT_BUNDLE_IDENTIFIER = dev.example.classic
    """.write(to: tmp.appendingPathComponent("Release.xcconfig"), atomically: true, encoding: .utf8)

    let srcDir = tmp.appendingPathComponent("AppSources")
    try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
    try """
    import SwiftUI
    import SQLite3
    #if canImport(Sparkle) && os(macOS)
    import Sparkle
    #endif

    @main
    struct ClassicApp: App {
      var body: some Scene {
        WindowGroup("Classic") { Text("Hi") }
      }
    }
    """.write(to: srcDir.appendingPathComponent("AppMain.swift"), atomically: true, encoding: .utf8)

    let projDir = tmp.appendingPathComponent("Classic.xcodeproj")
    let swiftpmDir = projDir.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm")
    try FileManager.default.createDirectory(at: swiftpmDir, withIntermediateDirectories: true)

    try """
    {
      "pins": [
        {
          "identity": "sparkle",
          "location": "https://github.com/sparkle-project/Sparkle.git",
          "state": { "revision": "deadbeef", "version": "2.6.0" }
        },
        {
          "identity": "swift-log",
          "location": "https://github.com/apple/swift-log.git",
          "state": { "revision": "cafe1234", "version": "1.6.1" }
        }
      ],
      "version": 2
    }
    """.write(to: swiftpmDir.appendingPathComponent("Package.resolved"), atomically: true, encoding: .utf8)

    try """
    // !$*UTF8*$!
    {
      archiveVersion = 1;
      objectVersion = 56;
      objects = {
        F001 = { isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };
        F002 = { isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppMain.swift; sourceTree = "<group>"; };
        B001 = { isa = PBXBuildFile; fileRef = F002; };
        G002 = { isa = PBXGroup; children = ( F002 ); path = AppSources; sourceTree = "<group>"; };
        G001 = { isa = PBXGroup; children = ( F001, G002 ); sourceTree = "<group>"; };
        P001 = { isa = PBXSourcesBuildPhase; files = ( B001 ); };
        R001 = { isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle.git"; requirement = { kind = upToNextMajorVersion; minimumVersion = 2.6.0; }; };
        R002 = { isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/apple/swift-log.git"; requirement = { kind = upToNextMajorVersion; minimumVersion = 1.6.0; }; };
        D001 = { isa = XCSwiftPackageProductDependency; package = R001; productName = Sparkle; };
        D002 = { isa = XCSwiftPackageProductDependency; package = R002; productName = Logging; };
        C001 = { isa = XCBuildConfiguration; baseConfigurationReference = F001; buildSettings = { SWIFT_VERSION = 5.0; }; name = Release; };
        C002 = { isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = ClassicApp; }; name = Release; };
        L001 = { isa = XCConfigurationList; buildConfigurations = ( C001 ); defaultConfigurationName = Release; };
        L002 = { isa = XCConfigurationList; buildConfigurations = ( C002 ); defaultConfigurationName = Release; };
        T001 = {
          isa = PBXNativeTarget;
          buildConfigurationList = L002;
          buildPhases = ( P001 );
          name = ClassicApp;
          packageProductDependencies = ( D001, D002 );
          productName = ClassicApp;
          productType = "com.apple.product-type.application";
        };
        PRJ1 = {
          isa = PBXProject;
          buildConfigurationList = L001;
          mainGroup = G001;
          packageReferences = ( R001, R002 );
          targets = ( T001 );
        };
      };
      rootObject = PRJ1;
    }
    """.write(to: projDir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

    let resolved = try XcodeProjectLoader().load(from: projDir, configuration: .release)
    XCTAssertEqual(resolved.mainTarget.bundleIdentifier, "dev.example.classic")
    XCTAssertEqual(resolved.mainTarget.marketingVersion, "2.4.1")
    XCTAssertEqual(resolved.mainTarget.swiftSources.map(\.lastPathComponent), ["AppMain.swift"])
    XCTAssertTrue(resolved.inferredCrossSwiftModules.contains("SwiftUI"))
    XCTAssertTrue(resolved.inferredCrossSwiftModules.contains("SQLite3"))
    XCTAssertEqual(resolved.skippedDarwinOnlyProducts, ["Sparkle"])
    XCTAssertEqual(resolved.productDependencies.map(\.productName), ["Logging"])
    XCTAssertEqual(resolved.remotePackages.first?.pinnedVersion, "1.6.1")

    let synthesizer = SwiftPMBackend()
    let nativeAPIRoot = repositoryRoot
      .deletingLastPathComponent()
      .appendingPathComponent("nativeapi/bindings/swift")
    let windowsManifest = synthesizer.generatePackageManifest(
      project: resolved,
      platform: .windows,
      configuration: .release,
      consoleSubsystem: false,
      crossSwiftRoot: repositoryRoot,
      nativeAPISwiftRoot: nativeAPIRoot,
      compiledResourceURL: nil
    )
    XCTAssertTrue(windowsManifest.contains(".product(name: \"SQLite3\""))
    let linuxManifest = synthesizer.generatePackageManifest(
      project: resolved,
      platform: .linux,
      configuration: .release,
      consoleSubsystem: false,
      crossSwiftRoot: repositoryRoot,
      nativeAPISwiftRoot: nativeAPIRoot,
      compiledResourceURL: nil
    )
    XCTAssertTrue(linuxManifest.contains(".product(name: \"SQLite3\""))
  }

  func testICOEncoderProducesValidMultiSizeHeaderAndPayloads() throws {
    let png16 = makeMinimalPNG(width: 16, height: 16)
    let png256 = makeMinimalPNG(width: 256, height: 256)
    let dims16 = ICOEncoder.readPNGDimensions(data: png16)
    let dims256 = ICOEncoder.readPNGDimensions(data: png256)
    XCTAssertEqual(dims16?.width, 16)
    XCTAssertEqual(dims256?.width, 256)

    let ico = try XCTUnwrap(
      ICOEncoder.encode(pngEntries: [
        ICOEncoder.PNGEntry(width: 256, height: 256, data: png256),
        ICOEncoder.PNGEntry(width: 16, height: 16, data: png16),
      ])
    )
    let bytes = [UInt8](ico)
    XCTAssertEqual(bytes[0..<6], [0, 0, 1, 0, 2, 0])
    // Entry 0 (sorted ascending): 16x16
    XCTAssertEqual(bytes[6], 16)
    XCTAssertEqual(bytes[7], 16)
    // Entry 1: 256x256 stored as 0x0 per ICO spec
    XCTAssertEqual(bytes[22], 0)
    XCTAssertEqual(bytes[23], 0)
    XCTAssertEqual(bytes.count, 6 + 32 + png16.count + png256.count)
  }

  func testAssetAndIconCompilerGeneratesSymbolsInfoPlistAndWindowsRC() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let resolved = try XcodeProjectLoader().load(from: demoProject, configuration: .release)

    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossswift-assets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let compiled = try AssetAndIconCompiler().compile(project: resolved, stagingRoot: tmp)
    XCTAssertNotNil(compiled.windowsIconURL)
    XCTAssertFalse(compiled.linuxIconVariants.isEmpty)

    let plistData = try Data(contentsOf: compiled.infoPlistURL)
    let plist = try XCTUnwrap(
      try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        as? [String: Any]
    )
    XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.crossswift.xcodedemo")
    XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.2.0")
    XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "XcodeDemo")

    let symbolsURL = try XCTUnwrap(compiled.generatedSymbolsSwiftURL)
    let symbolsCode = try String(contentsOf: symbolsURL, encoding: .utf8)
    XCTAssertTrue(symbolsCode.contains("struct ColorResource"))
    XCTAssertTrue(symbolsCode.contains("struct ImageResource"))
    XCTAssertTrue(symbolsCode.contains("static let brandAccent = ColorResource(name: \"BrandAccent\""))
    XCTAssertTrue(symbolsCode.contains("lightRed: 0.145"))
    XCTAssertTrue(symbolsCode.contains("darkRed: 0.31"))
    XCTAssertTrue(symbolsCode.contains("static let heroBadge = ImageResource(name: \"HeroBadge\""))

    let rcText = try String(contentsOf: XCTUnwrap(compiled.windowsResourceScriptURL), encoding: .utf8)
    XCTAssertTrue(rcText.contains("1 ICON \"AppIcon.ico\""))
    XCTAssertTrue(rcText.contains("1 24 \"Application.manifest\""))
    XCTAssertTrue(rcText.contains("FILEVERSION 1,2,0,1"))
  }

  func testXcodeBuildCLIParserFlagsOverridesAndActions() throws {
    let demoDir = repositoryRoot.appendingPathComponent("Examples/XcodeDemo")
    let outcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-scheme", "XcodeDemo",
        "-configuration", "Debug",
        "-derivedDataPath", "build-out",
        "-UseModernBuildSystem=YES",
        "-skipPackagePluginValidation",
        "CODE_SIGNING_ALLOWED=NO",
        "CONFIGURATION_BUILD_DIR=/tmp/custom-out",
        "MARKETING_VERSION=3.1.0",
        "clean",
        "build",
      ],
      currentDirectory: demoDir
    )

    guard case .run(let opts) = outcome else {
      XCTFail("Expected .run outcome")
      return
    }
    XCTAssertNil(opts.projectPath)
    XCTAssertEqual(opts.schemeName, "XcodeDemo")
    XCTAssertEqual(opts.configuration, .debug)
    XCTAssertEqual(
      opts.derivedDataPath?.path,
      demoDir.appendingPathComponent("build-out").standardizedFileURL.path
    )
    XCTAssertEqual(opts.buildSettingOverrides["CODE_SIGNING_ALLOWED"], "NO")
    XCTAssertEqual(opts.buildSettingOverrides["CONFIGURATION_BUILD_DIR"], "/tmp/custom-out")
    XCTAssertEqual(opts.buildSettingOverrides["MARKETING_VERSION"], "3.1.0")
    XCTAssertEqual(opts.mode, .actions([.clean, .build]))

    let discovered = try XcodeProjectLoader.discoverProjectURL(
      projectPath: opts.projectPath,
      workspacePath: opts.workspacePath,
      in: demoDir
    )
    XCTAssertEqual(discovered.lastPathComponent, "XcodeDemo.xcodeproj")
  }

  func testXcodeBuildDriverListJSONMatchesAppleSchema() throws {
    let demoDir = repositoryRoot.appendingPathComponent("Examples/XcodeDemo")
    let outcome = try XcodeBuildCLIParser.parse(
      arguments: ["-list", "-json"],
      currentDirectory: demoDir
    )
    guard case .run(let opts) = outcome else {
      XCTFail("Expected .run outcome")
      return
    }

    let driver = XcodeBuildDriver()
    let jsonText = try driver.list(options: opts, currentDirectory: demoDir)
    let json = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any]
    )
    let projectDict = try XCTUnwrap(json["project"] as? [String: Any])
    XCTAssertEqual(projectDict["name"] as? String, "XcodeDemo")
    XCTAssertEqual(projectDict["configurations"] as? [String], ["Debug", "Release"])
    XCTAssertEqual(projectDict["targets"] as? [String], ["XcodeDemo"])
    XCTAssertEqual(projectDict["schemes"] as? [String], ["XcodeDemo"])
  }

  func testXcodeBuildDriverShowBuildSettingsJSONAndOverrides() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let outcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-showBuildSettings",
        "-json",
        "-project", demoProject.path,
        "-scheme", "XcodeDemo",
        "-configuration", "Release",
        "-destination", "generic/platform=Windows",
        "MARKETING_VERSION=9.9.9",
        "CONFIGURATION_BUILD_DIR=/tmp/custom-out",
      ],
      currentDirectory: repositoryRoot
    )
    guard case .run(let opts) = outcome else {
      XCTFail("Expected .run outcome")
      return
    }

    let driver = XcodeBuildDriver()
    let jsonText = try driver.showBuildSettings(options: opts, currentDirectory: repositoryRoot)
    let array = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [[String: Any]]
    )
    XCTAssertEqual(array.count, 1)
    XCTAssertEqual(array[0]["action"] as? String, "build")
    XCTAssertEqual(array[0]["target"] as? String, "XcodeDemo")

    let buildSettings = try XCTUnwrap(array[0]["buildSettings"] as? [String: String])
    XCTAssertEqual(buildSettings["CONFIGURATION"], "Release")
    XCTAssertEqual(buildSettings["MARKETING_VERSION"], "9.9.9")
    XCTAssertEqual(buildSettings["BUILT_PRODUCTS_DIR"], "/tmp/custom-out")
    XCTAssertEqual(buildSettings["CONFIGURATION_BUILD_DIR"], "/tmp/custom-out")
    XCTAssertEqual(buildSettings["FULL_PRODUCT_NAME"], "XcodeDemo")
    XCTAssertEqual(buildSettings["EXECUTABLE_PATH"], "XcodeDemo/XcodeDemo.exe")
    XCTAssertEqual(buildSettings["PLATFORM_NAME"], "windows")
  }
  func testXcodeBuildDriverShowBuildSettingsForWasmAndHarmonyOS() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let driver = XcodeBuildDriver()

    let wasmOutcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-showBuildSettings", "-json",
        "-project", demoProject.path,
        "-scheme", "XcodeDemo",
        "-configuration", "Release",
        "-destination", "generic/platform=Wasm",
      ],
      currentDirectory: repositoryRoot
    )
    guard case .run(let wasmOpts) = wasmOutcome else {
      XCTFail("Expected .run outcome for Wasm")
      return
    }
    let wasmJSON = try driver.showBuildSettings(options: wasmOpts, currentDirectory: repositoryRoot)
    let wasmArray = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(wasmJSON.utf8)) as? [[String: Any]]
    )
    let wasmSettings = try XCTUnwrap(wasmArray.first?["buildSettings"] as? [String: String])
    XCTAssertEqual(wasmSettings["PLATFORM_NAME"], "wasm")
    XCTAssertEqual(wasmSettings["ARCHS"], "wasm32")
    XCTAssertEqual(wasmSettings["EXECUTABLE_PATH"], "XcodeDemo/app/XcodeDemo.wasm")

    let harmonyOutcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-showBuildSettings", "-json",
        "-project", demoProject.path,
        "-scheme", "XcodeDemo",
        "-configuration", "Release",
        "-sdk", "ohos",
      ],
      currentDirectory: repositoryRoot
    )
    guard case .run(let harmonyOpts) = harmonyOutcome else {
      XCTFail("Expected .run outcome for HarmonyOS")
      return
    }
    let harmonyJSON = try driver.showBuildSettings(options: harmonyOpts, currentDirectory: repositoryRoot)
    let harmonyArray = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(harmonyJSON.utf8)) as? [[String: Any]]
    )
    let harmonySettings = try XCTUnwrap(harmonyArray.first?["buildSettings"] as? [String: String])
    XCTAssertEqual(harmonySettings["PLATFORM_NAME"], "harmonyos")
    XCTAssertEqual(harmonySettings["ARCHS"], "arm64-v8a")
    XCTAssertEqual(harmonySettings["EXECUTABLE_PATH"], "XcodeDemo/runtime/XcodeDemo.o")
  }

  func testSwiftPMBackendGeneratesWasmManifestWithJavaScriptKitAndWasiStack() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let loader = XcodeProjectLoader()
    let resolved = try loader.load(from: demoProject, configuration: .release)

    let synthesizer = SwiftPMBackend()
    let manifest = synthesizer.generatePackageManifest(
      project: resolved,
      platform: .wasm,
      configuration: .release,
      consoleSubsystem: false,
      crossSwiftRoot: repositoryRoot,
      nativeAPISwiftRoot: nil,
      compiledResourceURL: nil
    )

    XCTAssertTrue(manifest.contains("JavaScriptKit.git"))
    XCTAssertTrue(manifest.contains(".product(name: \"SwiftUI\", package: \"crossswift\")"))
    XCTAssertTrue(manifest.contains("stack-size=16777216"))
    XCTAssertTrue(manifest.contains(".when(platforms: [.wasi])"))
    XCTAssertFalse(manifest.contains(".product(name: \"AppKit\""))
    XCTAssertFalse(manifest.contains(".product(name: \"CryptoKit\""))
    XCTAssertFalse(manifest.contains(".product(name: \"NativeAPI\""))
  }

  func testHarmonyBuilderDetectsMainAppTypeAndRendersHostExports() throws {
    let appSwift = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo/XcodeDemoApp.swift")
    let detected = HarmonyBuilder.detectMainAppTypeName(in: [appSwift])
    XCTAssertEqual(detected, "XcodeDemoApp")

    let hostCode = HarmonyBuilder.renderHarmonyAppHostSwift(appTypeName: "XcodeDemoApp")
    XCTAssertTrue(hostCode.contains("extension App {"))
    XCTAssertTrue(hostCode.contains("public static func main() {}"))
    XCTAssertTrue(hostCode.contains("@_cdecl(\"swift_mount_app\")"))
    XCTAssertTrue(hostCode.contains("let app = XcodeDemoApp()"))
  }

  func testAndroidBuilderPackageSanitizationHostRenderingAndManifest() throws {
    XCTAssertEqual(
      AndroidBuilder.sanitizedAndroidPackageName(from: "dev.cross-swift.XcodeDemo"),
      "dev.cross_swift.xcodedemo"
    )
    XCTAssertEqual(
      AndroidBuilder.jniMangledName("dev.cross_swift.xcodedemo"),
      "dev_cross_1swift_xcodedemo"
    )

    let hostSwift = AndroidBuilder.renderAndroidAppHostSwift(
      appTypeName: "XcodeDemoApp",
      androidPackageName: "dev.crossswift.xcodedemo"
    )
    XCTAssertTrue(hostSwift.contains("extension App {"))
    XCTAssertTrue(hostSwift.contains("@_cdecl(\"Java_dev_crossswift_xcodedemo_MainActivity_nativeCreate\")"))
    XCTAssertTrue(hostSwift.contains("AndroidHost.retain(root: rootView)"))

    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let loader = XcodeProjectLoader()
    let resolved = try loader.load(from: demoProject, configuration: .release)

    let backend = SwiftPMBackend()
    let manifest = backend.generatePackageManifest(
      project: resolved,
      platform: .android,
      configuration: .release,
      consoleSubsystem: false,
      crossSwiftRoot: repositoryRoot,
      nativeAPISwiftRoot: nil,
      compiledResourceURL: nil
    )
    XCTAssertTrue(manifest.contains(".library(name: \"XcodeDemo\", type: .dynamic, targets: [\"XcodeDemo\"])"))
    XCTAssertTrue(manifest.contains(".product(name: \"SwiftUI\", package: \"crossswift\")"))
    XCTAssertFalse(manifest.contains(".executableTarget("))
    XCTAssertFalse(manifest.contains(".product(name: \"AppKit\""))

    let driver = XcodeBuildDriver()
    let androidOutcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-showBuildSettings", "-json",
        "-project", demoProject.path,
        "-scheme", "XcodeDemo",
        "-configuration", "Release",
        "-destination", "generic/platform=Android",
      ],
      currentDirectory: repositoryRoot
    )
    guard case .run(let androidOpts) = androidOutcome else {
      XCTFail("Expected .run outcome for Android")
      return
    }
    let androidJSON = try driver.showBuildSettings(options: androidOpts, currentDirectory: repositoryRoot)
    let androidArray = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(androidJSON.utf8)) as? [[String: Any]]
    )
    let androidSettings = try XCTUnwrap(androidArray.first?["buildSettings"] as? [String: String])
    XCTAssertEqual(androidSettings["PLATFORM_NAME"], "android")
    XCTAssertEqual(androidSettings["ARCHS"], "arm64-v8a")
    XCTAssertEqual(androidSettings["EXECUTABLE_PATH"], "XcodeDemo/XcodeDemo.apk")
  }

  func testGenericPackageDependencyAdapterPatchesImplicitAppleImportsAndUndeclaredXCAassets() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossswift-pkgadapt-\(UUID().uuidString)")
    let upstream = tmp.appendingPathComponent("IconKit")
    let classesDir = upstream.appendingPathComponent("ios/IconKit/Classes")
    let catalogDir = upstream.appendingPathComponent("ios/IconKit/Assets/IconKit.xcassets")
    let sampleSet = catalogDir.appendingPathComponent("ic_sample_20_regular.imageset")
    try FileManager.default.createDirectory(at: classesDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sampleSet, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    try """
    // swift-tools-version: 5.7
    import PackageDescription
    let package = Package(
      name: "IconKit",
      products: [
        .library(name: "IconKit", targets: ["IconKit"]),
      ],
      dependencies: [],
      targets: [
        .target(
          name: "IconKit",
          dependencies: [],
          path: "ios/IconKit"
        ),
      ]
    )
    """.write(to: upstream.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    try """
    import Foundation
    #if canImport(SwiftUI)
    import SwiftUI
    #endif
    #if canImport(AppKit)
    import AppKit
    #endif
    public enum SampleIcon: String {
      case home = "ic_sample_20_regular"
    }
    """.write(to: classesDir.appendingPathComponent("SampleIcon.swift"), atomically: true, encoding: .utf8)
    try "%PDF-1.4\n".write(to: sampleSet.appendingPathComponent("ic_sample_20_regular.pdf"), atomically: true, encoding: .utf8)

    let inspection = PackageDependencyAdapter.inspect(packageRoot: upstream)
    XCTAssertTrue(inspection.needsAdaptation)
    XCTAssertEqual(inspection.targets.count, 1)
    XCTAssertEqual(inspection.targets[0].name, "IconKit")
    XCTAssertEqual(inspection.targets[0].importedCrossSwiftModules, ["AppKit", "SwiftUI"])
    XCTAssertEqual(inspection.targets[0].undeclaredAssetCatalogs, ["Assets/IconKit.xcassets"])

    let adaptedDir = tmp.appendingPathComponent("adapted/iconkit")
    let adaptedURL = try XCTUnwrap(
      PackageDependencyAdapter.adaptCheckoutIfNeeded(
        sourceRoot: upstream,
        outputDirectory: adaptedDir,
        crossSwiftRoot: repositoryRoot
      )
    )

    let patchedManifest = try String(contentsOf: adaptedURL.appendingPathComponent("Package.swift"), encoding: .utf8)
    XCTAssertTrue(patchedManifest.contains(".package(path:"))
    XCTAssertTrue(patchedManifest.contains(".product(name: \"SwiftUI\""))
    XCTAssertTrue(patchedManifest.contains(".product(name: \"AppKit\""))
    XCTAssertTrue(patchedManifest.contains(".copy(\"Assets/IconKit.xcassets\")"))

    // Pure Swift packages without Apple imports or undeclared .xcassets are left untouched.
    let purePkg = tmp.appendingPathComponent("PureSwift")
    try FileManager.default.createDirectory(at: purePkg.appendingPathComponent("Sources/PureSwift"), withIntermediateDirectories: true)
    try """
    // swift-tools-version: 5.9
    import PackageDescription
    let package = Package(
      name: "PureSwift",
      targets: [.target(name: "PureSwift")]
    )
    """.write(to: purePkg.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try "import Foundation\npublic let value = 1\n".write(
      to: purePkg.appendingPathComponent("Sources/PureSwift/Pure.swift"),
      atomically: true,
      encoding: .utf8
    )
    XCTAssertFalse(PackageDependencyAdapter.inspect(packageRoot: purePkg).needsAdaptation)
    XCTAssertNil(try PackageDependencyAdapter.adaptCheckoutIfNeeded(
      sourceRoot: purePkg,
      outputDirectory: tmp.appendingPathComponent("adapted/pureswift"),
      crossSwiftRoot: repositoryRoot
    ))
  }

  func testSwiftPMBackendGeneratesSwift6ManifestWhenSwiftVersionIs6() throws {
    let demoProject = repositoryRoot.appendingPathComponent("Examples/XcodeDemo/XcodeDemo.xcodeproj")
    let loader = XcodeProjectLoader()
    let resolved = try loader.load(
      from: demoProject,
      configuration: .release,
      buildSettingOverrides: ["SWIFT_VERSION": "6.0"]
    )

    let synthesizer = SwiftPMBackend()
    let manifest = synthesizer.generatePackageManifest(
      project: resolved,
      platform: .windows,
      configuration: .release,
      consoleSubsystem: false,
      crossSwiftRoot: repositoryRoot,
      nativeAPISwiftRoot: nil,
      compiledResourceURL: nil
    )

    XCTAssertTrue(manifest.hasPrefix("// swift-tools-version: 6.0\n"))
    XCTAssertFalse(manifest.contains("enableUpcomingFeature(\"BareSlashRegexLiterals\")"))
    XCTAssertTrue(manifest.contains(".product(name: \"CrossFoundation\", package: \"crossswift\")"))
  }

  func testLocalPackageAdaptationWithUnicodeCommentRemoteOverrideAndWasmJSKit() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("CrossXcodeBuildLocalAdapt-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tmp) }

    let pkgDir = tmp.appendingPathComponent("MyDesignKit")
    let srcDir = pkgDir.appendingPathComponent("Sources/MyDesignKit")
    try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)

    let manifest = """
    // swift-tools-version: 5.9
    // Design kit — includes non-ASCII em-dash before Package declaration.
    import PackageDescription

    let package = Package(
      name: "MyDesignKit",
      products: [.library(name: "MyDesignKit", targets: ["MyDesignKit"])],
      dependencies: [
        .package(
          url: "https://github.com/microsoft/fluentui-system-icons.git",
          revision: "21d5d02f724be2aaf586564775fff73a18a76eb6"
        ),
        .package(name: "SiblingPkg", path: "../SiblingPkg"),
      ],
      targets: [
        .target(
          name: "MyDesignKit",
          dependencies: [
            .product(name: "FluentIcons", package: "fluentui-system-icons"),
          ]
        ),
      ]
    )
    """
    try manifest.write(to: pkgDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try """
    import SwiftUI
    #if os(WASI)
      import JavaScriptKit
    #endif
    public struct KitView: View {
      public var body: some View { EmptyView() }
    }
    """.write(to: srcDir.appendingPathComponent("KitView.swift"), atomically: true, encoding: .utf8)

    let adaptedIcons = tmp.appendingPathComponent("adapted/fluentui-system-icons")
    let adaptedOut = tmp.appendingPathComponent("adapted/mydesignkit")
    let result = try PackageDependencyAdapter.adaptCheckoutIfNeeded(
      sourceRoot: pkgDir,
      outputDirectory: adaptedOut,
      crossSwiftRoot: repositoryRoot,
      allowedCrossSwiftModules: ["SwiftUI", "SwiftUIRuntime"],
      useWasmBundleShim: true,
      adaptedRemoteOverrides: [
        "https://github.com/microsoft/fluentui-system-icons.git": adaptedIcons,
        "fluentui-system-icons": adaptedIcons,
      ],
      resolveRelativePaths: true
    )
    XCTAssertEqual(result, adaptedOut)

    let patched = try String(contentsOf: adaptedOut.appendingPathComponent("Package.swift"), encoding: .utf8)
    XCTAssertTrue(patched.contains(".package(path: \"\(adaptedIcons.path)\")"))
    XCTAssertFalse(patched.contains("https://github.com/microsoft/fluentui-system-icons.git"))
    XCTAssertTrue(patched.contains(".package(name: \"SiblingPkg\", path: \"\(tmp.appendingPathComponent("SiblingPkg").path)\")"))
    XCTAssertTrue(patched.contains("JavaScriptKit.git"))
    XCTAssertTrue(patched.contains(".product(name: \"SwiftUI\", package:"))
    XCTAssertTrue(patched.contains(".product(name: \"JavaScriptKit\", package: \"javascriptkit\")"))
    XCTAssertTrue(fm.fileExists(atPath: adaptedOut.appendingPathComponent("Sources/MyDesignKit/KitView.swift").path))
  }

  func testPackageDependencyAdapterInsertsDependenciesBeforePath() throws {
    let manifest = """
      // swift-tools-version: 5.9
      import PackageDescription

      let package = Package(
        name: "MultiTargetKit",
        products: [
          .library(name: "MobileKit", targets: ["MobileKit"]),
        ],
        targets: [
          .target(
            name: "MobileKit",
            path: "packages/swift/MobileKit/Sources/MobileKit"
          ),
        ]
      )
      """
    let inspection = PackageDependencyAdapter.InspectionResult(
      targets: [
        PackageDependencyAdapter.TargetInspection(
          name: "MobileKit",
          relativePath: "packages/swift/MobileKit/Sources/MobileKit",
          importedCrossSwiftModules: ["SwiftUI"],
          undeclaredAssetCatalogs: [],
          largeAssetCatalogs: [],
          hasObjCAttributes: false
        )
      ]
    )
    let patched = PackageDependencyAdapter.patchManifest(
      manifest,
      inspection: inspection,
      crossSwiftRoot: URL(fileURLWithPath: "/tmp/crossswift")
    )
    let depsRange = try XCTUnwrap(patched.range(of: "dependencies: [\n        .product(name: \"SwiftUI\", package: \"crossswift\")"))
    let pathRange = try XCTUnwrap(patched.range(of: "path: \"packages/swift/MobileKit/Sources/MobileKit\""))
    XCTAssertLessThan(depsRange.lowerBound, pathRange.lowerBound)
  }

  func testXcodeProjectLoaderSkipsDarwinGuardedLocalPackageProduct() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("CrossXcodeBuild-DarwinGuard-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let widgetsDir = tmp.appendingPathComponent("AppleWidgets")
    try fm.createDirectory(at: widgetsDir.appendingPathComponent("Sources/AppleWidgets"), withIntermediateDirectories: true)
    try """
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
        name: "AppleWidgets",
        products: [.library(name: "AppleWidgets", targets: ["AppleWidgets"])],
        targets: [.target(name: "AppleWidgets")]
      )
      """.write(to: widgetsDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try "import WidgetKit\n".write(
      to: widgetsDir.appendingPathComponent("Sources/AppleWidgets/Widget.swift"),
      atomically: true,
      encoding: .utf8
    )

    let appSrcDir = tmp.appendingPathComponent("App")
    try fm.createDirectory(at: appSrcDir, withIntermediateDirectories: true)
    try """
      import SwiftUI
      #if os(macOS)
        import AppleWidgets
      #endif
      @main struct AppMain: App { var body: some Scene { WindowGroup { Text("Hi") } } }
      """.write(to: appSrcDir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

    let projDir = tmp.appendingPathComponent("App.xcodeproj")
    try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
    try """
      // !$*UTF8*$!
      {
        archiveVersion = 1;
        classes = {};
        objectVersion = 77;
        objects = {
          A1 = { isa = PBXBuildFile; productRef = P1; };
          F1 = { isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
          S1 = { isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; };
          FB1 = { isa = PBXFrameworksBuildPhase; files = (A1, ); };
          G0 = { isa = PBXGroup; children = (S1, G1, ); sourceTree = "<group>"; };
          G1 = { isa = PBXGroup; children = (F1, ); name = Products; sourceTree = "<group>"; };
          T1 = {
            isa = PBXNativeTarget;
            buildConfigurationList = C1;
            buildPhases = (SB1, FB1, );
            fileSystemSynchronizedGroups = (S1, );
            name = App;
            packageProductDependencies = (P1, );
            productName = App;
            productReference = F1;
            productType = "com.apple.product-type.application";
          };
          PRJ = {
            isa = PBXProject;
            buildConfigurationList = C0;
            mainGroup = G0;
            packageReferences = (LP1, );
            targets = (T1, );
          };
          SB1 = { isa = PBXSourcesBuildPhase; files = (); };
          BC0 = { isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
          BC1 = { isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = App; }; name = Debug; };
          C0 = { isa = XCConfigurationList; buildConfigurations = (BC0, ); defaultConfigurationName = Debug; };
          C1 = { isa = XCConfigurationList; buildConfigurations = (BC1, ); defaultConfigurationName = Debug; };
          LP1 = { isa = XCLocalSwiftPackageReference; relativePath = AppleWidgets; };
          P1 = { isa = XCSwiftPackageProductDependency; package = LP1; productName = AppleWidgets; };
        };
        rootObject = PRJ;
      }
      """.write(to: projDir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

    let resolved = try XcodeProjectLoader().load(from: projDir, configuration: .debug, targetName: "App")
    XCTAssertTrue(resolved.skippedDarwinOnlyProducts.contains("AppleWidgets"))
    XCTAssertFalse(resolved.productDependencies.contains(where: { $0.productName == "AppleWidgets" }))
    XCTAssertFalse(resolved.localPackages.contains(where: { $0.name == "AppleWidgets" }))
  }

  func testPatchManifestRewritesRemoteOverrideWithCRLFLineEndings() {
    let manifest = [
      "// swift-tools-version: 5.9",
      "// Comment mentioning .package(url: \"https://example.com/ignored.git\", from: \"1.0.0\")",
      "import PackageDescription",
      "let package = Package(",
      "  name: \"DazzUI\",",
      "  dependencies: [",
      "    .package(",
      "      url: \"https://github.com/microsoft/fluentui-system-icons.git\",",
      "      revision: \"21d5d02f724be2aaf586564775fff73a18a76eb6\"",
      "    ),",
      "  ],",
      "  targets: [",
      "    .target(",
      "      name: \"DazzUI\",",
      "      dependencies: [.product(name: \"FluentIcons\", package: \"fluentui-system-icons\")],",
      "      path: \"Sources/DazzUI\"",
      "    ),",
      "  ]",
      ")",
    ].joined(separator: "\r\n")

    let inspection = PackageDependencyAdapter.InspectionResult(targets: [
      .init(
        name: "DazzUI",
        relativePath: "Sources/DazzUI",
        importedCrossSwiftModules: ["SwiftUI"],
        undeclaredAssetCatalogs: [],
        largeAssetCatalogs: [],
        hasObjCAttributes: false
      )
    ])
    let adaptedIcons = URL(fileURLWithPath: "/tmp/AdaptedPackages/fluentui-system-icons")
    let patched = PackageDependencyAdapter.patchManifest(
      manifest,
      inspection: inspection,
      crossSwiftRoot: URL(fileURLWithPath: "/tmp/crossswift"),
      adaptedRemoteOverrides: ["fluentui-system-icons": adaptedIcons]
    )

    XCTAssertTrue(patched.contains(".package(path: \"/tmp/AdaptedPackages/fluentui-system-icons\")"))
    XCTAssertFalse(patched.contains("https://github.com/microsoft/fluentui-system-icons.git"))
    XCTAssertTrue(patched.contains("https://example.com/ignored.git"))
  }

  private func makeMinimalPNG(width: Int, height: Int) -> Data {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    data.append(contentsOf: [0, 0, 0, 13]) // IHDR length
    data.append(contentsOf: [0x49, 0x48, 0x44, 0x52]) // IHDR
    for val in [UInt32(width), UInt32(height)] {
      var be = val.bigEndian
      withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: [8, 6, 0, 0, 0])
    data.append(contentsOf: [0, 0, 0, 0]) // placeholder CRC for test
    return data
  }
}
