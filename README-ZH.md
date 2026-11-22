# CrossSwift

**非官方实现；与 Apple 无关。**

[English](./README.md) | 简体中文

CrossSwift（`crossswift`）是一套独立的 Apple 框架兼容层与 `xcodebuild` 兼容构建工具链，可将 SwiftUI 与 AppKit 应用（包括未经修改的 macOS / iOS `.xcodeproj` 工程）编译到 **Windows、Linux、WebAssembly、HarmonyOS 与 Android**，同时让 Apple 平台继续直接使用 Apple 原生 SDK 编译。

- **Windows 与 Linux 桌面端**：`CrossSwiftUI` 与 `CrossAppKit` 基于 [nativeapi](https://github.com/libnativeapi/nativeapi) 渲染视图并承载窗口、菜单、状态栏图标与原生文本输入控件，底层辅以 `CrossFoundation` 及 Apple 框架垫片。
- **WebAssembly**：`SwiftUIWeb` 借助 JavaScriptKit 与原生 HTML 控件将应用挂载至浏览器 DOM。
- **Android**：`SwiftUIAndroid` 通过 JNI 将共享运行时接入 Jetpack Compose，支持在 Material 3 + Navigation Compose 与 iOS 27 Liquid Glass 视觉风格之间实时切换。
- **HarmonyOS**：`SwiftUIHarmony` 与 `CrossXcodeBuild`（`HarmonyBuilder`）基于 `NativeAPI` 交叉编译 ARM64 Swift 静态目标文件（含 `SwiftUIRuntimeMacros` 与远程 SwiftPM 包），并打包为支持 HarmonyOS 原生 / iOS Liquid Glass 双风格的 Stage 模型 ArkUI HAP。

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

以上示例位于 [`Examples/Counter`](Examples/Counter/CounterApp.swift)。同一份视图源码可直接编译运行于 Windows、Linux、WebAssembly 与 Android，而在 macOS 上则直接针对 Apple 原生 `SwiftUI` 编译。

## 模块划分

仓库根目录的 [`Package.swift`](Package.swift) 保留了 SwiftPM 包名 `CrossSwiftUI` 以兼容下游依赖清单；仓库内部按职责划分为清晰的独立模块：

| 模块 | 职责说明 |
| --- | --- |
| `SwiftUIRuntime` + `SwiftUIRuntimeMacros` | 平台无关的 SwiftUI 核心引擎：`View`、`@ViewBuilder`、元素树、布局引擎（含 `Spacer.minLength`、`.layoutPriority`、保留空间的 `.hidden()` 与 `Lazy*` 虚拟化）、兄弟节点 diff、`@State` / `@AppStorage` / `@SceneStorage` / `@Binding` / `@Environment` / `@FocusState` / `@FocusedValue`、`@Observable`（`@Bindable`）与 `ObservableObject`、`@Entry` 与 `#Preview` 宏、基础与扩展控件（`DisclosureGroup`、`Gauge`、`DatePicker`、`ColorPicker`、`AsyncImage`、`Table`、`ShareLink`、`.fileImporter`/`.fileExporter`）、导航（`NavigationPath`）、弹窗展示、SVG/PDF 矢量解析、内置 SF Symbols、`.xcstrings` 本地化、富 `Canvas`、线性/径向/角度渐变、定时 `LongPressGesture` 及颜色/转场/布局动画。不依赖 `NativeAPI`，因此 `SwiftUIRuntimeTests` 可在 macOS、Windows、Linux 上直接运行。 |
| `CrossSwiftUI`（及 `CSwiftUIWindows`） | 面向 **Windows**（DirectWrite 文本、保留式 GDI+ 显示列表、离屏图层与模糊/亮度/对比度滤镜、原生按钮、双通道遮罩透明合成 `EDIT` 文本框）与 **Linux**（GTK 3 绘图区、Cairo/Pango 渲染、离屏滤镜与原生 GTK/ATK 控件）的桌面端 `NativeAPI` SwiftUI 后端、多场景 `App` / `WindowGroup` / `Window` / `Settings` / `Scene.commands` / `MenuBarExtra`（`.menu` 与 `.window`）运行器，以及 AppKit 桥接托管（`NSHostingView`、`NSHostingController`、`NSViewRepresentable`、`NSApplicationDelegateAdaptor`）。 |
| `SwiftUIWeb` | WebAssembly（`os(WASI)`）DOM/SVG/CSS 渲染器（深浅色同步、`openURL`、`scrollTo`、滤镜、渐变与多层矢量）、`WindowGroup` 浏览器运行器，以及 Web 端 `.xcassets` / `.xcstrings` / SF Symbols 资源加载器。 |
| `SwiftUIAndroid`（及 `CSwiftUIAndroid`） | Android 线程安全 JNI 异步桥接层（`AndroidHost`）、`Choreographer` 动画循环、深浅色与 `openURL` 同步，以及 Jetpack Compose 宿主（`SwiftUIComposeHost`），内置 Material 3 与 iOS Liquid Glass 双风格渲染器。 |
| `SwiftUIHarmony` | 正式 HarmonyOS 运行时后端（`HarmonyBackend`）与 ArkTS Stage 模型宿主（`CrossSwiftUIHost.ets`），支持异步刷新推送、60 Hz 动画帧、深浅色同步与 HarmonyOS / iOS Liquid Glass 双风格渲染。 |
| `SwiftUI` | 非 Apple 平台面向用户的 `import SwiftUI` 门面模块，重导出 `SwiftUIRuntime` 与当前目标平台后端（Windows/Linux 下重导出 `CrossSwiftUI` + `CrossAppKit` + `CrossFoundation` + `CoreGraphics`，WASI 下重导出 `SwiftUIWeb`，Android 下重导出 `SwiftUIAndroid`，HarmonyOS 下重导出 `SwiftUIHarmony`）。 |
| `CrossAppKit` + `AppKit`（及 `CAppKitWindows`） | 跨平台 AppKit 实现（`NSApplication`、`NSWindow`、`NSPanel`、`NSView`、常用控件、TextKit 1/2、`NSMenu`、`NSStatusItem`、`NSPasteboard`、`NSWorkspace`、`NSColor`、`NSAppearance`、`NSFont`、`NSImage`、`NSBezierPath`、Carbon 全局热键桥接）。在 Windows 与 Linux 上通过 `import AppKit` 暴露；`CrossAppKit` 亦可在 macOS 上独立构建以运行 `CrossAppKitTests`。 |
| `CrossFoundation` 与 Apple 框架垫片 | 补齐 `swift-corelibs-foundation` 缺失的 Apple `Foundation` API，提供顶层独立框架垫片（`CoreGraphics`、`Combine`、`CryptoKit`、`Carbon`、`UniformTypeIdentifiers`、`OSLog`、`os`、`SQLite3`）以及 `Sources/AppleShims/` 下的 34 个系统/框架模块（`CoreFoundation`、`Darwin`、`ApplicationServices`、`ServiceManagement`、`Security`、`CoreText`、`ImageIO`、`JavaScriptCore`、`IOKit`、`Network`、`AVFoundation`、`PDFKit` 等）。 |
| `CrossXcodeBuild` + `CrossXcodeBuildCLI` | 纯 Swift 实现的 `.xcodeproj` / `.xcworkspace` 解析器、Apple 框架与 SwiftPM 依赖适配器、`.xcassets` / `.xcstrings` / 图标资源编译器，以及支持编译到 Windows、Linux、WebAssembly、HarmonyOS 与 Android 的跨平台 `xcodebuild` 命令行工具。 |

## 项目定位

CrossSwift 保留了 SwiftUI 与 AppKit 的开发模型：值类型视图、结果构建器（Result Builder）、状态与 `@Observable` 追踪、作用域环境（Environment）、修饰符、`WindowGroup` 与 `MenuBarExtra` 场景、AppKit 窗口/视图，以及资源与本地化目录，使业务代码无需耦合各平台底层 API。

本项目是**部分兼容层**，不包含任何宿主应用的业务组件、主题或设计令牌（Token）；它既非 Apple 源码亦非 Apple 渲染器，不承诺像素级一致。采用具体 API 前请先阅读 [docs/COMPAT-ZH.md](docs/COMPAT-ZH.md) 与 [docs/DIVERGENCES-ZH.md](docs/DIVERGENCES-ZH.md)。

## 环境要求

- Linux / macOS：Swift 6.0 及以上，语言模式为 Swift 5（`swift-tools-version:5.9`；`CrossXcodeBuild` 同样支持适配 Swift 6 语言模式的应用 Target）。
  Windows 需使用 Swift 6.4.2 及以上版本：Swift 6.3.1 在链接 Foundation 的 `AttributedString.runs` 时会失败（[swift#88132](https://github.com/swiftlang/swift/issues/88132)）；当前新版 MSVC STL 还需配合新版 Clang 或传入 `-Xcxx -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH`。
- 包含 Swift 绑定平台支持的 [nativeapi](https://github.com/libnativeapi/nativeapi) 检出目录（Windows、Linux 与 HarmonyOS 构建必需；macOS 宿主测试、WebAssembly 与 Android 构建无需此依赖）。默认作为**同级路径依赖**读取 `../nativeapi/bindings/swift`，也可通过环境变量 `NATIVEAPI_SWIFT_PATH` 指定：

  ```text
  Projects/
  ├── nativeapi/
  └── crossswift/
  ```

  请使用 [`.github/workflows/ci.yml`](.github/workflows/ci.yml) 中锁定的 `nativeapi` 提交或更新的兼容版本。
- Linux：`pkg-config`、`libgtk-3-dev`、`libsqlite3-dev`、`libx11-dev`、`libxi-dev`。
- Windows：官方 Swift 工具链，以及 Swift 安装器要求的 Visual Studio Build Tools 与 Windows SDK。

## 构建与测试

在 macOS 上，`swift build` 与 `swift test` 会编译 `SwiftUIRuntime`、`CrossAppKit`、`CrossXcodeBuild`（`xcodebuild`）及其测试套件，并直接基于 **Apple 原生 SwiftUI** 编译 `Counter` 示例（CrossSwift 自身的 `SwiftUI` 与 `AppKit` 门面仅在非 Apple 目标平台构建）：

```bash
swift build
swift test
swift run Counter
```

在 Linux 与 Windows 上，则会完整构建运行时、`CrossSwiftUI`、`CrossAppKit`、`CrossFoundation` 与各框架垫片、`CrossXcodeBuild` 以及 `Counter`：

```bash
swift build
swift test
swift run Counter
```

在已验证的 Windows 源码构建环境（Swift 6.4.2、MSVC 与 Windows SDK）下，先准备 `nativeapi` 的源码符号链接并使用 SwiftPM 原生构建器：

```powershell
$env:NATIVEAPI_SWIFT_PATH = 'C:/src/nativeapi/bindings/swift'
& "$env:NATIVEAPI_SWIFT_PATH/scripts/prepare-windows.ps1"
swift build --build-system native
swift test --build-system native
swift run --build-system native Counter --smoke
```

请先初始化 `nativeapi` 的 `core` 子模块；若 Git 将符号链接检出为普通文本文件，请开启 Windows 开发者模式或执行上述准备脚本转换为目录联接（Junction）。

在 Windows 与 Linux 上，`swift run Counter --smoke` 会打开窗口并在 3 秒后由 `CrossSwiftUI` 运行器自动退出，CI 用它验证窗口、事件循环与渲染器能够正常启动。

## 构建 WebAssembly 版本

在 macOS 或 Linux 上使用 Swift.org 的 Swift 6.4.2 工具链及匹配的 [Swift SDK for WebAssembly](https://www.swift.org/documentation/articles/wasm-getting-started.html)，并安装 Node.js 与 npm 用于打包：

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

打开 [localhost:8000](http://localhost:8000) 即可体验 `XcodeDemo`，也可将该目录直接部署至任意静态 HTTP 服务器。Web 构建不需要 `nativeapi` 检出目录。浏览器端的具体限制请参见 [docs/DIVERGENCES-ZH.md](docs/DIVERGENCES-ZH.md)。

若在无 `.xcodeproj` 的独立 SwiftPM Web 包中使用，请添加本包的 `SwiftUI` 产物与 JavaScriptKit 的 `PackageToJS` 插件依赖，在执行 `swift package --swift-sdk <id> js` 时设置 `CROSS_SWIFTUI_WEB=1`，并参考 [Web/index.html](Web/index.html) 编写宿主页面。

## 构建 Android 版本

未经修改的 `.xcodeproj` 应用（如 [`Examples/MobileUIGallery`](Examples/MobileUIGallery/MobileUIGallery.xcodeproj) 与 [`Examples/XcodeDemo`](Examples/XcodeDemo/XcodeDemo.xcodeproj)）可直接通过 CrossSwift 的 `xcodebuild` CLI（`-destination generic/platform=Android`，见下文）一键构建出 APK。若需在独立 Gradle 工程中集成，可参考 [Android Counter 示例](Examples/AndroidCounter/README-ZH.md)，该示例基于 `CROSS_SWIFTUI_ANDROID=1`、`SwiftUIAndroid` 与 Jetpack Compose 构建多 ABI APK。有关 Android 架构、Material 3 / iOS Liquid Glass 双风格渲染模式及构建配置，请参见 [docs/ANDROID-ZH.md](docs/ANDROID-ZH.md)。

## 将 `.xcodeproj` 编译至 Windows、Linux、Wasm、HarmonyOS 与 Android

CrossSwift 提供了跨平台 **`xcodebuild` 兼容命令行工具**（`CrossXcodeBuild` / `CrossXcodeBuildCLI`），无需在应用工程中添加任何平台专属配置，即可将未修改的 macOS / iOS `.xcodeproj` 与 `.xcworkspace` 工程（支持传统分组与 Xcode 16 同步文件夹）编译并打包为自包含的 Windows、Linux、WebAssembly、HarmonyOS 或 Android 产物：

```bash
# 列出 targets、configurations 与 schemes（兼容 Apple 文本或 JSON 输出格式）
xcodebuild -list -json -project Examples/XcodeDemo/XcodeDemo.xcodeproj

# 查看解析后的构建设置（支持 KEY=VALUE 覆盖）
xcodebuild -showBuildSettings -json \
  -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -configuration Release -derivedDataPath build

# 为当前桌面宿主（Windows 或 Linux）编译并打包
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO clean build

# 从 macOS 或 Linux 交叉编译至 WebAssembly（需 Swift Wasm SDK + npm）
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=Wasm \
  -derivedDataPath build clean build

# 从 macOS 或 Linux 交叉编译至 HarmonyOS arm64-v8a（需 Static Linux ARM64 SDK）
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=HarmonyOS \
  -derivedDataPath build clean build

# 从 macOS 或 Linux 交叉编译并打包 Android APK（需 Swift Android SDK + NDK + JDK 17）
xcodebuild -project Examples/XcodeDemo/XcodeDemo.xcodeproj \
  -scheme XcodeDemo -configuration Release \
  -destination generic/platform=Android \
  -derivedDataPath build clean build
```

> 在 macOS 上，`/usr/bin/xcodebuild` 是 Apple 官方 Xcode 工具；请通过 `swift run xcodebuild ...`（或编译产物路径）显式调用 CrossSwift 的 CLI。

运行时，`CrossXcodeBuild` 会自动完成以下工作：

- 使用纯 Swift 解析 `project.pbxproj`（以及 `.xcworkspace`、`.xcconfig`、`Package.resolved` 与 `Info.plist` 键值），不依赖 Xcode。
- 将源码导入的 Apple 框架（`SwiftUI`、`AppKit`、`CryptoKit`、`Combine`、`CoreGraphics`、`SQLite3` 及 `AppleShims` 模块）自动映射为 `CrossSwiftUI` SwiftPM 包中的对应产物，适配本地 SwiftPM 依赖包，并剔除仅限 Darwin 的条件包依赖。
- 自动合成 `Info.plist`、`GeneratedAssetSymbols.swift`、`.colorset` / `.imageset` / PDF 矢量 / `.xcstrings` 运行时资源、多尺寸 Windows `AppIcon.ico` 与 Win32 清单/版本资源（`AppResources.rc`），以及 Linux `.desktop` 启动器与 `hicolor` PNG 图标。
- 在 `<CONFIGURATION_BUILD_DIR>/<ProductName>/`（默认为 `<derivedDataPath>/Build/Products/<Configuration>/<ProductName>/`）生成自包含产物目录：
  - **Windows / Linux**：原生可执行文件、`Resources/`、Windows 运行时 `.dll`（基于 PE 导入表扫描）或 Linux 运行时 `.so`（基于 `ldd` 收集并写入 `$ORIGIN/lib` RPATH）及 `.desktop` + `hicolor` 图标。
  - **Wasm**（`-destination generic/platform=Wasm` 或 `-sdk wasm`）：包含 `index.html`、`app/<Product>.wasm`、`app/index.js`、`app/node_modules/@bjorn3/browser_wasi_shim` 与 `Resources/` 的静态 Web 包。
  - **HarmonyOS**（`-destination generic/platform=HarmonyOS` 或 `-sdk ohos`）：包含 `aarch64-swift-linux-musl` 目标文件（`NativeAPI.o`、`SwiftUIRuntime.o`、`SwiftUI.o`、`<Product>.o`）及静态 Swift/Foundation musl 归档的 `runtime/` 目录，外加可直接组装的 Stage 模型 HarmonyOS 工程（`AppScope/`、`entry/src/main/cpp/`、`entry/src/main/ets/`、`rawfile/Resources/`）。当检测到已安装 DevEco Studio（`DEVECO_STUDIO_HOME` 或 `/Applications/DevEco-Studio.app/Contents`）时，会自动调用 `ohpm` + `hvigorw` 生成 `<ProductName>.hap`。
  - **Android**（`-destination generic/platform=Android` 或 `-sdk android`）：自包含 Gradle Android 工程（`app/`、`gradlew`、`jniLibs/<abi>/lib<Product>.so`、`libc++_shared.so`、`assets/Resources/`、Jetpack Compose `MainActivity.kt`）及打包完成的 `<ProductName>.apk`（可通过 `ANDROID_ABIS=arm64-v8a,x86_64` 构建多架构包）。

[`Examples/XcodeDemo`](Examples/XcodeDemo/XcodeDemo.xcodeproj) 是一个未经修改的 macOS Xcode 工程，可在 macOS 上使用 Apple `xcodebuild` 构建，也可使用 CrossSwift 的 `xcodebuild` 直接构建出 Windows、Linux、WebAssembly、HarmonyOS 与 Android 版本。

## 仓库目录结构

```text
Sources/SwiftUIRuntime/       平台无关的 SwiftUI 核心引擎（视图、布局、diff、状态）
Sources/SwiftUIRuntimeMacros/ 编译器插件宏（@Entry、#Preview；无 swift-syntax 依赖）
Sources/CrossSwiftUI/         桌面端 NativeAPI 后端（Windows/Linux）、场景运行器与 AppKit 托管
Sources/CSwiftUIWindows/      Win32/GDI+ 保留式显示列表、文本测量与控件合成桥接
Sources/CrossAppKit/          跨平台 AppKit 视图、窗口、菜单、TextKit 与剪贴板实现
Sources/AppKit/               面向 Windows 与 Linux 的 `import AppKit` 门面模块
Sources/CAppKitWindows/       服务于 CrossAppKit 与系统垫片的 Win32/DWM/Shell/COM/无障碍 C++ 胶水层
Sources/CrossFoundation/      Windows 与 Linux 上的 Apple Foundation 扩展 API
Sources/AppleShims/           34 个 Apple 系统/框架兼容模块（CoreText、IOKit 等）
Sources/{CoreGraphics,Combine,CryptoKit,Carbon,UniformTypeIdentifiers,OSLog,os,SQLite3}/
                              顶层独立 Apple 框架兼容垫片
Sources/SwiftUIWeb/           WebAssembly DOM 渲染器与浏览器应用运行器
Sources/SwiftUIAndroid/       Android JNI 桥接与 Jetpack Compose 宿主（Material 3 / iOS 双风格）
Sources/CSwiftUIAndroid/      Android JNI 入口 C 头文件桥接
Sources/SwiftUI/              按目标平台选择后端的 `import SwiftUI` 门面模块
Sources/CrossXcodeBuild/      纯 Swift .xcodeproj 解析器、包依赖适配器、资源编译器与驱动器
Sources/CrossXcodeBuildCLI/   跨平台 `xcodebuild` 可执行程序入口
Examples/Counter/             桌面、Web 与 Android 共享的最小 SwiftPM 计数器示例
Examples/XcodeDemo/           可编译至全部五个非 Apple 平台的未修改 macOS .xcodeproj 示例
Examples/DesktopUIGallery/    桌面端 SwiftUI 组件、布局、图形与导航示例画廊
Examples/MobileUIGallery/     移动端 SwiftUI 示例画廊（展示 iOS、Android、HarmonyOS 双风格切换）
Examples/{MenuBarDemo,NotesApp,MetricsDashboard,KanbanBoard}/
                              已在 macOS、Windows 与 Linux 验证的未修改 macOS .xcodeproj 应用
Examples/AndroidCounter/      独立 Gradle + Swift Android SDK Activity 示例与冒烟测试
Examples/HarmonyRuntimeProbe/ HarmonyOS Stage 模型 Swift 运行时与 ArkUI 画廊验证工程
Web/                          WebAssembly 构建的 HTML 宿主模板
Tests/SwiftUIRuntimeTests/    基于 FakeBackend 的无头布局、diff、状态与 COMPAT.md 校验测试
Tests/CrossAppKitTests/       CrossAppKit 坐标转换、外观颜色、字体与资源解析测试
Tests/CrossXcodeBuildTests/   .xcodeproj 解析器、加载器、包适配器与 xcodebuild CLI 测试
Tests/{Windows,Linux}DrawingTests/
                              平台绘制后端、阴影、滚动与文本编辑器集成测试
skills/xcodebuild/            面向编码智能体的 CrossSwift `xcodebuild` CLI 技能包
docs/                         架构设计、Android 后端说明、API 兼容矩阵与行为差异文档
```

## 一段话设计概览

一次 `SwiftUIRuntime` 渲染通道会在作用域化的环境值、`@State` 与 `@Observable` 读取追踪下求值视图 `body`，解析继承属性，执行提案式布局并提升弹窗层，最后对同级子节点进行身份 diff。各平台后端消费增量指令和/或协调后的完整元素树：`CrossSwiftUI` 在 Windows 上发布保留式 GDI+ 显示列表（`CSwiftUIWindows`），在 Linux 上通过 GTK 3 中的 Cairo/Pango 绘制，同时桥接 `CrossAppKit` 视图与窗口；`SwiftUIWeb` 在浏览器中按节点身份保留并定位 DOM 元素；`SwiftUIAndroid` 与 HarmonyOS ArkUI 宿主将语义控件与布局矩形映射至 Jetpack Compose 与 ArkUI；`FakeBackend` 则记录指令供确定性无头测试断言使用。详见 [docs/ARCHITECTURE-ZH.md](docs/ARCHITECTURE-ZH.md)。

## 兼容性说明

- API 支持状态：[docs/COMPAT-ZH.md](docs/COMPAT-ZH.md)
- 已知行为与视觉差异：[docs/DIVERGENCES-ZH.md](docs/DIVERGENCES-ZH.md)
- 架构设计与更新策略：[docs/ARCHITECTURE-ZH.md](docs/ARCHITECTURE-ZH.md)
- Android 后端与 Compose 集成：[docs/ANDROID-ZH.md](docs/ANDROID-ZH.md)

## 许可证

MIT。详见 [LICENSE](LICENSE)。
