# Android backend

**Unofficial; not affiliated with Apple.**

English | [简体中文](./ANDROID-ZH.md)

SwiftUI view and app sources compile for Android against CrossSwift's `SwiftUI`
facade (`SwiftUIRuntime` + `SwiftUIAndroid`). `SwiftUIRuntime` owns view
evaluation, `@State` / `@Observable` tracking, layout, and `NodeID` identity in
Swift, while `SwiftUIAndroid` (`AndroidHost` + `CSwiftUIAndroid`) bridges layout
snapshots and user interactions over JNI to Jetpack Compose (`SwiftUIComposeHost`
and `AndroidStyleRenderers`).

```text
SwiftUI view → SwiftUIRuntime → SwiftUIAndroid (AndroidHost) → JNI → SwiftUIComposeHost (Compose)
                     ↑                                                        │
                     └──────── taps, text, selection, scroll & back ──────────┘
```

## Package graph & build workflows

Because SwiftPM evaluates `Package.swift` on the build host, Android builds
select an isolated SwiftPM graph with `CROSS_SWIFTUI_ANDROID=1` (building
`SwiftUIRuntime`, `SwiftUIRuntimeMacros`, `CSwiftUIAndroid`, `SwiftUIAndroid`,
and `SwiftUI` without desktop `NativeAPI` or WebAssembly dependencies) using the
[official Swift SDK for Android][swift-sdk].

Two build workflows are supported:

1. **Unmodified `.xcodeproj` via `CrossXcodeBuild` (`xcodebuild`)**:
   `AndroidBuilder` cross-compiles the app target for `arm64-v8a` (and optional
   `x86_64`), strips native `.so` binaries, bundles `libc++_shared.so` and
   compiled `.xcassets` / `.xcstrings` resources, generates a Jetpack Compose
   `MainActivity.kt` wired to `_crossSwiftAndroidCreate`, and invokes Gradle to
   stage `<ProductName>.apk`:
   ```bash
   swift run xcodebuild \
     -project Examples/MobileUIGallery/MobileUIGallery.xcodeproj \
     -scheme MobileUIGallery \
     -configuration Release \
     -destination generic/platform=Android \
     -derivedDataPath build clean build
   ```
2. **Standalone Gradle integration**:
   Embed `AndroidHost` inside a custom Kotlin Activity, as demonstrated in
   [`Examples/AndroidCounter`](../Examples/AndroidCounter/README.md) (including
   its `verify-counter.py` UI Automator smoke test).

## Dual-style rendering (`AndroidUIStyle`)

`SwiftUIComposeHost` supports two visual and navigation styles from the same
Swift view tree, selectable at launch via `ANDROID_UI_STYLE=android|ios` (defaulting
to `ios` when the Xcode project's `SDKROOT` targets iPhoneOS, and `android`
otherwise) and toggleable live when `ANDROID_STYLE_SWITCHER=YES`:

- **Android Native (`AndroidUIStyle.ANDROID_NATIVE`)**: renders semantic controls
  with Jetpack Compose Material 3 (`Button`, `Switch`, `Slider`, `OutlinedTextField`,
  `CircularProgressIndicator` / `LinearProgressIndicator`, `ListItem`, Material
  menus/dialogs/bottom sheets) and drives `NavigationStack` transitions through
  Jetpack Navigation Compose `NavHost` with Android system back handling and
  edge-to-edge system bar insets.
- **iOS Liquid Glass (`AndroidUIStyle.IOS`)**: renders iOS 27-inspired translucent
  glass bars, grouped inset lists, switches, segmented/menu pickers, steppers,
  sheets, alerts, and navigation transitions in Compose while retaining Android
  touch, IME, and accessibility integration.

## Capabilities & host integration

- **Typography & layout**: Compose `TextMeasurer` measures fonts using the active
  density so `SwiftUIRuntime`'s layout frames match Compose text rendering; a
  custom Compose `Layout` positions children in pixel coordinates while keying
  composables by `NodeID`.
- **Controls & containers**: `Text`, `Button` (plain, bordered, prominent, and
  custom `ButtonStyle` hit areas), `TextField`, `SecureField`, multiline
  `TextEditor`, keyboard submit (`onSubmit`), `Toggle`, `Slider`, `Stepper`,
  `Picker`, `Menu`, `ProgressView`, `List`, `Form`, `Section`, `ScrollView`
  (vertical/horizontal plus `ScrollViewProxy.scrollTo`), `NavigationStack` /
  `NavigationPath`, `NavigationLink`, `TabView`, `DisclosureGroup`, `Gauge`,
  `DatePicker`, `ColorPicker`, `AsyncImage`, `Table`, `.sheet`,
  `.confirmationDialog`, and `.alert`.
- **Graphics, animations & assets**: shapes, rounded corners, borders,
  `graphicsLayer` rotation/scale transforms, drop shadows, custom vector clip
  paths, `.blur`, true linear/radial/angular gradients, raster images from
  bundled `Resources/`, and multi-layer vector paths (SF Symbols, `.xcassets`
  imagesets, and PDF/SVG vectors).
- **Async updates, animations & host integration**: `CSwiftUIAndroid` provides a
  thread-safe `JavaVM` bridge (`scheduleAsyncRender` and `openURL`) so `.task`,
  `Timer`, `AsyncImage`, and `@Observable` mutations push snapshots back to the
  Android main `Looper` automatically, while a `Choreographer` frame loop
  drives active `SwiftUIRuntime` animations. System dark mode (`isSystemInDarkTheme`)
  synchronizes `EnvironmentValues.colorScheme`, `OpenURLAction` launches
  `ACTION_VIEW` intents, and `AndroidHost` releases the Swift `Renderer` from
  `Activity.onDestroy` (`AutoCloseable`). `@State` is scoped to the mounted host
  instance across recompositions.

See [`skills/xcodebuild/references/platforms.md`](../skills/xcodebuild/references/platforms.md)
for all Android build settings (`ANDROID_ABIS`, `ANDROID_API_LEVEL`,
`SWIFT_ANDROID_SDK`, `ANDROID_UI_STYLE`, `ANDROID_STYLE_SWITCHER`) and
[DIVERGENCES.md](DIVERGENCES.md) for runtime behavioral limits.

[swift-sdk]: https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html
