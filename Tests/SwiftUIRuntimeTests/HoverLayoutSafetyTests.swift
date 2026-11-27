import Observation
import XCTest
@testable import SwiftUIRuntime

final class HoverLayoutSafetyTests: XCTestCase {
  @Observable fileprivate final class Model { var count = 0 }
  private struct ModelHover: View {
    let model: Model
    @State private var hot = false
    var body: some View {
      Button("model \(model.count)") {}.background(hot ? Color.red : .blue)
        .onHover { inside in
          hot = inside
          if inside { model.count += 1 }
        }
    }
  }
  func testHoverThatMutatesObservedModelInstallsNewContentAndRunsLayout() throws {
    StateRegistry.shared.reset()
    let model = Model()
    let renderer = Renderer(backend: HoverLayoutTests.Backend(), root: AnyView(ModelHover(model: model)),
                            size: Size(width: 200, height: 100))
    renderer.mount()
    let target = try XCTUnwrap(findNode(in: renderer.tree!, text: "model 0"))
    renderer.interact(target.id, .hover(true))
    XCTAssertEqual(model.count, 1)
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "model 1"))
    XCTAssertNotNil(renderer.lastTimings["layout"])
  }

  private struct EnvironmentLabel: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Text(scheme == .dark ? "dark" : "light") }
  }
  private struct EnvironmentHover: View {
    @State private var hot = false
    var body: some View {
      EnvironmentLabel().environment(\.colorScheme, hot ? .dark : .light).onHover { hot = $0 }
    }
  }
  func testHoverThatChangesDescendantEnvironmentResolvesNewText() throws {
    StateRegistry.shared.reset()
    let renderer = Renderer(backend: HoverLayoutTests.Backend(), root: AnyView(EnvironmentHover()),
                            size: Size(width: 200, height: 100))
    renderer.mount()
    let target = try XCTUnwrap(findNode(in: renderer.tree!, text: "light"))
    renderer.interact(target.id, .hover(true))
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "dark"))
    XCTAssertNotNil(renderer.lastTimings["layout"])
  }

  private struct GeometryMotion: View {
    @State private var hot = false
    var body: some View {
      HStack {
        Text("sibling")
        Text("moving").frame(width: hot ? 120 : 40)
          .background(hot ? Color.blue : .red)
          .onHover { inside in withAnimation(.linear(duration: 1)) { hot = inside } }
      }
    }
  }
  func testMixedColorAndGeometryMotionKeepsPhysicalInterpolation() throws {
    StateRegistry.shared.reset()
    var now = 100.0
    let renderer = Renderer(backend: HoverLayoutTests.Backend(), root: AnyView(GeometryMotion()),
                            size: Size(width: 300, height: 100))
    renderer.clock = { now }
    renderer.mount()
    let target = try XCTUnwrap(findNode(in: renderer.tree!, text: "moving"))
    renderer.interact(target.id, .hover(true))
    XCTAssertNil(renderer.lastTimings["hover.reuse"])
    XCTAssertTrue(renderer.hasActiveAnimations)
    now += 0.5
    XCTAssertTrue(renderer.stepAnimations())
    let midpoint = try XCTUnwrap(allNodes(renderer.tree!).first { $0.props.frameWidth != nil })
    XCTAssertEqual(try XCTUnwrap(midpoint.props.frameWidth), 80, accuracy: 0.01)
    XCTAssertNotNil(renderer.lastTimings["layout"])
    now += 0.51
    XCTAssertFalse(renderer.stepAnimations())
    let end = try XCTUnwrap(allNodes(renderer.tree!).first { $0.props.frameWidth != nil })
    XCTAssertEqual(try XCTUnwrap(end.props.frameWidth), 120, accuracy: 0.01)
  }
}
