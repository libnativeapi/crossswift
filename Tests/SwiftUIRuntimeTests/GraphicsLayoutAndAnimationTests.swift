import Foundation
import XCTest
@testable import SwiftUIRuntime

private struct TestGradientsView: View {
  var body: some View {
    VStack(spacing: 8) {
      RadialGradient(
        stops: [
          Gradient.Stop(color: .red, location: 0.0),
          Gradient.Stop(color: .yellow, location: 0.3),
          Gradient.Stop(color: .blue, location: 1.0),
        ],
        center: .center,
        startRadius: 10,
        endRadius: 80
      )
      .frame(width: 120, height: 120)

      AngularGradient(
        colors: [.green, .purple, .green],
        center: .center,
        startAngle: .degrees(45),
        endAngle: .degrees(315)
      )
      .frame(width: 120, height: 120)
    }
  }
}

private struct TestRichCanvasView: View {
  var body: some View {
    Canvas { ctx, size in
      var rect = Path()
      rect.addRect(CGRect(x: 10, y: 10, width: 40, height: 20))
      ctx.opacity = 0.8
      ctx.rotate(by: .degrees(90))
      ctx.stroke(rect, with: .color(.red), style: StrokeStyle(lineWidth: 3, dash: [4, 2]))
      ctx.fill(
        rect,
        with: .radialGradient(
          Gradient(colors: [.white, .black]),
          center: CGPoint(x: 20, y: 20),
          startRadius: 2,
          endRadius: 20
        )
      )
      ctx.draw(Text("CanvasLabel"), at: CGPoint(x: 30, y: 30))
      ctx.drawLayer { layer in
        var line = Path()
        line.move(to: CGPoint(x: 0, y: 0))
        line.addLine(to: CGPoint(x: size.width, y: size.height))
        layer.stroke(line, with: .color(.blue), lineWidth: 2)
      }
    }
    .frame(width: 200, height: 160)
  }
}

private struct TestFiltersView: View {
  var body: some View {
    VStack {
      Text("Filtered")
        .blur(radius: 6)
        .brightness(0.25)
        .contrast(1.4)
        .compositingGroup()
    }
  }
}

private struct TestTransitionView: View {
  @State private var shown = false

  var body: some View {
    VStack(spacing: 8) {
      Button("Toggle") {
        withAnimation(.linear(duration: 0.4)) {
          shown.toggle()
        }
      }
      if shown {
        Text("Banner")
          .id("banner")
          .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
      }
    }
  }
}

private struct TestColorAnimationView: View {
  @State private var active = false

  var body: some View {
    VStack(spacing: 8) {
      Button("Flip") {
        withAnimation(.linear(duration: 0.4)) {
          active.toggle()
        }
      }
      Text("Card")
        .background(active ? Color(red: 0, green: 0, blue: 1, opacity: 1) : Color(red: 1, green: 0, blue: 0, opacity: 1))
    }
  }
}

private struct TestLongPressView: View {
  let onPressing: (Bool) -> Void
  let onLongPress: () -> Void
  let onTap: () -> Void

  var body: some View {
    Text("HoldMe")
      .frame(width: 120, height: 40)
      .onTapGesture { onTap() }
      .gesture(
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 12)
          .onChanged { onPressing($0) }
          .onEnded { _ in onLongPress() }
      )
  }
}

private struct TestGestureArbitrationView: View {
  let onParentHigh: () -> Void
  let onChildRegular: () -> Void
  let onSimultaneous: () -> Void

  var body: some View {
    VStack {
      Text("Target")
        .frame(width: 100, height: 40)
        .onTapGesture { onChildRegular() }
        .simultaneousGesture(TapGesture().onEnded { onSimultaneous() })
    }
    .frame(width: 120, height: 60)
    .highPriorityGesture(TapGesture().onEnded { onParentHigh() })
  }
}

private struct TestLayoutFidelityView: View {
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Text("Left")
        Spacer(minLength: 30)
        Text("Right")
      }
      .frame(width: 100, height: 20)

      HStack(spacing: 0) {
        Text("01234567890123456789") // 20 chars = 160pt natural
          .layoutPriority(1)
        Text("ABCDEFGHIJABCDEFGHIJ") // 20 chars = 160pt natural
          .layoutPriority(0)
      }
      .frame(width: 200, height: 20)
    }
  }
}

private struct TestLazyContainersView: View {
  let count: Int
  let mode: Int

  var body: some View {
    if mode == 0 {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 4) {
          ForEach(0..<count, id: \.self) { idx in
            Text(verbatim: "H\(idx)").frame(width: 60, height: 40)
          }
        }
      }
    } else if mode == 1 {
      ScrollView(.vertical) {
        LazyVGrid(columns: [GridItem(.fixed(80)), GridItem(.fixed(80))], spacing: 4) {
          ForEach(0..<count, id: \.self) { idx in
            Text(verbatim: "VG\(idx)").frame(width: 80, height: 40)
          }
        }
      }
    } else {
      ScrollView(.horizontal) {
        LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 4) {
          ForEach(0..<count, id: \.self) { idx in
            Text(verbatim: "HG\(idx)").frame(width: 60, height: 40)
          }
        }
      }
    }
  }
}

private final class Phase4TestBackend: RenderBackend {
  var tapHandler: ((NodeID) -> Void)?
  var transactionHandler: ((() -> Void) -> Void)?
  func perform(_ commands: [RenderCommand]) {}
}

private func collectElements(
  in node: Element, where predicate: (Element) -> Bool, into out: inout [Element]
) {
  if predicate(node) { out.append(node) }
  for child in node.children {
    collectElements(in: child, where: predicate, into: &out)
  }
}

@MainActor
final class GraphicsLayoutAndAnimationTests: XCTestCase {
  func testRadialAndAngularGradientEmitTrueGradientKindsAndStops() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    let renderer = Renderer(
      backend: backend, root: AnyView(TestGradientsView()), size: Size(width: 300, height: 300))
    renderer.mount()

    let tree = try XCTUnwrap(renderer.tree)
    var gradients: [Element] = []
    collectElements(in: tree, where: { $0.kind == .gradient }, into: &gradients)
    XCTAssertEqual(gradients.count, 2)

    let radial = try XCTUnwrap(gradients[0].props.gradient)
    XCTAssertEqual(radial.kind, .radial)
    XCTAssertEqual(radial.locations, [0.0, 0.3, 1.0])
    XCTAssertEqual(radial.startRadius, 10)
    XCTAssertEqual(radial.endRadius, 80)

    let angular = try XCTUnwrap(gradients[1].props.gradient)
    XCTAssertEqual(angular.kind, .angular)
    XCTAssertEqual(angular.startAngle, 45)
    XCTAssertEqual(angular.endAngle, 315)
  }

  func testRichCanvasSupportsStrokeRotateOpacityGradientsTextAndDrawLayer() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    let renderer = Renderer(
      backend: backend, root: AnyView(TestRichCanvasView()), size: Size(width: 240, height: 200))
    renderer.mount()

    let tree = try XCTUnwrap(renderer.tree)
    var paths: [Element] = []
    collectElements(in: tree, where: { $0.kind == .path }, into: &paths)
    XCTAssertGreaterThanOrEqual(paths.count, 2)
    XCTAssertTrue(paths.contains { $0.props.borderWidth == 3 && $0.props.dash == [4, 2] })

    var grads: [Element] = []
    collectElements(in: tree, where: { $0.kind == .gradient }, into: &grads)
    XCTAssertEqual(grads.count, 1)
    XCTAssertEqual(grads[0].props.gradient?.kind, .radial)
    XCTAssertNotNil(grads[0].clipPathBuilder)

    var texts: [Element] = []
    collectElements(in: tree, where: { $0.kind == .text && $0.props.text == "CanvasLabel" }, into: &texts)
    XCTAssertEqual(texts.count, 1)
  }

  func testBlurBrightnessContrastAndCompositingGroupPreserveProps() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    let renderer = Renderer(
      backend: backend, root: AnyView(TestFiltersView()), size: Size(width: 200, height: 100))
    renderer.mount()

    let tree = try XCTUnwrap(renderer.tree)
    let textNode = try XCTUnwrap(findNode(in: tree, text: "Filtered"))
    XCTAssertEqual(textNode.props.blurRadius, 6, accuracy: 0.001)
    XCTAssertEqual(textNode.props.brightness, 0.25, accuracy: 0.001)
    XCTAssertEqual(textNode.props.contrast, 1.4, accuracy: 0.001)
    XCTAssertTrue(textNode.props.compositingGroup)
    XCTAssertEqual(textNode.props.opacity, 1.0, accuracy: 0.001)
  }

  func testMultiSegmentPathTrimmedPathSubdividesLinesAndCurves() async {
    var rect = Path()
    rect.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
    // Perimeter = 400. Trimming [0.25, 0.75] starts at (100, 0), goes to (100, 100), then (0, 100).
    let half = rect.trimmedPath(from: 0.25, to: 0.75)
    XCTAssertFalse(half.commands.isEmpty)
    // First command is move(to: (100, 0))
    XCTAssertEqual(half.commands[0], 0)
    XCTAssertEqual(half.commands[1], 100, accuracy: 0.01)
    XCTAssertEqual(half.commands[2], 0, accuracy: 0.01)

    // Cubic curve trim produces valid subdivided cubic commands.
    var curve = Path()
    curve.move(to: CGPoint(x: 0, y: 0))
    curve.addCurve(to: CGPoint(x: 100, y: 0), control1: CGPoint(x: 33, y: 50), control2: CGPoint(x: 66, y: 50))
    let partialCurve = curve.trimmedPath(from: 0.2, to: 0.8)
    XCTAssertTrue(partialCurve.commands.contains(2)) // cubic command op == 2
    XCTAssertEqual(partialCurve.commands[0], 0)
    XCTAssertGreaterThan(partialCurve.commands[1], 5)
    XCTAssertLessThan(partialCurve.commands[1], 40)
  }

  func testTransitionAnimatesInsertionAndRemovalAcrossFrames() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    var now = 100.0
    let renderer = Renderer(
      backend: backend, root: AnyView(TestTransitionView()), size: Size(width: 240, height: 160))
    renderer.clock = { now }
    renderer.mount()

    let toggleID = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Toggle")?.id)
    XCTAssertNil(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))

    // Insert with animation
    renderer.performTap(toggleID)
    XCTAssertTrue(renderer.hasActiveAnimations)
    let insertedStart = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))
    XCTAssertLessThan(insertedStart.props.opacity, 0.1)

    now = 100.2
    XCTAssertTrue(renderer.stepAnimations())
    let insertedMid = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))
    XCTAssertEqual(insertedMid.props.opacity, 0.5, accuracy: 0.05)

    now = 100.45
    XCTAssertFalse(renderer.stepAnimations())
    let insertedEnd = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))
    XCTAssertEqual(insertedEnd.props.opacity, 1.0, accuracy: 0.01)

    // Remove with animation: ghost stays alive during transition then disappears
    let toggleID2 = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Toggle")?.id)
    renderer.performTap(toggleID2)
    XCTAssertTrue(renderer.hasActiveAnimations)

    now = 100.65
    XCTAssertTrue(renderer.stepAnimations())
    let removingMid = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))
    XCTAssertEqual(removingMid.props.opacity, 0.5, accuracy: 0.08)
    XCTAssertGreaterThan(removingMid.props.offsetX, 1.0)
    XCTAssertFalse(removingMid.props.hitTesting)

    now = 100.90
    XCTAssertFalse(renderer.stepAnimations())
    XCTAssertNil(findNode(in: try XCTUnwrap(renderer.tree), text: "Banner"))
  }

  func testColorAnimationInterpolatesBackgroundAcrossFrames() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    var now = 200.0
    let renderer = Renderer(
      backend: backend, root: AnyView(TestColorAnimationView()), size: Size(width: 240, height: 120))
    renderer.clock = { now }
    renderer.mount()

    let flipID = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Flip")?.id)
    renderer.performTap(flipID)
    XCTAssertTrue(renderer.hasActiveAnimations)

    now = 200.2
    XCTAssertTrue(renderer.stepAnimations())
    let cardMid = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Card"))
    let bgMid = try XCTUnwrap(cardMid.props.background)
    XCTAssertEqual(bgMid.red, 0.5, accuracy: 0.06)
    XCTAssertEqual(bgMid.blue, 0.5, accuracy: 0.06)

    now = 200.45
    XCTAssertFalse(renderer.stepAnimations())
    let cardEnd = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Card"))
    let bgEnd = try XCTUnwrap(cardEnd.props.background)
    XCTAssertEqual(bgEnd.red, 0.0, accuracy: 0.01)
    XCTAssertEqual(bgEnd.blue, 1.0, accuracy: 0.01)
  }

  func testTimedLongPressGestureFiresAfterDurationAndCancelsOnMove() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    var now = 10.0
    var pressingStates: [Bool] = []
    var longPressCount = 0
    var tapCount = 0
    let renderer = Renderer(
      backend: backend,
      root: AnyView(
        TestLongPressView(
          onPressing: { pressingStates.append($0) },
          onLongPress: { longPressCount += 1 },
          onTap: { tapCount += 1 }
        )
      ),
      size: Size(width: 200, height: 100)
    )
    renderer.clock = { now }
    renderer.mount()

    let target = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "HoldMe"))
    let center = CGPoint(x: target.frame.minX + 10, y: target.frame.minY + 10)

    // Move beyond maximumDistance (12) cancels long press
    renderer.input(event: 2, point: center)
    XCTAssertEqual(pressingStates, [true])
    renderer.input(event: 1, point: CGPoint(x: center.x + 30, y: center.y))
    XCTAssertEqual(pressingStates, [true, false])
    now = 11.0
    XCTAssertFalse(renderer.checkLongPressTimeout())
    XCTAssertEqual(longPressCount, 0)
    renderer.input(event: 3, point: CGPoint(x: center.x + 30, y: center.y))

    // Hold past minimumDuration (0.5s) fires long press and suppresses tap
    now = 20.0
    tapCount = 0
    renderer.input(event: 2, point: center)
    now = 20.2
    XCTAssertFalse(renderer.checkLongPressTimeout())
    now = 20.6
    XCTAssertTrue(renderer.checkLongPressTimeout())
    XCTAssertEqual(longPressCount, 1)
    renderer.input(event: 3, point: center)
    XCTAssertEqual(tapCount, 0)
  }

  func testHighPriorityAndSimultaneousGestureArbitration() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    var parentHigh = 0
    var childRegular = 0
    var simultaneous = 0
    let renderer = Renderer(
      backend: backend,
      root: AnyView(
        TestGestureArbitrationView(
          onParentHigh: { parentHigh += 1 },
          onChildRegular: { childRegular += 1 },
          onSimultaneous: { simultaneous += 1 }
        )
      ),
      size: Size(width: 200, height: 120)
    )
    renderer.mount()

    let target = try XCTUnwrap(findNode(in: try XCTUnwrap(renderer.tree), text: "Target"))
    let pt = CGPoint(x: target.frame.minX + 10, y: target.frame.minY + 10)
    renderer.input(event: 2, point: pt)
    renderer.input(event: 3, point: pt)

    XCTAssertEqual(parentHigh, 1, "Outer highPriorityGesture must win over inner regular tap")
    XCTAssertEqual(childRegular, 0, "Inner regular tap must yield to ancestor highPriorityGesture")
    XCTAssertEqual(simultaneous, 1, "simultaneousGesture must fire alongside winning gesture")
  }

  func testSpacerMinLengthAndLayoutPrioritySpaceAllocation() async throws {
    StateRegistry.shared.reset()
    let backend = Phase4TestBackend()
    let renderer = Renderer(
      backend: backend, root: AnyView(TestLayoutFidelityView()), size: Size(width: 240, height: 80))
    renderer.mount()

    let tree = try XCTUnwrap(renderer.tree)
    let left = try XCTUnwrap(findNode(in: tree, text: "Left"))
    let right = try XCTUnwrap(findNode(in: tree, text: "Right"))
    // Left (32pt) + Right (40pt) = 72pt in 100pt box => only 28pt leftover,
    // but Spacer(minLength: 30) must guarantee >= 30pt gap!
    XCTAssertGreaterThanOrEqual(right.frame.minX - left.frame.maxX, 29.9)

    let highPrio = try XCTUnwrap(findNode(in: tree, text: "01234567890123456789"))
    let lowPrio = try XCTUnwrap(findNode(in: tree, text: "ABCDEFGHIJABCDEFGHIJ"))
    // In a 200pt HStack, priority 1 text gets its full 160pt ideal width first, leaving 40pt for priority 0.
    XCTAssertEqual(highPrio.frame.width, 160, accuracy: 1.0)
    XCTAssertEqual(lowPrio.frame.width, 40, accuracy: 1.0)
  }

  func testLazyHStackLazyVGridAndLazyHGridVirtualizeLargeCollections() async throws {
    for mode in 0...2 {
      StateRegistry.shared.reset()
      let backend = Phase4TestBackend()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(TestLazyContainersView(count: 200, mode: mode)),
        size: Size(width: 400, height: 300)
      )
      renderer.mount()

      let tree = try XCTUnwrap(renderer.tree)
      var materializedTexts: [Element] = []
      collectElements(in: tree, where: { $0.kind == .text }, into: &materializedTexts)
      XCTAssertGreaterThan(materializedTexts.count, 0, "Mode \(mode) should materialize visible items")
      XCTAssertLessThan(
        materializedTexts.count, 120,
        "Mode \(mode) should virtualize off-screen items out of 200")
    }
  }
}
