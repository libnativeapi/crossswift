# API 兼容性矩阵

**非官方实现；与 Apple 无关。**

[English](./COMPAT.md) | 简体中文

`supported` 表示该符号在 CrossSwift 已实现子集内具备对应的 API 形态；`partial` 表示存在行为简化或平台差异限制。两者均不代表与 Apple SwiftUI 完全一致。英文原表 [`COMPAT.md`](./COMPAT.md) 中的每一条 `supported` / `partial` 记录均由 `COMPATTests` 自动对照 `Sources/` 源码校验。渲染、布局与状态语义细节请参见 [DIVERGENCES-ZH.md](DIVERGENCES-ZH.md)。

Windows 与 Linux 使用 `SwiftUIRuntime` 配合 `CrossSwiftUI`（DirectWrite/GDI+ 与 GTK/Cairo/Pango 绘制及原生控件）、`CrossAppKit`（`import AppKit`）及 `CrossFoundation` / Apple 框架垫片；WebAssembly 使用 `SwiftUIWeb`；Android 使用 `SwiftUIAndroid`（见 [ANDROID-ZH.md](ANDROID-ZH.md)）；HarmonyOS 使用 `SwiftUIHarmony` 与 `CrossXcodeBuild` 的 ArkUI Stage 模型宿主。macOS 应用直接针对 Apple 原生 SDK 编译，同时 `SwiftUIRuntime`、`CrossAppKit` 与 `CrossXcodeBuild` 在 macOS 上可直接运行各自测试套件。

## 核心 SwiftUI 视图、状态与修饰符

| 符号 | 状态 | 行为说明 |
|---|---|---|
| `View` | supported | 含 `Body` 关联类型的值类型视图 |
| `View.body` | supported | 递归求值直至原语节点 |
| `@ViewBuilder` | supported | 0–10 个表达式、条件分支、`switch` 与循环 |
| `EmptyView` | supported | 空内容视图 |
| `AnyView` | supported | 类型擦除视图 |
| `Group` | supported | 透明分组容器 |
| `ViewModifier` | partial | 支持作用域环境与局部存储状态；比 Apple 完整 `DynamicProperty` 机制精简 |
| `VStack(alignment:spacing:)` | supported | 纵向堆栈布局 |
| `HStack(alignment:spacing:)` | supported | 横向堆栈布局 |
| `Spacer` | supported | 占据主轴剩余空间并强制执行 `minLength` |
| `Text` | partial | 原生文本测量、自动换行、省略号截断、`.xcstrings` 本地化及拼接 / `AttributedString` 富文本片段 |
| `Button(_:action:)` | supported | 原生按钮句柄与激活回调 |
| `Button(action:label:)` | partial | 通过 `ButtonStyle`（`plain`、`bordered`、`borderedProminent`、`borderless`、`link`）支持自定义标签；无样式标签展平为原生文本标题 |
| `ButtonStyle` | partial | 自定义视觉外观、原生激活与 `isPressed` 按压态 |
| `Color` | partial | RGB/透明度、深浅色动态闭包、`.xcassets` 颜色集、`Color(nsColor:)` 及语义色 |
| `Font` | partial | 原生字体族、文本样式、字号与 100–900 数值字重（Windows 经 DirectWrite、Linux 经 Pango） |
| `Rectangle` | partial | 填充与内描边（`strokeBorder`） |
| `RoundedRectangle` | partial | 圆弧圆角；`continuous` 当前与 `circular` 共用圆弧几何 |
| `Shape` | partial | 自定义 `Path`、`Circle`、`Ellipse`、`Capsule`、`UnevenRoundedRectangle`、`AnyShape` 及通用多段路径 `trim` |
| `ShapeStyle` | partial | `Color`、`HierarchicalShapeStyle`（`.primary`/`.secondary`/…）、`Material`、`Glass`、线性/径向/角度渐变与 `AnyShapeStyle` |
| `Edge` | supported | 单边枚举与用于内边距的 `Edge.Set` |
| `Alignment` | partial | Frame 与图层对齐 |
| `@State` | partial | 按结构路径、具体视图类型与属性序号寻址；按每个 `Renderer` 根节点独立隔离 |
| `@AppStorage` | partial | 基于 `UserDefaults` 的持久化状态，支持基础类型、`URL`、`Data` 与 `RawRepresentable` |
| `@SceneStorage` | partial | 按 `Renderer` 根节点独立隔离的场景级存储 |
| `@Binding` | supported | 读写闭包对与常量绑定 |
| `@Bindable`, `@Observable` | supported | 支持 Swift `Observation` 读取追踪与跨渲染器双向属性绑定 |
| `@Environment` | partial | 作用域环境值与 `@Observable` 对象注入，回调闭包可保留快照 |
| `@FocusedValue`, `@FocusedObject` | partial | 焦点视图值与对象的作用域发布与读取 |
| `EnvironmentKey` | supported | 带默认值的自定义环境键 |
| `@Entry` | supported | 自动生成 `EnvironmentKey` 与 `EnvironmentValues` 访问器的宏 |
| `EnvironmentValues` | partial | 自定义环境值、`font`、`colorScheme`、`locale`、`openURL`、`openWindow`、`dismissWindow`、`dismiss`、`refresh` 与 `accessibilityReduceMotion` |
| `@FocusState` | partial | `Bool` 与可选值焦点绑定；驱动原生按钮/输入框焦点 |
| `.padding(_:)` | supported | 统一间距、`EdgeInsets` 与 `Edge.Set` 重载 |
| `.frame(width:height:alignment:)` | partial | 有序尺寸包装器；支持对齐、`min`/`max` 与 `.infinity` |
| `.layoutPriority` | supported | 在 `HStack` 与 `VStack` 中按优先级分层分配与压缩主轴空间 |
| `.background(_:)` | partial | 纯色、`ShapeStyle`、材质与视图构建器背景层 |
| `.overlay` | partial | 不影响主视图测量尺寸的叠加视图与形状层 |
| `.foregroundColor(_:)` | partial | 可继承的 `Text` 与模板矢量图前景色 |
| `.foregroundStyle` | partial | 支持 `Color`、层级样式与各类 `ShapeStyle` |
| `.font` | partial | 作用于 `Text`、表单控件及自定义样式按钮标签 |
| `.lineLimit` | partial | 行数限制与首/尾省略号；富文本多行折行有限 |
| `.lineSpacing` | partial | 行间距设置 |
| `.opacity` | partial | Windows 与 Linux 均支持离屏合成组透明度（含 `.compositingGroup`） |
| `.clipShape` | partial | 矢量绘制路径裁剪与原生控件矩形视口裁剪 |
| `.mask` | partial | 桌面端支持视图 Alpha 遮罩合成 |
| `.contentShape` | partial | Windows 原生按钮圆角点击热区及宿主形状命中测试 |
| `.shadow` | partial | 桌面端基于三次盒式滤波高斯近似的圆角矩形/圆形轮廓阴影 |
| `.animation` | partial | 支持透明度、旋转、缩放、位移、颜色与布局尺寸的三次贝塞尔插值动画 |
| `.hidden()` | supported | 隐藏视觉绘制并禁用命中测试，同时保留布局空间 |
| `.disabled(_:)` | partial | 向下继承禁用态；内层显式传入 `false` 可重新启用 |
| `.onTapGesture(perform:)` | partial | 按钮动作及宿主区域命中测试点击 |
| `.onHover` | partial | 控件与宿主悬停检测及向祖先节点冒泡 |
| `.focused` | partial | `Bool` 与可选值焦点绑定；暂不支持焦点作用域（Focus Scope） |
| `.help` | partial | 原生按钮悬停工具提示（Tooltip） |
| `.id(_:)` | partial | 显式指定 diff 身份与局部状态作用域 |
| `App` | supported | 应用入口协议，由 `CrossSwiftUI`（桌面端）、`SwiftUIWeb`、`SwiftUIAndroid` 与 `SwiftUIHarmony` 提供运行器 |
| `Scene` | partial | 基于 `@SceneBuilder` 组合 `WindowGroup`、`Window`、`Settings`、`MenuBarExtra` 与 `.commands`（`CommandMenu` / `CommandGroup`） |
| `WindowGroup`, `Window`, `Settings` | partial | 桌面端多窗口声明式场景，支持 `defaultSize`、`OpenWindowAction`、`DismissWindowAction` 及接入原生主菜单的 `.commands` |
| `MenuBarExtra` | partial | 桌面端基于 `CrossAppKit.NSStatusItem`（`NativeAPI.TrayIcon`）的托盘/菜单栏项，支持 `.menu` 与 `.window` 浮动面板样式 |
| `@main` | supported | `App.main()` 启动入口 |
| `Preview` (`#Preview`) | supported | 在非 Apple 平台构建中可直接通过编译的独立预览宏 |
| `SwiftUI` module | supported | 面向 Windows、Linux、WebAssembly、HarmonyOS 与 Android 的统一门面模块 |

## 控件、容器、导航与图形

| 符号 | 状态 | 行为说明 |
|---|---|---|
| `ZStack` | supported | 支持对齐方式与 `zIndex` 排序的层叠容器 |
| `Divider` | supported | 自适应主轴方向的分割线及菜单分隔符 |
| `Label` | partial | 标题 + 图标组合，支持 `LabelStyle`（`titleAndIcon`、`iconOnly`、`titleOnly`） |
| `LabeledContent` | supported | 标签与值对齐行 |
| `Toggle` | partial | 支持 `switch`、`checkbox` 与 `button` 样式；在 Android 与 HarmonyOS 上映射原生/双风格开关 |
| `Slider` | partial | 连续或分段步进滑块；移动端映射原生滑块 |
| `Stepper` | partial | 增减按钮回调或数值绑定步进器 |
| `Picker` | partial | 支持 `segmented`、`menu`、`inline` 与 `radioGroup` 样式 |
| `Menu` | partial | 桌面端为锚定弹出下拉层（`_menuPopover`）；移动端映射原生或双风格菜单 |
| `ProgressView` | partial | 确定性线性进度条与不确定性加载指示器 |
| `ControlGroup` | partial | 水平组合控件容器 |
| `Form`, `Section` | partial | 带页眉与页脚的分组/双列设置表单容器 |
| `List` | partial | 可滚动、支持行选择的列表（`plain`、`inset`、`insetGrouped`、`sidebar`） |
| `NavigationStack`, `NavigationLink`, `NavigationPath` | partial | 支持路径/值压栈与 `.navigationDestination(for:)`；Android 映射 Jetpack Navigation Compose `NavHost`，HarmonyOS 映射 ArkUI `Navigation` |
| `NavigationSplitView` | partial | 支持侧边栏显隐切换的两栏与三栏分栏导航 |
| `TabView` | partial | 支持选中项绑定及标签图标/文字的标签页容器 |
| `DisclosureGroup` | supported | 支持绑定或内部展开状态的折叠容器 |
| `Gauge` | partial | 支持线性与环形样式及最大/最小/当前值标签的仪表盘 |
| `DatePicker` | partial | 支持紧凑气泡日历+时间调节器及 `.graphical` 日历样式 |
| `ColorPicker` | partial | 支持预设色板与 RGB/Alpha 滑块的颜色选择器气泡 |
| `AsyncImage` | partial | 带磁盘缓存与 `AsyncImagePhase` 状态切换的异步图片加载 |
| `Table`, `TableColumn` | partial | 支持列排序与单选/多选行的多列表格 |
| `ShareLink` | partial | 调用宿主剪贴板或打开链接回退的分享按钮 |
| `.fileImporter`, `.fileExporter` | partial | 桌面端通过 `NativeAPI.FileDialog` 调起系统原生打开/保存文件对话框 |
| `.redacted`, `.refreshable`, `.swipeActions` | partial | 占位脱敏渲染、异步下拉刷新动作与行首/行尾滑动操作按钮 |
| `.navigationTitle`, `.toolbar` | partial | 导航栏标题及 `ToolbarItem` / `ToolbarItemGroup` 工具栏项 |
| `.searchable` | partial | 绑定式搜索栏过滤修饰符 |
| `ContentUnavailableView` | supported | 居中的空状态图标、标题、描述与操作按钮占位视图 |
| `Link` | partial | 调用当前作用域的 `OpenURLAction`（桌面浏览器、Android Intent、Web `window.open`） |
| `ForEach` | partial | 稳定的数据 ID 状态作用域；在惰性堆栈与网格中元素数 `> 72` 时启用视口虚拟化 |
| `ScrollView` | partial | 纵向/横向滚轮与触控滚动、视口裁剪及滚动几何读取 |
| `LazyVStack`, `LazyHStack` | partial | 大列表（`> 72` 项）视口窗口虚拟化纵向/横向容器 |
| `Grid` | partial | 跨 `GridRow` 共享列宽的二维网格 |
| `LazyVGrid`, `LazyHGrid` | partial | 支持弹性/固定/自适应轨道及大集合（`> 72` 项）视口虚拟化 |
| `GeometryReader` | partial | 基于提案尺寸求值子视图，支持读取局部、全局与命名坐标空间矩形 |
| `Layout` | partial | 支持 `sizeThatFits`/`placeSubviews`、轴向弹性探测与 `AnyLayout` |
| `Path` | partial | 移动、直线、二次/三次贝塞尔曲线、圆弧、圆角矩形、闭合及通用多段 `trimmedPath(from:to:)` |
| `Canvas` | partial | 矢量填充/描边（`StrokeStyle`）、仿射变换（平移/缩放/旋转/矩阵）、透明度、渐变着色、`draw(Text)`、`draw(Image)`、`drawLayer` 与裁剪 |
| `LinearGradient`, `RadialGradient`, `AngularGradient` | supported | 跨桌面、Web、Android 与 HarmonyOS 真实渲染显式色标的线性、径向与角度/圆锥渐变 |
| `Image` | partial | 内置 `SFSymbolCatalog`（`systemName:`）、`.xcassets` 图像集与 PDF 矢量图、SVG 路径（保留逐路径填充/描边样式与 `renderingMode`）以及位图文件 |
| `TextField` | partial | 原生单行/多行文本编辑器，支持绑定、选区、IME 输入法及 Windows 透明背景合成 |
| `SecureField` | partial | 原生密码输入框 |
| `TextEditor` | partial | 原生多行文本编辑器 |
| `ObservableObject` | partial | 跨渲染器共享模型失效通知，提供 `Combine` `objectWillChange` 与 `@Published` `$prop` 发布者 |
| `StateObject` | partial | 按挂载身份保留的延迟初始化对象 |
| `ObservedObject` | partial | 对象订阅与可写 KeyPath 绑定投影 |
| `EnvironmentObject` | partial | 作用域环境对象查找 |
| `.onAppear`, `.onDisappear` | partial | 挂载完成与卸载移除生命周期回调 |
| `.onChange` | partial | 渲染完成后基于 `Equatable` 的新旧值比较回调 |
| `.task` | partial | 可取消的 `@MainActor` 异步任务，当 `id` 变化时自动取消重启 |
| `.gesture`, `.highPriorityGesture`, `.simultaneousGesture` | partial | 支持 `DragGesture`、`TapGesture`、`SpatialTapGesture`、定时 `LongPressGesture` 及高优先级/同时手势仲裁 |
| `.onKeyPress` | partial | 原生键盘事件路由与向祖先冒泡；字符与键盘布局映射有限 |
| `.keyboardShortcut` | partial | 作用域键盘快捷键；Windows/Linux 上 `Command` 快捷键同时兼容 `Control` |
| `.popover` | partial | 带箭头外框、四向边缘自动翻转、外部点击/Escape 关闭及 `presentationBackgroundInteraction` 的根层气泡 |
| `.sheet` | partial | 桌面与 Web 端为模态卡片层；移动端为原生/双风格底部弹窗（Bottom Sheet） |
| `.confirmationDialog` | partial | 支持破坏性与取消角色的操作确认弹窗 |
| `.contextMenu` | partial | 右键触发的根层上下文菜单，选择菜单项后自动收起 |
| `withAnimation` | partial | 将同步状态更新标记为支持属性、颜色、转场与布局插值的动画事务 |
| `.transition` | partial | 支持插入与移除过渡动画（`.opacity`、`.scale`、`.slide`、`.move`、`.push`、`.offset`、`.combined`、`.asymmetric`） |
| `.accessibilityLabel`, `.accessibilityValue` | partial | 映射至原生控件无障碍名称、描述与角色（Windows `BUTTON`/`EDIT` 与 Linux ATK）；纯绘制节点保留元数据 |
| `.border` | supported | 形状描边叠加层 |
| `.cornerRadius` | partial | 圆弧裁剪几何 |

## 附加跨平台与 AppKit 桥接 API

| 符号 | 状态 | 备注 |
|---|---|---|
| `ViewThatFits` | partial | 选取首个理想尺寸满足请求轴向的候选视图，兜底选取末项；所有候选即时求值 |
| `TimelineView(.animation(...))` | partial | 可取消的定时日期刷新，支持自定义间隔与暂停；未绑定显示器垂直同步信号 |
| `ScrollViewReader`, `ScrollViewProxy.scrollTo` | partial | 支持显式 ID 定位、锚点、轴向边界钳制、Web/Android 滚动同步与重复跳转请求 |
| `transformPreference`, `overlayPreferenceValue` | partial | 子节点偏好归约、有序变换及 `Equatable` 叠加层更新 |
| `LocalizedStringKey`, `LocalizedStringResource` | partial | 基于 `XCStringsCatalog` 的 `.xcstrings` 字符串目录查询与格式化插值 |
| `OpenURLAction`, `Text(AttributedString)` | partial | 链接点击调用作用域 `openURL`；支持前景色、字体、链接、下划线与删除线等属性 |
| `Text.kerning` | partial | 在纯文本与拼接片段上保留字距追踪元数据 |
| `ButtonRole` | partial | 取消快捷键绑定与破坏性操作红色样式 |
| `alert(_:isPresented:actions:message:)` | partial | 桌面与 Web 端为居中模态面板；移动端映射原生/双风格警告框 |
| `saturation`, `grayscale` | partial | 变换显式前景色/背景色/边框色，而非后处理像素级滤镜 |
| `blur`, `brightness`, `contrast` | partial | Windows 与 Linux 支持离屏三次盒式模糊与亮度/对比度像素滤镜；Web 使用 CSS `filter`；Android/HarmonyOS 透传 `.blur` |
| `LongPressGesture` | supported | 支持按压时长计时与最大位移取消的完整识别器 |
| `background(_:in:)` | supported | 在内容背后填充指定形状 |
| `FocusState.Binding.wrappedValue` | supported | 直接读写保留的焦点状态值 |
| `textSelection`, `accessibilityIdentifier` | partial | 保留元数据；自绘文本尚未接入系统级划词选区桥接 |
| `NSHostingView`, `NSHostingController` | partial | 在 `CrossAppKit` 窗口、面板与分栏视图中嵌入独立的 `SwiftUIRuntime` `Renderer`（由 `CrossSwiftUI` 提供） |
| `NSViewRepresentable` | partial | 在 SwiftUI 布局树中挂载并更新 `CrossAppKit.NSView` 实例（由 `CrossSwiftUI` 提供） |
| `NSApplicationDelegateAdaptor` | supported | 在 Windows 与 Linux 上从 `App` 注入 `CrossAppKit.NSApplicationDelegate`（由 `CrossSwiftUI` 提供） |

## 尚未实现

| 符号 | 状态 | 备注 |
|---|---|---|
| `DocumentGroup` | missing | 文档型多窗口生命周期与撤销/文件包管理 |
| 完整装饰性无障碍树 | missing | 面向非控件自绘形状与焦点作用域的完整 UI Automation / AT-SPI 提供程序 |
| GPU 着色器滤镜（`.colorEffect` / `.distortionEffect`） | missing | 非 Apple 平台上的 Metal 自定义着色器修饰符 |
