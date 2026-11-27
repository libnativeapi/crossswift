import XCTest
@testable import SwiftUIRuntime

private struct HoverPreference: PreferenceKey {
  static let defaultValue = false
  static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

final class HoverLayoutTests: XCTestCase {
  final class Backend: HoverLayoutBackend {
    var tapHandler: ((NodeID) -> Void)?
    var needsRenderCommands: Bool { false }
    var full = 0
    var colorHover = 0
    var scrolled = false
    var transactionHandler: ((() -> Void) -> Void)?
    func perform(_ commands: [RenderCommand]) {}
    func didRender(_ root: Element) { full += 1 }
    func didUpdateHoverColors(_ root: Element, changes: [(id: NodeID, props: NodeProps)], scrolled: Bool) {
      colorHover += 1
      self.scrolled = scrolled
    }
  }
  private enum Effect: CaseIterable {
    case color, size, text, accessibility, preference, geometry, shape, subtree
  }
  private struct Probe: View {
    let effect: Effect
    let perform: (Bool) -> Void
    @State private var hot = false
    var body: some View {
      let captured = hot
      let button = Button(effect == .text && hot ? "entered" : "row") { perform(captured) }
        .background(hot ? Color.blue : .red)
        .frame(width: 100, height: hot && effect == .size ? 90 : 40)
        .accessibilityLabel(hot && effect == .accessibility ? "updated label" : "label")
        .onHover { hot = $0 }
      switch effect {
      case .geometry:
        HStack { button; GeometryReader { proxy in Text(String(Int(proxy.size.width))) } }
      case .preference:
        button.preference(key: HoverPreference.self, value: hot)
          .onPreferenceChange(HoverPreference.self, perform: perform)
      case .subtree:
        VStack { button; if hot { Text("new subtree") } }
      case .shape:
        button.clipShape(Circle())
      default: button.clipShape(RoundedRectangle(cornerRadius: 4))
      }
    }
  }
  func testColorOnlyHoverRetainsNewCallbacksWithoutRecreatingButtons() throws {
    StateRegistry.shared.reset()
    let backend = Backend()
    var seen = [Bool]()
    let renderer = Renderer(backend: backend, root: AnyView(Probe(effect: .color) { seen.append($0) }),
                            size: Size(width: 160, height: 120))
    renderer.mount()
    let old = try XCTUnwrap(findNode(in: renderer.tree!, text: "row"))
    renderer.interact(old.id, .hover(true))
    XCTAssertEqual(backend.colorHover, 1)
    XCTAssertEqual(backend.full, 1)
    let new = try XCTUnwrap(findNode(in: renderer.tree!, text: "row"))
    XCTAssertEqual(new.frame, old.frame)
    XCTAssertEqual(new.id, old.id)
    renderer.performTap(new.id)
    renderer.interact(new.id, .hover(false))
    renderer.performTap(new.id)
    XCTAssertEqual(seen, [true, false])
  }

  func testOpaqueLayoutSemanticsAndNoncolorEffectsUseCompletePass() throws {
    for mode in Effect.allCases where mode != .color {
      StateRegistry.shared.reset()
      let backend = Backend()
      var values = [Bool]()
      let renderer = Renderer(backend: backend,
        root: AnyView(Probe(effect: mode) { values.append($0) }), size: Size(width: 200, height: 120))
      renderer.mount()
      let old = try XCTUnwrap(findNode(in: renderer.tree!, text: "row"))
      let before = backend.full
      renderer.interact(old.id, .hover(true))
      XCTAssertGreaterThan(backend.full, before, "\(mode)")
      XCTAssertEqual(backend.colorHover, 0, "\(mode)")
      let nodes = allNodes(try XCTUnwrap(renderer.tree))
      switch mode {
      case .text: XCTAssertTrue(nodes.contains { $0.props.text == "entered" })
      case .size: XCTAssertTrue(nodes.contains { $0.frame.height == 90 })
      case .preference: XCTAssertEqual(values.last, true)
      case .accessibility: XCTAssertTrue(nodes.contains { $0.props.accessibilityLabel == "updated label" })
      case .subtree: XCTAssertTrue(nodes.contains { $0.props.text == "new subtree" })
      default: break
      }
      renderer.unmount()
    }
  }

  private struct ScrollRows: View {
    var body: some View {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(0..<120) { index in ColorRow(text: "row-\(index)") }
        }
      }
    }
  }
  private struct ColorRow: View {
    let text: String
    @State private var hot = false
    var body: some View {
      Text(text).frame(height: 30).frame(maxWidth: .infinity)
        .background(hot ? Color.red : .clear).onHover { hot = $0 }
    }
  }
  func testBatchedColorAndScrollMatchesForcedLayoutForEveryNode() throws {
    StateRegistry.shared.reset()
    let backend = Backend()
    let renderer = Renderer(backend: backend, root: AnyView(ScrollRows()), size: Size(width: 100, height: 100))
    renderer.mount()
    let point = CGPoint(x: 50, y: 25)
    renderer.input(event: 1, point: point)
    backend.transactionHandler? {
      renderer.input(event: 5, point: point, value: -120)
      renderer.input(event: 1, point: point)
    }
    XCTAssertTrue(backend.scrolled)
    let actual = allNodes(try XCTUnwrap(renderer.tree))
    renderer.setNeedsRender()
    let control = allNodes(try XCTUnwrap(renderer.tree))
    XCTAssertEqual(actual.map(\.id), control.map(\.id))
    XCTAssertEqual(actual.map(\.frame), control.map(\.frame))
    XCTAssertEqual(actual.map(\.props), control.map(\.props))
  }
}
