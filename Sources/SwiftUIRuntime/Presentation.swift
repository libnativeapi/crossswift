/// Hoist presentations above scroll clipping while preserving the anchor's layout.

import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public enum PopoverAttachmentAnchor {
  case rect(RectAnchor)
  case point(UnitPoint)
}
public enum RectAnchor { case bounds }
public struct PresentationBackgroundInteraction {
  let enabled: Bool
  public static let enabled = Self(enabled: true)
  public static let disabled = Self(enabled: false)
  public static let automatic = Self.disabled
}
extension View {
  public func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction)
    -> some View
  {
    TransformView(content: self) { $0.props.presentationBackgroundEnabled = interaction.enabled }
  }
}
extension View {
  public func popover<Panel: View>(
    isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge = .top, @ViewBuilder content: () -> Panel
  ) -> some View {
    PopoverView(
      content: self, panel: content(), isPresented: isPresented, edge: arrowEdge,
      drawsPopoverChrome: true)
  }

  /// Internal anchored dropdown presentation for Menu and Picker without popover arrow chrome.
  package func _menuPopover<Panel: View>(
    isPresented: Binding<Bool>, arrowEdge: Edge = .top, @ViewBuilder content: () -> Panel
  ) -> some View {
    PopoverView(
      content: self, panel: content(), isPresented: isPresented, edge: arrowEdge,
      drawsPopoverChrome: false)
  }
}
private struct PopoverView<Content: View, Panel: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content, panel: Panel
  let isPresented: Binding<Bool>
  let edge: Edge
  let drawsPopoverChrome: Bool
  @Environment(\.colorScheme) private var colorScheme
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var children = [_render(content, path: path.appending(index: 0))]
    if isPresented.wrappedValue { children.append(_render(panel, path: path.appending(index: 1))) }
    var element = Element(kind: .presentation, children: children)
    element.presentationEdge = edge
    element.presentationPopoverChrome = drawsPopoverChrome
    element.presentationColorScheme = colorScheme
    element.dismissOnAction = !drawsPopoverChrome
    element.dismissPresentation = { isPresented.wrappedValue = false }
    return element
  }
}

/// Builds a single closed macOS NSPopover bubble path with an integrated smooth arrow beak.
private func makeMacOSPopoverPath(
  bodyRect b: CGRect,
  edge: Edge,
  arrowCenter: Double,
  cornerRadius: Double,
  arrowHeight ah: Double,
  arrowWidth aw: Double
) -> Path {
  let r = min(cornerRadius, min(b.width, b.height) * 0.5)
  let k = r * 0.5522847498
  let halfW = aw * 0.5
  let tipShoulder = aw * 0.14
  let baseCurve = aw * 0.22

  var p = Path()
  p.move(to: CGPoint(x: b.minX + r, y: b.minY))

  // Top edge (left -> right)
  if edge == .top {
    let ax = b.minX + arrowCenter
    p.addLine(to: CGPoint(x: ax - halfW, y: b.minY))
    p.addCurve(
      to: CGPoint(x: ax, y: b.minY - ah),
      control1: CGPoint(x: ax - halfW + baseCurve, y: b.minY),
      control2: CGPoint(x: ax - tipShoulder, y: b.minY - ah)
    )
    p.addCurve(
      to: CGPoint(x: ax + halfW, y: b.minY),
      control1: CGPoint(x: ax + tipShoulder, y: b.minY - ah),
      control2: CGPoint(x: ax + halfW - baseCurve, y: b.minY)
    )
  }
  p.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
  // Top-right corner
  p.addCurve(
    to: CGPoint(x: b.maxX, y: b.minY + r),
    control1: CGPoint(x: b.maxX - r + k, y: b.minY),
    control2: CGPoint(x: b.maxX, y: b.minY + r - k)
  )

  // Right edge (top -> bottom)
  if edge == .trailing {
    let ay = b.minY + arrowCenter
    p.addLine(to: CGPoint(x: b.maxX, y: ay - halfW))
    p.addCurve(
      to: CGPoint(x: b.maxX + ah, y: ay),
      control1: CGPoint(x: b.maxX, y: ay - halfW + baseCurve),
      control2: CGPoint(x: b.maxX + ah, y: ay - tipShoulder)
    )
    p.addCurve(
      to: CGPoint(x: b.maxX, y: ay + halfW),
      control1: CGPoint(x: b.maxX + ah, y: ay + tipShoulder),
      control2: CGPoint(x: b.maxX, y: ay + halfW - baseCurve)
    )
  }
  p.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
  // Bottom-right corner
  p.addCurve(
    to: CGPoint(x: b.maxX - r, y: b.maxY),
    control1: CGPoint(x: b.maxX, y: b.maxY - r + k),
    control2: CGPoint(x: b.maxX - r + k, y: b.maxY)
  )

  // Bottom edge (right -> left)
  if edge == .bottom {
    let ax = b.minX + arrowCenter
    p.addLine(to: CGPoint(x: ax + halfW, y: b.maxY))
    p.addCurve(
      to: CGPoint(x: ax, y: b.maxY + ah),
      control1: CGPoint(x: ax + halfW - baseCurve, y: b.maxY),
      control2: CGPoint(x: ax + tipShoulder, y: b.maxY + ah)
    )
    p.addCurve(
      to: CGPoint(x: ax - halfW, y: b.maxY),
      control1: CGPoint(x: ax - tipShoulder, y: b.maxY + ah),
      control2: CGPoint(x: ax - halfW + baseCurve, y: b.maxY)
    )
  }
  p.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
  // Bottom-left corner
  p.addCurve(
    to: CGPoint(x: b.minX, y: b.maxY - r),
    control1: CGPoint(x: b.minX + r - k, y: b.maxY),
    control2: CGPoint(x: b.minX, y: b.maxY - r + k)
  )

  // Left edge (bottom -> top)
  if edge == .leading {
    let ay = b.minY + arrowCenter
    p.addLine(to: CGPoint(x: b.minX, y: ay + halfW))
    p.addCurve(
      to: CGPoint(x: b.minX - ah, y: ay),
      control1: CGPoint(x: b.minX, y: ay + halfW - baseCurve),
      control2: CGPoint(x: b.minX - ah, y: ay + tipShoulder)
    )
    p.addCurve(
      to: CGPoint(x: b.minX, y: ay - halfW),
      control1: CGPoint(x: b.minX - ah, y: ay - tipShoulder),
      control2: CGPoint(x: b.minX, y: ay - halfW + baseCurve)
    )
  }
  p.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
  // Top-left corner
  p.addCurve(
    to: CGPoint(x: b.minX + r, y: b.minY),
    control1: CGPoint(x: b.minX, y: b.minY + r - k),
    control2: CGPoint(x: b.minX + r - k, y: b.minY)
  )
  p.closeSubpath()
  return p
}

func resolvePresentations(_ root: Element, in size: Size) -> Element {
  var panels: [Element] = []
  var blocksBackground = false
  func collect(_ node: Element) -> Element {
    if !node.hasPresentation { return node }
    var node = node
    node.children = node.children.map(collect)
    if node.kind == .presentation && node.children.count > 1 {
      var panel = node.children.removeLast()
      blocksBackground = blocksBackground || !panel.props.presentationBackgroundEnabled
      if node.dismissOnAction {
        func dismissAfterAction(_ panel: inout Element) {
          if let action = panel.action {
            let dismiss = node.dismissPresentation
            panel.action = {
              action()
              dismiss?()
            }
          }
          for i in panel.children.indices { dismissAfterAction(&panel.children[i]) }
        }
        dismissAfterAction(&panel)
      }
      let natural = LayoutEngine().measuredSize(of: panel)
      // The layout pass has already used the backend's text metrics.
      let width = panel.frame.width > 0 ? panel.frame.width : natural.width
      let height = panel.frame.height > 0 ? panel.frame.height : natural.height
      let anchor = node.frame
      let anchorMidX = anchor.minX + anchor.width * 0.5
      let anchorMidY = anchor.minY + anchor.height * 0.5
      let isPopover = node.presentationPopoverChrome && !node.presentationCentered && node.presentationPoint == nil
      let cornerRadius = 12.0
      let arrowHeight = 10.0
      let arrowWidth = 22.0
      let anchorGap = 2.0
      let margin = isPopover ? 8.0 : 4.0

      var resolvedEdge = node.presentationEdge ?? .top
      var x = anchor.minX
      var y = anchor.maxY + 4

      if isPopover {
        let gap = arrowHeight + anchorGap
        switch resolvedEdge {
        case .top:
          x = anchorMidX - width * 0.5
          y = anchor.maxY + gap
          if y + height + margin > size.height && anchor.minY - gap - height >= margin {
            resolvedEdge = .bottom
            y = anchor.minY - gap - height
          }
        case .bottom:
          x = anchorMidX - width * 0.5
          y = anchor.minY - gap - height
          if y < margin && anchor.maxY + gap + height + margin <= size.height {
            resolvedEdge = .top
            y = anchor.maxY + gap
          }
        case .leading:
          x = anchor.maxX + gap
          y = anchorMidY - height * 0.5
          if x + width + margin > size.width && anchor.minX - gap - width >= margin {
            resolvedEdge = .trailing
            x = anchor.minX - gap - width
          }
        case .trailing:
          x = anchor.minX - gap - width
          y = anchorMidY - height * 0.5
          if x < margin && anchor.maxX + gap + width + margin <= size.width {
            resolvedEdge = .leading
            x = anchor.maxX + gap
          }
        }
        x = max(margin, min(x, size.width - width - margin))
        y = max(margin, min(y, size.height - height - margin))
      } else {
        if resolvedEdge == .bottom { y = anchor.minY - height - 4 }
        if resolvedEdge == .leading {
          x = anchor.maxX + 4
          y = anchor.minY
        }
        if resolvedEdge == .trailing {
          x = anchor.minX - width - 4
          y = anchor.minY
        }
        if let point = node.presentationPoint {
          x = anchor.minX + point.x
          y = anchor.minY + point.y
        }
        if node.presentationCentered {
          x = (size.width - width) / 2
          y = (size.height - height) / 2
        } else if y + height > size.height && anchor.minY > height {
          y = anchor.minY - height - 4
        }
        if y < 0 && anchor.maxY + height < size.height { y = anchor.maxY + 4 }
        x = max(margin, min(x, size.width - width - margin))
        y = max(margin, min(y, size.height - height - margin))
      }

      func translate(_ node: inout Element, dx: Double, dy: Double) {
        node.frame.origin.x += dx
        node.frame.origin.y += dy
        for i in node.children.indices { translate(&node.children[i], dx: dx, dy: dy) }
      }
      translate(&panel, dx: x - panel.frame.minX, dy: y - panel.frame.minY)
      var props = NodeProps()
      if node.presentationCentered { props.background = .black.opacity(0.25) }
      props.fillWidth = true
      props.fillHeight = true
      props.keyboardShortcut = .cancelAction
      let backdrop = Element(
        kind: .shape, props: props, frame: Rect(origin: .zero, size: size),
        action: node.dismissPresentation)
      node.updateOverflow()

      if isPopover {
        let isDark = node.presentationColorScheme == .dark
        let surfaceFill = isDark
          ? Color(red: 0.165, green: 0.168, blue: 0.185, opacity: 0.98)
          : Color(red: 0.992, green: 0.992, blue: 0.996, opacity: 0.98)
        let borderStroke = isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)

        var shadowProps = NodeProps()
        shadowProps.cornerRadius = cornerRadius
        shadowProps.background = surfaceFill
        shadowProps.hitTesting = false
        shadowProps.shadows = [
          Shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 18, x: 0, y: 8),
          Shadow(color: .black.opacity(isDark ? 0.25 : 0.08), radius: 4, x: 0, y: 1),
        ]
        let shadowElement = Element(
          kind: .shape,
          props: shadowProps,
          frame: Rect(x: x, y: y, width: width, height: height)
        )

        let chromeFrame: Rect
        let bodyRectInChrome: CGRect
        let arrowCenter: Double
        switch resolvedEdge {
        case .top:
          chromeFrame = Rect(x: x, y: y - arrowHeight, width: width, height: height + arrowHeight)
          bodyRectInChrome = CGRect(x: 0, y: arrowHeight, width: width, height: height)
          let minC = cornerRadius + arrowWidth * 0.5 + 2
          arrowCenter = max(minC, min(anchorMidX - x, max(minC, width - minC)))
        case .bottom:
          chromeFrame = Rect(x: x, y: y, width: width, height: height + arrowHeight)
          bodyRectInChrome = CGRect(x: 0, y: 0, width: width, height: height)
          let minC = cornerRadius + arrowWidth * 0.5 + 2
          arrowCenter = max(minC, min(anchorMidX - x, max(minC, width - minC)))
        case .leading:
          chromeFrame = Rect(x: x - arrowHeight, y: y, width: width + arrowHeight, height: height)
          bodyRectInChrome = CGRect(x: arrowHeight, y: 0, width: width, height: height)
          let minC = cornerRadius + arrowWidth * 0.5 + 2
          arrowCenter = max(minC, min(anchorMidY - y, max(minC, height - minC)))
        case .trailing:
          chromeFrame = Rect(x: x, y: y, width: width + arrowHeight, height: height)
          bodyRectInChrome = CGRect(x: 0, y: 0, width: width, height: height)
          let minC = cornerRadius + arrowWidth * 0.5 + 2
          arrowCenter = max(minC, min(anchorMidY - y, max(minC, height - minC)))
        }

        var bubbleProps = NodeProps()
        bubbleProps.path = makeMacOSPopoverPath(
          bodyRect: bodyRectInChrome,
          edge: resolvedEdge,
          arrowCenter: arrowCenter,
          cornerRadius: cornerRadius,
          arrowHeight: arrowHeight,
          arrowWidth: arrowWidth
        )
        bubbleProps.background = surfaceFill
        bubbleProps.borderColor = borderStroke
        bubbleProps.borderWidth = 1.0
        let bubbleElement = Element(
          kind: .path,
          props: bubbleProps,
          frame: chromeFrame,
          action: {}
        )
        panels += [backdrop, shadowElement, bubbleElement, panel]
      } else {
        panels += [backdrop, panel]
      }
    }
    node.updateOverflow()
    return node
  }
  var base = collect(root)
  if blocksBackground {
    func block(_ node: inout Element) {
      node.props.hitTesting = false
      for i in node.children.indices { block(&node.children[i]) }
    }
    block(&base)
  }
  if panels.isEmpty { return base }
  var result = Element(
    kind: .zStack, children: [base] + panels, frame: Rect(origin: .zero, size: size))
  result.hasActivePresentation = true
  result.hasLayoutAnimation =
    base.hasLayoutAnimation || panels.contains { $0.hasLayoutAnimation }
  result.hasScopedAnimation =
    base.hasScopedAnimation || panels.contains { $0.hasScopedAnimation }
  result.updateOverflow()
  return result
}
extension View {
  /// Receives a secondary press in the view's local coordinates.
  public func onSecondaryClick(perform action: @escaping (CGPoint) -> Void) -> some View {
    SecondaryClickView(content: self, action: action)
  }

  public func contextMenu<Menu: View>(@ViewBuilder menuItems: () -> Menu) -> some View {
    ContextMenuView(content: self, menu: menuItems())
  }
}
private struct SecondaryClickView<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let action: (CGPoint) -> Void
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var element = _render(content, path: path)
    element.secondaryAction = action
    return element
  }
}
private struct ContextMenuView<Content: View, Menu: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content, menu: Menu
  @State private var presented = false
  @State private var location = CGPoint.zero
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var children = [_render(content, path: path.appending(index: 0))]
    if presented {
      let panel = VStack(alignment: .leading, spacing: 2) {
        menu
          ._menuItemButtonStyle()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .frame(minWidth: 140, maxWidth: 280, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
      .background(
        Color { s in s == .dark ? (0.16, 0.16, 0.18, 0.98) : (0.98, 0.98, 0.99, 0.98) },
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(
            Color { s in s == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.12) },
            lineWidth: 1
          )
      }
      .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
      children.append(_render(panel, path: path.appending(index: 1)))
    }
    var element = Element(kind: .presentation, children: children)
    element.dismissOnAction = true
    element.presentationPoint = location
    element.secondaryAction = {
      location = $0
      presented = true
    }
    element.dismissPresentation = { presented = false }
    return element
  }
}

extension View {
  public func alert<Actions: View, Message: View>(
    _ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions,
    @ViewBuilder message: () -> Message
  ) -> some View {
    AlertPresentation(
      content: self, title: title, isPresented: isPresented,
      actions: actions(), message: message())
  }

  public func alert<Actions: View>(
    _ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions
  ) -> some View {
    AlertPresentation(
      content: self, title: title, isPresented: isPresented,
      actions: actions(), message: EmptyView())
  }
}

private struct AlertPresentation<Content: View, Actions: View, Message: View>: View, _PrimitiveView
{
  typealias Body = Never
  let content: Content
  let title: String
  let isPresented: Binding<Bool>
  let actions: Actions
  let message: Message
  @Environment(\.colorScheme) private var scheme

  var body: Never { fatalError("AlertPresentation is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var children = [_render(content, path: path.appending(index: 0))]
    if isPresented.wrappedValue {
      var panelElement = _renderModalDialogCard(
        title: title,
        titleVisibility: .visible,
        scheme: scheme,
        actions: actions,
        message: message,
        path: path.appending(index: 1)
      )

      // Extract semantic alert metadata for native mobile hosts (Android Material 3 / iOS style)
      let msgTree = _render(message, path: path.appending(index: 2))
      func extractTexts(_ el: Element) -> [String] {
        var out: [String] = []
        if el.kind == .text, !el.props.text.isEmpty { out.append(el.props.text) }
        for c in el.children { out.append(contentsOf: extractTexts(c)) }
        return out
      }
      let messageText = extractTexts(msgTree).joined(separator: "\n")

      let actionsTree = _render(actions, path: path.appending(index: 3))
      var alertItems: [SemanticControl.AlertActionItem] = []
      var alertClosures: [() -> Void] = []
      func collectButtons(_ el: Element, inheritedEnabled: Bool) {
        let effectiveEnabled = inheritedEnabled && (el.props.disabledOverride.map { !$0 } ?? el.props.enabled)
        if el.kind == .button || el.kind == .styledButton {
          let label = el.props.text.isEmpty ? extractTexts(el).joined(separator: " ") : el.props.text
          let role: String
          if el.props.keyboardShortcut == .cancelAction {
            role = "cancel"
          } else if el.props.foreground == Color(hex: 0xb91c1c) || el.props.foreground == .red
            || el.props.semanticControl?.subtitle == "destructive"
          {
            role = "destructive"
          } else {
            role = "default"
          }
          alertItems.append(SemanticControl.AlertActionItem(title: label.isEmpty ? "OK" : label, role: role, enabled: effectiveEnabled))
          alertClosures.append(el.action ?? {})
          return
        }
        for c in el.children { collectButtons(c, inheritedEnabled: effectiveEnabled) }
      }
      collectButtons(actionsTree, inheritedEnabled: true)
      if alertItems.isEmpty {
        alertItems.append(SemanticControl.AlertActionItem(title: "OK", role: "default", enabled: true))
        alertClosures.append({})
      }

      panelElement.props.semanticControl = SemanticControl(
        kind: "alert",
        title: title,
        subtitle: messageText,
        alertActions: alertItems
      )
      panelElement.semanticAlertActions = alertClosures
      panelElement.dismissPresentation = { isPresented.wrappedValue = false }
      children.append(panelElement)
    }
    var element = Element(kind: .presentation, children: children)
    element.presentationCentered = true
    element.dismissOnAction = true
    element.dismissPresentation = { isPresented.wrappedValue = false }
    return element
  }
}
