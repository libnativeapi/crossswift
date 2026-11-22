#if os(Linux)
import CGTK3
import Foundation
import NativeAPI
import SwiftUIRuntime

/// Paints the shared desktop layout in a GTK window and retains its native text editors.
public final class LinuxDrawingBackend: RenderBackend {
  public var tapHandler: ((NodeID) -> Void)?
  public var transactionHandler: ((() -> Void) -> Void)?
  public var animationTickHandler: (() -> Bool)?
  public var inputHandler: ((NodeID?, Int, CGPoint, Int, EventModifiers, String) -> Bool)?
  public var interactionHandler: ((NodeID, Renderer.Interaction) -> Void)?
  public var onResize: ((SwiftUIRuntime.Size) -> Void)?

  private let window: NativeAPI.Window
  public var environmentTransform: ((inout EnvironmentValues) -> Void)?
  public var environment: EnvironmentValues {
    var env = EnvironmentValues.hosting(window)
    environmentTransform?(&env)
    return env
  }
  private let content: NativeAPI.View
  private let hostView: NativeAPI.View
  private let canvas: Widget
  private let host: Widget
  private let surface: Widget
  private let drawing = LinuxDrawing()
  private var root: Element?
  private var appliedDarkMode: Bool? = nil
  private var canvasImage: OpaquePointer?
  private var canvasSize: (width: Int32, height: Int32, scale: Int32)?
  private var canvasCapacity: (width: Int32, height: Int32, scale: Int32)?
  private var canvasDamageRects: [Rect] = []
  private var listener: ListenerId?
  private var queuedRender: (() -> Void)?
  private var pointerSource: UInt32 = 0
  private var pendingPointer: (event: Int, point: CGPoint, modifiers: EventModifiers)?
  private var controls: [NodeID: Editor] = [:]
  private var buttons: [NodeID: Activation] = [:]
  private var controlBranches: Set<NodeID> = []
  private var modal: NodeID?
  private var signals: [gulong] = []
  private var allocationSignal: gulong = 0
  private var windowScrollSignal: gulong = 0
  private var applying = false
  private var painting = false
  private var tick: UInt32 = 0
  private var motions: [NodeID: LinuxDrawing.Motion] = [:]
  private var motionDamage: [NodeID: Rect] = [:]
  private var prior: [NodeID: LinuxDrawing.DrawingValues] = [:]
  private let trace = ProcessInfo.processInfo.environment["CROSS_SWIFTUI_LINUX_TRACE"] == "1"

  fileprivate typealias Widget = UnsafeMutablePointer<GtkWidget>
  private static let connectAfter = GConnectFlags(rawValue: 1)

  public init?(window: NativeAPI.Window) {
    guard let content = window.contentView, let native = content.nativeObject,
          let canvas = gtk_drawing_area_new(), let host = gtk_fixed_new(),
          let surface = gtk_overlay_new() else { return nil }
    g_object_ref_sink(surface)
    g_object_ref_sink(host)
    g_object_ref_sink(canvas)
    guard let hostView = NativeAPI.View.createWithNativeView(UnsafeMutableRawPointer(host)) else {
      g_object_unref(canvas)
      g_object_unref(host)
      g_object_unref(surface)
      return nil
    }
    hostView.setLayout(.absolute)
    self.window = window
    self.content = content
    self.hostView = hostView
    self.canvas = canvas
    self.host = host
    self.surface = surface
    let container = native.assumingMemoryBound(to: GtkFixed.self)
    gtk_container_add(typed(surface, GtkContainer.self), canvas)
    gtk_overlay_add_overlay(typed(surface, GtkOverlay.self), host)
    gtk_widget_set_halign(host, GTK_ALIGN_FILL)
    gtk_widget_set_valign(host, GTK_ALIGN_FILL)
    gtk_overlay_set_overlay_pass_through(typed(surface, GtkOverlay.self), host, 1)
    gtk_fixed_put(container, surface, 0, 0)
    gtk_widget_show(host)
    gtk_widget_set_can_focus(canvas, 1)
    gtk_widget_add_events(canvas, Int32(
      GDK_POINTER_MOTION_MASK.rawValue | GDK_BUTTON_PRESS_MASK.rawValue | GDK_BUTTON_RELEASE_MASK.rawValue
        | GDK_SCROLL_MASK.rawValue | GDK_SMOOTH_SCROLL_MASK.rawValue | GDK_LEAVE_NOTIFY_MASK.rawValue
        | GDK_KEY_PRESS_MASK.rawValue))
    let context = Unmanaged.passUnretained(self).toOpaque()
    let allocate: @convention(c) (Widget?, UnsafeMutablePointer<GtkAllocation>?, UnsafeMutableRawPointer?) -> Void = { _, size, data in
      guard let size, let data else { return }
      let backend = Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue()
      var allocation = size.pointee
      gtk_widget_size_allocate(backend.surface, &allocation)
    }
    allocationSignal = g_signal_connect_data(container, "size-allocate", unsafeBitCast(allocate, to: GCallback.self),
                                             context, nil, Self.connectAfter)
    let draw: @convention(c) (Widget?, OpaquePointer?, UnsafeMutableRawPointer?) -> gboolean = { _, cairo, data in
      guard let cairo, let data else { return 0 }
      let backend = Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue()
      backend.paint(in: cairo)
      return 0
    }
    signals.append(g_signal_connect_data(canvas, "draw", unsafeBitCast(draw, to: GCallback.self), context, nil, .init(rawValue: 0)))
    let callback: @convention(c) (Widget?, UnsafeMutablePointer<GdkEvent>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
      guard let event, let data else { return 0 }
      return Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue().pointer(event)
    }
    for name in ["motion-notify-event", "button-press-event", "button-release-event", "scroll-event", "leave-notify-event"] {
      signals.append(g_signal_connect_data(canvas, name, unsafeBitCast(callback, to: GCallback.self), context, nil, .init(rawValue: 0)))
    }
    // The native overlay may be the scroll target between two controls.
    // Unhandled wheel events bubble to the toplevel in that case.
    if let top = window.nativeObject {
      let widget = top.assumingMemoryBound(to: GtkWidget.self)
      gtk_widget_add_events(widget, Int32(GDK_SCROLL_MASK.rawValue | GDK_SMOOTH_SCROLL_MASK.rawValue))
      windowScrollSignal = g_signal_connect_data(top, "scroll-event", unsafeBitCast(callback, to: GCallback.self),
                                                 context, nil, .init(rawValue: 0))
    }
    let key: @convention(c) (Widget?, UnsafeMutablePointer<GdkEventKey>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
      guard let event, let data else { return 0 }
      return Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue().key(event.pointee, id: nil)
    }
    signals.append(g_signal_connect_data(canvas, "key-press-event", unsafeBitCast(key, to: GCallback.self), context, nil, .init(rawValue: 0)))
    gtk_widget_show(canvas)
    gtk_widget_show(surface)
    listener = content.addListener { [weak self] event in
      guard let self else { return }
      switch event {
      case .resized(_, let size):
        self.onResize?(SwiftUIRuntime.Size(width: size.width, height: size.height))
        if let update = self.queuedRender {
          self.queuedRender = nil
          self.content.cancelUpdate()
          update()
        }
      case .updating:
        let update = self.queuedRender
        self.queuedRender = nil
        update?()
      default:
        break
      }
    }
  }

  deinit {
    if let canvasImage { cairo_surface_destroy(canvasImage) }
    content.cancelUpdate()
    if pointerSource != 0 { g_source_remove(pointerSource) }
    if tick != 0 { gtk_widget_remove_tick_callback(canvas, tick) }
    if let listener { _ = content.removeListener(listener) }
    if let native = content.nativeObject, allocationSignal != 0,
       g_signal_handler_is_connected(native, allocationSignal) != 0 {
      g_signal_handler_disconnect(native, allocationSignal)
    }
    if let top = window.nativeObject, windowScrollSignal != 0,
       g_signal_handler_is_connected(top, windowScrollSignal) != 0 {
      g_signal_handler_disconnect(top, windowScrollSignal)
    }
    controls.removeAll()
    buttons.removeAll()
    hostView.dispose()
    for signal in signals where g_signal_handler_is_connected(canvas, signal) != 0 {
      g_signal_handler_disconnect(canvas, signal)
    }
    gtk_widget_destroy(surface)
    g_object_unref(canvas)
    g_object_unref(host)
    g_object_unref(surface)
  }

  public func measureText(_ text: String, font: Font) -> SwiftUIRuntime.Size {
    drawing.measure(text, font: font)
  }

  public func requestRender(_ render: @escaping () -> Void) -> Bool {
    queuedRender = render
    content.requestUpdate()
    return true
  }

  public func perform(_ commands: [RenderCommand]) {}
  public var needsRenderCommands: Bool { false }

  private func findColorSchemeOverride(_ node: Element) -> ColorScheme? {
    if let scheme = node.props.colorSchemeOverride { return scheme }
    for child in node.children {
      if let scheme = findColorSchemeOverride(child) { return scheme }
    }
    return nil
  }

  private func syncWindowAppearance(_ root: Element) {
    guard let scheme = findColorSchemeOverride(root) else { return }
    let isDark = (scheme == .dark)
    guard appliedDarkMode != isDark else { return }
    appliedDarkMode = isDark
    if let settings = gtk_settings_get_default() {
      var val = GValue()
      g_value_init(&val, g_type_from_name("gboolean"))
      g_value_set_boolean(&val, isDark ? 1 : 0)
      g_object_set_property(UnsafeMutableRawPointer(settings).assumingMemoryBound(to: GObject.self),
                            "gtk-application-prefer-dark-theme", &val)
      g_value_unset(&val)
    }
  }

  public func didRender(_ root: Element) {
    syncWindowAppearance(root)
    preparePublication(root)
    publish(root)
  }

  public func didScroll(_ root: Element, viewport: Rect) {
    publish(root, damage: viewport)
  }

  public func didMeasureRender(_ timings: [String: Double]) {
    if trace {
      let stages = ["evaluate", "normalize", "environment", "layout", "layout.identify", "layout.place",
                    "layout.geometry", "layout.prune", "finalize", "diff", "scroll.translate", "backend"]
      log("GTK render " + stages.compactMap { name in
        timings[name].map { "\(name)=\($0)" }
      }.joined(separator: " "))
    }
  }

  private func log(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
  }

  private func paint(in context: OpaquePointer) {
    let size = (width: gtk_widget_get_allocated_width(canvas),
                height: gtk_widget_get_allocated_height(canvas),
                scale: gtk_widget_get_scale_factor(canvas))
    guard size.width > 0, size.height > 0 else { return }
    let targetW = Double(size.width)
    let targetH = Double(size.height)
    if let currentRoot = self.root,
       abs(currentRoot.frame.width - targetW) > 0.5 || abs(currentRoot.frame.height - targetH) > 0.5
    {
      painting = true
      onResize?(SwiftUIRuntime.Size(width: targetW, height: targetH))
      if let update = queuedRender {
        queuedRender = nil
        content.cancelUpdate()
        update()
      }
      painting = false
    }
    guard let root else { return }
    let start = trace ? g_get_monotonic_time() : 0
    if canvasImage == nil || canvasSize?.width != size.width || canvasSize?.height != size.height
      || canvasSize?.scale != size.scale
    {
      let reqW = max(Int32(1), pixels(Double(size.width) * Double(size.scale)))
      let reqH = max(Int32(1), pixels(Double(size.height) * Double(size.scale)))
      let canReuse =
        canvasImage != nil
        && canvasCapacity?.scale == size.scale
        && (canvasCapacity?.width ?? 0) >= reqW
        && (canvasCapacity?.height ?? 0) >= reqH
        && reqW >= (canvasCapacity?.width ?? 0) / 2
        && reqH >= (canvasCapacity?.height ?? 0) / 2
      if !canReuse {
        if let canvasImage { cairo_surface_destroy(canvasImage) }
        let capW = ((reqW + 255) / 256) * 256
        let capH = ((reqH + 255) / 256) * 256
        canvasImage = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, capW, capH)
        if let canvasImage {
          cairo_surface_set_device_scale(canvasImage, Double(size.scale), Double(size.scale))
        }
        canvasCapacity = (width: capW, height: capH, scale: size.scale)
      }
      canvasSize = size
      canvasDamageRects = [Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))]
    }
    let damageRects = canvasDamageRects
    canvasDamageRects.removeAll(keepingCapacity: true)
    let now = Date.timeIntervalSinceReferenceDate
    if let image = canvasImage, cairo_surface_status(image) == CAIRO_STATUS_SUCCESS {
      if !damageRects.isEmpty, let buffer = cairo_create(image) {
        defer { cairo_destroy(buffer) }
        for damage in damageRects where !damage.isEmpty {
          cairo_save(buffer)
          cairo_rectangle(buffer, damage.minX, damage.minY, damage.width, damage.height)
          cairo_clip(buffer)
          cairo_set_operator(buffer, CAIRO_OPERATOR_CLEAR)
          cairo_paint(buffer)
          cairo_set_operator(buffer, CAIRO_OPERATOR_OVER)
          drawing.paint(root, in: buffer, clip: root.frame, damage: damage, motions: motions, now: now)
          cairo_restore(buffer)
        }
      }
      cairo_save(context)
      cairo_set_source_surface(context, image, 0, 0)
      cairo_paint(context)
      cairo_restore(context)
    } else {
      drawing.paint(root, in: context, clip: root.frame, damage: root.frame, motions: motions, now: now)
    }
    if trace {
      let end = g_get_monotonic_time()
      let summary: String
      if damageRects.isEmpty {
        summary = "0.0x0.0"
      } else if damageRects.count == 1 {
        summary = "\(damageRects[0].width)x\(damageRects[0].height)"
      } else {
        let area = damageRects.reduce(0.0) { $0 + $1.width * $1.height }
        summary = "\(damageRects.count)rects(\(Int(area))px)"
      }
      log("GTK paint \(Double(end - start) / 1000) end=\(end) repaint=\(summary)")
    }
  }

  private static func unionRect(_ a: Rect, _ b: Rect) -> Rect {
    if a.isEmpty { return b }
    if b.isEmpty { return a }
    let left = min(a.minX, b.minX)
    let top = min(a.minY, b.minY)
    return Rect(
      x: left, y: top,
      width: max(a.maxX, b.maxX) - left,
      height: max(a.maxY, b.maxY) - top)
  }

  private static func addDamageRect(_ raw: Rect, into rects: inout [Rect]) {
    guard !raw.isEmpty else { return }
    let x = floor(raw.minX), y = floor(raw.minY)
    var rect = Rect(x: x, y: y, width: ceil(raw.maxX) - x, height: ceil(raw.maxY) - y)
    guard !rect.isEmpty else { return }
    // Merge with any overlapping or adjacent (<= 8px gap) rect.
    var merged = true
    while merged {
      merged = false
      var i = 0
      while i < rects.count {
        let existing = rects[i]
        let overlapsOrNear =
          rect.minX <= existing.maxX + 8 && rect.maxX + 8 >= existing.minX
          && rect.minY <= existing.maxY + 8 && rect.maxY + 8 >= existing.minY
        if overlapsOrNear {
          rect = unionRect(existing, rect)
          rects.remove(at: i)
          merged = true
        } else {
          i += 1
        }
      }
    }
    rects.append(rect)
    if rects.count > 8 {
      let combined = rects.reduce(Rect.zero, unionRect)
      rects = [combined]
    }
  }

  private func invalidateCanvas(_ rect: Rect? = nil) {
    guard let rect else {
      let full = Rect(
        x: 0, y: 0,
        width: Double(gtk_widget_get_allocated_width(canvas)),
        height: Double(gtk_widget_get_allocated_height(canvas)))
      canvasDamageRects = [full]
      if !painting { gtk_widget_queue_draw(canvas) }
      return
    }
    invalidateCanvasRects([rect])
  }

  private func invalidateCanvasRects(_ rects: [Rect]) {
    guard !rects.isEmpty else { return }
    for rect in rects where !rect.isEmpty {
      Self.addDamageRect(rect, into: &canvasDamageRects)
      if !painting {
        let x = floor(rect.minX), y = floor(rect.minY)
        let w = ceil(rect.maxX) - x, h = ceil(rect.maxY) - y
        gtk_widget_queue_draw_area(canvas, pixels(x), pixels(y), pixels(w), pixels(h))
      }
    }
  }

  private func publish(_ root: Element, damage: Rect? = nil) {
    let previousRoot = self.root
    self.root = root
    let hadVisibleMotions = !motionDamage.isEmpty
    updateVisibleMotions(in: root)
    applying = true
    defer { applying = false }
    var live = Set<NodeID>()
    var liveButtons = Set<NodeID>()
    var focus: NodeID?
    let defaultBg: SwiftUIRuntime.Color =
      appliedDarkMode == true ? SwiftUIRuntime.Color(red: 0.11, green: 0.11, blue: 0.13) : .white
    updateControls(root, clip: root.frame, background: defaultBg, allowed: true, focus: &focus, modal: modal,
                   inModal: false, accessibilityLabel: "", refreshContent: damage == nil,
                   live: &live, liveButtons: &liveButtons)
    if !controls.isEmpty {
      for id in controls.keys.filter({ !live.contains($0) }) { controls.removeValue(forKey: id) }
    }
    if !buttons.isEmpty {
      for id in buttons.keys.filter({ !liveButtons.contains($0) }) { buttons.removeValue(forKey: id) }
    }
    if let focus {
      if let edit = controls[focus] {
        if !edit.field.isFocused { edit.field.focus() }
      } else if let button = buttons[focus], gtk_widget_has_focus(button.widget) == 0 {
        gtk_widget_grab_focus(button.widget)
      }
    }
    // Moving controls can invalidate the whole GTK window. Track the pixels
    // that actually changed so an expose only composites the cached canvas.
    if !hadVisibleMotions && motionDamage.isEmpty {
      if let damage {
        invalidateCanvas(damage)
      } else if let previousRoot, previousRoot.frame == root.frame, canvasImage != nil {
        let incremental = computeIncrementalDamage(old: previousRoot, new: root, clip: root.frame)
        if !incremental.isEmpty {
          let totalArea = incremental.reduce(0.0) { $0 + $1.width * $1.height }
          let fullArea = root.frame.width * root.frame.height
          if fullArea > 0 && totalArea >= fullArea * 0.7 {
            invalidateCanvas(nil)
          } else {
            invalidateCanvasRects(incremental)
          }
        }
      } else {
        invalidateCanvas(nil)
      }
    } else {
      invalidateCanvas(nil)
    }
  }

  /// Computes disjoint damage rects between two mounted trees, skipping
  /// `reusesLayout` subtrees in O(1) and ignoring non-visual property noise.
  private func computeIncrementalDamage(old: Element, new: Element, clip: Rect) -> [Rect] {
    var rects: [Rect] = []
    func expandedBounds(_ node: Element) -> Rect {
      let shadowPad = node.props.shadows.reduce(0.0) { best, s in
        max(best, ShadowMask.padding(radius: s.radius) + max(abs(s.x), abs(s.y)))
      }
      let pad = max(2.0, node.props.borderWidth + shadowPad)
      return Rect(
        x: node.frame.minX - pad, y: node.frame.minY - pad,
        width: node.frame.width + pad * 2, height: node.frame.height + pad * 2)
    }
    func isTransformed(_ node: Element) -> Bool {
      node.props.rotation != 0 || node.props.scaleX != 1 || node.props.scaleY != 1
    }
    func subtreeBounds(_ node: Element, clip: Rect) -> Rect {
      if isTransformed(node) { return clip }
      let nextClip = node.props.clipped ? clip.intersection(node.frame) : clip
      var bounds = expandedBounds(node).intersection(clip)
      if node.hasOverflow {
        for child in node.children {
          bounds = Self.unionRect(bounds, subtreeBounds(child, clip: nextClip))
        }
      }
      return bounds
    }
    func pathBuildersDiffer(_ a: Element, _ b: Element) -> Bool {
      if (a.pathBuilder == nil) != (b.pathBuilder == nil) { return true }
      if let pa = a.pathBuilder, let pb = b.pathBuilder {
        let r = a.frame.cgRect
        if pa(r) != pb(r) { return true }
      }
      if (a.clipPathBuilder == nil) != (b.clipPathBuilder == nil) { return true }
      if let ca = a.clipPathBuilder, let cb = b.clipPathBuilder {
        let r = CGRect(origin: .zero, size: a.frame.cgRect.size)
        if ca(r) != cb(r) { return true }
      }
      return false
    }
    func diff(_ a: Element, _ b: Element, clip: Rect) {
      if b.reusesLayout && a.id == b.id && a.frame == b.frame { return }
      if isTransformed(a) || isTransformed(b) {
        Self.addDamageRect(clip, into: &rects)
        return
      }
      let aClip = a.props.clipped ? clip.intersection(a.frame) : clip
      let bClip = b.props.clipped ? clip.intersection(b.frame) : clip
      if a.id != b.id || a.kind != b.kind || a.frame != b.frame
        || a.props.clipped != b.props.clipped || a.props.visible != b.props.visible
        || a.props.opacity != b.props.opacity
      {
        Self.addDamageRect(subtreeBounds(a, clip: clip), into: &rects)
        Self.addDamageRect(subtreeBounds(b, clip: clip), into: &rects)
        return
      }
      if !a.props.visualEquals(b.props) || pathBuildersDiffer(a, b) {
        Self.addDamageRect(expandedBounds(a).intersection(clip), into: &rects)
        Self.addDamageRect(expandedBounds(b).intersection(clip), into: &rects)
      }
      if a.children.count == b.children.count {
        for i in 0..<a.children.count {
          diff(a.children[i], b.children[i], clip: bClip)
        }
      } else {
        var oldByID: [NodeID: Element] = [:]
        oldByID.reserveCapacity(a.children.count)
        for child in a.children { oldByID[child.id] = child }
        var seen = Set<NodeID>()
        seen.reserveCapacity(b.children.count)
        for child in b.children {
          seen.insert(child.id)
          if let prior = oldByID[child.id] {
            diff(prior, child, clip: bClip)
          } else {
            Self.addDamageRect(subtreeBounds(child, clip: bClip), into: &rects)
          }
        }
        for child in a.children where !seen.contains(child.id) {
          Self.addDamageRect(subtreeBounds(child, clip: aClip), into: &rects)
        }
      }
    }
    diff(old, new, clip: clip)
    return rects.map { $0.intersection(clip) }.filter { !$0.isEmpty }
  }

  private func preparePublication(_ root: Element) {
    let now = Date.timeIntervalSinceReferenceDate
    var next: [NodeID: LinuxDrawing.DrawingValues] = [:]
    next.reserveCapacity(prior.count)
    controlBranches.removeAll(keepingCapacity: true)
    modal = nil
    @discardableResult func visit(_ node: Element, animation: Animation?) -> Bool {
      let animation = node.props.animationDisabled ? nil : (node.props.animation ?? animation)
      let values = LinuxDrawing.DrawingValues(node.props)
      if let old = prior[node.id], old != values {
        if let animation, animation.duration > 0 {
          let origin =
            motions[node.id].flatMap { $0.isActive(at: now) ? $0.interpolated(to: old, now: now) : nil }
            ?? old
          motions[node.id] = LinuxDrawing.Motion(from: origin, animation: animation, start: now + animation.delay)
        } else {
          motions.removeValue(forKey: node.id)
        }
      }
      next[node.id] = values
      if modal == nil, node.props.accessibilityTraits & AccessibilityTraits.isModal.rawValue != 0 {
        modal = node.id
      }
      var hasControls = node.kind == .textField || node.kind == .button || node.kind == .styledButton
        || node.props.focusable
      let count = node.children.count
      if count > 0 {
        for i in stride(from: count - 1, through: 0, by: -1) {
          if visit(node.children[i], animation: animation) { hasControls = true }
        }
      }
      if hasControls { controlBranches.insert(node.id) }
      return hasControls
    }
    visit(root, animation: nil)
    prior = next
    if !motions.isEmpty {
      motions = motions.filter { next[$0.key] != nil && $0.value.isActive(at: now) }
    }
  }

  private func updateVisibleMotions(in root: Element) {
    motionDamage.removeAll(keepingCapacity: true)
    let now = Date.timeIntervalSinceReferenceDate
    motions = motions.filter { $0.value.isActive(at: now) }
    if !motions.isEmpty {
      func collect(_ node: Element, clip: Rect) {
        guard node.props.visible, !clip.isEmpty else { return }
        if let motion = motions[node.id] {
          let frame = node.frame
          let dx = motion.from.offsetX - node.props.offsetX
          let dy = motion.from.offsetY - node.props.offsetY
          let scale = max(1, abs(motion.from.scaleX), abs(motion.from.scaleY),
                          abs(node.props.scaleX), abs(node.props.scaleY))
          let rotates = motion.from.rotation != node.props.rotation || node.props.rotation != 0
          let spread = rotates ? (hypot(frame.width, frame.height) * scale) / 2 : 0
          let shadow = (node.props.shadows.map {
            ShadowMask.padding(radius: $0.radius) + max(abs($0.x), abs($0.y))
          }.max() ?? 0) * scale * (rotates ? sqrt(2) : 1)
          let padX = max(spread, frame.width * (scale - 1) / 2) + shadow + 2
          let padY = max(spread, frame.height * (scale - 1) / 2) + shadow + 2
          let bounds = Rect(
            x: frame.minX + min(0, dx) - padX, y: frame.minY + min(0, dy) - padY,
            width: frame.width + abs(dx) + padX * 2, height: frame.height + abs(dy) + padY * 2
          ).intersection(clip)
          if !bounds.isEmpty { motionDamage[node.id] = bounds }
        }
        let childClip = node.props.clipped ? clip.intersection(node.frame) : clip
        for child in node.children { collect(child, clip: childClip) }
      }
      collect(root, clip: root.frame)
    }
    if trace { log("GTK visible animations \(motionDamage.count)/\(motions.count)") }
    if (!motionDamage.isEmpty || root.hasLayoutAnimation) && tick == 0 {
      tick = gtk_widget_add_tick_callback(canvas, { _, _, data in
        guard let data else { return 0 }
        let backend = Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue()
        if backend.root?.hasLayoutAnimation == true {
          _ = backend.animationTickHandler?()
        } else {
          let now = Date.timeIntervalSinceReferenceDate
          for rect in backend.motionDamage.values {
            backend.invalidateCanvas(rect)
          }
          backend.motions = backend.motions.filter { $0.value.isActive(at: now) }
          backend.motionDamage = backend.motionDamage.filter { backend.motions[$0.key] != nil }
        }
        if backend.motionDamage.isEmpty && backend.root?.hasLayoutAnimation != true {
          backend.tick = 0
          return 0
        }
        return 1
      }, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
  }

  public func focusInitialControl() { gtk_widget_grab_focus(canvas) }

  fileprivate func sendText(_ text: String, from id: NodeID) {
    if !applying { _ = inputHandler?(id, 7, .zero, 0, [], text) }
  }

  fileprivate func activate(_ id: NodeID) {
    if !applying { tapHandler?(id) }
  }

  fileprivate func focus(_ id: NodeID, gained: Bool) {
    if !applying { interactionHandler?(id, .focus(gained)) }
  }

  private func updateControls(_ node: Element, clip: Rect, background: SwiftUIRuntime.Color,
                              allowed: Bool, focus: inout NodeID?, modal: NodeID?, inModal: Bool,
                              accessibilityLabel: String, refreshContent: Bool,
                              live: inout Set<NodeID>, liveButtons: inout Set<NodeID>) {
    guard controlBranches.contains(node.id) else { return }
    let props = node.props
    let inModal = inModal || node.id == modal
    let allowed = allowed && props.visible && props.hitTesting
    let clip = props.clipped ? clip.intersection(node.frame) : clip
    let visible = node.frame.intersection(clip)
    let background = props.background.flatMap { $0.opacity > 0.99 ? $0 : nil } ?? background
    let accessibilityLabel = props.accessibilityLabel.isEmpty ? accessibilityLabel : props.accessibilityLabel
    let modalAllowed = modal == nil || inModal
    let blockedByPresentation = !modalAllowed || (root?.hasActivePresentation == true && !allowed)
    let shown = props.visible && !blockedByPresentation && !visible.isEmpty
    let active = allowed && modalAllowed && !visible.isEmpty
    if node.kind == .textField, shown || controls[node.id] != nil {
      live.insert(node.id)
      if let existing = controls[node.id], existing.multiline != props.multiline {
        controls.removeValue(forKey: node.id)
      }
      let isNew = controls[node.id] == nil
      if isNew {
        controls[node.id] = Editor(node.id, props: props, hostView: hostView, backend: self)
      }
      if let editor = controls[node.id] {
        var effectiveProps = props
        effectiveProps.enabled = props.enabled && active
        if refreshContent || isNew { editor.updateContent(effectiveProps, background: background, label: accessibilityLabel) }
        editor.updatePlacement(effectiveProps, visible: shown ? visible : .zero)
        if props.focusRequested && active { focus = node.id }
      }
    }
    if node.kind != .textField, (node.kind == .button || node.kind == .styledButton || props.focusable),
       active || buttons[node.id] != nil {
      liveButtons.insert(node.id)
      let isNew = buttons[node.id] == nil
      if isNew {
        buttons[node.id] = Activation(node.id, host: typed(host, GtkFixed.self), backend: self)
      }
      if let control = buttons[node.id] {
        if isNew || (refreshContent && !node.reusesLayout) { control.updateContent(node) }
        control.updatePlacement(visible: active ? visible : .zero, enabled: props.enabled && active,
                                accessibilityHidden: props.accessibilityHidden)
        if props.focusRequested && active { focus = node.id }
      }
    }
    LinuxDrawing.forEachOrderedChild(node) { child in
      updateControls(child, clip: clip, background: background, allowed: allowed,
                     focus: &focus, modal: modal, inModal: inModal,
                     accessibilityLabel: accessibilityLabel, refreshContent: refreshContent,
                     live: &live, liveButtons: &liveButtons)
      if props.focusRequested && active && focus == nil {
        focus = firstFocusable(child)
      }
    }
  }

  private func firstFocusable(_ node: Element) -> NodeID? {
    if node.props.enabled && (controls[node.id] != nil || buttons[node.id] != nil) { return node.id }
    return node.children.lazy.compactMap { self.firstFocusable($0) }.first
  }

  private func flushPointer() {
    if pointerSource != 0 {
      g_source_remove(pointerSource)
      pointerSource = 0
    }
    guard let pendingPointer else { return }
    self.pendingPointer = nil
    _ = inputHandler?(nil, pendingPointer.event, pendingPointer.point, 0, pendingPointer.modifiers, "")
  }

  private func queuePointer(_ event: Int, point: CGPoint, modifiers: EventModifiers) {
    pendingPointer = (event, point, modifiers)
    guard pointerSource == 0 else { return }
    pointerSource = g_idle_add_full(G_PRIORITY_DEFAULT, { data in
      guard let data else { return 0 }
      let backend = Unmanaged<LinuxDrawingBackend>.fromOpaque(data).takeUnretainedValue()
      backend.pointerSource = 0
      backend.flushPointer()
      return 0
    }, Unmanaged.passUnretained(self).toOpaque(), nil)
  }

  fileprivate func pointer(_ event: UnsafeMutablePointer<GdkEvent>, origin: SwiftUIRuntime.Point = .zero,
                           button control: Widget? = nil, id: NodeID? = nil) -> gboolean {
    var x = 0.0, y = 0.0
    _ = gdk_event_get_coords(event, &x, &y)
    var state = GdkModifierType(rawValue: 0)
    _ = gdk_event_get_state(event, &state)
    var value = 0
    let type: Int
    switch event.pointee.type {
    case GDK_MOTION_NOTIFY: type = 1
    case GDK_BUTTON_PRESS:
      var button: UInt32 = 0
      _ = gdk_event_get_button(event, &button)
      if button == 3 { type = 9 }
      else if button == 1 { type = 2; gtk_widget_grab_focus(control ?? canvas) }
      else { return 0 }
    case GDK_BUTTON_RELEASE:
      var button: UInt32 = 0
      _ = gdk_event_get_button(event, &button)
      guard button == 1 else { return 0 }
      type = 3
    case GDK_2BUTTON_PRESS: type = 4
    case GDK_SCROLL:
      type = 5
      var dx = 0.0, dy = 0.0
      if gdk_event_get_scroll_deltas(event, &dx, &dy) != 0 {
        value = Int((abs(dy) >= abs(dx) ? -dy : -dx) * 90)
        if abs(dx) > abs(dy) { state = GdkModifierType(rawValue: state.rawValue | GDK_SHIFT_MASK.rawValue) }
      } else {
        var direction = GDK_SCROLL_DOWN
        _ = gdk_event_get_scroll_direction(event, &direction)
        value = direction == GDK_SCROLL_UP || direction == GDK_SCROLL_LEFT ? 120 : -120
        if direction == GDK_SCROLL_LEFT || direction == GDK_SCROLL_RIGHT {
          state = GdkModifierType(rawValue: state.rawValue | GDK_SHIFT_MASK.rawValue)
        }
      }
    case GDK_LEAVE_NOTIFY: type = 10
    default: return 0
    }
    if let eventWindow = gdk_event_get_window(event), let canvasWindow = gtk_widget_get_window(canvas) {
      if eventWindow != canvasWindow {
        var eventX: Int32 = 0, eventY: Int32 = 0
        var canvasX: Int32 = 0, canvasY: Int32 = 0
        _ = gdk_window_get_origin(eventWindow, &eventX, &eventY)
        _ = gdk_window_get_origin(canvasWindow, &canvasX, &canvasY)
        x += Double(eventX - canvasX)
        y += Double(eventY - canvasY)
      }
    } else {
      x += origin.x
      y += origin.y
    }
    let point = CGPoint(x: x, y: y)
    let flags = modifiers(state.rawValue)
    if type == 1 || type == 10 {
      queuePointer(type, point: point, modifiers: flags)
      return 1
    }
    flushPointer()
    let buttonID = type == 2 || type == 3 || type == 4 ? id : nil
    let handled = inputHandler?(buttonID, type, point, value, flags, "") == true
    if trace {
      log("GTK input event=\(type) x=\(point.x) y=\(point.y) handled=\(handled) time=\(g_get_monotonic_time())")
    }
    if control != nil && (type == 2 || type == 3 || type == 4) { return 1 }
    return handled ? 1 : 0
  }

  fileprivate func key(_ event: GdkEventKey, id: NodeID?) -> gboolean {
    let special: [UInt32: Int] = [
      UInt32(GDK_KEY_BackSpace): 8, UInt32(GDK_KEY_Tab): 9, UInt32(GDK_KEY_ISO_Left_Tab): 9,
      UInt32(GDK_KEY_Return): 13, UInt32(GDK_KEY_KP_Enter): 13, UInt32(GDK_KEY_Escape): 27,
      UInt32(GDK_KEY_space): 32, UInt32(GDK_KEY_Page_Up): 33, UInt32(GDK_KEY_Page_Down): 34,
      UInt32(GDK_KEY_End): 35, UInt32(GDK_KEY_Home): 36, UInt32(GDK_KEY_Left): 37,
      UInt32(GDK_KEY_Up): 38, UInt32(GDK_KEY_Right): 39, UInt32(GDK_KEY_Down): 40,
      UInt32(GDK_KEY_Delete): 46,
    ]
    let value = special[event.keyval] ?? Int(gdk_keyval_to_unicode(event.keyval))
    guard value != 0 else { return 0 }
    return inputHandler?(id, 6, .zero, value, modifiers(event.state), "") == true ? 1 : 0
  }

  private func modifiers(_ state: UInt32) -> EventModifiers {
    var result: EventModifiers = []
    if state & GDK_SHIFT_MASK.rawValue != 0 { result.insert(.shift) }
    if state & GDK_CONTROL_MASK.rawValue != 0 { result.insert(.control) }
    if state & GDK_MOD1_MASK.rawValue != 0 { result.insert(.option) }
    if state & GDK_SUPER_MASK.rawValue != 0 { result.insert(.command) }
    return result
  }
}

private typealias Widget = UnsafeMutablePointer<GtkWidget>

private func pixels(_ value: Double) -> Int32 {
  guard value.isFinite else { return 0 }
  return Int32(max(Double(Int32.min), min(Double(Int32.max), value.rounded())))
}

private func typed<T>(_ widget: Widget, _: T.Type) -> UnsafeMutablePointer<T> {
  UnsafeMutableRawPointer(widget).assumingMemoryBound(to: T.self)
}

private final class Activation {
  private static let style: OpaquePointer = {
    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_data(provider,
      "button { min-width: 0; min-height: 0; padding: 0; border-width: 0; }", -1, nil)
    return OpaquePointer(provider)
  }()
  let widget: Widget
  private let host: UnsafeMutablePointer<GtkFixed>
  private let id: NodeID
  private weak var backend: LinuxDrawingBackend?
  private var signals: [gulong] = []
  private var name: String?
  private var descriptionText: String?
  private var appliedTraits: Int = -1
  private var help: String?
  private var placement = Rect.zero
  private var isShown = false
  private var isSensitive = true

  init(_ id: NodeID, host: UnsafeMutablePointer<GtkFixed>, backend: LinuxDrawingBackend) {
    self.id = id
    self.host = host
    self.backend = backend
    widget = gtk_button_new()!
    g_object_ref_sink(widget)
    gtk_style_context_add_provider(gtk_widget_get_style_context(widget), Self.style, 700)
    gtk_widget_set_opacity(widget, 0)
    // This widget supplies input and accessibility. The canvas draws its pixels.
    gtk_widget_set_redraw_on_allocate(widget, 0)
    gtk_fixed_put(host, widget, 0, 0)
    let data = Unmanaged.passUnretained(self).toOpaque()
    let activate: @convention(c) (Widget?, UnsafeMutableRawPointer?) -> Void = { _, data in
      guard let data else { return }
      let control = Unmanaged<Activation>.fromOpaque(data).takeUnretainedValue()
      control.backend?.activate(control.id)
    }
    signals.append(g_signal_connect_data(widget, "clicked", unsafeBitCast(activate, to: GCallback.self), data, nil, .init(rawValue: 0)))
    let key: @convention(c) (Widget?, UnsafeMutablePointer<GdkEventKey>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
      guard let event, let data else { return 0 }
      let control = Unmanaged<Activation>.fromOpaque(data).takeUnretainedValue()
      return control.backend?.key(event.pointee, id: control.id) ?? 0
    }
    signals.append(g_signal_connect_data(widget, "key-press-event", unsafeBitCast(key, to: GCallback.self), data, nil, .init(rawValue: 0)))
    let focus: @convention(c) (Widget?, UnsafeMutablePointer<GdkEventFocus>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
      guard let event, let data else { return 0 }
      let control = Unmanaged<Activation>.fromOpaque(data).takeUnretainedValue()
      control.backend?.focus(control.id, gained: event.pointee.in != 0)
      return 0
    }
    for signal in ["focus-in-event", "focus-out-event"] {
      signals.append(g_signal_connect_data(widget, signal, unsafeBitCast(focus, to: GCallback.self), data, nil, .init(rawValue: 0)))
    }
    for signal in ["motion-notify-event", "button-press-event", "button-release-event", "scroll-event", "leave-notify-event"] {
      let pointer: @convention(c) (Widget?, UnsafeMutablePointer<GdkEvent>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
        guard let event, let data else { return 0 }
        let control = Unmanaged<Activation>.fromOpaque(data).takeUnretainedValue()
        let id = control.contains(event) ? control.id : nil
        return control.backend?.pointer(event, origin: control.placement.origin,
                                       button: control.widget, id: id) ?? 0
      }
      signals.append(g_signal_connect_data(widget, signal, unsafeBitCast(pointer, to: GCallback.self), data, nil, .init(rawValue: 0)))
    }
    gtk_widget_add_events(widget, Int32(GDK_POINTER_MOTION_MASK.rawValue | GDK_SCROLL_MASK.rawValue
      | GDK_SMOOTH_SCROLL_MASK.rawValue | GDK_LEAVE_NOTIFY_MASK.rawValue))
  }

  deinit {
    for signal in signals where g_signal_handler_is_connected(widget, signal) != 0 {
      g_signal_handler_disconnect(widget, signal)
    }
    gtk_widget_destroy(widget)
    g_object_unref(widget)
  }

  func contains(_ event: UnsafeMutablePointer<GdkEvent>) -> Bool {
    var x = 0.0, y = 0.0
    _ = gdk_event_get_coords(event, &x, &y)
    return x >= 0 && y >= 0 && x < placement.width && y < placement.height
  }

  func updateContent(_ node: Element) {
    func label(_ element: Element) -> String {
      if !element.props.accessibilityLabel.isEmpty { return element.props.accessibilityLabel }
      if !element.props.text.isEmpty { return element.props.text }
      return element.children.map(label).filter { !$0.isEmpty }.joined(separator: " ")
    }
    let label = label(node)
    if name != label {
      name = label
      atk_object_set_name(gtk_widget_get_accessible(widget), label)
    }
    let desc = !node.props.accessibilityValue.isEmpty ? node.props.accessibilityValue : node.props.help
    if descriptionText != desc {
      descriptionText = desc
      atk_object_set_description(gtk_widget_get_accessible(widget), desc)
    }
    if appliedTraits != node.props.accessibilityTraits {
      appliedTraits = node.props.accessibilityTraits
      let traits = AccessibilityTraits(rawValue: appliedTraits)
      let role: AtkRole
      if traits.contains(.isToggle) {
        role = ATK_ROLE_TOGGLE_BUTTON
      } else if traits.contains(.isLink) {
        role = ATK_ROLE_LINK
      } else if traits.contains(.isHeader) {
        role = ATK_ROLE_HEADING
      } else if traits.contains(.isImage) {
        role = ATK_ROLE_IMAGE
      } else {
        role = ATK_ROLE_PUSH_BUTTON
      }
      atk_object_set_role(gtk_widget_get_accessible(widget), role)
    }
    if help != node.props.help {
      help = node.props.help
      gtk_widget_set_tooltip_text(widget, node.props.help.isEmpty ? nil : node.props.help)
    }
  }

  func updatePlacement(visible: Rect, enabled: Bool, accessibilityHidden: Bool) {
    let shown = !visible.isEmpty && !accessibilityHidden
    if !shown, isShown {
      gtk_widget_hide(widget)
      isShown = false
    }
    if shown, placement != visible {
      let x = pixels(visible.minX), y = pixels(visible.minY)
      let width = pixels(visible.width), height = pixels(visible.height)
      if x != pixels(placement.minX) || y != pixels(placement.minY) {
        gtk_fixed_move(host, widget, x, y)
      }
      if width != pixels(placement.width) || height != pixels(placement.height) {
        gtk_widget_set_size_request(widget, width, height)
      }
      placement = visible
    }
    if isSensitive != enabled {
      gtk_widget_set_sensitive(widget, enabled ? 1 : 0)
      isSensitive = enabled
    }
    if shown, !isShown {
      gtk_widget_show(widget)
      isShown = true
    }
  }
}

private final class Editor {
  let field: NativeAPI.TextField
  let input: Widget
  let multiline: Bool
  private let widget: Widget
  private let hostView: NativeAPI.View
  private let id: NodeID
  private weak var backend: LinuxDrawingBackend?
  private var listener: ListenerId?
  private var keySignal: gulong = 0
  private var placement = Rect.zero

  init?(_ id: NodeID, props: NodeProps, hostView: NativeAPI.View, backend: LinuxDrawingBackend) {
    guard let field = NativeAPI.TextField.create(props.text) else { return nil }
    self.id = id
    self.field = field
    self.hostView = hostView
    self.backend = backend
    self.multiline = props.multiline
    if props.multiline { field.setMultiline(true) }
    if props.secure { field.setSecure(true) }
    field.setBordered(false)
    guard let raw = field.nativeObject else {
      field.dispose()
      return nil
    }
    let widget = raw.assumingMemoryBound(to: GtkWidget.self)
    let input: Widget
    if props.multiline {
      guard let scrolled = gtk_bin_get_child(typed(widget, GtkBin.self)),
            let textView = gtk_bin_get_child(typed(scrolled, GtkBin.self)) else {
        field.dispose()
        return nil
      }
      gtk_scrolled_window_set_policy(typed(scrolled, GtkScrolledWindow.self), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
      input = textView
    } else {
      gtk_entry_set_width_chars(typed(widget, GtkEntry.self), 1)
      input = widget
    }
    self.widget = widget
    self.input = input
    hostView.addSubview(field)
    listener = field.addListener { [weak self] event in
      guard let self else { return }
      switch event {
      case .textFieldChanged(_, let text):
        self.backend?.sendText(text ?? "", from: self.id)
      case .focused:
        self.backend?.focus(self.id, gained: true)
      case .blurred:
        self.backend?.focus(self.id, gained: false)
      default:
        break
      }
    }
    let data = Unmanaged.passUnretained(self).toOpaque()
    let key: @convention(c) (Widget?, UnsafeMutablePointer<GdkEventKey>?, UnsafeMutableRawPointer?) -> gboolean = { _, event, data in
      guard let event, let data else { return 0 }
      let editor = Unmanaged<Editor>.fromOpaque(data).takeUnretainedValue()
      return editor.backend?.key(event.pointee, id: editor.id) ?? 0
    }
    keySignal = g_signal_connect_data(input, "key-press-event", unsafeBitCast(key, to: GCallback.self), data, nil, .init(rawValue: 0))
  }

  deinit {
    if keySignal != 0, g_signal_handler_is_connected(UnsafeMutableRawPointer(input), keySignal) != 0 {
      g_signal_handler_disconnect(UnsafeMutableRawPointer(input), keySignal)
    }
    if let listener { _ = field.removeListener(listener) }
    hostView.removeSubview(field)
    field.dispose()
  }

  func updateContent(_ props: NodeProps, background: SwiftUIRuntime.Color, label: String) {
    field.setText(props.text)
    field.setPlaceholder(props.placeholder.isEmpty ? nil : props.placeholder)
    if !multiline { field.setSecure(props.secure) }
    let name = label.isEmpty ? props.placeholder : label
    field.setAccessibilityLabel(name.isEmpty ? nil : name)
    if let accessible = gtk_widget_get_accessible(input) {
      if !name.isEmpty { atk_object_set_name(accessible, name) }
      let desc = !props.accessibilityValue.isEmpty ? props.accessibilityValue : props.help
      if !desc.isEmpty { atk_object_set_description(accessible, desc) }
      let traits = AccessibilityTraits(rawValue: props.accessibilityTraits)
      if traits.contains(.isSearchField) {
        atk_object_set_role(accessible, ATK_ROLE_TEXT)
      }
    }
    let font = props.font ?? .body
    let fontFamily = font.family == "Consolas" ? "monospace" : font.family == "Segoe UI" ? "sans-serif" : font.family
    field.setFontFamily(fontFamily.isEmpty ? nil : fontFamily)
    field.setFontSize(Double(font.size) * 72.0 / 96.0)
    field.setFontWeight(CInt(font.weight.value.rounded()))
    field.setTextColor((props.foreground ?? .black).nativeColor)
    field.setBackgroundColor(background.nativeColor)
  }

  func updatePlacement(_ props: NodeProps, visible: Rect) {
    let shown = !visible.isEmpty
    if shown, placement != visible {
      placement = visible
      field.setFrame(NativeAPI.Rectangle(
        x: Double(pixels(visible.minX)),
        y: Double(pixels(visible.minY)),
        width: Double(pixels(visible.width)),
        height: Double(pixels(visible.height))))
    }
    if gtk_widget_get_opacity(widget) != props.opacity { gtk_widget_set_opacity(widget, props.opacity) }
    field.setEnabled(props.enabled)
    field.setVisible(shown)
  }
}
#endif
