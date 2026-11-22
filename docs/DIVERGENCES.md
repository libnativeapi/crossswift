# Known divergences from Apple SwiftUI

**Unofficial; not affiliated with Apple.** See [COMPAT.md](COMPAT.md) for API status.

English | [简体中文](./DIVERGENCES-ZH.md)

## Platforms and controls

On Windows, `CrossSwiftUI` (`WindowsDrawingBackend` + `CSwiftUIWindows`) uses a
retained display list on a `NativeAPI` content HWND with DirectWrite text
rendering (falling back to GDI+ if unavailable) and GDI+ vector/layer
compositing. Styled buttons retain native `BUTTON` activation, capture, focus,
accessible names/descriptions, and disabled state using owner drawing.
`TextField`, `SecureField`, and `TextEditor` use native Win32 `EDIT` controls
for selection, clipboard commands, and IME, composited transparently over the
drawn canvas backdrop via dual-pass matte extraction so custom backgrounds,
placeholders, scroll views, and disabled states show through cleanly. Native
controls are clipped to scroll viewports. Borderless windows and floating AppKit
panels (`CrossAppKit.NSPanel`) support per-pixel alpha and alpha-silhouette
window shadows on Windows.

Decorative content has no complete UI Automation or AT-SPI provider.
Accessibility modifiers retain metadata; native control names, descriptions,
GTK/ATK roles, and modal control exclusion are implemented, while a full
accessible hierarchy for non-control drawn shapes and focus scopes are not.

On Linux, `CrossSwiftUI` (`LinuxDrawingBackend`) uses Cairo and Pango in a GTK 3
drawing area (including detached Pango measurement in `NSHostingView` and
live appearance synchronization). GTK entries and text views provide native
editing, multiline placeholder overlays, and keyboard focus. GTK buttons expose
native activation and AT-SPI names, descriptions, and roles. Window chrome
follows light and dark appearances on both Windows and Linux.

On macOS, applications compile directly against Apple's native `SwiftUI` and
`AppKit` SDKs; `SwiftUIRuntime`, `CrossAppKit`, and `CrossXcodeBuild` build on
macOS for unit testing and cross-platform `.xcodeproj` compilation.

## Browser and mobile hosts

`SwiftUIWeb` mounts `WindowGroup` inside `#swiftui-root` in the page. Its title
sets `document.title`, the host element's dimensions drive layout, `colorScheme`
tracks `prefers-color-scheme` live, `openURL` opens browser tabs, and
`ScrollViewProxy.scrollTo` synchronizes DOM scroll offsets. HTML controls
provide editing, focus, and activation; text metrics and scrollbars follow the
browser. When staged by `CrossXcodeBuild`, `.xcassets` images, `.xcstrings`
catalogs, and embedded SF Symbols/multi-layer SVG/PDF vectors are loaded via
`web-manifest.json` (`window.__crossSwiftUIResources`). `CrossAppKit` and
`MenuBarExtra` are desktop-only modules and are not available on WebAssembly,
Android, or HarmonyOS.

`SwiftUIAndroid` and `SwiftUIHarmony` map semantic controls (`Toggle`, `Slider`,
`Stepper`, `Picker`, `Menu`, `ProgressView`, `List`, `NavigationStack`,
`TabView`, `.sheet`, `.alert`) to native Jetpack Compose / ArkUI components or
iOS Liquid Glass renderers while `SwiftUIRuntime` evaluates state and layout in
Swift, pushing asynchronous Swift updates and animation ticks back to the mobile
UI loop. See [ANDROID.md](ANDROID.md).

## Drawing, assets and text

On Windows, DirectWrite measures and renders text in logical points with full
numeric font weights (100–900), system font fallback, and color-font/emoji
support (with a GDI+ fallback). System sans, serif, and monospaced faces map to
Segoe UI, Georgia, and Consolas. Wrapping, newlines, line spacing, and head/tail
ellipsis are supported. Linux uses system font families with Pango weight
selection, tracking, and underline. Concatenated `Text` and `AttributedString`
runs retain font, foreground color, link, underline, and strikethrough metadata
without forming a full bidirectional paragraph engine.

`Image` supports the embedded `SFSymbolCatalog` (`Image(systemName:)`),
`.xcassets` imagesets and PDF vector assets, raster files, and bundled SVG
paths (including elliptical arcs, per-path fill/stroke styles, and template vs.
original `renderingMode`). Arbitrary SVG `<text>`, `<filter>`, and embedded
bitmap elements are not parsed. `LinearGradient`, `RadialGradient`, and
`AngularGradient` support explicit stops and render true linear, radial, and
angular/conic gradients across desktop, Web, Android, and HarmonyOS. `Canvas`
supports vector fills/strokes (`StrokeStyle`), affine transforms (`translateBy`,
`scaleBy`, `rotate`, `concatenate`), `opacity`, gradient shadings, `draw(Text)`,
`draw(Image)`, `drawLayer`, and clipping. `Path.trimmedPath(from:to:)` supports
both circular arcs and general multi-segment line/cubic Bezier paths.

Rounded corners use circular arcs for both `.circular` and `.continuous` styles.
Desktop shadows blur a rounded-rectangle or circular silhouette mask with three
box filters approximating a Gaussian, and `.mask` applies view alpha masks on
desktop. Windows and Linux composite offscreen layers for subtree `.opacity`,
`.compositingGroup()`, 3-pass box `.blur`, `.brightness`, and `.contrast` pixel
filters; Web uses CSS `filter`, and Android/HarmonyOS forward `.blur`. Arbitrary
clip paths constrain vector drawing, whereas native controls use rectangular
viewport clipping.

## Layout, state and events

Layout uses proposals, nested frames/padding/layers, stack flexibility,
`Spacer.minLength`, `.layoutPriority(_:)`, `Grid`, scroll content extents, and
custom `Layout` callbacks (with axis-flexibility probing). Inside a
`ScrollView`, `LazyVStack`, `LazyHStack`, `LazyVGrid`, and `LazyHGrid`
virtualize `ForEach` collections exceeding 72 items using cached item-extent
estimates; smaller collections evaluate eagerly to preserve fast pixel-copy
scroll translation. Exact text-baseline alignment across mixed native controls
remains incomplete.

`.hidden()` hides visuals and hit testing while preserving layout space, and
inner `.disabled(false)` can re-enable content. Dragging, timed
`LongPressGesture` (with duration and maximum-distance cancellation), hovering,
and `.highPriorityGesture` / `.simultaneousGesture` arbitration are handled in
the runtime; controls bubble key/focus callbacks to ancestors. Full keyboard
layout-to-character mapping remains incomplete.

`StateRegistry` is process-wide, while `@State`, `@SceneStorage`, and
`.onAppear` / `.onDisappear` / `.task` lifecycles are isolated per `Renderer`
root (allowing independent windows, `MenuBarExtra` popovers/menus, and
`NSHostingView` instances). `@AppStorage` persists through `UserDefaults`, and
`@FocusedValue` / `@FocusedObject` propagate active-view values to commands and
siblings. `@Observable` (`@Bindable`) and `ObservableObject` models invalidate
all observing renderers. Reflection installs directly stored wrappers rather
than Apple SwiftUI's complete nested `DynamicProperty` graph. Measurement and
placement caches reuse unchanged subtrees; `WindowsDrawingBackend` verifies
display commands before reusing integer-pixel scroll interiors, falling back to
normal damage repainting when unsafe. Use `Release` builds when benchmarking
interactive frame rates.

Presentations (`.popover`, `.sheet`, `.confirmationDialog`, `.alert`,
`.contextMenu`, and `Menu` dropdowns) hoist above scroll clipping on desktop and
web, flip `.popover` edges within window bounds, and dismiss on backdrop press
or Escape. On desktop they render inside the window surface rather than spawning
separate OS windows (except `MenuBarExtra` status items/popovers, declarative
`Window`/`Settings` scenes, and explicit `CrossAppKit` `NSWindow` / `NSPanel`
instances).

## Lifecycle, scenes and compatibility shims

Appearance, change, and disappearance callbacks commit after mounting; `.task`
cancels on disappearance or `id` change. `NativeAPI`'s Swift binding pumps
Swift's main `DispatchQueue` alongside the Win32, GTK, and HarmonyOS UI loops.

The runtime and desktop backends interpolate rotation, scale, opacity, offset,
colors (`background`, `foreground`, `borderColor`), insertion/removal
`.transition` animations, and animated layout sizing (frames, padding, and stack
spacing) across `withAnimation` and `.animation(_:value:)` using cubic-bezier
timing curves.

`CrossSwiftUI`'s scene runner supports declarative `WindowGroup` (including
ID/value windows), `Window`, `Settings`, `OpenWindowAction` /
`DismissWindowAction`, `.commands` (`CommandMenu` / `CommandGroup` wired to the
native main menu), and `MenuBarExtra` (`.menu` and `.window` popover panels),
plus accessory/menu-bar-only apps backed by `CrossAppKit.NSApplication`.
`DocumentGroup` and persistent scene-restoration archives are not implemented.
Windows executables reserve 16 MiB of stack (and WASI debug builds reserve
16 MiB) for deeply nested declarative view trees.

`ViewThatFits` evaluates candidates eagerly and clips unselected branches.
`TimelineView` uses a cancellable task rather than a display link and supports
the `.animation` schedule (bounded between 1/240s and 86,400s).
`ScrollViewReader` jumps to explicit IDs without scroll animation.
`.saturation` / `.grayscale` transform explicit colors rather than
post-composited pixels, while `.blur`, `.brightness`, and `.contrast` operate on
offscreen composited pixels (desktop) or CSS/platform filters. `Security`
Keychain APIs persist to Win32 Credential Manager on Windows and a user-only
(`0600`) XDG keystore on Linux; `ServiceManagement` manages HKCU `Run` entries
on Windows and XDG `~/.config/autostart` desktop files on Linux.
