/// Owns the mounted tree, state invalidation, layout and backend commands.
///
/// ```swift
/// let backend = FakeBackend()
/// let renderer = Renderer(backend: backend, root: AnyView(MyView()), size: Size(width: 320, height: 200))
/// renderer.mount()
/// // ... tap a button or write state ...
/// renderer.renderIfNeeded()
/// ```
///
/// Rendering is synchronous on the calling thread, which must be the UI thread
/// in a real app.

import Foundation
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

@MainActor @preconcurrency public final class Renderer {
  public let backend: any RenderBackend
  public let layoutEngine: LayoutEngine
  package var usesCustomScrollIndicators = true
  package var clock: () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }

  private let root: AnyView
  private let rootPath = ViewPath()
  private var allocator = NodeIDAllocator()
  private var mounted: Element?
  private var normalized: Element?
  private var hoverActions: [NodeID: (Bool) -> Void] = [:]
  private var continuousHoverActions: [NodeID: (HoverPhase) -> Void] = [:]
  private var lastContinuousHoverPoints: [NodeID: CGPoint] = [:]
  public private(set) var isRendering = false
  public var onDidFinishRenderPasses: (() -> Void)?
  private var needsRender = false
  private var pendingAnimation: Animation?
  private var pendingAnimationExplicit = false
  private var pendingDisablesAnimations = false
  private var renderPass = 0
  private let layoutAnimations = LayoutAnimator()
  private var transactionDepth = 0
  private let evaluations = EvaluationGraph()
  private var mountedGeometryChildren: [Int: Element] = [:]
  private var contentSize: Size
  private var hoveredNodeIDs: [NodeID] = []
  private var focused: NodeID?
  private var dragging: (
    id: NodeID, isHighPriority: Bool, start: CGPoint, origin: CGPoint,
    simultaneousIDs: [NodeID], minDistance: Double, active: Bool
  )?
  private var scrollDrag: (id: NodeID, start: CGPoint, offset: Point, ratio: Double)?
  private var pointerDown: NodeID?
  private var pointerDownHighPriority = false
  private var pointerDownSimultaneous: [NodeID] = []
  private final class PendingLongPress {
    let nodeID: NodeID
    let startPoint: CGPoint
    let startTime: TimeInterval
    let config: Element.LongPressConfig
    var fired = false
    var timerTask: Task<Void, Never>?
    init(nodeID: NodeID, startPoint: CGPoint, startTime: TimeInterval, config: Element.LongPressConfig) {
      self.nodeID = nodeID
      self.startPoint = startPoint
      self.startTime = startTime
      self.config = config
    }
    func cancelTimer() {
      timerTask?.cancel()
      timerTask = nil
    }
  }
  private var pendingLongPress: PendingLongPress?
  private var unpublishedOffsets: [NodeID: Point] = [:]
  private var wheelRemainders: [NodeID: Point] = [:]
  private var activeScrollPhases: Set<NodeID> = []
  private var scrollIdleTasks: [NodeID: Task<Void, Never>] = [:]
  private var hoverPending = false
  private var hoverPoint: CGPoint?
  private var pendingScroll: (id: NodeID, key: StateKey, offset: Point)?
  private var isAttached = false

  /// The last mounted element tree, with frames from the reference layout.
  public private(set) var tree: Element?
  /// The commands produced by the most recent render pass.
  public private(set) var lastCommands: [RenderCommand] = []
  /// Milliseconds spent in each stage of the most recent render transaction.
  public private(set) var lastTimings: [String: Double] = [:]

  public init(
    backend: any RenderBackend,
    root: AnyView,
    size: Size,
    layoutEngine: LayoutEngine = LayoutEngine()
  ) {
    self.backend = backend
    self.root = root
    self.contentSize = size
    self.layoutEngine = layoutEngine
    attachObservers()
  }

  private func attachObservers() {
    isAttached = true
    StateRegistry.shared.observe(rootPath, change: { [weak self] in
      self?.pendingScroll = nil
      self?.evaluations.invalidateAll()
      self?.scheduleRender()
    }, stateChange: { [weak self] key in
      if self?.pendingScroll?.key != key { self?.pendingScroll = nil }
      self?.evaluations.invalidate(key)
      self?.scheduleRender()
    })
    evaluations.onObservableChange = { [weak self] in
      self?.scheduleObservableRender()
    }
    backend.tapHandler = { [weak self] id in
      self?.performTap(id)
    }
    backend.transactionHandler = { [weak self] action in
      guard let self else {
        action()
        return
      }
      self.transactionDepth += 1
      defer { self.finishTransaction() }
      action()
    }
    backend.animationTickHandler = { [weak self] in
      self?.stepAnimations() ?? false
    }
  }

  deinit {
    pendingLongPress?.cancelTimer()
    for task in scrollIdleTasks.values { task.cancel() }
    StateRegistry.shared.removeObserver(rootPath)
  }

  /// Tears down the mounted tree, cancels pending timers and lifecycle tasks,
  /// and detaches `StateRegistry`, `@Observable`, and backend handlers.
  /// Safe to call multiple times; calling `mount()` afterwards re-attaches and remounts.
  public func unmount() {
    isAttached = false
    pendingLongPress?.cancelTimer()
    pendingLongPress = nil
    for task in scrollIdleTasks.values { task.cancel() }
    scrollIdleTasks.removeAll()
    activeScrollPhases.removeAll()
    hoveredNodeIDs.removeAll()
    hoverActions.removeAll()
    continuousHoverActions.removeAll()
    lastContinuousHoverPoints.removeAll()
    focused = nil
    dragging = nil
    scrollDrag = nil
    pointerDown = nil
    pointerDownHighPriority = false
    pointerDownSimultaneous.removeAll()
    pendingScroll = nil
    unpublishedOffsets.removeAll()
    wheelRemainders.removeAll()
    hoverPending = false
    hoverPoint = nil
    needsRender = false
    observableWakeupScheduled = false
    pendingAnimation = nil
    pendingAnimationExplicit = false
    pendingDisablesAnimations = false
    evaluations.reset()
    evaluations.onObservableChange = nil
    backend.tapHandler = nil
    backend.transactionHandler = nil
    backend.animationTickHandler = nil
    if let old = mounted {
      if backend.needsRenderCommands {
        let commands: [RenderCommand] = [.remove(id: old.id)]
        lastCommands = commands
        backend.perform(commands)
      } else {
        lastCommands = []
      }
    }
    mounted = nil
    normalized = nil
    tree = nil
    mountedGeometryChildren.removeAll()
    StateRegistry.shared.removeObserver(rootPath)
  }

  /// Checks whether an active `LongPressGesture` has reached its `minimumDuration`
  /// against the current `clock()` timestamp and fires its completion if so.
  @discardableResult
  public func checkLongPressTimeout() -> Bool {
    guard let lp = pendingLongPress, !lp.fired else { return false }
    guard clock() - lp.startTime >= lp.config.minimumDuration else { return false }
    lp.fired = true
    lp.cancelTimer()
    pointerDown = nil
    pointerDownHighPriority = false
    pointerDownSimultaneous.removeAll()
    transactionDepth += 1
    defer { finishTransaction() }
    lp.config.onEnded()
    lp.config.onPressingChanged?(false)
    return true
  }

  /// Builds and mounts the initial tree.
  public func mount() {
    if !isAttached {
      attachObservers()
    }
    guard mounted == nil else {
      renderIfNeeded()
      return
    }

    isRendering = true
    var mountedTree = buildTree()
    var commands: [RenderCommand]? = backend.needsRenderCommands ? [] : nil
    mountSubtree(
      &mountedTree,
      parent: nil,
      index: 0,
      commands: &commands,
      allocator: &allocator
    )
    mounted = mountedTree
    tree = mountedTree
    LifecycleRegistry.shared.commit(root: rootPath)
    isRendering = false

    if needsRender {
      if let commands, !commands.isEmpty {
        lastCommands = commands
        backend.perform(commands)
      }
      renderIfNeeded()
      if let settled = mounted {
        layoutAnimations.seed(settled)
      }
    } else {
      refreshMountedGeometryChildren(mountedTree)
      layoutAnimations.seed(mountedTree)
      refreshHoverActions()
      lastCommands = commands ?? []
      if let commands { backend.perform(commands) }
      backend.didRender(mountedTree)
      onDidFinishRenderPasses?()
    }
    StateRegistry.shared.finishHotReloadRestore()
  }

  /// Updates the available content area and re-renders if it changed.
  public func resize(to size: Size) {
    resize(to: size, invalidateMeasurements: false)
  }

  /// Measures the ideal / fitting size of the mounted or freshly evaluated root view.
  public func sizeThatFits(_ proposal: ProposedViewSize = ProposedViewSize(width: nil, height: nil)) -> Size {
    if let current = normalized ?? mounted {
      return layoutEngine.measure(current, proposal)
    }
    let savedEnvironment = EnvironmentValues.current
    EnvironmentValues.current = backend.environment
    defer { EnvironmentValues.current = savedEnvironment }
    let raw = normalize(_render(root, path: rootPath))
    return layoutEngine.measure(raw, proposal)
  }

  package func resize(to size: Size, invalidateMeasurements: Bool) {
    if !invalidateMeasurements,
      abs(size.width - contentSize.width) < 1e-4,
      abs(size.height - contentSize.height) < 1e-4
    {
      return
    }
    guard size != contentSize || invalidateMeasurements else { return }
    if invalidateMeasurements {
      layoutEngine.invalidateMeasurements()
      evaluations.invalidateAll()
    } else if let mounted,
      abs(size.height - contentSize.height) > 0.5 || abs(size.width - contentSize.width) > 0.5,
      containsLazyContainer(mounted)
    {
      evaluations.invalidateAll()
    }
    contentSize = size
    pendingScroll = nil
    scheduleRender()
  }

  /// Marks the tree dirty and renders now unless already inside a render pass.
  public func setNeedsRender() {
    guard isAttached else { return }
    pendingScroll = nil
    // Explicit host invalidation may follow changes outside tracked wrappers.
    evaluations.invalidateAll()
    scheduleRender()
  }

  /// Invalidates cached text/layout measurements and view evaluation caches,
  /// then schedules a re-render (e.g. after hot-reloading `.xcstrings` or image assets).
  public func reloadResources() {
    guard isAttached else { return }
    layoutEngine.invalidateMeasurements()
    evaluations.invalidateAll()
    pendingScroll = nil
    scheduleRender()
  }
  private var observableWakeupScheduled = false

  /// `withObservationTracking`'s `onChange` fires on `willSet` before the new value lands.
  /// Mark `needsRender = true` immediately (so synchronous callers calling `renderIfNeeded()`
  /// after the write see it) while deferring automatic rendering until after `willSet` completes.
  private func scheduleObservableRender() {
    guard isAttached else { return }
    pendingScroll = nil
    if AnimationContext.disablesAnimations {
      pendingDisablesAnimations = true
      pendingAnimation = nil
      pendingAnimationExplicit = true
    } else if AnimationContext.isExplicit {
      pendingAnimation = AnimationContext.current
      pendingAnimationExplicit = true
    } else if let animation = AnimationContext.current {
      pendingAnimation = animation
    }
    needsRender = true
    if isRendering || transactionDepth > 0 || observableWakeupScheduled { return }
    observableWakeupScheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.observableWakeupScheduled = false
      guard self.isAttached, self.needsRender, !self.isRendering, self.transactionDepth == 0 else { return }
      self.requestRender()
    }
  }

  private func scheduleRender() {
    guard isAttached else { return }
    if AnimationContext.disablesAnimations {
      pendingDisablesAnimations = true
      pendingAnimation = nil
      pendingAnimationExplicit = true
    } else if AnimationContext.isExplicit {
      pendingAnimation = AnimationContext.current
      pendingAnimationExplicit = true
    } else if let animation = AnimationContext.current {
      pendingAnimation = animation
    }
    needsRender = true
    if isRendering || transactionDepth > 0 { return }
    requestRender()
  }

  /// True while layout-sizing animations are still interpolating across frames.
  public var hasActiveAnimations: Bool { layoutAnimations.hasActiveMotions }

  /// Advances active layout animations to the current `clock()` timestamp.
  /// Returns true if layout animations remain in flight after this frame.
  @discardableResult
  public func stepAnimations() -> Bool {
    guard isAttached, mounted != nil else { return false }
    if needsRender {
      renderIfNeeded()
      return layoutAnimations.hasActiveMotions
    }
    guard layoutAnimations.hasActiveMotions else { return false }
    update()
    backend.didMeasureRender(lastTimings)
    unpublishedOffsets.removeAll(keepingCapacity: true)
    if needsRender { renderIfNeeded() }
    return layoutAnimations.hasActiveMotions
  }
  private func requestRender() {
    guard isAttached else { return }
    if !backend.requestRender({ [weak self] in
      guard let self, self.isAttached, self.needsRender else { return }
      self.renderIfNeeded()
    }) {
      renderIfNeeded()
    }
  }
  private func finishTransaction() {
    if transactionDepth == 1 && hoverPending {
      hoverPending = false
      let pt = hoverPoint
      let chain =
        pt.flatMap { point in tree.map { hitChain($0, point: point, hover: true) } } ?? []
      updateHover(chain, point: pt)
    }
    transactionDepth -= 1
    if transactionDepth == 0 && isAttached && needsRender && !isRendering { requestRender() }
  }

  /// Runs a render pass if one is pending. Coalesces writes made during a pass
  /// into at most eight follow-up passes, then stops to avoid a render loop.
  public func renderIfNeeded() {
    guard isAttached, !isRendering else { return }
    guard mounted != nil else {
      mount()
      return
    }

    var passes = 0
    repeat {
      needsRender = false
      update(allowSkipIntermediatePublish: passes < 7)
      backend.didMeasureRender(lastTimings)
      unpublishedOffsets.removeAll(keepingCapacity: true)
      passes += 1
    } while needsRender && passes < 8
    onDidFinishRenderPasses?()
  }

  /// Invokes the current action registered for a native button.
  public func performTap(_ id: NodeID) {
    transactionDepth += 1
    defer { finishTransaction() }
    var chain: [Element] = []
    guard ancestry(id, in: tree, into: &chain) else { return }
    guard let target = chain.first(where: { $0.action != nil }),
      target.props.enabled, target.props.visible, target.props.hitTesting
    else { return }
    target.action?()
  }

  /// Invokes the boolean change handler for a semantic toggle/switch control.
  public func performBoolInput(_ id: NodeID, value: Bool) {
    transactionDepth += 1
    defer { finishTransaction() }
    guard let node = find(id, in: tree), node.props.enabled, node.props.visible else { return }
    node.semanticBoolAction?(value)
  }

  /// Invokes the floating-point change handler for a semantic slider control.
  public func performDoubleInput(_ id: NodeID, value: Double, ended: Bool) {
    transactionDepth += 1
    defer { finishTransaction() }
    guard let node = find(id, in: tree), node.props.enabled, node.props.visible else { return }
    node.semanticDoubleAction?(value, ended)
  }

  /// Invokes the indexed selection handler for a semantic segmented control, tab bar, or alert action.
  public func performIntInput(_ id: NodeID, value: Int) {
    transactionDepth += 1
    defer { finishTransaction() }
    guard let node = find(id, in: tree), node.props.visible else { return }
    if node.props.semanticControl?.kind == "alert" {
      if value >= 0, value < node.semanticAlertActions.count {
        node.semanticAlertActions[value]()
      }
      node.dismissPresentation?()
      return
    }
    guard node.props.enabled else { return }
    node.semanticIntAction?(value)
  }

  /// Invokes the increment/decrement handler for a semantic stepper control.
  public func performStepInput(_ id: NodeID, delta: Int) {
    transactionDepth += 1
    defer { finishTransaction() }
    guard let node = find(id, in: tree), node.props.enabled, node.props.visible else { return }
    if delta >= 0 {
      node.semanticIncrementAction?()
    } else {
      node.semanticDecrementAction?()
    }
  }

  /// Invokes the navigation back handler for a semantic navigation bar.
  public func performBackInput(_ id: NodeID) {
    transactionDepth += 1
    defer { finishTransaction() }
    guard let node = find(id, in: tree), node.props.visible else { return }
    node.semanticBackAction?()
  }

  /// Dismisses any currently presented modal/alert presentation.
  public func dismissActivePresentation() {
    transactionDepth += 1
    defer { finishTransaction() }
    func findDismiss(_ node: Element?) -> (() -> Void)? {
      guard let node else { return nil }
      if let dismiss = node.dismissPresentation { return dismiss }
      for child in node.children.reversed() {
        if let dismiss = findDismiss(child) { return dismiss }
      }
      return nil
    }
    findDismiss(tree)?()
  }

  public enum Interaction {
    case hover(Bool)
    case focus(Bool)
    case pressed(Bool)
  }
  public func interact(_ id: NodeID, _ interaction: Interaction) {
    if case .hover(let value) = interaction,
      hoveredNodeIDs.contains(id) == value
    {
      return
    }
    transactionDepth += 1
    defer { finishTransaction() }
    var chain: [Element] = []
    guard ancestry(id, in: tree, into: &chain), let node = chain.first else { return }
    switch interaction {
    case .hover(let value):
      if value && node.props.enabled {
        var hoverChain = chain
        if node.kind == .styledButton {
          var inner: [Element] = []
          func collectHoverWrapperChain(_ el: Element) {
            inner.insert(el, at: 0)
            switch el.kind {
            case .styledButton, .frame, .padding, .layer, .presentation:
              if let first = el.children.first { collectHoverWrapperChain(first) }
            case .zStack where el.children.count == 1:
              collectHoverWrapperChain(el.children[0])
            default:
              break
            }
          }
          if let first = node.children.first {
            collectHoverWrapperChain(first)
          }
          hoverChain = inner + chain
        }
        updateHover(hoverChain)
      } else if hoveredNodeIDs.contains(id) {
        updateHover([])
      }
    case .focus(let value):
      if value { focused = id } else if focused == id { focused = nil }
      chain.forEach { $0.focusAction?(value) }
    case .pressed(let value): node.pressedAction?(value && node.props.enabled)
    }
  }
  private func updateHover(_ chain: [Element], point: CGPoint? = nil) {
    let ids = chain.map(\.id)
    if hoveredNodeIDs != ids {
      let previous = Set(hoveredNodeIDs)
      let next = Set(ids)
      let old = hoveredNodeIDs
      hoveredNodeIDs = ids
      for id in old where !next.contains(id) {
        hoverActions.removeValue(forKey: id)?(false)
        lastContinuousHoverPoints.removeValue(forKey: id)
        continuousHoverActions.removeValue(forKey: id)?(.ended)
      }
      for node in chain where !previous.contains(node.id) {
        if let action = node.hoverAction {
          hoverActions[node.id] = action
          action(true)
        }
      }
    }
    if let point {
      for node in chain {
        guard let cont = node.continuousHoverAction else { continue }
        let reported =
          node.continuousHoverGlobal
          ? point
          : CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
        if lastContinuousHoverPoints[node.id] != reported {
          lastContinuousHoverPoints[node.id] = reported
          continuousHoverActions[node.id] = cont
          cont(.active(reported))
        }
      }
    }
  }
  private func find(_ id: NodeID, in node: Element?) -> Element? {
    guard let node else { return nil }
    if node.id == id { return node }
    for child in node.children { if let found = find(id, in: child) { return found } }
    return nil
  }
  private func ancestry(_ id: NodeID, in node: Element?, into result: inout [Element]) -> Bool {
    guard let node else { return false }
    if node.id == id {
      result.append(node)
      return true
    }
    for child in node.children {
      if ancestry(id, in: child, into: &result) {
        result.append(node)
        return true
      }
    }
    return false
  }

  /// Platform-neutral input dispatch. Coordinates are logical points in the root.
  @discardableResult public func input(
    id: NodeID? = nil, event: Int, point: CGPoint = .zero, value: Int = 0,
    modifiers: EventModifiers = [], text: String = "", updatesPressedState: Bool = false
  ) -> Bool {
    transactionDepth += 1
    defer { finishTransaction() }
    if event == 7 {
      if let id { find(id, in: tree)?.textAction?(text) }
      return true
    }
    if event == 1 || event == 10 {
      hoverPending = true
      hoverPoint = event == 10 ? nil : point
    }
    var chain: [Element] = []
    if event != 1 && event != 10 {
      if let id, id.rawValue != 0 {
        _ = ancestry(id, in: tree, into: &chain)
        // Native focus peers represent keyboard focus, not an opaque hit target.
        // Pointer gestures inside a focusable calendar must still reach its cells.
        if [2, 3, 4, 9].contains(event), let container = chain.first,
          container.props.focusable, container.action == nil, container.kind != .textField
        {
          let descendants = hitChain(
            container, point: point, hover: false, event: event, modifiers: modifiers)
          if !descendants.isEmpty { chain = descendants + chain.dropFirst() }
        }
      } else if let root = tree {
        chain = hitChain(root, point: point, hover: false, event: event, modifiers: modifiers)
      }
    }
    if event == 2, usesCustomScrollIndicators,
      let scroll = chain.first(where: { $0.kind == .scroll && $0.props.showsScrollIndicators }),
      let content = scroll.children.first,
      point.x >= scroll.frame.maxX - 12 && content.frame.height > scroll.frame.height
    {
      scrollDrag = (
        scroll.id, point, scroll.props.scrollOffset, content.frame.height / scroll.frame.height
      )
      return true
    }
    if event == 1 || event == 3, let drag = scrollDrag {
      if let node = find(drag.id, in: tree) {
        scroll(
          node,
          to: Point(
            x: drag.offset.x,
            y: drag.offset.y + (point.y - drag.start.y) * drag.ratio))
      }
      if event == 3 { scrollDrag = nil }
      return true
    }
    if (event == 2 || event == 4 || event == 9),
      let hosted = chain.first(where: { $0.kind == .hostedView }),
      let handler = hosted.hostedViewMouseInput,
      handler(event, point, modifiers)
    {
      return true
    }
    if event == 2 {
      pendingLongPress?.cancelTimer()
      pendingLongPress = nil
      if let high = chain.reversed().first(where: { $0.highPriorityAction != nil }) {
        pointerDown = high.id
        pointerDownHighPriority = true
      } else {
        pointerDown = chain.first(where: { $0.action != nil })?.id
        pointerDownHighPriority = false
      }
      pointerDownSimultaneous = chain.filter { !$0.simultaneousActions.isEmpty }.map(\.id)
      if updatesPressedState, let pointerDown { interact(pointerDown, .pressed(true)) }

      if let lpNode = chain.first(where: { $0.longPressAction != nil }),
         let lpConfig = lpNode.longPressAction
      {
        let lp = PendingLongPress(
          nodeID: lpNode.id, startPoint: point, startTime: clock(), config: lpConfig)
        pendingLongPress = lp
        lpConfig.onPressingChanged?(true)
        if lpConfig.minimumDuration <= 0 {
          _ = checkLongPressTimeout()
        } else {
          let delayNs = UInt64(max(1.0, lpConfig.minimumDuration * 1_000_000_000.0))
          lp.timerTask = Task { @MainActor [weak self, weak lp] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard let self, let lp, self.pendingLongPress === lp, !lp.fired else { return }
            _ = self.checkLongPressTimeout()
          }
        }
      }

      let simDrags = chain.filter { !$0.simultaneousDragActions.isEmpty }.map(\.id)
      if let highDrag = chain.reversed().first(where: { $0.highPriorityDragAction != nil }) {
        let md = highDrag.highPriorityDragMinimumDistance
        dragging = (
          highDrag.id, true, point, CGPoint(x: highDrag.frame.minX, y: highDrag.frame.minY),
          simDrags, md, md <= 0
        )
      } else if let node = chain.first(where: { $0.dragAction != nil }) {
        let md = node.dragMinimumDistance
        dragging = (
          node.id, false, point, CGPoint(x: node.frame.minX, y: node.frame.minY),
          simDrags, md, md <= 0
        )
      } else if let firstSim = simDrags.first, let node = find(firstSim, in: tree) {
        dragging = (
          node.id, false, point, CGPoint(x: node.frame.minX, y: node.frame.minY),
          simDrags, 0, true
        )
      }
      if let node = chain.first(where: { $0.props.focusable || $0.focusAction != nil }) {
        focused = node.id
        interact(node.id, .focus(true))
      }
    }
    if event == 1, let lp = pendingLongPress, !lp.fired {
      let moved = hypot(Double(point.x - lp.startPoint.x), Double(point.y - lp.startPoint.y))
      if moved > lp.config.maximumDistance {
        lp.cancelTimer()
        pendingLongPress = nil
        lp.config.onPressingChanged?(false)
      } else if clock() - lp.startTime >= lp.config.minimumDuration {
        _ = checkLongPressTimeout()
      }
    }
    if event == 3, updatesPressedState, let pointerDown {
      interact(pointerDown, .pressed(false))
    }
    if event == 3, let lp = pendingLongPress {
      let alreadyFired = lp.fired
      if !alreadyFired && clock() - lp.startTime >= lp.config.minimumDuration {
        lp.fired = true
        lp.cancelTimer()
        pendingLongPress = nil
        pointerDown = nil
        pointerDownHighPriority = false
        pointerDownSimultaneous.removeAll()
        lp.config.onEnded()
        lp.config.onPressingChanged?(false)
        return true
      }
      lp.cancelTimer()
      pendingLongPress = nil
      if !alreadyFired {
        lp.config.onPressingChanged?(false)
      } else {
        pointerDown = nil
        pointerDownHighPriority = false
        pointerDownSimultaneous.removeAll()
        return true
      }
    }
    if event == 1 || event == 2 || event == 3, var drag = dragging {
      if !drag.active {
        if event == 1 {
          let dist = hypot(Double(point.x - drag.start.x), Double(point.y - drag.start.y))
          if dist >= drag.minDistance {
            drag.active = true
            dragging = drag
            pointerDown = nil
            pointerDownHighPriority = false
            pointerDownSimultaneous.removeAll()
          }
        } else if event == 3 {
          dragging = nil
        }
      }
      if drag.active {
        let location = CGPoint(x: point.x - drag.origin.x, y: point.y - drag.origin.y)
        let start = CGPoint(x: drag.start.x - drag.origin.x, y: drag.start.y - drag.origin.y)
        let dragVal = DragGesture.Value(
          location: location, startLocation: start,
          translation: CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y),
          time: Date())
        if let node = find(drag.id, in: tree) {
          if drag.isHighPriority {
            node.highPriorityDragAction?(dragVal, event == 3)
          } else {
            node.dragAction?(dragVal, event == 3)
          }
        }
        for simID in drag.simultaneousIDs {
          if let simNode = find(simID, in: tree) {
            for handler in simNode.simultaneousDragActions {
              handler(dragVal, event == 3)
            }
          }
        }
        if event == 3 {
          dragging = nil
          pointerDown = nil
          pointerDownHighPriority = false
          pointerDownSimultaneous.removeAll()
        }
        return true
      }
    }
    if event == 3 {
      let simIDs = pointerDownSimultaneous
      let isHigh = pointerDownHighPriority
      defer {
        pointerDown = nil
        pointerDownHighPriority = false
        pointerDownSimultaneous.removeAll()
      }
      var handledTap = false
      if let down = pointerDown, chain.contains(where: { $0.id == down }) {
        if let node = find(down, in: tree) {
          if isHigh, let highAction = node.highPriorityAction {
            highAction()
          } else if let action = node.tapLocationAction {
            action(CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY))
          } else {
            performTap(down)
          }
          handledTap = true
        }
      }
      for simID in simIDs where chain.contains(where: { $0.id == simID }) {
        if let simNode = find(simID, in: tree), simNode.props.enabled, simNode.props.visible {
          for cb in simNode.simultaneousActions {
            cb()
          }
          handledTap = true
        }
      }
      if handledTap { return true }
    }
    if event == 9, let node = chain.first(where: { $0.secondaryAction != nil }) {
      node.secondaryAction?(CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY))
      return true
    }
    if event == 4,
      let node = chain.first(where: {
        $0.doubleTapAction != nil || $0.doubleTapLocationAction != nil
      })
    {
      node.doubleTapAction?()
      node.doubleTapLocationAction?(
        CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY))
      return true
    }
    if event == 5 {
      let scale = max(1.0, Double(backend.environment.displayScale))
      for node in chain where node.scrollAction != nil {
        let current = unpublishedOffsets[node.id] ?? node.props.scrollOffset
        var remainder = wheelRemainders[node.id] ?? .zero
        var offset = current
        if modifiers.contains(.shift) || !node.props.scrollAxes.contains(.vertical) {
          if node.props.scrollAxes.contains(.horizontal) {
            let totalPx = (-Double(value) * 0.4 + remainder.x) * scale
            let snappedPx = totalPx.rounded()
            remainder.x = (totalPx - snappedPx) / scale
            offset.x += snappedPx / scale
          }
        } else if node.props.scrollAxes.contains(.vertical) {
          let totalPx = (-Double(value) * 0.4 + remainder.y) * scale
          let snappedPx = totalPx.rounded()
          remainder.y = (totalPx - snappedPx) / scale
          offset.y += snappedPx / scale
        }
        let insets = node.props.scrollContentInsets
        if let content = node.children.first {
          let minX = -insets.leading
          let maxX = max(minX, content.frame.width + insets.trailing - node.frame.width)
          let minY = -insets.top
          let maxY = max(minY, content.frame.height + insets.bottom - node.frame.height)
          let clampedX = max(minX, min(offset.x, maxX))
          let clampedY = max(minY, min(offset.y, maxY))
          if clampedX != offset.x { remainder.x = 0 }
          if clampedY != offset.y { remainder.y = 0 }
          offset.x = clampedX
          offset.y = clampedY
        }
        wheelRemainders[node.id] = remainder
        if offset != current {
          hoverPending = true
          hoverPoint = backend.pointerLocation(fallback: point)
          scroll(node, to: offset)
          return true
        }
      }
      return chain.contains(where: { $0.scrollAction != nil })
    }
    if event == 6 {
      let special: [Int: KeyEquivalent] = [
        8: .delete, 9: .tab, 13: .return, 27: .escape, 32: .space, 33: .pageUp, 34: .pageDown,
        35: .end, 36: .home, 37: .leftArrow, 38: .upArrow, 39: .rightArrow, 40: .downArrow,
        46: .deleteForward,
      ]
      let characters = !text.isEmpty
        ? text.lowercased()
        : (UnicodeScalar(value).map { String($0).lowercased() } ?? "")
      let key = special[value] ?? KeyEquivalent(characters.first ?? " ")
      let press = KeyPress(key: key, characters: characters, modifiers: modifiers)
      if let focus = (id?.rawValue ?? 0) != 0 ? id : focused {
        chain = []
        _ = ancestry(focus, in: tree, into: &chain)
      }
      for node in chain { if node.keyAction?(press) == .handled { return true } }
      if chain.isEmpty, let tree {
        func dispatchKeyToTree(_ node: Element) -> Bool {
          if node.keyAction?(press) == .handled { return true }
          return node.children.contains(where: dispatchKeyToTree)
        }
        if dispatchKeyToTree(tree) { return true }
      }
      if key == .return, let node = chain.first(where: { $0.submitAction != nil }) {
        node.submitAction?()
        return true
      }
      func shortcut(_ node: Element) -> Bool {
        guard node.props.visible && node.props.enabled && node.props.hitTesting else { return false }
        if node.props.clipped && (node.frame.width <= 0 || node.frame.height <= 0) { return false }
        if let shortcut = node.props.keyboardShortcut, shortcut.key == key,
          shortcut.modifiers == modifiers
            || (shortcut.modifiers == .command && modifiers == .control)
        {
          node.action?()
          return true
        }
        return node.children.contains(where: shortcut)
      }
      if let tree, shortcut(tree) { return true }
    }
    return false
  }
  private func hitChain(
    _ node: Element, point: CGPoint,
    hover: Bool = false, event: Int = 0, modifiers: EventModifiers = []
  ) -> [Element] {
    var result: [Element] = []
    _ = collectHitChain(node, point: point, hover: hover, event: event, modifiers: modifiers, into: &result)
    return result
  }
  private func collectHitChain(
    _ node: Element, point: CGPoint,
    hover: Bool, event: Int = 0, modifiers: EventModifiers = [], into result: inout [Element]
  ) -> Bool {
    guard node.props.visible, node.props.hitTesting, node.props.enabled else { return false }
    let inside =
      point.x >= node.frame.minX && point.x < node.frame.minX + node.frame.width
      && point.y >= node.frame.minY && point.y < node.frame.minY + node.frame.height
    if !inside && (node.props.clipped || !node.hasOverflow) { return false }
    if !node.children.isEmpty {
      var childPoint = point
      if let offset = unpublishedOffsets[node.id] {
        childPoint.x += offset.x - node.props.scrollOffset.x
        childPoint.y += offset.y - node.props.scrollOffset.y
      }
      let behind = node.kind == .layer && node.props.layerBehind
      let count = node.children.count
      if count > 1 && node.children.contains(where: { $0.props.zIndex != 0 }) {
        let base = behind ? Array(node.children.reversed()) : node.children
        let sorted = base.enumerated().sorted {
          $0.element.props.zIndex == $1.element.props.zIndex
            ? $0.offset < $1.offset : $0.element.props.zIndex < $1.element.props.zIndex
        }
        for entry in sorted.reversed() {
          if collectHitChain(entry.element, point: childPoint, hover: hover, event: event, modifiers: modifiers, into: &result) {
            result.append(node)
            return true
          }
        }
      } else if behind {
        for i in 0..<count {
          if collectHitChain(node.children[i], point: childPoint, hover: hover, event: event, modifiers: modifiers, into: &result) {
            result.append(node)
            return true
          }
        }
      } else {
        for i in stride(from: count - 1, through: 0, by: -1) {
          if collectHitChain(node.children[i], point: childPoint, hover: hover, event: event, modifiers: modifiers, into: &result) {
            result.append(node)
            return true
          }
        }
      }
    }
    guard inside else { return false }
    if !hover && node.kind == .hostedView, let hitTest = node.hostedViewHitTest {
      if hitTest(event, point, modifiers) {
        result.append(node)
        return true
      }
      return false
    }
    if event == 5 {
      if node.scrollAction != nil {
        result.append(node)
        return true
      }
      return false
    }
    // Layout-only containers, especially an empty overlay, do not occlude
    // interactive content underneath them.
    let interactive =
      node.action != nil || node.highPriorityAction != nil || !node.simultaneousActions.isEmpty
      || node.dragAction != nil || node.highPriorityDragAction != nil || !node.simultaneousDragActions.isEmpty
      || node.longPressAction != nil || node.scrollAction != nil
      || node.secondaryAction != nil || node.doubleTapAction != nil
      || node.doubleTapLocationAction != nil || node.hoverAction != nil
      || node.continuousHoverAction != nil
      || node.focusAction != nil || node.props.focusable
    let painted: Bool
    switch node.kind {
    case .text, .image, .gradient, .button, .styledButton, .textField: painted = true
    case .shape, .path: painted = (node.props.background?.opacity ?? 0) > 0
    default: painted = (node.props.background?.opacity ?? 0) > 0
    }
    // Decorative canvas ink (a card's stroked overlay, for example) has no
    // native input window. It must not hide the hover target below it.
    if interactive || (!hover && painted) {
      result.append(node)
      return true
    }
    return false
  }

  package func cancelPointer() {
    pointerDown = nil
    pointerDownHighPriority = false
    pointerDownSimultaneous.removeAll()
    pendingLongPress?.cancelTimer()
    pendingLongPress = nil
    dragging = nil
    scrollDrag = nil
  }

  package func endPointerOutside(at point: CGPoint) {
    pointerDown = nil
    input(event: 3, point: point)
  }

  /// Synchronizes the runtime's offset with a platform scroll container.
  package func scroll(id: NodeID, to offset: Point) {
    guard let node = find(id, in: tree), node.kind == .scroll else { return }
    transactionDepth += 1
    defer { finishTransaction() }
    scroll(node, to: offset)
  }

  // MARK: - Internals

  private func scroll(_ node: Element, to requested: Point) {
    var offset = requested
    let insets = node.props.scrollContentInsets
    if let content = node.children.first {
      let minX = -insets.leading
      let maxX = max(minX, content.frame.width + insets.trailing - node.frame.width)
      let minY = -insets.top
      let maxY = max(minY, content.frame.height + insets.bottom - node.frame.height)
      offset.x = max(minX, min(offset.x, maxX))
      offset.y = max(minY, min(offset.y, maxY))
    }
    guard offset != (unpublishedOffsets[node.id] ?? node.props.scrollOffset) else { return }
    unpublishedOffsets[node.id] = offset
    let lazyBucketUnchanged =
      !containsLazyContainer(node)
      || (ScrollViewportContext.quantize(node.props.scrollOffset.x) == ScrollViewportContext.quantize(offset.x)
        && ScrollViewportContext.quantize(node.props.scrollOffset.y) == ScrollViewportContext.quantize(offset.y))
    // Global/named geometry and active presentations require a full pass.
    // Opaque layouts must reproduce exactly translated placement proposals.
    // Note: if any phase or geometry handler below mutates @State other than
    // `key`, StateRegistry's observer clears `pendingScroll` automatically and
    // folds that update into a single render pass instead of two.
    if !needsRender || pendingScroll?.id == node.id, !isRendering, let key = node.scrollStateKey,
      mounted?.hasActivePresentation == false,
      mounted?.hasLayoutAnimation == false,
      lazyBucketUnchanged,
      node.children.allSatisfy({
        layoutEngine.canTranslateScroll(
          $0, dx: node.props.scrollOffset.x - offset.x,
          dy: node.props.scrollOffset.y - offset.y)
      })
    {
      pendingScroll = (node.id, key, offset)
    } else {
      pendingScroll = nil
    }
    if !node.scrollPhaseHandlers.isEmpty {
      if activeScrollPhases.insert(node.id).inserted {
        for phaseHandler in node.scrollPhaseHandlers {
          phaseHandler(.idle, .interacting)
        }
      }
      scrollIdleTasks[node.id]?.cancel()
      let scrollID = node.id
      let handlers = node.scrollPhaseHandlers
      scrollIdleTasks[scrollID] = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(nanoseconds: 160_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }
        self.scrollIdleTasks.removeValue(forKey: scrollID)
        guard self.activeScrollPhases.remove(scrollID) != nil else { return }
        self.transactionDepth += 1
        defer { self.finishTransaction() }
        for h in handlers { h(.interacting, .idle) }
      }
    }
    if !node.scrollGeometryHandlers.isEmpty, let content = node.children.first {
      let geo = ScrollGeometry(
        contentOffset: CGPoint(x: offset.x, y: offset.y),
        contentSize: CGSize(width: content.frame.width, height: content.frame.height),
        contentInsets: insets,
        containerSize: CGSize(width: node.frame.width, height: node.frame.height)
      )
      for h in node.scrollGeometryHandlers { h(geo) }
    }
    node.scrollAction?(offset)
  }

  private func containsLazyContainer(_ element: Element) -> Bool {
    if element.props.isLazyContainer { return true }
    return element.children.contains { containsLazyContainer($0) }
  }

  private func updateScroll() -> Bool {
    guard let pending = pendingScroll, var updated = mounted else { return false }
    pendingScroll = nil
    var commands: [RenderCommand]? = backend.needsRenderCommands ? [] : nil
    let started = Date.timeIntervalSinceReferenceDate
    let fullViewport = updated.frame
    var viewport = fullViewport
    func translate(
      _ node: inout Element, dx: Double, dy: Double,
      origins: [AnyHashable: CGPoint]
    ) {
      node.reusesLayout = false
      node.frame.origin.x += dx
      node.frame.origin.y += dy
      node.customLayoutFrames = node.customLayoutFrames.map { $0.offsetBy(dx: dx, dy: dy) }
      node.layoutContext = origins
      var childOrigins = origins
      if let name = node.props.coordinateSpace {
        childOrigins[name] = CGPoint(x: node.frame.minX, y: node.frame.minY)
      }
      if let snapshot = node.geometrySnapshot {
        snapshot.rect.origin = CGPoint(x: node.frame.minX, y: node.frame.minY)
        snapshot.namedOrigins = childOrigins
      }
      commands?.append(.setFrame(id: node.id, frame: node.frame))
      for i in node.children.indices {
        translate(&node.children[i], dx: dx, dy: dy, origins: childOrigins)
      }
    }
    func move(_ node: inout Element) -> Bool {
      if node.id == pending.id {
        if node.props.clipped, node.props.rotation == 0, node.props.scaleX == 1,
           node.props.scaleY == 1
        {
          viewport = node.frame
        }
        let old = node.props.scrollOffset
        node.props.scrollOffset = pending.offset
        node.reusesLayout = false
        commands?.append(.setProps(id: node.id, props: node.props))
        var origins = node.layoutContext
        if let name = node.props.coordinateSpace {
          origins[name] = CGPoint(x: node.frame.minX, y: node.frame.minY)
        }
        for i in node.children.indices {
          translate(
            &node.children[i], dx: old.x - pending.offset.x,
            dy: old.y - pending.offset.y, origins: origins)
        }
        node.updateOverflow()
        return true
      }
      for i in node.children.indices {
        if move(&node.children[i]) {
          node.reusesLayout = false
          node.updateOverflow()
          if node.props.rotation != 0 || node.props.scaleX != 1 || node.props.scaleY != 1 {
            viewport = fullViewport
          }
          return true
        }
      }
      return false
    }
    guard move(&updated) else { return false }
    pendingAnimation = nil
    isRendering = true
    mounted = updated
    tree = updated
    refreshMountedGeometryChildren(updated)
    lastCommands = commands ?? []
    lastTimings = ["scroll.translate": (Date.timeIntervalSinceReferenceDate - started) * 1000]
    let published = Date.timeIntervalSinceReferenceDate
    if let commands { backend.perform(commands) }
    backend.didScroll(updated, viewport: viewport)
    if updated.hasPreferences {
      LifecycleRegistry.shared.clearPending(root: rootPath)
      let savedActiveRoot = LifecycleRegistry.shared.activeRoot
      LifecycleRegistry.shared.activeRoot = ObjectIdentifier(rootPath)
      _ = resolvePreferences(updated)
      LifecycleRegistry.shared.activeRoot = savedActiveRoot
      LifecycleRegistry.shared.flushEnqueued(root: rootPath)
    }
    lastTimings["backend"] = (Date.timeIntervalSinceReferenceDate - published) * 1000
    isRendering = false
    return true
  }

  private func buildTree() -> Element {
    let savedEnvironment = EnvironmentValues.current
    EnvironmentValues.current = backend.environment
    defer { EnvironmentValues.current = savedEnvironment }
    renderPass += 1
    let currentPass = renderPass
    let savedPass = AnimationContext.renderPass
    AnimationContext.renderPass = currentPass
    defer { AnimationContext.renderPass = savedPass }
    let now = clock()
    lastTimings.removeAll(keepingCapacity: true)
    var start = Date.timeIntervalSinceReferenceDate
    StateRegistry.shared.begin(root: rootPath)
    LifecycleRegistry.shared.begin(root: rootPath)
    let savedActiveRoot = LifecycleRegistry.shared.activeRoot
    LifecycleRegistry.shared.activeRoot = ObjectIdentifier(rootPath)
    defer { LifecycleRegistry.shared.activeRoot = savedActiveRoot }
    var element = evaluations.evaluateRoot { _render(root, path: rootPath) }
    lastTimings["evaluate"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    start = Date.timeIntervalSinceReferenceDate
    element = normalize(element, previous: normalized)
    lastTimings["normalize"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    normalized = element
    start = Date.timeIntervalSinceReferenceDate
    let disablesAnimations = pendingDisablesAnimations || AnimationContext.disablesAnimations
    let explicitTransaction = pendingAnimationExplicit || AnimationContext.isExplicit || disablesAnimations
    let transactionAnimation = disablesAnimations ? nil : (pendingAnimation ?? AnimationContext.current)
    pendingAnimation = nil
    pendingAnimationExplicit = false
    pendingDisablesAnimations = false
    if let animation = transactionAnimation {
      element.props.animation = animation
      element.props.animationDisabled = false
      element.props.animationPass = currentPass
    } else if explicitTransaction {
      element.props.animation = nil
      element.props.animationDisabled = true
      element.props.animationPass = currentPass
    }
    let previousBase = mounted.flatMap {
      $0.hasActivePresentation ? $0.children.first : $0
    }
    resolveEnvironment(&element, previous: previousBase)
    layoutAnimations.beginPass()
    layoutAnimations.apply(
      to: &element,
      previous: previousBase,
      inheritedAnimation: nil,
      renderPass: currentPass,
      now: now,
      transactionDisabled: disablesAnimations)
    lastTimings["environment"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    start = Date.timeIntervalSinceReferenceDate
    layoutEngine.layout(
      root: &element,
      in: contentSize,
      animator: layoutAnimations,
      evaluations: evaluations,
      mountedGeometryChildren: mountedGeometryChildren,
      renderPass: currentPass,
      now: now)
    lastTimings["layout"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    for (key, value) in layoutEngine.lastTimings { lastTimings["layout." + key] = value }
    start = Date.timeIntervalSinceReferenceDate
    element = resolvePresentations(element, in: contentSize)
    assignKeys(&element)
    StateRegistry.shared.end(root: rootPath)
    _ = resolvePreferences(element)
    lastTimings["finalize"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    return element
  }

  private func update(allowSkipIntermediatePublish: Bool = false) {
    if updateScroll() { return }
    guard let old = mounted else {
      mount()
      return
    }

    isRendering = true
    var mountedTree = buildTree()
    var start = Date.timeIntervalSinceReferenceDate
    var commands: [RenderCommand]? = backend.needsRenderCommands ? [] : nil
    if commands == nil && old.hasActivePresentation != mountedTree.hasActivePresentation {
      if mountedTree.hasActivePresentation, !mountedTree.children.isEmpty {
        mountedTree.id = allocator.allocate()
        reconcile(
          old: old, new: &mountedTree.children[0], parent: mountedTree.id, index: 0,
          commands: &commands, allocator: &allocator)
        for i in 1..<mountedTree.children.count {
          mountSubtree(
            &mountedTree.children[i], parent: mountedTree.id, index: i,
            commands: &commands, allocator: &allocator)
        }
      } else if let oldBase = old.children.first {
        reconcile(
          old: oldBase, new: &mountedTree, parent: nil, index: 0,
          commands: &commands, allocator: &allocator)
      } else {
        reconcile(
          old: old, new: &mountedTree, parent: nil, index: 0,
          commands: &commands, allocator: &allocator)
      }
    } else {
      reconcile(
        old: old,
        new: &mountedTree,
        parent: nil,
        index: 0,
        commands: &commands,
        allocator: &allocator
      )
    }
    mounted = mountedTree
    tree = mountedTree
    refreshMountedGeometryChildren(mountedTree)
    layoutAnimations.finishPass(mounted: mountedTree)
    refreshHoverActions()
    lastCommands = commands ?? []
    lastTimings["diff"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    if !backend.needsRenderCommands {
      LifecycleRegistry.shared.commit(root: rootPath)
      if !(allowSkipIntermediatePublish && needsRender) {
        start = Date.timeIntervalSinceReferenceDate
        backend.didRender(mountedTree)
        lastTimings["backend"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
      }
      isRendering = false
      return
    }
    start = Date.timeIntervalSinceReferenceDate
    if let commands { backend.perform(commands) }
    backend.didRender(mountedTree)
    lastTimings["backend"] = (Date.timeIntervalSinceReferenceDate - start) * 1000
    LifecycleRegistry.shared.commit(root: rootPath)
    isRendering = false
  }
  private func refreshMountedGeometryChildren(_ root: Element) {
    mountedGeometryChildren.removeAll(keepingCapacity: true)
    func visit(_ node: Element) {
      if node.kind == .geometry, node.evaluationID != 0, let child = node.children.first {
        mountedGeometryChildren[node.evaluationID] = child
      }
      guard node.hasDynamicLayout else { return }
      for child in node.children { visit(child) }
    }
    visit(root)
  }

  private func refreshHoverActions() {
    guard let target = hoveredNodeIDs.first else { return }
    // The hit path is leaf-first. A single ancestry lookup refreshes callbacks
    // whose captures changed while the pointer stayed in place.
    var chain: [Element] = []
    if ancestry(target, in: tree, into: &chain) {
      for id in hoveredNodeIDs {
        let node = chain.first { $0.id == id } ?? find(id, in: tree)
        hoverActions[id] = node?.hoverAction
        continuousHoverActions[id] = node?.continuousHoverAction
      }
      return
    }
    for id in hoveredNodeIDs {
      let node = find(id, in: tree)
      hoverActions[id] = node?.hoverAction
      continuousHoverActions[id] = node?.continuousHoverAction
    }
  }
}
