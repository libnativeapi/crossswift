import CSwiftUIWindowsTestSupport
import CrossAppKit
import CrossUIKit
import NativeAPI
@testable import CrossSwiftUI
import SwiftUIRuntime
import XCTest

private final class HoverObservations {
  var taps: [Bool] = []
}

private struct HoverPeerFixture: SwiftUIRuntime.View {
  let observations: HoverObservations
  let hasEditor: Bool
  @State private var hot = false
  @State private var query = "native text"

  var body: some SwiftUIRuntime.View {
    let active = hot
    SwiftUIRuntime.VStack {
      SwiftUIRuntime.Button("Row") { observations.taps.append(active) }
        .frame(width: 100, height: 32)
        .background(active ? SwiftUIRuntime.Color.blue : .red)
        .onHover { hot = $0 }
      if hasEditor {
        SwiftUIRuntime.TextField("Query", text: $query)
          .foregroundStyle(active ? SwiftUIRuntime.Color.blue : .red)
          .frame(width: 120, height: 32)
      }
    }
  }
}

final class WindowsDrawingTests: XCTestCase {
  func testHoverPreservesNativeFocusAndDispatchesCurrentButtonActions() throws {
    func find(_ kind: ElementKind, in element: Element) -> Element? {
      if kind == element.kind { return element }
      return element.children.lazy.compactMap { find(kind, in: $0) }.first
    }
    WindowsDrawingBackend.prepareApplication()
    for hasEditor in [false, true] {
      let window = try XCTUnwrap(NativeAPI.Window.create())
      let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
      let observations = HoverObservations()
      let renderer = Renderer(backend: backend,
        root: AnyView(HoverPeerFixture(observations: observations, hasEditor: hasEditor)),
        size: .init(width: 240, height: 180))
      renderer.mount()
      defer { renderer.unmount(); _ = window.close() }
      let root = try XCTUnwrap(renderer.tree)
      let buttonID = try XCTUnwrap(find(.button, in: root)).id
      let button = try XCTUnwrap(backend.nativeButton(buttonID))
      let handle = try XCTUnwrap(button.nativeObject)
      let editorID = find(.textField, in: root)?.id
      let editor = editorID.flatMap(backend.nativeTextField)
      XCTAssertEqual(editor != nil, hasEditor)
      let focused: NativeAPI.View = editor ?? button
      focused.focus()
      XCTAssertTrue(focused.isFocused)
      let full = backend.fullPublicationCount
      renderer.interact(buttonID, .hover(true))
      XCTAssertTrue(focused.isFocused)
      XCTAssertEqual(backend.nativeButton(buttonID)?.nativeObject, handle)
      XCTAssertEqual(backend.fullPublicationCount, full + (hasEditor ? 1 : 0))
      if let editorID, let editor {
        XCTAssertEqual(backend.nativeTextField(editorID)?.nativeObject, editor.nativeObject)
        XCTAssertEqual(editor.text, "native text")
        XCTAssertGreaterThan(editor.textColor.b, editor.textColor.r)
        backend.replaceText(editorID, with: "updated")
        XCTAssertEqual(editor.text, "updated")
      }
      backend.activate(buttonID)
      renderer.interact(buttonID, .hover(false))
      backend.activate(buttonID)
      XCTAssertEqual(observations.taps, [true, false])
    }
  }
  func testColorFramesKeepButtonPeersAndRefreshNativeEditors() throws {
    struct Content: SwiftUIRuntime.View {
      let nativeEditor: Bool
      @State var active = false
      @State var query = ""
      var body: some SwiftUIRuntime.View {
        SwiftUIRuntime.ScrollView {
          SwiftUIRuntime.VStack(spacing: 0) {
            SwiftUIRuntime.Button("Toggle") {
              SwiftUIRuntime.withAnimation(.linear(duration: 1)) { active.toggle() }
            }
            SwiftUIRuntime.Text("Card").background(active ? SwiftUIRuntime.Color.blue : .red)
            if nativeEditor { SwiftUIRuntime.TextField("Query", text: $query) }
            SwiftUIRuntime.Text("Tail").frame(height: 800)
          }
        }
      }
    }
    func node(_ kind: ElementKind, in element: Element) -> Element? {
      if element.kind == kind { return element }
      return element.children.lazy.compactMap { node(kind, in: $0) }.first
    }
    WindowsDrawingBackend.prepareApplication()
    for nativeEditor in [false, true] {
      var now = 10.0
      let window = try XCTUnwrap(NativeAPI.Window.create())
      let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
      let renderer = Renderer(backend: backend, root: AnyView(Content(nativeEditor: nativeEditor)),
                              size: .init(width: 300, height: 160))
      renderer.clock = { now }
      renderer.mount()
      let buttonID = try XCTUnwrap(node(.button, in: try XCTUnwrap(renderer.tree))?.id)
      let button = try XCTUnwrap(backend.nativeButton(buttonID)?.nativeObject)
      renderer.performTap(buttonID)
      let full = backend.fullPublicationCount
      now += 0.2
      XCTAssertTrue(renderer.stepAnimations())
      XCTAssertEqual(backend.fullPublicationCount, full + (nativeEditor ? 1 : 0))
      if !nativeEditor { XCTAssertEqual(backend.lastTimings["controls"], 0) }
      now += 0.2
      XCTAssertTrue(renderer.input(event: 5, point: .init(x: 120, y: 80), value: -8))
      let scroll = try XCTUnwrap(node(.scroll, in: try XCTUnwrap(renderer.tree)))
      XCTAssertGreaterThan(scroll.props.scrollOffset.y, 0)
      XCTAssertEqual(backend.fullPublicationCount, full + (nativeEditor ? 2 : 0))
      XCTAssertEqual(backend.nativeButton(buttonID)?.nativeObject, button)
      if nativeEditor {
        let editID = try XCTUnwrap(node(.textField, in: try XCTUnwrap(renderer.tree))?.id)
        XCTAssertNotNil(backend.nativeTextField(editID))
      }
      renderer.unmount()
    }
  }

  func testTransparentNativeButtonKeepsShortcutWithoutCoveringCanvas() throws {
    final class Model: ObservableObject {
      @Published var opacity = 0.0
      var clicks = 0
    }
    struct Content: SwiftUIRuntime.View {
      @ObservedObject var model: Model
      var body: some SwiftUIRuntime.View {
        SwiftUIRuntime.Button("Shortcut") { model.clicks += 1 }
          .keyboardShortcut(.return, modifiers: .option)
          .opacity(model.opacity)
      }
    }
    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    XCTAssertFalse(backend.needsRenderCommands)
    let model = Model()
    let renderer = Renderer(backend: backend, root: AnyView(Content(model: model)),
                            size: .init(width: 300, height: 200))
    renderer.mount()
    func buttonID(_ element: Element) -> NodeID? {
      if element.kind == .button { return element.id }
      return element.children.lazy.compactMap(buttonID).first
    }
    let id = try XCTUnwrap(buttonID(try XCTUnwrap(renderer.tree)))
    let button = try XCTUnwrap(backend.nativeButton(id))
    let handle = try XCTUnwrap(button.nativeObject)
    func opacity(_ element: Element) -> Double? {
      if element.id == id { return element.props.opacity }
      return element.children.lazy.compactMap(opacity).first
    }
    XCTAssertEqual(opacity(try XCTUnwrap(renderer.tree)), 0)
    XCTAssertEqual(control_visible(handle), 0)
    XCTAssertTrue(renderer.input(id: nil, event: 6, point: .zero, value: 13,
                                 modifiers: .option))
    XCTAssertEqual(model.clicks, 1)
    model.opacity = 1
    renderer.renderIfNeeded()
    XCTAssertEqual(control_visible(handle), 1)
    model.opacity = 0
    renderer.renderIfNeeded()
    XCTAssertEqual(control_visible(handle), 0)
    XCTAssertTrue(renderer.input(id: nil, event: 6, point: .zero, value: 13,
                                 modifiers: .option))
    XCTAssertEqual(model.clicks, 2)
  }
  func testSidebarCollapseAnimatesAndClipsNativeTextFieldWithoutHidingEarly() throws {
    struct SidebarHost: SwiftUIRuntime.View {
      @State private var open = true
      @State private var query = "Filter"
      var body: some SwiftUIRuntime.View {
        SwiftUIRuntime.HStack(spacing: 0) {
          SwiftUIRuntime.VStack(spacing: 0) {
            SwiftUIRuntime.TextField("Search", text: $query)
              .padding(8)
              .frame(width: 200, height: 32)
          }
          .frame(width: 220, height: 200)
          .frame(width: open ? 220 : 0, alignment: .leading)
          .clipped()
          .allowsHitTesting(open)

          SwiftUIRuntime.Button("Toggle") {
            SwiftUIRuntime.withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.2)) {
              open.toggle()
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    var now = 50.0
    let renderer = Renderer(
      backend: backend, root: AnyView(SidebarHost()), size: .init(width: 500, height: 200))
    renderer.clock = { now }
    renderer.mount()

    func findKind(_ kind: ElementKind, in node: Element) -> NodeID? {
      if node.kind == kind { return node.id }
      return node.children.lazy.compactMap { findKind(kind, in: $0) }.first
    }
    let tree = try XCTUnwrap(renderer.tree)
    let editID = try XCTUnwrap(findKind(.textField, in: tree))
    let buttonID = try XCTUnwrap(findKind(.button, in: tree))
    let field = try XCTUnwrap(backend.nativeTextField(editID))
    let editHandle = try XCTUnwrap(field.nativeObject)
    let fullClipWidth = control_clip_width(editHandle)
    XCTAssertEqual(control_visible(editHandle), 1)
    XCTAssertGreaterThan(fullClipWidth, 0)

    renderer.performTap(buttonID)
    XCTAssertTrue(renderer.hasActiveAnimations)
    // Even with `.allowsHitTesting(false)` during collapse, the native EDIT
    // stays visible and progressively clips against the shrinking sidebar edge.
    XCTAssertEqual(control_visible(editHandle), 1)
    XCTAssertFalse(field.isEnabled)

    now = 50.05
    XCTAssertTrue(renderer.stepAnimations())
    let midClipWidth = control_clip_width(editHandle)
    XCTAssertEqual(control_visible(editHandle), 1)
    XCTAssertGreaterThan(midClipWidth, 0)
    XCTAssertLessThan(midClipWidth, fullClipWidth)

    now = 50.25
    XCTAssertFalse(renderer.stepAnimations())
    XCTAssertEqual(control_visible(editHandle), 0)
    XCTAssertEqual(control_clip_width(editHandle), 0)
  }
  func testResizingMultilineEditorClearsPixelsExposedBySidebarCollapse() {
    WindowsDrawingBackend.prepareApplication()
    XCTAssertEqual(editor_resize_probe(), 0,
      "A moved multiline editor must erase its full native frame, including unused line space")
  }
  func testShadowMaskFalloffTintOpacityClippingAndRetainedLifetime() throws {
    WindowsDrawingBackend.prepareApplication()
    for scale in [1.0, 2.0] {
      let mask = try XCTUnwrap(ShadowMask(width: 200, height: 160, cornerRadius: 12,
                                         radius: 24, scale: scale))
      let errors = mask.alpha.withUnsafeBufferPointer {
        shadow_probe($0.baseAddress, Int32(mask.width), Int32(mask.height), mask.inset, mask.scale)
      }
      XCTAssertEqual(errors, 0)
    }
  }
  func testScrollPixelReuseMatchesFreshRenderingAndFallsBackForUnsafeFrames() {
    WindowsDrawingBackend.prepareApplication()
    let result = scroll_probe()
    XCTAssertGreaterThanOrEqual(result.copies, 4)
    XCTAssertEqual(result.pixel_errors, 0, "Cached scroll pixels must exactly match a fresh render")
    XCTAssertEqual(
      result.fallback_errors, 0,
      "Backgrounds, overlays, content edits and fractional pixels must fall back")
  }
  func testRotatingNativeControlsMovesOnlyTheDisplacedSibling() {
    WindowsDrawingBackend.prepareApplication()
    XCTAssertEqual(control_order_probe(), 0)
  }

  func testHighDpiPixelsAndHoverDoNotRepositionControls() {
    WindowsDrawingBackend.prepareApplication()
    let result = drawing_probe()
    print("Windows drawing probe: \(result.dpi) DPI, \(result.hover_events) hover transitions")
    XCTAssertEqual(result.aware, 1, "Windows must use per-monitor V2 before creating HWNDs")
    XCTAssertGreaterThanOrEqual(result.dpi, 96)
    XCTAssertEqual(result.pixel_errors, 0, "The framebuffer must be copied at physical pixel size")
    XCTAssertEqual(
      result.child_pixel_errors, 0, "Owner-drawn controls must share the host's exact pixels")
    XCTAssertEqual(result.hover_events, 40)
    XCTAssertEqual(result.expose_errors, 0,
      "Full exposes must paint the canvas once and retain native-widget overlap paints")
    XCTAssertEqual(
      result.position_changes, 0, "Hover must not re-order or reset the region of a control")
    XCTAssertEqual(
      result.immediate_paints, 0, "Publishing a frame must not paint intermediate states")
    XCTAssertEqual(
      result.clip_errors, 0, "Clipping must recover when a control scrolls back into view")
    XCTAssertEqual(
      result.atomic_errors, 0, "A native paint during updates must see a complete frame")
    XCTAssertGreaterThan(result.damage_pixels, 0)
    XCTAssertLessThan(
      result.damage_pixels, result.surface_pixels / 2,
      "Hover should invalidate the button's ink, not the full window")
    XCTAssertEqual(
      result.scope_errors, 0, "Changing visible commands must repaint only their shared clip")
    XCTAssertEqual(
      result.group_errors, 0,
      "Nested scrolling must preserve pixels, native coordinates, activation and Tab order")
  }

  @MainActor
  func testNSPanelHostsSwiftUIViewWithObservableAndNSViewRepresentable() async throws {
    let state = PanelState()
    weak var reportedWindow: CrossAppKit.NSWindow?
    let panel = CrossAppKit.NSPanel(
      contentRect: NSRect(x: 100, y: 100, width: 400, height: 120),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.backgroundColor = .clear
    let hosting = NSHostingView(rootView: PanelContent(onWindow: { reportedWindow = $0 }).environment(state))
    hosting.sizingOptions = []
    panel.contentView = hosting

    let renderer = try XCTUnwrap(hosting.renderer)
    XCTAssertTrue(reportedWindow === panel)
    func hasText(_ expected: String, in node: Element) -> Bool {
      if node.kind == .text && node.props.text == expected { return true }
      return node.children.contains { hasText(expected, in: $0) }
    }
    XCTAssertTrue(hasText("Search apps", in: try XCTUnwrap(renderer.tree)))

    state.query = "Calculator: 42"
    renderer.renderIfNeeded()
    XCTAssertTrue(hasText("Calculator: 42", in: try XCTUnwrap(renderer.tree)))
    panel.close()
  }

  @MainActor
  func testSFSymbolCatalogAndStringLocalizedOnWindows() async {
    _ = NSHostingView(rootView: SwiftUIRuntime.EmptyView())
    let sampleSymbols = [
      "magnifyingglass", "gearshape", "sparkles", "apple.intelligence",
      "doc.on.clipboard", "macwindow", "puzzlepiece.extension", "stop.fill"
    ]
    for sym in sampleSymbols {
      XCTAssertNotNil(CrossAppKit.NSImage(systemSymbolName: sym, accessibilityDescription: nil), "Missing symbol \(sym)")
    }
    XCTAssertNil(CrossAppKit.NSImage(systemSymbolName: "CustomBrandAssetName", accessibilityDescription: nil))

    let msg = String(localized: "Found \(5) apps")
    XCTAssertEqual(msg, "Found 5 apps")
  }

  func testPDFVectorParserHandlesUncompressedAndFlateDecodePDFs() throws {
    let rawStream = "q 1 0 0 1 0 0 cm 2 4 m 18 4 l 18 16 l 2 16 l h f Q"
    let uncompressedPDF = """
    %PDF-1.4
    1 0 obj << /Type /Page /MediaBox [0 0 20 20] >> endobj
    2 0 obj << /Length \(rawStream.utf8.count) >>
    stream
    \(rawStream)
    endstream
    endobj
    %%EOF
    """
    let img = try XCTUnwrap(PDFVectorParser.parse(data: Data(uncompressedPDF.utf8)))
    XCTAssertEqual(img.bounds, CGRect(x: 0, y: 0, width: 20, height: 20))
    XCTAssertEqual(img.paths.count, 1)

    // Verify FlateDecode using a stored (uncompressed) zlib block wrapping the same content stream.
    let payload = Array(rawStream.utf8)
    var zlibBytes: [UInt8] = [0x78, 0x01] // zlib header (deflate, fastest)
    zlibBytes.append(0x01) // BFINAL=1, BTYPE=00 (stored block)
    let len = UInt16(payload.count)
    let nlen = ~len
    zlibBytes.append(UInt8(len & 0xFF))
    zlibBytes.append(UInt8((len >> 8) & 0xFF))
    zlibBytes.append(UInt8(nlen & 0xFF))
    zlibBytes.append(UInt8((nlen >> 8) & 0xFF))
    zlibBytes.append(contentsOf: payload)
    zlibBytes.append(contentsOf: [0, 0, 0, 0]) // placeholder adler32

    var compressedPDF = Data("%PDF-1.4\n1 0 obj << /Type /Page /MediaBox [0 0 20 20] >> endobj\n2 0 obj << /Filter /FlateDecode /Length \(zlibBytes.count) >>\nstream\n".utf8)
    compressedPDF.append(contentsOf: zlibBytes)
    compressedPDF.append(Data("\nendstream\nendobj\n%%EOF\n".utf8))

    let flateImg = try XCTUnwrap(PDFVectorParser.parse(data: compressedPDF))
    XCTAssertEqual(flateImg.bounds, CGRect(x: 0, y: 0, width: 20, height: 20))
    XCTAssertEqual(flateImg.paths.count, 1)

    // Verify VectorImage.load loads .pdf files from disk.
    let tmpPDF = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossswift-vector-\(UUID().uuidString).pdf")
    try compressedPDF.write(to: tmpPDF)
    defer { try? FileManager.default.removeItem(at: tmpPDF) }

    let loaded = try XCTUnwrap(VectorImage.load(tmpPDF.path))
    XCTAssertEqual(loaded.bounds, CGRect(x: 0, y: 0, width: 20, height: 20))
    XCTAssertEqual(loaded.paths.count, 1)
  }

  @MainActor
  func testUIHostingControllerAndUIKitRepresentablesInUIWindow() async throws {
    let session = UISceneSession(role: .windowApplication)
    let scene = UIWindowScene(session: session, connectionOptions: .init())
    let uiWindow = UIWindow(windowScene: scene)
    uiWindow.frame = CGRect(x: 120, y: 120, width: 640, height: 420)

    let state = UIKitPanelProbeState()
    var observedWindow: UIWindow?
    var observedVCFrame: CGRect = .zero

    let hosting = UIHostingController(
      rootView: UIKitPanelProbeContent(
        onViewWindow: { observedWindow = $0 },
        onControllerFrame: { observedVCFrame = $0 }
      )
      .environment(state)
    )
    uiWindow.rootViewController = hosting
    uiWindow.makeKeyAndVisible()

    let renderer = try XCTUnwrap(hosting.hostingView.renderer)
    XCTAssertTrue(observedWindow === uiWindow)
    XCTAssertEqual(observedVCFrame.width, 196, accuracy: 1.0)
    XCTAssertEqual(observedVCFrame.height, 28, accuracy: 1.0)

    func hasText(_ needle: String, in node: Element) -> Bool {
      if node.props.text == needle { return true }
      return node.children.contains { hasText(needle, in: $0) }
    }
    XCTAssertTrue(hasText("UIKit Ready", in: try XCTUnwrap(renderer.tree)))

    state.headline = "UIKit Updated: 99"
    renderer.renderIfNeeded()
    XCTAssertTrue(hasText("UIKit Updated: 99", in: try XCTUnwrap(renderer.tree)))

    // Verify UIGraphicsImageRenderer produces real PNG bytes via CSwiftUIWindows offscreen canvas
    let gfx = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 32))
    let chartImg = gfx.image { _ in
      UIColor.systemBlue.setFill()
      UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 44, height: 28), cornerRadius: 6).fill()
    }
    let png = try XCTUnwrap(chartImg.pngData())
    XCTAssertGreaterThan(png.count, 32)
    XCTAssertNotNil(UIImage(systemName: "sparkles"))

    uiWindow.isHidden = true
  }

  @MainActor
  func testTemplateSVGImagesetAndSymbolStatusItemIconOnWindows() async throws {
    _ = NSHostingView(rootView: SwiftUIRuntime.EmptyView())
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("CrossTraySVG-\(UUID().uuidString)")
    let imageset = tmp.appendingPathComponent("Assets.xcassets/MenuBarIcon.imageset")
    try fm.createDirectory(at: imageset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    try """
    {
      "images": [{ "filename": "thunder.svg", "idiom": "universal" }],
      "properties": { "template-rendering-intent": "template" }
    }
    """.write(to: imageset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    let svgURL = imageset.appendingPathComponent("thunder.svg")
    try """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="14" viewBox="4.6 1.7 14.8 20.6"><path d="M18.82 9.18A2 2 0 0 0 17 8h-1.81l1.33-3.26a2 2 0 0 0-.19-1.84 2.06 2.06 0 0 0-1.71-.9h-4.34a2 2 0 0 0-1.91 1.27l-3.23 8a2 2 0 0 0 .2 1.83 2.06 2.06 0 0 0 1.71.9h2.76L8 20.74a1 1 0 0 0 .5 1.15A1.1 1.1 0 0 0 9 22a1 1 0 0 0 .76-.35l8.8-10.37a2 2 0 0 0 .26-2.1"/></svg>
    """.write(to: svgURL, atomically: true, encoding: .utf8)

    let nsImg = try XCTUnwrap(CrossAppKit.NSImage(contentsOfFile: svgURL.path))
    XCTAssertTrue(nsImg.isTemplate)
    XCTAssertNotNil(nsImg.toNativeImage())

    let item = CrossAppKit.NSStatusBar.system.statusItem(withLength: CrossAppKit.NSStatusItem.variableLength)
    defer { CrossAppKit.NSStatusBar.system.removeStatusItem(item) }
    item.button?.image = nsImg
    XCTAssertEqual(item.nativeTrayIcon?.isIconTemplate, true)
    XCTAssertNotNil(item.nativeTrayIcon?.icon)

    let symImg = try XCTUnwrap(CrossAppKit.NSImage(systemSymbolName: "calendar", accessibilityDescription: nil))
    XCTAssertTrue(symImg.isTemplate)
    item.button?.image = symImg
    XCTAssertNotNil(item.nativeTrayIcon?.icon)
  }

  func testPopoverKeepsBackgroundButtonAndSidebarPlaceholderVisibleOnCanvas() throws {
    final class PopoverModel: ObservableObject {
      @Published var picking = false
      @Published var query = ""
    }
    struct PopoverScene: SwiftUIRuntime.View {
      @ObservedObject var model: PopoverModel
      var body: some SwiftUIRuntime.View {
        SwiftUIRuntime.HStack(spacing: 20) {
          SwiftUIRuntime.TextField("Search", text: $model.query)
            .frame(width: 160, height: 28)
          SwiftUIRuntime.VStack(spacing: 12) {
            SwiftUIRuntime.Spacer()
            SwiftUIRuntime.Button("Covered Row") {}
            SwiftUIRuntime.Button("Add Application…") { model.picking = true }
              .popover(isPresented: $model.picking, arrowEdge: .bottom) {
                SwiftUIRuntime.Text("App Picker")
                  .frame(width: 140, height: 80)
              }
          }
        }
        .padding(16)
        .frame(width: 460, height: 260)
      }
    }

    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    defer { _ = window.close() }
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    let model = PopoverModel()
    let renderer = Renderer(
      backend: backend, root: AnyView(PopoverScene(model: model)),
      size: .init(width: 460, height: 260))
    renderer.mount()

    func collectNodes(_ kind: ElementKind, in node: Element, into out: inout [Element]) {
      if node.kind == kind { out.append(node) }
      for child in node.children { collectNodes(kind, in: child, into: &out) }
    }
    var initialFields: [Element] = []
    collectNodes(.textField, in: try XCTUnwrap(renderer.tree), into: &initialFields)
    let searchID = try XCTUnwrap(initialFields.first?.id)
    let searchEdit = try XCTUnwrap(backend.nativeTextField(searchID))
    let searchHandle = try XCTUnwrap(searchEdit.nativeObject)
    let clipBefore = control_clip_width(searchHandle)
    XCTAssertEqual(control_visible(searchHandle), 1)
    XCTAssertGreaterThan(clipBefore, 0)

    model.picking = true
    renderer.renderIfNeeded()

    let tree = try XCTUnwrap(renderer.tree)
    let base = try XCTUnwrap(tree.children.first)
    var buttons: [Element] = []
    collectNodes(.button, in: base, into: &buttons)
    let coveredButton = try XCTUnwrap(buttons.first { $0.props.text == "Covered Row" })
    let addButton = try XCTUnwrap(buttons.first { $0.props.text == "Add Application…" })

    // Non-occluded sidebar TextField and anchor Button keep their exact live HWNDs (zero glyph shift).
    XCTAssertEqual(control_visible(searchHandle), 1)
    XCTAssertEqual(control_clip_width(searchHandle), clipBefore)
    XCTAssertTrue(searchEdit.isEnabled)

    let addNative = try XCTUnwrap(backend.nativeButton(addButton.id))
    let addHandle = try XCTUnwrap(addNative.nativeObject)
    XCTAssertEqual(control_visible(addHandle), 1)
    XCTAssertTrue(addNative.isEnabled)

    // Occluded button directly underneath the popover hides its HWND so the popover sits cleanly on top.
    let coveredNative = try XCTUnwrap(backend.nativeButton(coveredButton.id))
    let coveredHandle = try XCTUnwrap(coveredNative.nativeObject)
    XCTAssertEqual(control_visible(coveredHandle), 0)
  }

  @MainActor
  func testSingleLineTransparentNSTextViewPreservesUnderlyingPlaceholderAndHandlesDelegateCommands() async throws {
    let win = CrossAppKit.NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 320, height: 140),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    defer { win.close() }

    let state = AliasProbeState()
    let hosting = NSHostingView(rootView: AliasProbeView(state: state))
    hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
    win.contentView = hosting
    win.makeKeyAndOrderFront(nil)
    hosting.layoutSubtreeIfNeeded()

    let renderer = try XCTUnwrap(hosting.renderer)
    func findHosted(_ node: Element) -> Element? {
      if node.kind == .hostedView { return node }
      return node.children.lazy.compactMap(findHosted).first
    }
    let hostedNode = try XCTUnwrap(findHosted(try XCTUnwrap(renderer.tree)))
    let editorView = try XCTUnwrap(state.lastEditor)
    let nativeEditor = try XCTUnwrap(editorView.ownedNativeView)
    let editHandle = try XCTUnwrap(nativeEditor.nativeObject)

    // 1. Single-line NSTextView must NOT have ES_MULTILINE or WS_VSCROLL scrollbar.
    XCTAssertTrue(editorView.isSingleLineEditor)
    XCTAssertEqual(control_is_multiline_edit(editHandle), 0)
    XCTAssertEqual(control_has_vscroll(editHandle), 0)
    XCTAssertGreaterThan(hostedNode.frame.width, 80)

    // 2. Transparent compositing on the EDIT HWND must preserve the SwiftUI "Add Alias" placeholder underneath.
    let emptyDistinctPixels = control_print_distinct_pixels(editHandle)
    XCTAssertGreaterThan(
      emptyDistinctPixels, 20,
      "Transparent single-line NSTextView must composite underlying 'Add Alias' text instead of an opaque rectangle"
    )

    // 3. Focusing, typing, pressing Enter (commit + resign), and pressing Escape (revert + resign).
    XCTAssertTrue(win.makeFirstResponder(editorView))
    XCTAssertTrue(state.focused)
    XCTAssertEqual(state.beginCount, 1)

    control_send_char(editHandle, Int32(("g" as UnicodeScalar).value))
    control_send_char(editHandle, Int32(("o" as UnicodeScalar).value))
    hosting.layoutSubtreeIfNeeded()
    XCTAssertEqual(state.draft, "go")

    // Pressing Enter invokes doCommandBy(.insertNewline) -> makeFirstResponder(nil) -> textDidEndEditing -> commit.
    control_send_key(editHandle, 0x0D)
    hosting.layoutSubtreeIfNeeded()
    XCTAssertFalse(state.focused)
    XCTAssertEqual(state.endCount, 1)
    XCTAssertEqual(state.committedAlias, "go")

    // Re-focus, edit draft, then press Escape -> doCommandBy(.cancelOperation) reverts to committedAlias.
    XCTAssertTrue(win.makeFirstResponder(editorView))
    XCTAssertTrue(state.focused)
    control_send_char(editHandle, Int32(("x" as UnicodeScalar).value))
    hosting.layoutSubtreeIfNeeded()
    control_send_key(editHandle, 0x1B)
    hosting.layoutSubtreeIfNeeded()
    XCTAssertFalse(state.focused)
    XCTAssertEqual(state.draft, "go")
    XCTAssertEqual(state.committedAlias, "go")
  }

  @MainActor
  func testDefaultButtonInDarkFormRendersCustomBezelInsteadOfLightWin32Chrome() async throws {
    var tapped = 0
    let scene = SwiftUIRuntime.Form {
      SwiftUIRuntime.Section {
        SwiftUIRuntime.HStack {
          SwiftUIRuntime.Text("Providers")
          SwiftUIRuntime.Spacer()
          SwiftUIRuntime.Button("Manage…") { tapped += 1 }
        }
      }
    }
    .formStyle(.grouped)
    .background(SwiftUIRuntime.Color(red: 0.10, green: 0.10, blue: 0.11))
    .preferredColorScheme(.dark)

    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    defer { _ = window.close() }
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    backend.setBackgroundColor(SwiftUIRuntime.Color(red: 0.10, green: 0.10, blue: 0.11))
    backend.environmentTransform = { $0.colorScheme = .dark }
    let renderer = Renderer(
      backend: backend, root: AnyView(scene), size: .init(width: 480, height: 180))
    renderer.mount()

    func findButton(_ node: Element) -> Element? {
      if node.kind == .button, node.props.text == "Manage…" { return node }
      return node.children.lazy.compactMap(findButton).first
    }
    let manageEl = try XCTUnwrap(findButton(try XCTUnwrap(renderer.tree)))
    let manageNative = try XCTUnwrap(backend.nativeButton(manageEl.id))
    let manageHandle = try XCTUnwrap(manageNative.nativeObject)

    // Sample interior background pixel near the left bezel padding: must render dark surface fill
    // rather than an unthemed >200 RGB light Win32 GDI push button.
    let interiorRGB = control_print_pixel(manageHandle, 6, 6)
    let r = Int((interiorRGB >> 16) & 0xFF)
    let g = Int((interiorRGB >> 8) & 0xFF)
    let b = Int(interiorRGB & 0xFF)
    XCTAssertLessThan(r, 90, "Dark-mode default Button must not paint light Win32 button chrome")
    XCTAssertLessThan(g, 90)
    XCTAssertLessThan(b, 95)
    XCTAssertGreaterThan(control_print_distinct_pixels(manageHandle), 20, "Button title glyphs must render inside custom-drawn button")

    backend.activate(manageEl.id)
    XCTAssertEqual(tapped, 1)
  }

  @MainActor
  func testChatPresetSymbolPickerPopoverRendersAll28IconsInCleanSixColumnGrid() async throws {
    let presetSymbols = [
      "text.bubble", "bubble.left.and.bubble.right", "person.crop.circle", "brain", "lightbulb",
      "sparkles", "graduationcap", "book", "doc.text", "pencil.and.outline", "magnifyingglass",
      "chart.bar", "globe", "character.bubble", "curlybraces", "terminal", "ladybug", "hammer",
      "paintbrush", "megaphone", "envelope", "briefcase", "cart", "heart", "star", "flag", "leaf",
      "bolt",
    ]
    for sym in presetSymbols {
      XCTAssertNotNil(
        CrossAppKit.NSImage(systemSymbolName: sym, accessibilityDescription: nil),
        "Missing SF Symbol in catalog: \(sym)")
    }

    @MainActor
    final class PopoverState: ObservableObject {
      @Published var open = false
      @Published var notes = ""
    }

    struct PresetIconPopoverProbe: SwiftUIRuntime.View {
      let symbols: [String]
      @ObservedObject var state: PopoverState
      var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6)
      }
      var body: some SwiftUIRuntime.View {
        SwiftUIRuntime.ScrollView {
          SwiftUIRuntime.VStack(alignment: .leading, spacing: 12) {
            SwiftUIRuntime.Color.clear.frame(height: 360)
            SwiftUIRuntime.HStack {
              SwiftUIRuntime.Spacer()
              SwiftUIRuntime.Button("Automatic") { state.open = true }
                .popover(isPresented: $state.open, arrowEdge: .bottom) {
                  SwiftUIRuntime.VStack(alignment: .leading, spacing: 8) {
                    SwiftUIRuntime.LazyVGrid(columns: columns, spacing: 6) {
                      SwiftUIRuntime.ForEach(symbols, id: \.self) { symbol in
                        SwiftUIRuntime.Button {} label: {
                          SwiftUIRuntime.Image(systemName: symbol)
                            .font(.system(size: 15, weight: .regular))
                            .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                      }
                    }
                  }
                  .padding(8)
                  .frame(width: 244)
                }
            }
            SwiftUIRuntime.TextEditor(text: $state.notes)
              .frame(height: 220)
          }
          .padding(18)
        }
        .preferredColorScheme(.dark)
      }
    }

    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    defer { _ = window.close() }
    window.setContentSize(NativeAPI.Size(width: 480, height: 520))
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    backend.setBackgroundColor(SwiftUIRuntime.Color(red: 0.11, green: 0.11, blue: 0.12))
    backend.environmentTransform = { $0.colorScheme = .dark }
    let state = PopoverState()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(PresetIconPopoverProbe(symbols: presetSymbols, state: state)),
      size: .init(width: 480, height: 520))
    renderer.mount()
    // Scroll outer ScrollView past multiple 128pt buckets, then open the Icon popover.
    for _ in 0..<3 {
      renderer.input(event: 5, point: CGPoint(x: 240, y: 260), value: -360)
    }
    state.open = true
    renderer.renderIfNeeded()

    let tree = try XCTUnwrap(renderer.tree)
    let popoverPanel = try XCTUnwrap(tree.children.last)
    var iconButtons: [Element] = []
    func collectStyledButtons(_ node: Element) {
      if node.kind == .styledButton { iconButtons.append(node); return }
      for child in node.children { collectStyledButtons(child) }
    }
    collectStyledButtons(popoverPanel)
    XCTAssertEqual(iconButtons.count, 28, "All 28 preset icon cells must materialize inside popover")

    for (idx, btn) in iconButtons.enumerated() {
      let col = idx % 6
      let row = idx / 6
      if col > 0 {
        let prev = iconButtons[idx - 1]
        XCTAssertEqual(btn.frame.minY, prev.frame.minY, accuracy: 0.5)
        XCTAssertEqual(btn.frame.minX - prev.frame.maxX, 6.0, accuracy: 0.5)
      } else if row > 0 {
        let above = iconButtons[idx - 6]
        XCTAssertEqual(btn.frame.minX, above.frame.minX, accuracy: 0.5)
        XCTAssertEqual(btn.frame.minY - above.frame.maxY, 6.0, accuracy: 0.5)
      }
      let nativeBtn = try XCTUnwrap(backend.nativeButton(btn.id))
      let handle = try XCTUnwrap(nativeBtn.nativeObject)
      XCTAssertGreaterThan(
        control_print_distinct_pixels(handle), 6,
        "Symbol at index \(idx) (\(presetSymbols[idx])) rendered blank inside popover")
    }
  }

  @MainActor
  func testBorderlessTransparentPanelFormEditsRenderNonBlackOnInitialShow() async throws {
    WindowsDrawingBackend.prepareApplication()
    _ = NativeAPI.Application.shared.isRunning()
    CrossAppKit.NSApplication.shared.appearance = CrossAppKit.NSAppearance(named: .darkAqua)

    let state = MCPProbeState()
    let hosting = NSHostingView(rootView: MCPEditorProbe(state: state))
    hosting.setFrameSize(NSSize(width: 1, height: 1))
    hosting.layoutSubtreeIfNeeded()
    let fitting = hosting.fittingSize
    hosting.setFrameSize(NSSize(width: max(520, fitting.width), height: max(460, fitting.height)))

    let panel = CrossAppKit.NSPanel(
      contentRect: NSRect(origin: .zero, size: hosting.frame.size),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    panel.isOpaque = false
    panel.backgroundColor = CrossAppKit.NSColor.clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.contentView = hosting
    defer { panel.close() }

    panel.setFrameOrigin(NSPoint(x: 180, y: 160))
    panel.makeKeyAndOrderFront(nil)
    pump_pending_win32_messages()

    // Mimic SettingsEditorPresenter.focusAfterLayout(panel:)
    panel.makeKey()
    panel.selectNextKeyView(nil)
    pump_pending_win32_messages()

    let backend = try XCTUnwrap(hosting.backend)
    let renderer = try XCTUnwrap(hosting.renderer)
    let tree = try XCTUnwrap(renderer.tree)
    var fieldNodes: [Element] = []
    func collectFields(_ node: Element) {
      if node.kind == .textField { fieldNodes.append(node); return }
      for child in node.children { collectFields(child) }
    }
    collectFields(tree)
    XCTAssertEqual(fieldNodes.count, 4, "Expected Name, URL, Header, Value fields")

    let rootHwnd = try XCTUnwrap(panel.nativeWindow?.nativeObject)
    let hostHwnd = try XCTUnwrap(panel.nativeWindow?.contentView?.nativeObject)
    let dpiScale = Double(CrossAppKit.NSScreen.main?.backingScaleFactor ?? 1.0)

    for (index, fieldNode) in fieldNodes.enumerated() {
      let tf = try XCTUnwrap(backend.nativeTextField(fieldNode.id))
      let hwnd = try XCTUnwrap(tf.nativeObject)
      let hostOffX = Int(control_offset_in_host_x(hostHwnd, hwnd))
      let hostOffY = Int(control_offset_in_host_y(hostHwnd, hwnd))
      let expectedMinX = Int((44.0 * dpiScale).rounded())
      let expectedMinY = Int((44.0 * dpiScale).rounded())
      XCTAssertGreaterThan(
        hostOffX, expectedMinX,
        "Field[\(index)] X offset (\(hostOffX)) missed transparent envelope offset")
      XCTAssertGreaterThan(
        hostOffY, expectedMinY,
        "Field[\(index)] Y offset (\(hostOffY)) missed transparent envelope offset")

      // Sample right-side background pixel of each field in composed DWM window output
      let sampleX = Int32(max(4, Int((fieldNode.frame.width * 0.85 * dpiScale).rounded())))
      let sampleY = Int32(max(2, Int((fieldNode.frame.height * 0.5 * dpiScale).rounded())))
      let argb = control_screen_pixel_in_window(rootHwnd, hwnd, sampleX, sampleY)
      let r = (argb >> 16) & 0xFF
      let g = (argb >> 8) & 0xFF
      let b = argb & 0xFF
      XCTAssertGreaterThan(
        r, 25,
        "Field[\(index)] rendered black on initial show before click: argb=0x\(String(argb, radix: 16))")
      XCTAssertEqual(Int(r), Int(g), accuracy: 8)
      XCTAssertGreaterThan(b, 25)
    }

    // Header ("Authorization") must also render light text ink on dark field background
    let headerHwnd = try XCTUnwrap(backend.nativeTextField(fieldNodes[2].id)?.nativeObject)
    var maxLuma = 0
    for px in stride(from: 2, to: 90, by: 2) {
      let p = control_screen_pixel_in_window(
        rootHwnd, headerHwnd, Int32(px), Int32((10.0 * dpiScale).rounded()))
      let lum = Int(((p >> 16) & 0xFF) + ((p >> 8) & 0xFF) + (p & 0xFF)) / 3
      if lum > maxLuma { maxLuma = lum }
    }
    XCTAssertGreaterThan(maxLuma, 120, "Header initial text 'Authorization' must render light glyphs, got maxLuma=\(maxLuma)")
  }
}

@MainActor
@Observable
private final class MCPProbeState {
  var name = ""
  var url = ""
  var headerName = "Authorization"
  var headerValue = ""
  var usesOAuth = false
  var kind = 0
}

private struct SegmentedHostedProbe: NSViewRepresentable {
  @Binding var selection: Int
  func makeNSView(context: Context) -> CrossAppKit.NSSegmentedControl {
    let control = CrossAppKit.NSSegmentedControl(
      labels: ["HTTP", "Local Command"], trackingMode: .selectOne, target: nil, action: nil)
    control.setWidth(76, forSegment: 0)
    control.setWidth(128, forSegment: 1)
    return control
  }
  func updateNSView(_ nsView: CrossAppKit.NSSegmentedControl, context: Context) {
    nsView.selectedSegment = selection
  }
  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: CrossAppKit.NSSegmentedControl, context: Context
  ) -> CGSize? {
    CGSize(width: 204, height: nsView.intrinsicContentSize.height)
  }
}

private struct MCPEditorProbe: SwiftUIRuntime.View {
  @Bindable var state: MCPProbeState
  var body: some SwiftUIRuntime.View {
    let cardShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    let fieldShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    let fieldBg = SwiftUIRuntime.Color(red: 0.19, green: 0.19, blue: 0.21)
    let cardBg = SwiftUIRuntime.Color(red: 0.13, green: 0.13, blue: 0.15)
    SwiftUIRuntime.VStack(spacing: 0) {
      SwiftUIRuntime.Text("Add MCP Server")
        .font(.headline)
        .foregroundStyle(SwiftUIRuntime.Color.white)
        .padding(20)
      SwiftUIRuntime.Form {
        SwiftUIRuntime.Section {
          SwiftUIRuntime.TextField("Name", text: $state.name, prompt: SwiftUIRuntime.Text("GitHub"))
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(fieldShape.fill(fieldBg))
          SegmentedHostedProbe(selection: $state.kind)
          SwiftUIRuntime.TextField(
            "URL", text: $state.url, prompt: SwiftUIRuntime.Text("https://example.com/mcp")
          )
          .textFieldStyle(.plain)
          .padding(.horizontal, 8)
          .frame(height: 26)
          .background(fieldShape.fill(fieldBg))
          SwiftUIRuntime.Picker("Authentication", selection: $state.usesOAuth) {
            SwiftUIRuntime.Text("Header").tag(false)
            SwiftUIRuntime.Text("OAuth").tag(true)
          }
          SwiftUIRuntime.TextField(
            "Header", text: $state.headerName, prompt: SwiftUIRuntime.Text("Authorization")
          )
          .textFieldStyle(.plain)
          .padding(.horizontal, 8)
          .frame(height: 26)
          .background(fieldShape.fill(fieldBg))
          SwiftUIRuntime.HStack(spacing: 6) {
            SwiftUIRuntime.SecureField(
              "Value", text: $state.headerValue, prompt: SwiftUIRuntime.Text("Bearer …")
            )
            .textFieldStyle(.plain)
            SwiftUIRuntime.Button("Show") {}
              .buttonStyle(.plain)
              .disabled(state.headerValue.isEmpty)
          }
          .padding(.horizontal, 8)
          .frame(height: 26)
          .background(fieldShape.fill(fieldBg))
        }
      }
    }
    .frame(width: 520, height: 460)
    .background(cardShape.fill(cardBg))
    .preferredColorScheme(.dark)
  }
}

@Observable
private final class PanelState {
  var query = "Search apps"
}

private struct WindowProbe: NSViewRepresentable {
  let onWindow: (CrossAppKit.NSWindow?) -> Void
  func makeNSView(context: Context) -> CrossAppKit.NSView {
    CrossAppKit.NSView(frame: .zero)
  }
  func updateNSView(_ nsView: CrossAppKit.NSView, context: Context) {
    onWindow(nsView.window)
  }
}

private struct PanelContent: SwiftUIRuntime.View {
  @Environment(PanelState.self) var state
  let onWindow: (CrossAppKit.NSWindow?) -> Void
  var body: some SwiftUIRuntime.View {
    SwiftUIRuntime.VStack(spacing: 8) {
      SwiftUIRuntime.Text(state.query)
      WindowProbe(onWindow: onWindow)
        .frame(width: 10, height: 10)
    }
    .padding(12)
  }
}

@Observable
private final class UIKitPanelProbeState {
  var headline = "UIKit Ready"
}

private struct UIWindowProbeRepresentable: UIViewRepresentable {
  let onWindow: (UIWindow?) -> Void
  func makeUIView(context: Context) -> UIView {
    UIView(frame: .zero)
  }
  func updateUIView(_ uiView: UIView, context: Context) {
    onWindow(uiView.window)
  }
}

private final class AutoLayoutProbeViewController: UIViewController {
  let badgeLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .secondarySystemBackground
    badgeLabel.text = "Auto Layout Probe"
    badgeLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(badgeLabel)
    NSLayoutConstraint.activate([
      badgeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      badgeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      badgeLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      badgeLabel.heightAnchor.constraint(equalToConstant: 28),
    ])
  }
}

private struct UIControllerProbeRepresentable: UIViewControllerRepresentable {
  let onFrame: (CGRect) -> Void
  func makeUIViewController(context: Context) -> AutoLayoutProbeViewController {
    AutoLayoutProbeViewController()
  }
  func updateUIViewController(_ uiViewController: AutoLayoutProbeViewController, context: Context) {
    uiViewController.view.layoutIfNeeded()
    onFrame(uiViewController.badgeLabel.frame)
  }
}

private struct UIKitPanelProbeContent: SwiftUIRuntime.View {
  @Environment(UIKitPanelProbeState.self) var state
  let onViewWindow: (UIWindow?) -> Void
  let onControllerFrame: (CGRect) -> Void

  var body: some SwiftUIRuntime.View {
    SwiftUIRuntime.VStack(spacing: 8) {
      SwiftUIRuntime.Text(state.headline)
        .foregroundStyle(SwiftUIRuntime.Color(uiColor: .label))
      UIWindowProbeRepresentable(onWindow: onViewWindow)
        .frame(width: 24, height: 16)
      UIControllerProbeRepresentable(onFrame: onControllerFrame)
        .frame(width: 220, height: 56)
    }
    .padding(12)
  }
}

@MainActor
@Observable
private final class AliasProbeState {
  var draft = ""
  var committedAlias = ""
  var focused = false
  var beginCount = 0
  var endCount = 0
  weak var lastEditor: CrossAppKit.NSTextView?

  func commit() {
    committedAlias = draft
  }

  func revert() {
    draft = committedAlias
    focused = false
  }
}

private struct AliasProbeTextField: NSViewRepresentable {
  let state: AliasProbeState

  func makeCoordinator() -> Coordinator { Coordinator(state: state) }

  func makeNSView(context: Context) -> CrossAppKit.NSTextView {
    let editor = CrossAppKit.NSTextView()
    editor.delegate = context.coordinator
    editor.drawsBackground = false
    editor.backgroundColor = .clear
    editor.font = .systemFont(ofSize: CrossAppKit.NSFont.smallSystemFontSize)
    editor.textContainerInset = NSSize(width: 0, height: 5.5)
    editor.textContainer?.lineFragmentPadding = 0
    editor.textContainer?.maximumNumberOfLines = 1
    editor.textContainer?.lineBreakMode = .byTruncatingTail
    editor.setAccessibilityRole(.textField)
    state.lastEditor = editor
    return editor
  }

  func updateNSView(_ editor: CrossAppKit.NSTextView, context: Context) {
    state.lastEditor = editor
    if editor.string != state.draft {
      editor.string = state.draft
    }
    if !state.focused, editor.window?.firstResponder === editor {
      _ = editor.window?.makeFirstResponder(nil)
    }
  }

  @MainActor
  final class Coordinator: NSObject, CrossAppKit.NSTextViewDelegate {
    let state: AliasProbeState
    init(state: AliasProbeState) { self.state = state }

    func textDidBeginEditing(_ notification: Notification) {
      state.beginCount += 1
      state.focused = true
    }

    func textDidEndEditing(_ notification: Notification) {
      state.endCount += 1
      state.focused = false
      state.commit()
    }

    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? CrossAppKit.NSTextView else { return }
      state.draft = editor.string
    }

    func textView(_ textView: CrossAppKit.NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      switch commandSelector {
      case .insertNewline:
        _ = textView.window?.makeFirstResponder(nil)
        return true
      case .cancelOperation:
        state.revert()
        _ = textView.window?.makeFirstResponder(nil)
        return true
      default:
        return false
      }
    }
  }
}

private struct AliasProbeView: SwiftUIRuntime.View {
  let state: AliasProbeState
  var body: some SwiftUIRuntime.View {
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    SwiftUIRuntime.HStack(spacing: 4) {
      SwiftUIRuntime.ZStack(alignment: .leading) {
        if state.draft.isEmpty {
          SwiftUIRuntime.Text("Add Alias")
            .font(.system(size: 11))
            .foregroundStyle(SwiftUIRuntime.Color.white.opacity(0.65))
            .allowsHitTesting(false)
        }
        AliasProbeTextField(state: state)
      }
    }
    .padding(.horizontal, 9)
    .frame(width: 120, height: 24)
    .background(shape.fill(SwiftUIRuntime.Color(red: 0.16, green: 0.16, blue: 0.18)))
    .overlay(shape.strokeBorder(SwiftUIRuntime.Color.white.opacity(0.15), lineWidth: 1))
    .clipShape(shape)
    .padding(20)
  }
}
