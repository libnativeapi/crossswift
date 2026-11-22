# 架构设计

**非官方实现；与 Apple 无关。**

[English](./ARCHITECTURE.md) | 简体中文

CrossSwift（`crossswift`，SwiftPM 清单名 `CrossSwiftUI`）将平台无关的声明式 UI 引擎、各平台渲染后端、AppKit 与 Apple 框架兼容垫片，以及 `.xcodeproj` 构建工具链分层解耦。

## 模块与边界

- `SwiftUIRuntime` + `SwiftUIRuntimeMacros`：平台无关的视图值类型、结果构建器、作用域化 `EnvironmentValues`、`@State` / `@AppStorage` / `@SceneStorage` / `@Binding` / `@FocusState` / `@FocusedValue` / `@FocusedObject`、`@Observable`（`@Bindable`）与 `ObservableObject`、编译器插件宏（基于 Swift JSON 插件线协议实现 `@Entry` 与 `#Preview`，不依赖 `swift-syntax`）、元素树、布局引擎（含 `Spacer.minLength`、`.layoutPriority`、保留空间的 `.hidden()` 及 `LazyVStack`/`LazyHStack`/`LazyVGrid`/`LazyHGrid` 视口虚拟化）、同级节点 diff、扩展控件（`DisclosureGroup`、`Gauge`、`DatePicker`、`ColorPicker`、`AsyncImage`、`Table`、`ShareLink`、`.fileImporter`/`.fileExporter`、`.redacted`、`.refreshable`、`.swipeActions`）、导航（`NavigationPath` + `.navigationDestination`）、弹窗层、SVG/PDF 矢量解析、内置 `SFSymbolCatalog`、`.xcstrings` 本地化（`XCStringsCatalog`）、多段 `Path.trimmedPath`、富 `Canvas`、线性/径向/角度渐变、定时 `LongPressGesture` + 手势优先级仲裁以及颜色/转场/布局动画。不导入任何 `NativeAPI`、AppKit、浏览器或 Android API。
- `CrossSwiftUI`：面向 **Windows 与 Linux** 的桌面端（`NativeAPI`）集成模块——包含 `WindowsDrawingBackend`、`LinuxDrawingBackend`、`NativeViewBackend`、多场景 `App` / `WindowGroup` / `Window` / `Settings` / `MenuBarExtra`（`.menu` 与 `.window`）/ `Scene.commands` 运行器（`runApp`）、原生窗口深浅色边框同步，以及 `CrossAppKit` 与 `CrossUIKit` 桥接托管（`NSHostingView`、`NSHostingController`、`NSViewRepresentable`、`NSApplicationDelegateAdaptor`、`_UIHostingView`、`UIHostingController`、`UIHostingConfiguration`、`UIViewRepresentable`、`UIViewControllerRepresentable`、`UIApplicationDelegateAdaptor`，外加 `Color`/`Font`/`Image`/`EdgeInsets` 与 `NSColor`/`UIColor`、`NSFont`/`UIFont`、`NSImage`/`UIImage`、`UIEdgeInsets`/`NSDirectionalEdgeInsets` 互转及 `Combine` `Published`/`ObservableObjectPublisher` 桥接）。
- `CSwiftUIWindows`：通用 Win32/DirectWrite/GDI+ 保留式显示列表、双缓冲 `WM_PAINT` DIB 合成器、DirectWrite 文本测量与渲染（100–900 数值字重、字体回退与彩色字体，带 GDI+ 回退）、离屏图层透明度与三次盒式模糊/亮度/对比度像素滤镜、径向与角度渐变、双通道遮罩透明合成 `EDIT` 控件、借用 `NativeAPI` `BUTTON` 子类化桥接、焦点/无障碍/工具提示管理，以及分层窗口阴影辅助层。不包含任何宿主应用的设计令牌、业务组件或主题配方。
- `CrossAppKit` + `AppKit` + `CAppKitWindows`：基于 `NativeAPI`（Windows 下辅以 `CAppKitWindows` 中的 Win32/DWM/Shell/COM/Credential Manager/无障碍 C++ 胶水层）实现的跨平台 AppKit 视图、控件、窗口/面板、菜单、状态栏图标、TextKit 1/2、剪贴板、工作区（Linux 下支持 `/proc` 与 `xdg-open`，Windows 下基于 Shell/Win32）、色彩/外观、字体、图像以及 Carbon 全局热键。`CrossAppKit` 可在 macOS 上独立编译运行单元测试；`AppKit` 则是 Windows 与 Linux 下的 `import AppKit` 门面模块。
- `CrossUIKit` + `UIKit`：跨平台 UIKit 应用与场景生命周期（`UIApplication`、`UIApplicationDelegate.main()`、`UIWindowScene`、`UIWindow`）、左上角原点 `UIView` 层级与迭代式 Auto Layout 锚点求解器及 `UIStackView`、`UIControl` + `UIAction` + `UIMenu`、原生后备控件（`UILabel`、`UIButton`、`UITextField`、`UITextView`、`UIScrollView`）、`UITableView` & `UICollectionView` 与 Diffable 数据源、视图控制器容器（`UIViewController`、`UINavigationController`、`UITabBarController`、`UIAlertController`）、`UITraitCollection`、动态 `UIColor`、`UIFont` 与 `UIFontMetrics`、复用 `CrossAppKit` 离屏绘制管线的 `UIImage` + `UIGraphicsImageRenderer` + `UIBezierPath`、`UIPasteboard`、`UIScreen` 与 `UIDevice`。`CrossUIKit` 可在 macOS 上独立编译运行单元测试；`UIKit` 则是 Windows 与 Linux 下的 `import UIKit` 门面模块。
- `CrossFoundation` 与框架垫片：补齐 Windows/Linux 下 `swift-corelibs-foundation` 缺失的 Apple `Foundation` API，提供独立框架 Target（`CoreGraphics`、完整 `Combine` 发布者/操作符/调度器、`CryptoKit`、`Carbon`、`UniformTypeIdentifiers`、`OSLog`、`os`、`SQLite3`）及 `Sources/AppleShims/` 下的 35 个系统/框架垫片模块（含 `QuartzCore`、基于 Win32 Credential Manager / Linux 0600 XDG 存储的 `Security` Keychain 与支持 Windows / Linux XDG 的 `ServiceManagement` 开机自启）。
- `SwiftUIWeb`：基于 `JavaScriptKit` 的 WebAssembly（`os(WASI)`）`WindowGroup` 宿主、DOM/SVG/CSS 渲染器（含深浅色实时同步、`openURL`、`scrollTo` DOM 同步、CSS 滤镜、圆锥/径向/线性渐变与多层 SVG/PDF 矢量渲染），以及 Web 端 `.xcassets` / `.xcstrings` / SF Symbols 加载器。
- `SwiftUIAndroid` + `CSwiftUIAndroid`：Android 线程安全 `JavaVM` 异步桥接（`AndroidHost`）、`Choreographer` 动画循环、深浅色与 `openURL` 同步，以及 Jetpack Compose 宿主（`SwiftUIComposeHost`、`AndroidStyleRenderers`），支持在 Material 3 + Navigation Compose 与 iOS 27 Liquid Glass 风格之间实时切换。详见 [ANDROID-ZH.md](ANDROID-ZH.md)。
- `SwiftUIHarmony`：正式 HarmonyOS 运行时后端（`HarmonyBackend`）与参数化 ArkTS 宿主（`CrossSwiftUIHost.ets`），支持异步刷新推送、60 Hz 动画驱动、深浅色同步、`rawfile/Resources` 解包与 HarmonyOS 原生 / iOS Liquid Glass 双风格渲染。
- `SwiftUI`：非 Apple 平台面向用户的 `import SwiftUI` 门面模块，重导出 `Foundation`、`SwiftUIRuntime` 与对应平台后端（Windows/Linux 下重导出 `CrossSwiftUI`、`CrossAppKit`、`CrossUIKit`、`CrossFoundation`、`CoreGraphics`；WASI 下重导出 `SwiftUIWeb`；Android 下重导出 `SwiftUIAndroid`；HarmonyOS 在 `CROSS_SWIFTUI_HARMONY` 下重导出 `SwiftUIHarmony`）。
- `CrossXcodeBuild` + `CrossXcodeBuildCLI`：纯 Swift 实现的 `.xcodeproj` / `.xcworkspace` 解析器、Apple 框架与 SwiftPM 依赖适配器、`.xcassets` / `.xcstrings` / 图标编译器，以及面向 Windows、Linux、WebAssembly、HarmonyOS（`HarmonyBuilder`）与 Android（`AndroidBuilder`）的 `xcodebuild` 命令行驱动器。

在 macOS 上，`swift build` / `swift test` 会构建 `SwiftUIRuntime`、`CrossAppKit`、`CrossXcodeBuild`（`xcodebuild`）及其测试套件，并基于 Apple 原生 SwiftUI 编译 `Counter`。Windows、Linux、WebAssembly、HarmonyOS 与 Android 构建则消费 CrossSwift 提供的 `SwiftUI`（及桌面端的 `AppKit`）门面。

## 渲染通道（Render Pass）

1. 启动状态收集：在求值每个视图 `body` 前，按结构路径、具体视图类型与属性序号注入存储型属性包装器。
2. 在作用域化 `EnvironmentValues` 下求值 `body` 与修饰符，同时追踪 `@State` 与 `@Observable` 读取。局部状态写入仅使读取该状态的节点及其祖先失效，未受影响的分支直接复用既有元素树、状态与生命周期注册；`ObservableObject` 与未追踪几何状态写入则采取保守失效策略。
3. 归一化片段节点（保留显式 ID 与 `tag`），保留视图层级的双槽结构，并向下解析继承的前景色、`colorScheme`、禁用态、可见性与透明度。
4. 计算布局、求值几何读取子节点、提升弹窗展示层（Presentation）、裁剪过期状态并分配同级 diff 键。绘制后端注入原生文本测量器；无头引擎测试则使用确定性度量。
5. 与已挂载的元素树执行 diff，为匹配的元素保留稳定的 `NodeID`。diff 键作用域限定在同级子节点列表内；当同级顺序未变时走线性快路径，无需构建键字典或扫描移动列表。
6. 发布更新后的元素树与回调表，发送增量后端指令，最后调用 `didRender(root)`。渲染重入守卫会合并同一通道期间触发的状态写入；Windows 桥接层则会合并同一消息循环轮次内的延迟原生通知。

后端指令集包含 `create`、`insert`、`remove`、`move`、`setProps` 与 `setFrame`。移除节点会递归释放其子树。交互动作通过保留的 `NodeID` 查找最新闭包，原生回调永远不会持有旧 `body` 闭包。重入写入最多合并为八轮后续渲染通道。

## Windows 后端

`CrossSwiftUI` 中的 `WindowsDrawingBackend` 将 `NativeAPI` 内容视图设为绝对定位模式，并在每次 diff 后发布保留式显示列表。桥接层直接重设借用自 `NativeAPI` 的按钮 `HWND` 父窗口：由 `NativeAPI` 管理其生命周期与事件，由 `SwiftUIRuntime` 独占布局，避免控件卷入第二套布局树。图形与 `Text` 共享同一绘制表面，内边距、Frame 与图层节点共同决定绘制顺序与坐标。原生 `BUTTON` 句柄仅在新按钮 ID 首次出现且与视口相交时创建，并在状态、主题与窗口尺寸变化期间持续复用。托管的 `CrossAppKit` 视图（`NSViewRepresentable`）按宿主身份单次挂载并就地更新；`NSHostingView` 与 `NSHostingController` 可在 AppKit 窗口和面板（包括带逐像素 Alpha 轮廓阴影的无边框透明窗口）内嵌入独立的 `Renderer` 实例。控件移除前会先注销监听与窗口子类化。

`CSwiftUIWindows` 对内容 `HWND` 进行子类化以实现双缓冲 `WM_PAINT`。宿主画布、自绘按钮以及透明合成的 `EDIT` 文本控件（通过双通道遮罩提取在画布背景上透明合成，使自定义搜索框、占位符、滚动视图与禁用态自然融合）共享同一块物理像素 DIB 帧缓冲。显示列表对比仅使发生变化的墨迹包围盒失效；结构、裁剪或变换变更会重绘其最小公共裁剪区（无公共裁剪时重绘整个视口）。绘制过程按累积脏区裁剪并复用有界字体缓存。嵌套与非嵌套 `ScrollView` 均采用固定视口加平移内容宿主 `HWND` 的结构：滚动仅借助 `DeferWindowPos` 一次性移动内容宿主而无需逐个移动按钮，无中间态闪烁；视口裁剪与 Tab 可达性过滤确保屏幕外控件不接收输入。原生 `BUTTON` 仍负责鼠标捕获、空格键触发、启用状态与 `BN_CLICKED`；桥接层补充回车触发、有序 Tab 导航、悬停/按下/焦点回调、圆角点击区域（`HRGN`）与工具提示。`EDIT` 编辑通知在原生消息栈展开后再写回 `Binding`，从而允许渲染安全销毁旧控件。延迟焦点事件会与当前真实 `HWND` 焦点核对。滚轮、手势与快捷键经由宿主事件路由至渲染器，不注入任何全局输入。

仅与视口相交的控件才会申请原生句柄，滑出视口后已有句柄保持保留。未变化的标题、矩形、Z 序与点击区域会跳过原生调用。局部按钮区域排除视口已完成的裁剪，因此滚动不会重建逐按钮 `HRGN`。视口外的文本/图像/形状及全透明布局盒不生成绘制指令。在 `ScrollView` 内，`LazyVStack`、`LazyHStack`、`LazyVGrid` 与 `LazyHGrid` 会利用尺寸估算缓存与视口缓冲窗口对大数据集 `ForEach`（`> 72` 项）进行虚拟化，而小规模集合则即时求值子节点以保留整数像素拷贝滚动快路径。容器获焦时仅挑选单个原生后代控件请求焦点。

`App.main` 会在应用与窗口初始化前配置 Per-Monitor V2 DPI 感知；嵌入方应在创建原生窗口前调用 `WindowsDrawingBackend.prepareApplication()`，或自行提供声明 DPI 感知的应用清单。所有运行时几何均采用逻辑点（Point）：绘制时按 `GetDpiForWindow` 缩放，桥接层将借用控件矩形换算至一致的设备像素坐标，原生文本测量与绘制使用同一字体选择；窗口缩放读取内容区尺寸而非含边框外框尺寸；帧缓冲拷贝显式指定像素矩形以规避 GDI+ 隐式图像 DPI 缩放。显示列表在原生控件同步完成后再发布，保证中间消息重绘时仍呈现上一帧完整画面。

后端暴露 `activate` / `nativeButton` / `advanceFocus` 供限定于自身控件的集成测试调用；`NativeAPI` 公共核心 API 与自动生成绑定保持与显示列表渲染器解耦。

## Linux 后端

`CrossSwiftUI` 中的 `LinuxDrawingBackend` 在 `NativeAPI` 窗口内承载 GTK 3 `GtkDrawingArea`：由 Cairo 绘制协调后的元素树（含视图遮罩与缓存的高斯近似圆角阴影遮罩），由 Pango 负责文本测量与排版渲染。保留的 GTK 按钮、单行输入框与多行文本视图跟随共享布局移动，由 GTK 提供键盘焦点、按钮激活、原生文本输入、多行占位符叠加层与 AT-SPI 无障碍名称。指针与滚轮事件经由运行时命中测试分发；GLib 空闲回调合并重绘请求、泵送 Swift 主队列并调度动画帧。平台限制详见 [DIVERGENCES-ZH.md](DIVERGENCES-ZH.md)。

## 状态、布局与测试

`StateRegistry` 为进程级注册表，但 `@State` 的保留期及 `.onAppear` / `.onDisappear` / `.task` 生命周期均按每个 `Renderer` 根节点严格隔离，使多窗口、`MenuBarExtra` 宿主与 `NSHostingView` 实例在共享 `@Observable` 和 `ObservableObject` 模型的同时，各自保有独立局部状态与生命周期。`Binding` 为读写闭包对，焦点绑定包装局部状态；环境值围绕子树压栈与恢复；`.id` 与 `ForEach` 数据标识符同时限定 diff 身份与存储状态作用域。运行时通过父节点与子键驻留（intern）路径，使状态查找开销与视图树深度无关。重新求值会保留同一视图仍在读取的状态订阅。`@Published` 与 `@Observable` 写入会使所有观察该对象的渲染器失效；`StateObject` 延迟初始化。单次交互动作或单批原生通知内的多次写入合并发布。`ScrollView` 仅内部偏移变化时直接复用已挂载子树。

堆栈布局在主轴累加尺寸、在交叉轴取最大尺寸；内边距增加四周边距；Frame 约束并按对齐放置子节点；背景/叠加图层仅以主视图参与测量；弹性 Frame 与 `Spacer` 瓜分剩余提案空间。自定义 `Layout` 实现会探测主交叉轴弹性，而非硬编码水平拉伸。测量结果按提案与尺寸输入缓存，自动换行文本在测量与排布阶段共享同一缓存。重建的 `GeometryReader` 在尺寸输入不变时保留布局身份；排布快照仅将几何复制至新树而不覆盖最新回调或视觉属性。求值修订号与继承属性均未变化的已挂载子树直接复用：平移时整体偏移矩形，缩放时重新流式排布。文本、字体、约束、对齐、滚动偏移或子节点身份变化会使对应缓存失效；不透明的自定义布局/对齐引导闭包走保守路径。过期布局缓存每八轮通道回收一次，切换文本测量器时立即清空。

在 Windows 上，当可见绘制指令及裁剪栈满足纯整数像素平移、背景均匀且无静止叠加层相交时，滚动可直接复用帧缓冲内部像素，仅重绘新暴露边缘与滚动条；像素回归测试会将复用结果与全新渲染逐像素比对。

测试套件覆盖运行时布局、diff、多窗口状态隔离、环境作用域、`@Observable` 追踪、控件与容器、`CrossAppKit` 垫片、`CrossXcodeBuild` 工程解析与包适配、Windows/Linux 绘制，以及 [`COMPAT.md`](COMPAT.md) 符号一致性测试（`COMPATTests`）。`Counter --smoke` 会打开真实原生窗口并在 3 秒后退出以验证原生事件循环。`Renderer.lastTimings`、`WindowsDrawingBackend.lastTimings`、`lastPaintTimings` 与 `lastReusedPixels` 提供各阶段耗时与滚动像素复用统计。
