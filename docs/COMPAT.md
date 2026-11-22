# Compatibility

**Unofficial; not affiliated with Apple.**

English | [简体中文](./COMPAT-ZH.md)

`supported` describes the API shape within CrossSwift's implemented subset;
`partial` indicates behavioral or platform-specific limits. Neither implies full
Apple SwiftUI parity. Every `supported` and `partial` row is verified against
`Sources/` by `COMPATTests`. See [DIVERGENCES.md](DIVERGENCES.md) for rendering,
layout, and state details.

Windows and Linux use `SwiftUIRuntime` with `CrossSwiftUI` (DirectWrite/GDI+ and
GTK/Cairo/Pango drawing plus native controls), `CrossAppKit` (`import AppKit`),
and `CrossFoundation` / Apple framework shims. WebAssembly uses `SwiftUIWeb`,
Android uses `SwiftUIAndroid` (see [ANDROID.md](ANDROID.md)), and HarmonyOS uses
`SwiftUIHarmony` with `CrossXcodeBuild`'s ArkUI Stage-model host. macOS
applications compile against Apple's native SDKs, while `SwiftUIRuntime`,
`CrossAppKit`, and `CrossXcodeBuild` run their test suites on macOS.

## Core SwiftUI views, state & modifiers

| symbol | status | behavior |
|---|---|---|
| `View` | supported | value views with a `Body` |
| `View.body` | supported | recursively evaluated to primitives |
| `@ViewBuilder` | supported | 0–10 expressions, conditions, switches, loops |
| `EmptyView` | supported | no content |
| `AnyView` | supported | type erasure |
| `Group` | supported | transparent grouping |
| `ViewModifier` | partial | scoped environment and stored state; smaller than SwiftUI's full `DynamicProperty` system |
| `VStack(alignment:spacing:)` | supported | vertical stack |
| `HStack(alignment:spacing:)` | supported | horizontal stack |
| `Spacer` | supported | consumes leftover main-axis space while enforcing `minLength` |
| `Text` | partial | native measurement, wrapping, ellipsis, `.xcstrings` localization, and concatenated / `AttributedString` styled runs |
| `Button(_:action:)` | supported | native button handle and activation |
| `Button(action:label:)` | partial | custom labels through `ButtonStyle` (`plain`, `bordered`, `borderedProminent`, `borderless`, `link`); unstyled labels flatten to a native text title |
| `ButtonStyle` | partial | custom visuals, native activation, `isPressed` |
| `Color` | partial | RGB/opacity, dynamic light/dark closures, `.xcassets` colorsets, `Color(nsColor:)`, and semantic colors |
| `Font` | partial | native family, text styles, size, and numeric weights (100–900 via DirectWrite on Windows and Pango on Linux) |
| `Rectangle` | partial | fill/strokeBorder |
| `RoundedRectangle` | partial | circular corners; continuous currently uses circular arc geometry |
| `Shape` | partial | custom `Path`, `Circle`, `Ellipse`, `Capsule`, `UnevenRoundedRectangle`, `AnyShape`, and general multi-segment `trim` |
| `ShapeStyle` | partial | `Color`, `HierarchicalShapeStyle` (`.primary`/`.secondary`/…), `Material`, `Glass`, linear/radial/angular gradients, `AnyShapeStyle` |
| `Edge` | supported | individual edges and `Edge.Set` for padding |
| `Alignment` | partial | frame and layer alignment |
| `@State` | partial | structural path, concrete view type, and property position; isolated per renderer root |
| `@AppStorage` | partial | `UserDefaults`-backed persistent state for primitive, `URL`, `Data`, and `RawRepresentable` types |
| `@SceneStorage` | partial | per-renderer-root scoped scene storage |
| `@Binding` | supported | get/set pair and constant bindings |
| `@Bindable`, `@Observable` | supported | Swift `Observation` read tracking and two-way property bindings across renderers |
| `@Environment` | partial | scoped values and `@Observable` objects retained by callbacks |
| `@FocusedValue`, `@FocusedObject` | partial | scoped focused-value and focused-object publication and lookup |
| `EnvironmentKey` | supported | custom keys with default values |
| `@Entry` | supported | macro generating `EnvironmentKey` and `EnvironmentValues` accessors |
| `EnvironmentValues` | partial | custom values, `font`, `colorScheme`, `locale`, `openURL`, `openWindow`, `dismissWindow`, `dismiss`, `refresh`, and `accessibilityReduceMotion` |
| `@FocusState` | partial | `Bool` and optional-value bindings; native button/editor focus |
| `.padding(_:)` | supported | uniform, `EdgeInsets`, and `Edge.Set` overloads |
| `.frame(width:height:alignment:)` | partial | ordered wrapper; alignment, min/max, and infinity |
| `.layoutPriority` | supported | priority-tiered main-axis allocation and compression in `HStack` and `VStack` |
| `.background(_:)` | partial | colors, `ShapeStyle`s, materials, and view builder layers |
| `.overlay` | partial | view layers and shapes aligned without affecting base size |
| `.foregroundColor(_:)` | partial | inherited `Text` and template vector color |
| `.foregroundStyle` | partial | `Color`, hierarchical styles, and `ShapeStyle`s |
| `.font` | partial | `Text`, controls, and styled button labels |
| `.lineLimit` | partial | wrapping and head/tail ellipsis; limited rich-text wrapping |
| `.lineSpacing` | partial | spacing between lines |
| `.opacity` | partial | offscreen layer group compositing on Windows and Linux (plus `.compositingGroup`) |
| `.clipShape` | partial | vector drawing clip and rectangular native control viewport clipping |
| `.mask` | partial | alpha view masking on desktop |
| `.contentShape` | partial | rounded native button hit region on Windows; rectangular/shape hit testing |
| `.shadow` | partial | Gaussian-approximated rounded-rectangle/circular silhouette mask on desktop |
| `.animation` | partial | opacity, rotation, scale, offset, color, and layout sizing interpolation with cubic-bezier curves |
| `.hidden()` | supported | hides visuals and hit testing while preserving layout space |
| `.disabled(_:)` | partial | inherited by descendants; inner `false` can re-enable |
| `.onTapGesture(perform:)` | partial | button actions and hit-tested host content |
| `.onHover` | partial | control/host hover and ancestor delivery |
| `.focused` | partial | `Bool` and optional-value bindings; no focus scopes |
| `.help` | partial | native button tooltips |
| `.id(_:)` | partial | diff identity and explicit state scope |
| `App` | supported | entry point supplied by `CrossSwiftUI` (desktop), `SwiftUIWeb` (Wasm), `SwiftUIAndroid`, and `SwiftUIHarmony` |
| `Scene` | partial | `@SceneBuilder` composition of `WindowGroup`, `Window`, `Settings`, `MenuBarExtra`, and `.commands` (`CommandMenu` / `CommandGroup`) |
| `WindowGroup`, `Window`, `Settings` | partial | multi-window desktop scenes with `defaultSize`, `OpenWindowAction`, `DismissWindowAction`, and native main-menu `.commands` |
| `MenuBarExtra` | partial | tray/status-bar item backed by `CrossAppKit.NSStatusItem` (`NativeAPI.TrayIcon`) supporting `.menu` and `.window` popover panels on desktop |
| `@main` | supported | `App.main()` runner |
| `Preview` (`#Preview`) | supported | freestanding preview macro accepted across non-Apple builds |
| `SwiftUI` module | supported | user-facing facade on Windows, Linux, WebAssembly, HarmonyOS, and Android |

## Controls, containers, navigation & graphics

| symbol | status | behavior |
|---|---|---|
| `ZStack` | supported | ordered layers with alignment and `zIndex` |
| `Divider` | supported | axis-aware separator line and menu separator |
| `Label` | partial | title + icon with `LabelStyle` (`titleAndIcon`, `iconOnly`, `titleOnly`) |
| `LabeledContent` | supported | aligned label and value row |
| `Toggle` | partial | `switch`, `checkbox`, and `button` styles; native Material 3 / iOS controls on Android & HarmonyOS |
| `Slider` | partial | continuous or stepped value dragging; native slider on mobile hosts |
| `Stepper` | partial | increment/decrement buttons or value binding |
| `Picker` | partial | `segmented`, `menu`, `inline`, and `radioGroup` styles |
| `Menu` | partial | anchored dropdown popup (`_menuPopover`) on desktop; native/styled menu on mobile |
| `ProgressView` | partial | determinate linear bar and indeterminate spinner |
| `ControlGroup` | partial | grouped horizontal control container |
| `Form`, `Section` | partial | grouped and columns form layouts with headers and footers |
| `List` | partial | scrollable selectable rows (`plain`, `inset`, `insetGrouped`, `sidebar`) |
| `NavigationStack`, `NavigationLink`, `NavigationPath` | partial | value/path push stacks with `.navigationDestination(for:)`; Jetpack Navigation Compose `NavHost` on Android and ArkUI `Navigation` on HarmonyOS |
| `NavigationSplitView` | partial | two- and three-column split layouts with sidebar visibility toggle |
| `TabView` | partial | tabbed container with selection binding and tab item labels/icons |
| `DisclosureGroup` | supported | collapsible container with bound or internal expansion state |
| `Gauge` | partial | linear capacity and accessory circular gauges with min/max/current value labels |
| `DatePicker` | partial | compact popover calendar + time adjuster and `.graphical` calendar styles |
| `ColorPicker` | partial | color swatch popover with palette presets and RGB/alpha sliders |
| `AsyncImage` | partial | async URL loading with disk cache and `AsyncImagePhase` transitions |
| `Table`, `TableColumn` | partial | multi-column sortable tables with single/multi-row selection |
| `ShareLink` | partial | share/copy button invoking host pasteboard or open-URL fallback |
| `.fileImporter`, `.fileExporter` | partial | native OS file open/save dialogs via `NativeAPI.FileDialog` on desktop |
| `.redacted`, `.refreshable`, `.swipeActions` | partial | placeholder redaction, async `RefreshAction`, and trailing/leading row actions |
| `.navigationTitle`, `.toolbar` | partial | navigation bar header and `ToolbarItem` / `ToolbarItemGroup` |
| `.searchable` | partial | bound search bar filtering |
| `ContentUnavailableView` | supported | centered icon, title, description, and actions placeholder |
| `Link` | partial | invokes scoped `OpenURLAction` (wired to OS browser on desktop, Android Intent, and `window.open` on Web) |
| `ForEach` | partial | stable data-ID state scopes; virtualized inside lazy stacks and grids when `count > 72` |
| `ScrollView` | partial | vertical/horizontal wheel & touch scrolling, viewport clipping, and scroll geometry |
| `LazyVStack`, `LazyHStack` | partial | viewport-windowed `ForEach` virtualization for large lists (`> 72` items) |
| `Grid` | partial | shared columns across `GridRow` children |
| `LazyVGrid`, `LazyHGrid` | partial | flexible/fixed/adaptive tracks with viewport-windowed virtualization (`> 72` items) |
| `GeometryReader` | partial | proposal-driven children, local/global/named frames |
| `Layout` | partial | `sizeThatFits`/`placeSubviews`, axis-flexibility probing, and `AnyLayout` |
| `Path` | partial | move, line, quad/cubic curves, arcs, rounded rects, closures, and general multi-segment `trimmedPath(from:to:)` |
| `Canvas` | partial | vector fills/strokes (`StrokeStyle`), affine transforms (`translateBy`/`scaleBy`/`rotate`/`concatenate`), opacity, gradient shadings, `draw(Text)`, `draw(Image)`, `drawLayer`, and clipping |
| `LinearGradient`, `RadialGradient`, `AngularGradient` | supported | explicit color stops and true linear, radial, and angular/conic rendering across desktop, Web, Android, and HarmonyOS |
| `Image` | partial | embedded `SFSymbolCatalog` (`systemName:`), `.xcassets` imagesets & PDF vectors, SVG paths (preserving per-path fill/stroke and `renderingMode`), and raster files |
| `TextField` | partial | native editor with binding, selection, IME, and transparent backdrop compositing on Windows |
| `SecureField` | partial | native password editor |
| `TextEditor` | partial | multiline native text editor |
| `ObservableObject` | partial | shared-model invalidation across renderers with `Combine` `objectWillChange` / `@Published` `$prop` publishers |
| `StateObject` | partial | lazy retained object, scoped by mounted identity |
| `ObservedObject` | partial | object and writable-key-path bindings |
| `EnvironmentObject` | partial | scoped object lookup |
| `.onAppear`, `.onDisappear` | partial | post-mount and removal lifecycle callbacks |
| `.onChange` | partial | `Equatable` value comparison after rendering |
| `.task` | partial | cancellable main-actor task, restarted by `id` |
| `.gesture`, `.highPriorityGesture`, `.simultaneousGesture` | partial | `DragGesture`, `TapGesture`, `SpatialTapGesture`, timed `LongPressGesture`, and priority/simultaneous arbitration |
| `.onKeyPress` | partial | native key routing and ancestor handlers; limited character/layout mapping |
| `.keyboardShortcut` | partial | scoped key actions; Command shortcuts also accept Control on Windows/Linux |
| `.popover` | partial | root-layer presentation with beak chrome, 4-edge flipping, outside/Escape dismissal, and `presentationBackgroundInteraction` |
| `.sheet` | partial | modal card presentation on desktop/web; bottom sheet on mobile hosts |
| `.confirmationDialog` | partial | modal action sheet with destructive/cancel roles |
| `.contextMenu` | partial | secondary-click root-layer menu, dismissed on selection |
| `withAnimation` | partial | marks synchronous state updates for property, color, transition, and layout interpolation |
| `.transition` | partial | animated insertion and removal transitions (`.opacity`, `.scale`, `.slide`, `.move`, `.push`, `.offset`, `.combined`, `.asymmetric`) |
| `.accessibilityLabel`, `.accessibilityValue` | partial | native control names, descriptions, and roles (Windows `BUTTON`/`EDIT` + Linux ATK); decorative nodes retain metadata without a full custom accessibility tree |
| `.border` | supported | shape overlay |
| `.cornerRadius` | partial | circular clipping geometry |

## Additional portable & AppKit hosting APIs

| symbol | status | note |
|---|---|---|
| `ViewThatFits` | partial | first ideal-sized candidate fitting requested axes, last-child fallback; alternatives evaluated eagerly |
| `TimelineView(.animation(...))` | partial | cancellable date updates, configurable interval and pause; no display-link synchronization |
| `ScrollViewReader`, `ScrollViewProxy.scrollTo` | partial | explicit IDs, anchors, axis clamping, DOM/Compose scroll sync, and repeat requests |
| `transformPreference`, `overlayPreferenceValue` | partial | child reduction, ordered transforms, and `Equatable` overlay updates |
| `LocalizedStringKey`, `LocalizedStringResource` | partial | `.xcstrings` string catalog lookup and format interpolation via `XCStringsCatalog` |
| `OpenURLAction`, `Text(AttributedString)` | partial | links invoke scoped `openURL`; SwiftUI font, foreground color, link, underline, and strikethrough attributes |
| `Text.kerning` | partial | tracking metadata retained on plain and concatenated runs |
| `ButtonRole` | partial | cancel shortcut and destructive styling |
| `alert(_:isPresented:actions:message:)` | partial | centered modal panel on desktop/web; native/styled alert dialog on mobile |
| `saturation`, `grayscale` | partial | transforms explicit foreground/background/border colors rather than post-composited pixels |
| `blur`, `brightness`, `contrast` | partial | real offscreen 3-pass box blur and brightness/contrast pixel filters on Windows and Linux; CSS `filter` on Web; Compose/ArkUI `.blur` on Android and HarmonyOS |
| `LongPressGesture` | supported | timed duration and maximum-distance cancellation recognizer |
| `background(_:in:)` | supported | fills the supplied shape behind the content |
| `FocusState.Binding.wrappedValue` | supported | reads and writes the retained focus value |
| `textSelection`, `accessibilityIdentifier` | partial | metadata retained; drawn text has no platform selection bridge yet |
| `NSHostingView`, `NSHostingController` | partial | embeds a `SwiftUIRuntime` `Renderer` inside `CrossAppKit` windows, panels, and split views (`CrossSwiftUI`) |
| `NSViewRepresentable` | partial | mounts and updates `CrossAppKit.NSView` instances inside SwiftUI layouts (`CrossSwiftUI`) |
| `NSApplicationDelegateAdaptor` | supported | installs a `CrossAppKit.NSApplicationDelegate` from `App` on Windows and Linux (`CrossSwiftUI`) |

## Not implemented

| symbol | status | note |
|---|---|---|
| `DocumentGroup` | missing | document-based multi-window lifecycle and undo/file-wrapper management |
| Full decorative accessibility tree | missing | complete UI Automation / AT-SPI provider for custom non-control drawn shapes and focus scopes |
| GPU shader effects (`.colorEffect` / `.distortionEffect`) | missing | Metal shader modifiers on non-Apple backends |
