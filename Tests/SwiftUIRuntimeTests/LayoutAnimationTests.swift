import XCTest

@testable import SwiftUIRuntime

final class LayoutAnimationTests: XCTestCase {
  func testTimingCurveEvaluatesCubicBezierOvershootAndRepeat() {
    let linear = Animation.linear(duration: 0.2)
    XCTAssertEqual(linear.curveValue(at: 0), 0, accuracy: 1e-6)
    XCTAssertEqual(linear.curveValue(at: 0.37), 0.37, accuracy: 1e-6)
    XCTAssertEqual(linear.curveValue(at: 1), 1, accuracy: 1e-6)

    let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.2)
    // A fast-out curve rises well above the diagonal at midpoint.
    XCTAssertGreaterThan(standard.curveValue(at: 0.25), 0.5)
    XCTAssertGreaterThan(standard.curveValue(at: 0.5), 0.8)
    XCTAssertLessThan(standard.curveValue(at: 0.5), 1.0)

    let easeIn = Animation.easeIn(duration: 0.2)
    let easeOut = Animation.easeOut(duration: 0.2)
    XCTAssertLessThan(easeIn.curveValue(at: 0.3), 0.3)
    XCTAssertGreaterThan(easeOut.curveValue(at: 0.3), 0.3)

    let springy = Animation.timingCurve(0.21, 0.9, 0.35, 1.05, duration: 0.26)
    XCTAssertGreaterThan(springy.curveValue(at: 0.7), 1.0)

    let delayed = Animation.easeOut(duration: 0.2).delay(0.05)
    XCTAssertEqual(delayed.progress(at: 10.03, start: 10.05), 0, accuracy: 1e-6)
    XCTAssertGreaterThan(delayed.progress(at: 10.15, start: 10.05), 0.5)
    XCTAssertEqual(delayed.progress(at: 10.25, start: 10.05), 1, accuracy: 1e-6)

    let pingPong = Animation.linear(duration: 0.5).repeatForever(autoreverses: true)
    XCTAssertEqual(pingPong.progress(at: 0.25, start: 0), 0.5, accuracy: 1e-6)
    XCTAssertEqual(pingPong.progress(at: 0.75, start: 0), 0.5, accuracy: 1e-6)
    XCTAssertEqual(pingPong.progress(at: 0.90, start: 0), 0.2, accuracy: 1e-6)
  }

  private struct HoverColorRow: View {
    let index: Int
    @State private var hovered = false

    var body: some View {
      Text("File \(index)")
        .frame(width: 240, height: 28)
        .background(hovered ? Color.blue : Color.red)
        .animation(.linear(duration: 0.4), value: hovered)
        .onHover { hovered = $0 }
    }
  }

  func testScrollingAdvancesHoverColorsWithoutRepeatingLayout() throws {
    StateRegistry.shared.reset()
    final class ColorBackend: RenderBackend {
      var tapHandler: ((NodeID) -> Void)?
      let recorder = FakeBackend()
      var scrollSamples: [Bool] = []
      var lastChanges: [(id: NodeID, props: NodeProps)] = []
      func perform(_ commands: [RenderCommand]) { recorder.perform(commands) }
      func didUpdateColors(_ root: Element, changes: [(id: NodeID, props: NodeProps)], scrolled: Bool) {
        lastChanges = changes
        scrollSamples.append(scrolled)
      }
    }
    var now = 10.0
    let backend = ColorBackend()
    let renderer = Renderer(backend: backend, root: AnyView(ScrollView {
      LazyVStack(spacing: 0) { ForEach(0..<10_000, id: \.self) { HoverColorRow(index: $0) } }
    }), size: Size(width: 240, height: 120))
    renderer.clock = { now }
    renderer.mount()
    let target = try XCTUnwrap(findNode(in: renderer.tree!, text: "File 0"))
    let point = CGPoint(x: target.frame.minX + target.frame.width / 2, y: target.frame.minY + target.frame.height / 2)
    renderer.input(event: 1, point: point)
    XCTAssertTrue(renderer.hasActiveAnimations)
    let scroll = try XCTUnwrap(findNode(in: renderer.tree!, kind: .scroll))
    var fullEvaluations = 0
    var fullLayouts = 0
    var elapsedMS = 0.0
    for step in 1...20 {
      now = 10 + Double(step) / 50
      let start = Date.timeIntervalSinceReferenceDate
      if step.isMultiple(of: 2) {
        renderer.scroll(id: scroll.id, to: Point(x: 0, y: Double(step) / 2))
      } else {
        _ = renderer.stepAnimations()
      }
      elapsedMS += (Date.timeIntervalSinceReferenceDate - start) * 1000
      if renderer.lastTimings["evaluate"] != nil { fullEvaluations += 1 }
      if renderer.lastTimings["layout"] != nil { fullLayouts += 1 }
      let root = try XCTUnwrap(renderer.tree)
      XCTAssertFalse(allNodes(root).contains { $0.props.animation != nil })
      let rowColor = try XCTUnwrap(allNodes(root).first { item in
        item.props.background != nil && item.frame.minY <= point.y && item.frame.maxY >= point.y
      }?.props.background)
      let expected = Color.red.blue + (Color.blue.blue - Color.red.blue) * Double(step) / 20
      XCTAssertEqual(rowColor.blue, expected, accuracy: 0.01)
    }
    print("Hover color scroll: 20 updates, \(fullEvaluations) evaluations, \(fullLayouts) layouts, \(elapsedMS) ms")
    XCTAssertEqual(fullEvaluations, 0)
    XCTAssertEqual(fullLayouts, 0)
    XCTAssertFalse(renderer.hasActiveAnimations)
    XCTAssertFalse(renderer.tree!.hasLayoutAnimation)
    let finalNodes = allNodes(try XCTUnwrap(renderer.tree))
    XCTAssertFalse(backend.lastChanges.isEmpty)
    for change in backend.lastChanges {
      XCTAssertEqual(finalNodes.first(where: { $0.id == change.id })?.props, change.props)
    }
    XCTAssertEqual(backend.scrollSamples.count, 20)
    XCTAssertEqual(backend.scrollSamples.filter { $0 }.count, 10)
    XCTAssertTrue(backend.recorder.commands.contains(where: \.isSetProps))
  }

  private struct ShellFixture: View {
    @State private var listOpen = true
    @State private var asideOpen = true
    @State private var buttonLit = false
    let motion = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.2)

    var body: some View {
      HStack(spacing: 0) {
        Text("SidebarColumn")
          .frame(width: 240, height: 400)
          .frame(width: listOpen ? 240 : 0, alignment: .leading)
          .clipped()
          .allowsHitTesting(listOpen)

        VStack(spacing: 0) {
          HStack(spacing: 8) {
            Button("ToggleList") { withAnimation(motion) { listOpen.toggle() } }
            Button("ToggleAside") { withAnimation(motion) { asideOpen.toggle() } }
            Button("HoverState") { buttonLit.toggle() }
              .opacity(buttonLit ? 0.8 : 1.0)
          }
          GeometryReader { proxy in
            Text("StageWidth:\(Int(proxy.size.width.rounded()))")
              .frame(width: proxy.size.width, height: 100)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Text("AsideColumn")
          .frame(width: 200, height: 400)
          .frame(width: asideOpen ? 200 : 0, alignment: .trailing)
          .clipped()
          .allowsHitTesting(asideOpen)
      }
    }
  }

  func testSidebarAndAsideCollapseExpandReflowMainPaneSmoothly() throws {
    StateRegistry.shared.reset()
    var now = 100.0
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(ShellFixture()),
      size: Size(width: 900, height: 400))
    renderer.clock = { now }
    renderer.mount()

    func metrics() throws -> (
      sidebarClip: Rect, sidebarInner: Rect, stage: Rect, asideClip: Rect, asideInner: Rect
    ) {
      let root = try XCTUnwrap(renderer.tree)
      let sidebarClip = root.children[0].frame
      let sidebarInner = root.children[0].children[0].frame
      let stage = root.children[1].frame
      let asideClip = root.children[2].frame
      let asideInner = root.children[2].children[0].frame
      return (sidebarClip, sidebarInner, stage, asideClip, asideInner)
    }

    let initial = try metrics()
    XCTAssertEqual(initial.sidebarClip.width, 240, accuracy: 0.01)
    XCTAssertEqual(initial.stage.minX, 240, accuracy: 0.01)
    XCTAssertEqual(initial.stage.width, 460, accuracy: 0.01)
    XCTAssertEqual(initial.asideClip.minX, 700, accuracy: 0.01)
    XCTAssertEqual(initial.asideClip.width, 200, accuracy: 0.01)

    let toggleList = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "ToggleList"))
    renderer.performTap(toggleList.id)
    XCTAssertTrue(renderer.hasActiveAnimations)
    XCTAssertTrue(try XCTUnwrap(renderer.tree).hasLayoutAnimation)

    // At t = 0, the animation begins from the open geometry without a jump.
    let atStart = try metrics()
    XCTAssertEqual(atStart.sidebarClip.width, 240, accuracy: 0.01)
    XCTAssertEqual(atStart.stage.width, 460, accuracy: 0.01)

    var previousSidebarWidth = 240.0
    for step in [0.04, 0.10, 0.16] {
      now = 100.0 + step
      XCTAssertTrue(renderer.stepAnimations())
      let m = try metrics()
      XCTAssertLessThan(m.sidebarClip.width, previousSidebarWidth)
      XCTAssertGreaterThan(m.sidebarClip.width, 0)
      // Inner column keeps its full width and leading origin while clipped.
      XCTAssertEqual(m.sidebarInner.minX, 0, accuracy: 0.01)
      XCTAssertEqual(m.sidebarInner.width, 240, accuracy: 0.01)
      // Main stage shares the exact edge with the shrinking sidebar every frame.
      XCTAssertEqual(m.stage.minX, m.sidebarClip.maxX, accuracy: 0.01)
      XCTAssertEqual(m.stage.width, 900 - m.sidebarClip.width - 200, accuracy: 0.01)
      let geometry = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), kind: .geometry))
      let stageContent = try XCTUnwrap(geometry.children.first)
      let stageLabel = try XCTUnwrap(
        allNodes(geometry).first { $0.props.text.hasPrefix("StageWidth:") })
      XCTAssertEqual(stageContent.frame.width, m.stage.width, accuracy: 0.01)
      XCTAssertEqual(stageLabel.props.text, "StageWidth:\(Int(m.stage.width.rounded()))")
      previousSidebarWidth = m.sidebarClip.width
    }

    // Non-linear check: at midpoint (0.10 / 0.20 = 0.5) of cubic-bezier(0.2, 0, 0, 1),
    // more than 80% of the 240pt travel has already completed (< 48pt left).
    now = 100.10
    // Step trailing Aside too so both columns animate simultaneously, checking
    // that Aside's inner content stays pinned to the window's trailing edge.
    let toggleAside = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "ToggleAside"))
    renderer.performTap(toggleAside.id)

    now = 100.15
    XCTAssertTrue(renderer.stepAnimations())
    let midAside = try metrics()
    XCTAssertLessThan(midAside.asideClip.width, 200)
    XCTAssertGreaterThan(midAside.asideClip.width, 0)
    XCTAssertEqual(midAside.asideClip.maxX, 900, accuracy: 0.01)
    // Trailing alignment keeps the 200pt inner panel pinned to x = 700 (900 - 200).
    XCTAssertEqual(midAside.asideInner.minX, 700, accuracy: 0.01)
    XCTAssertEqual(midAside.asideInner.width, 200, accuracy: 0.01)
    XCTAssertEqual(
      midAside.stage.width,
      900 - midAside.sidebarClip.width - midAside.asideClip.width,
      accuracy: 0.01)

    now = 100.35
    XCTAssertFalse(renderer.stepAnimations())
    XCTAssertFalse(renderer.hasActiveAnimations)
    XCTAssertFalse(try XCTUnwrap(renderer.tree).hasLayoutAnimation)
    let settled = try metrics()
    XCTAssertEqual(settled.sidebarClip.width, 0, accuracy: 0.001)
    XCTAssertEqual(settled.asideClip.width, 0, accuracy: 0.001)
    XCTAssertEqual(settled.stage.minX, 0, accuracy: 0.001)
    XCTAssertEqual(settled.stage.width, 900, accuracy: 0.001)
  }

  func testUnrelatedStateWriteKeepsAnimationAliveAndMidFlightToggleReversesSmoothly() throws {
    StateRegistry.shared.reset()
    var now = 200.0
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(ShellFixture()),
      size: Size(width: 900, height: 400))
    renderer.clock = { now }
    renderer.mount()

    func sidebarWidth() throws -> Double {
      try XCTUnwrap(renderer.tree).children[0].frame.width
    }

    let toggleList = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "ToggleList"))
    let hoverButton = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "HoverState"))
    renderer.performTap(toggleList.id)

    now = 200.05
    XCTAssertTrue(renderer.stepAnimations())
    let widthBeforeHover = try sidebarWidth()
    XCTAssertLessThan(widthBeforeHover, 240)
    XCTAssertGreaterThan(widthBeforeHover, 30)

    // Unanimated sibling state update must not snap the in-flight sidebar to 0.
    now = 200.06
    renderer.performTap(hoverButton.id)
    let widthAfterHover = try sidebarWidth()
    XCTAssertLessThan(widthAfterHover, widthBeforeHover)
    XCTAssertGreaterThan(widthAfterHover, 20)
    XCTAssertTrue(renderer.hasActiveAnimations)

    // Reversing mid-flight starts from the current interpolated width, not 0.
    now = 200.08
    XCTAssertTrue(renderer.stepAnimations())
    let reversalOrigin = try sidebarWidth()
    renderer.performTap(toggleList.id)
    XCTAssertEqual(try sidebarWidth(), reversalOrigin, accuracy: 0.01)

    now = 200.14
    XCTAssertTrue(renderer.stepAnimations())
    let reopening = try sidebarWidth()
    XCTAssertGreaterThan(reopening, reversalOrigin)
    XCTAssertLessThan(reopening, 240)

    now = 200.30
    XCTAssertFalse(renderer.stepAnimations())
    XCTAssertEqual(try sidebarWidth(), 240, accuracy: 0.001)
  }

  private struct ResizableAndScopedSidebar: View {
    @State private var width = 220.0
    @State private var scopedWidth = 180.0
    @State private var counter = 0

    var body: some View {
      VStack(spacing: 0) {
        HStack(spacing: 4) {
          Button("AnimatedClose") {
            withAnimation(.easeInOut(duration: 0.2)) { width = 0 }
          }
          Button("DragTo150") { width = 150 }
          Button("ScopedToggle") { scopedWidth = scopedWidth == 0 ? 180 : 0 }
          Button("BumpCounter") { counter += 1 }
        }
        Text("Dragged:\(counter)")
          .frame(width: width, height: 30)
        Text("Scoped:\(counter)")
          .frame(width: scopedWidth, height: 30)
          .animation(.easeOut(duration: 0.2), value: scopedWidth)
      }
    }
  }

  func testUnanimatedDragCancelsMotionAndScopedAnimationTracksObservedValue() throws {
    StateRegistry.shared.reset()
    var now = 300.0
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(ResizableAndScopedSidebar()),
      size: Size(width: 500, height: 200))
    renderer.clock = { now }
    renderer.mount()

    func widths() throws -> (dragged: Double, scoped: Double) {
      let root = try XCTUnwrap(renderer.tree)
      return (root.children[1].frame.width, root.children[2].frame.width)
    }

    let closeBtn = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "AnimatedClose"))
    let dragBtn = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "DragTo150"))
    let scopedBtn = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "ScopedToggle"))
    let bumpBtn = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "BumpCounter"))

    renderer.performTap(closeBtn.id)
    now = 300.08
    XCTAssertTrue(renderer.stepAnimations())
    XCTAssertLessThan(try widths().dragged, 220)
    XCTAssertGreaterThan(try widths().dragged, 0)

    // Unanimated drag resize cancels the active motion immediately with zero lag.
    now = 300.09
    renderer.performTap(dragBtn.id)
    XCTAssertEqual(try widths().dragged, 150, accuracy: 0.001)
    XCTAssertFalse(renderer.hasActiveAnimations)

    // `.animation(_:value:)` animates when `scopedWidth` changes...
    now = 301.0
    renderer.performTap(scopedBtn.id)
    XCTAssertTrue(renderer.hasActiveAnimations)
    XCTAssertEqual(try widths().scoped, 180, accuracy: 0.01)

    now = 301.08
    XCTAssertTrue(renderer.stepAnimations())
    let midScoped = try widths().scoped
    XCTAssertLessThan(midScoped, 180)
    XCTAssertGreaterThan(midScoped, 0)

    // ...and keeps progressing when `counter` changes without `scopedWidth` changing.
    now = 301.10
    renderer.performTap(bumpBtn.id)
    XCTAssertLessThan(try widths().scoped, midScoped)

    now = 301.25
    XCTAssertFalse(renderer.stepAnimations())
    XCTAssertEqual(try widths().scoped, 0, accuracy: 0.001)
  }

  func testWithTransactionDisablesAnimationsSuppressesScopedValueAnimation() throws {
    struct ScopedBox: View {
      @State private var expanded = false
      var body: some View {
        VStack {
          Button("Jump") {
            withTransaction(\.disablesAnimations, true) {
              expanded.toggle()
            }
          }
          Rectangle()
            .frame(width: expanded ? 300 : 120, height: 40)
            .animation(.easeOut(duration: 0.3), value: expanded)
        }
      }
    }

    StateRegistry.shared.reset()
    let now = 500.0
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(ScopedBox()),
      size: Size(width: 400, height: 200))
    renderer.clock = { now }
    renderer.mount()

    let jumpBtn = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Jump"))
    renderer.performTap(jumpBtn.id)
    XCTAssertFalse(renderer.hasActiveAnimations)
    let root = try XCTUnwrap(renderer.tree)
    XCTAssertEqual(root.children[1].frame.width, 300, accuracy: 0.01)
  }
}
