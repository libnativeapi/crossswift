import Foundation

package protocol HoverPaintHost: AnyObject {
  var hoverTime: Double { get }
  func requestHoverPaint(_ phase: HoverPaintPhase)
}

/// The renderer samples the same transition for the row's ink and its surface.
package final class HoverPaintPhase {
  private(set) var inside = false
  private var origin = 0.0
  private var start = 0.0
  private var animation: Animation?
  func set(_ value: Bool, animation: Animation?, at now: Double) {
    guard value != inside else { return }
    origin = fraction(at: now)
    inside = value
    start = now
    self.animation = animation
  }

  package func isAnimating(at now: Double) -> Bool {
    guard let animation else { return false }
    return animation.repeats || now < start + animation.delay + animation.duration
  }
  package func fraction(at now: Double) -> Double {
    let target = inside ? 1.0 : 0.0
    guard let animation, isAnimating(at: now) else { return target }
    return origin + (target - origin) * animation.progress(at: now, start: start + animation.delay)
  }
}

private struct HoverPaintView<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let normalForeground: Color, activeForeground: Color
  let normalBackground: Color, activeBackground: Color
  let animation: Animation?
  @State private var phase = HoverPaintPhase()
  @State private var revision = 0

  init(_ content: Content, _ normalForeground: Color, _ activeForeground: Color,
       _ normalBackground: Color, _ activeBackground: Color, _ animation: Animation?) {
    self.content = content
    self.normalForeground = normalForeground
    self.activeForeground = activeForeground
    self.normalBackground = normalBackground
    self.activeBackground = activeBackground
    self.animation = animation
  }
  var body: Never { fatalError("HoverPaintView is primitive") }
  private func supportsCanvasPaint(_ node: Element) -> Bool {
    switch node.kind {
    case .button, .styledButton, .textField, .hostedView, .presentation, .geometry, .customLayout:
      return false
    default:
      return node.children.allSatisfy(supportsCanvasPaint)
    }
  }
  func _makeElement(path: ViewPath) -> Element {
    var node = _render(content, path: path.appending(index: 0))
    let environment = EnvironmentValues.current
    let host = environment.hoverPaintHost
    let phase = self.phase
    let previous = node.hoverAction
    if let host, supportsCanvasPaint(node) {
      let scheme = environment.colorScheme
      let animation = environment.accessibilityReduceMotion ? nil : self.animation
      node.props.foreground = normalForeground.resolved(in: scheme)
        .onHover(phase, color: activeForeground.resolved(in: scheme))
      node.props.background = normalBackground.resolved(in: scheme)
        .onHover(phase, color: activeBackground.resolved(in: scheme))
      node.hoverAction = { [weak host] inside in
        previous?(inside)
        guard phase.inside != inside else { return }
        phase.set(inside, animation: animation, at: host?.hoverTime ?? Date.timeIntervalSinceReferenceDate)
        host?.requestHoverPaint(phase)
      }
    } else {
      let _ = revision
      node.props.foreground = phase.inside ? activeForeground : normalForeground
      node.props.background = phase.inside ? activeBackground : normalBackground
      node.hoverAction = { inside in
        previous?(inside)
        guard phase.inside != inside else { return }
        withAnimation(animation) {
          phase.set(inside, animation: nil, at: Date.timeIntervalSinceReferenceDate)
          revision &+= 1
        }
      }
    }
    return node
  }
}

extension View {
  @_spi(WindowsRendering) public func _hoverColors(
    foreground: Color, hoveredForeground: Color, background: Color, hoveredBackground: Color,
    animation: Animation?
  ) -> some View {
    HoverPaintView(self, foreground, hoveredForeground, background, hoveredBackground, animation)
  }
}
