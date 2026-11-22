// swift-tools-version:5.9

import CompilerPluginSupport
import Foundation
import PackageDescription

// CrossSwift (`crossswift`) — cross-platform SwiftUI, AppKit, Apple-framework
// compatibility shims, and an `xcodebuild`-compatible build tool for Windows,
// Linux, WebAssembly, HarmonyOS, and Android.
// Unofficial; not affiliated with Apple.
//
// Note: The SwiftPM manifest retains `Package(name: "CrossSwiftUI")` for
// downstream package manifest compatibility, while `CrossSwiftUI` is specifically
// the desktop NativeAPI backend and AppKit-hosting module.
//
// Core module groups:
//   SwiftUIRuntime  platform-independent SwiftUI engine (views, layout, diff,
//                   state, observation, controls, vector graphics, localization)
//                   paired with `SwiftUIRuntimeMacros` (`@Entry`, `#Preview`).
//   CrossSwiftUI    desktop NativeAPI backend (Windows GDI+ via `CSwiftUIWindows`,
//                   Linux GTK/Cairo/Pango), `App`/`MenuBarExtra` runner, and
//                   `CrossAppKit` hosting (`NSHostingView`, `NSViewRepresentable`).
//   CrossAppKit     cross-platform AppKit implementation (re-exported as `AppKit`
//                   on Windows/Linux, backed by NativeAPI and `CAppKitWindows`).
//   CrossFoundation Apple Foundation extensions plus `Sources/AppleShims/*` and
//                   standalone shims (`CoreGraphics`, `Combine`, `CryptoKit`,
//                   `Carbon`, `UniformTypeIdentifiers`, `OSLog`, `os`, `SQLite3`).
//   SwiftUIWeb      WebAssembly (`os(WASI)`) DOM backend and browser runner.
//   SwiftUIAndroid  Android JNI bridge (`CSwiftUIAndroid`) and Jetpack Compose host.
//   SwiftUI         user-facing `import SwiftUI` facade on non-Apple targets.
//   CrossXcodeBuild pure-Swift `.xcodeproj`/`.xcworkspace` parser, adapter, and
//                   multi-platform builder powering `CrossXcodeBuildCLI` (`xcodebuild`).
//
// On macOS, the desktop package graph builds `SwiftUIRuntime`, `CrossAppKit`,
// `CrossXcodeBuild` (`xcodebuild`), their test suites, and `Counter` compiled
// against Apple's native SwiftUI. WebAssembly (`CROSS_SWIFTUI_WEB=1`) and Android
// (`CROSS_SWIFTUI_ANDROID=1`) select isolated cross-compilation package graphs.
//
// The nativeapi Swift package is consumed as a sibling checkout at
// ../nativeapi/bindings/swift (see README "Requirements"). It is intentionally
// a path dependency: this project is not published to a package registry.

// SwiftPM evaluates the manifest on the host. Select the cross-build graph
// explicitly so it never resolves desktop SDK dependencies.
let buildForAndroid = ProcessInfo.processInfo.environment["CROSS_SWIFTUI_ANDROID"] == "1"
let buildForHarmony = !buildForAndroid && ProcessInfo.processInfo.environment["CROSS_SWIFTUI_HARMONY"] == "1"
let buildForWeb = !buildForAndroid && !buildForHarmony && ProcessInfo.processInfo.environment["CROSS_SWIFTUI_WEB"] == "1"
let buildForDesktop = !buildForWeb && !buildForAndroid && !buildForHarmony
let explicitNativeAPIPath = ProcessInfo.processInfo.environment["NATIVEAPI_SWIFT_PATH"]
#if os(macOS)
let buildDesktopNative = false
#else
let defaultNativeAPIManifest = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("nativeapi/bindings/swift/Package.swift")
  .path
let buildDesktopNative = buildForDesktop
  && (explicitNativeAPIPath != nil || FileManager.default.fileExists(atPath: defaultNativeAPIManifest))
#endif

var packageDependencies: [Package.Dependency] = []
if buildForWeb {
  packageDependencies = [
    .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.63.0")
  ]
}
#if !os(macOS)
if buildDesktopNative {
  packageDependencies = [
    .package(
      name: "NativeAPI",
      path: explicitNativeAPIPath ?? "../nativeapi/bindings/swift")
  ]
}
#endif

var targets: [Target] = [
  .macro(name: "SwiftUIRuntimeMacros"),
  .target(
    name: "SwiftUIRuntime",
    dependencies: ["SwiftUIRuntimeMacros"],
    linkerSettings: [
      // Deep declarative view trees exceed Windows' 1 MiB default in debug builds.
      .unsafeFlags(["-Xlinker", "/STACK:16777216"], .when(platforms: [.windows]))
    ]),
]

var products: [Product] = [
  .library(name: "SwiftUIRuntime", targets: ["SwiftUIRuntime"])
]

var crossAppKitDependencies: [Target.Dependency] = []
#if os(macOS)
let buildCrossAppKit = buildForDesktop
#else
let buildCrossAppKit = buildDesktopNative
#endif
if buildCrossAppKit {
  products.append(.library(name: "CrossAppKit", targets: ["CrossAppKit"]))
}

#if os(Windows)
if buildDesktopNative {
  targets.append(
    .target(
      name: "CAppKitWindows",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedLibrary("user32"),
        .linkedLibrary("shell32"),
        .linkedLibrary("ole32"),
        .linkedLibrary("oleaut32"),
        .linkedLibrary("uuid"),
        .linkedLibrary("dwmapi"),
        .linkedLibrary("gdi32"),
        .linkedLibrary("gdiplus"),
        .linkedLibrary("imm32"),
        .linkedLibrary("bcrypt"),
        .linkedLibrary("advapi32"),
        .linkedLibrary("shlwapi"),
      ]
    )
  )
  targets.append(
    .target(
      name: "SQLite3",
      publicHeadersPath: "include",
      linkerSettings: [.linkedLibrary("winsqlite3")]
    )
  )
  products.append(.library(name: "CAppKitWindows", targets: ["CAppKitWindows"]))
  products.append(.library(name: "SQLite3", targets: ["SQLite3"]))
  crossAppKitDependencies.append("CAppKitWindows")

  targets.append(
    .target(
      name: "CSwiftUIWindows", dependencies: [.product(name: "CNativeAPI", package: "NativeAPI")],
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedLibrary("gdiplus"),
        .linkedLibrary("comctl32"),
        .linkedLibrary("dwrite"),
        .linkedLibrary("d2d1"),
      ]))
  targets.append(
    .target(
      name: "CSwiftUIWindowsTestSupport",
      dependencies: ["CSwiftUIWindows", .product(name: "CNativeAPI", package: "NativeAPI")],
      path: "Tests/CSwiftUIWindowsTestSupport", publicHeadersPath: "include"))
  targets.append(
    .testTarget(
      name: "WindowsDrawingTests",
      dependencies: [
        "CSwiftUIWindowsTestSupport",
        "CrossSwiftUI",
        "CrossAppKit",
      ]))
}
let drawingDependencies: [Target.Dependency] = ["CSwiftUIWindows"]
#elseif !os(macOS)
let drawingDependencies: [Target.Dependency] = []
#if os(Linux)
if buildDesktopNative {
  targets.append(
    .target(
      name: "SQLite3",
      publicHeadersPath: "include",
      linkerSettings: [.linkedLibrary("sqlite3")]
    )
  )
  products.append(.library(name: "SQLite3", targets: ["SQLite3"]))
  targets.append(.testTarget(name: "LinuxDrawingTests", dependencies: ["CrossSwiftUI"]))
}
#endif
#endif

var counterDependencies: [Target.Dependency] = []
if buildForAndroid {
  targets += [
    .target(name: "CSwiftUIAndroid"),
    .target(name: "SwiftUIAndroid", dependencies: ["SwiftUIRuntime", "CSwiftUIAndroid"], exclude: ["Kotlin"]),
    .target(name: "SwiftUI", dependencies: ["SwiftUIRuntime", "SwiftUIAndroid"]),
    .target(
      name: "AndroidCounter", dependencies: ["SwiftUI", "CSwiftUIAndroid"],
      path: "Examples/Counter", exclude: ["CounterApp.swift"])
  ]
  products += [
    .library(name: "SwiftUI", targets: ["SwiftUI"]),
    .library(name: "AndroidCounter", type: .dynamic, targets: ["AndroidCounter"]),
  ]
}
if buildForHarmony {
  targets += [
    .target(
      name: "SwiftUIHarmony",
      dependencies: ["SwiftUIRuntime"],
      exclude: ["ArkTS"],
      swiftSettings: [.define("CROSS_SWIFTUI_HARMONY")]
    ),
    .target(
      name: "SwiftUI",
      dependencies: ["SwiftUIRuntime", "SwiftUIHarmony"],
      swiftSettings: [.define("CROSS_SWIFTUI_HARMONY")]
    ),
  ]
  products += [
    .library(name: "SwiftUIHarmony", targets: ["SwiftUIHarmony"]),
    .library(name: "SwiftUI", targets: ["SwiftUI"]),
  ]
}
if buildForWeb {
  targets += [
    .target(
      name: "SwiftUIWeb",
      dependencies: [
        "SwiftUIRuntime",
        .product(name: "JavaScriptKit", package: "JavaScriptKit"),
        .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
      ]
    ),
    .target(name: "SwiftUI", dependencies: ["SwiftUIRuntime", "SwiftUIWeb"]),
  ]
  products.append(.library(name: "SwiftUI", targets: ["SwiftUI"]))
  counterDependencies = ["SwiftUI"]
}

#if !os(macOS)
if buildDesktopNative {
  crossAppKitDependencies.append(.product(name: "NativeAPI", package: "NativeAPI"))
  crossAppKitDependencies.append("CoreGraphics")
  crossAppKitDependencies.append("UniformTypeIdentifiers")
  crossAppKitDependencies.append("Combine")
  crossAppKitDependencies.append("Carbon")

  let winGlueDependencies: [Target.Dependency]
  #if os(Windows)
    winGlueDependencies = ["CAppKitWindows"]
  #else
    winGlueDependencies = []
  #endif

  let crossFoundationDeps: [Target.Dependency] = [
    "SwiftUIRuntime", "CoreFoundation", "Darwin", "CoreGraphics", "Carbon",
  ] + winGlueDependencies
  let darwinDeps: [Target.Dependency] = ["CoreFoundation", "CDarwinShims"] + winGlueDependencies
  let appServicesDeps: [Target.Dependency] = ["CoreFoundation", "CoreGraphics"] + winGlueDependencies
  let imageIODeps: [Target.Dependency] = ["CoreFoundation", "CoreGraphics"] + winGlueDependencies
  let qlThumbDeps: [Target.Dependency] = ["CrossAppKit", "CoreGraphics"] + winGlueDependencies
  let coreGraphicsDeps: [Target.Dependency] = ["CoreFoundation", "Carbon"] + winGlueDependencies
  let crossSwiftUIDeps: [Target.Dependency] = [
    "SwiftUIRuntime",
    .product(name: "NativeAPI", package: "NativeAPI"),
    "CrossAppKit",
  ] + drawingDependencies

  let desktopTargets: [Target] = [
    .target(name: "CrossFoundation", dependencies: crossFoundationDeps),
    .target(name: "CoreFoundation", path: "Sources/AppleShims/CoreFoundation"),
    .target(name: "CDarwinShims", path: "Sources/AppleShims/CDarwinShims", publicHeadersPath: "include"),
    .target(name: "Darwin", dependencies: darwinDeps, path: "Sources/AppleShims/Darwin"),
    .target(name: "ApplicationServices", dependencies: appServicesDeps, path: "Sources/AppleShims/ApplicationServices"),
    .target(name: "ServiceManagement", dependencies: winGlueDependencies, path: "Sources/AppleShims/ServiceManagement"),
    .target(name: "Security", dependencies: ["CoreFoundation"] + winGlueDependencies, path: "Sources/AppleShims/Security"),
    .target(name: "CloudKit", path: "Sources/AppleShims/CloudKit"),
    .target(name: "EventKit", dependencies: ["CoreGraphics"], path: "Sources/AppleShims/EventKit"),
    .target(name: "AVFoundation", dependencies: ["CoreGraphics", "CrossAppKit", "CoreMedia"], path: "Sources/AppleShims/AVFoundation"),
    .target(name: "AVKit", dependencies: ["CrossAppKit", "AVFoundation"], path: "Sources/AppleShims/AVKit"),
    .target(name: "CoreAudio", dependencies: ["CoreFoundation"], path: "Sources/AppleShims/CoreAudio"),
    .target(name: "AudioToolbox", path: "Sources/AppleShims/AudioToolbox"),
    .target(name: "CoreMedia", dependencies: ["CoreFoundation", "AudioToolbox"], path: "Sources/AppleShims/CoreMedia"),
    .target(name: "CoreServices", dependencies: ["CoreFoundation"], path: "Sources/AppleShims/CoreServices"),
    .target(name: "CoreText", dependencies: ["CoreFoundation", "CoreGraphics", "CrossAppKit"], path: "Sources/AppleShims/CoreText"),
    .target(name: "ImageIO", dependencies: imageIODeps, path: "Sources/AppleShims/ImageIO"),
    .target(name: "ColorSync", path: "Sources/AppleShims/ColorSync"),
    .target(name: "PDFKit", dependencies: ["CrossAppKit", "CoreGraphics"], path: "Sources/AppleShims/PDFKit"),
    .target(name: "QuickLookUI", dependencies: ["CrossAppKit"], path: "Sources/AppleShims/QuickLookUI"),
    .target(name: "QuickLookThumbnailing", dependencies: qlThumbDeps, path: "Sources/AppleShims/QuickLookThumbnailing"),
    .target(name: "Network", path: "Sources/AppleShims/Network"),
    .target(name: "SystemConfiguration", dependencies: ["CoreFoundation"], path: "Sources/AppleShims/SystemConfiguration"),
    .target(name: "AuthenticationServices", dependencies: ["CrossAppKit"], path: "Sources/AppleShims/AuthenticationServices"),
    .target(name: "JavaScriptCore", path: "Sources/AppleShims/JavaScriptCore"),
    .target(name: "IOKit", path: "Sources/AppleShims/IOKit", publicHeadersPath: "include"),
    .target(name: "Compression", path: "Sources/AppleShims/Compression"),
    .target(name: "System", path: "Sources/AppleShims/System"),
    .target(name: "AppleArchive", dependencies: ["System"], path: "Sources/AppleShims/AppleArchive"),
    .target(name: "Accelerate", path: "Sources/AppleShims/Accelerate"),
    .target(name: "notify", path: "Sources/AppleShims/notify"),
    .target(name: "CommonCrypto", dependencies: winGlueDependencies, path: "Sources/AppleShims/CommonCrypto"),
    .target(name: "FoundationModels", path: "Sources/AppleShims/FoundationModels"),
    .target(name: "NaturalLanguage", path: "Sources/AppleShims/NaturalLanguage"),
    .target(name: "Translation", path: "Sources/AppleShims/Translation"),
    .target(name: "Carbon", publicHeadersPath: "include"),
    .target(name: "CoreGraphics", dependencies: coreGraphicsDeps),
    .target(name: "UniformTypeIdentifiers"),
    .target(name: "OSLog"),
    .target(name: "os", dependencies: ["OSLog"]),
    .target(name: "Combine"),
    .target(name: "CryptoKit", dependencies: winGlueDependencies),
    .target(name: "AppKit", dependencies: ["CrossAppKit", "CrossFoundation", "CoreFoundation", "CoreGraphics", "CoreText", "UniformTypeIdentifiers", "ApplicationServices"]),
    .target(name: "CrossSwiftUI", dependencies: crossSwiftUIDeps),
    .target(
      name: "SwiftUI",
      dependencies: [
        "SwiftUIRuntime",
        "CrossSwiftUI",
        "CrossAppKit",
        "CrossFoundation",
        "CoreGraphics",
        "Combine",
      ]
    ),
    .testTarget(
      name: "CrossShimsTests",
      dependencies: [
        "Combine",
        "Security",
        "ServiceManagement",
        "SwiftUIRuntime",
        "CrossSwiftUI",
      ]
    ),
  ]
  targets.append(contentsOf: desktopTargets)

  let desktopProducts: [Product] = [
    .library(name: "CrossFoundation", targets: ["CrossFoundation"]),
    .library(name: "CoreFoundation", targets: ["CoreFoundation"]),
    .library(name: "Darwin", targets: ["Darwin"]),
    .library(name: "ApplicationServices", targets: ["ApplicationServices"]),
    .library(name: "ServiceManagement", targets: ["ServiceManagement"]),
    .library(name: "Security", targets: ["Security"]),
    .library(name: "CloudKit", targets: ["CloudKit"]),
    .library(name: "EventKit", targets: ["EventKit"]),
    .library(name: "AVFoundation", targets: ["AVFoundation"]),
    .library(name: "AVKit", targets: ["AVKit"]),
    .library(name: "CoreAudio", targets: ["CoreAudio"]),
    .library(name: "AudioToolbox", targets: ["AudioToolbox"]),
    .library(name: "CoreMedia", targets: ["CoreMedia"]),
    .library(name: "CoreServices", targets: ["CoreServices"]),
    .library(name: "CoreText", targets: ["CoreText"]),
    .library(name: "ImageIO", targets: ["ImageIO"]),
    .library(name: "ColorSync", targets: ["ColorSync"]),
    .library(name: "PDFKit", targets: ["PDFKit"]),
    .library(name: "QuickLookUI", targets: ["QuickLookUI"]),
    .library(name: "QuickLookThumbnailing", targets: ["QuickLookThumbnailing"]),
    .library(name: "Network", targets: ["Network"]),
    .library(name: "SystemConfiguration", targets: ["SystemConfiguration"]),
    .library(name: "AuthenticationServices", targets: ["AuthenticationServices"]),
    .library(name: "JavaScriptCore", targets: ["JavaScriptCore"]),
    .library(name: "IOKit", targets: ["IOKit"]),
    .library(name: "Compression", targets: ["Compression"]),
    .library(name: "System", targets: ["System"]),
    .library(name: "AppleArchive", targets: ["AppleArchive"]),
    .library(name: "Accelerate", targets: ["Accelerate"]),
    .library(name: "notify", targets: ["notify"]),
    .library(name: "CommonCrypto", targets: ["CommonCrypto"]),
    .library(name: "FoundationModels", targets: ["FoundationModels"]),
    .library(name: "NaturalLanguage", targets: ["NaturalLanguage"]),
    .library(name: "Translation", targets: ["Translation"]),
    .library(name: "AppKit", targets: ["AppKit"]),
    .library(name: "Carbon", targets: ["Carbon"]),
    .library(name: "CoreGraphics", targets: ["CoreGraphics"]),
    .library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]),
    .library(name: "OSLog", targets: ["OSLog"]),
    .library(name: "os", targets: ["os"]),
    .library(name: "Combine", targets: ["Combine"]),
    .library(name: "CryptoKit", targets: ["CryptoKit"]),
    .library(name: "CrossSwiftUI", targets: ["CrossSwiftUI"]),
    .library(name: "SwiftUI", targets: ["SwiftUI"]),
  ]
  products.append(contentsOf: desktopProducts)
  counterDependencies = ["SwiftUI"]
}
#endif

if buildCrossAppKit {
  targets += [
    .target(
      name: "CrossAppKit",
      dependencies: crossAppKitDependencies
    ),
    .testTarget(
      name: "CrossAppKitTests",
      dependencies: ["CrossAppKit"]
    ),
  ]
}

if buildForDesktop {
  targets += [
    .target(
      name: "CrossXcodeBuild",
      dependencies: ["SwiftUIRuntime"]
    ),
    .executableTarget(
      name: "CrossXcodeBuildCLI",
      dependencies: ["CrossXcodeBuild"]
    ),
    .testTarget(
      name: "CrossXcodeBuildTests",
      dependencies: ["CrossXcodeBuild"]
    ),
  ]
  products += [
    .library(name: "CrossXcodeBuild", targets: ["CrossXcodeBuild"]),
    .executable(name: "xcodebuild", targets: ["CrossXcodeBuildCLI"]),
  ]
}

#if os(macOS)
let buildCounter = !buildForAndroid && !buildForHarmony
#else
let buildCounter = buildForWeb || buildDesktopNative
#endif
if buildCounter {
  targets.append(
    .executableTarget(
      name: "Counter",
      dependencies: counterDependencies,
      path: "Examples/Counter",
      exclude: ["AndroidCounterHost.swift"],
      linkerSettings: [
        // The WASI linker defaults to a 64 KiB stack. Debug view evaluation can
        // exceed it before the first frame has been mounted.
        .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=16777216"], .when(platforms: [.wasi]))
      ]
    )
  )
  products.append(.executable(name: "Counter", targets: ["Counter"]))
}
targets.append(
  .testTarget(
    name: "SwiftUIRuntimeTests",
    dependencies: ["SwiftUIRuntime"]
  )
)
let package = Package(
  name: "CrossSwiftUI",
  platforms: [.macOS(.v14)],
  products: products,
  dependencies: packageDependencies,
  targets: targets,
  cxxLanguageStandard: .cxx17
)
