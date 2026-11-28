import XCTest
@_spi(WindowsRendering) @testable import SwiftUIRuntime

final class DeferredViewportTests: XCTestCase {
  private final class Host: RenderBackend, LazyViewportRefreshBackend {
    let supportsDeferredViewport = true
    let needsRenderCommands = false
    var tapHandler: ((NodeID) -> Void)?
    var transactionHandler: ((() -> Void) -> Void)?
    var prepareForDiscreteInput: (() -> Void)?
    var refresh: (() -> Void)?
    var fullPublications = 0
    func perform(_ commands: [RenderCommand]) {}
    func didRender(_ root: Element) { fullPublications += 1 }
    func didScroll(_ root: Element, viewport: Rect) {}
    func refreshViewportAfterPaint(_ work: @escaping () -> Void) { refresh = work }
  }

  private final class Log { var events: [String] = [] }
  private enum Effect: CaseIterable { case shortcut, appearance, preference, geometry }
  private struct RowPreference: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
  }

  private struct Rows: View {
    let effect: Effect
    let log: Log
    @State private var ready = false

    @ViewBuilder private var specialRow: some View {
      switch effect {
      case .shortcut:
        Button("Shortcut") { log.events.append("key") }.keyboardShortcut("z", modifiers: .control)
      case .appearance:
        Text("Appearance").onAppear { publish() }
      case .preference:
        Text("Preference").preference(key: RowPreference.self, value: 28)
          .onPreferenceChange(RowPreference.self) { if $0 == 28 { publish() } }
      case .geometry:
        Text("Geometry").onGeometryChange(for: Int.self, of: { Int($0.size.width) }) {
          if $0 > 0 { publish() }
        }
      }
    }
    private func publish() {
      guard !ready else { return }
      ready = true
      log.events.append("ready")
    }
    var body: some View {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(0..<1000, id: \.self) { index in
            Group {
              if index == 28 { specialRow }
              else if index == 11 { Text(ready ? "Ready" : "Waiting") }
              else { Text("Row \(index)") }
            }.frame(height: 28).clipped()
          }
        }._fixedLazyRows()
      }
    }
  }

  @MainActor func testNewRowsDeliverObservableEffectsOnTheFirstPublication() async throws {
    for effect in [Effect.appearance, .preference, .geometry] {
      let log = Log(), host = Host()
      let renderer = Renderer(backend: host, root: AnyView(Rows(effect: effect, log: log)),
                              size: Size(width: 500, height: 489))
      renderer.mount()
      defer { renderer.unmount() }
      let id = try XCTUnwrap(renderer.tree).id
      XCTAssertTrue(log.events.isEmpty)
      renderer.scroll(id: id, to: Point(x: 0, y: 140))
      func containsReady(_ node: Element) -> Bool {
        node.props.text == "Ready" || node.children.contains(where: containsReady)
      }
      XCTAssertTrue(containsReady(try XCTUnwrap(renderer.tree)), "\(effect)")
      XCTAssertEqual(log.events, ["ready"], "\(effect)")
      XCTAssertNil(host.refresh, "\(effect)")
    }
  }

  @MainActor func testKeyboardUsesPublishedWindowThroughWheelTransactionsAndReversal() async throws {
    let log = Log(), host = Host()
    let renderer = Renderer(backend: host, root: AnyView(Rows(effect: .shortcut, log: log)),
                            size: Size(width: 500, height: 489))
    renderer.mount()
    defer { renderer.unmount() }
    let id = try XCTUnwrap(renderer.tree).id
    func move(_ y: Double) { renderer.scroll(id: id, to: Point(x: 0, y: y)) }
    func key() -> Bool { renderer.input(event: 6, value: 90, modifiers: .control, text: "z") }

    let transaction = try XCTUnwrap(host.transactionHandler)
    transaction {
      move(140)
      XCTAssertFalse(key(), "The wheel is still in the same unpublished transaction")
    }
    XCTAssertTrue(key())
    move(0)
    move(140)
    XCTAssertNotNil(host.refresh)
    transaction {
      move(0)
      XCTAssertTrue(key(), "The previously published window contains the shortcut")
    }
    XCTAssertEqual(log.events, ["key", "key"])
  }

  @MainActor func testOldRefreshCannotPublishAfterRemount() async throws {
    let host = Host()
    let renderer = Renderer(backend: host, root: AnyView(Rows(effect: .shortcut, log: Log())),
                            size: Size(width: 500, height: 489))
    renderer.mount()
    renderer.scroll(id: try XCTUnwrap(renderer.tree).id, to: Point(x: 0, y: 140))
    let stale = try XCTUnwrap(host.refresh)
    renderer.unmount()
    renderer.mount()
    defer { renderer.unmount() }
    let count = host.fullPublications
    stale()
    XCTAssertEqual(host.fullPublications, count)
  }
}
