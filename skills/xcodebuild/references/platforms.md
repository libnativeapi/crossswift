# CrossXcodeBuild Platform & Settings Reference

## Environment variables & build settings

Build settings can be supplied as `KEY=VALUE` CLI arguments or via `-xcconfig <file>`.
When both a build setting and an environment variable exist, the build setting takes precedence.

### General / path overrides

| Variable / Setting | Kind | Purpose |
| --- | --- | --- |
| `CROSS_SWIFTUI_PATH` | env (or `--crossswift-path`) | Path to the `crossswift` repository root (must contain `Package.swift` and `Sources/CrossSwiftUI`). |
| `NATIVEAPI_SWIFT_PATH` | env (or `--nativeapi-path`) | Path to `nativeapi/bindings/swift` (must contain `Package.swift` and `Sources/CNativeAPI/core/src`). Required for Windows, Linux, and HarmonyOS; not required for Wasm or Android. |
| `SWIFT_TOOLCHAIN_BIN` | env | Directory containing `swift` / `swiftc` to prefer over `swiftly` and `PATH` for Wasm, HarmonyOS, and Android cross-compiles. |
| `SYMROOT` | build setting | Override `<derivedDataPath>/Build/Products`. |
| `CONFIGURATION_BUILD_DIR` | build setting | Override `<SYMROOT>/<Configuration>` staging parent directory. |
| `CROSS_SWIFTUI_CONSOLE_SUBSYSTEM` | build setting (`YES`) | Same as `--console`: keep Windows console subsystem instead of `/SUBSYSTEM:WINDOWS`. |

### WebAssembly (`-destination generic/platform=Wasm` / `-sdk wasm|web|wasi`)

- **Host**: macOS or Linux.
- **Prerequisites**: Swift.org 6.4.2+ toolchain (or `swiftly`), matching Swift Wasm SDK, and `npm`.
  ```bash
  swift sdk install https://download.swift.org/swift-6.4.2-release/wasm-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_wasm.artifactbundle.tar.gz \
    --checksum 83baca83553f8c443cda7b84800912e6e709c3acd2e7ebf277794ca5836c0da5
  ```
- **Settings / env**:
  - `SWIFT_WASM_SDK` (build setting or env): Explicit Swift SDK ID (default: auto-detects `swift-6.4.2-RELEASE_wasm` or first non-embedded `*_wasm` SDK).
  - `SWIFT_WASM_TOOLCHAIN` (env): `swiftly` toolchain version (default: `6.4.2`).
- **Staged layout** (`<BUILT_PRODUCTS_DIR>/<ProductName>/`):
  - `index.html`
  - `app/<ExecutableName>.wasm`, `app/index.js`, `app/node_modules/@bjorn3/browser_wasi_shim/`
  - `Resources/` (including `web-manifest.json`)

### HarmonyOS (`-destination generic/platform=HarmonyOS` / `-sdk harmonyos|ohos`)

- **Host**: macOS or Linux.
- **Architecture**: `arm64-v8a` (`aarch64-swift-linux-musl`, configurable via `HARMONY_ABIS`).
- **Prerequisites**: Swift 6.4.2 `swiftc`, ARM64 Swift Static Linux SDK (`musl-1.2.5.sdk/aarch64`), and `nativeapi/bindings/swift`. DevEco Studio is optional — when present, `ohpm` + `hvigorw` run automatically to produce `<ProductName>.hap`.
- **Settings / env**:
  - `SWIFT_STATIC_LINUX_SDK` (env): Path to the Static Linux SDK artifact bundle or `.../musl-1.2.5.sdk/aarch64` (also searched under `~/Library/org.swift.swiftpm/swift-sdks` and `~/.swiftpm/swift-sdks`).
  - `DEVECO_STUDIO_HOME` (env): Path to DevEco Studio `Contents` directory (default fallback on macOS: `/Applications/DevEco-Studio.app/Contents`).
  - `HARMONY_SDK_VERSION` (build setting or env): Target/compile SDK version in `build-profile.json5` (default: `6.0.2(22)`).
  - `HARMONY_COMPATIBLE_SDK_VERSION` (build setting or env): Compatible SDK version (default: `6.0.2(22)`).
  - `HARMONY_ABIS` (build setting or env): Comma- or space-separated ABIs for `externalNativeOptions` (default: `arm64-v8a`).
  - `HARMONY_UI_STYLE` (build setting or env): Initial UI style — `harmony` or `ios` (default: `harmony`, or `ios` when `SDKROOT` contains `iphone`).
- **Staged layout** (`<BUILT_PRODUCTS_DIR>/<ProductName>/`):
  - `runtime/` (`NativeAPI.o`, `SwiftUIRuntime.o`, `SwiftUIHarmony.o`, `SwiftUI.o`, adapted SwiftPM package `.o` files, `<ExecutableName>.o`, static musl archives)
  - Stage-model HarmonyOS project (`AppScope/`, `entry/src/main/cpp/`, `entry/src/main/ets/` using `Sources/SwiftUIHarmony/ArkTS/CrossSwiftUIHost.ets`, `entry/src/main/resources/rawfile/Resources/` extracted at startup)
  - `<ProductName>.hap` (unsigned, copied from `entry/build/default/outputs/default/entry-default-unsigned.hap` when DevEco Studio is found)

### Android (`-destination generic/platform=Android` / `-sdk android`)

- **Host**: macOS or Linux.
- **Prerequisites**: Swift SDK for Android (e.g. `swift-6.4.2-RELEASE_android`), Android NDK (with `llvm-strip`), Android SDK, and JDK 17.
- **Settings / env**:
  - `ANDROID_ABIS` (build setting or env): Comma- or space-separated ABIs. Supported: `arm64-v8a`, `x86_64` (default: `arm64-v8a`).
  - `ANDROID_API_LEVEL` (build setting): Target Android API level for `--triple` (default: `23`).
  - `SWIFT_ANDROID_SDK` (build setting or env): Explicit Swift Android SDK ID (default: auto-detects `swift-6.4.2-RELEASE_android` or first `*_android` SDK).
  - `SWIFTUI_ANDROID_SDKS_PATH` (build setting or env): Extra `--swift-sdks-path` directory.
  - `SWIFT_ANDROID_TOOLCHAIN` (env): `swiftly` toolchain version (default: `6.4.2`).
  - `ANDROID_HOME` / `ANDROID_SDK_ROOT` (env): Android SDK root (fallback: `~/Library/Android/sdk`, `~/Android/Sdk`).
  - `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` (env): Android NDK root (fallback: newest NDK under `<ANDROID_HOME>/ndk` or `<crossswift>/.build/android-tools`).
  - `ANDROID_UI_STYLE` (build setting or env): Initial UI style — `ios` or `android` (defaults to `ios` if `SDKROOT` contains `iphone`, else `android`).
  - `ANDROID_STYLE_SWITCHER` (build setting or env): `YES` (default) or `NO` to show/hide the runtime style switcher.
- **Staged layout** (`<BUILT_PRODUCTS_DIR>/<ProductName>/`):
  - Gradle project (`app/`, `gradlew`, `app/src/main/jniLibs/<abi>/lib<ExecutableName>.so`, `libc++_shared.so`, `app/src/main/assets/Resources/`, Jetpack Compose `MainActivity.kt`)
  - `<ProductName>.apk`

### Windows & Linux native builds

- **Windows**: Runs `swift build --build-system native` (plus `-ffunction-sections`/`-fdata-sections` in Release), compiles `AppIcon.ico` + `AppResources.rc`, strips Release binaries if `llvm-strip`/`strip` is present, and scans PE imports to bundle runtime `.dll`s alongside `<ExecutableName>.exe`.
- **Linux**: Runs `swift build`, strips Release binaries if possible, collects runtime `.so` dependencies into `lib/` with `$ORIGIN/lib` RPATH, and emits a `.desktop` entry plus `icons/hicolor/<size>x<size>/apps/<bundleId>.png`.

## Accepted Apple-compatibility flags

For drop-in compatibility with existing CI scripts, the parser silently accepts
these Apple `xcodebuild` flags without error:

- **Valued flags**: `-clonedSourcePackagesDirPath`, `-scmProvider`,
  `-destinationTimeout`, `-resultBundlePath`, `-jobs` (and `-jobs=...`),
  `-toolchain`, `-exportOptionsPlist`, `-exportPath`, `-archivePath`
- **Boolean flags**: `-skipPackagePluginValidation`, `-skipMacroValidation`,
  `-allowProvisioningUpdates`, `-allowProvisioningDeviceRegistration`,
  `-parallelizeTargets`, `-hideShellScriptEnvironment`,
  `-showBuildTimingSummary`, `-disableAutomaticPackageResolution`,
  `-onlyUsePackageResolved`, `-skipUnavailableActions`,
  `-enableAddressSanitizer`, `-enableThreadSanitizer`,
  `-enableUndefinedBehaviorSanitizer`, `-UseModernBuildSystem` (and
  `-UseModernBuildSystem=...`)

## Automatic framework mapping & asset synthesis

- **Imported Apple frameworks** automatically mapped to products of the
  `crossswift` (`Package(name: "CrossSwiftUI")`) SwiftPM package on desktop
  platforms: `SwiftUI`, `AppKit`, `UIKit`, `QuartzCore`, `CrossFoundation`,
  `CoreFoundation`, `Darwin`, `ApplicationServices`, `ServiceManagement`,
  `Security`, `CloudKit`, `EventKit`, `AVFoundation`, `AVKit`, `CoreAudio`,
  `AudioToolbox`, `CoreMedia`, `CoreServices`, `CoreText`, `ImageIO`,
  `ColorSync`, `PDFKit`, `QuickLookUI`, `QuickLookThumbnailing`, `Network`,
  `SystemConfiguration`, `AuthenticationServices`, `JavaScriptCore`, `IOKit`,
  `Compression`, `System`, `AppleArchive`, `Accelerate`, `notify`,
  `CommonCrypto`, `FoundationModels`, `NaturalLanguage`, `Translation`,
  `Combine`, `CoreGraphics`, `Carbon`, `CryptoKit`, `OSLog`, `os`,
  `UniformTypeIdentifiers`, `SQLite3`.
  (On Wasm and Android, only `SwiftUI` and `SwiftUIRuntime` are linked from
  the package.)
- **Darwin-only packages**: Local Darwin-only packages and conditionally
  imported Darwin binary packages (such as `Sparkle`) are omitted automatically.
- **Resources**: Synthesizes `Info.plist`, `GeneratedAssetSymbols.swift`,
  `.colorset` / `.imageset` / `.xcstrings` runtime assets, Windows `.ico`/`.rc`,
  and Linux `.desktop` + `hicolor` PNG icons.
