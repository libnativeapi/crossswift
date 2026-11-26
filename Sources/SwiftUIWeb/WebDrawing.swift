import JavaScriptKit
import SwiftUIRuntime

extension WebBackend {
  func makeNode(_ element: Element) -> Node {
    let tag: String
    switch element.kind {
    case .button, .styledButton: tag = "button"
    case .textField: tag = element.props.multiline ? "textarea" : "input"
    default: tag = "div"
    }
    let dom = document.createElement!(tag).object!
    _ = dom.setAttribute!("data-node", String(element.id.rawValue))
    _ = dom.setAttribute!("data-kind", element.kind.description)
    if tag == "button" { dom.type = .string("button") }
    let style = dom.style.object!
    style.position = .string("absolute")
    style.boxSizing = .string("border-box")
    // Keep each sibling subtree in a single stacking context.
    style.isolation = .string("isolate")

    var drawing: JSObject?
    if element.kind == .shape || element.kind == .path || element.kind == .gradient {
      let svg = svgElement("svg")
      _ = svg.setAttribute!("aria-hidden", "true")
      let css = svg.style.object!
      css.position = .string("absolute")
      css.inset = .string("0")
      css.width = .string("100%")
      css.height = .string("100%")
      css.overflow = .string("visible")
      css.pointerEvents = .string("none")
      _ = dom.appendChild!(svg)
      drawing = svg
    }

    // Put layout children in their own DOM container when the node also
    // contains a drawing, or needs a browser-managed scrollable extent.
    var content: JSObject?
    if element.kind == .image {
      let image = document.createElement!("img").object!
      image.draggable = .boolean(false)
      image.style.display = .string("block")
      image.style.width = .string("100%")
      image.style.height = .string("100%")
      _ = dom.appendChild!(image)
      content = image
    } else if drawing != nil || element.kind == .scroll {
      let wrapper = document.createElement!("div").object!
      wrapper.style.position = .string("absolute")
      wrapper.style.inset = .string("0 auto auto 0")
      _ = dom.appendChild!(wrapper)
      content = wrapper
    }
    if element.kind == .scroll {
      _ = dom.setAttribute!("data-scroll", "")
    }
    return Node(dom: dom, drawing: drawing, content: content)
  }

  func updateStyle(_ node: Node, for element: Element) {
    let props = element.props
    let dom = node.dom
    let style = dom.style.object!
    let kind = element.kind
    let isButton = kind == .button || kind == .styledButton
    let isControl = isButton || kind == .textField
    let interactive = props.enabled && props.hitTesting && props.visible
    style.visibility = .string(props.visible ? "visible" : "hidden")
    dom.inert = .boolean(!props.hitTesting || !props.visible)
    style.transform = .string(
      props.rotation == 0 && props.scaleX == 1 && props.scaleY == 1
        ? "" : "rotate(\(props.rotation)deg) scale(\(props.scaleX), \(props.scaleY))")
    var filters: [String] = []
    if props.blurRadius > 0.01 { filters.append("blur(\(px(props.blurRadius)))") }
    if abs(props.brightness) > 0.001 { filters.append("brightness(\(max(0.0, 1.0 + props.brightness)))") }
    if abs(props.contrast - 1.0) > 0.001 { filters.append("contrast(\(max(0.0, props.contrast)))") }
    style.filter = .string(filters.joined(separator: " "))
    if props.gradient?.kind == .angular, let gradient = props.gradient, gradient.colors.count >= 2 {
      let cx = gradient.start.x * 100
      let cy = gradient.start.y * 100
      let span = max(1.0, gradient.endAngle - gradient.startAngle)
      let stops = gradient.colors.enumerated().map { idx, color -> String in
        let loc = idx < gradient.locations.count
          ? gradient.locations[idx]
          : Double(idx) / Double(max(1, gradient.colors.count - 1))
        let deg = loc * span
        return "\(color.css) \(deg)deg"
      }.joined(separator: ", ")
      style.backgroundImage = .string(
        "conic-gradient(from \(gradient.startAngle + 90)deg at \(cx)% \(cy)%, \(stops))")
    } else if !props.imageTemplate {
      style.backgroundImage = .string("")
    }
    style.color = .string(props.foreground?.css ?? "")
    let effectiveCorner =
      props.shadows.isEmpty ? props.cornerRadius : max(props.cornerRadius, element.shadowCornerRadius)
    let radius = max(0, min(effectiveCorner, min(element.frame.width, element.frame.height) / 2))
    style.borderRadius = .string(radius > 0 || props.clipped ? px(radius) : "")
    style.backgroundColor = .string(node.drawing == nil ? props.background?.css ?? "" : "")
    style.boxShadow = .string(
      props.shadows.map { shadow in
        "\(px(shadow.x)) \(px(shadow.y)) \(px(max(0, shadow.radius))) \(shadow.color.css)"
      }.joined(separator: ", "))
    style.overflow = .string(props.clipped ? "clip" : "")
    if props.borderWidth > 0, node.drawing == nil {
      // An inset shadow preserves the content box and the runtime's child coordinates.
      let border = "inset 0 0 0 \(px(props.borderWidth)) \(props.borderColor.css)"
      let shadows = style.boxShadow.string ?? ""
      style.boxShadow = .string(shadows.isEmpty ? border : "\(border), \(shadows)")
    }

    if isControl { dom.disabled = .boolean(!interactive) }
    if !isControl && element.needsNativeFocus {
      dom.tabIndex = .number(interactive ? 0 : -1)
    } else {
      _ = dom.removeAttribute!("tabindex")
    }
    if props.accessibilityHidden {
      _ = dom.setAttribute!("aria-hidden", "true")
    } else {
      _ = dom.removeAttribute!("aria-hidden")
    }
    let label =
      props.accessibilityLabel.isEmpty && kind == .textField
      ? props.placeholder : props.accessibilityLabel
    setAttribute("aria-label", label, on: dom)
    setAttribute("aria-description", props.accessibilityValue, on: dom)
    setAttribute("title", props.help, on: dom)

    if kind == .text || kind == .button || kind == .textField {
      let font = props.font ?? .body
      style.font = .string(font.css)
      style.lineHeight = .string(px(font.lineHeight + props.lineSpacing))
      style.letterSpacing = .string(px(props.tracking))
      style.textDecoration = .string(props.underline ? "underline" : "")
      style.textAlign = .string(
        props.textAlignment == .center
          ? "center"
          : props.textAlignment == .trailing ? "end" : kind == .button ? "center" : "start")
    }

    switch kind {
    case .text:
      let text = props.renderedText ?? props.text
      if dom.textContent.string != text { dom.textContent = .string(text) }
      style.whiteSpace = .string("pre")
    case .button:
      if dom.textContent.string != props.text { dom.textContent = .string(props.text) }
      style.padding = .string("0")
      style.whiteSpace = .string("pre")
    case .styledButton:
      style.padding = .string("0")
      style.border = .string("0")
      if props.background == nil { style.backgroundColor = .string("transparent") }
    case .textField:
      if !props.multiline { dom.type = .string(props.secure ? "password" : "text") }
      dom.placeholder = .string(props.placeholder)
      style.padding = .string(props.plainTextField ? "0" : "0 3px")
      style.border = .string(props.plainTextField ? "0" : "")
      style.outline = .string(props.plainTextField ? "none" : "")
      if props.plainTextField && props.background == nil {
        style.backgroundColor = .string("transparent")
      }
      if props.plainTextField { style.caretColor = .string("currentColor") }
      style.resize = .string("none")
    case .image:
      if let image = node.content {
        image.alt = .string(props.accessibilityLabel)
        image.style.objectFit = .string(props.aspectFit ? "contain" : "fill")
        let isVector =
          props.imagePath.hasPrefix("sf://")
          || props.imagePath.lowercased().hasSuffix(".svg")
          || props.imagePath.lowercased().hasSuffix(".pdf")
        if isVector,
           let vector = VectorImage.load(props.imagePath),
           !vector.layers.isEmpty
        {
          image.style.display = .string("none")
          _ = image.removeAttribute!("src")
          style.maskImage = .string("")
          style.webkitMaskImage = .string("")
          let svg: JSObject
          if let existing = dom.querySelector!("svg[data-sf]").object {
            svg = existing
          } else {
            let created = svgElement("svg")
            _ = created.setAttribute!("data-sf", "1")
            _ = created.setAttribute!("aria-hidden", "true")
            let css = created.style.object!
            css.position = .string("absolute")
            css.inset = .string("0")
            css.width = .string("100%")
            css.height = .string("100%")
            css.display = .string("block")
            css.pointerEvents = .string("none")
            _ = dom.appendChild!(created)
            svg = created
          }
          let b = vector.bounds
          _ = svg.setAttribute!("viewBox", "\(b.minX) \(b.minY) \(b.width) \(b.height)")
          _ = svg.setAttribute!("preserveAspectRatio", props.aspectFit ? "xMidYMid meet" : "none")
          _ = svg.replaceChildren!()
          let isTemplate = props.imagePath.hasPrefix("sf://") || props.imageTemplate
          for layer in vector.layers {
            let d = layer.path.svgData
            guard !d.isEmpty else { continue }
            let pathEl = svgElement("path")
            _ = pathEl.setAttribute!("d", d)
            if let fill = layer.fill {
              _ = pathEl.setAttribute!("fill", isTemplate ? "currentColor" : fill.css)
              _ = pathEl.setAttribute!("fill-rule", "evenodd")
            } else {
              _ = pathEl.setAttribute!("fill", "none")
            }
            if let stroke = layer.stroke, layer.strokeWidth > 0 {
              _ = pathEl.setAttribute!("stroke", isTemplate ? "currentColor" : stroke.css)
              _ = pathEl.setAttribute!("stroke-width", layer.strokeWidth)
              _ = pathEl.setAttribute!("stroke-linecap", "round")
              _ = pathEl.setAttribute!("stroke-linejoin", "round")
            }
            _ = svg.appendChild!(pathEl)
          }
          if !props.accessibilityHidden { _ = dom.setAttribute!("role", "img") }
        } else {
          if let existingSF = dom.querySelector!("svg[data-sf]").object {
            _ = existingSF.remove!()
          }
          if props.imageTemplate {
            image.style.display = .string("none")
            _ = image.removeAttribute!("src")
            let encoded = JSObject.global.JSON.stringify(props.imagePath).string ?? "\"\""
            let maskURL = "url(\(encoded))"
            let maskSize = props.aspectFit ? "contain" : "100% 100%"
            style.maskImage = .string(maskURL)
            style.webkitMaskImage = .string(maskURL)
            style.maskSize = .string(maskSize)
            style.webkitMaskSize = .string(maskSize)
            style.maskPosition = .string("center")
            style.webkitMaskPosition = .string("center")
            style.maskRepeat = .string("no-repeat")
            style.webkitMaskRepeat = .string("no-repeat")
            style.backgroundColor = .string("currentColor")
            if !props.accessibilityHidden { _ = dom.setAttribute!("role", "img") }
          } else {
            style.maskImage = .string("")
            style.webkitMaskImage = .string("")
            image.style.display = .string("block")
            image.style.visibility = .string("")
            setAttribute("src", props.imagePath, on: image)
            _ = dom.removeAttribute!("role")
          }
        }
      }
    case .scroll:
      style.overflowX = .string(props.scrollAxes.contains(.horizontal) ? "auto" : "hidden")
      style.overflowY = .string(props.scrollAxes.contains(.vertical) ? "auto" : "hidden")
      style.scrollbarWidth = .string(props.showsScrollIndicators ? "thin" : "none")
    default: break
    }
  }

  func drawingPath(for node: Element) -> String {
    let rect = CGRect(x: 0, y: 0, width: node.frame.width, height: node.frame.height)
    let path =
      node.pathBuilder?(rect)
      ?? (node.kind == .path
        ? node.props.path : Path(roundedRect: rect, cornerRadius: node.props.cornerRadius))
    return path.svgData
  }

  func draw(_ node: Element, path: String, in svg: JSObject) {
    let props = node.props
    let shape = svgElement("path")
    _ = shape.setAttribute!("d", path)
    _ = shape.setAttribute!("fill", (props.background ?? .clear).css)
    if props.borderWidth > 0 {
      _ = shape.setAttribute!("stroke", props.borderColor.css)
      _ = shape.setAttribute!("stroke-width", props.borderWidth)
      if !props.dash.isEmpty {
        _ = shape.setAttribute!(
          "stroke-dasharray", props.dash.map { String($0) }.joined(separator: " "))
      }
    }

    _ = svg.replaceChildren!(shape)
    if let gradient = props.gradient, !gradient.colors.isEmpty {
      if gradient.colors.count == 1 {
        _ = shape.setAttribute!("fill", gradient.colors.last!.css)
        return
      }
      if gradient.kind == .angular {
        // Rendered via native CSS conic-gradient on the element box.
        _ = shape.setAttribute!("fill", "none")
        return
      }
      let id = "swiftui-gradient-\(node.id.rawValue)"
      let fill: JSObject
      if gradient.kind == .radial {
        fill = svgElement("radialGradient")
        _ = fill.setAttribute!("id", id)
        _ = fill.setAttribute!("gradientUnits", "userSpaceOnUse")
        let cx = gradient.start.x * node.frame.width
        let cy = gradient.start.y * node.frame.height
        let fallbackR = max(1.0, hypot(node.frame.width, node.frame.height) * 0.5)
        let r1 = gradient.endRadius > 0 ? gradient.endRadius : fallbackR
        let r0 = max(0.0, min(gradient.startRadius, r1))
        _ = fill.setAttribute!("cx", cx)
        _ = fill.setAttribute!("cy", cy)
        _ = fill.setAttribute!("fx", cx)
        _ = fill.setAttribute!("fy", cy)
        _ = fill.setAttribute!("r", r1)
        let innerRatio = r1 > 1e-6 ? r0 / r1 : 0.0
        for (index, color) in gradient.colors.enumerated() {
          let stop = svgElement("stop")
          let rawLoc = index < gradient.locations.count
            ? gradient.locations[index]
            : Double(index) / Double(gradient.colors.count - 1)
          let offset = innerRatio + rawLoc * (1.0 - innerRatio)
          _ = stop.setAttribute!("offset", offset)
          _ = stop.setAttribute!("stop-color", color.css)
          _ = fill.appendChild!(stop)
        }
      } else {
        if gradient.start == gradient.end {
          _ = shape.setAttribute!("fill", gradient.colors.last!.css)
          return
        }
        fill = svgElement("linearGradient")
        _ = fill.setAttribute!("id", id)
        _ = fill.setAttribute!("gradientUnits", "userSpaceOnUse")
        _ = fill.setAttribute!("x1", gradient.start.x * node.frame.width)
        _ = fill.setAttribute!("y1", gradient.start.y * node.frame.height)
        _ = fill.setAttribute!("x2", gradient.end.x * node.frame.width)
        _ = fill.setAttribute!("y2", gradient.end.y * node.frame.height)
        for (index, color) in gradient.colors.enumerated() {
          let stop = svgElement("stop")
          let offset = index < gradient.locations.count
            ? gradient.locations[index]
            : Double(index) / Double(gradient.colors.count - 1)
          _ = stop.setAttribute!("offset", offset)
          _ = stop.setAttribute!("stop-color", color.css)
          _ = fill.appendChild!(stop)
        }
      }
      let definitions = svgElement("defs")
      _ = definitions.appendChild!(fill)
      _ = svg.insertBefore!(definitions, shape)
      _ = shape.setAttribute!("fill", "url(#\(id))")
    }
  }

  private func svgElement(_ name: String) -> JSObject {
    document.createElementNS!("http://www.w3.org/2000/svg", name).object!
  }

  private func setAttribute(_ name: String, _ value: String, on node: JSObject) {
    if value.isEmpty {
      _ = node.removeAttribute!(name)
    } else {
      _ = node.setAttribute!(name, value)
    }
  }
}

func px(_ value: Double) -> String { "\(value)px" }

extension Font {
  var css: String {
    let fallback = family == "Consolas" ? "monospace" : family == "Georgia" ? "serif" : "system-ui"
    let quoted = family.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\(weight.value) \(px(size)) \"\(quoted)\", \(fallback)"
  }

  var lineHeight: Double { ceil(size * 1.25) }
}

extension Color {
  fileprivate var css: String { "rgba(\(red * 255), \(green * 255), \(blue * 255), \(opacity))" }
}
