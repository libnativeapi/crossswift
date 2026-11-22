# CrossSwift

**Unofficial; not affiliated with Apple.**

English | [简体中文](./README-ZH.md)

CrossSwift (`crossswift`) is an independent Apple-framework compatibility layer
and `xcodebuild`-compatible build toolchain that compiles SwiftUI, AppKit, and
UIKit applications — including unmodified macOS/iOS `.xcodeproj` projects — for
**Windows, Linux, WebAssembly, HarmonyOS, and Android**, while letting Apple
platform builds compile natively against Apple's SDKs.

- **Windows & Linux desktop**: `CrossSwiftUI`, `CrossAppKit`, and `CrossUIKit`
  render views and host windows, scenes, menus, status items, Auto Layout view
  hierarchies, and native text controls over
  [nativeapi](https://github.com/libnativeapi/nativeapi), backed by
  `CrossFoundation` and Apple framework shims.
- **WebAssembly**: `SwiftUIWeb` mounts apps in the browser DOM using
  JavaScriptKit and native HTML controls.
- **Android**: `SwiftUIAndroid` connects the shared runtime over JNI to Jetpack
  Compose, supporting live switching between Material 3 + Navigation Compose and
  iOS 27 Liquid Glass styling.
- **HarmonyOS**: `SwiftUIHarmony` and `CrossXcodeBuild` (`HarmonyBuilder`)
  cross-compile ARM64 Swift static objects (with `SwiftUIRuntimeMacros` and
  adapted SwiftPM packages) against `NativeAPI` and package a Stage-model ArkUI
  HAP with dual HarmonyOS Native / iOS Liquid Glass styling.

```swift
import SwiftUI

@main
struct CounterApp: App {
  var body: some Scene {
    WindowGroup("Counter") {
      CounterView()
    }
  }
}

struct CounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(spacing: 12) {
      Spacer()
      Text("Count: \(count)")
      HStack(spacing: 8) {
        Button("Increment") {
          count += 1
        }
        Button("Reset") {
          count = 0
        }
      }
      Spacer()
    }
    .padding(24)
  }
}
```

That program is checked in as [`Examples/Counter`](Examples/Counter/CounterApp.swift).
The same view source builds for Windows, Linux, WebAssembly, and Android, while
macOS builds compile it directly against Apple's `SwiftUI`.

## Modules

The root [`Package.swift`](Package.swift) retains the SwiftPM manifest name
`CrossSwiftUI` for downstream dependency compatibility. Inside the repository,
responsibilities are split cleanly across distinct modules:

| Module | Role |
| --- | --- |
| `SwiftUIRuntime` + `SwiftUIRuntimeMacros` | Platform-independent SwiftUI engine: `View`, `@ViewBuilder`, element tree, layout (with `Spacer.minLength`, `.layoutPriority`, layout-preserving `.hidden()`, and `Lazy*` virtualization), sibling diff, `@State` / `@AppStorage` / `@SceneStorage` / `@Binding` / `@Environment` / `@FocusState` / `@FocusedValue`, `@Observable` (`@Bindable`) and `ObservableObject`, `@Entry` & `#Preview` macros, controls (`DisclosureGroup`, `Gauge`, `DatePicker`, `ColorPicker`, `AsyncImage`, `Table`, `ShareLink`, `.fileImporter`/`.fileExporter`), navigation (`NavigationPath`), presentations, SVG/PDF vectors, SF Symbols, `.xcstrings` localization, rich `Canvas`, linear/radial/angular gradients, timed `LongPressGesture`, and color/transition/layout animations. Has no `NativeAPI` dependency, so `SwiftUIRuntimeTests` runs on macOS, Windows, and Linux. |
| `CrossSwiftUI` (+ `CSwiftUIWindows`) | Desktop `NativeAPI` SwiftUI backend for **Windows** (DirectWrite text, retained GDI+ display list, offscreen layers & blur/brightness/contrast filters, native buttons, transparent matte-composited `EDIT` controls) and **Linux** (GTK 3 drawing area with Cairo/Pango, offscreen filters, and native GTK/ATK controls), multi-scene `App` / `WindowGroup` / `Window` / `Settings` / `Scene.commands` / `MenuBarExtra` (`.menu` & `.window`) runner, and AppKit/UIKit hosting (`NSHostingView`, `NSHostingController`, `NSViewRepresentable`, `NSApplicationDelegateAdaptor`, `_UIHostingView`, `UIHostingController`, `UIHostingConfiguration`, `UIViewRepresentable`, `UIViewControllerRepresentable`, `UIApplicationDelegateAdaptor`). |
| `SwiftUIWeb` | WebAssembly (`os(WASI)`) DOM/SVG/CSS renderer (dark-mode sync, `openURL`, `scrollTo`, filters, gradients, multi-layer vectors), `WindowGroup` browser runner, and web `.xcassets` / `.xcstrings` / SF Symbol loader. |
| `SwiftUIAndroid` (+ `CSwiftUIAndroid`) | Android thread-safe JNI async bridge (`AndroidHost`), `Choreographer` animation loop, dark-mode & `openURL` sync, and Jetpack Compose host (`SwiftUIComposeHost`), with dual Material 3 and iOS Liquid Glass renderers. |
| `SwiftUIHarmony` | Formal HarmonyOS runtime backend (`HarmonyBackend`) and ArkTS Stage-model host (`CrossSwiftUIHost.ets`) with async render push, 60 Hz animation ticks, dark-mode sync, and dual HarmonyOS / iOS Liquid Glass styling. |
| `SwiftUI` | User-facing `import SwiftUI` facade on non-Apple targets, re-exporting `SwiftUIRuntime` together with the active platform backend (`CrossSwiftUI` + `CrossAppKit` + `CrossUIKit` + `CrossFoundation` + `CoreGraphics` on Windows/Linux, `SwiftUIWeb` on WASI, `SwiftUIAndroid` on Android, or `SwiftUIHarmony` on HarmonyOS). |
| `CrossAppKit` + `AppKit` (+ `CAppKitWindows`) | Cross-platform AppKit implementation (`NSApplication`, `NSWindow`, `NSPanel`, `NSView`, controls, TextKit 1/2, `NSMenu`, `NSStatusItem`, `NSPasteboard`, `NSWorkspace`, `NSColor`, `NSAppearance`, `NSFont`, `NSImage`, `NSBezierPath`, Carbon hotkey bridge). Re-exported as `import AppKit` on Windows and Linux; `CrossAppKit` also builds standalone on macOS for `CrossAppKitTests`. |
| `CrossUIKit` + `UIKit` | Cross-platform UIKit implementation (`UIApplication`, `UIApplicationDelegate`, `UIWindowScene`, `UIWindow`, `UIResponder`, `UIView` + Auto Layout anchor solver & `UIStackView`, `UIControl` + `UIAction` + `UIMenu`, `UILabel` / `UIButton` / `UITextField` / `UITextView` / `UIScrollView`, `UITableView` & `UICollectionView` + diffable data sources, `UIViewController` / `UINavigationController` / `UITabBarController` / `UIAlertController`, `UITraitCollection`, dynamic `UIColor`, `UIFont` & `UIFontMetrics`, `UIImage` + `UIGraphicsImageRenderer` + `UIBezierPath`, `UIPasteboard`, `UIScreen`, `UIDevice`, gesture recognizers, and haptic feedback shims). Re-exported as `import UIKit` on Windows and Linux; `CrossUIKit` also builds standalone on macOS for `CrossUIKitTests`. |
| `CrossFoundation` & Apple shims | Apple `Foundation` extensions missing from `swift-corelibs-foundation`, standalone framework shims (`CoreGraphics`, `Combine`, `CryptoKit`, `Carbon`, `UniformTypeIdentifiers`, `OSLog`, `os`, `SQLite3`), and 35 system/framework shims under `Sources/AppleShims/` (`QuartzCore`, `CoreFoundation`, `Darwin`, `ApplicationServices`, `ServiceManagement`, `Security`, `CoreText`, `ImageIO`, `JavaScriptCore`, `IOKit`, `Network`, `AVFoundation`, `AVKit`, `PDFKit`, etc.). |
| `CrossXcodeBuild` + `CrossXcodeBuildCLI` | Pure-Swift `.xcodeproj` / `.xcworkspace` parser, Apple-framework & SwiftPM dependency adapter, `.xcassets` / `.xcstrings` / icon compiler, and the cross-platform `xcodebuild` executable targeting Windows, Linux, WebAssembly, HarmonyOS, and Android. |

## What this is

CrossSwift preserves SwiftUI and AppKit authoring conventions — value views,
result builders, state and `@Observable` tracking, scoped environment,
modifiers, `WindowGroup` and `MenuBarExtra` scenes, AppKit windows/views, and
asset/localization catalogs — without coupling user code to platform-specific
APIs.

This is a **partial compatibility layer**. It contains no host application's
domain components, themes, or tokens. It is not Apple's source or renderer, and
does not promise pixel equality. Read [docs/COMPAT.md](docs/COMPAT.md) and
[docs/DIVERGENCES.md](docs/DIVERGENCES.md) before adopting an API.

## Requirements

- Swift 6.0 or newer on Linux/macOS, language mode 5 (`swift-tools-version:5.9`;
  `CrossXcodeBuild` also adapts Swift 6 language-mode app targets).
  Windows uses Swift 6.4.2 or newer: Swift 6.3.1 fails to link Foundation's
  `AttributedString.runs` ([swift#88132](https://github.com/swiftlang/swift/issues/88132)).
  The current Windows runners also require a modern Clang (or
  `-Xcxx -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH`) for the MSVC STL.
- A [nativeapi](https://github.com/libnativeapi/nativeapi) checkout with the
  Swift binding's platform support (required for Windows, Linux, and HarmonyOS;
  not required for macOS host tests, WebAssembly, or Android). The package
  consumes it as a **sibling path dependency** at `../nativeapi/bindings/swift`,
  or the path in `NATIVEAPI_SWIFT_PATH`:

  ```text
  Projects/
  ├── nativeapi/
  └── crossswift/
  ```

  Use the `nativeapi` revision pinned in [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
  or a newer compatible revision.
- Linux: `pkg-config`, `libgtk-3-dev`, `libsqlite3-dev`, `libx11-dev`, `libxi-dev`.
- Windows: the official Swift toolchain with the Visual Studio build tools and
  Windows SDK required by the Swift installer.

## Build and test

On macOS, `swift build` and `swift test` compile `SwiftUIRuntime`,
`CrossAppKit`, `CrossXcodeBuild` (`xcodebuild`), their test suites, and the
`Counter` example against **Apple's native SwiftUI** (CrossSwift's own `SwiftUI`
and `AppKit` facades are only built for non-Apple targets):

```bash
swift build
swift test
swift run Counter
```

Linux and Windows build the runtime, `CrossSwiftUI`, `CrossAppKit`,
`CrossFoundation` and framework shims, `CrossXcodeBuild`, and `Counter`:

```bash
swift build
swift test
swift run Counter
```

For the verified Windows source-build path (Swift 6.4.2, MSVC, and Windows SDK),
prepare `nativeapi`'s source symlink and use the SwiftPM native builder:

```powershell
$env:NATIVEAPI_SWIFT_PATH = 'C:/src/nativeapi/bindings/swift'
& "$env:NATIVEAPI_SWIFT_PATH/scripts/prepare-windows.ps1"
swift build --build-system native
swift test --build-system native
swift run --build-system native Counter --smoke
```

Enable Windows Developer Mode if Git checked the `core` symlink out as a text
file, and initialize `nativeapi`'s `core` submodule first.

On Windows and Linux, `swift run Counter --smoke` opens the window and asks
`CrossSwiftUI`'s app runner to quit after three seconds; CI uses it to verify
that the window, event loop, and renderer start cleanly.

## Build for the web

Use the Swift.org Swift 6.4.2 toolchain and matching
[Swift SDK for WebAssembly](https://www.swift.org/documentation/articles/wasm-getting-started.html)
on macOS or Linux, with Node.js and npm for packaging:

```bash
swift sdk install https://download.swift.org/swift-6.4.2-release/wasm-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum 83baca83553f8c443cda7b84800912e6e709c3acd2e7ebf277794ca5836c0da5
swift run xcodebuild \
  -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo \
  -configuration Release \
  -destination generic/platform=Wasm \
  -derivedDataPath build clean build
python3 -m http.server 8000 --directory build/Build/Products/Release/XcodeDemo
```

Open [localhost:8000](http://localhost:8000) to try `XcodeDemo`, or serve the
staged directory from any static HTTP host. Web builds require no `nativeapi`
checkout. See [docs/DIVERGENCES.md](docs/DIVERGENCES.md) for browser-specific
limits.

For a standalone SwiftPM Web package (without an `.xcodeproj`), depend on the
`SwiftUI` product from this package and JavaScriptKit's `PackageToJS` plugin, set
`CROSS_SWIFTUI_WEB=1` when invoking `swift package --swift-sdk <id> js`, and use
[Web/index.html](Web/index.html) as a host page.

## Build for Android

Unmodified `.xcodeproj` apps (such as [`Examples/MobileUIGallery`](Examples/MobileUIGallery/MobileUIGallery.xcodeproj)
and [`Examples/XcodeDemo`](Examples/XcodeDemo/XcodeDemo.xcodeproj)) can be built
directly into an APK with CrossSwift's `xcodebuild` CLI (`-destination generic/platform=Android`;
see below). For standalone Gradle integration, the
[Android Counter example](Examples/AndroidCounter/README.md) builds a multi-ABI
APK using `CROSS_SWIFTUI_ANDROID=1`, `SwiftUIAndroid`, and Jetpack Compose. See
[docs/ANDROID.md](docs/ANDROID.md) for the Android architecture, dual Material 3 /
iOS Liquid Glass rendering modes, and build settings.

## Build an `.xcodeproj` for Windows, Linux, Wasm, HarmonyOS & Android

CrossSwift provides a cross-platform **`xcodebuild`-compatible CLI**
(`CrossXcodeBuild` / `CrossXcodeBuildCLI`) that compiles unmodified macOS/iOS
`.xcodeproj` and `.xcworkspace` projects (classic groups or Xcode 16
synchronized folders) into self-contained Windows, Linux, WebAssembly,
HarmonyOS, or Android artifacts with zero platform-specific configuration in the
app project:

```bash
# List targets, configurations, and schemes (Apple-compatible text or JSON)
xcodebuild -list -json -project Examples/XcodeDemo/XcodeDemo.xcodeproj

# Inspect resolved build settings (supports KEY=VALUE overrides)
xcodebuild -showBuildSettings -json \
  -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -configuration Release -derivedDataPath build

# Compile and stage for the current desktop host (Windows or Linux)
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO clean build

# Cross-compile to WebAssembly from macOS or Linux (requires Swift Wasm SDK + npm)
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=Wasm \
  -derivedDataPath build clean build

# Cross-compile to HarmonyOS arm64-v8a from macOS or Linux (requires Static Linux ARM64 SDK)
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=HarmonyOS \
  -derivedDataPath build clean build

# Cross-compile and package an Android APK from macOS or Linux (requires Swift Android SDK + NDK + JDK 17)
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=Android \
  -derivedDataPath build clean build
```

> On macOS, `/usr/bin/xcodebuild` is Apple's Xcode tool; invoke CrossSwift's CLI
> via `swift run xcodebuild ...` (or its built binary path).

When invoked, `CrossXcodeBuild`:

- Parses `project.pbxproj` (plus `.xcworkspace`, `.xcconfig`,
  `Package.resolved`, and `Info.plist` keys) in pure Swift with no Xcode
  dependency.
- Maps imported Apple frameworks (`SwiftUI`, `AppKit`, `CryptoKit`, `Combine`,
  `CoreGraphics`, `SQLite3`, and `AppleShims` modules) to products of the
  `CrossSwiftUI` SwiftPM package, adapts local SwiftPM dependencies, and omits
  Darwin-only conditional packages.
- Synthesizes `Info.plist`, `GeneratedAssetSymbols.swift`, `.colorset` /
  `.imageset` / PDF vector / `.xcstrings` runtime assets, multi-size Windows
  `AppIcon.ico` + Win32 manifest/version resource (`AppResources.rc`), and Linux
  `.desktop` + `hicolor` PNG icons.
- Stages a self-contained output directory at
  `<CONFIGURATION_BUILD_DIR>/<ProductName>/` (defaulting to
  `<derivedDataPath>/Build/Products/<Configuration>/<ProductName>/`):
  - **Windows / Linux**: native executable, `Resources/`, Windows runtime `.dll`s
    (via PE import scanning) or Linux runtime `.so`s (via `ldd` + `$ORIGIN/lib`
    RPATH) + `.desktop` + `hicolor` icons.
  - **Wasm** (`-destination generic/platform=Wasm` or `-sdk wasm`): static web
    bundle with `index.html`, `app/<Product>.wasm`, `app/index.js`,
    `app/node_modules/@bjorn3/browser_wasi_shim`, and `Resources/`.
  - **HarmonyOS** (`-destination generic/platform=HarmonyOS` or `-sdk ohos`):
    `runtime/` containing `aarch64-swift-linux-musl` object files
    (`NativeAPI.o`, `SwiftUIRuntime.o`, `SwiftUI.o`, `<Product>.o`) and static
    Swift/Foundation musl archives, plus a ready-to-assemble Stage-model
    HarmonyOS project (`AppScope/`, `entry/src/main/cpp/`, `entry/src/main/ets/`,
    `rawfile/Resources/`). When DevEco Studio is installed (`DEVECO_STUDIO_HOME`
    or `/Applications/DevEco-Studio.app/Contents`), `ohpm` + `hvigorw` run
    automatically to produce `<ProductName>.hap`.
  - **Android** (`-destination generic/platform=Android` or `-sdk android`):
    self-contained Gradle Android project (`app/`, `gradlew`,
    `jniLibs/<abi>/lib<Product>.so`, `libc++_shared.so`, `assets/Resources/`,
    Jetpack Compose `MainActivity.kt`) plus `<ProductName>.apk` (pass
    `ANDROID_ABIS=arm64-v8a,x86_64` for multi-ABI builds).

[`Examples/XcodeDemo`](Examples/XcodeDemo/XcodeDemo.xcodeproj) is an unmodified
macOS Xcode project that builds with Apple's `xcodebuild` on macOS and with
CrossSwift's `xcodebuild` for Windows, Linux, WebAssembly, HarmonyOS, and
Android. [`Examples/UIKitDemo`](Examples/UIKitDemo/UIKitDemo.xcodeproj) is an
unmodified iOS UIKit + SwiftUI `.xcodeproj` (`@main` `UIApplicationDelegate` +
`UIWindowSceneDelegate` + `UIHostingController` + `UIViewRepresentable` +
`UIViewControllerRepresentable` + Auto Layout) that builds for Windows and Linux
desktop via `xcodebuild`.

## Repository layout

```text
Sources/SwiftUIRuntime/       platform-independent SwiftUI engine (views, layout, diff, state)
Sources/SwiftUIRuntimeMacros/ compiler-plugin macros (@Entry, #Preview; no swift-syntax dep)
Sources/CrossSwiftUI/         desktop NativeAPI backends (Windows/Linux), runner, AppKit/UIKit hosting
Sources/CSwiftUIWindows/      Win32/GDI+ retained display list, text & control compositing bridge
Sources/CrossAppKit/          cross-platform AppKit views, windows, menus, TextKit & pasteboard
Sources/AppKit/               `import AppKit` facade for Windows and Linux
Sources/CrossUIKit/           cross-platform UIKit scenes, windows, views, Auto Layout & controls
Sources/UIKit/                `import UIKit` facade for Windows and Linux
Sources/CAppKitWindows/       Win32/DWM/Shell/COM/Accessibility C++ glue for CrossAppKit/UIKit & shims
Sources/CrossFoundation/      Apple Foundation extensions on Windows and Linux
Sources/AppleShims/           35 Apple system/framework compatibility modules (QuartzCore, CoreText, …)
Sources/{CoreGraphics,Combine,CryptoKit,Carbon,UniformTypeIdentifiers,OSLog,os,SQLite3}/
                              standalone Apple framework shims
Sources/SwiftUIWeb/           WebAssembly DOM renderer and browser app runner
Sources/SwiftUIAndroid/       Android JNI bridge and Jetpack Compose host (Material 3 / iOS style)
Sources/CSwiftUIAndroid/      C header glue for Android JNI entry points
Sources/SwiftUI/              `import SwiftUI` facade selecting the target platform backend
Sources/CrossXcodeBuild/      pure-Swift .xcodeproj parser, package adapter, asset compiler & driver
Sources/CrossXcodeBuildCLI/   cross-platform `xcodebuild` executable
Examples/Counter/             minimal SwiftPM counter shared across desktop, Web, and Android
Examples/XcodeDemo/           unmodified macOS .xcodeproj built for all five non-Apple targets
Examples/UIKitDemo/           unmodified iOS UIKit + UIHostingController .xcodeproj for Windows & Linux
Examples/DesktopUIGallery/    desktop SwiftUI component, layout, graphics & navigation gallery
Examples/MobileUIGallery/     mobile SwiftUI gallery (iOS, Android, HarmonyOS dual-style showcase)
Examples/{MenuBarDemo,NotesApp,MetricsDashboard,KanbanBoard}/
                              unmodified macOS .xcodeproj apps verified on macOS, Windows & Linux
Examples/AndroidCounter/      standalone Gradle + Swift Android SDK Activity example & smoke test
Examples/HarmonyRuntimeProbe/ HarmonyOS Stage-model Swift runtime & ArkUI gallery probe
Web/                          HTML host template for WebAssembly builds
Tests/SwiftUIRuntimeTests/    headless FakeBackend tests for layout, diff, state & COMPAT.md
Tests/CrossAppKitTests/       CrossAppKit geometry, appearance, font & asset resolution tests
Tests/CrossUIKitTests/        CrossUIKit traits, colors, graphics, Auto Layout & controller tests
Tests/CrossXcodeBuildTests/   .xcodeproj parser, loader, adapter & xcodebuild CLI tests
Tests/{Windows,Linux}DrawingTests/
                              platform backend drawing, shadow, scroll & editor integration tests
skills/xcodebuild/            agent skill for CrossSwift's `xcodebuild` CLI
docs/                         architecture, Android backend, compatibility table & divergences
```

## Design in one paragraph

A `SwiftUIRuntime` render pass evaluates view bodies under scoped environment,
state, and `@Observable` tracking, resolves inherited properties, lays out the
tree, hoists presentations, and diffs sibling identity. Platform backends
consume incremental commands and/or the reconciled element tree: `CrossSwiftUI`
publishes a retained GDI+ display list on Windows (`CSwiftUIWindows`) and paints
with Cairo/Pango in GTK 3 on Linux while bridging `CrossAppKit` views and
windows; `SwiftUIWeb` retains positioned DOM elements in the browser;
`SwiftUIAndroid` and the HarmonyOS ArkUI host map semantic controls and layout
frames to Jetpack Compose and ArkUI; and `FakeBackend` records commands for
deterministic headless tests. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Compatibility

- API status: [docs/COMPAT.md](docs/COMPAT.md)
- Known behavioral and visual gaps: [docs/DIVERGENCES.md](docs/DIVERGENCES.md)
- Architecture and update strategy: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Android backend and Compose integration: [docs/ANDROID.md](docs/ANDROID.md)

## License

MIT. See [LICENSE](LICENSE).
