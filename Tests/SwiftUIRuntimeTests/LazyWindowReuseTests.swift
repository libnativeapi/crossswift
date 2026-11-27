import XCTest
@_spi(WindowsRendering) @testable import SwiftUIRuntime

/// Rows of a lazy stack change index when its window moves. Retained rows are
/// matched by ID, and the result must equal a complete rebuild.
final class LazyWindowReuseTests: XCTestCase {
  private final class Host: RenderBackend, LazyViewportRefreshBackend {
    let supportsDeferredViewport = true
    let needsRenderCommands = false
    var tapHandler: ((NodeID) -> Void)?
    var transactionHandler: ((() -> Void) -> Void)?
    var prepareForDiscreteInput: (() -> Void)?
    var refresh: (() -> Void)?
    func perform(_ commands: [RenderCommand]) {}
    func refreshViewportAfterPaint(_ work: @escaping () -> Void) { refresh = work }
  }

  private struct Row: View {
    let index: Int
    let selected: Bool
    var body: some View {
      HStack(spacing: 4) {
        if index % 5 == 0 { Image(systemName: "folder").frame(width: 16, height: 16) }
        Text("Row \(index)").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        if index % 3 == 0 { Text("\(index) KB").foregroundStyle(Color.gray) }
      }
      .padding(.leading, CGFloat(index % 4) * 16)
      .frame(height: 28)
      .background(selected ? Color.blue : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .opacity(index % 7 == 0 ? 0.5 : 1)
    }
  }

  private struct Rows: View {
    var body: some View {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<2000, id: \.self) { index in Row(index: index, selected: index == 40) }
        }
        ._fixedLazyRows()
      }
      .foregroundStyle(Color.red)
    }
  }

  private func rows(_ root: Element) -> [String: NodeID] {
    var result: [String: NodeID] = [:]
    func visit(_ node: Element) {
      let text = node.props.text
      if text.hasPrefix("Row ") { result[text] = node.id }
      node.children.forEach(visit)
    }
    visit(root)
    return result
  }

  @MainActor func testShiftedWindowMatchesCompleteRebuildAndKeepsRowIdentity() throws {
    StateRegistry.shared.reset()
    let host = Host()
    let renderer = Renderer(backend: host, root: AnyView(Rows()), size: Size(width: 400, height: 300))
    renderer.mount()
    defer { renderer.unmount() }
    // The first pass seeds row heights; compare windows built from measurements.
    renderer.setNeedsRender()
    let scrollID = try XCTUnwrap(renderer.tree).id
    var offset = 0.0
    for step in 0..<40 {
      offset += step < 25 ? 70 : -95
      let before = rows(try XCTUnwrap(renderer.tree))
      renderer.scroll(id: scrollID, to: Point(x: 0, y: offset))
      if let refresh = host.refresh {
        host.refresh = nil
        refresh()
      }
      let actual = allNodes(try XCTUnwrap(renderer.tree))
      for (text, id) in rows(try XCTUnwrap(renderer.tree)) {
        if let old = before[text] { XCTAssertEqual(old, id, "step \(step): \(text) changed identity") }
      }
      renderer.setNeedsRender()
      let control = allNodes(try XCTUnwrap(renderer.tree))
      XCTAssertEqual(actual.map(\.id), control.map(\.id), "step \(step)")
      XCTAssertEqual(actual.map(\.frame), control.map(\.frame), "step \(step)")
      XCTAssertEqual(actual.map(\.props), control.map(\.props), "step \(step)")
    }
  }
}
