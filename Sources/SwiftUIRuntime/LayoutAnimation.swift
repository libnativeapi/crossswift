import Foundation

/// Tracks and interpolates layout-sizing properties across `withAnimation` and
/// `.animation(_:value:)` transactions so sibling panes and native child controls
/// reflow together frame by frame.
final class LayoutAnimator {
  enum Field: Hashable {
    case frameWidth, frameHeight
    case minWidth, minHeight
    case idealWidth, idealHeight
    case maxWidth, maxHeight
    case paddingTop, paddingLeading, paddingBottom, paddingTrailing
    case spacing
  }

  enum ColorField: Hashable {
    case background, foreground, borderColor
  }

  struct ColorMotion {
    let from: Color
    let to: Color
    let animation: Animation
    let start: TimeInterval

    func isActive(at now: TimeInterval) -> Bool {
      animation.duration > 0 && now < start + animation.duration
    }

    func value(at now: TimeInterval) -> Color {
      let p = animation.progress(at: now, start: start)
      return Color(
        red: from.red + (to.red - from.red) * p,
        green: from.green + (to.green - from.green) * p,
        blue: from.blue + (to.blue - from.blue) * p,
        opacity: from.opacity + (to.opacity - from.opacity) * p
      )
    }
  }

  private struct TransitionKey: Hashable {
    let parentID: NodeID
    let childKey: ElementKey
  }

  private struct ActiveInsertion {
    let phase: AnyTransition.Phase
    let animation: Animation
    let start: TimeInterval
  }

  private struct ActiveRemoval {
    let snapshot: Element
    let phase: AnyTransition.Phase
    let animation: Animation
    let start: TimeInterval
    let insertionIndex: Int
    let ghostID: AnyHashable
  }

  struct ScalarMotion {
    let from: Double
    let to: Double
    let animation: Animation
    let start: TimeInterval

    func isActive(at now: TimeInterval) -> Bool {
      animation.duration > 0 && now < start + animation.duration
    }

    func value(at now: TimeInterval, nonNegative: Bool) -> Double {
      let progress = animation.progress(at: now, start: start)
      let interpolated = from + (to - from) * progress
      return nonNegative ? max(0, interpolated) : interpolated
    }
  }

  struct TargetSizing: Equatable {
    var frameWidth: Double?
    var frameHeight: Double?
    var minWidth: Double?
    var minHeight: Double?
    var idealWidth: Double?
    var idealHeight: Double?
    var maxWidth: Double?
    var maxHeight: Double?
    var padding: EdgeInsets
    var spacing: Double
    var background: Color?
    var foreground: Color?
    var borderColor: Color

    init(_ props: NodeProps) {
      frameWidth = props.frameWidth
      frameHeight = props.frameHeight
      minWidth = props.minWidth
      minHeight = props.minHeight
      idealWidth = props.idealWidth
      idealHeight = props.idealHeight
      maxWidth = props.maxWidth
      maxHeight = props.maxHeight
      padding = props.padding
      spacing = props.spacing
      background = props.background
      foreground = props.foreground
      borderColor = props.borderColor
    }
  }

  private struct GeometryScope {
    let previousChildren: [Element]
    let inheritedAnimation: Animation?
    let transactionDisabled: Bool
  }

  private var targets: [NodeID: TargetSizing] = [:]
  private var motions: [NodeID: [Field: ScalarMotion]] = [:]
  private var colorMotions: [NodeID: [ColorField: ColorMotion]] = [:]
  private var activeInsertions: [TransitionKey: ActiveInsertion] = [:]
  private var activeRemovals: [TransitionKey: ActiveRemoval] = [:]
  private var geometryScopes: [NodeID: GeometryScope] = [:]
  private var visitedMotions = Set<NodeID>()
  private var visitedColorMotions = Set<NodeID>()
  private var visitedInsertions = Set<TransitionKey>()
  private var visitedRemovals = Set<TransitionKey>()
  private var passes = 0

  var hasActiveMotions: Bool {
    !motions.isEmpty || !colorMotions.isEmpty || !activeInsertions.isEmpty || !activeRemovals.isEmpty
  }

  func beginPass() {
    visitedMotions.removeAll(keepingCapacity: true)
    visitedColorMotions.removeAll(keepingCapacity: true)
    visitedInsertions.removeAll(keepingCapacity: true)
    visitedRemovals.removeAll(keepingCapacity: true)
    geometryScopes.removeAll(keepingCapacity: true)
  }

  func finishPass(mounted: Element?) {
    if !motions.isEmpty {
      motions = motions.filter { visitedMotions.contains($0.key) && !$0.value.isEmpty }
    }
    if !colorMotions.isEmpty {
      colorMotions = colorMotions.filter { visitedColorMotions.contains($0.key) && !$0.value.isEmpty }
    }
    if !activeInsertions.isEmpty {
      activeInsertions = activeInsertions.filter { visitedInsertions.contains($0.key) }
    }
    if !activeRemovals.isEmpty {
      activeRemovals = activeRemovals.filter { visitedRemovals.contains($0.key) }
    }
    guard let mounted else { return }
    seedMissingTargets(mounted)
    passes += 1
    if passes % 16 == 0 && !hasActiveMotions {
      var live = Set<NodeID>()
      collectIDs(mounted, into: &live)
      targets = targets.filter { live.contains($0.key) }
    }
  }

  func seed(_ root: Element) {
    seedMissingTargets(root)
  }

  private func seedMissingTargets(_ node: Element) {
    if node.id.rawValue != 0 && targets[node.id] == nil {
      targets[node.id] = TargetSizing(node.props)
    } else if node.reusesLayout && node.id.rawValue != 0 && targets[node.id] != nil {
      return
    }
    for child in node.children {
      seedMissingTargets(child)
    }
  }

  private func collectIDs(_ node: Element, into live: inout Set<NodeID>) {
    if node.id.rawValue != 0 { live.insert(node.id) }
    for child in node.children { collectIDs(child, into: &live) }
  }

  func apply(
    to element: inout Element,
    previous: Element?,
    inheritedAnimation: Animation?,
    renderPass: Int,
    now: TimeInterval,
    transactionDisabled: Bool = false
  ) {
    let effectiveAnimation: Animation?
    if transactionDisabled {
      element.props.animation = nil
      element.props.animationDisabled = true
      element.props.animationPass = renderPass
      element.hasScopedAnimation = false
      effectiveAnimation = nil
    } else if element.props.animationPass == renderPass {
      element.hasScopedAnimation = true
      if element.props.animationDisabled {
        effectiveAnimation = nil
      } else {
        effectiveAnimation = element.props.animation ?? inheritedAnimation
      }
    } else {
      element.props.animation = nil
      element.props.animationDisabled = false
      element.props.animationPass = 0
      element.hasScopedAnimation = false
      effectiveAnimation = inheritedAnimation
    }

    let matched = previous.flatMap { $0.kind == element.kind && $0.id.rawValue != 0 ? $0 : nil }
    if let matched {
      let id = matched.id
      if transactionDisabled {
        motions.removeValue(forKey: id)
        colorMotions.removeValue(forKey: id)
      }
      let hasChildTransitions =
        activeInsertions.keys.contains { $0.parentID == id }
        || activeRemovals.keys.contains { $0.parentID == id }
      if element.reusesLayout && !matched.hasLayoutAnimation && !matched.hasScopedAnimation
        && motions[id] == nil && colorMotions[id] == nil && !hasChildTransitions
        && effectiveAnimation == nil
      {
        element.hasLayoutAnimation = false
        element.hasScopedAnimation = false
        return
      }
      element.hasLayoutAnimation = interpolateNode(
        id: id, props: &element.props, animation: effectiveAnimation, now: now)
      if element.kind == .geometry {
        element.id = id
        geometryScopes[id] = GeometryScope(
          previousChildren: matched.children,
          inheritedAnimation: effectiveAnimation,
          transactionDisabled: transactionDisabled)
      }
    } else {
      element.hasLayoutAnimation = false
    }

    guard !element.children.isEmpty || (matched != nil && !matched!.children.isEmpty) else { return }
    if let matched {
      let parentID = matched.id
      // Exclude already-active removal ghosts from oldChildren when computing newly removed items.
      let removalGhostIDs = Set(activeRemovals.values.map(\.ghostID))
      let oldChildren = matched.children.filter { child in
        guard let eid = child.explicitID else { return true }
        return !removalGhostIDs.contains(eid)
      }
      let aligned =
        oldChildren.count == element.children.count
        && !activeInsertions.keys.contains { $0.parentID == parentID }
        && !activeRemovals.keys.contains { $0.parentID == parentID }
        && oldChildren.indices.allSatisfy { idx in
          let oldChild = oldChildren[idx]
          let newChild = element.children[idx]
          let expected: ElementKey =
            newChild.explicitID.map(ElementKey.explicit) ?? .structural(newChild.kind, idx)
          return oldChild.key == expected && oldChild.kind == newChild.kind
        }
      if aligned {
        for index in element.children.indices {
          apply(
            to: &element.children[index],
            previous: oldChildren[index],
            inheritedAnimation: effectiveAnimation,
            renderPass: renderPass,
            now: now,
            transactionDisabled: transactionDisabled)
          if element.children[index].hasLayoutAnimation { element.hasLayoutAnimation = true }
          if element.children[index].hasScopedAnimation { element.hasScopedAnimation = true }
        }
      } else {
        var oldByKey: [ElementKey: (index: Int, element: Element)] = [:]
        oldByKey.reserveCapacity(oldChildren.count)
        for (oldIdx, child) in oldChildren.enumerated() where oldByKey[child.key] == nil {
          oldByKey[child.key] = (oldIdx, child)
        }
        var seenNewKeys = Set<ElementKey>()
        for index in element.children.indices {
          let child = element.children[index]
          let key: ElementKey =
            child.explicitID.map(ElementKey.explicit) ?? .structural(child.kind, index)
          seenNewKeys.insert(key)
          let oldChild = oldByKey[key].flatMap { $0.element.kind == child.kind ? $0.element : nil }
          let tKey = TransitionKey(parentID: parentID, childKey: key)
          if oldChild == nil, !transactionDisabled,
            let transition = child.props.transition,
            !transition.insertion.isIdentity
          {
            let anim = transition.animationOverride ?? effectiveAnimation
            if let anim, anim.duration > 0, !anim.repeats, activeInsertions[tKey] == nil {
              activeInsertions[tKey] = ActiveInsertion(
                phase: transition.insertion,
                animation: anim,
                start: now + max(0, anim.delay)
              )
            }
          }
          // Cancel any in-flight removal for a key that just came back.
          activeRemovals.removeValue(forKey: tKey)

          apply(
            to: &element.children[index],
            previous: oldChild,
            inheritedAnimation: effectiveAnimation,
            renderPass: renderPass,
            now: now,
            transactionDisabled: transactionDisabled)

          if let ins = activeInsertions[tKey] {
            if !transactionDisabled && now < ins.start + ins.animation.duration {
              let progress = ins.animation.progress(at: now, start: ins.start)
              applyTransitionPhase(ins.phase, factor: 1.0 - progress, to: &element.children[index], referenceFrame: element.children[index].frame)
              element.children[index].hasLayoutAnimation = true
              visitedInsertions.insert(tKey)
            } else {
              activeInsertions.removeValue(forKey: tKey)
            }
          }
          if element.children[index].hasLayoutAnimation { element.hasLayoutAnimation = true }
          if element.children[index].hasScopedAnimation { element.hasScopedAnimation = true }
        }

        // Detect newly removed children with transitions.
        if !transactionDisabled {
          for (oldIdx, oldChild) in oldChildren.enumerated() where !seenNewKeys.contains(oldChild.key) {
            let tKey = TransitionKey(parentID: parentID, childKey: oldChild.key)
            if activeRemovals[tKey] == nil,
              let transition = oldChild.props.transition,
              !transition.removal.isIdentity
            {
              let anim = transition.animationOverride ?? effectiveAnimation
              if let anim, anim.duration > 0, !anim.repeats {
                let ghostID = AnyHashable("__crossswift_removal_\(parentID.rawValue)_\(oldChild.id.rawValue)")
                activeRemovals[tKey] = ActiveRemoval(
                  snapshot: oldChild,
                  phase: transition.removal,
                  animation: anim,
                  start: now + max(0, anim.delay),
                  insertionIndex: oldIdx,
                  ghostID: ghostID
                )
              }
            }
          }
        }

        // Re-insert active removal ghosts for this parent.
        let removalsForParent = activeRemovals
          .filter { $0.key.parentID == parentID }
          .sorted { $0.value.insertionIndex < $1.value.insertionIndex }
        for (tKey, rem) in removalsForParent {
          if !transactionDisabled && now < rem.start + rem.animation.duration {
            let progress = rem.animation.progress(at: now, start: rem.start)
            var ghost = rem.snapshot
            ghost.explicitID = rem.ghostID
            ghost.props.hitTesting = false
            ghost.props.enabled = false
            ghost.reusesLayout = false
            applyTransitionPhase(rem.phase, factor: progress, to: &ghost, referenceFrame: rem.snapshot.frame)
            ghost.hasLayoutAnimation = true
            let insertAt = min(rem.insertionIndex, element.children.count)
            element.children.insert(ghost, at: insertAt)
            element.hasLayoutAnimation = true
            visitedRemovals.insert(tKey)
          } else {
            activeRemovals.removeValue(forKey: tKey)
          }
        }
      }
    } else {
      for index in element.children.indices {
        apply(
          to: &element.children[index],
          previous: nil,
          inheritedAnimation: effectiveAnimation,
          renderPass: renderPass,
          now: now,
          transactionDisabled: transactionDisabled)
        if element.children[index].hasScopedAnimation { element.hasScopedAnimation = true }
      }
    }
  }

  private func applyTransitionPhase(
    _ phase: AnyTransition.Phase,
    factor: Double,
    to element: inout Element,
    referenceFrame: Rect
  ) {
    let f = max(0.0, min(1.0, factor))
    if phase.opacity != 1.0 {
      element.props.opacity *= (1.0 + (phase.opacity - 1.0) * f)
    }
    if phase.scale != 1.0 {
      let s = 1.0 + (phase.scale - 1.0) * f
      element.props.scaleX *= s
      element.props.scaleY *= s
    }
    var dx = phase.offsetX * f
    var dy = phase.offsetY * f
    if let edge = phase.edge {
      let w = referenceFrame.width > 1 ? referenceFrame.width : (element.props.frameWidth ?? 200)
      let h = referenceFrame.height > 1 ? referenceFrame.height : (element.props.frameHeight ?? 100)
      switch edge {
      case .leading: dx -= w * f
      case .trailing: dx += w * f
      case .top: dy -= h * f
      case .bottom: dy += h * f
      }
    }
    element.props.offsetX += dx
    element.props.offsetY += dy
  }

  func applyGeometryChild(
    _ child: inout Element,
    geometryID: NodeID,
    fallbackPrevious: Element?,
    renderPass: Int,
    now: TimeInterval
  ) {
    let scope = geometryID.rawValue != 0 ? geometryScopes[geometryID] : nil
    let candidate = scope?.previousChildren.first ?? fallbackPrevious
    let prior = candidate.flatMap { $0.kind == child.kind ? $0 : nil }
    apply(
      to: &child,
      previous: prior,
      inheritedAnimation: scope?.inheritedAnimation,
      renderPass: renderPass,
      now: now,
      transactionDisabled: scope?.transactionDisabled ?? false)
  }

  private func interpolateNode(
    id: NodeID,
    props: inout NodeProps,
    animation: Animation?,
    now: TimeInterval
  ) -> Bool {
    let nextTarget = TargetSizing(props)
    guard let prevTarget = targets[id] else {
      targets[id] = nextTarget
      return false
    }
    targets[id] = nextTarget

    let animatable = (animation != nil && animation!.duration > 0 && !animation!.repeats)
      ? animation : nil
    var nodeMotions = motions[id] ?? [:]

    func stepOptional(
      _ field: Field, previous: Double?, target: Double?, nonNegative: Bool
    ) -> Double? {
      guard let target, target.isFinite else {
        nodeMotions.removeValue(forKey: field)
        return target
      }
      guard let previous, previous.isFinite else {
        nodeMotions.removeValue(forKey: field)
        return target
      }
      return stepScalar(field, previous: previous, target: target, nonNegative: nonNegative)
    }

    func stepScalar(
      _ field: Field, previous: Double, target: Double, nonNegative: Bool
    ) -> Double {
      let existing = nodeMotions[field]
      if target == previous {
        if let existing, existing.isActive(at: now) {
          return existing.value(at: now, nonNegative: nonNegative)
        }
        nodeMotions.removeValue(forKey: field)
        return target
      }
      guard let animatable else {
        nodeMotions.removeValue(forKey: field)
        return target
      }
      let currentShown: Double
      if let existing, existing.isActive(at: now) {
        currentShown = existing.value(at: now, nonNegative: nonNegative)
      } else {
        currentShown = previous
      }
      guard abs(currentShown - target) > 1e-6 else {
        nodeMotions.removeValue(forKey: field)
        return target
      }
      let motion = ScalarMotion(
        from: currentShown,
        to: target,
        animation: animatable,
        start: now + max(0, animatable.delay))
      if motion.isActive(at: now) {
        nodeMotions[field] = motion
        return motion.value(at: now, nonNegative: nonNegative)
      }
      nodeMotions.removeValue(forKey: field)
      return target
    }

    props.frameWidth = stepOptional(
      .frameWidth, previous: prevTarget.frameWidth, target: nextTarget.frameWidth, nonNegative: true)
    props.frameHeight = stepOptional(
      .frameHeight, previous: prevTarget.frameHeight, target: nextTarget.frameHeight,
      nonNegative: true)
    props.minWidth = stepOptional(
      .minWidth, previous: prevTarget.minWidth, target: nextTarget.minWidth, nonNegative: true)
    props.minHeight = stepOptional(
      .minHeight, previous: prevTarget.minHeight, target: nextTarget.minHeight, nonNegative: true)
    props.idealWidth = stepOptional(
      .idealWidth, previous: prevTarget.idealWidth, target: nextTarget.idealWidth, nonNegative: true)
    props.idealHeight = stepOptional(
      .idealHeight, previous: prevTarget.idealHeight, target: nextTarget.idealHeight,
      nonNegative: true)
    props.maxWidth = stepOptional(
      .maxWidth, previous: prevTarget.maxWidth, target: nextTarget.maxWidth, nonNegative: true)
    props.maxHeight = stepOptional(
      .maxHeight, previous: prevTarget.maxHeight, target: nextTarget.maxHeight, nonNegative: true)
    props.padding.top = stepScalar(
      .paddingTop, previous: prevTarget.padding.top, target: nextTarget.padding.top,
      nonNegative: false)
    props.padding.leading = stepScalar(
      .paddingLeading, previous: prevTarget.padding.leading, target: nextTarget.padding.leading,
      nonNegative: false)
    props.padding.bottom = stepScalar(
      .paddingBottom, previous: prevTarget.padding.bottom, target: nextTarget.padding.bottom,
      nonNegative: false)
    props.padding.trailing = stepScalar(
      .paddingTrailing, previous: prevTarget.padding.trailing, target: nextTarget.padding.trailing,
      nonNegative: false)
    props.spacing = stepScalar(
      .spacing, previous: prevTarget.spacing, target: nextTarget.spacing, nonNegative: false)

    // Color interpolation
    var nodeColorMotions = colorMotions[id] ?? [:]
    func stepOptionalColor(
      _ field: ColorField, previous: Color?, target: Color?
    ) -> Color? {
      guard let target else {
        nodeColorMotions.removeValue(forKey: field)
        return nil
      }
      guard let previous else {
        nodeColorMotions.removeValue(forKey: field)
        return target
      }
      let existing = nodeColorMotions[field]
      if target == previous {
        if let existing, existing.isActive(at: now) {
          return existing.value(at: now)
        }
        nodeColorMotions.removeValue(forKey: field)
        return target
      }
      guard let animatable else {
        nodeColorMotions.removeValue(forKey: field)
        return target
      }
      let shown = (existing != nil && existing!.isActive(at: now)) ? existing!.value(at: now) : previous
      let motion = ColorMotion(
        from: shown, to: target, animation: animatable, start: now + max(0, animatable.delay))
      if motion.isActive(at: now) {
        nodeColorMotions[field] = motion
        return motion.value(at: now)
      }
      nodeColorMotions.removeValue(forKey: field)
      return target
    }

    props.background = stepOptionalColor(
      .background, previous: prevTarget.background, target: nextTarget.background)
    props.foreground = stepOptionalColor(
      .foreground, previous: prevTarget.foreground, target: nextTarget.foreground)
    props.borderColor = stepOptionalColor(
      .borderColor, previous: prevTarget.borderColor, target: nextTarget.borderColor) ?? nextTarget.borderColor

    var active = false
    if nodeMotions.isEmpty {
      motions.removeValue(forKey: id)
    } else {
      motions[id] = nodeMotions
      visitedMotions.insert(id)
      active = true
    }
    if nodeColorMotions.isEmpty {
      colorMotions.removeValue(forKey: id)
    } else {
      colorMotions[id] = nodeColorMotions
      visitedColorMotions.insert(id)
      active = true
    }
    return active
  }
}
