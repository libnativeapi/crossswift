import Foundation

/// Validates a newly evaluated hover transaction against the mounted tree.
/// Opaque measurement, inherited coordinate behavior, preferences, and native
/// semantics use the regular layout path. New event closures stay on new nodes.
struct HoverLayout {
  let scroll: (id: NodeID, offset: Point)?
  var changes: [(id: NodeID, props: NodeProps)] = []
  var scrolled = false

  mutating func retain(_ node: inout Element, from old: Element,
                       dx: Double = 0, dy: Double = 0) -> Bool {
    guard old.kind == node.kind, old.explicitID == node.explicitID,
      old.children.count == node.children.count else { return false }
    if node.reusesLayout, node.id == old.id, dx == 0, dy == 0,
       !node.hasLayoutAnimation, !node.hasScopedAnimation { return true }
    guard isSupported(node), isSupported(old), node.tagValue == old.tagValue,
      node.needsNativeFocus == old.needsNativeFocus,
      (node.clipPathBuilder == nil) == (old.clipPathBuilder == nil),
      node.roundedClipRadius == old.roundedClipRadius,
      node.kind != .scroll || (dx == 0 && dy == 0),
      (node.action == nil) == (old.action == nil),
      (node.focusAction == nil) == (old.focusAction == nil),
      (node.keyAction == nil) == (old.keyAction == nil),
      node.lazyCacheKey == old.lazyCacheKey
    else { return false }
    var compared = node.props
    compared.background = old.props.background
    compared.foreground = old.props.foreground
    compared.borderColor = old.props.borderColor
    compared.renderedText = old.props.renderedText
    compared.animation = old.props.animation
    compared.animationDisabled = old.props.animationDisabled
    compared.animationPass = old.props.animationPass
    var childDX = dx
    var childDY = dy
    if compared.scrollOffset != old.props.scrollOffset {
      // Accept only the already-clamped offset from Renderer.scroll's check
      // for unchanged materialized lazy range and rigid geometry.
      guard node.kind == .scroll, scroll?.id == old.id,
        scroll?.offset == compared.scrollOffset, !scrolled else { return false }
      childDX += old.props.scrollOffset.x - compared.scrollOffset.x
      childDY += old.props.scrollOffset.y - compared.scrollOffset.y
      compared.scrollOffset = old.props.scrollOffset
      scrolled = true
    }
    guard compared == old.props else { return false }
    node.id = old.id
    node.key = old.key
    node.layoutID = old.layoutID
    node.frame = old.frame
    node.frame.origin.x += dx
    node.frame.origin.y += dy
    node.props.renderedText = old.props.renderedText
    node.layoutContext = old.layoutContext
    node.reusesLayout = false
    if node.props != old.props { changes.append((id: old.id, props: node.props)) }
    for i in node.children.indices {
      guard retain(&node.children[i], from: old.children[i], dx: childDX, dy: childDY)
      else { return false }
    }
    node.updateOverflow()
    return true
  }

  private func isSupported(_ node: Element) -> Bool {
    node.kind != .presentation && node.kind != .customLayout && node.kind != .geometry
      && node.kind != .hostedView && node.kind != .textField
      && node.layout == nil && node.geometryBuilder == nil && node.geometrySnapshot == nil
      && node.hostedViewMeasure == nil && node.horizontalGuides.isEmpty && node.verticalGuides.isEmpty
      && node.preferences.isEmpty && node.anchorPreferences.isEmpty && node.preferenceTransforms.isEmpty
      && node.preferenceAction == nil && node.scrollTarget == nil && node.completeScrollTarget == nil
      && node.scrollGeometryHandlers.isEmpty && node.geometryChangeHandlers.isEmpty
      && node.pathBuilder == nil && (node.clipPathBuilder == nil || node.roundedClipRadius != nil)
      && node.props.coordinateSpace == nil && node.tabItemContent == nil && node.tabItemTitle == nil
      && node.tabItemIcon == nil && node.popupPresentations.isEmpty
  }
}
