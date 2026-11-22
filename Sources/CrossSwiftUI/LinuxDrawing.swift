#if os(Linux)
import CGTK3
import Foundation
import SwiftUIRuntime

final class LinuxDrawing {
  private struct TextKey: Hashable {
    let text: String
    let font: Font
    var spacing = 0.0
    var underline = false
    var tracking = 0.0
  }
  private var measured: [TextKey: SwiftUIRuntime.Size] = [:]
  private var layouts: [TextKey: OpaquePointer] = [:]
  private var fontDescriptions: [Font: OpaquePointer] = [:]
  private let textContext = pango_font_map_create_context(pango_cairo_font_map_get_default())
  private final class NativeShadowMask {
    let surface: OpaquePointer
    init?(_ mask: ShadowMask) {
      guard let surface = cairo_image_surface_create(CAIRO_FORMAT_A8, Int32(mask.width), Int32(mask.height)) else { return nil }
      guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS,
            let data = cairo_image_surface_get_data(surface) else {
        cairo_surface_destroy(surface)
        return nil
      }
      self.surface = surface
      let stride = Int(cairo_image_surface_get_stride(surface))
      for y in 0..<mask.height {
        for x in 0..<mask.width { data[y * stride + x] = mask.alpha[y * mask.width + x] }
      }
      cairo_surface_mark_dirty(surface)
      cairo_surface_set_device_scale(surface, mask.scale, mask.scale)
    }
    deinit { cairo_surface_destroy(surface) }
  }
  private let shadowCache = ShadowCache<NativeShadowMask>()

  deinit {
    for layout in layouts.values { g_object_unref(UnsafeMutableRawPointer(layout)) }
    for desc in fontDescriptions.values { pango_font_description_free(desc) }
    if let textContext { g_object_unref(UnsafeMutableRawPointer(textContext)) }
  }
  struct Motion {
    let from: DrawingValues
    let animation: Animation
    let start: TimeInterval

    func isActive(at now: TimeInterval) -> Bool {
      animation.repeats || now < start + animation.duration
    }

    func interpolated(to target: DrawingValues, now: TimeInterval) -> DrawingValues {
      let progress = animation.progress(at: now, start: start)
      func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * progress }
      return DrawingValues(
        rotation: mix(from.rotation, target.rotation),
        scaleX: mix(from.scaleX, target.scaleX),
        scaleY: mix(from.scaleY, target.scaleY),
        opacity: mix(from.opacity, target.opacity),
        offsetX: mix(from.offsetX, target.offsetX),
        offsetY: mix(from.offsetY, target.offsetY))
    }

    func apply(to props: inout NodeProps, now: TimeInterval) -> CGPoint {
      let current = interpolated(to: DrawingValues(props), now: now)
      props.rotation = current.rotation
      props.scaleX = current.scaleX
      props.scaleY = current.scaleY
      props.opacity = current.opacity
      return CGPoint(x: current.offsetX - props.offsetX,
                     y: current.offsetY - props.offsetY)
    }
  }

  struct DrawingValues: Equatable {
    let rotation, scaleX, scaleY, opacity, offsetX, offsetY: Double

    init(_ props: NodeProps) {
      rotation = props.rotation
      scaleX = props.scaleX
      scaleY = props.scaleY
      opacity = props.opacity
      offsetX = props.offsetX
      offsetY = props.offsetY
    }

    init(
      rotation: Double, scaleX: Double, scaleY: Double,
      opacity: Double, offsetX: Double, offsetY: Double
    ) {
      self.rotation = rotation
      self.scaleX = scaleX
      self.scaleY = scaleY
      self.opacity = opacity
      self.offsetX = offsetX
      self.offsetY = offsetY
    }
  }

  func measure(_ text: String, font: Font) -> SwiftUIRuntime.Size {
    let key = TextKey(text: text, font: font)
    if let size = measured[key] { return size }
    guard let layout = textLayout(key) else { return .zero }
    var width: Int32 = 0
    var height: Int32 = 0
    pango_layout_get_pixel_size(layout, &width, &height)
    let size = SwiftUIRuntime.Size(width: Double(width), height: Double(height))
    if measured.count >= 8192 { measured.removeAll(keepingCapacity: true) }
    measured[key] = size
    return size
  }

  private func fontDescription(for font: Font) -> OpaquePointer? {
    if let cached = fontDescriptions[font] { return cached }
    guard let description = pango_font_description_new() else { return nil }
    let family: String
    switch font.family {
    case "Segoe UI", "-apple-system", "system-ui": family = "Sans"
    case "Consolas": family = "Monospace"
    case "Georgia": family = "Serif"
    default: family = font.family
    }
    pango_font_description_set_family(description, family)
    pango_font_description_set_absolute_size(description, Double(font.size) * Double(PANGO_SCALE))
    pango_font_description_set_weight(description, PangoWeight(rawValue: UInt32(max(100, min(900, font.weight.value)))))
    if fontDescriptions.count >= 256 {
      for desc in fontDescriptions.values { pango_font_description_free(desc) }
      fontDescriptions.removeAll(keepingCapacity: true)
    }
    fontDescriptions[font] = description
    return description
  }

  private func configure(_ layout: OpaquePointer, text: String, font: Font, spacing: Double) {
    if let description = fontDescription(for: font) {
      pango_layout_set_font_description(layout, description)
    }
    pango_layout_set_text(layout, text, -1)
    pango_layout_set_spacing(layout, Int32(clamping: Int(spacing * Double(PANGO_SCALE))))
  }

  func paint(_ node: Element, in context: OpaquePointer, clip: Rect, damage: Rect,
                    motions: [NodeID: Motion], now: TimeInterval, inheritedOpacity: Double = 1,
                    isScaled: Bool = false) {
    var props = node.props
    let translation = motions[node.id]?.apply(to: &props, now: now) ?? .zero
    let frame = node.frame
    guard props.visible, props.opacity > 0, frame.width.isFinite, frame.height.isFinite else { return }
    // The runtime resolves cumulative opacity. Cairo applies the relative
    // opacity of this node to the group that holds its drawing and children.
    let opacity = min(1, props.opacity / inheritedOpacity)
    let area = frame.intersection(clip)
    if props.clipped && area.isEmpty { return }
    if node.children.isEmpty && area.isEmpty && props.shadows.isEmpty { return }

    let transformed = translation != .zero || props.rotation != 0 || props.scaleX != 1 || props.scaleY != 1
    if !transformed && props.shadows.isEmpty && frame.intersection(damage).isEmpty
      && (props.clipped || !node.hasOverflow || node.children.isEmpty) { return }
    let canFoldOpacity =
      opacity < 1 && node.children.isEmpty && node.kind != .gradient && node.kind != .image
      && !((props.background?.opacity ?? 0) > 0 && props.borderWidth > 0 && props.borderColor.opacity > 0)
    let needsGroup = opacity < 1 && !canFoldOpacity
    let tightGroupClip = needsGroup && !props.clipped && !node.hasOverflow
    let usesClip = props.clipped || node.clipPathBuilder != nil || tightGroupClip
    if transformed || usesClip { cairo_save(context) }
    defer { if transformed || usesClip { cairo_restore(context) } }
    if translation != .zero { cairo_translate(context, translation.x, translation.y) }

    if props.rotation != 0 || props.scaleX != 1 || props.scaleY != 1 {
      cairo_translate(context, frame.minX + frame.width / 2, frame.minY + frame.height / 2)
      cairo_rotate(context, props.rotation * .pi / 180)
      cairo_scale(context, props.scaleX, props.scaleY)
      cairo_translate(context, -frame.minX - frame.width / 2, -frame.minY - frame.height / 2)
    }
    if !props.shadows.isEmpty {
      let shadowCorner = node.shadowCornerRadius
      for shadow in props.shadows where shadow.color.opacity > 0 {
        // Shadows precede this node's clip/group but remain inside ancestor
        // groups, so apply this node's relative opacity exactly once here.
        source(context, shadow.color.opacity(opacity))
        if shadow.radius <= 0 {
          let rect = Rect(x: frame.minX + shadow.x, y: frame.minY + shadow.y,
                          width: frame.width, height: frame.height)
          addRoundedRect(rect, radius: shadowCorner, to: context)
          cairo_fill(context)
        } else {
          var sx = 1.0, sy = 1.0
          cairo_surface_get_device_scale(cairo_get_target(context), &sx, &sy)
          if let (mask, native) = shadowCache.value(
            width: frame.width, height: frame.height, corner: shadowCorner,
            radius: shadow.radius, scale: max(sx, sy), create: { NativeShadowMask($0) }) {
            cairo_mask_surface(context, native.surface,
                               frame.minX + shadow.x - mask.inset, frame.minY + shadow.y - mask.inset)
          }
        }
      }
    }
    if props.clipped {
      addRoundedRect(frame, radius: props.cornerRadius, to: context)
      cairo_clip(context)
    } else if tightGroupClip {
      // Bound cairo_push_group's offscreen surface to this node's frame rather
      // than allocating a full-window buffer for every dimmed subtree.
      let margin = max(2.0, props.borderWidth)
      cairo_rectangle(
        context, frame.minX - margin, frame.minY - margin,
        frame.width + margin * 2, frame.height + margin * 2)
      cairo_clip(context)
    }
    if let builder = node.clipPathBuilder {
      let mask = builder(CGRect(origin: .zero, size: frame.cgRect.size))
      add(mask.transformed(x: frame.minX, y: frame.minY), to: context)
      cairo_clip(context)
    }

    if needsGroup { cairo_push_group(context) }
    let leafAlpha = canFoldOpacity ? opacity : 1.0
    if let builder = node.pathBuilder {
      shape(context, builder(frame.cgRect),
            fill: (props.background ?? .clear).opacity(leafAlpha),
            stroke: props.borderColor.opacity(leafAlpha), width: props.borderWidth, dash: props.dash)
    } else if node.kind == .path {
      shape(context, props.path.transformed(x: frame.minX, y: frame.minY),
            fill: (props.background ?? .clear).opacity(leafAlpha),
            stroke: props.borderColor.opacity(leafAlpha), width: props.borderWidth, dash: props.dash)
    } else if props.background != nil || props.borderWidth > 0 {
      addRoundedRect(frame, radius: props.cornerRadius, to: context)
      drawPath(context, fill: (props.background ?? .clear).opacity(leafAlpha),
               stroke: props.borderColor.opacity(leafAlpha), width: props.borderWidth)
    }
    if node.kind == .gradient, let gradient = props.gradient {
      let pattern = cairo_pattern_create_linear(
        frame.minX + gradient.start.x * frame.width, frame.minY + gradient.start.y * frame.height,
        frame.minX + gradient.end.x * frame.width, frame.minY + gradient.end.y * frame.height)
      if let pattern {
        for (index, color) in gradient.colors.enumerated() {
          cairo_pattern_add_color_stop_rgba(pattern, Double(index) / Double(max(1, gradient.colors.count - 1)),
                                           color.red, color.green, color.blue, color.opacity)
        }
        cairo_set_source(context, pattern)
        cairo_rectangle(context, frame.minX, frame.minY, frame.width, frame.height)
        cairo_fill(context)
        cairo_pattern_destroy(pattern)
      }
    }
    let scaled = isScaled || props.rotation != 0 || props.scaleX != 1 || props.scaleY != 1
    if node.kind == .image { image(node, in: context) }
    if node.kind == .text || node.kind == .button {
      text(node, in: context, isScaled: scaled, alpha: leafAlpha)
    }
    let childClip = props.clipped ? area : clip
    let childDamage = transformed ? clip : damage
    Self.forEachOrderedChild(node) { child in
      paint(child, in: context, clip: childClip, damage: childDamage,
            motions: motions, now: now,
            inheritedOpacity: node.props.opacity, isScaled: scaled)
    }
    if node.kind == .scroll, props.showsScrollIndicators, let content = node.children.first {
      let color = (props.foreground ?? .gray).opacity(0.28)
      if content.frame.height > frame.height && frame.height > 0 {
        let height = max(20, frame.height * frame.height / content.frame.height)
        let y = frame.minY + props.scrollOffset.y / (content.frame.height - frame.height) * (frame.height - height)
        addRoundedRect(Rect(x: frame.maxX - 5, y: y, width: 4, height: height), radius: 2, to: context)
        source(context, color)
        cairo_fill(context)
      }
      if content.frame.width > frame.width && frame.width > 0 {
        let width = max(20, frame.width * frame.width / content.frame.width)
        let x = frame.minX + props.scrollOffset.x / (content.frame.width - frame.width) * (frame.width - width)
        addRoundedRect(Rect(x: x, y: frame.maxY - 5, width: width, height: 4), radius: 2, to: context)
        source(context, color)
        cairo_fill(context)
      }
    }
    if needsGroup {
      cairo_pop_group_to_source(context)
      cairo_paint_with_alpha(context, opacity)
    }
  }

  private func textLayout(_ key: TextKey) -> OpaquePointer? {
    if let layout = layouts[key] { return layout }
    guard let textContext, let layout = pango_layout_new(textContext) else { return nil }
    configure(layout, text: key.text, font: key.font, spacing: key.spacing)
    if key.underline || key.tracking != 0, let attributes = pango_attr_list_new() {
      if key.underline { pango_attr_list_insert(attributes, pango_attr_underline_new(PANGO_UNDERLINE_SINGLE)) }
      if key.tracking != 0 {
        pango_attr_list_insert(attributes, pango_attr_letter_spacing_new(Int32(clamping: Int(key.tracking * Double(PANGO_SCALE)))))
      }
      pango_layout_set_attributes(layout, attributes)
      pango_attr_list_unref(attributes)
    }
    if layouts.count >= 4096 {
      for old in layouts.values { g_object_unref(UnsafeMutableRawPointer(old)) }
      layouts.removeAll(keepingCapacity: true)
    }
    layouts[key] = layout
    return layout
  }

  private func text(_ node: Element, in context: OpaquePointer, isScaled: Bool, alpha: Double = 1.0) {
    let props = node.props
    let frame = node.frame
    let key = TextKey(text: props.renderedText ?? props.text, font: props.font ?? .body,
                      spacing: props.lineSpacing, underline: props.underline, tracking: props.tracking)
    guard let layout = textLayout(key) else { return }
    source(context, (props.foreground ?? .black).opacity(alpha))
    if node.kind == .button {
      var width: Int32 = 0, height: Int32 = 0
      pango_layout_get_pixel_size(layout, &width, &height)
      cairo_move_to(context, frame.minX + (frame.width - Double(width)) / 2,
                    frame.minY + (frame.height - Double(height)) / 2)
    } else {
      cairo_move_to(context, frame.minX, frame.minY)
    }
    if isScaled {
      pango_cairo_layout_path(context, layout)
      cairo_fill(context)
    } else {
      pango_cairo_show_layout(context, layout)
    }
  }

  private func image(_ node: Element, in context: OpaquePointer) {
    let frame = node.frame
    guard frame.width > 0, frame.height > 0 else { return }
    let path = node.props.imagePath
    let isVector =
      path.hasPrefix("sf://")
      || path.hasSuffix(".svg") || path.hasSuffix(".SVG")
      || path.hasSuffix(".pdf") || path.hasSuffix(".PDF")
    if isVector,
       let image = VectorImage.load(path),
       image.bounds.width > 0, image.bounds.height > 0 {
      let scale = min(frame.width / image.bounds.width, frame.height / image.bounds.height)
      let x = frame.minX + (frame.width - image.bounds.width * scale) / 2 - image.bounds.minX * scale
      let y = frame.minY + (frame.height - image.bounds.height * scale) / 2 - image.bounds.minY * scale
      let ink = (node.props.foreground ?? .black).opacity(node.props.opacity)
      let isTemplate = node.props.imageTemplate || path.hasPrefix("sf://")
      for layer in image.layers {
        let t = layer.path.transformed(x: x, y: y, sx: scale, sy: scale)
        let fillColor: SwiftUIRuntime.Color
        let strokeColor: SwiftUIRuntime.Color
        let sw: Double
        if isTemplate {
          fillColor = layer.fill != nil ? ink : .clear
          strokeColor = layer.stroke != nil ? ink : .clear
          sw = layer.strokeWidth > 0 ? max(1.1, layer.strokeWidth * scale) : 0
        } else {
          fillColor = (layer.fill ?? .clear).opacity(node.props.opacity)
          strokeColor = (layer.stroke ?? .clear).opacity(node.props.opacity)
          sw = layer.strokeWidth > 0 ? max(1.0, layer.strokeWidth * scale) : 0
        }
        if fillColor.opacity > 0 || sw > 0 {
          shape(context, t, fill: fillColor, stroke: strokeColor, width: sw)
        }
      }
    } else if let pixels = gdk_pixbuf_new_from_file_at_scale(path, Int32(clamping: Int(frame.width)),
                                                             Int32(clamping: Int(frame.height)), 1, nil) {
      defer { g_object_unref(UnsafeMutableRawPointer(pixels)) }
      gdk_cairo_set_source_pixbuf(context, pixels, frame.minX, frame.minY)
      cairo_paint(context)
    }
  }

  private func shape(_ context: OpaquePointer, _ path: Path, fill: Color, stroke: Color,
                            width: Double, dash: [Double] = []) {
    add(path, to: context)
    drawPath(context, fill: fill, stroke: stroke, width: width, dash: dash)
  }

  private func drawPath(_ context: OpaquePointer, fill: Color, stroke: Color, width: Double, dash: [Double] = []) {
    let hasStroke = width > 0 && stroke.opacity > 0
    if fill.opacity > 0 {
      source(context, fill)
      if !hasStroke {
        cairo_fill(context)
        return
      }
      cairo_fill_preserve(context)
    }
    if hasStroke {
      source(context, stroke)
      cairo_set_line_width(context, width)
      dash.withUnsafeBufferPointer { cairo_set_dash(context, $0.baseAddress, Int32($0.count), 0) }
      cairo_stroke(context)
    } else {
      cairo_new_path(context)
    }
  }

  private func addRoundedRect(_ rect: Rect, radius: Double, to context: OpaquePointer) {
    cairo_new_path(context)
    let r = min(radius, rect.width / 2, rect.height / 2)
    if r < 0 {
      add(Path(roundedRect: rect.cgRect, cornerRadius: radius), to: context)
      return
    }
    let x = rect.minX, y = rect.minY, right = rect.maxX, bottom = rect.maxY
    if r == 0 {
      cairo_rectangle(context, x, y, rect.width, rect.height)
      return
    }
    // Cubic approximation of a quarter circle, matching Path.addArc.
    let inset = r * (1 - 4 / 3 * (sqrt(2.0) - 1))
    cairo_move_to(context, x + r, y)
    cairo_line_to(context, right - r, y)
    cairo_curve_to(context, right - inset, y, right, y + inset, right, y + r)
    cairo_line_to(context, right, bottom - r)
    cairo_curve_to(context, right, bottom - inset, right - inset, bottom, right - r, bottom)
    cairo_line_to(context, x + r, bottom)
    cairo_curve_to(context, x + inset, bottom, x, bottom - inset, x, bottom - r)
    cairo_line_to(context, x, y + r)
    cairo_curve_to(context, x, y + inset, x + inset, y, x + r, y)
    cairo_close_path(context)
  }

  private func add(_ path: Path, to context: OpaquePointer) {
    cairo_new_path(context)
    let values = path.commands
    var index = 0
    while index < values.count {
      switch values[index] {
      case 0 where index + 2 < values.count:
        cairo_move_to(context, values[index + 1], values[index + 2])
        index += 3
      case 1 where index + 2 < values.count:
        cairo_line_to(context, values[index + 1], values[index + 2])
        index += 3
      case 2 where index + 6 < values.count:
        cairo_curve_to(context, values[index + 1], values[index + 2], values[index + 3],
                       values[index + 4], values[index + 5], values[index + 6])
        index += 7
      case 3:
        cairo_close_path(context)
        index += 1
      default: return
      }
    }
  }

  private func source(_ context: OpaquePointer, _ color: Color) {
    cairo_set_source_rgba(context, color.red, color.green, color.blue, color.opacity)
  }

  static func forEachOrderedChild(_ node: Element, _ body: (Element) -> Void) {
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

  static func orderedChildren(_ node: Element) -> [Element] {
    let children = node.kind == .layer && node.props.layerBehind ? Array(node.children.reversed()) : node.children
    if !children.contains(where: { $0.props.zIndex != 0 }) { return children }
    return children.enumerated().sorted {
      $0.element.props.zIndex == $1.element.props.zIndex
        ? $0.offset < $1.offset : $0.element.props.zIndex < $1.element.props.zIndex
    }.map(\.element)
  }
}

extension Rect {
  var cgRect: CGRect { CGRect(x: minX, y: minY, width: width, height: height) }
  var isEmpty: Bool { width <= 0 || height <= 0 }

  func intersection(_ other: Rect) -> Rect {
    let x = max(minX, other.minX)
    let y = max(minY, other.minY)
    return Rect(x: x, y: y, width: max(0, min(maxX, other.maxX) - x),
                height: max(0, min(maxY, other.maxY) - y))
  }
}
#endif
