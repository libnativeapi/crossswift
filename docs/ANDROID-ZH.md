# Android 后端

**非官方实现；与 Apple 无关。**

[English](./ANDROID.md) | 简体中文

SwiftUI 视图与应用源码可直接针对 CrossSwift 的 `SwiftUI` 门面模块（`SwiftUIRuntime` + `SwiftUIAndroid`）交叉编译为 Android 原生库。`SwiftUIRuntime` 在 Swift 侧负责视图求值、`@State` / `@Observable` 状态追踪、布局计算与 `NodeID` 身份维护；`SwiftUIAndroid`（`AndroidHost` + `CSwiftUIAndroid`）则通过 JNI 将布局快照与用户交互桥接至 Jetpack Compose（`SwiftUIComposeHost` 与 `AndroidStyleRenderers`）。

```text
SwiftUI 视图 → SwiftUIRuntime → SwiftUIAndroid (AndroidHost) → JNI → SwiftUIComposeHost (Compose)
                     ↑                                                        │
                     └───────── 点击、文本输入、选择、滚动与返回键 ──────────────┘
```

## 包依赖图与构建方式

由于 SwiftPM 在构建宿主机上求值 `Package.swift`，Android 构建通过 `CROSS_SWIFTUI_ANDROID=1` 选择独立的 SwiftPM 依赖图（仅构建 `SwiftUIRuntime`、`SwiftUIRuntimeMacros`、`CSwiftUIAndroid`、`SwiftUIAndroid` 与 `SwiftUI`，不解析桌面端 `NativeAPI` 或 WebAssembly 依赖），并配合 [官方 Swift SDK for Android][swift-sdk] 交叉编译。

支持以下两种构建工作流：

1. **通过 `CrossXcodeBuild`（`xcodebuild`）直接构建未修改的 `.xcodeproj`**：
   `AndroidBuilder` 会自动为 `arm64-v8a`（及可选 `x86_64`）交叉编译应用 Target，裁剪原生 `.so` 符号，打包 `libc++_shared.so` 与编译后的 `.xcassets` / `.xcstrings` 资源，生成接入 `_crossSwiftAndroidCreate` 的 Jetpack Compose `MainActivity.kt`，并调用 Gradle 产出 `<ProductName>.apk`：
   ```bash
   swift run xcodebuild \
     -project Examples/MobileUIGallery/MobileUIGallery.xcodeproj \
     -scheme MobileUIGallery \
     -configuration Release \
     -destination generic/platform=Android \
     -derivedDataPath build clean build
   ```
2. **独立 Gradle 工程集成**：
   在自定义 Kotlin `Activity` 中直接嵌入 `AndroidHost`，具体构建命令与 `verify-counter.py` UI Automator 冒烟测试详见 [`Examples/AndroidCounter`](../Examples/AndroidCounter/README-ZH.md)。

## 双风格实时渲染（`AndroidUIStyle`）

`SwiftUIComposeHost` 支持基于同一棵 Swift 视图树呈现两种视觉与导航风格，可在启动时通过 `ANDROID_UI_STYLE=android|ios` 指定（当 Xcode 工程 `SDKROOT` 指向 iPhoneOS 时默认为 `ios`，否则默认为 `android`），也可在 `ANDROID_STYLE_SWITCHER=YES` 时在运行时实时切换：

- **Android 原生风格（`AndroidUIStyle.ANDROID_NATIVE`）**：将语义控件映射为 Jetpack Compose Material 3 原生组件（`Button`、`Switch`、`Slider`、`OutlinedTextField`、`CircularProgressIndicator` / `LinearProgressIndicator`、`ListItem`、Material 菜单/对话框/底部弹窗），并通过 Jetpack Navigation Compose `NavHost` 驱动 `NavigationStack` 页面转场、系统返回手势与边到边（Edge-to-Edge）系统栏安全区适配。
- **iOS Liquid Glass 风格（`AndroidUIStyle.IOS`）**：在 Compose 中绘制 iOS 27 风格的半透明玻璃导航栏/标签栏、内嵌分组列表、开关、分段/下拉选择器、步进器、底部卡片与弹窗，同时保留 Android 触控、输入法（IME）与无障碍语义集成。

## 支持能力与宿主集成

- **排版测量与布局**：Compose 侧通过 `TextMeasurer` 按当前屏幕密度测量真实字体尺寸并回传给 `SwiftUIRuntime`，确保 Swift 布局框与 Compose 文本渲染一致；自定义 Compose `Layout` 按像素坐标放置子节点并以 `NodeID` 作为键值复用组合项。
- **控件与容器**：支持 `Text`、`Button`（`plain`、`bordered`、`borderedProminent` 及自定义 `ButtonStyle` 点击热区）、`TextField`、`SecureField`、多行 `TextEditor`、键盘提交（`onSubmit`）、`Toggle`、`Slider`、`Stepper`、`Picker`、`Menu`、`ProgressView`、`List`、`Form`、`Section`、`ScrollView`（纵向/横向及 `ScrollViewProxy.scrollTo`）、`NavigationStack` / `NavigationPath`、`NavigationLink`、`TabView`、`DisclosureGroup`、`Gauge`、`DatePicker`、`ColorPicker`、`AsyncImage`、`Table`、`.sheet`、`.confirmationDialog` 与 `.alert`。
- **图形、动画与资源**：支持几何形状、圆角、边框、`graphicsLayer` 旋转/缩放变换、投影阴影、自定义矢量裁剪路径、`.blur`、线性/径向/角度渐变、打包在 `Resources/` 中的位图，以及多层矢量路径（SF Symbols、`.xcassets` 图像集与 PDF/SVG 矢量图）。
- **异步更新、动画与宿主集成**：`CSwiftUIAndroid` 提供线程安全的 `JavaVM` 桥接（`scheduleAsyncRender` 与 `openURL`），使 `.task`、`Timer`、`AsyncImage` 与 `@Observable` 变更能够自动向 Android 主线程 `Looper` 推送最新快照，并由 `Choreographer` 帧循环驱动 `SwiftUIRuntime` 动画。系统深浅色模式（`isSystemInDarkTheme`）实时同步至 `EnvironmentValues.colorScheme`，`OpenURLAction` 拉起系统 `ACTION_VIEW` Intent，`AndroidHost` 在 `Activity.onDestroy`（`AutoCloseable`）时释放底层 Swift `Renderer`。`@State` 状态在当前挂载宿主实例生命周期内跨 Compose 重组保持。

完整的 Android 构建设置（`ANDROID_ABIS`、`ANDROID_API_LEVEL`、`SWIFT_ANDROID_SDK`、`ANDROID_UI_STYLE`、`ANDROID_STYLE_SWITCHER`）请参见 [`skills/xcodebuild/references/platforms.md`](../skills/xcodebuild/references/platforms.md)，运行时行为边界请参见 [DIVERGENCES-ZH.md](DIVERGENCES-ZH.md)。

[swift-sdk]: https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html
