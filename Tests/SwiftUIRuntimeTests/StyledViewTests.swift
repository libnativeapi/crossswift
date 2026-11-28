import XCTest

@testable import SwiftUIRuntime

private struct MarkerKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
  fileprivate var marker: Int {
    get { self[MarkerKey.self] }
    set { self[MarkerKey.self] = newValue }
  }
}
private struct Marker: View {
  @Environment(\.marker) var marker
  var body: some View { Text("marker:\(marker)") }
}
private struct CountingChild: View {
  let name: String
  @State var count = 0
  var body: some View {
    VStack {
      Text("\(name):\(count)")
      Button(name) { count += 1 }
    }
  }
}
private struct CountingParent: View {
  @State var extra = false
  var body: some View {
    VStack {
      CountingChild(name: "first")
      CountingChild(name: "second")
      Button("toggle") { extra.toggle() }
      if extra { CountingChild(name: "temporary") }
    }
  }
}
private struct TestStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.padding(8)
      .background { RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? .red : .blue) }
  }
}
private struct CountingModifier: ViewModifier {
  @Environment(\.marker) var marker
  @State var count = 0
  func body(content: Content) -> some View {
    VStack {
      content
      Button("\(marker):\(count)") { count += 1 }
    }
  }
}
private struct EnabledLabel: View {
  @Environment(\.isEnabled) var enabled
  var body: some View { Text(enabled ? "enabled" : "disabled") }
}

final class StyledViewTests: XCTestCase {
  @MainActor
  func testRepeatedImageAssetLookupsAreScopedToEachRenderPass() async {
    let graph = EvaluationGraph()
    let path = ViewPath()
    var generation = 0
    var queries = 0
    let previous = Image.assetPathResolver
    defer { Image.assetPathResolver = previous }
    Image.assetPathResolver = { name, bundle in
      queries += 1
      return "\(generation)/\(bundle == nil ? "default" : "bundle")/\(name)"
    }
    for pass in 1...2 {
      generation = pass
      _ = graph.evaluateRoot {
        for _ in 0..<32 {
          let first = Image("repeated-symbol")._makeElement(path: path)
          let second = Image("repeated-symbol", bundle: .main)._makeElement(path: path)
          XCTAssertEqual(first.props.imagePath, "\(pass)/default/repeated-symbol")
          XCTAssertEqual(second.props.imagePath, "\(pass)/bundle/repeated-symbol")
        }
        return Element(kind: .empty)
      }
      XCTAssertEqual(queries, pass * 2)
    }
  }

  override func setUp() { StateRegistry.shared.reset() }
  private func render<V: View>(_ view: V) -> Renderer {
    let renderer = Renderer(
      backend: FakeBackend(), root: AnyView(view), size: Size(width: 400, height: 240))
    renderer.mount()
    return renderer
  }
  private func nodes(_ node: Element) -> [Element] { [node] + node.children.flatMap(nodes) }

  func testEnvironmentAndFontAreScopedThroughErasureAndSiblings() {
    let renderer = render(
      VStack {
        AnyView(Marker().environment(\.marker, 7).font(.system(size: 22)))
        Marker()
      }.environment(\.marker, 3).font(.system(size: 11)))
    let texts = nodes(renderer.tree!).filter { $0.kind == .text }
    XCTAssertEqual(texts.map(\.props.text), ["marker:7", "marker:3"])
    XCTAssertEqual(texts.map { $0.props.font?.size }, [22, 11])
    XCTAssertEqual(EnvironmentValues.current.marker, 0)
  }

  func testSiblingStatePersistsIndependentlyAcrossReevaluation() throws {
    let renderer = render(CountingParent())
    let second = try XCTUnwrap(nodes(renderer.tree!).first { $0.props.text == "second" })
    renderer.performTap(second.id)
    renderer.performTap(second.id)
    let texts = nodes(renderer.tree!).map(\.props.text)
    XCTAssertTrue(texts.contains("first:0"))
    XCTAssertTrue(texts.contains("second:2"))
    XCTAssertFalse(
      renderer.lastCommands.contains {
        if case .create = $0 { return true }
        return false
      })
  }

  func testRemovedStateStartsFreshWhenInsertedAgain() throws {
    let renderer = render(CountingParent())
    let toggle = try XCTUnwrap(nodes(renderer.tree!).first { $0.props.text == "toggle" })
    renderer.performTap(toggle.id)
    let temporary = try XCTUnwrap(nodes(renderer.tree!).first { $0.props.text == "temporary" })
    renderer.performTap(temporary.id)
    renderer.performTap(toggle.id)
    renderer.performTap(toggle.id)
    XCTAssertTrue(nodes(renderer.tree!).contains { $0.props.text == "temporary:0" })
  }

  func testStyledButtonPressedStateAndDisabledActivation() throws {
    var count = 0
    let renderer = render(
      HStack {
        Button("enabled") { count += 1 }.buttonStyle(TestStyle())
        Button("disabled") { count += 100 }.buttonStyle(TestStyle()).disabled()
      })
    let buttons = nodes(renderer.tree!).filter { $0.kind == .styledButton }
    XCTAssertEqual(buttons.count, 2)
    renderer.interact(buttons[0].id, .pressed(true))
    XCTAssertTrue(
      nodes(renderer.tree!).contains { $0.kind == .shape && $0.props.background == .red })
    XCTAssertFalse(
      renderer.lastCommands.contains {
        if case .create = $0 { return true }
        return false
      })
    renderer.performTap(buttons[0].id)
    renderer.performTap(buttons[1].id)
    XCTAssertEqual(count, 1)
    renderer.interact(buttons[0].id, .pressed(false))
    XCTAssertFalse(
      nodes(renderer.tree!).contains { $0.kind == .shape && $0.props.background == .red })
  }

  func testFrameDoesNotCollapseModifierOrderOrGrowForOverlay() {
    let renderer = render(
      VStack {
        Text("A").frame(width: 40, height: 30)
          .padding(5).background(.blue)
          .overlay { Rectangle().strokeBorder(.red, lineWidth: 2).padding(-2) }
      })
    let child = renderer.tree!.children[0]
    XCTAssertEqual(child.frame.width, 50)
    XCTAssertEqual(child.frame.height, 40)
    let text = nodes(child).first { $0.kind == .text }!
    XCTAssertEqual(text.frame.width, 8)
    XCTAssertEqual(text.frame.height, 20)
    XCTAssertEqual(text.frame.minX, child.frame.minX + 21)
  }

  func testModifierReadsScopedEnvironmentAndRetainsState() throws {
    let renderer = render(Text("content").modifier(CountingModifier()).environment(\.marker, 9))
    let button = try XCTUnwrap(nodes(renderer.tree!).first { $0.kind == .button })
    XCTAssertEqual(button.props.text, "9:0")
    renderer.performTap(button.id)
    XCTAssertTrue(nodes(renderer.tree!).contains { $0.props.text == "9:1" })
  }

  func testFlexibleDividerFillsPaddedStackWithoutGrowingItsHeight() throws {
    let renderer = render(
      VStack(alignment: .leading, spacing: 0) {
        Text("A")
        Rectangle().fill(.blue).frame(height: 1).frame(maxWidth: .infinity)
      }.padding(10))
    let shape = try XCTUnwrap(nodes(renderer.tree!).first { $0.kind == .shape })
    XCTAssertEqual(shape.frame.width, 380)
    XCTAssertEqual(shape.frame.height, 1)
  }

  func testCustomLayoutUsesChildStackExpansion() throws {
    struct Fill: Layout {
      func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 200, height: 140)
      }
      func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
      ) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
      }
    }
    let renderer = render(
      ScrollView {
        Fill {
          VStack(spacing: 0) {
            Text("Source").frame(height: 40)
            Text("Result").frame(maxHeight: .infinity).background(.blue)
          }
        }
      })
    let result = try XCTUnwrap(nodes(renderer.tree!).first { $0.props.background == .blue })
    XCTAssertEqual(result.frame.height, 100)
  }

  func testUnstyledLabelBuilderUsesNativeTitle() throws {
    let renderer = render(
      Button(action: {}) {
        HStack {
          Text("Save")
          Text("document")
        }
      })
    XCTAssertEqual(renderer.tree?.props.text, "Save document")
  }

  func testDisabledIsVisibleToEnvironmentReadersAndScopedToSubtree() {
    let renderer = render(
      VStack {
        EnabledLabel().disabled()
        EnabledLabel()
      })
    let texts = nodes(renderer.tree!).filter { $0.kind == .text }
    XCTAssertEqual(texts.map(\.props.text), ["disabled", "enabled"])
    XCTAssertEqual(texts.map(\.props.enabled), [false, true])
  }

  func testIntrinsicWrappingCustomLayoutDoesNotSplitRowWithSpacer() throws {
    struct SwatchFlow: Layout {
      let spacing: CGFloat = 6
      private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var result: [[Int]] = [[]]
        var run: CGFloat = 0
        for index in subviews.indices {
          let size = subviews[index].sizeThatFits(.unspecified)
          if run > 0, run + spacing + size.width > width {
            result.append([])
            run = 0
          }
          result[result.count - 1].append(index)
          run += (run > 0 ? spacing : 0) + size.width
        }
        return result.filter { !$0.isEmpty }
      }
      func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = rows(subviews, width: proposal.width ?? .infinity)
        var size = CGSize.zero
        for row in lines {
          let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
          size.width = max(size.width, sizes.reduce(0) { $0 + $1.width } + CGFloat(row.count - 1) * spacing)
          size.height += (sizes.map(\.height).max() ?? 0) + spacing
        }
        size.height = max(0, size.height - spacing)
        return size
      }
      func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
      ) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
          let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
          let width = sizes.reduce(0) { $0 + $1.width } + CGFloat(row.count - 1) * spacing
          var x = bounds.maxX - width
          for (index, size) in zip(row, sizes) {
            subviews[index].place(
              at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
          }
          y += (sizes.map(\.height).max() ?? 0) + spacing
        }
      }
    }

    let wide = Renderer(
      backend: FakeBackend(),
      root: AnyView(
        HStack(spacing: 10) {
          Text("Theme")
          Spacer(minLength: 0)
          HStack(spacing: 10) {
            SwatchFlow {
              ForEach(0..<6, id: \.self) { _ in
                Rectangle().fill(.blue).frame(width: 39, height: 26)
              }
            }
          }
        }.frame(maxWidth: .infinity)),
      size: Size(width: 480, height: 200))
    wide.mount()
    let wideSwatches = nodes(wide.tree!).filter { $0.kind == .shape }
    XCTAssertEqual(wideSwatches.count, 6)
    XCTAssertEqual(Set(wideSwatches.map { Int($0.frame.minY.rounded()) }).count, 1)
    XCTAssertEqual(wideSwatches.last?.frame.maxX ?? 0, 480, accuracy: 0.5)

    let narrow = Renderer(
      backend: FakeBackend(),
      root: AnyView(
        HStack(spacing: 10) {
          Text("Theme")
          Spacer(minLength: 0)
          HStack(spacing: 10) {
            SwatchFlow {
              ForEach(0..<6, id: \.self) { _ in
                Rectangle().fill(.blue).frame(width: 39, height: 26)
              }
            }
          }
        }.frame(maxWidth: .infinity)),
      size: Size(width: 280, height: 200))
    narrow.mount()
    let narrowSwatches = nodes(narrow.tree!).filter { $0.kind == .shape }
    XCTAssertEqual(Set(narrowSwatches.map { Int($0.frame.minY.rounded()) }).count, 2)
    XCTAssertTrue(narrowSwatches.allSatisfy { $0.frame.maxX <= 280.5 })
  }

  func testOverlayForEachPositionsChildrenInSharedLayer() {
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(
        Color.clear
          .frame(width: 200, height: 56)
          .overlay(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
              Image(systemName: "star")
                .font(.system(size: 16))
                .position(CGPoint(x: 120 + Double(index) * 40, y: 28))
            }
          }
      ),
      size: Size(width: 200, height: 56))
    renderer.mount()
    let images = nodes(renderer.tree!).filter { $0.kind == .image }
    XCTAssertEqual(images.count, 2)
    XCTAssertEqual(images[0].frame.minX + images[0].frame.width / 2, 120, accuracy: 0.5)
    XCTAssertEqual(images[0].frame.minY + images[0].frame.height / 2, 28, accuracy: 0.5)
    XCTAssertEqual(images[1].frame.minX + images[1].frame.width / 2, 160, accuracy: 0.5)
    XCTAssertEqual(images[1].frame.minY + images[1].frame.height / 2, 28, accuracy: 0.5)
    XCTAssertEqual(images[0].frame.width, 16, accuracy: 0.5)
    XCTAssertEqual(images[1].frame.height, 16, accuracy: 0.5)
  }

  func testMaskBuildsCompoundClipPathSkippingTransparentShapes() {
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(
        Color.black
          .frame(width: 200, height: 56)
          .mask {
            ZStack(alignment: .topLeading) {
              Capsule().fill(.white).frame(width: 120, height: 56)
              Circle().fill(.white).frame(width: 40, height: 40).position(CGPoint(x: 150, y: 28))
              Circle().fill(.white).frame(width: 40, height: 40).opacity(0).position(CGPoint(x: 190, y: 28))
            }
          }
      ),
      size: Size(width: 200, height: 56))
    renderer.mount()
    let masked = nodes(renderer.tree!).first { $0.clipPathBuilder != nil }
    XCTAssertNotNil(masked)
    let path = masked!.clipPathBuilder!(CGRect(x: 0, y: 0, width: 200, height: 56))
    let closes = path.commands.filter { $0 == 3 }.count
    XCTAssertEqual(closes, 2)
  }
}

extension StyledViewTests {
  func testNativeFocusPeerForwardsCellPointerGestures() throws {
    var selected = false
    var opened = false
    let renderer = render(
      VStack {
        Color.clear.frame(width: 100, height: 80)
          .onTapGesture(count: 2) { opened = true }
          .onTapGesture { selected = true }
      }.focusable())
    let focus = try XCTUnwrap(nodes(renderer.tree!).first { $0.props.focusable })
    let cell = try XCTUnwrap(nodes(renderer.tree!).first { $0.doubleTapAction != nil })
    let point = CGPoint(x: cell.frame.minX + 10, y: cell.frame.minY + 10)
    renderer.input(id: focus.id, event: 2, point: point)
    renderer.input(id: focus.id, event: 3, point: point)
    renderer.input(id: focus.id, event: 4, point: point)
    XCTAssertTrue(selected)
    XCTAssertTrue(opened)
  }
}
