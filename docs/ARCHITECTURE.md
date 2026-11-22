# Architecture

**Unofficial; not affiliated with Apple.**

English | [简体中文](./ARCHITECTURE-ZH.md)

CrossSwift (`crossswift`, SwiftPM manifest `CrossSwiftUI`) separates the
platform-independent declarative UI engine from platform backends, AppKit and
Apple-framework compatibility shims, and the `.xcodeproj` build toolchain.

## Modules and boundaries

- `SwiftUIRuntime` + `SwiftUIRuntimeMacros`: platform-independent view values,
  result builders, scoped `EnvironmentValues`, `@State` / `@AppStorage` /
  `@SceneStorage` / `@Binding` / `@FocusState` / `@FocusedValue` /
  `@FocusedObject`, `@Observable` (`@Bindable`) and `ObservableObject`, compiler
  macros (`@Entry` and `#Preview` over Swift's JSON plugin wire protocol without
  `swift-syntax`), element tree, layout engine (with `Spacer.minLength`,
  `.layoutPriority`, layout-preserving `.hidden()`, and viewport virtualization
  for `LazyVStack`/`LazyHStack`/`LazyVGrid`/`LazyHGrid`), sibling diff,
  controls (`DisclosureGroup`, `Gauge`, `DatePicker`, `ColorPicker`,
  `AsyncImage`, `Table`, `ShareLink`, `.fileImporter`/`.fileExporter`,
  `.redacted`, `.refreshable`, `.swipeActions`), navigation (`NavigationPath` +
  `.navigationDestination`), presentations, SVG/PDF vector parsing, embedded
  `SFSymbolCatalog`, `.xcstrings` localization (`XCStringsCatalog`), multi-segment
  `Path.trimmedPath`, rich `Canvas`, true linear/radial/angular gradients,
  timed `LongPressGesture` + gesture arbitration, and color/transition/layout
  animations. Imports no `NativeAPI`, AppKit, browser, or Android APIs.
- `CrossSwiftUI`: desktop (`NativeAPI`) integration for **Windows and Linux** —
  `WindowsDrawingBackend`, `LinuxDrawingBackend`, `NativeViewBackend`, the
  multi-scene `App` / `WindowGroup` / `Window` / `Settings` / `MenuBarExtra`
  (`.menu` and `.window`) / `Scene.commands` runner (`runApp`), native window
  dark/light chrome synchronization, and `CrossAppKit` hosting (`NSHostingView`,
  `NSHostingController`, `NSViewRepresentable`, `NSApplicationDelegateAdaptor`,
  plus `Color`/`Font`/`Image` ↔ `NSColor`/`NSFont`/`NSImage` conversions and
  `Combine` `Published`/`ObservableObjectPublisher` bridging).
- `CSwiftUIWindows`: generic Win32/DirectWrite/GDI+ retained display list,
  buffered `WM_PAINT` DIB compositor, DirectWrite text measurement and rendering
  (numeric weights 100–900, font fallback, color fonts, with GDI+ fallback),
  offscreen layer opacity and 3-pass box blur / brightness / contrast pixel
  filters, radial/angular gradients, dual-pass matte transparent `EDIT`
  compositing, borrowed `NativeAPI` `BUTTON` subclassing, focus/accessibility/tooltip
  bridge, and layered window shadow helper. Owns no application design tokens,
  domain components, or theme recipes.
- `CrossAppKit` + `AppKit` + `CAppKitWindows`: cross-platform AppKit views,
  controls, windows/panels, menus, status items, TextKit 1/2, pasteboard,
  workspace (`/proc` and `xdg-open` on Linux, Shell/Win32 on Windows),
  colors/appearances, fonts, images, and Carbon global hotkeys over
  `NativeAPI` (with Win32/DWM/Shell/COM/Credential Manager/Accessibility glue
  in `CAppKitWindows` on Windows). `CrossAppKit` compiles standalone on macOS
  for unit tests; `AppKit` is the `import AppKit` facade on Windows and Linux.
- `CrossFoundation` + framework shims: Apple `Foundation` extensions missing
  from `swift-corelibs-foundation` on Windows/Linux, standalone framework
  targets (`CoreGraphics`, full `Combine` publishers/operators/schedulers,
  `CryptoKit`, `Carbon`, `UniformTypeIdentifiers`, `OSLog`, `os`, `SQLite3`),
  and 34 system/framework shims under `Sources/AppleShims/` (including real
  `Security` Keychain persistence via Win32 Credential Manager / Linux 0600 XDG
  keystore and `ServiceManagement` login items on Windows and Linux XDG).
- `SwiftUIWeb`: WebAssembly (`os(WASI)`) `WindowGroup` hosting, DOM/SVG/CSS
  renderer (including live dark-mode sync, `openURL`, `scrollTo` DOM sync, CSS
  filters, conic/radial/linear gradients, and multi-layer SVG/PDF vectors), and
  web `.xcassets` / `.xcstrings` / SF Symbol loader via `JavaScriptKit`.
- `SwiftUIAndroid` + `CSwiftUIAndroid`: Android thread-safe `JavaVM` async
  bridge (`AndroidHost`), `Choreographer` animation loop, dark-mode & `openURL`
  sync, and Jetpack Compose host (`SwiftUIComposeHost`, `AndroidStyleRenderers`)
  supporting live switching between Material 3 + Navigation Compose and iOS 27
  Liquid Glass styling. See [ANDROID.md](ANDROID.md).
- `SwiftUIHarmony`: formal HarmonyOS runtime backend (`HarmonyBackend`) and
  parameterized ArkTS host (`CrossSwiftUIHost.ets`) with async render push,
  60 Hz animation ticks, dark-mode sync, `rawfile/Resources` extraction, and
  HarmonyOS Native / iOS Liquid Glass dual-style rendering.
- `SwiftUI`: user-facing `import SwiftUI` facade on non-Apple targets,
  re-exporting `Foundation` and `SwiftUIRuntime` together with `CrossSwiftUI`
  (+ `CrossAppKit`, `CrossFoundation`, `CoreGraphics`) on Windows/Linux,
  `SwiftUIWeb` on WASI, `SwiftUIAndroid` on Android, or `SwiftUIHarmony` under
  `CROSS_SWIFTUI_HARMONY` for HarmonyOS.
- `CrossXcodeBuild` + `CrossXcodeBuildCLI`: pure-Swift `.xcodeproj` /
  `.xcworkspace` parser, Apple-framework & SwiftPM dependency adapter,
  `.xcassets` / `.xcstrings` / icon compiler, and the `xcodebuild` CLI driver
  for Windows, Linux, WebAssembly, HarmonyOS (`HarmonyBuilder`), and Android
  (`AndroidBuilder`).

On macOS, `swift build` / `swift test` builds `SwiftUIRuntime`, `CrossAppKit`,
`CrossXcodeBuild` (`xcodebuild`), their test suites, and `Counter` compiled
against Apple's native SwiftUI. Windows, Linux, WebAssembly, HarmonyOS, and
Android builds consume CrossSwift's `SwiftUI` (and `AppKit` on desktop) facades.

## Render pass

1. Begin state collection. Install stored wrappers by structural path, concrete
   view type, and property position before evaluating each body.
2. Track `@State` and `@Observable` reads while evaluating bodies and modifiers
   under scoped `EnvironmentValues`. A local write invalidates its readers and
   ancestors; unaffected branches retain their element trees, state, and
   lifecycle entries. `ObservableObject` and untracked geometry-state writes
   invalidate conservatively.
3. Normalize fragments (preserving explicit IDs and tags), retain both slots of
   view layers, and resolve inherited foreground, color scheme, disabled,
   visibility, and alpha values.
4. Compute layout, evaluate geometry children, hoist presentations, prune state,
   and assign sibling diff keys. The drawing backends supply native text
   measurers; deterministic metrics serve headless engine tests.
5. Diff against the mounted tree, retaining `NodeID`s for matched elements.
   Keys are local to sibling lists; an unchanged sibling order uses a linear
   path without key dictionaries or move-list scans.
6. Publish the updated tree and callbacks, send backend commands, then call
   `didRender(root)`. Rendering guards coalesce writes made during a pass;
   the Windows bridge batches deferred native notifications from a message turn.

Commands are `create`, `insert`, `remove`, `move`, `setProps`, and `setFrame`.
Removing a node disposes its subtree. Actions are looked up by retained
`NodeID`, so a native callback never invokes a stale body closure. Reentrant
writes are coalesced into at most eight follow-up render passes.

## Windows backend

`WindowsDrawingBackend` (in `CrossSwiftUI`) sets `NativeAPI`'s content view to
absolute layout and publishes a retained display list after each diff. The
bridge reparents borrowed button HWNDs directly; `NativeAPI` retains their
lifetime and events, while `SwiftUIRuntime` owns layout without enrolling
controls in a second layout tree. Shapes and `Text` share the surface;
padding/frame/layer nodes determine paint order and coordinates. Native `BUTTON`
HWNDs are created only for new button IDs and retained across state, theme, and
resize changes. Hosted `CrossAppKit` views (`NSViewRepresentable`) mount once
per host identity and update in place, while `NSHostingView` and
`NSHostingController` embed independent `Renderer` instances inside AppKit
windows and panels (including borderless per-pixel alpha windows with layered
alpha-silhouette shadows). Removed controls unregister listeners and subclasses
before disposal.

`CSwiftUIWindows` subclasses the content HWND for buffered `WM_PAINT`. A
retained physical-pixel DIB is shared by the host, owner-drawn buttons, and
transparently composited `EDIT` controls (rendered over the canvas backdrop via
dual-pass matte extraction so custom search bars, placeholders, scroll views,
and disabled states blend cleanly). Display-list comparison invalidates only
changed ink bounds. Structural/clip/transform changes repaint their common
enclosing clip, or the full viewport when none is available. Painting clips to
the accumulated damage and reuses bounded font resources. `ScrollView` controls
share a fixed viewport and translated content HWND, including nested scroll
views. Scrolling moves the content host instead of every button; viewport
clipping and Tab eligibility keep offscreen controls out of input. Translations
use `DeferWindowPos` without intermediate redraws. The native `BUTTON` still
handles mouse capture, Space activation, enabled state, and `BN_CLICKED`; the
bridge adds Enter activation, ordered Tab navigation, hover/pressed/focus
callbacks, rounded hit regions, and tooltips. `EDIT` notifications update
bindings after the native message unwinds, so a render can safely remove old
controls. Deferred focus events are checked against current HWND focus. Host
events route scrolling, gestures, and shortcuts through the renderer. No global
input is injected.

Only controls intersecting the viewport acquire native handles; existing handles
remain retained when scrolled away. Unchanged labels, frames, z-order, and hit
regions skip native mutations. Local button regions exclude clipping already
performed by their viewport, so scrolling does not rebuild per-button `HRGN`s.
Offscreen text/images/shapes and transparent layout boxes do not generate
drawing commands. Within a `ScrollView`, `LazyVStack`, `LazyHStack`, `LazyVGrid`, and `LazyHGrid`
virtualize large `ForEach` collections (`> 72` items) using cached item-extent
estimates and a viewport buffer, while smaller collections evaluate eagerly to
preserve fast pixel-copy scroll translation.
A focused container chooses one native descendant rather than requesting focus
on every child.

`App.main` configures per-monitor V2 DPI awareness before application/window
initialization. Embedders should call `WindowsDrawingBackend.prepareApplication()`
before creating native windows, or provide their own DPI-aware application
manifest. All geometry is in logical points. Painting scales using
`GetDpiForWindow`; the drawing bridge converts borrowed control frames to the
same device coordinates. Native text measurement uses the same font choice as
painting. Resize uses the window's content size, not the event's decorated frame
size. Framebuffer copies specify both rectangles in pixels, avoiding GDI+'s
implicit image-DPI scaling. Display lists publish after native control updates,
so intermediate messages still paint the previous complete frame.

The backend's `activate`/`nativeButton`/`advanceFocus` methods allow integration
tests scoped to their own controls. Public `NativeAPI` core APIs and generated
bindings remain decoupled from the SwiftUI display-list renderer.

## Linux backend

`LinuxDrawingBackend` (in `CrossSwiftUI`) hosts a GTK 3 drawing area in the
`NativeAPI` window. Cairo paints the reconciled element tree (including view
masks and cached Gaussian-approximated shadow masks), and Pango supplies text
measurement and rendering. Retained GTK buttons, entries, and text views follow
the shared layout, with GTK providing keyboard focus, activation, native text
entry, multiline placeholder overlays, and AT-SPI names. Pointer and scroll
events go through the runtime hit tester. GLib coalesces renders into an idle
callback, services the Swift main queue, and schedules animated redraws. See
[DIVERGENCES.md](DIVERGENCES.md) for platform limits.

## State, layout and testing

`StateRegistry` is process-wide, with state retention and lifecycle ownership
isolated per `Renderer` root so multiple windows, `MenuBarExtra` hosts, and
`NSHostingView` instances maintain independent `@State` and `.onAppear` /
`.onDisappear` / `.task` lifecycles while sharing `@Observable` and
`ObservableObject` models. Bindings are get/set closures; focus bindings wrap
state. Environment values are saved and restored around subtrees. `.id` and
`ForEach` identifiers scope both diff identity and stored state. The runtime
interns paths by parent and child key, keeping state lookups independent of view
depth. Reevaluation retains subscriptions to state values the same view still
reads. Published and `@Observable` writes invalidate observing renderers;
`StateObject` initialization is lazy. Writes from one action or native
notification batch are published together. `ScrollView` retains its stored
content when only its internal offset changes. Lifecycle callbacks commit after
mounting, and native run-loop timers service tasks plus property and layout
animations.

Stack measurement sums main-axis sizes and takes the largest cross-axis size.
Padding adds insets; frames constrain and alignment-place a child; layers
measure the base view only. Flexible frames and spacers consume remaining
proposed space. Custom `Layout` implementations are probed for axis flexibility
rather than assumed to expand horizontally. Measurements are cached by proposal
and sizing inputs. Wrapped text and its measured size share a cache across
measurement and placement. Rebuilt `GeometryReader` content keeps layout
identities when its sizing inputs match. Placement snapshots copy geometry into
the new tree without replacing callbacks or visual properties. Unchanged
evaluation revisions reuse mounted subtrees when inherited properties also
match: moving them translates their frames, and resizing reflows them. Changed
text, fonts, constraints, alignment, scroll offsets, and child identities
invalidate the relevant caches. Opaque custom layout/guide closures take the
conservative path. Obsolete layout cache entries are reclaimed every eight
passes; changing the text measurer or fallback metrics clears them immediately.

On Windows, integer-pixel scrolls can reuse the framebuffer's interior when
visible paint commands and clip stacks are exact translations over a uniform
backdrop without intersecting stationary overlays; exposed strips, edges, and
scroll indicators repaint, and pixel regression tests compare reuse against
fresh rendering.

The test suites cover runtime layout, diffing, multi-window state isolation,
environment scope, observation, controls/containers, `CrossAppKit` shims,
`CrossXcodeBuild` project parsing/adaptation, Windows/Linux drawing, and
[`COMPAT.md`](COMPAT.md) symbol verification (`COMPATTests`). `Counter --smoke`
opens a real window and exits after three seconds to exercise the native
application loop. `Renderer.lastTimings`, `WindowsDrawingBackend.lastTimings`,
`lastPaintTimings`, and `lastReusedPixels` expose frame and rasterization
telemetry.
