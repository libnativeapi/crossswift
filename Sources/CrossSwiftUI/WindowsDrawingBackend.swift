#if os(Windows)
  import Foundation
  import NativeAPI
  import SwiftUIRuntime
  import CSwiftUIWindows

  /// Generic SwiftUI drawing hosted by nativeapi. Decorative nodes share a
  /// display list; buttons keep native Windows handles and native activation.
  public final class WindowsDrawingBackend: RenderBackend {
    /// Ensures NativeAPI's early Per-Monitor V2 DPI setup has run before any
    /// standalone HWNDs are created outside `Application`.
    public static func prepareApplication() { _ = NativeAPI.Application.shared.isRunning() }
    public static func setApplicationIdentifier(_ identifier: String) {
      sui_set_application_identifier(identifier)
    }

    public var tapHandler: ((NodeID) -> Void)?
    public var transactionHandler: ((() -> Void) -> Void)?
    public var animationTickHandler: (() -> Bool)?
    public var interactionHandler: ((NodeID, Renderer.Interaction) -> Void)?
    public var inputHandler: ((NodeID?, Int, CGPoint, Int, EventModifiers, String) -> Bool)?
    private let schedulesUpdates: Bool
    private let tracesFrames = ProcessInfo.processInfo.environment["CROSS_SWIFTUI_TRACE_PATH"] != nil
    private var deliveringUpdate = false
    private var pendingRender: (() -> Void)?
    private var pendingPointer: (() -> Void)?
    private var contentListener: ListenerId?
    private var pendingEvents: [() -> Void] = []
    private var modalControls: Set<NodeID>?
    private var presentationOccluderRects: [Rect] = []
    private var controlBranches: Set<NodeID> = []
    private var desiredFocus: NodeID?
    private struct RetainedButton {
      let view: NativeAPI.Button
      let listener: ListenerId
      var enabled: Bool?
      var visible: Bool?
      var label: String?
      var hitRadius: Double = 0
    }
    private struct RetainedEdit {
      let view: NativeAPI.TextField
      let listener: ListenerId
      let multiline: Bool
      let secure: Bool
      var placeholder: String?
      var fontFamily: String?
      var fontSizePt: Double = -1
      var fontWeight: CInt = -1
      var textColorARGB: UInt32 = 0
      var bgColorARGB: UInt32?
      var accessibilityLabel: String?
      var enabled: Bool = true
    }
    private var edits: [NodeID: RetainedEdit] = [:]
    private var root: Element?
    private var appliedDarkMode: Bool? = nil
    private final class NativeShadowMask {
      let handle: UnsafeMutableRawPointer
      init?(_ mask: ShadowMask) {
        guard let handle = mask.alpha.withUnsafeBufferPointer({
          sui_mask_create($0.baseAddress, Int32(mask.width), Int32(mask.height))
        }) else { return nil }
        self.handle = handle
      }
      deinit { sui_mask_destroy(handle) }
    }
    private let shadowCache = ShadowCache<NativeShadowMask>()
    private struct AnimatedValues: Equatable {
      let rotation, scaleX, scaleY, opacity, offsetX, offsetY: Double
      let background: SwiftUIRuntime.Color?
      let foreground: SwiftUIRuntime.Color?
      let borderColor: SwiftUIRuntime.Color
      init(_ p: NodeProps) {
        rotation = p.rotation
        scaleX = p.scaleX
        scaleY = p.scaleY
        opacity = p.opacity
        offsetX = p.offsetX
        offsetY = p.offsetY
        background = p.background
        foreground = p.foreground
        borderColor = p.borderColor
      }
      init(
        rotation: Double, scaleX: Double, scaleY: Double,
        opacity: Double, offsetX: Double, offsetY: Double,
        background: SwiftUIRuntime.Color? = nil,
        foreground: SwiftUIRuntime.Color? = nil,
        borderColor: SwiftUIRuntime.Color = .clear
      ) {
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.background = background
        self.foreground = foreground
        self.borderColor = borderColor
      }
    }
    private struct Motion {
      let from: AnimatedValues
      let frame: Rect
      let animation: Animation
      let start: TimeInterval
      func isActive(at now: TimeInterval) -> Bool {
        animation.repeats || now < start + animation.duration
      }
      func interpolated(to target: AnimatedValues, at now: TimeInterval) -> AnimatedValues {
        let fraction = animation.progress(at: now, start: start)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        func mixColor(_ a: SwiftUIRuntime.Color?, _ b: SwiftUIRuntime.Color?) -> SwiftUIRuntime.Color? {
          guard let a, let b else { return b }
          return SwiftUIRuntime.Color(
            red: mix(a.red, b.red),
            green: mix(a.green, b.green),
            blue: mix(a.blue, b.blue),
            opacity: mix(a.opacity, b.opacity)
          )
        }
        return AnimatedValues(
          rotation: mix(from.rotation, target.rotation),
          scaleX: mix(from.scaleX, target.scaleX),
          scaleY: mix(from.scaleY, target.scaleY),
          opacity: mix(from.opacity, target.opacity),
          offsetX: mix(from.offsetX, target.offsetX),
          offsetY: mix(from.offsetY, target.offsetY),
          background: mixColor(from.background, target.background),
          foreground: mixColor(from.foreground, target.foreground),
          borderColor: mixColor(from.borderColor, target.borderColor) ?? target.borderColor)
      }
    }
    private var motions: [NodeID: Motion] = [:]
    private var previous: [NodeID: AnimatedValues] = [:]
    public var onResize: ((SwiftUIRuntime.Size) -> Void)?
    public var onTextSelectionOrCompositionChanged: (() -> Void)?
    public private(set) var lastTimings: [String: Double] = [:]
    public private(set) var publicationCount = 0
    public private(set) var fullPublicationCount = 0
    public private(set) var nativeHoverEventCount = 0
    public private(set) var nativeHoverEnterCount = 0
    public private(set) var totalPointerQueryMilliseconds: Double = 0
    public var totalPaintTimings: [String: Double] {
      guard let surface else { return [:] }
      let stats = sui_surface_total_paint_stats(surface)
      return ["raster": stats.raster_ms, "blit": stats.blit_ms, "count": Double(stats.paints)]
    }
    public var lastReusedPixels: Int64 { surface.map { sui_surface_reused_pixels($0) } ?? 0 }
    public var lastPaintTimings: [String: Double] {
      guard let surface else { return [:] }
      let stats = sui_surface_paint_stats(surface)
      return ["raster": stats.raster_ms, "blit": stats.blit_ms, "count": Double(stats.paints)]
    }
    private let window: NativeAPI.Window?
    public var environmentTransform: ((inout EnvironmentValues) -> Void)?
    public var onPreInput: ((Int, CGPoint, Int, EventModifiers) -> Bool)?
    public var canAcquireControlFocus: (() -> Bool)?
    public var environment: EnvironmentValues {
      var env: EnvironmentValues = window.map { .hosting($0) } ?? EnvironmentValues()
      environmentTransform?(&env)
      return env
    }
    private struct RetainedHostedView {
      let mount: any _HostedViewMount
      var nativeView: NativeAPI.View?
      var nativeHandle: UnsafeMutableRawPointer?
      var isEdit: Bool
      var handleKeyDown: ((Int, EventModifiers) -> Bool)?
    }
    private let content: NativeAPI.View
    private var surface: UnsafeMutableRawPointer?
    private var surfaceBackgroundColor: SwiftUIRuntime.Color = .white
    private var buttons: [NodeID: RetainedButton] = [:]
    private var hostedViews: [NodeID: RetainedHostedView] = [:]

    public convenience init?(window: NativeAPI.Window, schedulesUpdates: Bool = false) {
      guard let content = window.contentView else { return nil }
      self.init(view: content, window: window, schedulesUpdates: schedulesUpdates)
    }

    public init?(view content: NativeAPI.View, window: NativeAPI.Window? = nil, schedulesUpdates: Bool = false) {
      guard let handle = content.nativeObject else { return nil }
      self.schedulesUpdates = schedulesUpdates
      self.window = window ?? content.window
      self.content = content
      content.setLayout(.absolute)
      surface = sui_surface_create(
        handle,
        { context, id, event in
          guard let context else { return }
          let backend = Unmanaged<WindowsDrawingBackend>.fromOpaque(context).takeUnretainedValue()
          if event == 1 || event == 2 { backend.nativeHoverEventCount += 1 }
          if event == 1 { backend.nativeHoverEnterCount += 1 }
          if backend.schedulesUpdates && (event == 1 || event == 2) {
            backend.queuePointer()
            return
          }
          if event == 7 {
            backend.enqueue { [weak backend] in
              backend?.onTextSelectionOrCompositionChanged?()
            }
            return
          }
          let interaction: Renderer.Interaction
          switch event {
          case 1: interaction = .hover(true)
          case 2: interaction = .hover(false)
          case 3: interaction = .pressed(true)
          case 4: interaction = .pressed(false)
          case 5: interaction = .focus(true)
          default: interaction = .focus(false)
          }
          backend.enqueue { [weak backend] in
            guard let backend else { return }
            let node = NodeID(rawValue: Int(id))
            if event == 5 || event == 6 {
              // Several Tab/focus changes can arrive before the next render.
              // An obsolete gain must not pull focus back to its old HWND.
              let focused =
                backend.edits[node]?.view.isFocused
                ?? backend.hostedViews[node]?.nativeView?.isFocused
                ?? backend.buttons[node]?.view.isFocused ?? false
              guard focused == (event == 5) else { return }
            }
            backend.interactionHandler?(node, interaction)
          }
        }, Unmanaged.passUnretained(self).toOpaque(), content.nativeHandle)
      guard let surface else { return nil }
      sui_surface_input(
        surface,
        { context, id, event, x, y, value, modifiers in
          guard let context else { return 0 }
          let backend = Unmanaged<WindowsDrawingBackend>.fromOpaque(context).takeUnretainedValue()
          if backend.schedulesUpdates {
            if event == 1 || event == 10 {
              backend.queuePointer(fallback: CGPoint(x: x, y: y))
              return 1
            }
            if event == 5 {
              backend.enqueue { [weak backend] in
                _ = backend?.inputHandler?(
                  id == 0 ? nil : NodeID(rawValue: Int(id)), 5,
                  CGPoint(x: x, y: y), Int(value), EventModifiers(rawValue: Int(modifiers)), "")
              }
              return 1
            }
            if event == 8 {
              if !backend.motions.isEmpty || backend.root?.hasLayoutAnimation == true {
                _ = backend.content.requestUpdate()
              }
              return 0
            }
            // Preserve press/key/text ordering relative to earlier pointer input.
            if [2, 3, 4, 6, 7, 9].contains(Int(event)) { backend.drainInput() }
          }
          if event == 12 {
            if let root = backend.root { backend.didRender(root) }
            return 0
          }
          if event == 11 {
            let jobs = backend.pendingEvents
            backend.pendingEvents.removeAll()
            if let transaction = backend.transactionHandler {
              transaction { jobs.forEach { $0() } }
            } else {
              jobs.forEach { $0() }
            }
            return 0
          }
          if event == 8 {
            if backend.root?.hasLayoutAnimation == true {
              _ = backend.animationTickHandler?()
            } else {
              backend.tick()
            }
            return 0
          }
          if event == 10, let point = backend.pointerLocation(fallback: .zero) {
            // Leaving a native scrolling container for one of its children is
            // not leaving the SwiftUI surface. Reconcile the current hit path.
            return backend.inputHandler?(nil, 1, point, 0, [], "") == true ? 1 : 0
          }
          if backend.onPreInput?(
            Int(event), CGPoint(x: x, y: y), Int(value), EventModifiers(rawValue: Int(modifiers))
          ) == true {
            return 1
          }
          if event == 6 && id != 0,
            backend.handleHostedKeyDown(
              id: NodeID(rawValue: Int(id)),
              vk: Int(value),
              modifiers: EventModifiers(rawValue: Int(modifiers))
            )
          {
            return 1
          }
          return backend.inputHandler?(
            id == 0 ? nil : NodeID(rawValue: Int(id)), Int(event), CGPoint(x: x, y: y), Int(value),
            EventModifiers(rawValue: Int(modifiers)), "") == true ? 1 : 0
        })
      contentListener = content.addListener { [weak self] event in
        guard let self else { return }
        switch event {
        case .updating where self.schedulesUpdates:
          self.deliverUpdate()
        case let .resized(_, size):
          self.onResize?(SwiftUIRuntime.Size(width: size.width, height: size.height))
          if self.schedulesUpdates && !self.deliveringUpdate && self.pendingRender != nil {
            self.content.cancelUpdate()
            self.deliverUpdate()
          }
        default:
          break
        }
      }
    }
    deinit {
      content.cancelUpdate()
      if let contentListener { _ = content.removeListener(contentListener) }
      for id in Array(hostedViews.keys) { removeHostedView(id) }
      for id in Array(edits.keys) { removeEdit(id) }
      for id in Array(buttons.keys) { removeButton(id) }
      if let surface { sui_surface_destroy(surface) }
    }

    public func setBackgroundColor(_ color: SwiftUIRuntime.Color) {
      surfaceBackgroundColor = color
      guard let surface else { return }
      sui_surface_set_background(surface, color.argb)
    }

    public func setWindowShadow(enabled: Bool, isDark: Bool) {
      guard let surface else { return }
      sui_surface_set_window_shadow(surface, enabled ? 1 : 0, isDark ? 1 : 0)
    }

    public func flushSyncPaint() {
      guard let surface else { return }
      sui_surface_flush_paint(surface)
    }

    public func beginPendingResize(width: Double, height: Double) {
      guard let surface else { return }
      sui_surface_begin_pending_resize(surface, width, height)
    }

    public func prerenderPendingResize() {
      guard let surface else { return }
      sui_surface_prerender_pending_resize(surface)
    }

    public func commitPendingResize() {
      guard let surface else { return }
      sui_surface_commit_pending_resize(surface)
    }

    public func flushPendingEdits() {
      guard let surface else { return }
      sui_surface_flush_edits(surface)
    }

    public func setContentOffset(x: Double, y: Double) {
      guard let surface else { return }
      sui_surface_set_content_offset(surface, x, y)
    }

    public func setPendingContentOffset(x: Double, y: Double) {
      guard let surface else { return }
      sui_surface_set_pending_offset(surface, x, y)
    }

    private struct TextMeasurementKey: Hashable {
      let text: String, family: String
      let size: Double, weight: Double
    }
    private static var textMeasurements: [TextMeasurementKey: SwiftUIRuntime.Size] = [:]

    public static func measureText(_ text: String, font: Font) -> SwiftUIRuntime.Size {
      let key = TextMeasurementKey(
        text: text, family: font.family, size: Double(font.size), weight: font.weight.value)
      if let cached = textMeasurements[key] { return cached }
      let measured = sui_measure_text(text, font.family, Double(font.size), font.weight.value)
      let size = SwiftUIRuntime.Size(width: measured.width, height: measured.height)
      // Bound cache growth when applications display arbitrary edited text.
      if textMeasurements.count >= 10000 { textMeasurements.removeAll(keepingCapacity: true) }
      textMeasurements[key] = size
      return size
    }

    /// Drawing is published atomically from didRender after diffing assigns IDs.
    public var needsRenderCommands: Bool { false }
    public func perform(_ commands: [RenderCommand]) {}
    public func didMeasureRender(_ timings: [String: Double]) {
      guard tracesFrames, let surface else { return }
      for (stage, name) in ["evaluate", "environment", "layout", "finalize", "diff",
                            "backend", "scroll.translate"].enumerated() {
        if let value = timings[name] { sui_surface_trace_duration(surface, Int32(stage), value) }
      }
      for (stage, name) in ["prepare", "draw", "controls", "publish"].enumerated() {
        if let value = lastTimings[name] { sui_surface_trace_duration(surface, Int32(stage + 10), value) }
      }
    }
    private func findColorSchemeOverride(_ node: Element) -> ColorScheme? {
      if let scheme = node.props.colorSchemeOverride { return scheme }
      for child in node.children {
        if let scheme = findColorSchemeOverride(child) { return scheme }
      }
      return nil
    }

    public func didRender(_ root: Element) {
      guard let surface else { return }
      if let scheme = findColorSchemeOverride(root) {
        let isDark = (scheme == .dark)
        if appliedDarkMode != isDark {
          appliedDarkMode = isDark
          if let native = window?.nativeObject {
            sui_window_set_dark_mode(native, isDark ? 1 : 0)
          }
        }
      }
      fullPublicationCount += 1
      let started = Date.timeIntervalSinceReferenceDate
      let now = Date.timeIntervalSinceReferenceDate
      var current: [NodeID: AnimatedValues] = [:]
      current.reserveCapacity(previous.count)
      var live = Set<NodeID>()
      live.reserveCapacity(buttons.count)
      var liveEdits = Set<NodeID>()
      liveEdits.reserveCapacity(edits.count)
      var liveHosted = Set<NodeID>()
      liveHosted.reserveCapacity(hostedViews.count)
      controlBranches.removeAll(keepingCapacity: true)
      var hasModal = false
      var hasFocusRequest = false
      let rootSizeChanged = self.root.map {
        abs($0.frame.width - root.frame.width) > 0.5 || abs($0.frame.height - root.frame.height) > 0.5
      } ?? false
      let suppressAllAnimations = root.props.animationDisabled || rootSizeChanged
      @discardableResult
      func animate(_ node: Element, inherited: Animation?, disabled: Bool) -> Bool {
        var hasControl = false
        switch node.kind {
        case .textField:
          liveEdits.insert(node.id)
          hasControl = true
        case .hostedView:
          liveHosted.insert(node.id)
          hasControl = true
        case .styledButton, .button:
          live.insert(node.id)
          hasControl = true
        case .scroll:
          hasControl = true
        default:
          break
        }
        if node.props.accessibilityTraits & AccessibilityTraits.isModal.rawValue != 0 {
          hasModal = true
        }
        if node.props.focusRequested {
          hasFocusRequest = true
        }
        let values = AnimatedValues(node.props)
        current[node.id] = values
        let nodeDisabled = disabled || node.props.animationDisabled
        let animation = nodeDisabled ? nil : (node.props.animation ?? inherited)
        if let old = previous[node.id], old != values {
          if let animation, animation.duration > 0 {
            let origin: AnimatedValues
            if let existing = motions[node.id], existing.isActive(at: now) {
              origin = existing.interpolated(to: old, at: now)
            } else {
              origin = old
            }
            motions[node.id] = Motion(
              from: origin, frame: node.frame, animation: animation, start: now + animation.delay)
          } else if !motions.isEmpty {
            motions.removeValue(forKey: node.id)
          }
        } else if nodeDisabled, !motions.isEmpty {
          motions.removeValue(forKey: node.id)
        }
        for child in node.children {
          if animate(child, inherited: animation, disabled: nodeDisabled) {
            hasControl = true
          }
        }
        if hasControl { controlBranches.insert(node.id) }
        return hasControl
      }
      animate(root, inherited: nil, disabled: suppressAllAnimations)
      if suppressAllAnimations {
        motions.removeAll(keepingCapacity: true)
      }
      previous = current
      if !motions.isEmpty {
        motions = motions.filter { current[$0.key] != nil }
      }
      self.root = root
      modalControls = nil
      func modal(_ node: Element) {
        if node.props.accessibilityTraits & AccessibilityTraits.isModal.rawValue != 0 {
          func ids(_ node: Element) -> [NodeID] { [node.id] + node.children.flatMap(ids) }
          modalControls = Set(ids(node))
        }
        for child in node.children { modal(child) }
      }
      if hasModal { modal(root) }
      desiredFocus = nil
      func focusTarget(_ node: Element) {
        if node.props.focusRequested {
          func controls(_ node: Element) -> [NodeID] {
            if node.kind == .button || node.kind == .styledButton || node.kind == .textField {
              return [node.id]
            }
            return node.children.flatMap(controls)
          }
          let candidates = controls(node)
          desiredFocus =
            candidates.first(where: { id in
              edits[id]?.view.isFocused == true || buttons[id]?.view.isFocused == true
            }) ?? candidates.first
        }
        for child in node.children { focusTarget(child) }
      }
      if hasFocusRequest { focusTarget(root) }
      if !buttons.isEmpty {
        let deadButtons = buttons.keys.filter { !live.contains($0) }
        for id in deadButtons { removeButton(id) }
      }
      if !edits.isEmpty {
        let deadEdits = edits.keys.filter { !liveEdits.contains($0) }
        for id in deadEdits { removeEdit(id) }
      }
      if !hostedViews.isEmpty {
        let deadHosted = hostedViews.keys.filter { !liveHosted.contains($0) }
        for id in deadHosted { removeHostedView(id) }
      }
      sui_surface_begin(surface)
      lastTimings["prepare"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
      publish(root, on: surface)
      if schedulesUpdates && !deliveringUpdate && (!motions.isEmpty || root.hasLayoutAnimation) {
        _ = content.requestUpdate()
      }
    }

    public func didScroll(_ root: Element) {
      guard motions.isEmpty else {
        didRender(root)
        return
      }
      guard let surface else { return }
      self.root = root
      // Scrolling does not change live controls, animation values, modal state
      // or focus requests. Keep those registrations and publish new geometry.
      lastTimings["prepare"] = 0
      sui_surface_begin(surface)
      publish(root, on: surface, geometryOnly: true)
    }

    private func publish(_ root: Element, on surface: UnsafeMutableRawPointer, geometryOnly: Bool = false) {
      publicationCount += 1
      presentationOccluderRects.removeAll(keepingCapacity: true)
      if root.hasActivePresentation {
        var fullScrim = false
        for overlay in root.children.dropFirst() {
          let isFullBackdrop = overlay.kind == .shape && overlay.frame == root.frame
          if isFullBackdrop {
            if (overlay.props.background?.opacity ?? 0) > 0.001 {
              fullScrim = true
              break
            }
          } else if overlay.frame.width > 0 && overlay.frame.height > 0 {
            presentationOccluderRects.append(overlay.frame)
          }
        }
        if fullScrim {
          presentationOccluderRects = [root.frame]
        }
      }
      var started = Date.timeIntervalSinceReferenceDate
      draw(root, clip: root.frame)
      lastTimings["draw"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
      started = Date.timeIntervalSinceReferenceDate
      sui_controls_begin(surface)
      updateButtons(root, clip: root.frame, background: surfaceBackgroundColor, geometryOnly: geometryOnly)
      lastTimings["controls"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
      started = Date.timeIntervalSinceReferenceDate
      sui_surface_end(surface)
      lastTimings["publish"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
      for (stage, name) in ["reuse", "order", "commands", "geometry", "damage", "invalidate"]
        .enumerated()
      {
        lastTimings["publish.\(name)"] = sui_surface_publish_time(surface, Int32(stage))
      }
    }

    /// Native activation for integration tests or accessibility adapters. It is
    /// scoped to a retained control, never to the user's keyboard or pointer.
    public func activate(_ id: NodeID) {
      if let handle = buttons[id]?.view.nativeObject {
        sui_button_activate(handle)
        if let surface { sui_surface_flush(surface) }
      }
    }
    /// Programmatic editing and pointer events are scoped to this surface's HWND.
    public func replaceText(_ id: NodeID, with text: String) {
      guard let edit = edits[id]?.view else { return }
      edit.setText(text)
      enqueue { [weak self] in
        _ = self?.inputHandler?(id, 7, .zero, 0, [], text)
      }
      if schedulesUpdates {
        drainInput()
      } else if let surface {
        sui_surface_flush(surface)
      }
    }
    public func pointer(event: Int, at point: CGPoint, value: Int = 0) {
      if let surface { sui_surface_pointer(surface, Int32(event), point.x, point.y, Int32(value)) }
    }
    public func pointerLocation(fallback: CGPoint) -> CGPoint? {
      guard let surface else { return nil }
      let started = Date.timeIntervalSinceReferenceDate
      defer {
        totalPointerQueryMilliseconds += (Date.timeIntervalSinceReferenceDate - started) * 1000
      }
      var x = 0.0
      var y = 0.0
      guard sui_surface_cursor(surface, &x, &y) != 0 else { return nil }
      return CGPoint(x: x, y: y)
    }
    public func nativeButton(_ id: NodeID) -> NativeAPI.Button? { buttons[id]?.view }
    public func nativeTextField(_ id: NodeID) -> NativeAPI.TextField? { edits[id]?.view }
    public func hostedNativeView(_ id: NodeID) -> NativeAPI.View? { hostedViews[id]?.nativeView }
    internal func handleHostedKeyDown(id: NodeID, vk: Int, modifiers: EventModifiers) -> Bool {
      hostedViews[id]?.handleKeyDown?(vk, modifiers) ?? false
    }
    public func focusNextControl(from current: UnsafeMutableRawPointer?, backward: Bool = false) {
      if let surface {
        sui_surface_focus_next(surface, current, backward ? 1 : 0)
      }
    }
    public func advanceFocus(from id: NodeID?, backward: Bool = false) {
      if let surface {
        let current = id.flatMap {
          buttons[$0]?.view.nativeObject
            ?? edits[$0]?.view.nativeObject
            ?? hostedViews[$0]?.nativeHandle
        }
        sui_surface_focus_next(surface, current, backward ? 1 : 0)
      }
    }
    public func applyPendingFocusIfNeeded() {
      guard canAcquireControlFocus?() ?? true, let id = desiredFocus else { return }
      if let edit = edits[id], edit.enabled, !edit.view.isFocused {
        edit.view.focus()
      } else if let btn = buttons[id]?.view, btn.isEnabled, !btn.isFocused {
        btn.focus()
      }
    }
    func focusInitialControl() {
      // The top-level HWND initially owns focus. Put it on the first available
      // control so Tab works before the user has clicked anything.
      if !buttons.values.contains(where: { $0.view.isFocused })
        && !edits.values.contains(where: { $0.view.isFocused })
      {
        advanceFocus(from: nil)
      }
    }

    public func requestRender(_ render: @escaping () -> Void) -> Bool {
      guard schedulesUpdates, !deliveringUpdate else { return false }
      pendingRender = render
      if content.requestUpdate() { return true }
      pendingRender = nil
      return false
    }
    private func queuePointer(fallback: CGPoint = .zero) {
      pendingPointer = { [weak self] in
        guard let self else { return }
        let point = self.pointerLocation(fallback: fallback)
        _ = self.inputHandler?(nil, point == nil ? 10 : 1, point ?? fallback, 0, [], "")
      }
      // A move over unchanged content must not consume the next publication
      // slot. Resolve that cheap hit path now; state changes still request one
      // deferred render. Preserve ordering when wheel/actions are pending.
      if pendingEvents.isEmpty && pendingRender == nil && !deliveringUpdate {
        drainInput()
      } else if !content.requestUpdate() {
        drainInput()
      }
    }
    private func drainInput() {
      let jobs = pendingEvents
      pendingEvents.removeAll(keepingCapacity: true)
      let pointer = pendingPointer
      pendingPointer = nil
      let run = {
        jobs.forEach { $0() }
        pointer?()
      }
      if let transaction = transactionHandler { transaction(run) } else { run() }
    }
    private func deliverUpdate() {
      if let surface { sui_surface_trace_update(surface, 1) }
      defer { if let surface { sui_surface_trace_update(surface, 0) } }
      deliveringUpdate = true
      defer { deliveringUpdate = false }
      let publications = publicationCount
      drainInput()
      let render = pendingRender
      pendingRender = nil
      render?()
      if publications == publicationCount {
        if root?.hasLayoutAnimation == true {
          _ = animationTickHandler?()
        } else {
          tick()
        }
      }
      flushPendingEdits()
      if !motions.isEmpty || root?.hasLayoutAnimation == true { _ = content.requestUpdate() }
    }
    private func enqueue(_ action: @escaping () -> Void) {
      let schedule = pendingEvents.isEmpty
      pendingEvents.append(action)
      if schedulesUpdates {
        if !content.requestUpdate() { drainInput() }
      } else if schedule, let surface {
        sui_surface_schedule(surface)
      }
    }
    private func tick() {
      // The C bridge services Dispatch without consuming NativeAPI WM_QUIT.
      guard !motions.isEmpty, let surface, let root else { return }
      let hadVisible = motions.values.contains(where: {
        let visible = $0.frame.intersection(root.frame)
        return visible.width > 0 && visible.height > 0
      })
      let now = Date.timeIntervalSinceReferenceDate
      motions = motions.filter { $0.value.isActive(at: now) }
      guard hadVisible else { return }
      sui_surface_begin(surface)
      draw(root, clip: root.frame)
      sui_surface_end(surface)
    }
    private func updateButtons(
      _ node: Element, allowed: Bool = true, clip: Rect,
      background: SwiftUIRuntime.Color = .white, nativeClip: Rect? = nil,
      geometryOnly: Bool = false
    ) {
      guard controlBranches.contains(node.id) else { return }
      let allowed = allowed && node.props.hitTesting
      let modalAllowed = modalControls?.contains(node.id) ?? true
      let controlAllowed = allowed && modalAllowed
      let blockedByPresentation =
        !modalAllowed || (root?.hasActivePresentation == true && !allowed)
      let occludedByPresentation =
        blockedByPresentation
        && (!modalAllowed
          || presentationOccluderRects.contains(where: {
            let inter = $0.intersection(node.frame)
            return inter.width > 0 && inter.height > 0
          }))
      let passthroughForPresentation =
        blockedByPresentation && !occludedByPresentation && node.kind != .styledButton
      let clip = node.props.clipped ? clip.intersection(node.frame) : clip
      var nativeClip = nativeClip.map { node.props.clipped ? $0.intersection(node.frame) : $0 }
      let parentBackground = background
      let background: SwiftUIRuntime.Color
      if let bg = node.props.background {
        let a = min(max(bg.opacity, 0), 1)
        if a >= 0.999 {
          background = bg
        } else if a > 0.001 {
          background = SwiftUIRuntime.Color(
            red: bg.red * a + parentBackground.red * (1 - a),
            green: bg.green * a + parentBackground.green * (1 - a),
            blue: bg.blue * a + parentBackground.blue * (1 - a),
            opacity: 1.0
          )
        } else {
          background = parentBackground
        }
      } else {
        background = parentBackground
      }
      let wantsFocus = desiredFocus == node.id
      let viewport = node.frame.intersection(clip)
      let shownInViewport =
        node.props.visible && !occludedByPresentation && viewport.width > 0 && viewport.height > 0
      let inViewport = shownInViewport && controlAllowed
      let buttonShown = shownInViewport && (controlAllowed || passthroughForPresentation)
      // Keep child HWND coordinates stable while the ScrollView's content moves.
      // The shared framebuffer remains in surface coordinates at native DPI.
      let grouped = node.kind == .scroll && node.children.first != nil
      if grouped, let surface, let child = node.children.first {
        let r = child.frame
        let visible = node.props.visible ? clip.intersection(node.frame) : .zero
        sui_controls_push(
          surface, Int64(node.id.rawValue), r.minX, r.minY, r.width, r.height,
          visible.minX, visible.minY, visible.width, visible.height)
        // The parent viewport already clips this content. Only additional
        // clipping inside it belongs in each control's local hit region.
        nativeClip = r
      }
      defer { if grouped, let surface { sui_controls_pop(surface) } }
      if node.kind == .styledButton || node.kind == .button, buttons[node.id] != nil || buttonShown {
        let retained = buttons[node.id] != nil
        if buttons[node.id] == nil {
          let initialTitle = label(node)
          guard let button = NativeAPI.Button.create(initialTitle), let handle = button.nativeObject
          else {
            fatalError("nativeapi failed to create a button")
          }
          let styled = node.kind == .styledButton
          if let surface {
            sui_surface_button(
              surface, handle, Int64(node.id.rawValue), styled ? 1 : 0, button.nativeHandle)
          }
          let id = node.id
          let listener = button.addListener { [weak self] event in
            if case .buttonClicked = event {
              self?.enqueue { [weak self] in self?.tapHandler?(id) }
            }
          }
          buttons[id] = RetainedButton(view: button, listener: listener, label: initialTitle)
        }
        var entry = buttons[node.id]!
        let button = entry.view
        let r = node.frame
        if buttonShown || nativeClip != nil, let surface, let handle = button.nativeObject {
          sui_control_frame(surface, handle, r.minX, r.minY, r.width, r.height)
        }
        // A scroll-only publication preserves state and labels. Native parent
        // clipping handles visibility inside a scroll group; ungrouped controls
        // still need visibility refreshed when their viewport changes.
        if !geometryOnly || !retained {
          let enabled = node.props.enabled && (controlAllowed || passthroughForPresentation)
          if entry.enabled != enabled {
            if button.isEnabled != enabled { button.setEnabled(enabled) }
            entry.enabled = enabled
          }
          if !retained || !node.reusesLayout {
            let title = label(node)
            if entry.label != title {
              button.setText(title)
              entry.label = title
            }
            func hitRadius(_ element: Element) -> Double {
              var radius = element.props.hitRadius
              for child in element.children {
                radius = max(radius, hitRadius(child))
              }
              return radius
            }
            entry.hitRadius = hitRadius(node)
          }
        }
        if !geometryOnly || !retained || nativeClip == nil {
          // Opacity-zero shortcut buttons still participate in the renderer's
          // key handling, but their HWND must not paint or occlude the canvas.
          let visible = node.props.visible && node.props.opacity > 0
            && (controlAllowed || passthroughForPresentation) && (nativeClip != nil || buttonShown)
          if entry.visible != visible {
            if button.isVisible != visible { button.setVisible(visible) }
            entry.visible = visible
          }
        }
        buttons[node.id] = entry
          if let surface, let handle = button.nativeObject {
            sui_control_tab_visible(surface, handle, inViewport ? 1 : 0)
            sui_control_set_passthrough(surface, handle, passthroughForPresentation ? 1 : 0)
            let visible =
              node.props.visible && (controlAllowed || passthroughForPresentation)
              ? r.intersection(nativeClip ?? clip) : .zero
            sui_button_update(
              surface, handle, entry.hitRadius, node.props.help,
              visible.minX - r.minX, visible.minY - r.minY, visible.width, visible.height)
            if !node.props.accessibilityValue.isEmpty || !node.props.accessibilityLabel.isEmpty {
              sui_button_set_accessibility(handle, label(node), node.props.accessibilityValue)
            }
          }
        if wantsFocus && (canAcquireControlFocus?() ?? true) && !button.isFocused && node.props.enabled && inViewport {
          button.focus()
        }
      }
      if node.kind == .textField, let surface, edits[node.id] != nil || shownInViewport {
        if let existing = edits[node.id],
          existing.multiline != node.props.multiline || existing.secure != node.props.secure
        {
          removeEdit(node.id)
        }
        let retained = edits[node.id] != nil
        if edits[node.id] == nil {
          guard let field = NativeAPI.TextField.create(node.props.text) else {
            fatalError("nativeapi failed to create a text field")
          }
          if node.props.multiline { field.setMultiline(true) }
          if node.props.secure { field.setSecure(true) }
          field.setBordered(false)
          guard let handle = field.nativeObject else {
            field.dispose()
            fatalError("nativeapi text field has no native handle")
          }
          sui_surface_edit(surface, handle, Int64(node.id.rawValue), field.nativeHandle)
          let id = node.id
          let listener = field.addListener { [weak self] event in
            switch event {
            case let .textFieldChanged(_, text):
              let value = text ?? ""
              self?.enqueue { [weak self] in
                if self?.schedulesUpdates == true { self?.drainInput() }
                _ = self?.inputHandler?(id, 7, .zero, 0, [], value)
              }
            case .focused:
              self?.enqueue { [weak self] in
                guard let self, self.edits[id]?.view.isFocused == true else { return }
                self.interactionHandler?(id, .focus(true))
              }
            case .blurred:
              self?.enqueue { [weak self] in
                guard let self, self.edits[id]?.view.isFocused == false else { return }
                self.interactionHandler?(id, .focus(false))
              }
            default:
              break
            }
          }
          edits[id] = RetainedEdit(
            view: field, listener: listener, multiline: node.props.multiline,
            secure: node.props.secure)
        }
        if var edit = edits[node.id], let handle = edit.view.nativeObject {
          let p = node.props
          let r = node.frame
          let isTransparentBg = (p.background == nil) || (p.background!.opacity < 0.999)
          let defaultFg: SwiftUIRuntime.Color =
            environment.colorScheme == .dark ? .white : .black
          let resolvedFg = p.foreground ?? defaultFg
          if !geometryOnly || !retained {
            let font = p.font ?? .body
            if edit.view.text != p.text {
              edit.view.setText(p.text)
            }
            let nativePlaceholder: String? =
              isTransparentBg ? nil : (p.placeholder.isEmpty ? nil : p.placeholder)
            if !retained || edit.placeholder != nativePlaceholder {
              edit.view.setPlaceholder(nativePlaceholder)
              edit.placeholder = nativePlaceholder
            }
            let fontFamily = font.family.isEmpty ? nil : font.family
            let fontSizePt = Double(font.size) * 72.0 / 96.0
            let fontWeight = CInt(font.weight.value.rounded())
            if !retained || edit.fontFamily != fontFamily || abs(edit.fontSizePt - fontSizePt) > 0.01
              || edit.fontWeight != fontWeight
            {
              edit.view.setFontFamily(fontFamily)
              edit.view.setFontSize(fontSizePt)
              edit.view.setFontWeight(fontWeight)
              edit.fontFamily = fontFamily
              edit.fontSizePt = fontSizePt
              edit.fontWeight = fontWeight
            }
            if !retained || edit.textColorARGB != resolvedFg.argb {
              edit.view.setTextColor(resolvedFg.nativeColor)
              edit.textColorARGB = resolvedFg.argb
            }
            if let explicitBg = p.background, explicitBg.opacity >= 0.999 {
              if !retained || edit.bgColorARGB != explicitBg.argb {
                edit.view.setBackgroundColor(explicitBg.nativeColor)
                edit.bgColorARGB = explicitBg.argb
              }
            }
            let rawName = p.accessibilityLabel.isEmpty ? p.placeholder : p.accessibilityLabel
            let name = rawName.isEmpty ? nil : rawName
            if !retained || edit.accessibilityLabel != name {
              edit.view.setAccessibilityLabel(name)
              edit.accessibilityLabel = name
            }
            let enabled = p.enabled && (controlAllowed || passthroughForPresentation)
            if !retained || edit.enabled != enabled {
              edit.view.setEnabled(enabled)
              edit.enabled = enabled
            }
            edits[node.id] = edit
            if wantsFocus && (canAcquireControlFocus?() ?? true) && enabled && !edit.view.isFocused && inViewport {
              edit.view.focus()
            }
          }
          var editRect = r
          if !p.multiline {
            // Single-line Win32 EDIT paints at y = 0 of its own HWND rather
            // than centring vertically. Align the glyph's optical cap centre to
            // the layout slot's midpoint.
            var lineCenter = 0.0
            var lineHeight = 0.0
            sui_edit_line_metrics(surface, handle, &lineCenter, &lineHeight)
            if lineHeight > 0 {
              let editY = r.minY + r.height * 0.5 - lineCenter
              editRect = Rect(
                x: r.minX, y: editY, width: r.width,
                height: max(lineHeight, r.maxY - editY))
            }
          }
          if shownInViewport || nativeClip != nil {
            sui_control_frame(
              surface, handle, editRect.minX, editRect.minY, editRect.width, editRect.height)
          }
          let placeholderARGB = resolvedFg.opacity(0.42).argb
          p.placeholder.withCString { placeholderCStr in
            sui_edit_set_transparent(
              surface, handle, isTransparentBg ? 1 : 0,
              editRect.minX + editRect.width * 0.5,
              editRect.minY + editRect.height * 0.5,
              placeholderCStr, resolvedFg.argb, placeholderARGB,
              p.multiline ? 1 : 0)
          }
          sui_edit_order(surface, handle)
          sui_control_set_passthrough(surface, handle, passthroughForPresentation ? 1 : 0)
          sui_control_opacity(handle, p.opacity)
          let visible = shownInViewport ? editRect.intersection(nativeClip ?? clip) : .zero
          sui_surface_control_clip(
            surface, handle, visible.minX - editRect.minX, visible.minY - editRect.minY,
            visible.width, visible.height)
        }
      }
      if node.kind == .hostedView, let surface, let adapter = node.hostedViewAdapter as? any _HostedViewBackendBridge {
        let r = node.frame
        var entry: RetainedHostedView
        if let existing = hostedViews[node.id] {
          adapter.updateMount(existing.mount, frame: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
          entry = existing
        } else {
          let created = adapter.createMount(frame: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
          entry = RetainedHostedView(
            mount: created.mount,
            nativeView: created.nativeView,
            nativeHandle: nil,
            isEdit: false,
            handleKeyDown: nil
          )
        }
        let editorDesc = adapter.editorDescriptor(for: entry.mount)
        let resolvedNV = editorDesc?.nativeView ?? entry.nativeView
        let nextHandle = resolvedNV?.nativeObject
        let wantEdit = editorDesc != nil
        if entry.nativeHandle != nextHandle || entry.isEdit != wantEdit {
          if let oldHandle = entry.nativeHandle {
            if entry.isEdit {
              sui_surface_remove_edit(surface, oldHandle)
            } else {
              sui_surface_remove_custom_view(surface, oldHandle)
            }
          }
          if let nv = resolvedNV, let newHandle = nextHandle {
            if wantEdit {
              sui_surface_edit(surface, newHandle, Int64(node.id.rawValue), nv.nativeHandle)
            } else {
              sui_surface_custom_view(surface, newHandle, nv.nativeHandle)
            }
          }
          entry.nativeView = resolvedNV
          entry.nativeHandle = nextHandle
          entry.isEdit = wantEdit
        }
        entry.handleKeyDown = editorDesc?.handleKeyDown
        if let handle = entry.nativeHandle {
          if let editorDesc {
            var editRect = r
            if editorDesc.isSingleLine {
              var lineCenter = 0.0
              var lineHeight = 0.0
              sui_edit_line_metrics(surface, handle, &lineCenter, &lineHeight)
              if lineHeight > 0 {
                let editY = r.minY + r.height * 0.5 - lineCenter
                editRect = Rect(
                  x: r.minX, y: editY, width: r.width,
                  height: max(lineHeight, r.maxY - editY))
              }
            }
            if shownInViewport || nativeClip != nil {
              sui_control_frame(
                surface, handle, editRect.minX, editRect.minY, editRect.width, editRect.height)
            }
            "".withCString { emptyCStr in
              sui_edit_set_transparent(
                surface, handle, editorDesc.isTransparentBackground ? 1 : 0,
                editRect.minX + editRect.width * 0.5,
                editRect.minY + editRect.height * 0.5,
                emptyCStr, editorDesc.textColorARGB, 0,
                editorDesc.isSingleLine ? 0 : 1)
            }
            sui_edit_order(surface, handle)
            sui_control_set_passthrough(surface, handle, passthroughForPresentation ? 1 : 0)
            sui_control_opacity(handle, node.props.opacity)
            let visible = shownInViewport ? editRect.intersection(nativeClip ?? clip) : .zero
            sui_surface_control_clip(
              surface, handle, visible.minX - editRect.minX, visible.minY - editRect.minY,
              visible.width, visible.height)
          } else {
            if shownInViewport || nativeClip != nil {
              sui_control_frame(surface, handle, r.minX, r.minY, r.width, r.height)
            }
            sui_custom_view_order(surface, handle)
            sui_control_opacity(handle, node.props.opacity)
            let visible = shownInViewport ? r.intersection(nativeClip ?? clip) : .zero
            sui_surface_control_clip(
              surface, handle, visible.minX - r.minX, visible.minY - r.minY,
              visible.width, visible.height)
          }
        }
        hostedViews[node.id] = entry
      }
      forEachOrderedChild(node) { child in
        updateButtons(
          child, allowed: allowed, clip: clip, background: background, nativeClip: nativeClip,
          geometryOnly: geometryOnly)
      }
    }
    private func label(_ node: Element) -> String {
      if !node.props.accessibilityLabel.isEmpty { return node.props.accessibilityLabel }
      if !node.props.text.isEmpty { return node.props.text }
      return node.children.map(label).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func removeHostedView(_ id: NodeID) {
      guard let entry = hostedViews.removeValue(forKey: id) else { return }
      if let surface, let handle = entry.nativeHandle {
        if entry.isEdit {
          sui_surface_remove_edit(surface, handle)
        } else {
          sui_surface_remove_custom_view(surface, handle)
        }
      }
      entry.mount.dismantle()
    }
    private func removeEdit(_ id: NodeID) {
      guard let edit = edits.removeValue(forKey: id) else { return }
      _ = edit.view.removeListener(edit.listener)
      if let surface, let handle = edit.view.nativeObject {
        sui_surface_remove_edit(surface, handle)
      }
      edit.view.dispose()
    }
    private func removeButton(_ id: NodeID) {
      guard let button = buttons.removeValue(forKey: id) else { return }
      _ = button.view.removeListener(button.listener)
      if let surface, let handle = button.view.nativeObject {
        sui_surface_remove_button(surface, handle)
      }
      button.view.dispose()
    }
    private func draw(
      _ node: Element, clip: Rect, transformedAncestor: Bool = false,
      inheritedOpacity: Double = 1.0, allowed: Bool = true
    ) {
      guard let surface, node.props.visible else { return }
      var p = node.props
      let allowed = allowed && p.hitTesting
      let modalAllowed = modalControls?.contains(node.id) ?? true
      let blockedByPresentation =
        !modalAllowed || (root?.hasActivePresentation == true && !allowed)
      let r = node.frame
      let occludedByPresentation =
        blockedByPresentation
        && (!modalAllowed
          || presentationOccluderRects.contains(where: {
            let inter = $0.intersection(r)
            return inter.width > 0 && inter.height > 0
          }))
      var translated = false
      if let motion = motions[node.id] {
        let now = Date.timeIntervalSinceReferenceDate
        let current = motion.interpolated(to: AnimatedValues(p), at: now)
        p.rotation = current.rotation
        p.scaleX = current.scaleX
        p.scaleY = current.scaleY
        p.opacity = current.opacity
        p.background = current.background
        p.foreground = current.foreground
        p.borderColor = current.borderColor
        let dx = current.offsetX - p.offsetX
        let dy = current.offsetY - p.offsetY
        if dx != 0 || dy != 0 {
          sui_surface_translation(surface, dx, dy)
          translated = true
        }
      }
      guard p.opacity > 0 else { return }
      let relOpacity = inheritedOpacity > 1e-6 ? min(1.0, p.opacity / inheritedOpacity) : p.opacity
      let hasPixelFilter =
        p.blurRadius > 0.1 || abs(p.brightness) > 0.001 || abs(p.contrast - 1.0) > 0.001
      let canFoldOpacity =
        relOpacity < 0.999 && !p.compositingGroup && !hasPixelFilter
        && node.children.isEmpty && node.kind != .gradient && node.kind != .image
        && !((p.background?.opacity ?? 0) > 0 && p.borderWidth > 0 && p.borderColor.opacity > 0)
      let needsLayer =
        hasPixelFilter || (relOpacity < 0.999 && !canFoldOpacity && r.width > 0 && r.height > 0)
      let transformed = p.rotation != 0 || p.scaleX != 1 || p.scaleY != 1
      let canCull = !transformedAncestor && !transformed && !translated && !needsLayer
      let clip = p.clipped && canCull ? clip.intersection(r) : clip
      if canCull && p.clipped && (clip.width <= 0 || clip.height <= 0) { return }
      if canCull && !node.hasOverflow && p.shadows.isEmpty && !node.children.isEmpty {
        let visible = r.intersection(clip)
        if visible.width <= 0 || visible.height <= 0 { return }
      }
      if canCull && node.children.isEmpty && p.shadows.isEmpty
        && (node.kind == .text || node.kind == .image || node.kind == .shape
          || node.kind == .button || node.kind == .textField)
      {
        let margin = max(2, max(p.borderWidth, p.blurRadius * 2))
        let ink = Rect(
          x: r.minX - margin, y: r.minY - margin,
          width: r.width + margin * 2, height: r.height + margin * 2)
        let visible = ink.intersection(clip)
        if visible.width <= 0 || visible.height <= 0 { return }
      }
      if transformed {
        sui_surface_transform(
          surface, r.minX + r.width / 2, r.minY + r.height / 2, p.rotation, p.scaleX, p.scaleY)
      }
      let localAlpha = needsLayer ? 1.0 : relOpacity
      func vector(
        _ path: Path, fill: SwiftUIRuntime.Color = .clear, stroke: SwiftUIRuntime.Color = .clear,
        width: Double = 0, clip: Bool = false
      ) {
        path.commands.withUnsafeBufferPointer { buffer in
          sui_surface_path(
            surface, buffer.baseAddress, Int32(buffer.count), fill.opacity(localAlpha).argb,
            stroke.opacity(localAlpha).argb, width, clip ? 1 : 0)
        }
      }
      let bounds = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
      if !p.shadows.isEmpty {
        let shadowCorner = node.shadowCornerRadius
        for shadow in p.shadows where shadow.color.opacity > 0 {
          if shadow.radius <= 0 {
            sui_surface_shape(
              surface, r.minX + shadow.x, r.minY + shadow.y, r.width, r.height,
              shadowCorner, shadow.color.opacity(relOpacity).argb, 0, 0)
          } else if let (mask, native) = shadowCache.value(
            width: r.width, height: r.height, corner: shadowCorner, radius: shadow.radius,
            scale: sui_surface_scale(surface), create: { NativeShadowMask($0) }) {
            sui_surface_mask(
              surface, native.handle, r.minX + shadow.x - mask.inset, r.minY + shadow.y - mask.inset,
              Double(mask.width) / mask.scale, Double(mask.height) / mask.scale,
              shadow.color.opacity(relOpacity).argb)
          }
        }
      }
      if p.clipped { sui_surface_clip(surface, r.minX, r.minY, r.width, r.height, p.cornerRadius) }
      if let clip = node.clipPathBuilder {
        vector(
          clip(CGRect(origin: .zero, size: bounds.size)).transformed(x: r.minX, y: r.minY),
          clip: true)
      }
      if needsLayer {
        sui_surface_layer_begin(
          surface, r.minX, r.minY, r.width, r.height,
          relOpacity, p.blurRadius, p.brightness, p.contrast)
      }
      if let shape = node.pathBuilder {
        vector(
          shape(bounds), fill: p.background ?? .clear, stroke: p.borderColor, width: p.borderWidth)
      } else if node.kind == .path {
        vector(
          p.path.transformed(x: r.minX, y: r.minY), fill: p.background ?? .clear,
          stroke: p.borderColor, width: p.borderWidth)
      } else if !(node.kind == .button && occludedByPresentation),
        p.background != nil || (p.borderWidth > 0 && p.borderColor.opacity > 0)
      {
        sui_surface_shape(
          surface, r.minX, r.minY, r.width, r.height, p.cornerRadius,
          (p.background ?? .clear).opacity(localAlpha).argb, p.borderColor.opacity(localAlpha).argb,
          p.borderWidth)
      }
      if node.kind == .gradient, let gradient = p.gradient {
        let colors = gradient.colors.map { $0.opacity(localAlpha).argb }
        let startParam = gradient.kind == .radial ? gradient.startRadius : gradient.startAngle
        let endParam = gradient.kind == .radial ? gradient.endRadius : gradient.endAngle
        colors.withUnsafeBufferPointer { colorBuf in
          gradient.locations.withUnsafeBufferPointer { locBuf in
            sui_surface_gradient_ex(
              surface, Int32(gradient.kind.rawValue), r.minX, r.minY, r.width, r.height,
              gradient.start.x, gradient.start.y, gradient.end.x, gradient.end.y,
              startParam, endParam,
              colorBuf.baseAddress,
              locBuf.count == colorBuf.count ? locBuf.baseAddress : nil,
              Int32(colorBuf.count))
          }
        }
      }
      if node.kind == .image {
        let imagePath = p.imagePath
        let isVector =
          imagePath.hasPrefix("sf://")
          || imagePath.hasSuffix(".svg") || imagePath.hasSuffix(".SVG")
          || imagePath.hasSuffix(".pdf") || imagePath.hasSuffix(".PDF")
        if isVector,
          let image = VectorImage.load(imagePath)
        {
          let sx = r.width / image.bounds.width
          let sy = r.height / image.bounds.height
          let scale = min(sx, sy)
          let inkColor = (p.foreground ?? .black).opacity(localAlpha)
          let weightBoost = ((p.font?.weight.value ?? 400) - 400) / 500 * 0.45
          let isTemplate = p.imageTemplate || p.imagePath.hasPrefix("sf://")
          for layer in image.layers {
            let transformed = layer.path.transformed(
              x: r.minX + (r.width - image.bounds.width * scale) / 2 - image.bounds.minX * scale,
              y: r.minY + (r.height - image.bounds.height * scale) / 2 - image.bounds.minY * scale,
              sx: scale, sy: scale)
            let fillColor: SwiftUIRuntime.Color
            let strokeColor: SwiftUIRuntime.Color
            let sw: Double
            if isTemplate {
              fillColor = layer.fill != nil ? inkColor : .clear
              strokeColor = layer.stroke != nil ? inkColor : .clear
              sw = layer.strokeWidth > 0 ? max(1.1, (layer.strokeWidth + weightBoost) * scale) : 0
            } else {
              fillColor = (layer.fill ?? .clear).opacity(localAlpha)
              strokeColor = (layer.stroke ?? .clear).opacity(localAlpha)
              sw = layer.strokeWidth > 0 ? max(1.0, layer.strokeWidth * scale) : 0
            }
            if fillColor.opacity > 0 || sw > 0 {
              vector(transformed, fill: fillColor, stroke: strokeColor, width: sw)
            }
          }
        } else if !p.imagePath.isEmpty {
          sui_surface_image(surface, p.imagePath, r.minX, r.minY, r.width, r.height)
        }
      }
      if node.kind == .text {
        let font = p.font ?? .body
        let text = p.renderedText ?? p.text
        sui_surface_text(
          surface, r.minX, r.minY, r.width, r.height, text, font.family,
          Double(font.size), font.weight.value, p.lineSpacing,
          (p.foreground ?? .black).opacity(localAlpha).argb)
      }
      if node.kind == .button, occludedByPresentation {
        let isDark = environment.colorScheme == .dark
        let btnFill = p.background ?? (
          isDark
            ? SwiftUIRuntime.Color(red: 0.22, green: 0.22, blue: 0.24, opacity: 0.96)
            : SwiftUIRuntime.Color(red: 0.99, green: 0.99, blue: 0.995, opacity: 1.0)
        )
        let btnBorder =
          p.borderWidth > 0 && p.borderColor.opacity > 0
          ? p.borderColor
          : (isDark ? SwiftUIRuntime.Color.white.opacity(0.14) : SwiftUIRuntime.Color.black.opacity(0.16))
        let radius = p.cornerRadius > 0 ? p.cornerRadius : 5.0
        sui_surface_shape(
          surface, r.minX, r.minY, r.width, r.height, radius,
          btnFill.opacity(localAlpha).argb, btnBorder.opacity(localAlpha).argb,
          p.borderWidth > 0 ? p.borderWidth : 1.0)
        let title = label(node)
        if !title.isEmpty {
          let font = p.font ?? .body
          let m = Self.measureText(title, font: font)
          let tx = r.minX + max(0, (r.width - m.width) * 0.5)
          let ty = r.minY + (r.height - m.height) * 0.5
          let defaultFg: SwiftUIRuntime.Color = isDark ? .white : .black
          let fgAlpha = (p.enabled ? 1.0 : 0.45) * localAlpha
          sui_surface_text(
            surface, tx, ty, max(r.width, m.width + 2), max(r.height, m.height + 2),
            title, font.family, Double(font.size), font.weight.value, p.lineSpacing,
            (p.foreground ?? defaultFg).opacity(fgAlpha).argb)
        }
      }
      if node.kind == .textField, occludedByPresentation {
        let isDark = environment.colorScheme == .dark
        let defaultFg: SwiftUIRuntime.Color = isDark ? .white : .black
        let resolvedFg = p.foreground ?? defaultFg
        let isEmpty = p.text.isEmpty
        let rawDisplay = isEmpty
          ? p.placeholder
          : (p.secure ? String(repeating: "•", count: p.text.count) : p.text)
        if !rawDisplay.isEmpty {
          let font = p.font ?? .body
          let m = Self.measureText(rawDisplay, font: font)
          let ty = p.multiline ? r.minY : (r.minY + (r.height - m.height) * 0.5)
          let textColor = isEmpty
            ? resolvedFg.opacity(0.42 * localAlpha)
            : resolvedFg.opacity((p.enabled ? 1.0 : 0.5) * localAlpha)
          sui_surface_clip(surface, r.minX, r.minY, r.width, r.height, 0)
          sui_surface_text(
            surface, r.minX + 1.0, ty, max(0, r.width - 2.0), max(r.height, m.height + 2),
            rawDisplay, font.family, Double(font.size), font.weight.value, p.lineSpacing,
            textColor.argb)
          sui_surface_restore(surface)
        }
      }
      let cacheScroll =
        node.kind == .scroll && canCull && p.clipped && p.cornerRadius == 0
        && node.clipPathBuilder == nil && motions.isEmpty && node.children.first != nil
      if cacheScroll, let child = node.children.first {
        // The bridge verifies translated paint commands, clips and backdrop
        // before copying pixels; opaque/custom layout does not need guessing.
        sui_surface_scroll_begin(
          surface, Int64(node.id.rawValue), 0,
          clip.minX, clip.minY, clip.width, clip.height, child.frame.minX, child.frame.minY)
      }
      let nextInheritedOpacity = needsLayer ? node.props.opacity : inheritedOpacity
      forEachOrderedChild(node) { child in
        draw(
          child, clip: clip,
          transformedAncestor: transformedAncestor || transformed || translated || needsLayer,
          inheritedOpacity: nextInheritedOpacity, allowed: allowed)
      }
      if node.kind == .scroll, p.showsScrollIndicators, let child = node.children.first {
        let color = (p.foreground ?? .gray).opacity(0.3).argb
        if child.frame.height > r.height && r.height > 0 {
          let height = max(20, r.height * r.height / child.frame.height)
          let y = r.minY + p.scrollOffset.y / (child.frame.height - r.height) * (r.height - height)
          sui_surface_shape(surface, r.maxX - 6, y, 4, height, 2, color, 0, 0)
        }
        if child.frame.width > r.width && r.width > 0 {
          let width = max(20, r.width * r.width / child.frame.width)
          let x = r.minX + p.scrollOffset.x / (child.frame.width - r.width) * (r.width - width)
          sui_surface_shape(surface, x, r.maxY - 6, width, 4, 2, color, 0, 0)
        }
      }
      if cacheScroll { sui_surface_scroll_end(surface) }
      if needsLayer { sui_surface_layer_end(surface) }
      if node.clipPathBuilder != nil { sui_surface_restore(surface) }
      if p.clipped { sui_surface_restore(surface) }
      if transformed { sui_surface_restore(surface) }
      if translated { sui_surface_restore(surface) }
    }
    private func forEachOrderedChild(_ node: Element, _ body: (Element) -> Void) {
      let children = node.children
      let count = children.count
      if count == 0 { return }
      if count == 1 {
        body(children[0])
        return
      }
      let behind = node.kind == .layer && node.props.layerBehind
      if children.contains(where: { $0.props.zIndex != 0 }) {
        let base = behind ? Array(children.reversed()) : children
        let sorted = base.enumerated().sorted {
          $0.element.props.zIndex == $1.element.props.zIndex
            ? $0.offset < $1.offset : $0.element.props.zIndex < $1.element.props.zIndex
        }
        for entry in sorted { body(entry.element) }
      } else if behind {
        for i in stride(from: count - 1, through: 0, by: -1) { body(children[i]) }
      } else {
        for i in 0..<count { body(children[i]) }
      }
    }
  }
  extension Rect {
    fileprivate func intersection(_ other: Rect) -> Rect {
      let x = max(minX, other.minX)
      let y = max(minY, other.minY)
      return Rect(
        x: x, y: y, width: max(0, min(maxX, other.maxX) - x),
        height: max(0, min(maxY, other.maxY) - y))
    }
  }
  extension SwiftUIRuntime.Color {
    fileprivate var argb: UInt32 {
      func byte(_ value: Double) -> UInt32 { UInt32(max(0, min(255, (value * 255).rounded()))) }
      return byte(opacity) << 24 | byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
  }
#endif
